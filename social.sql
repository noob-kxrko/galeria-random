-- Favoritos, reacciones y perfiles. Pégalo en Supabase > SQL Editor > Run (se puede repetir).
create table if not exists favorites (
  media_id uuid not null references media on delete cascade,
  user_id uuid not null default auth.uid(),
  created_at timestamptz default now(),
  primary key (media_id, user_id));
create table if not exists reactions (
  media_id uuid not null references media on delete cascade,
  user_id uuid not null default auth.uid(),
  emoji text not null check (char_length(emoji) <= 8),
  created_at timestamptz default now(),
  primary key (media_id, user_id, emoji));
create table if not exists profiles (
  id uuid primary key default auth.uid(),
  bio text check (char_length(bio) <= 160),
  updated_at timestamptz default now());

alter table favorites enable row level security;
alter table reactions enable row level security;
alter table profiles  enable row level security;

drop policy if exists "fav ver" on favorites;      drop policy if exists "fav crear" on favorites;      drop policy if exists "fav borrar" on favorites;
drop policy if exists "rx ver" on reactions;       drop policy if exists "rx crear" on reactions;       drop policy if exists "rx borrar" on reactions;
drop policy if exists "perfil ver" on profiles;    drop policy if exists "perfil crear" on profiles;    drop policy if exists "perfil editar" on profiles;

create policy "fav ver"    on favorites for select to authenticated using (user_id = auth.uid());   -- favoritos privados
create policy "fav crear"  on favorites for insert to authenticated with check (user_id = auth.uid());
create policy "fav borrar" on favorites for delete to authenticated using (user_id = auth.uid());
create policy "rx ver"     on reactions for select to authenticated using (true);
create policy "rx crear"   on reactions for insert to authenticated with check (user_id = auth.uid());
create policy "rx borrar"  on reactions for delete to authenticated using (user_id = auth.uid());
create policy "perfil ver"    on profiles for select to authenticated using (true);
create policy "perfil crear"  on profiles for insert to authenticated with check (id = auth.uid());
create policy "perfil editar" on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

grant select, insert, delete on favorites, reactions to authenticated;
grant select, insert, update on profiles to authenticated;
