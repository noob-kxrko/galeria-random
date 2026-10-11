-- Galería de todos · SQL completo y repetible.
-- Pégalo en Supabase > SQL Editor > Run. Sirve aunque ya hayas ejecutado versiones anteriores.

create table if not exists albums (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  user_id uuid default auth.uid(),
  created_at timestamptz default now()
);
create table if not exists media (
  id uuid primary key default gen_random_uuid(),
  album_id uuid references albums on delete set null,
  user_id uuid not null default auth.uid(),
  author_name text,
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
alter table albums add column if not exists user_id uuid default auth.uid();
alter table media add column if not exists author_name text;
alter table comments add column if not exists author_name text;

-- Si venías de la versión con grupos, las columnas de grupo ya no son obligatorias
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='albums' and column_name='group_id') then
    alter table albums alter column group_id drop not null; end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='media' and column_name='group_id') then
    alter table media alter column group_id drop not null; end if;
end $$;

-- El nombre de quien sube o comenta lo pone el servidor (nadie puede falsificarlo)
create or replace function set_author() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.author_name := coalesce(
    (select nullif(trim(raw_user_meta_data->>'name'), '') from auth.users where id = auth.uid()),
    (select split_part(email, '@', 1) from auth.users where id = auth.uid()),
    'alguien');
  return new;
end $$;

drop trigger if exists media_author on media;
create trigger media_author before insert on media for each row execute function set_author();
drop trigger if exists comments_author on comments;
create trigger comments_author before insert on comments for each row execute function set_author();

-- Nombres para lo que ya estaba subido
update media set author_name = coalesce((select nullif(trim(raw_user_meta_data->>'name'), '') from auth.users u where u.id = media.user_id), 'alguien') where author_name is null;
update comments set author_name = coalesce((select nullif(trim(raw_user_meta_data->>'name'), '') from auth.users u where u.id = comments.user_id), 'alguien') where author_name is null;

alter table albums   enable row level security;
alter table media    enable row level security;
alter table comments enable row level security;

drop policy if exists "albumes ver" on albums;
drop policy if exists "albumes crear" on albums;
drop policy if exists "albumes borrar" on albums;
drop policy if exists "media ver" on media;
drop policy if exists "media subir" on media;
drop policy if exists "media borrar" on media;
drop policy if exists "comentarios ver" on comments;
drop policy if exists "comentarios crear" on comments;
drop policy if exists "comentarios borrar" on comments;

-- Todos los que hayan iniciado sesión ven todo; cada quien borra solo lo suyo
create policy "albumes ver"    on albums for select to authenticated using (true);
create policy "albumes crear"  on albums for insert to authenticated with check (user_id = auth.uid());
create policy "albumes borrar" on albums for delete to authenticated using (user_id = auth.uid());

create policy "media ver"    on media for select to authenticated using (true);
create policy "media subir"  on media for insert to authenticated with check (user_id = auth.uid());
create policy "media borrar" on media for delete to authenticated using (user_id = auth.uid());

create policy "comentarios ver"    on comments for select to authenticated using (true);
create policy "comentarios crear"  on comments for insert to authenticated with check (user_id = auth.uid());
create policy "comentarios borrar" on comments for delete to authenticated using (user_id = auth.uid());

-- Almacenamiento: cada quien sube a su carpeta (id de usuario); todos con sesión pueden ver
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', false)
on conflict do nothing;

drop policy if exists "fotos ver" on storage.objects;
drop policy if exists "fotos subir" on storage.objects;
drop policy if exists "fotos borrar" on storage.objects;

create policy "fotos ver" on storage.objects for select to authenticated
  using (bucket_id = 'fotos');
create policy "fotos subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "fotos borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and owner_id = auth.uid()::text);

grant usage on schema public to authenticated;
grant select, insert, delete on albums, media, comments to authenticated;
