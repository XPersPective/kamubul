let tokenCache;
const encode=bytes=>btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
const text64=text=>encode(new TextEncoder().encode(text));
export async function fcmAccessToken(env) {
  if(!env.FCM_CLIENT_EMAIL||!env.FCM_PRIVATE_KEY)throw new Error('fcm_credentials_missing');
  if(tokenCache&&tokenCache.expires>Date.now()+60000)return tokenCache.token;
  const now=Math.floor(Date.now()/1000);
  const claim=text64(JSON.stringify({iss:env.FCM_CLIENT_EMAIL,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600}));
  const signed=text64(JSON.stringify({alg:'RS256',typ:'JWT'}))+'.'+claim;
  const pem=env.FCM_PRIVATE_KEY.replace(/\\n/g,'\n').replace(/-----[^-]+-----|\s/g,'');
  const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),x=>x.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(signed));
  const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:signed+'.'+encode(new Uint8Array(signature))}),signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw new Error('fcm_oauth_'+response.status);
  const data=await response.json();if(typeof data.access_token!=='string')throw new Error('fcm_oauth_format');
  tokenCache={token:data.access_token,expires:Date.now()+Math.min(Number(data.expires_in)||3600,3600)*1000};return tokenCache.token;
}
export function fcmMessage(token,event,now=new Date()){
  const deadline=Date.parse(event.deadline),ttl=Math.max(0,Math.min(86400,Number.isFinite(deadline)?Math.floor((deadline-Number(now))/1000):86400));
  const digest=event.mode==='digest';
  return {message:{token,notification:{title:digest?'KamuBul · İlan özeti':'KamuBul · Size uygun yeni ilan',body:digest?`${event.digestCount} yeni ilan kriterlerinize uyuyor. ${String(event.title).slice(0,120)}`:String(event.title).slice(0,180)},data:{eventId:event.eventId,listingId:event.id,url:event.url,revision:String(event.revision),kind:digest?'digest':'instant',count:String(event.digestCount??1)},android:{priority:digest?'NORMAL':'HIGH',ttl:ttl+'s',notification:{channel_id:'kamubul_alerts',tag:event.eventId}},apns:{headers:{'apns-collapse-id':event.eventId.slice(0,64),'apns-expiration':String(Math.floor(Number(now)/1000)+ttl)},payload:{aps:{sound:'default'}}}}};
}
export async function sendFcm(env,token,event){
  const access=await fcmAccessToken(env);const response=await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,{method:'POST',headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},body:JSON.stringify(fcmMessage(token,event)),signal:AbortSignal.timeout(15000)});
  const data=await response.json().catch(()=>({}));
  if(response.ok&&typeof data.name==='string'&&data.name)return {state:'accepted',id:data.name};
  const invalid=data.error?.details?.some(d=>d.errorCode==='UNREGISTERED');
  if(invalid)return {state:'invalid_token'};
  if(response.status===401)tokenCache=null;
  throw new Error('fcm_http_'+response.status);
}
