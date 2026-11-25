/* PEDIDOS POR WHATSAPP. No contiene claves ni contraseñas. */
const PEDIDOS={
  whatsapp:'59171429955', // Número internacional, sin + ni espacios.
  nombre:'MOOD',
  formaPago:'Efectivo',
  recojo:{
    zonaHoraria:'America/La_Paz',
    anticipacionMinutos:25,
    intervaloMinutos:15,
    // Se usan los horarios que ya tenía tu web. Cambiarlos aquí cambia la validación.
    horarios:{
      0:['09:00','19:00'], // Domingo
      1:['07:00','22:00'], // Lunes
      2:['07:00','22:00'], // Martes
      3:['07:00','22:00'], // Miércoles
      4:['07:00','22:00'], // Jueves
      5:['07:00','22:00'], // Viernes
      6:['08:00','21:00']  // Sábado. Usa null para marcar un día cerrado.
    }
  },
  // La respuesta automática se activa en la aplicación WhatsApp Business del negocio.
};
