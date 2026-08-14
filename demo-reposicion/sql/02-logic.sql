-- =====================================================================
-- J6 · Reposición predictiva — lógica de cálculo
--
-- Cadena completa:
--   peso de la mascota  →  gramos/día  →  días de cobertura  →  fecha de
--   aviso  →  cola de envío filtrada por opt-in, tope de frecuencia y
--   asignación de experimento.
--
-- Cada paso es una vista, para poder inspeccionarlo por separado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Etapa de vida derivada de la fecha de nacimiento.
-- STABLE, no IMMUTABLE: depende de current_date.
-- ---------------------------------------------------------------------
create or replace function fn_life_stage(p_specie text, p_birth_date date)
returns text
language sql
stable
as $$
  select case
    when p_birth_date is null then 'adult'          -- supuesto conservador
    when p_specie = 'dog' then
      case
        when age(current_date, p_birth_date) <  interval '12 months' then 'puppy'
        when age(current_date, p_birth_date) >= interval '7 years'   then 'senior'
        else 'adult'
      end
    when p_specie = 'cat' then
      case
        when age(current_date, p_birth_date) <  interval '12 months' then 'kitten'
        when age(current_date, p_birth_date) >= interval '10 years'  then 'senior'
        else 'adult'
      end
    else 'adult'
  end
$$;

-- ---------------------------------------------------------------------
-- Asignación determinista a bucket.
--
-- El mismo cliente cae siempre en el mismo bucket para una misma sal, así
-- que la pertenencia al holdout es estable entre ejecuciones y entre
-- reinicios. Cambiar la sal equivale a re-aleatorizar el experimento.
--
-- 7 caracteres hex = 28 bits, siempre positivo: no hace falta abs().
-- ---------------------------------------------------------------------
create or replace function fn_bucket(p_id uuid, p_salt text, p_buckets int default 100)
returns int
language sql
immutable
as $$
  select (('x' || substr(md5(p_id::text || p_salt), 1, 7))::bit(28)::int % p_buckets)
$$;

-- ---------------------------------------------------------------------
-- 1 · Consumo diario por mascota
-- ---------------------------------------------------------------------
create or replace view v_pet_daily_grams as
select
  p.id                                                  as pet_id,
  p.customer_id,
  p.name                                                as pet_name,
  p.specie,
  p.weight_kg,
  fn_life_stage(p.specie, p.birth_date)                 as life_stage,
  round(p.weight_kg * cf.body_weight_fraction * 1000, 1) as grams_per_day
from pets p
join consumption_factors cf
  on cf.specie     = p.specie
 and cf.life_stage = fn_life_stage(p.specie, p.birth_date)
where p.weight_kg is not null;

-- ---------------------------------------------------------------------
-- 2 · Última compra de alimento por (cliente, mascota, presentación)
-- ---------------------------------------------------------------------
create or replace view v_last_food_purchase as
select distinct on (o.customer_id, oi.pet_id, oi.presentation_id)
  o.customer_id,
  oi.pet_id,
  oi.presentation_id,
  o.ordered_at as last_ordered_at,
  oi.quantity
from orders o
join order_items  oi on oi.order_id        = o.id
join presentations pr on pr.id             = oi.presentation_id
where pr.is_food
order by o.customer_id, oi.pet_id, oi.presentation_id, o.ordered_at desc;

-- ---------------------------------------------------------------------
-- 3 · Intervalo observado de recompra
--
-- La mediana de días entre compras consecutivas del mismo SKU por el
-- mismo cliente. Con dos o más intervalos, este dato le gana al modelo:
-- refleja el consumo real de esa casa, incluidas las sobras, los premios
-- y el gato que también come del plato del perro.
-- ---------------------------------------------------------------------
create or replace view v_observed_interval as
with seq as (
  select
    o.customer_id,
    oi.presentation_id,
    o.ordered_at,
    lag(o.ordered_at) over (
      partition by o.customer_id, oi.presentation_id
      order by o.ordered_at
    ) as prev_ordered_at
  from orders o
  join order_items  oi on oi.order_id = o.id
  join presentations pr on pr.id      = oi.presentation_id
  where pr.is_food
)
select
  customer_id,
  presentation_id,
  count(*)                                                       as intervals,
  -- percentile_cont devuelve double precision; se normaliza a numeric
  -- aquí para que todo el resto de la cadena trabaje en un solo tipo.
  percentile_cont(0.5) within group (
    order by extract(epoch from (ordered_at - prev_ordered_at)) / 86400.0
  )::numeric                                                     as median_days
from seq
where prev_ordered_at is not null
group by customer_id, presentation_id;

