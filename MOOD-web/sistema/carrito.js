/* MOOD · Animación del carrito sin intervenir en la lógica de compras.
   Observa el contador que ya actualiza sistema/app.min.js. */
(() => {
  const button = document.querySelector('.header .nav-actions .bag');
  const badge = document.getElementById('cart-count');
  if (!button || !badge) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let previous = Number(badge.textContent) || 0;
  let animationTimeout;

  function syncCart() {
    const amount = Number(badge.textContent) || 0;
    button.setAttribute('aria-label', amount
      ? `Ver mi pedido, ${amount} ${amount === 1 ? 'producto' : 'productos'}`
      : 'Ver mi pedido, sin productos');

    if (amount > previous && !reducedMotion.matches) {
      button.classList.remove('cart-bump');
      // Reiniciar la animación si el usuario añade varios artículos seguidos.
      void button.offsetWidth;
      button.classList.add('cart-bump');
      window.clearTimeout(animationTimeout);
      animationTimeout = window.setTimeout(() => button.classList.remove('cart-bump'), 550);
    }
    previous = amount;
  }

  new MutationObserver(syncCart).observe(badge, {
    childList: true,
    characterData: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['hidden']
  });
  syncCart();
})();
