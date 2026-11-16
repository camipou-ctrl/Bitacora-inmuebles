-- Bitácora de Inmuebles: tablas y seguridad.
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Cada usuario ve y modifica únicamente sus propios registros (RLS).

create table if not exists public.inmuebles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  titulo     text not null,
  fecha      date not null default current_date,
  tipo       text,
  operacion  text,
  zona       text,
  precio     numeric,
  captador   text,
  enlace     text,
  enlace_novus text,
  estado     text not null default 'Activa',
  notas      text,
  creado     timestamptz not null default now()
);

create table if not exists public.atenciones (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  cliente      text not null,
  contacto     text,
  fecha        date not null default current_date,
  inmueble_id  uuid references public.inmuebles (id) on delete set null,
  canal        text,
  resultado    text,
  seguimiento  date,
  hecho        boolean not null default false,
  notas        text,
  creado       timestamptz not null default now()
);

create index if not exists inmuebles_user_fecha on public.inmuebles (user_id, fecha desc);
create index if not exists atenciones_user_fecha on public.atenciones (user_id, fecha desc);
create index if not exists atenciones_inmueble on public.atenciones (inmueble_id);

alter table public.inmuebles enable row level security;
alter table public.atenciones enable row level security;

drop policy if exists "inmuebles propios" on public.inmuebles;
create policy "inmuebles propios" on public.inmuebles
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "atenciones propias" on public.atenciones;
create policy "atenciones propias" on public.atenciones
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Permisos: solo usuarios con sesión iniciada; sin sesión no hay acceso.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.inmuebles to authenticated;
grant select, insert, update, delete on public.atenciones to authenticated;
revoke all on public.inmuebles from anon;
revoke all on public.atenciones from anon;

-- Columnas agregadas después de la primera versión (para bases ya creadas).
alter table public.inmuebles add column if not exists captador text;
alter table public.inmuebles add column if not exists enlace_novus text;

-- Perfiles y rol de supervisor: un supervisor ve los registros de todos, en solo lectura.
create table if not exists public.perfiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  nombre  text not null,
  rol     text not null default 'asistente' check (rol in ('asistente', 'supervisor'))
);
alter table public.perfiles enable row level security;

create schema if not exists privado;

create or replace function privado.es_supervisor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfiles p
    where p.user_id = (select auth.uid()) and p.rol = 'supervisor'
  );
$$;

revoke all on function privado.es_supervisor() from public, anon;
grant usage on schema privado to authenticated;
grant execute on function privado.es_supervisor() to authenticated;

revoke all on public.perfiles from anon;
revoke all on public.perfiles from authenticated;
grant select on public.perfiles to authenticated;

drop policy if exists "perfil propio o supervisor" on public.perfiles;
create policy "perfil propio o supervisor" on public.perfiles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select privado.es_supervisor()));

drop policy if exists "supervisor ve inmuebles" on public.inmuebles;
create policy "supervisor ve inmuebles" on public.inmuebles
  for select to authenticated
  using ((select privado.es_supervisor()));

drop policy if exists "supervisor ve atenciones" on public.atenciones;
create policy "supervisor ve atenciones" on public.atenciones
  for select to authenticated
  using ((select privado.es_supervisor()));

-- Para dar de alta a alguien después de crear su usuario en Authentication > Users:
--   insert into public.perfiles (user_id, nombre, rol)
--   select id, 'Nombre', 'supervisor' from auth.users where email = 'correo@ejemplo.com';

-- ===== Equipo: edición compartida, avisos en vivo y tipo de atención =====
-- Toda persona con fila en public.perfiles ve y edita todos los registros.
create or replace function privado.es_miembro()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.perfiles p where p.user_id = (select auth.uid()));
$$;
revoke all on function privado.es_miembro() from public, anon;
grant execute on function privado.es_miembro() to authenticated;

drop policy if exists "inmuebles propios" on public.inmuebles;
drop policy if exists "supervisor ve inmuebles" on public.inmuebles;
drop policy if exists "equipo inmuebles" on public.inmuebles;
create policy "equipo inmuebles" on public.inmuebles
  for all to authenticated
  using ((select privado.es_miembro()))
  with check ((select privado.es_miembro()));

drop policy if exists "atenciones propias" on public.atenciones;
drop policy if exists "supervisor ve atenciones" on public.atenciones;
drop policy if exists "equipo atenciones" on public.atenciones;
create policy "equipo atenciones" on public.atenciones
  for all to authenticated
  using ((select privado.es_miembro()))
  with check ((select privado.es_miembro()));

