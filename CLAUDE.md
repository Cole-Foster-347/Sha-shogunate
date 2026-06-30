# Roomeet — CLAUDE.md
> Claude Code project context. Lives at repo root. Read on every session.
> iOS-only · Swift/SwiftUI · Supabase · MVP v1.1 · Owner: Cole

---

## 1. What Roomeet Is

An iOS app that pairs college friends into **duos** and gets two duos to meet IRL.
Loop: form a duo → browse other duos → **both members like** a duo → mutual likes create a match → **chat in-app** to coordinate (informal time) → optionally **check in** with a shared code.

**Tagline:** "Meet as a pair. 45 minutes. Zero pressure." · **Browse line:** "IRL > DMs"

---

## 2. Locked Architecture Decisions (do not relitigate)

| Decision | Choice |
|---|---|
| Platform | **iOS only**, Swift + SwiftUI, iOS 16+ |
| Backend | **Supabase** (Postgres, Auth, Realtime, Storage) — no custom server |
| Existing Xcode code | **Overwrite** toward the architecture in this file |
| Duo control | **Equal** — member_a and member_b have identical rights |
| Likes | **Both members must like** a target (two-stage: intent → duo_like) |
| Partner sees | **Pending-likes tray**: "Your partner liked X — confirm or skip" |
| Multiple duos | **Allowed** — a user can be in many duos; one **active duo** at a time |
| Browse identity | **Active-duo switcher** — you browse/match as your active duo |
| Meetup time | **Informal, in chat** — no rigid confirm-both state machine |
| Chat | **In-app from day 1**, live via Supabase Realtime |
| Live updates | **Realtime** subscriptions (chat, match, check_in, like_intent) |
| Match on leave | **Cancel match; delete duo profile** (draft-save deferred) |
| Re-pairing | Either ex-member can form a new duo immediately |
| Auth | **.edu magic link**, enforced by a before-user-created hook |
| Push (APNs) | **Stubbed module** — Apple Developer acct pending; wire up later |
| Moderation | **Trust + report/block** only |
| Penalty engine | **Deferred** behind penalty_engine flag (tables exist) |

---

## 3. Repo Layout (target)

```
Sha-shogunate/
├── DuoDating/                    # Xcode project (Swift/SwiftUI)
│   └── DuoDating/
│       ├── App/                  # entry, environment, Supabase client init
│       ├── Auth/                 # magic-link entry, session restore
│       ├── Onboarding/           # create/join duo, photos, bio, interests
│       ├── Browse/               # card stack, like, active-duo switcher
│       ├── PendingLikes/         # partner-liked tray (confirm/skip)
│       ├── Matches/              # match list
│       ├── Chat/                 # in-app live chat per match
│       ├── CheckIn/              # code entry, soft window, arrived sync
│       ├── Profile/              # edit duo, weekly reset, manage duos
│       ├── Settings/             # notifications, sign out, report/block
│       ├── Models/               # Codable structs (one per DB table)
│       ├── Services/             # SupabaseService, RealtimeService,
│       │                         #   PushService (stub), Analytics, Sentry
│       └── Shared/               # components, extensions, Constants, Copy
├── supabase/
│   └── migrations/               # 0001_init … 0004_triggers (source of truth)
├── SETUP.md                      # one-time setup & how to use this in Claude
└── CLAUDE.md
```

---

## 4. Hard Constraints (never violate)

1. **RLS always.** Only the authenticated Supabase client; never the service-role key on device.
2. **No GPS storage.** Check-in stores only arrived bool + timestamp.
3. **Both must like.** A like is never duo-level until both members tap it.
4. **Active-duo scoping.** Browse/like/match always run as app_user.active_duo_id.
5. **No age gate, no view caps, no paywall UI** in MVP.
6. **Secrets in env only** — never hardcode keys; load from xcconfig / env.
7. **Signed, expiring URLs** for all Storage photos — never public URLs.
8. **Schema is owned by supabase/migrations/.** Generate Swift models to match; never invent columns.

---

## 5. Database — Source of Truth

The schema lives in supabase/migrations/. Key tables:

- app_user (id = auth uid, email, name, **active_duo_id**)
- duo_profile (member_a, member_b, photos[], bio, active_week, reliability_score, status)
- like_intent (from_duo_id, target_duo_id, **actor_user_id**) — one per member
- duo_like (from_duo_id, to_duo_id) — created by trigger when both members agree
- match (duo_a, duo_b, status: active|cancelled|completed)
- chat_message (match_id, sender_user_id, body, created_at)
- check_in (match_id, code, opened_at, window_secs, arrived jsonb, status)
- report, block, penalty_event, credit, feature_flag, interests

