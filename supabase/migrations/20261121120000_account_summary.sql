-- Ce que l'espace compte du site affiche : le nombre d'éléments synchronisés,
-- la place qu'ils prennent (comptée comme le quota de sync_push : contenu
-- chiffré des éléments vivants) et la date du dernier changement. Rien
-- d'autre : le contenu reste chiffré, le serveur ne peut pas le lire.
--
-- Invoker : la fonction lit avec les droits de l'appelant, donc seulement ses
-- propres lignes (RLS « sync_items: read own »).

create function public.account_summary()
returns json
language sql
stable
security invoker
set search_path = ''
as $$
  select json_build_object(
    'items', count(*) filter (where not s.deleted),
    'bytes', coalesce(sum(char_length(s.payload)) filter (where not s.deleted), 0),
    'last_change', max(s.modified_at)
  )
  from public.sync_items s
  where s.user_id = (select auth.uid());
$$;

revoke execute on function public.account_summary() from public, anon;
grant execute on function public.account_summary() to authenticated;
