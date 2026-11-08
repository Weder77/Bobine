-- Synchronisation des données de Bobine entre appareils.
--
-- Le serveur ne voit que des éléments opaques : `id` est une empreinte (HMAC)
-- calculée sur l'appareil et `payload` est chiffré sur l'appareil. Pour chaque
-- élément, il garde la version la plus récente (`modified_at`, horloge de
-- l'appareil en ms) et numérote les changements (`rev`) pour qu'un appareil ne
-- récupère que ce qui a bougé depuis sa dernière synchro.
--
-- Les appareils lisent et suppriment directement leurs lignes (RLS) ; ils
-- n'écrivent que par `sync_push`, qui applique « le plus récent gagne », le
-- quota et la numérotation.

create sequence public.sync_rev;

create table public.sync_items (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null check (char_length(id) between 16 and 128),
  modified_at bigint not null,
  deleted boolean not null default false,
  payload text not null check (char_length(payload) <= 16384),
  rev bigint not null default nextval('public.sync_rev'),
  primary key (user_id, id)
);

create index sync_items_user_rev on public.sync_items (user_id, rev);

alter table public.sync_items enable row level security;

create policy "sync_items: read own" on public.sync_items
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "sync_items: delete own" on public.sync_items
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.sync_items from anon, authenticated;
grant select, delete on public.sync_items to authenticated;

-- Envoie jusqu'à 500 éléments. Un élément n'en remplace un autre que s'il est
-- plus récent. Renvoie les versions du serveur qui ont gagné (plus récentes que
-- celles envoyées) pour que l'appareil les applique.
create function public.sync_push(items jsonb)
returns setof public.sync_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
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
  if (select count(*) from public.sync_items s where s.user_id = uid) > 50000 then
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

-- « Supprimer mon compte » : le compte et toutes ses données synchronisées.
create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
