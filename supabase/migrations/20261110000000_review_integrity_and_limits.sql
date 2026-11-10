-- =====================================================================
-- HTBIZ - REVIEW INTEGRITY AND ABUSE LIMITS
-- =====================================================================
-- Idempotent. Safe to run repeatedly.
--
-- WARNING: THIS MIGRATION DELETES DATA. Read sections 1 and 2 before
-- applying it to a live project, and take a backup first:
--   * reviews whose author no longer exists in auth.users are deleted
--   * reviews whose business no longer exists are deleted
--   * when one user has several reviews on one business, only the most
--     recently updated one is kept
--
-- Fixes shipped here:
--   1.  reviews had no foreign keys, so deleting an account or a business
--       left its reviews (and their stars) behind forever.
--   2.  The one-review-per-user index was skipped on any database that
--       already held duplicates, which is exactly where it was needed.
--   3.  A client could INSERT into reviews directly through REST, skipping
--       save_review and every rule it enforces. save_review is now the only
--       way to create a review.
--   4.  An owner could review their own business.
--   5.  Nothing was rate limited. Reviews, new businesses and review likes
--       now have per-user limits enforced in the database.
--   6.  reviews.image_urls allowed 6 images; the app allows 5.
--   7.  Trigger and maintenance functions were executable by anon through
--       /rest/v1/rpc. EXECUTE is now granted only where the app needs it.
--   8.  prune_old_notifications was never scheduled.
--
-- Error codes raised for the client (PostgREST returns them as "code"):
--   HT001  you cannot review your own business
--   HT002  daily review limit reached
--   HT003  daily new business limit reached
--   HT004  too many unverified businesses
--   HT005  daily like limit reached
-- =====================================================================

BEGIN;

-- Nobody may write a review while the cleanup and the new constraints go in.
LOCK TABLE public.reviews IN SHARE ROW EXCLUSIVE MODE;


-- =====================================================================
-- 1. Remove reviews that point at nothing
-- =====================================================================
-- Without foreign keys, deleting an account or a business left its reviews
-- behind. They cannot be edited or removed by anyone and still count toward
-- the business rating. They must go before the foreign keys can be added.
-- The review stats trigger recalculates each affected business as rows are
-- deleted; section 4 resyncs every aggregate again to be certain.

DELETE FROM public.reviews r
 WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = r.user_id);

DELETE FROM public.reviews r
 WHERE NOT EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = r.business_id);


-- =====================================================================
-- 2. One review per user per business
-- =====================================================================
-- The hardening migration only created this index when no duplicates
-- existed. Keep the most recently updated review of each pair (that is the
-- one the author last meant) and delete the older ones.

DELETE FROM public.reviews r
 USING (
   SELECT id,
          row_number() OVER (
            PARTITION BY user_id, business_id
            ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
          ) AS position
     FROM public.reviews
 ) ranked
 WHERE ranked.id = r.id
   AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS reviews_one_per_user_per_business
  ON public.reviews (user_id, business_id);


-- =====================================================================
-- 3. Foreign keys
-- =====================================================================
-- ADD CONSTRAINT has no IF NOT EXISTS. The check is on the shape of the
-- constraint rather than its name, because databases built from the test
-- baseline already carry these keys under their default names. A key that
-- exists without ON DELETE CASCADE is replaced.

DO $blk$
DECLARE
  target RECORD;
  existing RECORD;
  has_cascade BOOLEAN;
BEGIN
  FOR target IN
    SELECT * FROM (VALUES
      ('user_id',     'auth.users'::regclass,        'reviews_user_id_fkey'),
      ('business_id', 'public.businesses'::regclass, 'reviews_business_id_fkey')
    ) AS t(col, ref, conname)
  LOOP
    has_cascade := false;

    FOR existing IN
      SELECT c.conname, c.confdeltype
        FROM pg_constraint c
        JOIN pg_attribute a
          ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
       WHERE c.conrelid = 'public.reviews'::regclass
         AND c.contype = 'f'
         AND c.confrelid = target.ref
         AND array_length(c.conkey, 1) = 1
         AND a.attname = target.col
    LOOP
      IF existing.confdeltype = 'c' THEN
        has_cascade := true;
      ELSE
        EXECUTE format('ALTER TABLE public.reviews DROP CONSTRAINT %I', existing.conname);
      END IF;
    END LOOP;

    IF NOT has_cascade THEN
      EXECUTE format(
        'ALTER TABLE public.reviews ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %s (id) ON DELETE CASCADE',
        target.conname, target.col, target.ref);
    END IF;
  END LOOP;
END $blk$;


-- =====================================================================
-- 4. Image limit, then resync the rating rollups
-- =====================================================================
-- The app lets a reviewer attach 5 photos. Trim any stored row that holds
-- more (the extra URL is dropped from the row; the storage object is not
-- touched) and tighten the constraint to match.

