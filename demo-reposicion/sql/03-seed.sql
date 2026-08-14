-- =====================================================================
-- J6 · Datos de demostración
--
-- Las fechas son relativas a now(), así que la cola siempre tiene casos
-- vencidos sin importar el día en que se corra.
--
-- ANTES DE EJECUTAR: cambia el teléfono de 'demo-001' por el tuyo, en
-- formato E.164 (+58...). Es el único número al que llegará un mensaje
-- real durante la demo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Clientes
--
-- Los uuid van fijos a propósito. fn_bucket hashea el id del cliente, así
-- que con ids aleatorios la asignación de variante cambiaría en cada
-- ejecución del seed y la demo no sería reproducible. En producción los
-- ids ya son estables y esto no hace falta.
-- ---------------------------------------------------------------------
insert into customers (id, external_id, full_name, phone_e164, city, loyalty_tier, force_variant) values
  ('d0000000-0000-4000-8000-000000000001', 'demo-001', 'Sebastián Quijada', '+584140000000', 'Caracas',  'plata', 'treatment'),
  ('d0000000-0000-4000-8000-000000000002', 'demo-002', 'María Ferrer',       '+584141111111', 'Caracas',  'base',   null),
  ('d0000000-0000-4000-8000-000000000003', 'demo-003', 'Andrés Blanco',      '+584142222222', 'Valencia', 'oro',    null),
  ('d0000000-0000-4000-8000-000000000004', 'demo-004', 'Gabriela Ríos',      '+584143333333', 'Caracas',  'base',  'holdout'),
  ('d0000000-0000-4000-8000-000000000005', 'demo-005', 'Luis Peña',          '+584144444444', 'Maracay',  'plata',  null),
  ('d0000000-0000-4000-8000-000000000006', 'demo-006', 'Carolina Méndez',    '+584145555555', 'Caracas',  'base',   null)
on conflict (external_id) do nothing;

-- ---------------------------------------------------------------------
-- Mascotas
--
-- Los pesos y edades están elegidos para producir cadencias muy
-- distintas: de 18 a 33 días. Es justamente lo que hace inviable un
-- umbral fijo de "60 días sin comprar".
-- ---------------------------------------------------------------------
insert into pets (customer_id, name, specie, sex, birth_date, weight_kg)
select c.id, v.name, v.specie, v.sex, v.birth_date, v.weight_kg
from (values
  ('demo-001', 'Rocky',  'dog', 'male',   current_date - interval '4 years'  , 20.0),
  ('demo-002', 'Luna',   'cat', 'female', current_date - interval '3 years'  ,  4.0),
  ('demo-003', 'Simón',  'dog', 'male',   current_date - interval '5 years'  , 30.0),
  ('demo-004', 'Canela', 'dog', 'female', current_date - interval '7 months' ,  8.0),
  ('demo-005', 'Miel',   'cat', 'female', current_date - interval '11 years' ,  5.0),
  ('demo-006', 'Toby',   'dog', 'male',   current_date - interval '6 years'  , 12.0)
) as v(ext, name, specie, sex, birth_date, weight_kg)
join customers c on c.external_id = v.ext
where not exists (select 1 from pets p where p.customer_id = c.id and p.name = v.name);

-- ---------------------------------------------------------------------
-- Presentaciones
-- ---------------------------------------------------------------------
insert into presentations (sku, product_name, brand, specie, life_stage, weight_kg, price_gross, url) values
  ('DC-AMG-08', 'Adultos Medianos y Grandes con Carne y Pollo', 'Dog Chow',  'dog', 'adult',  8.000, 52.14, 'https://duwupetclub.com/productos/dog-chow-amg-8kg'),
  ('DC-AMG-20', 'Adultos Medianos y Grandes con Carne y Pollo', 'Dog Chow',  'dog', 'adult', 20.000, 89.20, 'https://duwupetclub.com/productos/dog-chow-amg-20kg'),
  ('DC-CAC-04', 'Gran Comienzo Cachorros Medianos y Grandes',   'Dog Chow',  'dog', 'puppy',  4.000, 30.89, 'https://duwupetclub.com/productos/dog-chow-cachorros-4kg'),
  ('DM-LMB-20', 'Lamb Meal & Rice Para Perro Adulto Raza Grande','Diamond',  'dog', 'adult', 20.000, 96.30, 'https://duwupetclub.com/productos/diamond-lamb-20kg'),
  ('HO-GAT-15', 'Alimento Para Gatitos Con Salmón',             'HappyOne',  'cat', 'adult',  1.500, 21.02, 'https://duwupetclub.com/productos/happyone-salmon-1-5kg'),
  ('CC-GAT-03', 'Gatitos Hasta 12 Meses Prebióticos',           'Cat Chow',  'cat', 'senior', 3.000, 18.40, 'https://duwupetclub.com/productos/cat-chow-3kg'),
  ('HO-PEQ-08', 'Razas Pequeñas con Pollo',                     'HappyOne',  'dog', 'adult',  8.000, 41.99, 'https://duwupetclub.com/productos/happyone-pequenas-8kg')
on conflict (sku) do nothing;

