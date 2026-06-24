-- ============================================================
-- Roomeet — 0001_init.sql
-- Core schema. Run in Supabase SQL editor or via `supabase db push`.
-- ============================================================

-- Extensions ------------------------------------------------
create extension if not exists "pgcrypto";  -- gen_random_uuid()

-- ----------------------------------------------------------------
-- app_user : mirror of auth.users we control (1 row per person)
-- auth.users.id is the source of truth; we copy id + email + name.
-- ----------------------------------------------------------------
create table if not exists public.app_user (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text not null,
  name         text,
  active_duo_id uuid,               -- which duo this user is currently browsing as
  created_at   timestamptz not null default now()
);

-- ----------------------------------------------------------------
-- duo_profile : a pair of two friends. Equal control.
-- A user may belong to MANY duos (multiple duos per user allowed).
-- member_a / member_b are both real users with equal rights.
-- ----------------------------------------------------------------
create table if not exists public.duo_profile (
  id                uuid primary key default gen_random_uuid(),
  member_a          uuid not null references public.app_user (id) on delete cascade,
  member_b          uuid not null references public.app_user (id) on delete cascade,
  photos            text[] not null default '{}',   -- Supabase Storage paths (served via signed URLs)
  bio               text,
  active_week       int  not null default 0,
  reliability_score int  not null default 0,
  status            text not null default 'active'  -- active | cancelled
                    check (status in ('active','cancelled')),
  created_at        timestamptz not null default now(),
  constraint distinct_members check (member_a <> member_b)
);

-- a user shouldn't form two identical duos with the same partner
create unique index if not exists duo_unique_pair
  on public.duo_profile (least(member_a, member_b), greatest(member_a, member_b))
  where status = 'active';

create index if not exists duo_member_a_idx on public.duo_profile (member_a);
create index if not exists duo_member_b_idx on public.duo_profile (member_b);

-- now that duo_profile exists, point active_duo_id at it
alter table public.app_user
  add constraint app_user_active_duo_fk
  foreign key (active_duo_id) references public.duo_profile (id) on delete set null;

-- ----------------------------------------------------------------
-- interests (display-only in MVP, no matching weight)
-- ----------------------------------------------------------------
create table if not exists public.interest_tag (
  id    uuid primary key default gen_random_uuid(),
  label text not null unique
);

create table if not exists public.duo_interest (
  duo_id uuid not null references public.duo_profile (id) on delete cascade,
  tag_id uuid not null references public.interest_tag (id) on delete cascade,
  primary key (duo_id, tag_id)
);

-- ----------------------------------------------------------------
-- TWO-STAGE LIKE
-- like_intent : ONE member of a duo taps Like on a target duo.
-- When BOTH members of the same duo have an intent toward the same
-- target, a trigger promotes it to a duo_like (see 0004_triggers).
-- ----------------------------------------------------------------
create table if not exists public.like_intent (
  id            uuid primary key default gen_random_uuid(),
  from_duo_id   uuid not null references public.duo_profile (id) on delete cascade,
  target_duo_id uuid not null references public.duo_profile (id) on delete cascade,
  actor_user_id uuid not null references public.app_user (id) on delete cascade,
  created_at    timestamptz not null default now(),
  unique (from_duo_id, target_duo_id, actor_user_id)
);

-- duo_like : a confirmed, duo-level like (both members agreed)
create table if not exists public.duo_like (
  id          uuid primary key default gen_random_uuid(),
  from_duo_id uuid not null references public.duo_profile (id) on delete cascade,
  to_duo_id   uuid not null references public.duo_profile (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (from_duo_id, to_duo_id)
);

-- ----------------------------------------------------------------
-- match : created when two duos mutually duo_like each other
-- ----------------------------------------------------------------
create table if not exists public.match (
  id         uuid primary key default gen_random_uuid(),
  duo_a      uuid not null references public.duo_profile (id) on delete cascade,
  duo_b      uuid not null references public.duo_profile (id) on delete cascade,
  status     text not null default 'active'
             check (status in ('active','cancelled','completed')),
  created_at timestamptz not null default now()
);

create index if not exists match_duo_a_idx on public.match (duo_a);
create index if not exists match_duo_b_idx on public.match (duo_b);

-- ----------------------------------------------------------------
-- chat_message : in-app chat, live via Supabase Realtime
-- ----------------------------------------------------------------
create table if not exists public.chat_message (
  id             uuid primary key default gen_random_uuid(),
  match_id       uuid not null references public.match (id) on delete cascade,
  sender_user_id uuid not null references public.app_user (id) on delete cascade,
  body           text not null,
  created_at     timestamptz not null default now()
);

create index if not exists chat_match_idx on public.chat_message (match_id, created_at);

-- ----------------------------------------------------------------
-- check_in : chat-triggered (informal meetups). Soft window.
-- arrived flags + mutual code. Automated penalties are DEFERRED
-- (feature-flagged) since meetup times are informal.
-- ----------------------------------------------------------------
create table if not exists public.check_in (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references public.match (id) on delete cascade,
  code        text not null,                 -- mutual one-word code e.g. 'PINE'
  opened_at   timestamptz not null default now(),
  window_secs int not null default 600,      -- 10 min soft window
  arrived     jsonb not null default '{}',   -- { "<duo_id>": true }
  status      text not null default 'open'   -- open | complete | expired
              check (status in ('open','complete','expired'))
);

-- ----------------------------------------------------------------
-- reliability / penalties — tables exist, engine deferred via flag
-- ----------------------------------------------------------------
create table if not exists public.penalty_event (
  id        uuid primary key default gen_random_uuid(),
  duo_id    uuid not null references public.duo_profile (id) on delete cascade,
  match_id  uuid references public.match (id) on delete set null,
  type      text not null check (type in ('no_show','late_cancel')),
  resolved  bool not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.credit (
  id         uuid primary key default gen_random_uuid(),
  duo_id     uuid not null references public.duo_profile (id) on delete cascade,
  type       text not null check (type in ('PriorityReroll')),
  expires_at timestamptz
);

-- ----------------------------------------------------------------
-- safety : report + block (trust-based moderation)
-- ----------------------------------------------------------------
create table if not exists public.report (
  id               uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references public.app_user (id) on delete cascade,
  target_duo_id    uuid not null references public.duo_profile (id) on delete cascade,
  match_id         uuid references public.match (id) on delete set null,
  reason           text not null,
  note             text,
  created_at       timestamptz not null default now()
);

create table if not exists public.block (
  id             uuid primary key default gen_random_uuid(),
  blocker_duo_id uuid not null references public.duo_profile (id) on delete cascade,
  blocked_duo_id uuid not null references public.duo_profile (id) on delete cascade,
  created_at     timestamptz not null default now(),
  unique (blocker_duo_id, blocked_duo_id)
);

-- ----------------------------------------------------------------
-- feature_flag : gates deferred systems (penalty engine, premium, etc.)
-- ----------------------------------------------------------------
create table if not exists public.feature_flag (
  key     text primary key,
  enabled bool not null default false
);

insert into public.feature_flag (key, enabled) values
  ('penalty_engine', false),
  ('premium_hooks',  false),
  ('sponsor_spots',  false)
on conflict (key) do nothing;
