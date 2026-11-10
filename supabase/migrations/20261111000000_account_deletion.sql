-- =====================================================================
-- HTBIZ - ACCOUNT DELETION
-- =====================================================================
-- Idempotent. Safe to run repeatedly.
--
-- Google Play requires that a user can delete their account and the data
-- that belongs to it. The delete-account edge function removes the user's
-- storage files and then deletes the row in auth.users. Everything in the
-- database must follow that one delete through foreign keys, so that no
-- code path can forget a table.
--
-- WARNING: THIS MIGRATION DELETES DATA. Rows that point at an account, a
-- business or a review that no longer exists are removed before each
-- foreign key is added (a foreign key cannot be created over them). Those
-- rows are already unreachable from the app. Take a backup first.
--
-- What goes when an account is deleted:
--   profiles           profiles.id          -> auth.users   (added here)
--   reviews            reviews.user_id      -> auth.users
--   review_likes       review_likes.user_id -> auth.users
--   favorites          favorites.user_id    -> auth.users
--   check_ins          check_ins.user_id    -> auth.users
--   notifications      notifications.user_id -> auth.users
--   fcm_tokens         fcm_tokens.user_id   -> auth.users
--   usage_consent      usage_consent.user_id -> auth.users
--   usage_events       usage_events.user_id -> auth.users
--   admins             admins.user_id       -> auth.users
--   rate_limit_events  rate_limit_events.user_id -> auth.users
--   businesses         through the auth_user_delete_owned_businesses
--                      trigger (businesses.owner_id deliberately has no
--                      foreign key, see 20261006010000)
--   business_images, favorites, check_ins, notifications and reviews of
--   those businesses   through their business_id foreign keys
--   likes and notifications of the deleted reviews, through review_id
--
-- DECISION: reviews that OTHER people wrote on a business owned by the
-- deleted account are deleted with the business. A review cannot exist
-- without the business it describes, and keeping the listing alive without
-- an owner would keep publishing the owner's business data after they asked
-- for it to be removed. The confirmation dialog in the app says so.
--
-- Reviews the deleted user wrote on other businesses are deleted too, and
-- trigger_update_business_review_stats recomputes the rating and the review
-- count of each of those businesses as the rows go.
--
-- Most of these foreign keys are declared in earlier migrations, but always
-- inside CREATE TABLE IF NOT EXISTS: on a project where the table was first
-- created from the dashboard the statement was skipped and the key may be
-- missing or may lack ON DELETE CASCADE. This migration checks the shape of
-- every one of them instead of assuming.
-- =====================================================================

BEGIN;

DO $blk$
DECLARE
  target      RECORD;
  existing    RECORD;
  has_cascade BOOLEAN;
  removed     BIGINT;
BEGIN
  FOR target IN
    SELECT * FROM (VALUES
      -- table,            column,        referenced table
      ('profiles',          'id',          'auth.users'),
      ('reviews',           'user_id',     'auth.users'),
      ('reviews',           'business_id', 'public.businesses'),
      ('review_likes',      'user_id',     'auth.users'),
      ('review_likes',      'review_id',   'public.reviews'),
      ('favorites',         'user_id',     'auth.users'),
      ('favorites',         'business_id', 'public.businesses'),
      ('check_ins',         'user_id',     'auth.users'),
      ('check_ins',         'business_id', 'public.businesses'),
      ('notifications',     'user_id',     'auth.users'),
      ('notifications',     'business_id', 'public.businesses'),
      ('notifications',     'review_id',   'public.reviews'),
      ('fcm_tokens',        'user_id',     'auth.users'),
      ('usage_consent',     'user_id',     'auth.users'),
      ('usage_events',      'user_id',     'auth.users'),
      ('admins',            'user_id',     'auth.users'),
      ('rate_limit_events', 'user_id',     'auth.users'),
      ('business_images',   'business_id', 'public.businesses')
    ) AS t(tbl, col, ref)
  LOOP
    -- A table or column that this database does not have is skipped rather
    -- than failing the whole migration.
    IF to_regclass('public.' || target.tbl) IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM pg_attribute
          WHERE attrelid = to_regclass('public.' || target.tbl)
            AND attname = target.col AND NOT attisdropped) THEN
      RAISE NOTICE 'account deletion: public.%.% not found, skipped',
        target.tbl, target.col;
      CONTINUE;
    END IF;

    has_cascade := false;

    -- The check is on the shape of the constraint rather than its name. A
    -- key that exists without ON DELETE CASCADE is replaced.
    FOR existing IN
      SELECT c.conname, c.confdeltype
        FROM pg_constraint c
        JOIN pg_attribute a
          ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
       WHERE c.conrelid = to_regclass('public.' || target.tbl)
         AND c.contype = 'f'
         AND c.confrelid = target.ref::regclass
         AND array_length(c.conkey, 1) = 1
         AND a.attname = target.col
    LOOP
      IF existing.confdeltype = 'c' THEN
        has_cascade := true;
      ELSE
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',
                       target.tbl, existing.conname);
      END IF;
    END LOOP;

    IF NOT has_cascade THEN
      -- Nobody may write to the table between the cleanup and the new key.
      EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE',
                     target.tbl);

      -- Rows pointing at nothing. NULL (notifications.business_id and
      -- review_id are optional) is not an orphan and is kept.
      EXECUTE format(
        'DELETE FROM public.%I t
          WHERE t.%I IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM %s r WHERE r.id = t.%I)',
        target.tbl, target.col, target.ref, target.col);
      GET DIAGNOSTICS removed = ROW_COUNT;
      IF removed > 0 THEN
        RAISE NOTICE 'account deletion: removed % orphaned row(s) from public.% (%)',
          removed, target.tbl, target.col;
      END IF;

      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I
           FOREIGN KEY (%I) REFERENCES %s (id) ON DELETE CASCADE',
        target.tbl, target.tbl || '_' || target.col || '_fkey',
        target.col, target.ref);
    END IF;
  END LOOP;
END $blk$;

-- Deleting orphaned reviews above (only possible if 20261110000000 was not
-- applied first) is followed by the review stats trigger, so no rollup
-- resync is needed here.

-- The trigger that removes the businesses of a deleted account must exist:
-- businesses.owner_id has no foreign key to do it. It is created in
-- 20261006010000; fail loudly instead of silently leaving listings behind.
DO $blk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid = 'auth.users'::regclass
       AND tgname = 'auth_user_delete_owned_businesses'
       AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION
      'auth_user_delete_owned_businesses is missing: apply 20261006010000_orphan_owner_rating_rollups.sql first';
  END IF;
END $blk$;

COMMIT;
