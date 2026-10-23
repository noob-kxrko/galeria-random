-- Papelera, edición de descripciones y tiempo real. Pégalo en Supabase > SQL Editor > Run (se puede repetir).
alter table media add column if not exists deleted_at timestamptz;
create index if not exists media_created_idx on media (created_at desc);
create index if not exists media_album_idx on media (album_id);
create index if not exists comments_media_idx on comments (media_id);
create index if not exists reactions_media_idx on reactions (media_id);

drop policy if exists "media editar" on media;
create policy "media editar" on media for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant update on media to authenticated;

do $$ declare t text; begin
  foreach t in array array['media','reactions','comments'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t);
    exception when others then null; end;
  end loop;
end $$;
