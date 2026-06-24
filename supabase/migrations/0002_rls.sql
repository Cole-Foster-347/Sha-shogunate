-- ============================================================
-- Roomeet — 0002_rls.sql
-- Row Level Security. Enable on every table; users only touch
-- rows tied to a duo they are a member of.
-- ============================================================

-- Helper: is the current user a member of this duo?
create or replace function public.is_duo_member(p_duo_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.duo_profile d
    where d.id = p_duo_id
      and (d.member_a = auth.uid() or d.member_b = auth.uid())
  );
$$;

-- Helper: is the current user a participant in this match?
create or replace function public.is_match_participant(p_match_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.match m
    join public.duo_profile d
      on d.id = m.duo_a or d.id = m.duo_b
    where m.id = p_match_id
      and (d.member_a = auth.uid() or d.member_b = auth.uid())
  );
$$;

-- Enable RLS everywhere -------------------------------------
alter table public.app_user      enable row level security;
alter table public.duo_profile   enable row level security;
alter table public.interest_tag  enable row level security;
alter table public.duo_interest  enable row level security;
alter table public.like_intent   enable row level security;
alter table public.duo_like      enable row level security;
alter table public.match         enable row level security;
alter table public.chat_message  enable row level security;
alter table public.check_in      enable row level security;
alter table public.penalty_event enable row level security;
alter table public.credit        enable row level security;
alter table public.report        enable row level security;
alter table public.block         enable row level security;
alter table public.feature_flag  enable row level security;

-- app_user ---------------------------------------------------
create policy app_user_self_read on public.app_user
  for select using (id = auth.uid());
create policy app_user_self_update on public.app_user
  for update using (id = auth.uid());

-- duo_profile ------------------------------------------------
-- Read: any active duo is browsable (needed for the feed) EXCEPT
-- blocked ones (filtered in the query). Write: members only.
create policy duo_read_active on public.duo_profile
  for select using (status = 'active' or public.is_duo_member(id));
create policy duo_insert on public.duo_profile
  for insert with check (member_a = auth.uid() or member_b = auth.uid());
create policy duo_update_members on public.duo_profile
  for update using (public.is_duo_member(id));
create policy duo_delete_members on public.duo_profile
  for delete using (public.is_duo_member(id));

-- interest tags: readable by all authed; write via service role
create policy interest_read on public.interest_tag
  for select using (auth.role() = 'authenticated');

create policy duo_interest_read on public.duo_interest
  for select using (auth.role() = 'authenticated');
create policy duo_interest_write on public.duo_interest
  for all using (public.is_duo_member(duo_id))
  with check (public.is_duo_member(duo_id));

-- like_intent: members of from_duo only
create policy like_intent_read on public.like_intent
  for select using (public.is_duo_member(from_duo_id));
create policy like_intent_insert on public.like_intent
  for insert with check (
    public.is_duo_member(from_duo_id) and actor_user_id = auth.uid()
  );
create policy like_intent_delete on public.like_intent
  for delete using (public.is_duo_member(from_duo_id));

-- duo_like: readable by either side (so reverse-like can be seen)
create policy duo_like_read on public.duo_like
  for select using (
    public.is_duo_member(from_duo_id) or public.is_duo_member(to_duo_id)
  );
-- inserts happen via trigger (security definer) — no direct insert policy

-- match: participants only
create policy match_read on public.match
  for select using (
    public.is_duo_member(duo_a) or public.is_duo_member(duo_b)
  );
create policy match_update on public.match
  for update using (
    public.is_duo_member(duo_a) or public.is_duo_member(duo_b)
  );

-- chat_message: match participants only
create policy chat_read on public.chat_message
  for select using (public.is_match_participant(match_id));
create policy chat_insert on public.chat_message
  for insert with check (
    public.is_match_participant(match_id) and sender_user_id = auth.uid()
  );

-- check_in: match participants
create policy checkin_read on public.check_in
  for select using (public.is_match_participant(match_id));
create policy checkin_write on public.check_in
  for all using (public.is_match_participant(match_id))
  with check (public.is_match_participant(match_id));

-- penalty / credit: read own duo only
create policy penalty_read on public.penalty_event
  for select using (public.is_duo_member(duo_id));
create policy credit_read on public.credit
  for select using (public.is_duo_member(duo_id));

-- report: insert only, no self-read (admin reads via service role)
create policy report_insert on public.report
  for insert with check (reporter_user_id = auth.uid());

-- block: members of blocker duo
create policy block_read on public.block
  for select using (public.is_duo_member(blocker_duo_id));
create policy block_write on public.block
  for all using (public.is_duo_member(blocker_duo_id))
  with check (public.is_duo_member(blocker_duo_id));

-- feature_flag: read-only for authed users
create policy flag_read on public.feature_flag
  for select using (auth.role() = 'authenticated');
