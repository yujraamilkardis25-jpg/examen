-- MOOD — actualización de precios propuesta tras investigación pública (11-11-2026)
-- EJECUTAR UNA SOLA VEZ en Supabase > SQL Editor, sobre tu proyecto MOOD.
-- Este archivo NO cambia tablas, usuarios, productos archivados ni pedidos previos.
-- price_cents son centavos de boliviano: 1400 = Bs 14,00.
-- Evita ejecutar 01-CONFIGURAR-MOOD.sql de nuevo solo para cambiar precios.

BEGIN;

-- Evita aplicar una lista incompleta si cambian los códigos de productos.
DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n
 FROM public.mood_products
 WHERE id IN ('espresso', 'latte', 'cortado', 'cold', 'matcha', 'limonada', 'mocha', 'te', 'avo', 'granola', 'postre');
 IF n <> 11 THEN
  RAISE EXCEPTION 'Se encontraron % productos de 11; revisión necesaria antes de cambiar precios.', n;
 END IF;
END $$;

WITH nuevos(id, price_cents) AS (
  VALUES
    ('espresso', 1400),
    ('latte', 1900),
    ('cortado', 1300),
    ('cold', 1700),
    ('matcha', 2300),
    ('limonada', 1200),
    ('mocha', 2100),
    ('te', 800),
    ('avo', 2100),
    ('granola', 2000),
    ('postre', 1600)
)
UPDATE public.mood_products AS p
SET price_cents=n.price_cents
FROM nuevos AS n
WHERE p.id=n.id;

COMMIT;

-- Comprobar los 11 precios que mostrará la web conectada a Supabase.
SELECT id, nombre, price_cents, price_cents/100.0 AS precio_bs, active
FROM public.mood_products
WHERE id IN ('espresso', 'latte', 'cortado', 'cold', 'matcha', 'limonada', 'mocha', 'te', 'avo', 'granola', 'postre')
ORDER BY nombre;
