-- Galería compartida · SQL completo y repetible.
-- Pégalo en Supabase > SQL Editor > Run. Sirve aunque ya hayas ejecutado la versión anterior.

create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text unique not null default substr(md5(random()::text), 1, 8),
  created_by uuid default auth.uid(),
  created_at timestamptz default now()
);
create table if not exists members (
  group_id uuid references groups on delete cascade,
  user_id uuid references auth.users on delete cascade,
  display_name text,
  primary key (group_id, user_id)
);
create table if not exists albums (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups on delete cascade,
  name text not null,
  created_at timestamptz default now()
);
create table if not exists media (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups on delete cascade,
  album_id uuid references albums on delete set null,
  user_id uuid not null default auth.uid(),
  path text not null,
  kind text not null check (kind in ('image', 'video')),
  caption text,
  created_at timestamptz default now()
);
create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references media on delete cascade,
  user_id uuid not null default auth.uid(),
  author_name text,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz default now()
);

-- Espacio personal: group_id puede ser nulo
alter table albums alter column group_id drop not null;
alter table media  alter column group_id drop not null;
alter table albums add column if not exists user_id uuid default auth.uid();

create or replace function is_member(gid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from members where group_id = gid and user_id = auth.uid())
$$;

create or replace function can_see_media(mid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from media m where m.id = mid
    and (m.user_id = auth.uid() or (m.group_id is not null and is_member(m.group_id))))
$$;

create or replace function create_group(gname text, dname text) returns groups
language plpgsql security definer set search_path = public as $$
declare g groups;
begin
  insert into groups (name) values (gname) returning * into g;
  insert into members (group_id, user_id, display_name) values (g.id, auth.uid(), dname);
  return g;
end $$;

create or replace function join_group(code text, dname text) returns groups
language plpgsql security definer set search_path = public as $$
declare g groups;
begin
  select * into g from groups where invite_code = lower(trim(code));
  if g.id is null then raise exception 'Código inválido'; end if;
  insert into members (group_id, user_id, display_name) values (g.id, auth.uid(), dname)
  on conflict do nothing;
  return g;
end $$;

alter table groups   enable row level security;
alter table members  enable row level security;
alter table albums   enable row level security;
alter table media    enable row level security;
alter table comments enable row level security;

drop policy if exists "ver grupo" on groups;
drop policy if exists "ver miembros" on members;
drop policy if exists "salir" on members;
drop policy if exists "albumes ver" on albums;
drop policy if exists "albumes crear" on albums;
drop policy if exists "albumes borrar" on albums;
drop policy if exists "media ver" on media;
drop policy if exists "media subir" on media;
drop policy if exists "media borrar" on media;
drop policy if exists "comentarios ver" on comments;
drop policy if exists "comentarios crear" on comments;
drop policy if exists "comentarios borrar" on comments;

create policy "ver grupo"    on groups  for select using (is_member(id));
create policy "ver miembros" on members for select using (is_member(group_id));
create policy "salir"        on members for delete using (user_id = auth.uid());

create policy "albumes ver" on albums for select using (
  (group_id is null and user_id = auth.uid()) or (group_id is not null and is_member(group_id)));
create policy "albumes crear" on albums for insert with check (
  (group_id is null and user_id = auth.uid()) or (group_id is not null and is_member(group_id)));
create policy "albumes borrar" on albums for delete using (
  (group_id is null and user_id = auth.uid()) or (group_id is not null and is_member(group_id)));

create policy "media ver" on media for select using (
  user_id = auth.uid() or (group_id is not null and is_member(group_id)));
create policy "media subir" on media for insert with check (
  user_id = auth.uid() and (group_id is null or is_member(group_id)));
create policy "media borrar" on media for delete using (user_id = auth.uid());

create policy "comentarios ver"    on comments for select using (can_see_media(media_id));
create policy "comentarios crear"  on comments for insert with check (user_id = auth.uid() and can_see_media(media_id));
create policy "comentarios borrar" on comments for delete using (user_id = auth.uid());

-- Almacenamiento privado: carpeta = id del grupo (compartido) o id del usuario (personal)
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', false)
on conflict do nothing;

drop policy if exists "fotos ver" on storage.objects;
drop policy if exists "fotos subir" on storage.objects;
drop policy if exists "fotos borrar" on storage.objects;

create policy "fotos ver" on storage.objects for select using (
  bucket_id = 'fotos' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or is_member(((storage.foldername(name))[1])::uuid)));
create policy "fotos subir" on storage.objects for insert with check (
  bucket_id = 'fotos' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or is_member(((storage.foldername(name))[1])::uuid)));
create policy "fotos borrar" on storage.objects for delete using (
  bucket_id = 'fotos' and owner_id = auth.uid()::text);

grant usage on schema public to authenticated;
grant select, insert, update, delete on groups, members, albums, media, comments to authenticated;
grant execute on function is_member(uuid), can_see_media(uuid), create_group(text, text), join_group(text, text) to authenticated;
