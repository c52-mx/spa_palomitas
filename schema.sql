-- ============================================================
--  Palomitas · esquema Supabase (catalogo + config + pedidos)
--  Ejecutar en: Supabase > SQL Editor > New query > Run
--  Es idempotente: puedes correrlo mas de una vez.
-- ============================================================

-- ---------- TABLAS ----------
create table if not exists config (
  id                int primary key default 1,
  negocio           text,
  whatsapp_numero   text,
  pedido_minimo     int     default 5,
  anticipacion_dias int     default 1,
  tope_por_sabor    int     default 10,
  costo_envio       numeric default 30,
  anticipo_pct      numeric default 0.5,
  hora_abre         int     default 10,
  hora_cierra       int     default 22,
  horario           text    default '10:00 a 22:00 h',
  zonas             jsonb   default '[]'::jsonb,
  constraint config_single check (id = 1)
);

create table if not exists tamanos (
  id     text primary key,   -- chica | mediana | grande | extra_grande
  nombre text not null,
  orden  int default 0
);

create table if not exists precios_tamano (
  categoria text not null,          -- salado | dulce | icee
  tamano_id text not null references tamanos(id),
  precio    numeric not null,
  primary key (categoria, tamano_id)
);

create table if not exists sabores (
  id         text primary key,
  nombre     text not null,
  cat        text not null,          -- salado | dulce | icee
  icon       text,
  img        text,                   -- url de foto (opcional)
  badge      text,
  disponible boolean default true,
  stock      int,                    -- null = sin control de stock
  orden      int default 0
);

create table if not exists combos (
  id             text primary key,
  nombre         text not null,
  descripcion    text,
  precio         numeric not null,
  icon           text,
  badge          text,
  combo_hint     text,
  envio_incluido boolean default false,
  disponible     boolean default true,
  stock          int,
  orden          int default 0
);

create table if not exists extras (
  id          text primary key,
  nombre      text not null,
  descripcion text,
  precio      numeric not null,
  icon        text,
  cat         text default 'icee',
  disponible  boolean default true,
  stock       int,
  orden       int default 0
);

create table if not exists orders (
  id            uuid primary key default gen_random_uuid(),
  creado        timestamptz default now(),
  cliente       text,
  fecha_entrega date,
  entrega       text,
  zona          text,
  pago          text,
  items         jsonb,
  piezas        int,
  subtotal      numeric,
  envio         numeric,
  total         numeric,
  anticipo      numeric,
  notas         text,
  direccion     text,
  estatus       text default 'pendiente'   -- pendiente | confirmado | entregado | cancelado
);

-- ---------- RLS ----------
alter table config        enable row level security;
alter table tamanos       enable row level security;
alter table precios_tamano enable row level security;
alter table sabores       enable row level security;
alter table combos        enable row level security;
alter table extras        enable row level security;
alter table orders        enable row level security;

-- Catalogo: lectura publica, escritura solo admin autenticado
do $$
declare t text;
begin
  foreach t in array array['config','tamanos','precios_tamano','sabores','combos','extras'] loop
    execute format('drop policy if exists "%s_read"  on %I;', t, t);
    execute format('drop policy if exists "%s_write" on %I;', t, t);
    execute format('create policy "%s_read"  on %I for select to anon, authenticated using (true);', t, t);
    execute format('create policy "%s_write" on %I for all    to authenticated using (true) with check (true);', t, t);
  end loop;
end $$;

-- Pedidos: cualquiera puede registrar; solo admin lee y actualiza
drop policy if exists "orders_insert" on orders;
drop policy if exists "orders_read"   on orders;
drop policy if exists "orders_update" on orders;
create policy "orders_read"   on orders for select to authenticated using (true);
create policy "orders_update" on orders for update to authenticated using (true) with check (true);

-- ---------- SEED (catalogo actual) ----------
insert into config (id, negocio, whatsapp_numero, zonas) values
  (1, 'Las Palomitas de los Abuelos', '525566707620',
   '["Zona Heroes 1","Zona Heroes 2","Zona Heroes 3","Zona Heroes 4","Zona Heroes 5","Zona Heroes 6","Tecamac","Ojo de Agua (cobertura parcial)"]'::jsonb)