UPDATE public.reviews
   SET image_urls = image_urls[1:5]
 WHERE array_length(image_urls, 1) > 5;

ALTER TABLE public.reviews DROP CONSTRAINT IF EXISTS reviews_image_urls_max;
ALTER TABLE public.reviews
  ADD CONSTRAINT reviews_image_urls_max
  CHECK (image_urls IS NULL
         OR array_length(image_urls, 1) IS NULL
         OR array_length(image_urls, 1) <= 5);

-- Same statement as 20261006020000_resync_rating_rollups.sql: after the
-- deletes above every business must match its remaining reviews.
-- businesses_guard_columns reinstates rating/total_reviews unless privileged.
SELECT set_config('htbiz.privileged', 'on', true);

WITH actual AS (
  SELECT b.id,
         coalesce(avg(r.rating), 0)::DOUBLE PRECISION AS avg_rating,
         count(r.id)::INTEGER                         AS review_count
    FROM public.businesses b
    LEFT JOIN public.reviews r ON r.business_id = b.id
   GROUP BY b.id
)
UPDATE public.businesses b
   SET rating = a.avg_rating, total_reviews = a.review_count
  FROM actual a
 WHERE a.id = b.id
   AND (b.total_reviews IS DISTINCT FROM a.review_count
        OR abs(coalesce(b.rating, 0) - a.avg_rating) > 0.0001);

SELECT set_config('htbiz.privileged', 'off', true);


-- =====================================================================
-- 5. Rate limit ledger
-- =====================================================================
-- Counting rows in the limited table is not enough: a user could insert,
-- delete and insert again all day (each new review also pushes a
-- notification to the owner). Every counted action is recorded here
-- instead, so deleting the row does not give the allowance back.
--
-- No policies and no grants: only the functions below touch this table.

CREATE TABLE IF NOT EXISTS public.rate_limit_events (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action      TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS rate_limit_events_lookup
  ON public.rate_limit_events (user_id, action, occurred_at DESC);

ALTER TABLE public.rate_limit_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rate_limit_events FROM PUBLIC, anon, authenticated;

-- Records one use of p_action by p_user, or raises p_errcode when the user
-- already used it p_max times inside p_window. Expired entries of the same
-- user and action are removed on the way, so the table stays small without
-- a scheduled job.
--
-- Internal: it takes the user as a parameter, so it must never be callable
-- through the API. It is only called from the SECURITY DEFINER functions in
-- this file, which run as the owner.
CREATE OR REPLACE FUNCTION public.htbiz_consume_rate_limit(
  p_user UUID, p_action TEXT, p_max INTEGER, p_window INTERVAL,
  p_errcode TEXT, p_message TEXT
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $fn$
BEGIN
  -- Serialize per user and action, so parallel requests cannot all read the
  -- same count and slip past the limit together.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('limit:' || p_action || ':' || p_user::text, 0));

  DELETE FROM public.rate_limit_events
   WHERE user_id = p_user AND action = p_action
     AND occurred_at < now() - p_window;

  IF (SELECT count(*) FROM public.rate_limit_events
       WHERE user_id = p_user AND action = p_action) >= p_max THEN
    RAISE EXCEPTION '%', p_message USING ERRCODE = p_errcode;
  END IF;

  INSERT INTO public.rate_limit_events (user_id, action) VALUES (p_user, p_action);
END;
$fn$;


-- =====================================================================
-- 6. save_review is the only way to create a review
-- =====================================================================
-- The INSERT policy let any signed-in client POST /rest/v1/reviews, which
-- skipped the soft-delete check, the self-review check and the daily limit.
-- Clients lose INSERT on the table altogether; UPDATE and DELETE are kept,
-- because authors edit and delete their own review and owners reply with a
-- direct update (both still pass through RLS and reviews_guard_columns).

DROP POLICY IF EXISTS "reviews_insert_authenticated" ON public.reviews;
DROP POLICY IF EXISTS "Authenticated users can create reviews" ON public.reviews;
REVOKE INSERT ON public.reviews FROM PUBLIC, anon, authenticated;

-- save_review therefore has to be SECURITY DEFINER, and that has a cost that
-- must be handled here: inside it current_user is the owner, so
-- htbiz_is_privileged() is true and reviews_guard_columns lets every column
-- through, and RLS does not apply. The function is safe because it never
-- trusts the caller for anything but the five parameters:
--   * the row it updates is found by auth.uid(), never by a supplied id
--   * it writes only the columns an author may write (rating, comment,
--     images, anonymity); owner_reply, user_name, is_verified_visit,
--     created_at and the identity columns are not in the SET list
--   * on insert, reviews_stamp_identity still runs and still takes user_id,
--     user_name and is_verified_visit from auth.uid(), which reads the
--     request JWT and is not changed by the definer context
-- The signature is unchanged, so the app keeps calling it the same way.
CREATE OR REPLACE FUNCTION public.save_review(
  p_business_id UUID, p_rating INTEGER, p_comment TEXT DEFAULT NULL,
  p_image_urls TEXT[] DEFAULT '{}', p_anonymous BOOLEAN DEFAULT false
) RETURNS SETOF public.reviews
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  caller      UUID := auth.uid();
  biz_owner   UUID;
  existing_id UUID;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to review' USING ERRCODE = '42501';
  END IF;
  IF p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '23514';
  END IF;

  SELECT owner_id INTO biz_owner FROM public.businesses
   WHERE id = p_business_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business unavailable' USING ERRCODE = '23503';
  END IF;

  -- An owner rating their own business is not a review.
  IF biz_owner = caller THEN
    RAISE EXCEPTION 'You cannot review your own business'
      USING ERRCODE = 'HT001';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(caller::text || p_business_id::text, 0));
  SELECT id INTO existing_id FROM public.reviews
    WHERE business_id = p_business_id AND user_id = caller
    ORDER BY created_at, id LIMIT 1;

  IF existing_id IS NOT NULL THEN
    -- Editing an existing review never counts toward the daily limit.
    RETURN QUERY UPDATE public.reviews SET
      rating = p_rating, comment = nullif(btrim(p_comment), ''),
      is_anonymous = coalesce(p_anonymous, false),
      image_urls = coalesce(p_image_urls, '{}'), image_url = p_image_urls[1]
      WHERE id = existing_id AND user_id = caller RETURNING *;
  ELSE
    PERFORM public.htbiz_consume_rate_limit(
      caller, 'review_create', 10, INTERVAL '24 hours', 'HT002',
      'You have reached the limit of 10 new reviews per day');
    RETURN QUERY INSERT INTO public.reviews
      (business_id, user_id, rating, comment, image_urls, image_url, is_anonymous)
    VALUES (p_business_id, caller, p_rating, nullif(btrim(p_comment), ''),
      coalesce(p_image_urls, '{}'), p_image_urls[1], coalesce(p_anonymous, false))
    RETURNING *;
  END IF;
