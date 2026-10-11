// Supabase Edge Function "manage-user" — sostituisce la versione precedente.
// NON inserire chiavi segrete nel sito. La service role viene letta dalle variabili d'ambiente Supabase.
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors={ 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS' };
const reply=(obj:unknown,status=200)=>new Response(JSON.stringify(obj),{status,headers:{...cors,'Content-Type':'application/json'}});
const validName=(s:unknown)=>typeof s==='string'&&/^[a-zA-Z0-9_.-]{3,32}$/.test(s);
const alias=(s:string)=>s.toLowerCase()+'@pcr.invalid';
serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply({error:'Metodo non consentito'},405);
 try{
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if(!url||!anon||!secret)return reply({error:'Configurazione server incompleta'},500);
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');
  if(!token)return reply({error:'Autenticazione richiesta'},401);
  const client=createClient(url,anon,{global:{headers:{Authorization:'Bearer '+token}}});
  const {data:{user},error:authErr}=await client.auth.getUser();
  if(authErr||!user)return reply({error:'Sessione non valida'},401);
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:profile,error:pe}=await admin.from('profiles').select('id,role,archived,username').eq('id',user.id).single();
  if(pe||profile?.role!=='admin'||profile?.archived)return reply({error:'Operazione riservata ad ADMIN'},403);
  const b=await req.json(),action=String(b.action||'');
  if(action==='list'){
   const {data,error}=await admin.auth.admin.listUsers({page:1,perPage:1000});if(error)throw error;
   return reply({users:data.users.map(u=>({id:u.id,email:u.email||''}))});
  }
  if(action==='admin-profile'){
   if(!validName(b.username))return reply({error:'Username non valido'},400);
   const patch:Record<string,string>={};
   if(b.username.toLowerCase()!==String(profile.username).toLowerCase())patch.email=alias(b.username);
   if(b.password){if(String(b.password).length<10)return reply({error:'Password troppo corta'},400);patch.password=b.password}
   if(Object.keys(patch).length){const {error}=await admin.auth.admin.updateUserById(user.id,patch);if(error)throw error}
   const {error}=await admin.from('profiles').update({username:b.username}).eq('id',user.id);if(error)throw error;
   return reply({ok:true});
  }
  if(!['create','update','archive','restore','delete','repair-login'].includes(action))return reply({error:'Azione sconosciuta'},400);
  if(action==='create'){
   if(!validName(b.username)||!b.password||String(b.password).length<10)return reply({error:'Username o password non validi'},400);
   const {data:created,error}=await admin.auth.admin.createUser({email:alias(b.username),password:b.password,email_confirm:true});if(error)throw error;
   const id=created.user.id;
   const {error:profileErr}=await admin.from('profiles').upsert({id,username:b.username,role:'user',archived:false});
   if(profileErr){await admin.auth.admin.deleteUser(id);throw profileErr}
   if(Array.isArray(b.room_ids)&&b.room_ids.length){const {error:accessErr}=await admin.from('room_access').upsert(b.room_ids.map((room_id:string)=>({room_id,user_id:id})),{onConflict:'room_id,user_id'});if(accessErr)throw accessErr}
   return reply({user:{id}});
  }
  const id=String(b.user_id||'');if(!/^[0-9a-f-]{36}$/i.test(id))return reply({error:'ID utente non valido'},400);
  const {data:target}=await admin.from('profiles').select('id,role,username').eq('id',id).single();
  if(!target||target.role!=='user')return reply({error:'Utente non trovato'},404);
  if(action==='repair-login'){
   const {error}=await admin.auth.admin.updateUserById(id,{email:alias(String(target.username)),email_confirm:true});if(error)throw error;
   return reply({ok:true});
  }
  if(action==='delete'){
   const {error}=await admin.auth.admin.deleteUser(id);if(error)throw error;
   return reply({ok:true});
  }
  if(action==='archive'||action==='restore'){
   const {error}=await admin.from('profiles').update({archived:action==='archive'}).eq('id',id);if(error)throw error;
   return reply({ok:true});
  }
  if(!validName(b.username))return reply({error:'Username non valido'},400);
  const patch:Record<string,string>={};
  if(b.username.toLowerCase()!==String(target.username).toLowerCase())patch.email=alias(b.username);
  // IMPORTANTE: non cambiare MAI password quando il campo è vuoto o non presente.
  if(typeof b.password==='string'&&b.password.length){if(b.password.length<10)return reply({error:'Password troppo corta'},400);patch.password=b.password}
  if(Object.keys(patch).length){const {error}=await admin.auth.admin.updateUserById(id,patch);if(error)throw error}
  const {error}=await admin.from('profiles').update({username:b.username}).eq('id',id);if(error)throw error;
  return reply({user:{id}});
 }catch(e){console.error('manage-user:',e);return reply({error:e instanceof Error?e.message:'Errore server'},500)}
});
