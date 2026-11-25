# MOOD · Versión estática con Supabase

Empieza por **LEEME-EMPEZAR.txt**. Primero debes ejecutar el archivo SQL en tu proyecto Supabase y configurar el usuario administrador.

- Tienda: index.html.
- Panel privado: admin.html.
- Diagnóstico de conexión: comprobar.html.
- Tablas, permisos y reglas del pedido: supabase/01-CONFIGURAR-MOOD.sql.
- Conexión pública ya configurada: EDITAR-SUPABASE.js.
- Apariencia e imágenes: EDITAR-DISENO.css y EDITAR-IMAGENES.js.

Abre con Live Server. También funciona con GitHub Pages, incluidas las direcciones con subcarpeta de repositorio. No necesitas instalar Node.js ni paquetes.

Las contraseñas las gestiona Supabase Auth. Los pedidos solo se insertan y actualizan mediante funciones de PostgreSQL que validan cuenta, catálogo, importes, cobertura, horarios, duplicados y permisos. Los clientes no pueden editar directamente la tabla de pedidos. Las políticas RLS limitan la lectura al dueño de la compra y al administrador.

Se conserva la marca y los archivos multimedia de la entrega anterior. Esta entrega no está publicada y el archivo SQL no se ejecuta automáticamente con una clave pública: debes aplicarlo desde el SQL Editor de tu cuenta.