END;
$fn$;


-- =====================================================================
-- 7. Limits on new businesses and review likes
-- =====================================================================
-- Both are AFTER INSERT triggers, so they only count rows that were really
-- written: an insert refused by RLS, or a like skipped by ON CONFLICT DO
-- NOTHING, never reaches them. Raising here rolls the insert back.
--
-- They are SECURITY DEFINER because they write the ledger, so (like
-- reviews_stamp_identity) they must not consult htbiz_is_privileged(), which
-- would always be true. They look at the request instead: a service_role
-- request, the SQL editor and server-side jobs carry no user id and are
-- exempt, as is a transaction explicitly flagged as privileged.

CREATE OR REPLACE FUNCTION public.businesses_enforce_limits()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  caller UUID := auth.uid();
BEGIN
  IF caller IS NULL
     OR coalesce(current_setting('htbiz.privileged', true), 'off') = 'on' THEN
    RETURN NULL;
  END IF;

  -- Every creation counts for 24 hours, even if the business is deleted
  -- again, so deleting cannot be used to get around the limit.
  PERFORM public.htbiz_consume_rate_limit(
    caller, 'business_create', 3, INTERVAL '24 hours', 'HT003',
    'You have reached the limit of 3 new businesses per day');

  -- The row just inserted is included in this count. Soft-deleted businesses
  -- do not count.
  IF (SELECT count(*) FROM public.businesses
       WHERE owner_id = caller
         AND deleted_at IS NULL
         AND coalesce(verification_status, 'none') <> 'verified') > 10 THEN
    RAISE EXCEPTION 'You have reached the limit of 10 unverified businesses'
      USING ERRCODE = 'HT004';
  END IF;

  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_businesses_enforce_limits ON public.businesses;
CREATE TRIGGER trg_businesses_enforce_limits
  AFTER INSERT ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION public.businesses_enforce_limits();

CREATE OR REPLACE FUNCTION public.review_likes_enforce_limits()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  caller UUID := auth.uid();
BEGIN
  IF caller IS NULL
     OR coalesce(current_setting('htbiz.privileged', true), 'off') = 'on' THEN
    RETURN NULL;
  END IF;

  PERFORM public.htbiz_consume_rate_limit(
    caller, 'review_like', 100, INTERVAL '24 hours', 'HT005',
    'You have reached the limit of 100 likes per day');

  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_review_likes_enforce_limits ON public.review_likes;
CREATE TRIGGER trg_review_likes_enforce_limits
  AFTER INSERT ON public.review_likes
  FOR EACH ROW EXECUTE FUNCTION public.review_likes_enforce_limits();


