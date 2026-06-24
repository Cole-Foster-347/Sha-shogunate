-- ============================================================
-- Roomeet — 0003_auth_edu_hook.sql
-- 1) Restrict signups to .edu (allowlist table + before-user-created hook)
-- 2) Auto-create a public.app_user row when an auth user is created
-- ============================================================

-- ----------------------------------------------------------------
-- 1) .EDU SIGNUP RESTRICTION
-- ----------------------------------------------------------------
-- Allowlist table. Add specific campus domains, or keep the broad
-- ".edu" suffix rule below. Storing in a table means you add/remove
-- campuses without editing SQL.
create table if not exists public.signup_email_domains (
  domain     text primary key,     -- exact domain e.g. 'stanford.edu'
  created_at timestamptz not null default now()
);

-- Seed with nothing exact — the hook uses a SUFFIX rule for *.edu.
-- If you later want to limit to specific campuses, insert them here
-- and switch the hook to exact-match (see commented block).

-- The before-user-created hook function.
-- Receives the auth event as jsonb; returns it to allow, or returns
-- an {"error": {...}} object to REJECT the signup.
create or replace function public.hook_restrict_signup_to_edu(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  user_email text;
  domain     text;
begin
  user_email := lower(event -> 'user_metadata' ->> 'email');
  -- fall back to top-level email field shape
  if user_email is null then
    user_email := lower(event -> 'claims' ->> 'email');
  end if;
  if user_email is null then
    user_email := lower(event ->> 'email');
  end if;

  if user_email is null then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'No email on signup request.'
      )
    );
  end if;

  domain := split_part(user_email, '@', 2);

  -- RULE: allow any *.edu address.
  if domain like '%.edu' then
    return event;  -- allow
  end if;

  -- (OPTIONAL) exact-campus mode — uncomment to restrict to allowlist:
  -- if exists (select 1 from public.signup_email_domains s where s.domain = domain) then
  --   return event;
  -- end if;

  return jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', 'Roomeet is for verified .edu student emails only.'
    )
  );
end;
$$;

-- Grant the auth admin role permission to run the hook.
grant execute on function public.hook_restrict_signup_to_edu(jsonb)
  to supabase_auth_admin;
revoke execute on function public.hook_restrict_signup_to_edu(jsonb)
  from authenticated, anon, public;

-- NOTE: After running this, enable the hook in the Supabase Dashboard:
--   Authentication → Hooks → "Before User Created"
--   → Postgres → select public.hook_restrict_signup_to_edu
-- (Or set it via the Management API / config.toml — see SETUP.md.)

-- ----------------------------------------------------------------
-- 2) AUTO-SYNC public.app_user FROM auth.users
-- ----------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_user (id, email, name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
