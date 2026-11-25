/* MOOD | Botón accesible para mostrar u ocultar la contraseña.
   Se aplica a formularios que se generan dinámicamente, sin alterar la autenticación. */
(() => {
  'use strict';
  const eyeOpen = '<svg class="mood-eye-open" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M2 12s3.6-6 10-6 10 6 10 6-3.6 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>';
  const eyeSlash = '<svg class="mood-eye-slash" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M10.6 6.1A11.4 11.4 0 0 1 12 6c6.4 0 10 6 10 6a15 15 0 0 1-3.1 3.7M6.1 6.2A15.5 15.5 0 0 0 2 12s3.6 6 10 6c1.3 0 2.5-.3 3.5-.7M9.9 9.9a3 3 0 0 0 4.2 4.2M3 3l18 18"/></svg>';

  function addToggle(input) {
    if (input.closest('.mood-password-control')) return;
    const label = input.closest('label');
    if (!label || !label.parentNode) return;

    // El botón está al lado del label (no dentro), para no interferir
    // con el clic sobre la etiqueta ni con el envío del formulario.
    const wrapper = document.createElement('div');
    wrapper.className = 'mood-password-control';
    label.parentNode.insertBefore(wrapper, label);
    wrapper.append(label);
    input.classList.add('mood-password-input');

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'mood-password-toggle';
    button.setAttribute('aria-label', 'Mostrar contraseña');
    button.setAttribute('title', 'Mostrar contraseña');
    button.setAttribute('aria-pressed', 'false');
    button.innerHTML = eyeOpen + eyeSlash;
    button.addEventListener('click', () => {
      const visible = input.type === 'password';
      input.type = visible ? 'text' : 'password';
      button.setAttribute('aria-label', visible ? 'Ocultar contraseña' : 'Mostrar contraseña');
      button.setAttribute('title', visible ? 'Ocultar contraseña' : 'Mostrar contraseña');
      button.setAttribute('aria-pressed', String(visible));
      input.focus({ preventScroll: true });
    });
    wrapper.append(button);
  }

  function scan(node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    if (node.matches('input[type="password"]')) addToggle(node);
    node.querySelectorAll('input[type="password"]').forEach(addToggle);
  }

  scan(document.body);
  // Los formularios de acceso y de pedido se renderizan después de cargar la web.
  new MutationObserver(records => {
    records.forEach(record => {
      record.addedNodes.forEach(scan);
    });
  }).observe(document.body, { childList: true, subtree: true });
})();
