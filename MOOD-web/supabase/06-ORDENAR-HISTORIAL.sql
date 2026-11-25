BEGIN;
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
REVOKE ALL ON FUNCTION public.mood_cash_day(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mood_cash_day(date) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
