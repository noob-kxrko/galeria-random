-- Mejoras: papelera, renombrar álbumes, subir solo a tu carpeta, tiempo real y lista de correos permitidos.
-- Pégalo en Supabase > SQL Editor > Run (se puede repetir).

-- 1) Papelera (7 días) y editar descripción de tus propias fotos
alter table media add column if not exists deleted_at timestamptz;
drop policy if exists "media editar" on media;
create policy "media editar" on media for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant update (caption, deleted_at) on media to authenticated;

-- 2) Renombrar tus álbumes
drop policy if exists "albumes editar" on albums;
create policy "albumes editar" on albums for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant update (name) on albums to authenticated;

-- 3) Solo se puede registrar un archivo que esté en tu propia carpeta
drop policy if exists "media subir" on media;
create policy "media subir" on media for insert to authenticated
  with check (user_id = auth.uid() and (storage.foldername(path))[1] = auth.uid()::text);

-- 4) Tiempo real (fotos, reacciones y comentarios nuevos aparecen solos)
do $$ begin
  begin alter publication supabase_realtime add table media;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table reactions; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table comments;  exception when duplicate_object then null; end;
end $$;

-- 5) Lista de correos permitidos. Mientras la tabla esté vacía, el registro sigue abierto.
-- Primero agrega los correos, por ejemplo:
--   insert into allowed_emails values ('tucorreo@gmail.com'), ('jennifer@gmail.com') on conflict do nothing;
create table if not exists allowed_emails (email text primary key);
alter table allowed_emails enable row level security;  -- sin políticas: nadie la lee desde la web
create or replace function check_allowed_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from allowed_emails) and not exists (select 1 from allowed_emails where lower(email) = lower(new.email)) then
    raise exception 'Este correo no está autorizado para esta galería';
  end if;
  return new;
end $$;
drop trigger if exists allowed_email_check on auth.users;
create trigger allowed_email_check before insert on auth.users for each row execute function public.check_allowed_email();

-- 6) Miniaturas compartidas: cualquier miembro puede CREAR (no reemplazar) la miniatura .t.jpg de una foto o video.
-- Así, quien abra la galería primero deja listas las portadas para todos.
drop policy if exists "fotos miniaturas" on storage.objects;
create policy "fotos miniaturas" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and name like '%.t.jpg');
