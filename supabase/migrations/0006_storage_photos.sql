-- ============================================================
-- Roomeet — 0006_storage_photos.sql
-- Storage RLS for duo photos.
--
-- Photos belong to the DUO (equal control; deleted with the duo). They live in
-- a PRIVATE bucket `duo-photos`, laid out per-duo:
--     duo-photos/<duo_id>/<uuid>.jpg
-- `duo_profile.photos[]` stores the STORAGE PATH (never a URL); the read side
-- resolves each path to a signed, expiring URL (CLAUDE.md §4: signed/expiring
-- only, never public).
--
-- NOTE: the `duo-photos` BUCKET itself is created in the Supabase dashboard
-- (Storage → New bucket → duo-photos → Private) — buckets can't be created
-- cleanly from a migration. The ACCESS POLICIES live here, in version control.
--
-- Authorization: a row in storage.objects for this bucket is named
--   `<duo_id>/<uuid>.jpg` (the bucket is a separate column, not part of `name`),
-- so (storage.foldername(name))[1] is the `<duo_id>` folder. We authorize by
-- reusing public.is_duo_member(uuid) from 0002 — only members of that duo may
-- read/write files under its folder.
-- ============================================================

-- SELECT: members of the owning duo may read that duo's photos.
drop policy if exists duo_photos_read on storage.objects;
create policy duo_photos_read on storage.objects
  for select using (
    bucket_id = 'duo-photos'
    and public.is_duo_member( (storage.foldername(name))[1]::uuid )
  );

-- INSERT: members may upload into their own duo's folder.
drop policy if exists duo_photos_insert on storage.objects;
create policy duo_photos_insert on storage.objects
  for insert with check (
    bucket_id = 'duo-photos'
    and public.is_duo_member( (storage.foldername(name))[1]::uuid )
  );

-- UPDATE: members may modify files in their own duo's folder.
drop policy if exists duo_photos_update on storage.objects;
create policy duo_photos_update on storage.objects
  for update using (
    bucket_id = 'duo-photos'
    and public.is_duo_member( (storage.foldername(name))[1]::uuid )
  )
  with check (
    bucket_id = 'duo-photos'
    and public.is_duo_member( (storage.foldername(name))[1]::uuid )
  );

-- DELETE: members may delete files in their own duo's folder.
drop policy if exists duo_photos_delete on storage.objects;
create policy duo_photos_delete on storage.objects
  for delete using (
    bucket_id = 'duo-photos'
    and public.is_duo_member( (storage.foldername(name))[1]::uuid )
  );
