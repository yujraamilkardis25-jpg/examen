/* Inercia ligera de escritorio. No aplica blur ni transforma el contenido. */
(() => {
 const SUAVIDAD_MS=110; // Mayor valor: más inercia.
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 const desktop=matchMedia('(hover: hover) and (pointer: fine)');
 window.MoodMotion={behavior:()=>reduced.matches?'instant':'smooth'};
 let frame=0,target=0,lastY=0,lastTime=0,direction=0;
 const clamp=y=>Math.max(0,Math.min(Math.max(0,document.documentElement.scrollHeight-innerHeight),y));
 function stop(){if(frame)cancelAnimationFrame(frame);frame=0;direction=0;}
 function tick(time){
  if(Math.abs(scrollY-lastY)>3){stop();return;}
  const dt=Math.min(64,Math.max(1,time-lastTime));lastTime=time;target=clamp(target);
  const gap=target-scrollY;
  const next=scrollY+Math.sign(gap)*Math.min(Math.abs(gap),Math.max(1,Math.abs(gap)*(1-Math.exp(-dt/SUAVIDAD_MS))));
  window.scrollTo({top:Math.abs(target-next)<.6?target:next,behavior:'instant'});lastY=scrollY;
  if(Math.abs(target-scrollY)<1){stop();return;}
  frame=requestAnimationFrame(tick);
 }
 function nativeArea(node,delta){
  if(node?.closest?.('dialog,input,textarea,select,[contenteditable],.mood-map,.leaflet-container'))return true;
  for(let el=node;el&&el!==document.body;el=el.parentElement){
   if(/auto|scroll/.test(getComputedStyle(el).overflowY)&&el.scrollHeight>el.clientHeight+1&&((delta>0&&el.scrollTop+el.clientHeight<el.scrollHeight-1)||(delta<0&&el.scrollTop>0)))return true;
  }
  return false;
 }
 window.addEventListener('wheel',e=>{
  const route=location.hash.split('/')[0];
  if(reduced.matches||!desktop.matches||!['','#inicio','#menu','#cowork','#delivery','#ubicacion','#contacto'].includes(route)||document.querySelector('dialog[open]')||e.defaultPrevented||!e.cancelable||e.ctrlKey||e.metaKey||e.shiftKey||Math.abs(e.deltaX)>Math.abs(e.deltaY)||!e.deltaY||nativeArea(e.target,e.deltaY)){stop();return;}
  const delta=e.deltaY*(e.deltaMode===1?16:e.deltaMode===2?innerHeight:1),sign=Math.sign(delta);
  if(!frame||direction!==sign)target=scrollY;
  const next=clamp(target+delta);if(!frame&&next===scrollY)return;
  e.preventDefault();target=next;direction=sign;
  if(!frame){lastY=scrollY;lastTime=performance.now();frame=requestAnimationFrame(tick);}
 },{passive:false});
 ['hashchange','pagehide','blur','pointerdown','touchstart','keydown'].forEach(name=>window.addEventListener(name,stop,{passive:true}));
 reduced.addEventListener('change',stop);desktop.addEventListener('change',stop);
})();
