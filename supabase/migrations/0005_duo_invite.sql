-- ============================================================
-- Roomeet — 0005_duo_invite.sql
-- Invite-code duo formation. A creator generates a short code; another
-- user looks it up by code and accepts. The real duo_profile is created
-- at ACCEPTANCE (created_duo_id is filled in then), NOT at invite time.
-- ============================================================

-- ----------------------------------------------------------------
-- duo_invite : a pending invitation identified by a short human code.
-- creator_user_id  = the user who generated the code (becomes member_a).
-- accepted_by_user_id = the user who redeemed it (becomes member_b).
-- created_duo_id   = the duo_profile created when accepted (set later).
-- ----------------------------------------------------------------
create table if not exists public.duo_invite (
  id                  uuid primary key default gen_random_uuid(),
  code                text not null unique,            -- short human code, e.g. 'PINE-4823'
  creator_user_id     uuid not null references public.app_user (id) on delete cascade,
  status              text not null default 'pending'
                      check (status in ('pending','accepted','expired','cancelled')),
  accepted_by_user_id uuid references public.app_user (id) on delete set null,
  created_duo_id      uuid references public.duo_profile (id) on delete set null,
  created_at          timestamptz not null default now(),
  expires_at          timestamptz                      -- nullable; optional expiry
);

-- `code` is already btree-indexed by the unique constraint above (used for code lookup).
create index if not exists duo_invite_creator_idx on public.duo_invite (creator_user_id);

-- ----------------------------------------------------------------
-- Row Level Security (mirrors 0002_rls.sql conventions)
-- ----------------------------------------------------------------
alter table public.duo_invite enable row level security;

-- SELECT
-- Creator sees all of their own invites (any status). The accepter sees invites
-- they have accepted (accepted_by_user_id). Any other authenticated user may read
-- PENDING invites so they can look one up by code and accept it.
--
-- The accepted_by_user_id branch is also REQUIRED for the accept UPDATE to work:
-- PostgREST issues UPDATE ... RETURNING, and the post-update row must satisfy this
-- SELECT policy. Without it, an accepter's own accept (status -> 'accepted') would
-- produce a row invisible to them and fail with "new row violates RLS".
--
-- MVP TRADEOFF: RLS cannot restrict the read to "only the row matching the code
-- the user typed" — the by-code scoping lives in the client query (eq code).
-- This means any authenticated user could, in principle, enumerate *pending*
-- invites (not accepted/cancelled/expired ones). Codes are unguessable-ish and
-- this is acceptable for MVP; tighten later via a SECURITY DEFINER lookup-by-code
-- function if enumeration becomes a concern.
drop policy if exists duo_invite_read on public.duo_invite;
create policy duo_invite_read on public.duo_invite
  for select using (
    creator_user_id = auth.uid()
    or accepted_by_user_id = auth.uid()
    or (status = 'pending' and auth.role() = 'authenticated')
  );

-- INSERT: a user may only create invites as themselves.
drop policy if exists duo_invite_insert on public.duo_invite;
create policy duo_invite_insert on public.duo_invite
  for insert with check (creator_user_id = auth.uid());

-- UPDATE (accept / cancel) — single explicit policy.
--   USING (rows you may target):
--     * the creator may act on their own invites (e.g. cancel), OR
--     * any authenticated non-creator may act on a still-PENDING invite (to accept).
--   WITH CHECK (constraints on the resulting row):
--     * the creator may leave it as their own row (cancel -> status 'cancelled', etc.), OR
--     * a non-creator may only transition it to 'accepted' AND must claim themselves
--       via accepted_by_user_id = auth.uid().
-- Net effect: a non-creator can only do pending -> accepted while marking themselves;
-- they cannot expire/cancel someone else's invite or accept on another's behalf.
--
-- MVP TRADEOFF: WITH CHECK cannot see the OLD row, so it does not block a non-creator
-- from also writing created_duo_id in the same UPDATE. The accept flow (later ticket)
-- sets created_duo_id to a duo the accepter is a member of; not security-critical for MVP.
drop policy if exists duo_invite_update on public.duo_invite;
create policy duo_invite_update on public.duo_invite
  for update
  using (
    creator_user_id = auth.uid()
    or (status = 'pending' and auth.role() = 'authenticated')
  )
  with check (
    creator_user_id = auth.uid()
    or (status = 'accepted' and accepted_by_user_id = auth.uid())
  );
