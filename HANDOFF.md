# Roomeet — Cofounder Handoff / Status

_A quick "where we are" for the demo build. The product spec lives in `CLAUDE.md` (locked decisions, schema, build order) — read that for the "why"; this doc is the "what's built so far."_

## What Roomeet is
iOS app that pairs two friends into a **duo**, then matches two duos for a low-pressure IRL double-date.
Loop: **form a duo → browse other duos → both members like → mutual match → chat to meet up.**

## Status: the core loop is BUILT and verified against the live backend
Sign in → form a duo (invite code) → browse other duos → **both members like** → **match** (fires via DB triggers) → **live realtime chat** → **live "It's a match" banner**. Each step verified live (SDK/websocket + simulator).

## Stack
- **Frontend:** iOS, Swift + SwiftUI (MVVM, async/await). The reused `oneshot/` Xcode project is the **demo shell**.
- **Backend:** Supabase (Postgres + Auth + Realtime), project ref `grlhstgzlulrgofhgrvq`. Schema is code — migrations `0001`–`0005` in `supabase/migrations/` (the source of truth; don't hand-edit the DB).
- **Matching engine is in the DB, not the app:** a like inserts one `like_intent` per user; triggers (migration `0004`) promote to `duo_like` when *both* members like the same target, then to a `match` on mutual likes (7-day rematch guard). The app only inserts likes.
- **Realtime:** Supabase Realtime powers live chat and live match detection.
- **Canonical Swift services:** `AuthService`, `DuoInviteService`, `BrowseService`, `LikeService`, `MatchService`, `ChatService` (all talk to the canonical tables; the old OneShot/GetStream/dead-schema code is unused).

## What works
- **Auth** — email/password sign in / sign up (session persists; existing users resume).
- **Duo formation** — invite-code flow: one person "Create a duo" → short code; partner "Join with a code" → real `duo_profile` created at acceptance; both users' active duo set.
- **Browse** — swipeable card stack of other active duos (excludes your own + blocked), duo photos + bio + "IRL > DMs".
- **Like** — per-user like; both members liking the same duo → match via triggers.
- **Match + live banner** — the moment a match fires, a maroon "You matched — say hi?" banner slides in on both members' screens (app-level realtime), photos animating together; "Say hi" opens the chat.
- **Chat** — per-match live messaging over Supabase Realtime (messages appear on the other phone within ~1–2s).
- **Branding** — UChicago maroon theme, "Roomeet" name, magnet-snap splash animation.

## Intentional demo shortcuts (NOT the production design — flagged so we don't trip on them)
- App shell is `oneshot/` (prod target is a clean `DuoDating/`).
- **Email/password** auth for the demo; the real design is **.edu magic-link** enforced by a signup hook.
- Supabase config lives in a gitignored `Environment.swift` (prod: `Secrets.xcconfig`).
- Duo **photos are public placeholder URLs** (`i.pravatar.cc`); prod uses a **private `duo-photos` bucket + signed URLs** (isolated behind `photoURL(for:)`).
- The `.edu` signup hook and email confirmation are **OFF** in the dashboard for demo convenience — turn back ON before real testing.

## Test fixtures (live backend, password `Demo1234!` for all)
- `demo1@test.com` + `demo2@test.com` — a duo (Cole + friend stand-ins).
- `seed1..seed8@test.com` — paired into **4 browseable "fake" duos** (Coffee snobs, Gym/tacos, Film nerds, Hiking).
- A "primed" fake duo already likes the demo duo so a **match + banner fires live** when both demo members like it.

## How to run the demo
Two iOS Simulators (e.g. iPhone 17 + iPhone 16e), the app installed on each:
1. Sign in on phone 1 as `demo1@test.com`, phone 2 as `demo2@test.com` (both resume to Browse).
2. On both phones, **Like** the primed fake duo. The **2nd like fires the match** → banner slides in on both.
3. Tap **Say hi** → live chat; a message on one phone appears on the other in ~1–2s.

## Known gaps / next up
- **Not yet done a full two-human GUI run** end-to-end (verified via API/websocket + simulator so far).
- Onboarding "Your Profile" step has no Continue button (must swipe); disabled Sign-In button gives no hint — both minor polish tickets.
- Photos → real private bucket + signed URLs.
- Not built yet: photo upload, check-in codes, profile editing, push notifications, multi-duo switcher UI.

## Repo
`github.com/Cole-Foster-347/Sha-shogunate`, branch `main`. Feature commits are pushed through the Roomeet rebrand; the newest work (canonical session-resume + sign-out, live match banner) is committed locally and about to push.