-- =====================================================================
-- 8. Function privileges
-- =====================================================================
-- Postgres grants EXECUTE on every new function to PUBLIC, and a Supabase
-- project also grants it to anon and authenticated by default. Every
-- function in `public` is therefore an endpoint under /rest/v1/rpc unless
-- it is revoked. None of ours was.

-- 8a. Trigger functions. Firing a trigger does not check EXECUTE (it is
-- checked once, when the trigger is created), so nobody needs it. Extension
-- owned functions are left alone.
DO $blk$
DECLARE
  fn RECORD;
BEGIN
  FOR fn IN
    SELECT format('%I.%I(%s)', n.nspname, p.proname,
                  pg_get_function_identity_arguments(p.oid)) AS signature
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prorettype = 'pg_catalog.trigger'::regtype
       AND NOT EXISTS (
         SELECT 1 FROM pg_depend d
          WHERE d.classid = 'pg_proc'::regclass
            AND d.objid = p.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
                   fn.signature);
  END LOOP;
END $blk$;

-- 8b. Everything else, by name. A function that an earlier migration has not
-- created yet on this database is skipped rather than failing the run.
--
--   server     maintenance and internals. No API role may call them.
--   signed_in  exactly what the Flutter app calls with .rpc(, plus
--              usage_retention_days_for_admin, which the usage_events
--              policy (TO authenticated) calls.
--              htbiz_is_privileged() is here too: the SECURITY INVOKER
--              guard triggers call it as `authenticated`, and revoking it
--              would fail every client update. anon never reaches a guard
--              (RLS leaves it no row to update), so anon loses it.
--   policy     htbiz_is_admin() only. storage_patents_select_own uses it
--              and applies to every role, so anon must keep it or every
--              anonymous read of storage.objects fails with "permission
--              denied for function". It only ever answers for the caller,
--              and is false for anon.
DO $blk$
DECLARE
  entry RECORD;
BEGIN
  FOR entry IN
    SELECT * FROM (VALUES
      ('server',    'public.prune_old_notifications()'),
      ('server',    'public.purge_expired_usage()'),
      ('server',    'public.htbiz_consume_rate_limit(uuid,text,integer,interval,text,text)'),
      ('signed_in', 'public.save_review(uuid,integer,text,text[],boolean)'),
      ('signed_in', 'public.business_stats(uuid)'),
      ('signed_in', 'public.unread_notification_count()'),
      ('signed_in', 'public.soft_delete_business(uuid)'),
      ('signed_in', 'public.set_usage_consent(boolean)'),
      ('signed_in', 'public.record_usage(text,text,text,integer,integer,integer,text,numeric,numeric)'),
      ('signed_in', 'public.delete_my_usage()'),
      ('signed_in', 'public.usage_summary()'),
      ('signed_in', 'public.get_usage_retention_days()'),
      ('signed_in', 'public.set_usage_retention_days(smallint)'),
      ('signed_in', 'public.usage_retention_days_for_admin(uuid)'),
      ('signed_in', 'public.htbiz_is_privileged()'),
      ('policy',    'public.htbiz_is_admin()')
    ) AS t(audience, signature)
  LOOP
    IF to_regprocedure(entry.signature) IS NULL THEN
      RAISE NOTICE 'Skipped privileges for %: function does not exist', entry.signature;
      CONTINUE;
    END IF;

    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
                   entry.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', entry.signature);

    IF entry.audience IN ('signed_in', 'policy') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', entry.signature);
    END IF;
    IF entry.audience = 'policy' THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', entry.signature);
    END IF;
  END LOOP;
END $blk$;

-- 8c. Functions created from now on (by the role running this migration)
-- start closed. A new function that the app must call needs an explicit
--   GRANT EXECUTE ON FUNCTION ... TO authenticated;
-- The PUBLIC default can only be changed globally, not per schema.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;


-- =====================================================================
-- 9. Schedule the notification pruning
-- =====================================================================
-- Same guarded pattern as 20261007010000_user_selected_usage_retention.sql:
-- Supabase ships pg_cron, local and test Postgres images may not. The job is
-- replaced by name so the migration stays idempotent. Weekly, Sunday 03:23.
DO $blk$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron';
    IF to_regclass('cron.job') IS NOT NULL THEN
      EXECUTE 'SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = ''htbiz-prune-notifications''';
      EXECUTE 'SELECT cron.schedule(''htbiz-prune-notifications'', ''23 3 * * 0'', ''SELECT public.prune_old_notifications()'')';
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron is unavailable; old notifications must be pruned by an external scheduler';
  END IF;
END;
$blk$;

COMMIT;

ANALYZE public.reviews;
ANALYZE public.businesses;
