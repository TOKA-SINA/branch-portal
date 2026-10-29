import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const source=(await readFile(new URL('../dist/api.js',import.meta.url),'utf8')).replace(/^import[^\n]+\n/,'').replace(/\bexport /g,'');
const key='branch-portal-session';
function storage(initial={}){const values=new Map(Object.entries(initial));return {getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,String(v)),removeItem:k=>values.delete(k)}}
function tab({local=storage(),session=storage(),url='https://portal.example/branch-portal/'}={}){
 const requests=[];const window={location:{href:url},history:{state:null,replaceState(state,title,path){window.location.href=new URL(path,window.location.href).href}},dispatchEvent(){}};
 const context=vm.createContext({URL,Date,JSON,Event,config:{url:'https://backend.example',key:'public-test-key'},localStorage:local,sessionStorage:session,window,
  fetch:async(url,options)=>{requests.push({url,options});const body=options.body?JSON.parse(options.body):{};let data=null;
   if(url.includes('/token?')){const id=body.email?body.email.split('@')[0]:body.refresh_token.replace('refresh-','');data={access_token:'access-'+id,refresh_token:'refresh-'+id,expires_in:3600,user:{id}}}
   return {ok:true,status:200,text:async()=>data?JSON.stringify(data):''};
  }
 });
 vm.runInContext(source+'\nglobalThis.api={currentSession,login,logout,token,clearSession};',context);
 return {api:context.api,session,local,requests,window};
}
test('different tabs keep different users through login, reload and logout',async()=>{
 const local=storage();const a=tab({local});const b=tab({local});
 await a.api.login('branch','password');await b.api.login('executor','password');
 assert.equal(a.api.currentSession().user.id,'branch');assert.equal(b.api.currentSession().user.id,'executor');
 assert.equal(local.getItem(key),null);
 const reloadedA=tab({local,session:a.session});assert.equal(reloadedA.api.currentSession().user.id,'branch');
 await b.api.logout();assert.equal(b.api.currentSession(),null);assert.equal(reloadedA.api.currentSession().user.id,'branch');
 assert.ok(b.requests.at(-1).url.endsWith('/logout?scope=local'));
});
test('new-user links clear copied tab credentials and remove only the temporary URL flag',async()=>{
 const original=tab();await original.api.login('admin','password');
 const copied=storage({[key]:original.session.getItem(key)});
 const opened=tab({session:copied,url:'https://portal.example/branch-portal/?new_session=1&keep=yes#overview'});
 assert.equal(opened.api.currentSession(),null);assert.equal(copied.getItem(key),null);
 assert.equal(opened.window.location.href,'https://portal.example/branch-portal/?keep=yes#overview');
 assert.equal(original.api.currentSession().user.id,'admin');
});
test('legacy shared login migrates once, so the next normal tab starts signed out',()=>{
 const previous={access_token:'old-access',refresh_token:'old-refresh',expires_at:9999999999,user:{id:'admin'}};
 const local=storage({[key]:JSON.stringify(previous)});const a=tab({local});const b=tab({local});
 assert.equal(a.api.currentSession().user.id,'admin');assert.equal(local.getItem(key),null);assert.equal(b.api.currentSession(),null);
});
test('a fresh-user tab never imports a legacy login',()=>{
 const previous={access_token:'old-access',refresh_token:'old-refresh',user:{id:'admin'}};
 const local=storage({[key]:JSON.stringify(previous)});const a=tab({local,url:'https://portal.example/branch-portal/?new_session=1'});
 assert.equal(a.api.currentSession(),null);assert.ok(local.getItem(key));
 const reloaded=tab({local,session:a.session,url:a.window.location.href});
 assert.equal(reloaded.api.currentSession(),null,'refresh must not silently import an older shared login');
});
test('refreshing one token does not replace another tab session',async()=>{
 const local=storage();const a=tab({local});const b=tab({local});
 await a.api.login('supervisor','password');await b.api.login('executor','password');
 a.api.currentSession().expires_at=0;
 await Promise.all([a.api.token(),a.api.token()]);
 assert.equal(a.requests.filter(r=>r.url.includes('grant_type=refresh_token')).length,1);
 assert.equal(a.api.currentSession().user.id,'supervisor');assert.equal(b.api.currentSession().user.id,'executor');
});