on conflict (id) do nothing;

-- migracion desde el modelo anterior por gramaje, si existia en una corrida previa
drop table if exists gramajes;

insert into tamanos (id, nombre, orden) values
  ('chica','Chica',1),
  ('mediana','Mediana',2),
  ('grande','Grande',3),
  ('extra_grande','Extra grande',4)
on conflict (id) do nothing;

insert into precios_tamano (categoria, tamano_id, precio) values
  ('salado','chica',15),  ('salado','mediana',25),  ('salado','grande',45),  ('salado','extra_grande',60),
  ('dulce','chica',25),   ('dulce','mediana',35),   ('dulce','grande',55),   ('dulce','extra_grande',80),
  ('icee','chica',25),    ('icee','mediana',35),    ('icee','grande',55),    ('icee','extra_grande',80)
on conflict (categoria, tamano_id) do nothing;

insert into sabores (id,nombre,cat,icon,badge,orden) values
  ('naturales','Naturales / saladas','salado','🍿',null,1),
  ('queso','Queso','salado','🧀','Popular',2),
  ('rufles','Rufles','salado','🥔',null,3),
  ('mantequilla','Mantequilla','salado','🧈',null,4),
  ('doritos','Doritos rojos','salado','🔺',null,5),
  ('takis','Takis','salado','🌶️',null,6),
  ('cremas','Cremas y especias','salado','🧂',null,7),
  ('chilelimon','Chile y limon','salado','🍋',null,8),
  ('esquites','Esquites','salado','🌽','Nuevo',9),
  ('caramelo','Caramelo','dulce','🍮','🔥 Mas vendido',10),
  ('chocolate','Chocolate','dulce','🍫','Popular',11),
  ('oreo','Galleta Oreo','dulce','🍪',null,12),
  ('quesocaramelo','Queso-caramelo','dulce','🍯',null,13),
  ('moraazul','Mora azul','dulce','🫐',null,14),
  ('uva','Uva','dulce','🍇',null,15),
  ('sandia','Sandia','dulce','🍉',null,16),
  ('picafresa','Picafresa','dulce','🍓',null,17),
  ('iceeazul','Icee azul','icee','🧊','Nuevo',18),
  ('iceerojo','Icee rojo','icee','🍒',null,19),
  ('iceecombinada','Icee combinada','icee','🌈',null,20)
on conflict (id) do nothing;

insert into combos (id,nombre,descripcion,precio,icon,badge,combo_hint,envio_incluido,orden) values
  ('combo-degustacion','Pack Degustacion','4 sabores de 150 g a elegir',299,'🎁','Envio incluido','Indica tus 4 sabores en Notas',true,1),
  ('combo-fiesta','Pack Fiesta','6 sabores de 200 g a elegir',549,'🎉','Para compartir','Indica tus 6 sabores en Notas',true,2),
  ('combo-cine','Combo Cine','2 palomitas 100 g + 2 refrescos',175,'🎬',null,'Indica sabores y refrescos en Notas',false,3)
on conflict (id) do nothing;

insert into extras (id,nombre,descripcion,precio,icon,cat,orden) values
  ('ex-refresco','Refresco en lata 355 ml','Cola, sabores o light',28,'🥤','icee',1),
  ('ex-agua','Agua 600 ml','Natural',18,'💧','icee',2),
  ('ex-dulces','Bolsa de dulces surtidos','Mix mexicano',35,'🍬','dulce',3)
on conflict (id) do nothing;

-- ============================================================
--  Validacion de costos del lado servidor
--  El sitio llama a crear_pedido(); los precios NUNCA vienen del cliente,
--  se recalculan desde el catalogo. Valida disponibilidad, stock y minimo.
-- ============================================================
drop policy if exists "orders_insert" on orders;  -- ya no se inserta directo; solo via funcion
drop function if exists crear_pedido(text,date,text,text,text,jsonb,text);

