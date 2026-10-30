import {config} from './config.js';
const storageKey='branch-portal-session';
const initializedKey='branch-portal-tab-initialized';
const pageUrl=new URL(window.location.href);
const freshTab=pageUrl.searchParams.has('new_session');
let session=null;
try{
 if(freshTab){sessionStorage.removeItem(storageKey)}
 else{
  session=JSON.parse(sessionStorage.getItem(storageKey)||'null');
  if(!session&&sessionStorage.getItem(initializedKey)!=='1'){
   const previous=JSON.parse(localStorage.getItem(storageKey)||'null');
   if(previous?.access_token&&previous?.refresh_token&&previous?.user?.id){session=previous;sessionStorage.setItem(storageKey,JSON.stringify(session));localStorage.removeItem(storageKey)}
  }
 }
 sessionStorage.setItem(initializedKey,'1');
}catch{session=null}
if(freshTab){pageUrl.searchParams.delete('new_session');window.history.replaceState(window.history.state,'',pageUrl.pathname+pageUrl.search+pageUrl.hash)}
let refreshing;
export const currentSession=()=>session;
export function clearSession(){session=null;sessionStorage.removeItem(storageKey);stopRealtime()}
function save(data){session={access_token:data.access_token,refresh_token:data.refresh_token,expires_at:Math.floor(Date.now()/1000)+data.expires_in,user:data.user};sessionStorage.setItem(storageKey,JSON.stringify(session));}
async function raw(path,{method='GET',body,headers={},auth=true}={}){
 const r=await fetch(config.url+path,{method,headers:{apikey:config.key,'Content-Type':'application/json',...(auth&&session?{Authorization:'Bearer '+session.access_token}:{}),...headers},...(body!==undefined?{body:JSON.stringify(body)}:{})});
 let data;const t=await r.text();try{data=t?JSON.parse(t):null}catch{data={message:t}}
 if(!r.ok){const e=new Error(data?.error_description||data?.message||data?.error||'მოთხოვნა ვერ შესრულდა');e.status=r.status;e.code=data?.code;throw e;}return data;
}
export async function token(){
 if(!session)throw new Error('გთხოვთ შეხვიდეთ სისტემაში');
 if(session.expires_at<Date.now()/1000+90){
  if(!refreshing)refreshing=raw('/auth/v1/token?grant_type=refresh_token',{method:'POST',auth:false,body:{refresh_token:session.refresh_token}}).then(save).catch(e=>{clearSession();window.dispatchEvent(new Event('session-expired'));throw e}).finally(()=>{refreshing=null});
  await refreshing;
 }return session.access_token;
}
export async function login(username,password){
 const data=await raw('/auth/v1/token?grant_type=password',{method:'POST',auth:false,body:{email:username.trim().toLowerCase()+'@branch-portal.internal.invalid',password}});save(data);return data.user;
}
export async function logout(){try{await token();await raw('/auth/v1/logout?scope=local',{method:'POST'})}finally{clearSession()}}
export async function changePassword(password){await token();return raw('/auth/v1/user',{method:'PUT',body:{password}})}
export async function query(table,filter=''){await token();return raw('/rest/v1/'+table+'?'+filter);}
export async function all(table,filter=''){
 const rows=[];for(let start=0;;start+=1000){await token();const data=await raw('/rest/v1/'+table+'?'+filter,{headers:{Range:`${start}-${start+999}`,'Range-Unit':'items'}});rows.push(...data);if(data.length<1000)return rows;}
}
export async function insert(table,body){await token();return raw('/rest/v1/'+table,{method:'POST',body,headers:{Prefer:'return=representation'}})}
export async function update(table,id,body){await token();const data=await raw('/rest/v1/'+table+'?id=eq.'+encodeURIComponent(id),{method:'PATCH',body,headers:{Prefer:'return=representation'}});if(!data?.length)throw new Error('ჩანაწერი ვერ განახლდა; გადაამოწმეთ წვდომა');return data;}
export async function adminUser(body){await token();const data=await raw('/functions/v1/admin-users',{method:'POST',body});if(data?.error)throw new Error(data.error);return data;}
export async function readNotifications(){await token();return raw('/rest/v1/notifications?read_at=is.null',{method:'PATCH',body:{read_at:new Date().toISOString()}})}
let realtimeSocket=null,realtimeHeartbeat=null,realtimeReconnect=null,realtimeStopped=true;
export function stopRealtime(){realtimeStopped=true;if(realtimeReconnect){clearTimeout(realtimeReconnect);realtimeReconnect=null}if(realtimeHeartbeat){clearInterval(realtimeHeartbeat);realtimeHeartbeat=null}if(realtimeSocket){try{realtimeSocket.close()}catch{}realtimeSocket=null}}
export async function startRealtime(userId,onChange){
 stopRealtime();realtimeStopped=false;
 const topic='realtime:branch-portal-'+userId;
 const socketUrl=config.url.replace(/^https?/,'wss')+'/realtime/v1/websocket?apikey='+encodeURIComponent(config.key)+'&vsn=1.0.0';
 const connect=async()=>{
  if(realtimeStopped)return;
  const access=await token();
  const ws=new WebSocket(socketUrl);realtimeSocket=ws;let ref=0;
  const send=(event,payload={})=>ws.send(JSON.stringify({topic,event,payload,ref:String(++ref)}));
  ws.onopen=()=>{
   send('phx_join',{config:{broadcast:{ack:false,self:false},presence:{key:''},postgres_changes:[
    {event:'*',schema:'public',table:'issues'},
    {event:'*',schema:'public',table:'comments'},
    {event:'*',schema:'public',table:'issue_events'},
    {event:'*',schema:'public',table:'notifications',filter:'user_id=eq.'+userId}
   ]},access_token:access});
   realtimeHeartbeat=setInterval(()=>{if(ws.readyState===WebSocket.OPEN)send('heartbeat',{})},25000);
  };
  ws.onmessage=e=>{try{const m=JSON.parse(e.data);if(m.event==='postgres_changes')onChange?.(m.payload?.data||m.payload)}catch{}};
  ws.onerror=()=>{try{ws.close()}catch{}};
  ws.onclose=()=>{if(realtimeSocket===ws)realtimeSocket=null;if(realtimeHeartbeat){clearInterval(realtimeHeartbeat);realtimeHeartbeat=null}if(!realtimeStopped)realtimeReconnect=setTimeout(()=>connect().catch(()=>{}),5000)};
 };
 connect().catch(()=>{if(!realtimeStopped)realtimeReconnect=setTimeout(()=>connect().catch(()=>{}),5000)});
}
