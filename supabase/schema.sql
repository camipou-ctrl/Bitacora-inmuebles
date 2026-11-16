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
  enlace     text,
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