create or replace function crear_pedido(
  p_cliente text, p_fecha date, p_entrega text, p_zona text, p_pago text,
  p_items jsonb, p_notas text, p_direccion text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg config%rowtype;
  it jsonb;
  v_key text; v_qty int; v_tamano text; v_id text; v_cat text; v_tam_nombre text;
  v_precio numeric; v_nombre text; v_tipo text; v_hint text; v_env_incl boolean;
  v_disp boolean; v_stock int;
  arr jsonb := '[]'::jsonb;
  subtotal numeric := 0; piezas int := 0; unidades_pal int := 0;
  hay_combo boolean := false; envio_gratis boolean := false;
  es_envio boolean; envio numeric; total numeric; anticipo numeric; new_id uuid;
begin
  select * into cfg from config where id = 1;

  for it in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_key := it->>'key';
    v_qty := coalesce((it->>'qty')::int, 0);
    if v_qty <= 0 then continue; end if;

    if position(':' in v_key) > 0 then
      v_id     := split_part(v_key, ':', 1);
      v_tamano := split_part(v_key, ':', 2);
      select s.nombre, s.disponible, s.stock, s.cat into v_nombre, v_disp, v_stock, v_cat from sabores s where s.id = v_id;
      if v_nombre is null then raise exception 'Sabor no encontrado: %', v_id; end if;
      select pt.precio into v_precio from precios_tamano pt where pt.categoria = v_cat and pt.tamano_id = v_tamano;
      if v_precio is null then raise exception 'Tamano no valido: %', v_tamano; end if;
      select t.nombre into v_tam_nombre from tamanos t where t.id = v_tamano;
      v_nombre := v_nombre || ' ' || coalesce(v_tam_nombre, v_tamano); v_tipo := 'palomita'; v_hint := null; v_env_incl := false;
    else
      select nombre, precio, disponible, stock, combo_hint, envio_incluido, 'combo'
        into v_nombre, v_precio, v_disp, v_stock, v_hint, v_env_incl, v_tipo from combos where id = v_key;
      if v_nombre is null then
        select nombre, precio, disponible, stock, null::text, false, 'extra'
          into v_nombre, v_precio, v_disp, v_stock, v_hint, v_env_incl, v_tipo from extras where id = v_key;
      end if;
      if v_nombre is null then raise exception 'Producto no encontrado: %', v_key; end if;
    end if;

    if v_disp is false then raise exception 'No disponible: %', v_nombre; end if;
    if v_stock is not null and v_stock < v_qty then raise exception 'Sin stock suficiente: %', v_nombre; end if;

    subtotal := subtotal + v_precio * v_qty;
    piezas   := piezas + v_qty;
    if v_tipo = 'palomita' then unidades_pal := unidades_pal + v_qty; end if;
    if v_tipo = 'combo' then hay_combo := true; end if;
    if v_env_incl then envio_gratis := true; end if;

    arr := arr || jsonb_build_object('key',v_key,'nombre',v_nombre,'qty',v_qty,'importe',v_precio*v_qty,'tipo',v_tipo,'comboHint',v_hint);
  end loop;

  if piezas = 0 then raise exception 'Pedido vacio'; end if;
  if not (unidades_pal >= cfg.pedido_minimo or hay_combo) then
    raise exception 'Pedido minimo: % paquetes de palomitas o un combo', cfg.pedido_minimo;
  end if;

  es_envio := (p_entrega = 'envio');
  envio    := case when es_envio and not envio_gratis then cfg.costo_envio else 0 end;
  total    := subtotal + envio;
  anticipo := round(total * cfg.anticipo_pct);

  insert into orders (cliente,fecha_entrega,entrega,zona,pago,items,piezas,subtotal,envio,total,anticipo,notas,direccion,estatus)
  values (p_cliente, p_fecha, p_entrega, case when es_envio then p_zona else null end, p_pago, arr,
          piezas, subtotal, envio, total, anticipo, p_notas, case when es_envio then p_direccion else null end, 'pendiente')
  returning id into new_id;

  return jsonb_build_object('order_id',new_id,'items',arr,'piezas',piezas,'subtotal',subtotal,
    'envio',envio,'envio_gratis',envio_gratis,'total',total,'anticipo',anticipo,'es_envio',es_envio);
end $$;

grant execute on function crear_pedido(text,date,text,text,text,jsonb,text,text) to anon, authenticated;
