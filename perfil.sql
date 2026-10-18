-- Foto de perfil. Pégalo en Supabase > SQL Editor > Run (se puede repetir).
alter table profiles add column if not exists avatar_path text;