**Matching flow (triggers, already written):**
like_intent insert → if both members agree → duo_like → if reverse duo_like exists and no match in last 7 days → match.

When generating Swift models, **match column names exactly** (snake_case → use CodingKeys).

---

## 6. Swift Conventions

- **SwiftUI + async/await + MVVM.** View + @StateObject ViewModel. No UIKit unless an SDK forces it. No Combine unless already present.
- **Supabase Swift SDK** for all DB/Auth/Realtime/Storage.
- **One Codable struct per table** in Models/, names matching DB.
- **No hardcoded user-facing strings** — put copy in Shared/Copy.swift.
- **Error handling:** throws / do-catch; never try!. Surface errors to a toast.
- **Photos:** compress to ≤ 1 MB JPEG before upload.
- **Active duo:** read/write app_user.active_duo_id; every browse/like query is scoped to it.

---

## 7. Build Order (each step builds on a working prior step)

1. **Supabase client + Auth** — magic link sign-in, session restore, .edu validated server-side. Verify a non-.edu email is rejected.
2. **Models** — generate Codable structs for all tables.
3. **Duo create/join** — onboarding flow; set as active duo. Support multiple duos + switcher.
4. **Browse** — fetch active, non-blocked duos (exclude own duos); card stack; like_intent insert.
5. **Pending-likes tray** — show targets the partner liked but you haven't; confirm → insert your like_intent.
6. **Matches** — list active matches (Realtime).
7. **Chat** — per-match live chat (Realtime on chat_message).
8. **Check-in** — chat-triggered code; soft window; arrived sync.
9. **Profile/Settings** — edit duo, weekly reset prompt, report/block.
10. **Push (stub → real)** — PushService protocol with a no-op impl; swap to APNs once enrolled.

Do steps in order. After each, confirm it builds and the prior flow still works.

---

## 8. Realtime Patterns

Subscribe per-context, unsubscribe on view disappear:
- **Chat:** channel chat:<matchId>, listen to chat_message inserts where match_id = X.
- **Matches:** listen to match inserts/updates touching the active duo.
- **Check-in:** listen to check_in updates for the match.
- **Pending likes:** listen to like_intent inserts on the active duo's from_duo_id.

---

## 9. Copy Reference (use exactly)

| Context | Copy |
|---|---|
| Tagline | Meet as a pair. 45 minutes. Zero pressure. |
| Browse line | IRL > DMs |
| Like button | Like |
| Pending tray | Your partner liked this duo — you in? |
| Match toast | You matched — say hi? |
| Check-in prompt | Check in: enter your code 'PINE' within 10 minutes. |
| Grace prompt | Your match checked in. Running late? You have 5 more minutes. |
| Weekly reset | New week — same wing or switching it up? |
| Leave duo confirm | Leaving ends this duo and its matches. Sure? |

---

## 10. PostHog Events (fire exactly)

onboard_complete · duo_created · active_duo_switched · profile_view ·
like_intent_sent · duo_like_formed · match_created · chat_message_sent ·
checkin_opened · checkin_success · report_sent · block_set

---

## 11. Out of Scope (do not build)

Calendar/slot scheduling · algorithmic/interest-weighted matching · admin console UI ·
automated no-show penalty cron (flag-gated) · solo "find me a wing" auto-matcher ·
sponsored spots / payments · premium paywall UI · ID/age verification · Android/web.

---

## 12. Pre-Merge Checklist

- [ ] Non-.edu signup is rejected by the hook
- [ ] Two test users complete: sign in → duo → browse → both-like → match → chat → check-in
- [ ] Multiple-duo switcher works; browse is correctly scoped to active duo
- [ ] Pending-likes tray promotes to a match only when both members like
- [ ] RLS verified with two sessions (user A cannot read user B's private rows)
- [ ] Photos via signed URLs (expiry ≤ 1h)
- [ ] git grep -iE "key|secret|token" returns no literals
- [ ] Realtime chat delivers live both directions
- [ ] 7-day rematch guard holds

---

## 13. Commands

\`\`\`bash
# Supabase
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <ref>
supabase db push                       # apply migrations/
supabase db reset                      # local: wipe + replay migrations

# iOS build check
xcodebuild -scheme DuoDating \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
\`\`\`
