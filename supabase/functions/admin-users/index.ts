import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:cors});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 let createdId:string|undefined;
 try{
  const b=await req.json();
  let bootstrap=false;
  if(b.action==='bootstrap'){
   if(typeof b.token!=='string'||b.token.length<40)return reply({error:'დაყენების კოდი არასწორია'},403);
   const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(b.token)))).map(v=>v.toString(16).padStart(2,'0')).join('');
   const {data,error}=await db.rpc('claim_portal_setup',{p_hash:hash});
   if(error||!data)return reply({error:'დაყენება უკვე დასრულებულია ან კოდი არასწორია'},403);
   bootstrap=true;
  }else{
   const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');
   if(!token)return reply({error:'ავტორიზაცია აუცილებელია'},401);
   const {data:{user},error}=await db.auth.getUser(token);
   if(error||!user)return reply({error:'სესია ამოიწურა'},401);
   const {data:me}=await db.from('profiles').select('role,active').eq('id',user.id).single();
   if(!me?.active||me.role!=='admin')return reply({error:'მხოლოდ ადმინისთვის'},403);
   if(b.id===user.id&&(b.active===false||(b.role&&b.role!=='admin')))return reply({error:'საკუთარ ადმინის ანგარიშს ვერ გათიშავთ'},400);
  }
  if(!['create','update','bootstrap'].includes(b.action))return reply({error:'უცნობი მოქმედება'},400);
  if(typeof b.display_name!=='string'||!b.display_name.trim()||b.display_name.length>120)throw new Error('მიუთითეთ სახელი');
  const role=bootstrap?'admin':b.role;
  if(!['admin','supervisor','executor','branch'].includes(role))throw new Error('როლი არასწორია');
  const branchId=role==='branch'?b.branch_id:null;
  if(role==='branch'&&!branchId)throw new Error('აირჩიეთ ფილიალი');
  if(branchId){const {data}=await db.from('branches').select('id').eq('id',branchId).eq('active',true).single();if(!data)throw new Error('ფილიალი არააქტიურია');}
  const scope=role==='supervisor'&&Array.isArray(b.branch_ids)?[...new Set(b.branch_ids)].filter(x=>typeof x==='string'):[];
  if(scope.length){const {data,error}=await db.from('branches').select('id').in('id',scope);if(error||data?.length!==scope.length)throw new Error('ფილიალების სია არასწორია');}
  if(b.action==='create'||bootstrap){
   const username=String(b.username||'').trim().toLowerCase();
   if(!/^[a-z0-9][a-z0-9._-]{2,39}$/.test(username))throw new Error('მომხმარებლის სახელი: 3–40 ლათინური ასო, ციფრი, წერტილი, ტირე ან ქვედა ტირე');
   if(typeof b.password!=='string'||b.password.length<6)throw new Error('პაროლი უნდა შეიცავდეს მინიმუმ 6 სიმბოლოს');
   const {data,error}=await db.auth.admin.createUser({email:username+'@branch-portal.internal.invalid',password:b.password,email_confirm:true});
   if(error)throw new Error('ანგარიშის შექმნა ვერ მოხერხდა; გადაამოწმეთ მომხმარებლის სახელის უნიკალურობა');
   createdId=data.user.id;
   const {error:pe}=await db.from('profiles').insert({id:createdId,username,display_name:b.display_name.trim(),role,branch_id:branchId,must_change_password:true});
   if(pe)throw new Error(pe.code==='23505'?'ეს მომხმარებელი ან ფილიალის ანგარიში უკვე არსებობს':pe.message);
   if(scope.length){const {error}=await db.from('supervisor_branches').insert(scope.map(branch_id=>({supervisor_id:createdId,branch_id})));if(error)throw error;}
   return reply({id:createdId});
  }
  if(typeof b.id!=='string')throw new Error('მომხმარებელი არასწორია');
  const {data:old}=await db.from('profiles').select('*').eq('id',b.id).single();
  if(!old)throw new Error('მომხმარებელი ვერ მოიძებნა');
  if(old.role==='executor'&&(role!=='executor'||b.active===false)){
   const {count}=await db.from('issues').select('id',{count:'exact',head:true}).eq('assigned_to',b.id).is('deleted_at',null).not('status','in','(completed,recorded)');
   if(count)throw new Error('ჯერ გადაანაწილეთ მომხმარებლის მიმდინარე დავალებები');
  }
  if(b.password){if(b.password.length<6)throw new Error('პაროლი: მინიმუმ 6 სიმბოლო');const {error}=await db.auth.admin.updateUserById(b.id,{password:b.password});if(error)throw error;}
  const {error}=await db.from('profiles').update({display_name:b.display_name.trim(),role,branch_id:branchId,active:b.active!==false}).eq('id',b.id);
  if(error)throw new Error(error.code==='23505'?'ფილიალს უკვე აქვს ანგარიში':error.message);
  const {error:de}=await db.from('supervisor_branches').delete().eq('supervisor_id',b.id);if(de)throw de;
  if(scope.length){const {error}=await db.from('supervisor_branches').insert(scope.map(branch_id=>({supervisor_id:b.id,branch_id})));if(error)throw error;}
  return reply({id:b.id});
 }catch(e){
  if(createdId){await db.from('supervisor_branches').delete().eq('supervisor_id',createdId);await db.from('profiles').delete().eq('id',createdId);await db.auth.admin.deleteUser(createdId);}
  return reply({error:e instanceof Error?e.message:'ოპერაცია ვერ შესრულდა'},400);
 }
});

