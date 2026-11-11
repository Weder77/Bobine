-- Limites du compte de synchro, mesurées en octets plutôt qu'en lignes, et
-- débit des envois.
--
-- Avant : 50 000 lignes de 16 Ko (800 Mo) par compte, suppressions comprises
-- et gardées pour toujours, sans limite de débit. Une fois le quota atteint,
-- rien ne le faisait redescendre.
--
-- Maintenant :
-- * les suppressions de plus de 180 jours sont effacées (un appareil resté
--   éteint plus longtemps garde simplement l'élément ; une liaison neuve ne
--   renvoie pas ce qu'il a supprimé hors connexion, voir le client) ;
-- * le quota porte sur les éléments vivants : 20 Mo de contenu chiffré et
--   20 000 éléments ;
-- * 60 envois par minute et par compte au plus.

create table public.sync_rate (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start timestamptz not null,
  pushes integer not null
);

alter table public.sync_rate enable row level security;
revoke all on public.sync_rate from anon, authenticated;

create or replace function public.sync_push(items jsonb)
returns setof public.sync_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  live_items bigint;
  live_bytes bigint;
  incoming_bytes bigint;
  recent integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) > 500 then
    raise exception 'items: array of at most 500 elements expected' using errcode = '22023';
  end if;
  -- One push at a time per account: revs are then committed in order and a
  -- device reading "rev > cursor" can never skip a change still in flight.
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  -- Rate: a window of one minute per account.
  insert into public.sync_rate as r (user_id, window_start, pushes)
  values (uid, now(), 1)
  on conflict (user_id) do update
    set window_start = case when r.window_start < now() - interval '1 minute' then now() else r.window_start end,
        pushes = case when r.window_start < now() - interval '1 minute' then 1 else r.pushes + 1 end
  returning pushes into recent;
  if recent > 60 then
    raise exception 'sync rate exceeded' using errcode = '54000';
  end if;

  -- Old deletions no longer count, nor stay.
  delete from public.sync_items s
  where s.user_id = uid
    and s.deleted
    and s.modified_at < (extract(epoch from now()) * 1000)::bigint - 180::bigint * 86400000;

  select count(*), coalesce(sum(char_length(s.payload)), 0)
  into live_items, live_bytes
  from public.sync_items s
  where s.user_id = uid and not s.deleted;
  select coalesce(sum(char_length(i.payload)), 0)
  into incoming_bytes
  from jsonb_to_recordset(items) as i (payload text, deleted boolean)
  where not coalesce(i.deleted, false);
  if live_items > 20000 or live_bytes + incoming_bytes > 20 * 1024 * 1024 then
    raise exception 'sync quota exceeded' using errcode = '54000';
  end if;

  return query
  with input as (
    select distinct on (i.id) i.id, i.modified_at, coalesce(i.deleted, false) as deleted, i.payload
    from jsonb_to_recordset(items) as i (id text, modified_at bigint, deleted boolean, payload text)
    order by i.id, i.modified_at desc
  ),
  written as (
    insert into public.sync_items as s (user_id, id, modified_at, deleted, payload, rev)
    select uid, input.id, input.modified_at, input.deleted, input.payload, nextval('public.sync_rev')
    from input
    on conflict (user_id, id) do update
      set modified_at = excluded.modified_at,
          deleted = excluded.deleted,
          payload = excluded.payload,
          rev = excluded.rev
      where excluded.modified_at > s.modified_at
    returning s.id
  )
  -- Same snapshot as before the insert: rows not written are unchanged.
  select s.*
  from public.sync_items s
  join input on input.id = s.id
  where s.user_id = uid
    and s.modified_at > input.modified_at
    and not exists (select 1 from written w where w.id = s.id);
end
$$;

revoke execute on function public.sync_push(jsonb) from public, anon;
grant execute on function public.sync_push(jsonb) to authenticated;