drop policy if exists "perfil propio o supervisor" on public.perfiles;
drop policy if exists "perfiles del equipo" on public.perfiles;
create policy "perfiles del equipo" on public.perfiles
  for select to authenticated
  using ((select privado.es_miembro()));

alter table public.inmuebles  add column if not exists editado timestamptz, add column if not exists editado_por uuid;
alter table public.atenciones add column if not exists editado timestamptz, add column if not exists editado_por uuid;

create or replace function privado.marcar_edicion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.editado := now();
  new.editado_por := (select auth.uid());
  return new;
end;
$$;

drop trigger if exists inmuebles_marcar_edicion on public.inmuebles;
create trigger inmuebles_marcar_edicion before update on public.inmuebles
  for each row execute function privado.marcar_edicion();
drop trigger if exists atenciones_marcar_edicion on public.atenciones;
create trigger atenciones_marcar_edicion before update on public.atenciones
  for each row execute function privado.marcar_edicion();

alter table public.atenciones add column if not exists tipo text not null default 'Consulta';

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'inmuebles') then
    alter publication supabase_realtime add table public.inmuebles;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'atenciones') then
    alter publication supabase_realtime add table public.atenciones;
  end if;
end $$;

-- ===== Lista de agentes para el desplegable de Captador =====
-- Los nombres se cargan directo en la base (no van en el repositorio).
create table if not exists public.agentes (
  nombre  text primary key,
  agencia text,
  activo  boolean not null default true
);
alter table public.agentes enable row level security;
revoke all on public.agentes from anon;
revoke all on public.agentes from authenticated;
grant select on public.agentes to authenticated;
drop policy if exists "agentes para el equipo" on public.agentes;
create policy "agentes para el equipo" on public.agentes
  for select to authenticated
  using ((select privado.es_miembro()));

-- ===== Notificaciones push =====
-- La función supabase/functions/notificar envía los avisos. Las claves VAPID las genera
-- esa función la primera vez y quedan en push_config; el secreto se genera aquí mismo.
create extension if not exists pg_net with schema extensions;

create table if not exists public.suscripciones_push (
  endpoint text primary key,
  user_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  p256dh   text not null,
  auth     text not null,
  creado   timestamptz not null default now()
);
create index if not exists suscripciones_push_user on public.suscripciones_push (user_id);
alter table public.suscripciones_push enable row level security;
revoke all on public.suscripciones_push from anon;
revoke all on public.suscripciones_push from authenticated;
grant select, insert, update, delete on public.suscripciones_push to authenticated;
drop policy if exists "suscripciones propias" on public.suscripciones_push;
create policy "suscripciones propias" on public.suscripciones_push
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and (select privado.es_miembro()));

-- Sin políticas: solo la usa el servidor.
create table if not exists public.push_config (
  id      int primary key default 1 check (id = 1),
  secreto text not null,
  url     text not null,
  vapid   jsonb
);
alter table public.push_config enable row level security;
revoke all on public.push_config from anon;
revoke all on public.push_config from authenticated;

grant select, update on public.push_config to service_role;
grant select, delete on public.suscripciones_push to service_role;
grant select on public.perfiles to service_role;

-- Cambia la URL por la de tu proyecto.
insert into public.push_config (id, secreto, url)
values (1, encode(extensions.gen_random_bytes(32), 'hex'), 'https://TU-PROYECTO.supabase.co/functions/v1/notificar')
on conflict (id) do nothing;

create or replace function privado.avisar_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid := (select auth.uid());
  v_cfg    record;
  v_fila   jsonb;
begin
  if v_actor is null then return null; end if;
  select secreto, url into v_cfg from public.push_config where id = 1;
  if v_cfg.secreto is null then return null; end if;
  if tg_op = 'DELETE' then v_fila := to_jsonb(old); else v_fila := to_jsonb(new); end if;
  perform net.http_post(
    url := v_cfg.url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-bitacora-secreto', v_cfg.secreto),
    body := jsonb_build_object(
      'tabla', tg_table_name,
      'tipo', tg_op,
      'actor', v_actor,
      'titulo', coalesce(v_fila ->> 'titulo', v_fila ->> 'cliente', '')
    ),
    timeout_milliseconds := 8000
  );
  return null;
exception when others then
  return null; -- un fallo del aviso nunca debe impedir guardar
end;
$$;
revoke all on function privado.avisar_push() from public, anon, authenticated;

drop trigger if exists inmuebles_avisar_push on public.inmuebles;
create trigger inmuebles_avisar_push after insert or update or delete on public.inmuebles
  for each row execute function privado.avisar_push();
drop trigger if exists atenciones_avisar_push on public.atenciones;
create trigger atenciones_avisar_push after insert or update or delete on public.atenciones
  for each row execute function privado.avisar_push();
