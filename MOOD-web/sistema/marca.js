/* Iconos coherentes con la guía visual; sin alterar acciones ni navegación. */
(() => {
 const svg=(paths,box='0 0 32 32')=>`<svg viewBox="${box}" aria-hidden="true" focusable="false">${paths}</svg>`;
 const arrow=svg('<circle cx="16" cy="16" r="13"/><path d="M9 16h14m-6-6 6 6-6 6"/>');
 const plus=svg('<circle cx="16" cy="16" r="13"/><path d="M9 16h14m-7-7v14"/>');
 const icons={focus:svg('<rect x="6" y="5" width="20" height="17" rx="2"/><path d="M3 27h26l-3-5H6z"/>'),social:svg('<circle cx="16" cy="9" r="4"/><circle cx="6" cy="13" r="3"/><circle cx="26" cy="13" r="3"/><path d="M9 27v-4a7 7 0 0 1 14 0v4zm-6 0v-5a5 5 0 0 1 5-5m21 10v-5a5 5 0 0 0-5-5"/>'),chill:svg('<path d="M7 16V9a5 5 0 0 1 5-5h8a5 5 0 0 1 5 5v7M7 23h18M7 28v-5m18 5v-5"/><path d="M7 15a4 4 0 0 0-4 4v4h26v-4a4 4 0 0 0-8 0H11a4 4 0 0 0-4-4z"/>'),energy:svg('<path d="m19 2-13 17h10l-3 11 13-18H16z"/>')};
 const root=document.getElementById('main');if(!root)return;
 function decorate(){
  const info=[svg('<path d="M25 13c0 7-9 16-9 16S7 20 7 13a9 9 0 0 1 18 0z"/><circle cx="16" cy="13" r="3"/>'),svg('<circle cx="16" cy="16" r="12"/><path d="M16 8v8l5 3"/>'),svg('<rect x="4" y="7" width="24" height="18" rx="3"/><path d="m5 9 11 9L27 9"/>')];
  root.querySelectorAll('.info-card .info-icon').forEach((slot,i)=>{if(!slot.dataset.brandIcon){slot.innerHTML=info[i%info.length];slot.dataset.brandIcon='1';}});
  root.querySelectorAll('.mood-card').forEach(card=>{const name=Object.keys(icons).find(k=>card.classList.contains(k));const slot=card.querySelector('.mood-icon');if(name&&slot&&!slot.dataset.brandIcon){slot.innerHTML=icons[name];slot.dataset.brandIcon='1';}});
  root.querySelectorAll('.button').forEach(button=>{
   if(button.closest('form,.checkout-page,.order-tracking,dialog')||button.querySelector('.brand-action-icon')||button.children.length)return;
   if(button.classList.contains('add')){const span=document.createElement('span');span.className='brand-action-icon';span.innerHTML=plus;button.append(span);return;}
   if(button.tagName==='A'&&/menú|pedir|espacio/i.test(button.textContent)){button.textContent=button.textContent.replace(/[→↗]/g,'').trim();const span=document.createElement('span');span.className='brand-action-icon';span.innerHTML=arrow;button.append(span);}
  });
 }
 let frame=0;new MutationObserver(()=>{if(!frame)frame=requestAnimationFrame(()=>{frame=0;decorate();});}).observe(root,{subtree:true,childList:true});decorate();
})();
