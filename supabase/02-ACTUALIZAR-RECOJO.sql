BEGIN;
CREATE OR REPLACE FUNCTION public.mood_update_order(p_id uuid,p_status text,p_version integer,p_eta integer DEFAULT NULL,p_reason text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.mood_orders;allowed text[];data jsonb;estimated_at timestamptz;
BEGIN
 IF NOT public.mood_is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede actualizar pedidos.'; END IF;
 SELECT * INTO r FROM public.mood_orders WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pedido no encontrado.'; END IF;
 IF p_version IS NULL OR p_version<>r.version THEN RAISE EXCEPTION 'El pedido cambió. Actualiza el panel e inténtalo de nuevo.'; END IF;
 allowed:=CASE r.status WHEN 'pending' THEN ARRAY['accepted','rejected'] WHEN 'accepted' THEN ARRAY['delivered'] WHEN 'preparing' THEN ARRAY['delivered'] WHEN 'ready' THEN ARRAY['delivered'] WHEN 'on_way' THEN ARRAY['delivered'] ELSE ARRAY[]::text[] END;
 IF p_status IS NULL OR NOT p_status=ANY(allowed) THEN RAISE EXCEPTION 'Cambio de estado no permitido.'; END IF;
 data:=r.body;
 IF p_status='accepted' THEN
  IF p_eta IS NULL OR p_eta NOT BETWEEN 5 AND 180 THEN RAISE EXCEPTION 'Indica un tiempo estimado entre 5 y 180 minutos.'; END IF;
  estimated_at:=CASE WHEN data#>>'{schedule,modo}'='scheduled' THEN ((data#>>'{schedule,fecha}')::date+(data#>>'{schedule,hora}')::time) AT TIME ZONE 'America/La_Paz' ELSE now()+make_interval(mins=>p_eta) END;
  data:=data||jsonb_build_object('eta',p_eta,'estimatedAt',estimated_at);
  IF data->>'mode'='pickup' THEN data:=data||jsonb_build_object('pickupDeadline',estimated_at+interval '10 minutes'); END IF;
 END IF;
 IF p_status='rejected' THEN
  IF btrim(coalesce(p_reason,''))='' THEN RAISE EXCEPTION 'Indica el motivo del rechazo.'; END IF;
  data:=data||jsonb_build_object('rejection',left(btrim(p_reason),300));
 END IF;
 data:=jsonb_set(data,'{history}',(data->'history')||jsonb_build_array(jsonb_build_object('status',p_status,'at',now())));
 UPDATE public.mood_orders SET body=data,status=p_status,version=version+1 WHERE id=p_id RETURNING * INTO r;
 RETURN jsonb_build_object('order',r.body||jsonb_build_object('id',r.id,'code',r.code,'status',r.status,'version',r.version,'created',r.created));
END $$;
REVOKE ALL ON FUNCTION public.mood_update_order(uuid,text,integer,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_update_order(uuid,text,integer,integer,text) TO authenticated;


UPDATE public.mood_orders SET status='accepted',version=version+1 WHERE status IN ('preparing','ready','on_way');
UPDATE public.mood_orders SET body=body||jsonb_build_object('pickupDeadline',(body->>'estimatedAt')::timestamptz+interval '10 minutes'),version=version+1 WHERE status='accepted' AND body->>'mode'='pickup' AND body->>'estimatedAt' IS NOT NULL;
NOTIFY pgrst,'reload schema';
COMMIT;
