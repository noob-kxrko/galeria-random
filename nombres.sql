-- Nombres de quien sube cada foto. Pégalo en Supabase > SQL Editor > Run (es corto y se puede repetir).
create or replace function user_names() returns table(id uuid, name text)
language sql security definer stable set search_path = public as $$
  select u.id, coalesce(nullif(trim(u.raw_user_meta_data->>'name'), ''), split_part(u.email, '@', 1))
  from auth.users u
$$;

revoke all on function user_names() from public, anon;
grant execute on function user_names() to authenticated;
