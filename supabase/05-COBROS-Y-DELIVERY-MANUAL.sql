BEGIN;
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
