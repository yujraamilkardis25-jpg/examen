/* Supabase por HTTPS: sin Node.js, dependencias instaladas ni claves privadas. */
const MoodAccounts=(()=>{
 'use strict';
 const base=SUPABASE.url.replace(/\/$/,''),key=SUPABASE.publishableKey,storageKey='mood-supabase-session-v1';
 let session=null,user=null,remember=false,refreshing=null;
 const read=storage=>{try{return JSON.parse(storage.getItem(storageKey)||'null');}catch{return null;}};
 const signal=()=>window.dispatchEvent(new Event('mood-account-change'));
 function store(data,persistent=remember){session=data;remember=persistent;try{localStorage.removeItem(storageKey);sessionStorage.removeItem(storageKey);if(data)(persistent?localStorage:sessionStorage).setItem(storageKey,JSON.stringify(data));}catch{ /* La sesión sigue disponible en memoria. */ }}
 function translate(message){const text=String(message||'No se pudo completar la operación.');if(/Invalid login credentials/i.test(text))return 'Correo o contraseña incorrectos.';if(/Email not confirmed/i.test(text))return 'Confirma tu correo electrónico antes de iniciar sesión.';if(/already registered/i.test(text))return 'Este correo ya tiene una cuenta. Elige Ya tengo cuenta.';if(/rate limit|too many/i.test(text))return 'Supabase limitó temporalmente los intentos. Espera unos minutos.';if(/Could not find the function|schema cache|does not exist/i.test(text))return 'Falta ejecutar 01-CONFIGURAR-MOOD.sql en el SQL Editor de Supabase.';return text;}
 async function raw(path,{method='GET',body,token,headers={}}={}){let response;try{response=await fetch(base+path,{method,headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body)});}catch{throw Error('No se pudo conectar con Supabase. Revisa tu conexión a Internet.');}let data;try{data=await response.json();}catch{data={};}if(!response.ok)throw Object.assign(Error(translate(data.msg||data.error_description||data.message||data.error)),{status:response.status});return data;}
 function normalized(data){return {access_token:data.access_token,refresh_token:data.refresh_token,expires_at:data.expires_at||Math.floor(Date.now()/1000)+Number(data.expires_in||3600)};}
 async function ensureSession(){if(!session)return null;if(Number(session.expires_at)>Date.now()/1000+60)return session;if(!refreshing)refreshing=raw('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token}}).then(data=>{store(normalized(data));return session;}).catch(error=>{if(error.status===400||error.status===401){store(null);user=null;signal();}throw error;}).finally(()=>{refreshing=null;});return refreshing;}
 async function rpc(name,args={},anonymous=false){await ensureSession();if(!anonymous&&!session)throw Object.assign(Error('Inicia sesión para continuar.'),{status:401});return raw('/rest/v1/rpc/'+name,{method:'POST',body:args,token:session?.access_token});}
 async function loadUser(){if(!await ensureSession()){user=null;return null;}await raw('/auth/v1/user',{token:session.access_token});user=await rpc('mood_profile');return user;}
 async function request(path,options={}){
  const method=options.method||'GET',data=options.body?JSON.parse(options.body):{};
  if(path==='/api/admin/cash-day')return rpc('mood_cash_day',{p_day:data.date});
  if(path==='/api/admin/manual-delivery')return rpc('mood_manual_delivery',{p_input:data});
  if(path==='/api/admin/manual-void')return rpc('mood_manual_void',{p_id:data.id,p_reason:data.reason});
  if(path==='/api/session')return {user:await loadUser()};
  if(path==='/api/config')return rpc('mood_config',{},true);
  if(path==='/api/orders'&&method==='POST')return rpc('mood_create_order',{p_input:data,p_key:options.headers?.['Idempotency-Key']});
  if(path==='/api/orders')return rpc('mood_list_orders',{p_admin:false});
  if(path==='/api/admin/orders')return rpc('mood_list_orders',{p_admin:true});
  const match=path.match(/^\/api\/(admin\/)?orders\/([a-f0-9-]{36})$/);
  if(match&&method==='PATCH')return rpc('mood_update_order',{p_id:match[2],p_status:data.status,p_version:data.version,p_eta:Number.isInteger(data.eta)?data.eta:null,p_reason:data.reason||''});
  if(match&&method==='GET')return rpc('mood_get_order',{p_id:match[2]});
  throw Error('Operación no disponible.');
 }
 async function start(){try{const [config,products]=await Promise.all([rpc('mood_config',{},true),raw('/rest/v1/mood_products?select=id,nombre,price_cents&active=eq.true')]);window.MoodPublicData={config,products};window.MoodClockOffset=Date.parse(config.now)-Date.now();}catch{/* El catálogo local sigue visible mientras se completa la configuración. */}session=read(sessionStorage);if(!session){session=read(localStorage);remember=!!session;}const params=new URLSearchParams(location.hash.slice(1));if(params.has('access_token')&&params.has('refresh_token')){store(normalized({access_token:params.get('access_token'),refresh_token:params.get('refresh_token'),expires_in:params.get('expires_in')}));history.replaceState(null,'',location.pathname+location.search+'#pedido');}try{await loadUser();}catch(error){user=null;if(error.status===401){store(null);}}}
 const ready=start();
 async function finishAuth(data,persistent){if(!data.access_token)throw Error('Revisa tu correo y confirma la cuenta. Después vuelve y elige Ya tengo cuenta. Tu pedido aún no se envió.');store(normalized(data),persistent);await loadUser();signal();return user.email;}
 return {ready,request,current:()=>user?.email||'',profile:()=>user,
  async signup(name,email,password){const redirect=location.href.split('#')[0];const data=await raw('/auth/v1/signup?redirect_to='+encodeURIComponent(redirect),{method:'POST',body:{email,password,data:{name}}});return finishAuth(data,false);},
  async login(email,password,persistent=false){const data=await raw('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});return finishAuth(data,persistent);},
  async logout(){const token=session?.access_token;store(null);user=null;signal();if(token)try{await raw('/auth/v1/logout?scope=local',{method:'POST',token});}catch{ /* La sesión de este navegador ya se ha cerrado. */ }}
 };
})();
