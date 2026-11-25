/* Mapa y cobertura del delivery. La configuración está en EDITAR-DELIVERY.js. */
(() => {
  'use strict';
  const config=DELIVERY,origin=[Number(config.latitud),Number(config.longitud)],radius=Number(config.radioMetros);
  const validPoint=(lat,lng)=>Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180;
  function distance(a,b){const rad=n=>n*Math.PI/180,dlat=rad(b[0]-a[0]),dlng=rad(b[1]-a[1]);const h=Math.sin(dlat/2)**2+Math.cos(rad(a[0]))*Math.cos(rad(b[0]))*Math.sin(dlng/2)**2;return 6371000*2*Math.atan2(Math.sqrt(Math.min(1,h)),Math.sqrt(Math.max(0,1-h)));}
  function check(lat,lng){if(!validPoint(lat,lng))return {valid:false,inside:false,meters:null};const meters=distance(origin,[lat,lng]);return {valid:true,inside:meters<=radius,meters};}
  const km=m=>(m/1000).toLocaleString('es-BO',{maximumFractionDigits:2}),maps=new Set();
  let selected=null,confirmed=false,leafletPromise,homeObserver,locationRequest=0;
  // La selección de entrega vive en memoria; no se guarda el GPS en localStorage.
  window.MoodDelivery={check,distance,getSelection:()=>selected?{...selected,confirmed}:null};
  if(!validPoint(...origin)||!Number.isFinite(radius)||radius<=0){console.error('Revisa las coordenadas y el radio en EDITAR-DELIVERY.js.');return;}
  MOOD.negocio.direccion=config.direccion;MOOD.negocio.ciudad=config.ciudad;MOOD.negocio.mapa=config.mapaGoogle;
  function loadLeaflet(){
    if(window.L)return Promise.resolve(window.L);
    if(leafletPromise)return leafletPromise;
    leafletPromise=new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='sistema/vendor/leaflet/leaflet.js';script.onload=()=>window.L?resolve(window.L):reject(Error('No se pudo cargar el mapa.'));script.onerror=()=>reject(Error('No se pudo cargar el mapa. Actualiza la página.'));document.head.append(script);});
    leafletPromise.catch(()=>{leafletPromise=null;});return leafletPromise;
  }

  function saveForm(){const form=document.getElementById('delivery-form');if(form)Object.assign(deliveryData,Object.fromEntries(new FormData(form)));}
  function cleanMaps(){for(const item of maps)if(!document.contains(item.node)){item.map.remove();maps.delete(item);}}
  function card(delivery){
    const node=document.createElement('section');node.className='delivery-map-card';
    node.innerHTML=`<span class="coverage-label">Cobertura: ${km(radius)} km de radio</span><h3>${delivery?'Marca tu punto de entrega':'¿Llegamos hasta ti?'}</h3><p>${delivery?'Toca el mapa o mueve el marcador hasta la entrada de tu domicilio.':'MOOD · '+escapeHTML(config.direccion)+', '+escapeHTML(config.ciudad)+'. La zona sombreada indica nuestra cobertura inicial.'}</p><div class="mood-map ${delivery?'':'coverage-map'}" role="region" aria-label="Mapa de cobertura de MOOD" tabindex="0"><div class="map-loading">Cargando mapa…</div></div><div class="delivery-tools">${delivery?'<button type="button" data-map="locate">Usar mi ubicación</button><button type="button" data-map="center">Marcar centro del mapa</button>':''}${delivery?'<button type="button" data-map="store">Ver MOOD y cobertura</button><button type="button" data-map="expand" aria-pressed="false">Ampliar mapa</button>':''}<a href="${escapeHTML(config.mapaGoogle)}" target="_blank" rel="noopener">Ver local en Google Maps ↗</a></div>${delivery?'<div class="delivery-result" data-map="result" role="status" aria-live="polite">Selecciona un punto para comprobar la cobertura.</div><label class="delivery-check"><input type="checkbox" data-map="confirm" disabled> Confirmo que el marcador corresponde a mi dirección de entrega.</label><p class="map-status" data-map="status" role="status"></p><button type="button" class="text-button" data-map="pickup" hidden>Mi dirección queda fuera: recoger en MOOD</button>':''}<p class="map-note">La zona sombreada muestra la cobertura disponible. ${delivery?'Completa también tu correo electrónico y las referencias debajo del mapa. Puedes marcar el punto manualmente si no deseas usar el GPS.':''}</p>`;
    return node;
  }
  async function mount(node,delivery){
    const canvas=node.querySelector('.mood-map');
    try{
      const L=await loadLeaflet();if(!document.contains(node))return;
      canvas.innerHTML='';const map=L.map(canvas,{scrollWheelZoom:false,keyboard:true}).setView(origin,14);
      const item={node,map};maps.add(item);let destination,accuracyCircle;
      const tiles=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors'}).addTo(map);
      let loaded=false,errors=0;tiles.on('load',()=>{loaded=true;});tiles.on('tileerror',()=>{errors++;if(errors>=4&&!loaded&&delivery)node.querySelector('[data-map=status]').textContent='No se pudieron cargar las calles. Comprueba Internet y actualiza la página antes de elegir tu punto.';});
      const zone=L.circle(origin,{radius,color:'#196d76',fillColor:'#196d76',fillOpacity:.12,weight:2}).addTo(map);
      const icon=(text,customer)=>L.divIcon({className:customer?'mood-customer-pin':'mood-store-pin',html:text,iconSize:[34,34],iconAnchor:[17,17]});
      L.marker(origin,{icon:icon('M',false),title:'MOOD · '+config.direccion}).addTo(map).bindPopup('<b>MOOD</b><br>'+escapeHTML(config.direccion)+'<br>'+escapeHTML(config.ciudad));
      const fit=()=>map.fitBounds(zone.getBounds(),{padding:[18,18]});fit();
      const result=node.querySelector('[data-map=result]'),confirmation=node.querySelector('[data-map=confirm]');
      function update(){
        if(!delivery)return;
        const value=selected?check(selected.lat,selected.lng):null;
        confirmation.disabled=!value?.inside;confirmation.checked=confirmed&&!!value?.inside;
        node.querySelector('[data-map=pickup]').hidden=!value||value.inside;
        if(!value){result.className='delivery-result';result.textContent='Selecciona un punto para comprobar la cobertura.';return;}
        result.className='delivery-result '+(value.inside?'ok':'out');
        result.textContent=value.inside?'Tu punto de entrega está dentro de la cobertura de MOOD.':`Tu punto de entrega está fuera de la cobertura de ${km(radius)} km de radio. Puedes recoger en MOOD.`;
      }
      function select(latlng,accuracy=null){
        const value=check(latlng.lat,latlng.lng);if(!value.valid)return;
        selected={lat:latlng.lat,lng:latlng.lng,meters:value.meters,accuracy};confirmed=false;
        if(!destination){destination=L.marker(latlng,{draggable:true,icon:icon('●',true),title:'Tu punto de entrega',alt:'Tu punto de entrega'}).addTo(map);destination.on('dragend',()=>select(destination.getLatLng()));}else destination.setLatLng(latlng);
        if(accuracyCircle){map.removeLayer(accuracyCircle);accuracyCircle=null;}
        if(accuracy&&accuracy>25)accuracyCircle=L.circle(latlng,{radius:accuracy,weight:1,color:'#eb5c32',fillOpacity:.06,interactive:false}).addTo(map);
        update();const error=document.getElementById('delivery-error');if(error)error.textContent='';
      }
      const storeButton=node.querySelector('[data-map=store]');if(storeButton)storeButton.onclick=fit;
      const expandButton=node.querySelector('[data-map=expand]');if(expandButton)expandButton.onclick=e=>{const expanded=node.classList.toggle('expanded');e.currentTarget.textContent=expanded?'Reducir mapa':'Ampliar mapa';e.currentTarget.setAttribute('aria-pressed',String(expanded));requestAnimationFrame(()=>map.invalidateSize());};
      node.addEventListener('keydown',e=>{if(e.key==='Escape'&&node.classList.contains('expanded'))node.querySelector('[data-map=expand]')?.click();});
      if(delivery){
        map.on('click',e=>select(e.latlng));
        if(selected){const previous=confirmed;select(L.latLng(selected.lat,selected.lng),selected.accuracy);confirmed=previous;update();}
        node.querySelector('[data-map=center]').onclick=()=>select(map.getCenter());
        confirmation.onchange=()=>{confirmed=confirmation.checked&&!!selected&&check(selected.lat,selected.lng).inside;};
        node.querySelector('[data-map=pickup]').onclick=()=>document.querySelector('[data-action=mode][data-mode=pickup]')?.click();
        node.querySelector('[data-map=locate]').onclick=e=>{
          const button=e.currentTarget,status=node.querySelector('[data-map=status]');
          if(!navigator.geolocation){status.textContent='Este navegador no ofrece ubicación. Marca tu dirección manualmente.';return;}
          if(!window.isSecureContext){status.textContent='El GPS requiere HTTPS o localhost. Marca tu dirección manualmente.';return;}
          const request=++locationRequest;button.disabled=true;status.textContent='Buscando tu ubicación…';
          navigator.geolocation.getCurrentPosition(position=>{
            button.disabled=false;if(request!==locationRequest||!document.contains(node))return;
            const {latitude,longitude,accuracy}=position.coords;select(L.latLng(latitude,longitude),accuracy);map.setView([latitude,longitude],16);
            status.textContent=accuracy>100?'La ubicación es aproximada. Mueve el marcador hasta tu entrada antes de confirmar.':'Revisa la posición y mueve el marcador si hace falta.';
          },error=>{button.disabled=false;if(request!==locationRequest||!document.contains(node))return;status.textContent=error.code===1?'No se autorizó la ubicación. Puedes elegir el punto tocando el mapa.':'No se pudo obtener tu ubicación. Selecciona el punto manualmente.';},{enableHighAccuracy:true,timeout:12000,maximumAge:0});
        };
      }
      requestAnimationFrame(()=>map.invalidateSize());
    }catch(error){canvas.innerHTML='';const message=document.createElement('div');message.className='map-loading';message.textContent=error.message;canvas.append(message);}
  }
  function mountHome(){cleanMaps();const section=document.getElementById('delivery');if(!section||section.querySelector('.delivery-coverage'))return;const wrapper=document.createElement('div');wrapper.className='container delivery-coverage';const node=card(false);wrapper.append(node);section.append(wrapper);if(homeObserver)homeObserver.disconnect();if('IntersectionObserver' in window){homeObserver=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){homeObserver.disconnect();mount(node,false);}},{rootMargin:'300px'});homeObserver.observe(node);}else mount(node,false);}
  const originalHome=renderHome;renderHome=function(){saveForm();originalHome();mountHome();};
  const originalCheckout=checkoutPage;checkoutPage=function(){saveForm();locationRequest++;originalCheckout();cleanMaps();if(deliveryMode!=='delivery')return;const form=document.getElementById('delivery-form'),node=card(true);form.before(node);const address=form.elements.direccion;if(address)address.addEventListener('input',()=>{confirmed=false;const checkbox=node.querySelector('[data-map=confirm]');checkbox.checked=false;});mount(node,true);};
  const originalConfirm=confirmOrder;confirmOrder=function(){
    if(deliveryMode==='delivery'&&MoodAccounts.current()&&count()){
      const value=selected?check(selected.lat,selected.lng):null;let message='';
      if(!value?.valid)message='Marca tu punto de entrega en el mapa antes de confirmar.';
      else if(!value.inside)message=`Tu punto está fuera de los ${km(radius)} km de cobertura. Puedes recoger en MOOD.`;
      else if(!confirmed)message='Confirma que el marcador corresponde a tu dirección de entrega.';
      if(message){const error=document.getElementById('delivery-error');if(error){error.textContent=message;error.scrollIntoView({behavior:'smooth',block:'center'});}return;}
    }
    originalConfirm();

  };
  document.addEventListener('click',event=>{if(event.target.closest('[data-action=finish]')){selected=null;confirmed=false;locationRequest++;}});
  // La primera vista fue dibujada por app.min.js: actualiza solo dirección y enlaces al local.
  if(location.hash==='#pedido')checkoutPage();else if(!location.hash||['#inicio','#delivery','#ubicacion','#cowork','#galeria'].includes(location.hash)){renderHome();if(location.hash&&location.hash!=='#inicio')requestAnimationFrame(()=>document.querySelector(location.hash)?.scrollIntoView());}
})();
