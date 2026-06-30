# Roomeet — SETUP.md
One-time setup, and how to drive the build with Claude Code.

---

## A. Put these files in your repo

From this output set, copy into your repo like so:

```
Sha-shogunate/
├── CLAUDE.md                        ← repo root
├── SETUP.md                         ← repo root
└── supabase/
    └── migrations/
        ├── 0001_init.sql
        ├── 0002_rls.sql
        ├── 0003_auth_edu_hook.sql
        └── 0004_triggers.sql
```

```bash
cd Sha-shogunate
mkdir -p supabase/migrations
# move the four .sql files into supabase/migrations/
# move CLAUDE.md and SETUP.md to the repo root
git add CLAUDE.md SETUP.md supabase/
git commit -m "Add Roomeet foundation: CLAUDE.md + DB migrations"
```

---

## B. Supabase project setup (once)

1. Create a project at supabase.com. Note the **project ref** and **anon key**.
2. Install the CLI and link:
   ```bash
   brew install supabase/tap/supabase
   supabase login
   supabase link --project-ref <your-ref>
   ```
3. Apply the schema:
   ```bash
   supabase db push
   ```
   This runs the four migrations in order: tables → RLS → .edu hook → triggers.

4. **Enable the .edu hook** (one click, can't be done purely in SQL):
   Dashboard → **Authentication → Hooks → Before User Created**
   → type **Postgres** → function `public.hook_restrict_signup_to_edu`.
   Test: try a magic link to a gmail address — it must be rejected.

   > Default rule allows any `*.edu`. To limit to specific campuses, insert
   > rows into `signup_email_domains` and switch the hook to exact-match
   > (commented block inside `0003_auth_edu_hook.sql`).

5. **Storage:** create a bucket `duo-photos` (Private). The app uploads here and
   serves images via signed URLs only.

6. **Realtime:** already enabled in `0004` for chat_message, match, check_in,
   like_intent. Nothing else to do.

7. **Email (Resend):** in Auth → Email, point SMTP at your Resend credentials so
   magic links send reliably.

---

## C. iOS app config

Store secrets outside source control:
- Create `Secrets.xcconfig` (gitignored) with:
  ```
  SUPABASE_URL = https://<ref>.supabase.co
  SUPABASE_ANON_KEY = <anon key>
  ```
- Add Supabase Swift SDK via Swift Package Manager:
  `https://github.com/supabase/supabase-swift`

> Push notifications are **stubbed** for now. `PushService` is a protocol with a
> no-op implementation; once your Apple Developer account is active, add the APNs
> implementation and swap it in `App/` — no other code changes.

---

## D. How to drive the build with Claude Code

1. Open the repo in Claude Code (`claude` in the repo directory). It auto-reads `CLAUDE.md`.
2. Work the **Build Order** in section 7 of CLAUDE.md, one step per session/PR. Suggested first prompts:

   - **Step 1:** "Set up the Supabase client and magic-link auth per CLAUDE.md.
     Add session restore on launch. Show me how to test that a non-.edu email is rejected."
   - **Step 2:** "Generate Codable model structs for every table in
     supabase/migrations/0001_init.sql, with CodingKeys matching the snake_case columns."
   - **Step 3:** "Build the duo create/join onboarding flow, including the
     active-duo switcher for users with multiple duos."
   - **Step 4:** "Build Browse: fetch active, non-blocked duos excluding my own,
     as a card stack; tapping Like inserts a like_intent for the current user."
   - **Step 5:** "Build the Pending-Likes tray showing duos my partner liked that
     I haven't; confirming inserts my like_intent so the trigger can promote it."
   - ... continue through step 10.

3. After each step, run the **Pre-Merge Checklist** (section 12) items relevant to it.

### Tips to get the most out of Claude Code
- Let it read the migrations rather than describing schema in chat — they're the source of truth.
- Ask it to **write a quick test** of each RLS policy with two simulated users before moving on.
- Keep one feature per PR; the build order is designed so each step compiles on its own.
- When something feels ambiguous, point it back to the relevant CLAUDE.md section by number.

---

## E. Open decisions to revisit later (pinned)

- **Draft-saving a duo when a member leaves** — currently we hard-delete. When ready,
  flip `duo_profile.status` to 'cancelled' instead of deleting, and add a restore flow.
- **Penalty/reliability engine** — tables exist; turn on by flipping the
  `penalty_engine` feature flag and adding the evaluation logic (needs a firmer
  meetup time anchor than the current informal-chat model).
- **Strict vs informal meetups** — if you later want automated no-show detection,
  reintroduce a scheduled `start_at` and a cron Edge Function.
