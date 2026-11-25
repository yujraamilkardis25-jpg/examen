# MOOD — Estudio y propuesta de precios universitarios

**Fecha de consulta y propuesta:** 11 de noviembre de 2026. **Zona principal:** Cochabamba, Bolivia. **Moneda:** bolivianos (Bs).

## Interpretación de la información

- **Precio observado:** precio publicado en las páginas web de otras cafeterías consultadas en la fecha de este estudio; el comercio puede haberlo cambiado sin actualizar su carta. No implica que el precio se haya verificado en caja el mismo día.
- **Precio de MOOD:** recomendación calculada para posicionarse en el tramo accesible del mercado local. No es un precio cobrado por otra cafetería.
- **Beneficio:** ningún precio propuesto puede garantizar ganancias netas sin conocer cuánto cuesta preparar y servir cada porción, pagar personal, alquiler, impuestos y mermas.
- Los comparables «Ahumado», «Naranja» y «Menta» no son recetas idénticas en la competencia; los precios de mercado corresponden a la bebida base.

## Propuesta para los 11 productos del menú actual

| Producto MOOD | Referencia competitiva publicada (Bs) | Propuesta MOOD (Bs) | Máx. costo variable/porción para 65% de margen bruto (Bs) | Comparabilidad |
|---|---|---:|---:|---|
| Espresso Doble | Caffinos 12; Tercer Espacio 18; Oye Café 18 | 14 | 4.90 | café doble |
| Latte de Vainilla | Caffinos 20; Café Ciudad 18; Tercer Espacio 25 | 19 | 6.65 | latte vainilla |
| Cortado Ahumado | La La Latte (cortado) 10; Cofi 12; Tercer Espacio 15 | 13 | 4.55 | cortado base, no idéntico al ahumado |
| Cold Brew | La La Latte 15; Cofi 15; Tercer Espacio 25 | 17 | 5.95 | cold brew |
| Matcha Latte | Cofi 12; Oye Café 24; Tercer Espacio 25 | 23 | 8.05 | matcha latte; calidad e ingredientes pueden diferir |
| Limonada Menta | La La Latte (limonada) 10; Oye Café (limonada fresca) 13; Tercer Espacio (limonada) 16 | 12 | 4.20 | limonada base; menta adicional |
| Mocha Naranja | La La Latte (mocha) 15; Oye Café (mokaccino) 23; Tercer Espacio (mokaccino) 25 | 21 | 7.35 | mocha base; naranja adicional |
| Té de la casa | La La Latte (té negro) 6; Café Ciudad (té/mate) 7; Tercer Espacio (té clásico) 10 | 8 | 2.80 | té base |
| Avo Toast | Oye Café (tostada con palta) 22; Oye Café (con tocino) 32 | 21 | 7.35 | tostada con palta base |
| Granola Bowl | Oye Café (granola bowl con yogur griego y frutos secos) 25 | 20 | 7.00 | bowl de granola; porciones e ingredientes varían |
| Postre del día | La La Latte (porción de postre) 18; Café Ciudad (porción de torta) 18; Tercer Espacio (torta) 18–25 | 16 | 5.60 | postre rotativo de temporada |

## Prueba del margen

**Margen bruto orientativo = (precio de venta – costo variable por unidad) / precio de venta × 100.** El «costo variable» debe incluir insumos, vaso/envase, servilletas y merma. La columna con el tope de 35% es un **objetivo de cálculo**, no una afirmación sobre los costos reales de MOOD.

**Ejemplo del espresso doble:** Una publicación de Café Ilapso de julio 2026 anuncia grano a Bs 200/kg. Una dosis hipotética de 18 g costaría Bs 3,60 solo en grano; al añadir envase y operación, hay que comprobar cuánto margen deja venderlo a Bs 14. No todos los cafés usan ese costo ni esa dosis.

**Ejemplo del Granola Bowl:** Hipermaxi Cochabamba publica yogur griego natural a Bs 27,50/L. Una porción hipotética de 150 ml cuesta aproximadamente Bs 4,13 de yogur, antes de agregar granola, fruta, envase y merma. Con precio MOOD de Bs 20, el objetivo de costo directo ≤ Bs 7 puede ser difícil si se incluyen muchas frutas o frutos secos; definir porciones es indispensable.

**Matcha:** Las materias primas varían enormemente por grado/calidad. Ever Green Bolivia publica matcha premium 100 g a Bs 140: 3 g hipotéticos representarían Bs 4,20 antes de leche de avena, miel y envase. Si usas calidad ceremonial genuina, mide costos antes de ofrecerlo a Bs 23.

**Recomendación comercial:** conservar opciones económicas (té Bs 8, limonada Bs 12, espresso Bs 14), mantener bebidas especiales en Bs 17–23 y snacks en Bs 20–21, sin sacrificar porciones o calidad. Revisar costos cada mes y precios de venta según cambios de insumos.

## Fuentes consultadas

- Caffinos (Cochabamba): https://cafe-cafinos.ola.click/products
- Tercer Espacio (Cochabamba): https://www.mercat.bo/tercer-espacio
- Oye Café (Cochabamba): https://www.mercat.bo/oye-cafe-paddel/
- La La Latte (Cochabamba): https://www.lalalattecoffee.com/carta
- Cofi (Bolivia; ubicación no verificada): https://cofi.ola.click/products
- Café Ciudad (Bolivia): https://cafeciudad.com.bo/menu/
- Hipermaxi Cochabamba (lácteos): https://www.hipermaxi.com/cochabamba/hipermaxi-blanco-galindo/categoria/lacteos-y-derivados/yogures
- Hipermaxi Cochabamba (leche): https://www.hipermaxi.com/cochabamba/hipermaxi-juan-de-la-rosa/categoria/lacteos-y-derivados/karpil-varios-sabores-200ml
- Café Ilapso (grano, publicación 2026): https://www.restaurants10.com/BO/Cochabamba/112596455022417/ilapso
- Ever Green Bolivia (matcha 100 g): https://www.evergreenbolivia.com/

## Integración en la web y Supabase

- Ya se actualizaron los 11 precios de reserva en `sistema/contenido.min.js`.
- Se actualizaron los 11 precios semilla del archivo `supabase/01-CONFIGURAR-MOOD.sql`, para que una instalación nueva no vuelva a valores antiguos.
- **Importante: Supabase tiene precios guardados que tienen prioridad sobre JavaScript.** Para que el catálogo conectado, el carrito, las confirmaciones y el panel utilicen estos nuevos precios, ejecutar `supabase/07-ACTUALIZAR-PRECIOS-NOVIEMBRE-2026.sql` en Supabase > SQL Editor y luego recargar MOOD con Ctrl+F5. Este cambio **no se ha ejecutado en la base remota**.
- El ajuste no cambia el costo de delivery ni altera las órdenes ya creadas.