-- ---------------------------------------------------------------------
-- 4 · Predicción de cobertura
--
-- Prioridad: intervalo observado (≥2 intervalos) sobre modelo de consumo.
-- confidence deja explícito de dónde salió el número, para poder medir
-- después si las predicciones observadas aciertan más que las modeladas.
-- ---------------------------------------------------------------------
create or replace view v_reorder_predictions as
select
  lp.customer_id,
  lp.pet_id,
  lp.presentation_id,
  lp.last_ordered_at,
  lp.quantity,
  pdg.pet_name,
  pdg.grams_per_day,
  pdg.life_stage,
  pr.product_name,
  pr.brand,
  pr.weight_kg              as presentation_kg,
  pr.url,
  oi.median_days            as observed_days,
  oi.intervals,
  case
    when pdg.grams_per_day > 0
    then round(pr.weight_kg * lp.quantity * 1000.0 / pdg.grams_per_day, 1)
  end                       as model_days,
  coalesce(
    case when oi.intervals >= 2 then round(oi.median_days, 1) end,
    case when pdg.grams_per_day > 0
         then round(pr.weight_kg * lp.quantity * 1000.0 / pdg.grams_per_day, 1) end
  )                         as coverage_days,
  case
    when oi.intervals >= 2      then 'observed'
    when pdg.grams_per_day > 0  then 'model'
    else 'none'
  end                       as confidence
from v_last_food_purchase lp
join presentations pr        on pr.id        = lp.presentation_id
left join v_pet_daily_grams pdg on pdg.pet_id = lp.pet_id
left join v_observed_interval oi
       on oi.customer_id     = lp.customer_id
      and oi.presentation_id = lp.presentation_id;

-- ---------------------------------------------------------------------
-- 5 · Fecha de aviso, variante y frase legible
--
-- El colchón de 5 días es la única constante arbitraria de la cadena.
-- Se avisa antes de que se acabe, no cuando ya se acabó: para entonces
-- el cliente ya fue a la tienda de la esquina.
-- ---------------------------------------------------------------------
create or replace view v_reorder_due as
select
  rp.*,
  (rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval)::date
    as depletion_date,
  (rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval - interval '5 days')::date
    as notify_date,
  ((rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval)::date - current_date)
    as days_remaining,
  fn_bucket(rp.customer_id, 'j6_reorder_v1', 100) as bucket,
  coalesce(
    c.force_variant,                              -- override de QA / demo
    case
      when fn_bucket(rp.customer_id, 'j6_reorder_v1', 100) < 20 then 'holdout'
      else 'treatment'
    end
  ) as variant,
  case
    when ((rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval)::date
          - current_date) <= 3  then 'muy poquito'
    when ((rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval)::date
          - current_date) <= 7  then 'una semana'
    when ((rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval)::date
          - current_date) <= 14 then 'dos semanas'
    else ((rp.last_ordered_at::date + (rp.coverage_days || ' days')::interval)::date
          - current_date)::text || ' días'
  end as remaining_phrase
from v_reorder_predictions rp
join customers c on c.id = rp.customer_id
where rp.coverage_days is not null;

-- ---------------------------------------------------------------------
-- 6 · Cola de envío
--
-- Aquí se aplican las tres reglas del presupuesto de atención:
--   · opt-in vigente
--   · sin repetir el mismo aviso en 21 días
--   · máximo 2 mensajes no transaccionales por semana
--
-- El holdout NO se filtra aquí: entra en la cola y se registra sin
-- enviar. Ese es todo el punto del grupo de control.
-- ---------------------------------------------------------------------
create or replace view v_reorder_queue as
select
  d.customer_id,
  c.full_name,
  c.first_name,
  c.phone_e164,
  d.pet_id,
  d.pet_name,
  d.presentation_id,
  d.product_name,
  d.brand,
  d.presentation_kg,
  d.url,
  d.coverage_days,
  d.days_remaining,
  d.remaining_phrase,
  d.confidence,
  d.notify_date,
  d.variant,
  d.bucket
from v_reorder_due d
join customers c on c.id = d.customer_id
where c.whatsapp_opt_in
  and c.opted_out_at is null
  and d.notify_date <= current_date
  and d.days_remaining > -30                    -- descarta rezagados muy viejos
  and not exists (
    select 1 from message_log m
    where m.customer_id     = d.customer_id
      and m.presentation_id = d.presentation_id
      and m.journey         = 'J6_reorder'
      and m.sent_at         > now() - interval '21 days'
  )
  and (
    select count(*) from message_log m2
    where m2.customer_id      = d.customer_id
      and m2.is_transactional = false
      and m2.sent_at          > now() - interval '7 days'
  ) < 2
order by d.days_remaining asc;

-- ---------------------------------------------------------------------
-- 7 · Lectura del experimento (X7)
--
-- Recompra dentro de la ventana, tratamiento contra control. Es la
-- consulta que responde si el journey aporta algo por encima de lo que
-- habría pasado igual.
-- ---------------------------------------------------------------------
create or replace view v_x7_results as
with touched as (
  select distinct on (m.customer_id, m.presentation_id)
    m.customer_id, m.presentation_id, m.variant, m.sent_at
  from message_log m
  where m.journey = 'J6_reorder'
  order by m.customer_id, m.presentation_id, m.sent_at desc
)
select
  t.variant,
  count(*)                                                   as clientes,
  count(*) filter (where r.reordered)                        as recompraron,
  round(100.0 * count(*) filter (where r.reordered) / nullif(count(*), 0), 1)
                                                             as tasa_pct
from touched t
left join lateral (
  select exists (
    select 1
    from orders o
    join order_items oi on oi.order_id = o.id
    where o.customer_id     = t.customer_id
      and oi.presentation_id = t.presentation_id
      and o.ordered_at between t.sent_at and t.sent_at + interval '14 days'
  ) as reordered
) r on true
group by t.variant;
