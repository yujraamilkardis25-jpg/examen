-- MOOD: ejecutar este archivo completo en SQL Editor de TU proyecto Supabase.
-- No contiene contraseñas ni crea usuarios de autenticación.
BEGIN;
CREATE SCHEMA IF NOT EXISTS mood_private;
REVOKE ALL ON SCHEMA mood_private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS mood_private.admin_emails(email text PRIMARY KEY);
INSERT INTO mood_private.admin_emails VALUES ('yujraamilkar.dis25@tecba.edu.bo') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS mood_private.settings(id boolean PRIMARY KEY DEFAULT true CHECK(id), body jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS mood_private.profiles(user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, nombre text NOT NULL DEFAULT '', apellidos text NOT NULL DEFAULT '', telefono text NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS public.mood_products(id text PRIMARY KEY,nombre text NOT NULL,price_cents integer NOT NULL CHECK(price_cents>=0),active boolean NOT NULL DEFAULT true);
CREATE TABLE IF NOT EXISTS public.mood_orders(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text NOT NULL UNIQUE,
 user_id uuid NOT NULL REFERENCES auth.users(id),request_key text NOT NULL,request_hash text NOT NULL,
 body jsonb NOT NULL,status text NOT NULL CHECK(status IN ('pending','accepted','preparing','ready','on_way','delivered','rejected')),
 version integer NOT NULL DEFAULT 1,created timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,request_key)
);
CREATE INDEX IF NOT EXISTS mood_orders_user_created ON public.mood_orders(user_id,created DESC);
CREATE INDEX IF NOT EXISTS mood_orders_created ON public.mood_orders(created DESC);
ALTER TABLE public.mood_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mood_orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA mood_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.mood_products,public.mood_orders FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.mood_products TO anon,authenticated;
GRANT SELECT ON public.mood_orders TO authenticated;

-- La autorización se consulta en auth.users: nunca se confía en user_metadata para roles.
CREATE OR REPLACE FUNCTION public.mood_is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM auth.users u JOIN mood_private.admin_emails a ON lower(u.email)=a.email
 WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL);
$$;
REVOKE ALL ON FUNCTION public.mood_is_admin() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_is_admin() TO authenticated;
DROP POLICY IF EXISTS mood_products_read ON public.mood_products;
CREATE POLICY mood_products_read ON public.mood_products FOR SELECT TO anon,authenticated USING(active);
DROP POLICY IF EXISTS mood_orders_read ON public.mood_orders;
CREATE POLICY mood_orders_read ON public.mood_orders FOR SELECT TO authenticated
 USING(user_id=(SELECT auth.uid()) OR (SELECT public.mood_is_admin()));

CREATE OR REPLACE FUNCTION public.mood_profile() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('id',u.id,'email',u.email,'name',coalesce(nullif(p.nombre,''),u.raw_user_meta_data->>'name',''),
 'apellidos',coalesce(p.apellidos,''),'telefono',coalesce(p.telefono,''),'role',CASE WHEN public.mood_is_admin() THEN 'admin' ELSE 'customer' END)
 FROM auth.users u LEFT JOIN mood_private.profiles p ON p.user_id=u.id WHERE u.id=auth.uid();
$$;
REVOKE ALL ON FUNCTION public.mood_profile() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_profile() TO authenticated;

