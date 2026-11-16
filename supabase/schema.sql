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
