// 飯省 service worker：頁面 network-first（離線才用快取，避免舊版或壞掉的快取讓 App 打不開）；靜態檔 cache-first；API 一律走網路。
const C='fansave-v1792366708', SHELL=['./','index.html','data.js','manifest.json','icons/icon-192.png','icons/favicon-32.png','icons/apple-touch-icon.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))));self.skipWaiting();});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('fansave-v1792366708')&&k!==C).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method==='POST'&&u.origin===location.origin&&u.pathname.endsWith('/fansave/share-target')){   // Android 分享到飯省：暫存後轉到我的住宿
    e.respondWith((async()=>{try{const f=await r.formData(),c=await caches.open('fansave-share');await c.delete('/fansave/__share');
      const meta={title:f.get('title')||'',text:f.get('text')||'',url:f.get('url')||'',t:Date.now()};const img=f.get('image');
      if(img&&typeof img!=='string'&&img.size){await c.put('/fansave/__share_img',new Response(img,{headers:{'Content-Type':img.type||'image/jpeg'}}));meta.img=1;}
      await c.put('/fansave/__share',new Response(JSON.stringify(meta),{headers:{'Content-Type':'application/json'}}));}catch(x){}
      return Response.redirect('/fansave/?share=1#tab=stays',303);})());return;}
  if(r.method!=='GET'||u.origin!==location.origin)return;               // Apps Script / Worker：瀏覽器自己處理
  if(r.mode==='navigate'){
    e.respondWith(fetch(r).then(res=>{if(res.ok){const k=res.clone();caches.open(C).then(c=>c.put('./',k));}return res;})
      .catch(()=>caches.match('./').then(x=>x||caches.match('index.html')).then(x=>x||new Response('<meta charset=utf-8><p style="font:16px sans-serif;padding:24px">目前離線，請連上網路後再開一次飯省。</p>',{headers:{'Content-Type':'text/html; charset=utf-8'}}))));
    return;}
  e.respondWith(caches.match(r).then(x=>x||fetch(r)));
});
// 系統通知（Web Push，VAPID）：推播沒有內容，收到後向伺服器取最新一則通知再顯示
self.addEventListener('push',e=>{e.waitUntil((async()=>{
  let t='飯省 FanSave',b='有新的通知',l='./#tab=alerts',tag='fansave';
  try{const {dev,api}=await new Promise((ok,no)=>{const o=indexedDB.open('fansave',1);o.onupgradeneeded=()=>o.result.createObjectStore('kv');o.onerror=no;o.onsuccess=()=>{const r=o.result.transaction('kv').objectStore('kv').get('meta');r.onsuccess=()=>r.result?ok(r.result):no();r.onerror=no;};});
    const j=await (await fetch(api+'?action=alerts&dev='+encodeURIComponent(dev))).json();const a=(j.alerts||[])[0];if(a){t=a.title;b=a.body;l=a.link||l;tag=a.id||tag;}}catch(x){}
  await self.registration.showNotification(t,{body:b,icon:'icons/icon-192.png',badge:'icons/favicon-48.png',tag,data:{link:l}});})());});
self.addEventListener('notificationclick',e=>{const l=(e.notification.data||{}).link||'./';e.notification.close();
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{for(const c of cs){if('focus' in c){c.postMessage({link:l});return c.focus();}}return clients.openWindow(l);}));});