CREATE OR REPLACE FUNCTION public.mood_config() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT body || jsonb_build_object('now',now()) FROM mood_private.settings WHERE id=true;
$$;
REVOKE ALL ON FUNCTION public.mood_config() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_config() TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.mood_list_orders(p_admin boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Inicia sesión para ver tus pedidos.'; END IF;
 IF p_admin AND NOT public.mood_is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede entrar al panel.'; END IF;
 SELECT coalesce(jsonb_agg(q.o ORDER BY q.created DESC),'[]'::jsonb) INTO result FROM (
  SELECT body||jsonb_build_object('id',id,'code',code,'status',status,'version',version,'created',created) AS o,created
  FROM public.mood_orders WHERE p_admin OR user_id=auth.uid() ORDER BY created DESC LIMIT CASE WHEN p_admin THEN 500 ELSE 100 END
 )q;
 RETURN jsonb_build_object('orders',result);
END $$;
REVOKE ALL ON FUNCTION public.mood_list_orders(boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_list_orders(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.mood_get_order(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 SELECT body||jsonb_build_object('id',id,'code',code,'status',status,'version',version,'created',created) INTO result
 FROM public.mood_orders WHERE id=p_id;
 IF result IS NULL THEN RAISE EXCEPTION 'Pedido no encontrado o no tienes acceso.'; END IF;
 RETURN jsonb_build_object('order',result);
END $$;
REVOKE ALL ON FUNCTION public.mood_get_order(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_get_order(uuid) TO authenticated;

-- Función transaccional: calcula importes, valida horarios y cobertura, evita duplicados.
CREATE OR REPLACE FUNCTION public.mood_create_order(p_input jsonb,p_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 uid uuid:=auth.uid(); cfg jsonb; old public.mood_orders; row_order public.mood_orders;
 mode text; contact jsonb; nombre text; apellidos text; telefono text; email text;
 local_now timestamp; today date; hours jsonb; open_at timestamp; close_at timestamp; earliest timestamp;
 lead_minutes integer; step_minutes integer; requested timestamp; hour_value text; schedule jsonb:=NULL;
 lat double precision; lng double precision; h double precision; distance_m double precision; point jsonb:=NULL;
 line jsonb; product public.mood_products; qty integer; items jsonb:='[]'::jsonb; seen text[]:='{}';
 subtotal bigint:=0; shipping bigint:=0; total bigint; invoice jsonb:=NULL; comment_value text; references_value text;
 data jsonb; order_code text; signature text; attempts integer:=0;
BEGIN
 IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users au WHERE au.id=uid AND au.email IS NOT NULL AND NOT coalesce(au.is_anonymous,false)) THEN
  RAISE EXCEPTION 'Debes registrarte e iniciar sesión antes de enviar.';
 END IF;
 IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>32768 THEN RAISE EXCEPTION 'Datos del pedido no válidos.'; END IF;
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{10,100}$' THEN RAISE EXCEPTION 'Falta la identificación de envío.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(uid::text,0));
 signature:=encode(sha256(convert_to(p_input::text,'UTF8')),'hex');
 SELECT * INTO old FROM public.mood_orders WHERE user_id=uid AND request_key=p_key;
 IF FOUND THEN
  IF old.request_hash<>signature THEN RAISE EXCEPTION 'El envío cambió. Revisa tu pedido antes de reenviarlo.'; END IF;
  RETURN jsonb_build_object('order',old.body||jsonb_build_object('id',old.id,'code',old.code,'status',old.status,'version',old.version,'created',old.created));
 END IF;
 IF (SELECT count(*) FROM public.mood_orders WHERE user_id=uid AND created>now()-interval '15 minutes')>=30 THEN RAISE EXCEPTION 'Espera unos minutos antes de enviar más pedidos.'; END IF;
 SELECT body INTO cfg FROM mood_private.settings WHERE id=true;
 IF cfg IS NULL THEN RAISE EXCEPTION 'Falta configurar MOOD en la base de datos.'; END IF;
 mode:=p_input->>'mode';
 IF mode IS NULL OR mode NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Elige delivery o recojo.'; END IF;
 nombre:=left(btrim(coalesce(p_input#>>'{contact,nombre}','')),100);
 apellidos:=left(btrim(coalesce(p_input#>>'{contact,apellidos}','')),100);
 telefono:=left(btrim(coalesce(p_input#>>'{contact,telefono}','')),25);
 email:=left(btrim(coalesce(p_input#>>'{contact,email}','')),254);
 IF nombre='' OR apellidos='' OR telefono !~ '^\+?[0-9 ()-]{7,25}$' OR length(regexp_replace(telefono,'[^0-9]','','g')) NOT BETWEEN 7 AND 15 THEN
  RAISE EXCEPTION 'Completa nombres, apellidos y un teléfono válido.';
 END IF;
 IF email<>'' AND email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Revisa el correo electrónico.'; END IF;
 IF p_input->>'payment' IS DISTINCT FROM 'Efectivo' THEN RAISE EXCEPTION 'Selecciona el pago en efectivo.'; END IF;
 contact:=jsonb_build_object('nombre',nombre,'apellidos',apellidos,'telefono',telefono,'email',email);
 local_now:=now() AT TIME ZONE (cfg#>>'{recojo,zonaHoraria}'); today:=local_now::date;
 IF mode='pickup' THEN
  hours:=cfg#>ARRAY['recojo','horarios',extract(dow FROM local_now)::integer::text];
  IF hours IS NULL OR jsonb_typeof(hours)<>'array' THEN RAISE EXCEPTION 'Hoy no hay horarios de recojo disponibles.'; END IF;
  open_at:=today+(hours->>0)::time;close_at:=today+(hours->>1)::time;
  lead_minutes:=(cfg#>>'{recojo,anticipacionMinutos}')::integer;step_minutes:=(cfg#>>'{recojo,intervaloMinutos}')::integer;
  IF lead_minutes<0 OR step_minutes<1 OR close_at<=open_at THEN RAISE EXCEPTION 'Revisa la configuración de horarios de MOOD.'; END IF;
  earliest:=local_now+make_interval(mins=>lead_minutes);
  IF p_input#>>'{schedule,mode}'='now' THEN
   IF local_now<open_at OR earliest>close_at THEN RAISE EXCEPTION 'No está disponible recoger ahora. Elige un horario disponible de hoy.'; END IF;
   schedule:=jsonb_build_object('modo','now','fecha',today,'hora','','texto','Ahora mismo · preparación sujeta a confirmación de MOOD');
  ELSIF p_input#>>'{schedule,mode}'='scheduled' THEN
   IF p_input#>>'{schedule,date}' IS DISTINCT FROM today::text THEN RAISE EXCEPTION 'Solo puedes programar el recojo para hoy, hora de Bolivia.'; END IF;
   hour_value:=p_input#>>'{schedule,hour}';
   IF hour_value IS NULL OR hour_value !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Selecciona una hora de recojo.'; END IF;
   requested:=today+hour_value::time;
   IF requested<earliest THEN RAISE EXCEPTION 'Programa con al menos % minutos de anticipación.',lead_minutes; END IF;
   IF requested<open_at OR requested>close_at OR mod((extract(hour FROM requested)*60+extract(minute FROM requested))::integer,step_minutes)<>0 THEN RAISE EXCEPTION 'Selecciona una hora disponible dentro del horario de MOOD.'; END IF;
   schedule:=jsonb_build_object('modo','scheduled','fecha',today,'hora',hour_value,'texto','Programado: '||to_char(today,'DD/MM/YYYY')||' a las '||hour_value||' (hora de Bolivia)');
  ELSE RAISE EXCEPTION 'Elige recoger ahora o programar el recojo.';
  END IF;
 ELSE
  IF p_input#>'{point,confirmed}' IS DISTINCT FROM 'true'::jsonb OR jsonb_typeof(p_input#>'{point,lat}') IS DISTINCT FROM 'number' OR jsonb_typeof(p_input#>'{point,lng}') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Confirma un punto de entrega dentro de la cobertura.'; END IF;
  lat:=(p_input#>>'{point,lat}')::double precision;lng:=(p_input#>>'{point,lng}')::double precision;
  IF lat NOT BETWEEN -90 AND 90 OR lng NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'La ubicación no es válida.'; END IF;
  h:=power(sin(radians(lat-(cfg#>>'{delivery,latitud}')::double precision)/2),2)+cos(radians(lat))*cos(radians((cfg#>>'{delivery,latitud}')::double precision))*power(sin(radians(lng-(cfg#>>'{delivery,longitud}')::double precision)/2),2);
  distance_m:=6371000*2*asin(sqrt(least(1.0,greatest(0.0,h))));
  IF distance_m>(cfg#>>'{delivery,radioMetros}')::double precision THEN RAISE EXCEPTION 'El punto está fuera de la cobertura. Puedes recoger en MOOD.'; END IF;
  point:=jsonb_build_object('lat',lat,'lng',lng);shipping:=(cfg->>'deliveryFeeCents')::bigint;
 END IF;
 IF jsonb_typeof(p_input->'items') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Revisa el carrito.'; END IF;
 IF jsonb_array_length(p_input->'items') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Agrega un producto antes de enviar.'; END IF;
 FOR line IN SELECT value FROM jsonb_array_elements(p_input->'items') LOOP
  IF coalesce(line->>'qty','') !~ '^[1-9][0-9]?$' THEN RAISE EXCEPTION 'Revisa las cantidades del carrito.'; END IF;
  qty:=(line->>'qty')::integer;
  SELECT * INTO product FROM public.mood_products WHERE id=line->>'id' AND active;
  IF NOT FOUND OR product.id=ANY(seen) THEN RAISE EXCEPTION 'Hay un producto no disponible o repetido. Revisa el carrito.'; END IF;
  seen:=array_append(seen,product.id);
  items:=items||jsonb_build_array(jsonb_build_object('id',product.id,'nombre',product.nombre,'qty',qty,'unit',product.price_cents,'line',product.price_cents::bigint*qty));
  subtotal:=subtotal+product.price_cents::bigint*qty;
 END LOOP;
 total:=subtotal+shipping;
 IF shipping<0 OR total>9007199254740991 THEN RAISE EXCEPTION 'El importe del pedido no es válido.'; END IF;
 IF jsonb_typeof(p_input->'invoice')='object' THEN invoice:=jsonb_build_object('razon',left(btrim(coalesce(p_input#>>'{invoice,razon}','')),150),'nit',left(btrim(coalesce(p_input#>>'{invoice,nit}','')),30)); END IF;
 comment_value:=left(btrim(coalesce(p_input->>'comment','')),500);
 references_value:=CASE WHEN mode='delivery' THEN left(btrim(coalesce(p_input->>'referencias','')),500) ELSE '' END;
 data:=jsonb_build_object('mode',mode,'contact',contact,'items',items,'sub',subtotal,'fee',shipping,'total',total,'payment','Efectivo','schedule',schedule,'point',point,'invoice',invoice,'comment',comment_value,'referencias',references_value,'address',cfg->>'address','eta',NULL,'rejection','','history',jsonb_build_array(jsonb_build_object('status','pending','at',now())));
 LOOP
  order_code:=translate(upper(substr(replace(gen_random_uuid()::text,'-',''),1,5)),'01','GH');attempts:=attempts+1;
  BEGIN
   INSERT INTO public.mood_orders(code,user_id,request_key,request_hash,body,status) VALUES(order_code,uid,p_key,signature,data,'pending') RETURNING * INTO row_order;
   EXIT;
  EXCEPTION WHEN unique_violation THEN IF attempts>=10 THEN RAISE EXCEPTION 'No se pudo asignar un código. Inténtalo de nuevo.'; END IF;
  END;
 END LOOP;
 INSERT INTO mood_private.profiles(user_id,nombre,apellidos,telefono) VALUES(uid,nombre,apellidos,telefono)
 ON CONFLICT(user_id) DO UPDATE SET nombre=excluded.nombre,apellidos=excluded.apellidos,telefono=excluded.telefono;
 RETURN jsonb_build_object('order',row_order.body||jsonb_build_object('id',row_order.id,'code',row_order.code,'status',row_order.status,'version',row_order.version,'created',row_order.created));
END $$;
REVOKE ALL ON FUNCTION public.mood_create_order(jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_create_order(jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.mood_update_order(p_id uuid,p_status text,p_version integer,p_eta integer DEFAULT NULL,p_reason text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.mood_orders;allowed text[];data jsonb;estimated_at timestamptz;
BEGIN
 IF NOT public.mood_is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede actualizar pedidos.'; END IF;
 SELECT * INTO r FROM public.mood_orders WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pedido no encontrado.'; END IF;
 IF p_version IS NULL OR p_version<>r.version THEN RAISE EXCEPTION 'El pedido cambió. Actualiza el panel e inténtalo de nuevo.'; END IF;
 IF p_status='cancel_order' THEN
  IF r.status NOT IN ('pending','accepted') OR r.body->>'mode'<>'pickup' THEN RAISE EXCEPTION 'Solo puedes cancelar un recojo pendiente o aceptado.'; END IF;
  IF length(btrim(coalesce(p_reason,''))) NOT BETWEEN 1 AND 300 THEN RAISE EXCEPTION 'Indica un motivo de cancelación de hasta 300 caracteres.'; END IF;
  data:=r.body||jsonb_build_object('cancelledAt',now(),'cancellationKind','manual','rejection',btrim(p_reason));
  data:=jsonb_set(data,'{history}',(data->'history')||jsonb_build_array(jsonb_build_object('status','rejected','event','cancelled_admin','at',now())));
  UPDATE public.mood_orders SET body=data,status='rejected',version=version+1 WHERE id=p_id RETURNING * INTO r;
  RETURN jsonb_build_object('order',r.body||jsonb_build_object('id',r.id,'code',r.code,'status',r.status,'version',r.version,'created',r.created));
 END IF;
 IF p_status='cancel_expired' THEN
  IF r.status<>'accepted' OR r.body->>'mode'<>'pickup' OR r.body->>'pickupDeadline' IS NULL THEN RAISE EXCEPTION 'Solo puedes cancelar por demora un recojo aceptado con plazo definido.'; END IF;
  IF now()<(r.body->>'pickupDeadline')::timestamptz THEN RAISE EXCEPTION 'El plazo de recojo aún no ha vencido.'; END IF;
  data:=r.body||jsonb_build_object('cancelledAt',now(),'rejection','Pedido cancelado por falta de recojo tras vencer el plazo.');
  data:=jsonb_set(data,'{history}',(data->'history')||jsonb_build_array(jsonb_build_object('status','rejected','event','cancelled_no_pickup','at',now())));
  UPDATE public.mood_orders SET body=data,status='rejected',version=version+1 WHERE id=p_id RETURNING * INTO r;
  RETURN jsonb_build_object('order',r.body||jsonb_build_object('id',r.id,'code',r.code,'status',r.status,'version',r.version,'created',r.created));
 END IF;
 IF p_status='notify_ready' THEN
  IF r.status<>'accepted' OR r.body->>'mode'<>'pickup' OR r.body#>>'{schedule,modo}'='scheduled' THEN RAISE EXCEPTION 'Este aviso solo corresponde a un recojo inmediato aceptado.'; END IF;
  IF r.body->>'readyAt' IS NOT NULL THEN RAISE EXCEPTION 'El pedido ya está marcado como listo.'; END IF;
  data:=r.body||jsonb_build_object('readyAt',now(),'pickupDeadline',now()+interval '10 minutes');
  data:=jsonb_set(data,'{history}',(data->'history')||jsonb_build_array(jsonb_build_object('status','accepted','event','ready','at',now())));
  UPDATE public.mood_orders SET body=data,version=version+1 WHERE id=p_id RETURNING * INTO r;
  RETURN jsonb_build_object('order',r.body||jsonb_build_object('id',r.id,'code',r.code,'status',r.status,'version',r.version,'created',r.created));
 END IF;
 allowed:=CASE r.status WHEN 'pending' THEN ARRAY['accepted','rejected'] WHEN 'accepted' THEN ARRAY['delivered'] WHEN 'preparing' THEN ARRAY['delivered'] WHEN 'ready' THEN ARRAY['delivered'] WHEN 'on_way' THEN ARRAY['delivered'] ELSE ARRAY[]::text[] END;
 IF p_status IS NULL OR NOT p_status=ANY(allowed) THEN RAISE EXCEPTION 'Cambio de estado no permitido.'; END IF;
 data:=r.body;
 IF p_status='accepted' THEN
  IF p_eta IS NULL OR p_eta NOT BETWEEN 5 AND 180 THEN RAISE EXCEPTION 'Indica un tiempo estimado entre 5 y 180 minutos.'; END IF;
  estimated_at:=CASE WHEN data#>>'{schedule,modo}'='scheduled' THEN ((data#>>'{schedule,fecha}')::date+(data#>>'{schedule,hora}')::time) AT TIME ZONE 'America/La_Paz' ELSE now()+make_interval(mins=>p_eta) END;
  data:=data||jsonb_build_object('eta',p_eta,'estimatedAt',estimated_at);
  IF data->>'mode'='pickup' AND data#>>'{schedule,modo}'='scheduled' THEN data:=data||jsonb_build_object('pickupDeadline',estimated_at+interval '10 minutes'); END IF;
 END IF;
 IF p_status='rejected' THEN
  IF btrim(coalesce(p_reason,''))='' THEN RAISE EXCEPTION 'Indica el motivo del rechazo.'; END IF;
  data:=data||jsonb_build_object('rejection',left(btrim(p_reason),300));
 END IF;
 IF p_status='delivered' THEN data:=data||jsonb_build_object('deliveredAt',now(),'paidAt',now()); END IF;
 data:=jsonb_set(data,'{history}',(data->'history')||jsonb_build_array(jsonb_build_object('status',p_status,'at',now())));
 UPDATE public.mood_orders SET body=data,status=p_status,version=version+1 WHERE id=p_id RETURNING * INTO r;
 RETURN jsonb_build_object('order',r.body||jsonb_build_object('id',r.id,'code',r.code,'status',r.status,'version',r.version,'created',r.created));
END $$;
REVOKE ALL ON FUNCTION public.mood_update_order(uuid,text,integer,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_update_order(uuid,text,integer,integer,text) TO authenticated;

-- Configuración y catálogo originales de tu web.
INSERT INTO mood_private.settings(id,body) VALUES(true,'{"delivery":{"direccion":"Calle José Pol y Sucre","ciudad":"Cochabamba, Bolivia","latitud":-17.3921341,"longitud":-66.1444161,"radioMetros":2000,"mapaGoogle":"https://maps.app.goo.gl/ZwsPPq1i6PHmePVAA"},"recojo":{"zonaHoraria":"America/La_Paz","anticipacionMinutos":25,"intervaloMinutos":15,"horarios":{"0":["09:00","19:00"],"1":["07:00","22:00"],"2":["07:00","22:00"],"3":["07:00","22:00"],"4":["07:00","22:00"],"5":["07:00","22:00"],"6":["08:00","21:00"]}},"deliveryFeeCents":1000,"address":"Calle José Pol y Sucre, Cochabamba, Bolivia"}'::jsonb) ON CONFLICT(id) DO UPDATE SET body=excluded.body;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('espresso','Espresso Doble',1400) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('latte','Latte de Vainilla',1900) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('cortado','Cortado Ahumado',1300) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('cold','Cold Brew',1700) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('matcha','Matcha Latte',2300) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('limonada','Limonada Menta',1200) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('mocha','Mocha Naranja',2100) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('te','Té de la casa',800) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('avo','Avo Toast',2100) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('granola','Granola Bowl',2000) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
INSERT INTO public.mood_products(id,nombre,price_cents) VALUES('postre','Postre del día',1600) ON CONFLICT(id) DO UPDATE SET nombre=excluded.nombre,price_cents=excluded.price_cents;
NOTIFY pgrst, 'reload schema';
CREATE TABLE IF NOT EXISTS mood_private.manual_deliveries(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),request_key text UNIQUE NOT NULL,
 day date NOT NULL,customer text NOT NULL,reference text NOT NULL DEFAULT '',note text NOT NULL,
 cents integer NOT NULL CHECK(cents>0 AND cents<=10000000),created_by uuid NOT NULL REFERENCES auth.users(id),
 created timestamptz NOT NULL DEFAULT now(),voided_at timestamptz,void_reason text
);
REVOKE ALL ON mood_private.manual_deliveries FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.mood_manual_delivery(p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r mood_private.manual_deliveries;d date;n integer;k text;
BEGIN
 IF NOT public.mood_is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede registrar cobros.'; END IF;
 k:=p_input->>'key';d:=(p_input->>'day')::date;n:=(p_input->>'cents')::integer;
 IF k IS NULL OR length(k) NOT BETWEEN 16 AND 100 OR d IS NULL OR d>(now() AT TIME ZONE 'America/La_Paz')::date OR n IS NULL OR n NOT BETWEEN 1 AND 10000000 OR length(btrim(coalesce(p_input->>'customer',''))) NOT BETWEEN 1 AND 100 OR length(btrim(coalesce(p_input->>'note',''))) NOT BETWEEN 1 AND 500 OR length(coalesce(p_input->>'reference',''))>80 THEN RAISE EXCEPTION 'Revisa fecha, cliente, detalle e importe del delivery.'; END IF;
 INSERT INTO mood_private.manual_deliveries(request_key,day,customer,reference,note,cents,created_by)
 VALUES(k,d,btrim(p_input->>'customer'),coalesce(p_input->>'reference',''),btrim(p_input->>'note'),n,auth.uid()) ON CONFLICT(request_key) DO NOTHING;
 SELECT * INTO r FROM mood_private.manual_deliveries WHERE request_key=k;
 IF r.day<>d OR r.cents<>n OR r.customer<>btrim(p_input->>'customer') OR r.note<>btrim(p_input->>'note') OR r.reference<>coalesce(p_input->>'reference','') THEN RAISE EXCEPTION 'Esta referencia de guardado ya se usó con otros datos.'; END IF;
 RETURN jsonb_build_object('id',r.id);
END $$;
CREATE OR REPLACE FUNCTION public.mood_manual_void(p_id uuid,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.mood_is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede anular cobros.'; END IF;
 IF length(btrim(coalesce(p_reason,''))) NOT BETWEEN 1 AND 300 THEN RAISE EXCEPTION 'Indica un motivo de hasta 300 caracteres.'; END IF;
 UPDATE mood_private.manual_deliveries SET voided_at=now(),void_reason=btrim(p_reason) WHERE id=p_id AND voided_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registro no encontrado o ya anulado.'; END IF;
 RETURN jsonb_build_object('ok',true);
END $$;
CREATE OR REPLACE FUNCTION public.mood_cash_day(p_day date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NOT public.mood_is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede consultar cobros.'; END IF;
 IF p_day IS NULL THEN RAISE EXCEPTION 'Selecciona una fecha.'; END IF;
 WITH web AS (
  SELECT o.*,coalesce((o.body->>'deliveredAt')::timestamptz,(SELECT max((h->>'at')::timestamptz) FROM jsonb_array_elements(o.body->'history') h WHERE h->>'status'='delivered')) AS paid_at FROM public.mood_orders o WHERE o.body->>'mode'='pickup'
 ), entries AS (
  SELECT id::text AS id,'web'::text AS kind,code,concat_ws(' ',body#>>'{contact,nombre}',body#>>'{contact,apellidos}') AS customer,(body->>'total')::bigint AS cents,status='delivered' AS counted,false AS voided,CASE WHEN body->>'cancelledAt' IS NOT NULL THEN 'Cancelado' WHEN status='delivered' THEN 'Cobrado y entregado' WHEN status='rejected' THEN 'Rechazado' WHEN status='accepted' THEN 'Aceptado · por cobrar' ELSE 'Pendiente' END AS state,coalesce(body->>'rejection','') AS note,coalesce(paid_at,created) AS recorded_at
  FROM web WHERE CASE WHEN status='delivered' THEN (paid_at AT TIME ZONE 'America/La_Paz')::date=p_day ELSE (created AT TIME ZONE 'America/La_Paz')::date=p_day END
  UNION ALL
  SELECT id::text,'manual',coalesce(nullif(reference,''),left(id::text,8)),customer,cents,voided_at IS NULL,voided_at IS NOT NULL,CASE WHEN voided_at IS NULL THEN 'Cobrado y entregado' ELSE 'Registro anulado' END,note||CASE WHEN voided_at IS NULL THEN '' ELSE ' · Anulación: '||void_reason END,(day+((created AT TIME ZONE 'America/La_Paz')::time)) AT TIME ZONE 'America/La_Paz' FROM mood_private.manual_deliveries WHERE day=p_day
 ) SELECT jsonb_build_object('total',coalesce(sum(cents) FILTER(WHERE counted),0),'pickup',coalesce(sum(cents) FILTER(WHERE counted AND kind='web'),0),'delivery',coalesce(sum(cents) FILTER(WHERE counted AND kind='manual'),0),'count',count(*) FILTER(WHERE counted),'pending',(SELECT coalesce(sum((body->>'total')::bigint),0) FROM public.mood_orders WHERE status='accepted' AND body->>'mode'='pickup'),'entries',coalesce(jsonb_agg(to_jsonb(entries) ORDER BY recorded_at DESC,id DESC),'[]'::jsonb)) INTO result FROM entries;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.mood_manual_delivery(jsonb),public.mood_manual_void(uuid,text),public.mood_cash_day(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_manual_delivery(jsonb),public.mood_manual_void(uuid,text),public.mood_cash_day(date) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