-- ---------------------------------------------------------------------
-- Pedidos
--
-- Caso A · Vencidos hoy, predicción por modelo de consumo
--   Rocky   20 kg × 0.020 = 400 g/día · saco 8 kg  → 20 días → aviso a los 15
--   Luna     4 kg × 0.020 =  80 g/día · bolsa 1.5  → 19 días → aviso a los 14
--   Canela   8 kg × 0.030 = 240 g/día · saco 4 kg  → 17 días → aviso a los 12
-- ---------------------------------------------------------------------
with nuevo as (
  insert into orders (customer_id, external_id, ordered_at, total_gross)
  select c.id, v.ext_order, now() - v.hace, v.total
  from (values
    ('demo-001', 'ord-001', interval '15 days', 52.14),
    ('demo-002', 'ord-002', interval '14 days', 21.02),
    ('demo-004', 'ord-004', interval '12 days', 30.89)
  ) as v(ext_cust, ext_order, hace, total)
  join customers c on c.external_id = v.ext_cust
  on conflict (external_id) do nothing
  returning id, external_id, customer_id
)
insert into order_items (order_id, presentation_id, pet_id, quantity, unit_price)
select n.id, pr.id, p.id, 1, pr.price_gross
from (values
  ('ord-001', 'DC-AMG-08', 'Rocky'),
  ('ord-002', 'HO-GAT-15', 'Luna'),
  ('ord-004', 'DC-CAC-04', 'Canela')
) as v(ext_order, sku, pet_name)
join nuevo n         on n.external_id = v.ext_order
join presentations pr on pr.sku       = v.sku
join pets p          on p.customer_id = n.customer_id and p.name = v.pet_name;

-- ---------------------------------------------------------------------
-- Caso B · Historial de 3 compras del mismo SKU
--
-- Simón consume en teoría 600 g/día → un saco de 20 kg debería durar 33
-- días. En la práctica compra cada 28. El intervalo observado le gana al
-- modelo y confidence pasa a 'observed'.
-- ---------------------------------------------------------------------
with nuevo as (
  insert into orders (customer_id, external_id, ordered_at, total_gross)
  select c.id, v.ext_order, now() - v.hace, 96.30
  from (values
    ('demo-003', 'ord-003a', interval '79 days'),
    ('demo-003', 'ord-003b', interval '51 days'),
    ('demo-003', 'ord-003c', interval '23 days')
  ) as v(ext_cust, ext_order, hace)
  join customers c on c.external_id = v.ext_cust
  on conflict (external_id) do nothing
  returning id, external_id, customer_id
)
insert into order_items (order_id, presentation_id, pet_id, quantity, unit_price)
select n.id, pr.id, p.id, 1, pr.price_gross
from nuevo n
join presentations pr on pr.sku = 'DM-LMB-20'
join pets p on p.customer_id = n.customer_id and p.name = 'Simón';

-- ---------------------------------------------------------------------
-- Caso C · Todavía no vencido — debe quedar FUERA de la cola
--
-- Miel: 5 kg × 0.018 = 90 g/día · bolsa 3 kg → 33 días → aviso a los 28.
-- Compró hace 20 días, así que aún no toca. Sirve para comprobar que el
-- filtro de fecha funciona y no se avisa a todo el mundo.
-- ---------------------------------------------------------------------
with nuevo as (
  insert into orders (customer_id, external_id, ordered_at, total_gross)
  select c.id, 'ord-005', now() - interval '20 days', 18.40
  from customers c where c.external_id = 'demo-005'
  on conflict (external_id) do nothing
  returning id, customer_id
)
insert into order_items (order_id, presentation_id, pet_id, quantity, unit_price)
select n.id, pr.id, p.id, 1, pr.price_gross
from nuevo n
join presentations pr on pr.sku = 'CC-GAT-03'
join pets p on p.customer_id = n.customer_id and p.name = 'Miel';

-- ---------------------------------------------------------------------
-- Caso D · Cliente que se dio de baja — debe quedar FUERA de la cola
--
-- Toby: 12 kg × 0.020 = 240 g/día · saco 8 kg → 33,3 días → aviso a los
-- 28,3. Compró hace 32 días, así que por fecha SÍ le tocaría. Queda
-- fuera únicamente por la baja de canal, que es lo que se quiere probar.
-- ---------------------------------------------------------------------
update customers
   set whatsapp_opt_in = false,
       opted_out_at    = now() - interval '5 days'
 where external_id = 'demo-006';

with nuevo as (
  insert into orders (customer_id, external_id, ordered_at, total_gross)
  select c.id, 'ord-006', now() - interval '32 days', 41.99
  from customers c where c.external_id = 'demo-006'
  on conflict (external_id) do nothing
  returning id, customer_id
)
insert into order_items (order_id, presentation_id, pet_id, quantity, unit_price)
select n.id, pr.id, p.id, 1, pr.price_gross
from nuevo n
join presentations pr on pr.sku = 'HO-PEQ-08'
join pets p on p.customer_id = n.customer_id and p.name = 'Toby';

-- =====================================================================
-- Comprobación
--
--   select pet_name, product_name, coverage_days, days_remaining,
--          confidence, variant, remaining_phrase
--     from v_reorder_queue;
--
-- Debe devolver 4 filas: Rocky, Luna, Canela y Simón.
-- Miel queda fuera por fecha; Toby, por baja de canal.
-- Gabriela (Canela) sale como 'holdout': se registra y no se envía.
-- =====================================================================
