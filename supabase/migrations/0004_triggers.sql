-- ============================================================
-- Roomeet — 0004_triggers.sql
-- Matching engine:
--   like_intent (one member) ──► duo_like (both members agreed)
--   duo_like (both directions) ──► match  (with 7-day rematch guard)
-- ============================================================

-- ----------------------------------------------------------------
-- When a like_intent is inserted, check whether BOTH members of the
-- from_duo now have an intent toward the same target. If so, promote
-- to a duo_like.
-- ----------------------------------------------------------------
create or replace function public.promote_like_intent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m_a uuid;
  m_b uuid;
  both_agreed boolean;
begin
  select member_a, member_b into m_a, m_b
  from public.duo_profile
  where id = new.from_duo_id;

  -- both members have an intent toward this target?
  select
    exists(select 1 from public.like_intent
           where from_duo_id = new.from_duo_id
             and target_duo_id = new.target_duo_id
             and actor_user_id = m_a)
    and
    exists(select 1 from public.like_intent
           where from_duo_id = new.from_duo_id
             and target_duo_id = new.target_duo_id
             and actor_user_id = m_b)
  into both_agreed;

  if both_agreed then
    insert into public.duo_like (from_duo_id, to_duo_id)
    values (new.from_duo_id, new.target_duo_id)
    on conflict (from_duo_id, to_duo_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_promote_like_intent on public.like_intent;
create trigger trg_promote_like_intent
  after insert on public.like_intent
  for each row execute function public.promote_like_intent();

-- ----------------------------------------------------------------
-- When a duo_like is inserted, check for the reverse duo_like.
-- If present and no recent match exists between the pair, create a match.
-- 7-day avoid-rematch guard.
-- ----------------------------------------------------------------
create or replace function public.create_match_on_mutual_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reverse_exists boolean;
  recent_match   boolean;
begin
  select exists(
    select 1 from public.duo_like
    where from_duo_id = new.to_duo_id
      and to_duo_id   = new.from_duo_id
  ) into reverse_exists;

  if not reverse_exists then
    return new;
  end if;

  -- avoid rematch within 7 days (either ordering)
  select exists(
    select 1 from public.match
    where created_at > now() - interval '7 days'
      and (
        (duo_a = new.from_duo_id and duo_b = new.to_duo_id) or
        (duo_a = new.to_duo_id   and duo_b = new.from_duo_id)
      )
  ) into recent_match;

  if recent_match then
    return new;
  end if;

  insert into public.match (duo_a, duo_b, status)
  values (new.from_duo_id, new.to_duo_id, 'active');

  return new;
end;
$$;

drop trigger if exists trg_create_match on public.duo_like;
create trigger trg_create_match
  after insert on public.duo_like
  for each row execute function public.create_match_on_mutual_like();

-- ----------------------------------------------------------------
-- When a duo is cancelled (a member leaves), cancel its active matches.
-- MVP decision: profile is deleted by the client; this safeguards any
-- matches if a soft-cancel path is used instead of a hard delete.
-- ----------------------------------------------------------------
create or replace function public.cancel_matches_on_duo_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    update public.match
    set status = 'cancelled'
    where (duo_a = new.id or duo_b = new.id)
      and status = 'active';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cancel_matches on public.duo_profile;
create trigger trg_cancel_matches
  after update on public.duo_profile
  for each row execute function public.cancel_matches_on_duo_cancel();

-- ----------------------------------------------------------------
-- Realtime: add chat + match + check_in to the realtime publication
-- so the iOS client gets live updates.
-- ----------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.chat_message;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.match;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.check_in;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.like_intent;
exception when duplicate_object then null;
end $$;
