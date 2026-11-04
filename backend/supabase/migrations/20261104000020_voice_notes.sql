-- Voice notes: a message can carry up to 30 seconds of audio, recorded on a
-- display (through the voice service) or in the app.
--
-- The audio is a WAV (16 kHz mono, 16-bit: about 960 KB for 30 s) in the
-- private `voice-notes` bucket, at <the sender's auth user>/<uuid>.wav:
-- a paired display or an admin uploads into their own folder and reads
-- everyone's (signed links). The message names it (`audio_path`) with its
-- length (`audio_ms`). Its `body` stays required: with no caption the server
-- writes "🎤 Voice note · 0:12", which older screens show as text and
-- the notification shows as it is.
--
-- send_message gains the two arguments (defaulted, so a call naming only
-- the first three still resolves); the three-argument one goes, since two
-- would make every PostgREST call ambiguous. Audio outlives its message when
-- the message is pruned after a year.

alter table public.messages
  add column audio_path text check (audio_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.wav$'),
  add column audio_ms   int  check (audio_ms between 300 and 31000),
  add check ((audio_path is null) = (audio_ms is null));

-- What a voice note says without a caption, as every screen writes it too.
create function public.voice_note_label(ms int)
returns text
language sql immutable set search_path = public as $$
  select '🎤 Voice note · ' || (round(ms / 1000.0)::int / 60)::text || ':' || lpad((round(ms / 1000.0)::int % 60)::text, 2, '0')
$$;

drop function public.send_message(text, text, text);

-- As before (20261103000010), and: `audio_path` a WAV this caller uploaded
-- to voice-notes (its own folder; it must be there), `audio_ms` its length,
-- 0.3 to 31 s. With audio the body is an optional caption.
create function public.send_message(body text default null, sender_name text default null, via text default null,
                                    audio_path text default null, audio_ms int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b text;
  kind text;
  who text;
  channel text;
  device uuid;
  device_name text;
  names text[];
  found_object boolean;
  m public.messages;
begin
  if public.is_device() then
    kind := 'display';
    channel := 'display';
    select d.id, d.name into device, device_name from public.devices d where d.user_id = auth.uid();
    select s.message_names into names from public.platform_settings s limit 1;
    if btrim(coalesce(send_message.sender_name, '')) <> '' and cardinality(coalesce(names, '{}')) > 0 then
      select n into who from unnest(names) n where lower(n) = lower(btrim(send_message.sender_name));
      if who is null then
        raise exception 'pick who is writing: %', array_to_string(names, ', ');
      end if;
    end if;
    who := left(coalesce(who, nullif(btrim(device_name), ''), 'Home'), 40);
    if (select count(*) from public.messages x where x.device_id = device and x.created_at > now() - interval '1 minute') >= 10 then
      raise exception 'slow down: wait a minute before sending another message';
    end if;
    if (select count(*) from public.messages x where x.device_id = device and x.created_at > now() - interval '1 hour') >= 60 then
      raise exception 'that''s a lot of messages: wait a while before sending more';
    end if;
  elsif public.is_platform_admin() and not public.is_service_role() and auth.uid() is not null then
    kind := 'person';
    channel := case when send_message.via = 'console' then 'console' else 'app' end;
    select p.message_name into who from public.profiles p where p.id = auth.uid();
    who := coalesce(who, 'Parent');
  else
    raise exception 'only a paired display or an admin can send a message';
  end if;

  if send_message.audio_path is not null or send_message.audio_ms is not null then
    if send_message.audio_path is null or send_message.audio_ms is null then
      raise exception 'a voice note needs its file and its length';
    end if;
    if send_message.audio_path !~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.wav$') then
      raise exception 'that voice note isn''t yours to send';
    end if;
    if send_message.audio_ms not between 300 and 31000 then
      raise exception 'a voice note is up to 30 seconds';
    end if;
    -- Plain Postgres (the tests) has no storage schema.
    if to_regclass('storage.objects') is not null then
      execute 'select exists (select 1 from storage.objects o where o.bucket_id = ''voice-notes'' and o.name = $1)'
        into found_object using send_message.audio_path;
      if not found_object then raise exception 'that voice note hasn''t been uploaded'; end if;
    end if;
  end if;

  b := replace(regexp_replace(coalesce(send_message.body, ''), '\r\n?', E'\n', 'g'), E'\t', ' ');
  b := regexp_replace(b, '[ ]+\n', E'\n', 'g');
  b := btrim(regexp_replace(b, '\n{3,}', E'\n\n', 'g'), E' \n');
  if b ~ '[\x01-\x09\x0b-\x1f\x7f]' then raise exception 'a message can''t hold control characters'; end if;
  if length(b) = 0 and send_message.audio_path is not null then b := public.voice_note_label(send_message.audio_ms); end if;
  if length(b) = 0 then raise exception 'write something to send'; end if;
  if length(b) > 500 then raise exception 'a message can be at most 500 characters'; end if;

  insert into public.messages (sender_kind, sender_name, body, device_id, author, via, audio_path, audio_ms)
  values (kind, who, b, device, auth.uid(), channel, send_message.audio_path, send_message.audio_ms)
  returning * into m;
  delete from public.messages x where x.created_at < now() - interval '365 days';
  return to_jsonb(m);
end $$;

revoke execute on function public.send_message(text, text, text, text, int) from public, anon;
grant execute on function public.send_message(text, text, text, text, int) to authenticated;

-- The bucket: private, WAVs of up to 1.5 MB. Displays and admins upload into
-- their own folder and read every voice note (to sign links for it).
do $$
begin
  if to_regclass('storage.buckets') is not null then
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
               values ('voice-notes', 'voice-notes', false, 1572864, array['audio/wav', 'audio/x-wav', 'audio/wave'])
               on conflict (id) do nothing$q$;
    execute $q$create policy voice_notes_upload on storage.objects for insert to authenticated
               with check (bucket_id = 'voice-notes' and public.can_read()
                           and (storage.foldername(name))[1] = auth.uid()::text)$q$;
    execute $q$create policy voice_notes_read on storage.objects for select to authenticated
               using (bucket_id = 'voice-notes' and public.can_read())$q$;
  end if;
end $$;
