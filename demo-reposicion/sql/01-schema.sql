-- =====================================================================
-- J6 · Reposición predictiva — esquema base
-- Postgres / Supabase
--
-- Modelo mínimo para calcular cuándo se le acaba el alimento a una
-- mascota y disparar un aviso de recompra. No pretende reemplazar el
-- catálogo real de Duwu: es la porción de datos que el journey necesita.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Clientes
-- ---------------------------------------------------------------------
create table if not exists customers (
  id              uuid primary key default gen_random_uuid(),
  external_id     text unique,                  -- id del cliente en Duwu
  full_name       text not null,
  first_name      text generated always as (split_part(full_name, ' ', 1)) stored,
  phone_e164      text not null,                -- formato +584141234567
  city            text,
  loyalty_tier    text not null default 'base',
  whatsapp_opt_in boolean not null default true,
  opted_out_at    timestamptz,
  -- Anula la asignación aleatoria del experimento. Solo para QA y demo:
  -- en producción debe estar en null para todo el mundo.
  force_variant   text check (force_variant in ('treatment', 'holdout')),
  created_at      timestamptz not null default now(),
  constraint phone_is_e164 check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$')
);

-- ---------------------------------------------------------------------
-- Mascotas
--
-- weight_kg y birth_date son los dos campos que habilitan todo el
-- cálculo. Son exactamente los que el journey J2 existe para capturar.
-- ---------------------------------------------------------------------
create table if not exists pets (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references customers(id) on delete cascade,
  name         text not null,
  specie       text not null check (specie in ('dog', 'cat')),
  sex          text check (sex in ('male', 'female')),
  birth_date   date,
  weight_kg    numeric(5,2) check (weight_kg > 0 and weight_kg < 120),
  is_neutered  boolean,
  created_at   timestamptz not null default now()
);

create index if not exists idx_pets_customer on pets(customer_id);

-- ---------------------------------------------------------------------
-- Presentaciones (SKU)
--
-- Una presentación es un producto en un tamaño concreto: "Dog Chow
-- Adultos M/G · 20 kg". weight_kg es la entrada del cálculo de cobertura.
-- ---------------------------------------------------------------------
create table if not exists presentations (
  id            uuid primary key default gen_random_uuid(),
  sku           text unique not null,
  product_name  text not null,
  brand         text,
  specie        text not null check (specie in ('dog', 'cat')),
  life_stage    text,                            -- para qué etapa está formulado
  weight_kg     numeric(6,3) not null check (weight_kg > 0),
  price_gross   numeric(10,2),
  is_food       boolean not null default true,   -- solo el alimento se repone por consumo
  url           text,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Pedidos
-- ---------------------------------------------------------------------
create table if not exists orders (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references customers(id) on delete cascade,
  external_id  text unique,
  ordered_at   timestamptz not null default now(),
  total_gross  numeric(10,2),
  created_at   timestamptz not null default now()
);

create index if not exists idx_orders_customer_date on orders(customer_id, ordered_at desc);

create table if not exists order_items (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references orders(id) on delete cascade,
  presentation_id uuid not null references presentations(id),
  pet_id          uuid references pets(id) on delete set null,  -- a qué mascota va, si se sabe
  quantity        int  not null default 1 check (quantity > 0),
  unit_price      numeric(10,2)
);

create index if not exists idx_order_items_order on order_items(order_id);
create index if not exists idx_order_items_pres on order_items(presentation_id);

-- ---------------------------------------------------------------------
-- Factores de consumo
--
-- Fracción del peso corporal que un animal consume en alimento seco por
-- día. Son valores de arranque en frío, deliberadamente generosos: es
-- preferible avisar unos días antes que unos días tarde. Se recalibran
-- solos en cuanto hay dos compras del mismo SKU (ver 02-logic.sql).
-- ---------------------------------------------------------------------
create table if not exists consumption_factors (
  specie               text not null,
  life_stage           text not null,
  body_weight_fraction numeric(6,4) not null,
  primary key (specie, life_stage)
);

insert into consumption_factors (specie, life_stage, body_weight_fraction) values
  ('dog', 'puppy',  0.0300),
  ('dog', 'adult',  0.0200),
  ('dog', 'senior', 0.0180),
  ('cat', 'kitten', 0.0280),
  ('cat', 'adult',  0.0200),
  ('cat', 'senior', 0.0180)
on conflict (specie, life_stage) do nothing;

-- ---------------------------------------------------------------------
-- Bitácora de mensajes
--
-- Una fila por intento de mensaje, incluidos los del grupo de control
-- (holdout), que se registran con status = 'suppressed' y no se envían.
-- Sin esas filas no se puede medir incrementalidad.
-- ---------------------------------------------------------------------
create table if not exists message_log (
  id                  uuid primary key default gen_random_uuid(),
  customer_id         uuid not null references customers(id) on delete cascade,
  pet_id              uuid references pets(id) on delete set null,
  presentation_id     uuid references presentations(id) on delete set null,
  journey             text not null,               -- 'J6_reorder'
  channel             text not null default 'whatsapp',
  variant             text not null check (variant in ('treatment', 'holdout')),
  template_name       text,
  is_transactional    boolean not null default false,
  status              text not null default 'queued'
                        check (status in ('queued','sent','delivered','read',
                                          'replied','failed','suppressed')),
  provider_message_id text,
  error_reason        text,
  payload             jsonb,
  sent_at             timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_msg_customer_date on message_log(customer_id, sent_at desc);
create index if not exists idx_msg_journey       on message_log(journey, sent_at desc);
create index if not exists idx_msg_provider_id   on message_log(provider_message_id);

-- ---------------------------------------------------------------------
-- Nota sobre RLS
--
-- En Supabase estas tablas deben quedar con Row Level Security activo y
-- accederse solo con la service role desde n8n. Ninguna de ellas debe ser
-- legible desde el cliente: contienen teléfonos y asignación de
-- experimento.
-- ---------------------------------------------------------------------
alter table customers      enable row level security;
alter table pets           enable row level security;
alter table orders         enable row level security;
alter table order_items    enable row level security;
alter table message_log    enable row level security;
