# Bitácora de Inmuebles

App web para llevar el registro de inmuebles publicados en Facebook Marketplace y de las atenciones a clientes, con reporte semanal en PDF. Funciona en teléfono y PC.

Es un sitio estático (HTML + JavaScript, sin paso de compilación) con Supabase como base de datos e inicio de sesión.

## Qué hace

- **Inmuebles:** título, fecha, tipo, operación, zona, precio, estado, captador (agente que lo captó), enlace de la publicación y enlace en Novus.
- **Atenciones:** cliente, contacto, tipo de atención (consulta, seguimiento, visita, captación, negociación, etc.), inmueble relacionado, canal, resultado y fecha de seguimiento.
- **Clientes:** cada cliente con su historial de atenciones, último resultado y seguimiento pendiente.
- **Inicio:** conteo de la semana y seguimientos pendientes.
- **Reporte semanal (lunes a domingo):** PDF que se comparte desde el teléfono, y resumen en texto para pegar en WhatsApp.

No se conecta con Meta: Marketplace no ofrece una API para publicaciones de perfiles personales, así que el enlace de cada publicación se pega a mano.

## Puesta en marcha

1. **Supabase:** crea un proyecto y ejecuta `supabase/schema.sql` en el SQL Editor.
2. **Usuario:** en Authentication > Users, crea el usuario (correo y contraseña) de quien usará la app. Conviene desactivar el registro público en Authentication > Sign In / Providers.
3. **Configuración:** en `config.js` coloca la URL del proyecto y la clave `anon` (Project Settings > API). Nunca la clave `service_role`.
4. **Publicación:** sube el repositorio a Netlify, Vercel o GitHub Pages. No requiere comando de build; el directorio de publicación es la raíz.

## Seguridad

Las tablas tienen RLS: solo las personas del equipo (quienes tienen fila en la tabla `perfiles`) ven y editan los registros, y todos comparten los mismos. Los cambios de una persona le aparecen a las demás en vivo. La clave `anon` puede estar en el repositorio porque sin iniciar sesión no da acceso a ningún dato.

## Notificaciones

Cuando alguien del equipo registra, edita o elimina algo, a los demás les llega una notificación push ("Edgar editó una atención"), aunque tengan la app cerrada. Cada persona las activa en Inicio > Notificaciones, una vez por dispositivo. En iPhone hay que abrir la app desde el ícono de la pantalla de inicio.

Por dentro: un trigger de la base llama a la función `notificar` (Edge Function, desplegada sin verificación de JWT porque valida un secreto propio), y `sw.js` muestra el aviso en el dispositivo.

## Estructura

```
index.html           App completa
config.js            URL y clave pública de Supabase
supabase/schema.sql  Tablas, índices y políticas RLS
supabase/functions/notificar/index.ts  Envío de notificaciones push
sw.js                Service worker que muestra las notificaciones
```
