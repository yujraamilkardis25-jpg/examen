/* Recojo: fecha de Bolivia, solo hoy, horarios y anticipación mínima configurables. */
(() => {
 const cfg=PEDIDOS.recojo;
 function clock(now=new Date(Date.now()+(window.MoodClockOffset||0))){
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:cfg.zonaHoraria,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(now).map(p=>[p.type,p.value]));
  const date=`${parts.year}-${parts.month}-${parts.day}`,day=new Date(date+'T12:00:00Z').getUTCDay();
  return {date,day,minutes:Number(parts.hour)*60+Number(parts.minute)+Number(parts.second)/60};
 }
 function parse(value){if(!/^\d{2}:\d{2}$/.test(value||''))return NaN;const [h,m]=value.split(':').map(Number);return h<24&&m<60?h*60+m:NaN;}
 const format=value=>String(Math.floor(value/60)).padStart(2,'0')+':'+String(value%60).padStart(2,'0');
 function availability(now){
  const time=clock(now),hours=cfg.horarios[time.day],lead=Number(cfg.anticipacionMinutos),step=Number(cfg.intervaloMinutos);
  if(!Number.isFinite(lead)||lead<0||!Number.isInteger(step)||step<1)throw Error('Revisa los horarios de recojo en EDITAR-PEDIDOS.js.');
  if(!hours)return {...time,hours:null,slots:[],nowAvailable:false};
  const open=parse(hours[0]),close=parse(hours[1]);
  if(!Number.isFinite(open)||!Number.isFinite(close)||close<=open)throw Error('El horario de recojo configurado no es válido.');
  const first=Math.ceil(Math.max(open,time.minutes+lead)/step)*step,slots=[];
  for(let minute=first;minute<=close;minute+=step)slots.push(format(minute));
  return {...time,hours,slots,nowAvailable:time.minutes>=open&&time.minutes+lead<=close};
 }
 function validate(mode,date,hour,now){
  const state=availability(now);
  if(mode==='now'){
   if(!state.nowAvailable)throw Error('No está disponible el recojo ahora. Elige un horario de hoy si hay disponibilidad.');
   return {modo:'now',fecha:state.date,hora:'',texto:'Ahora mismo · preparación sujeta a confirmación de MOOD'};
  }
  if(mode!=='scheduled')throw Error('Elige recoger ahora o programar el recojo.');
  if(date!==state.date)throw Error('Solo puedes programar el recojo para hoy. No se admiten fechas anteriores ni posteriores.');
  if(!state.hours||!state.slots.length)throw Error('Hoy ya no hay horarios disponibles para programar el recojo.');
  const minutes=parse(hour);
  if(!Number.isFinite(minutes))throw Error('Selecciona una hora de recojo.');
  if(minutes<state.minutes+Number(cfg.anticipacionMinutos))throw Error(`Programa con al menos ${cfg.anticipacionMinutos} minutos de anticipación.`);
  if(!state.slots.includes(hour))throw Error('Selecciona una hora disponible dentro del horario de MOOD.');
  return {modo:'scheduled',fecha:date,hora:hour,texto:`Programado: ${date.split('-').reverse().join('/')} a las ${hour} (hora de Bolivia)`};
 }
 window.MoodPickup={availability,validate,clock};
})();
