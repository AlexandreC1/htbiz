-- =====================================================================
-- HTBIZ - PRODUCTION HARDENING
-- =====================================================================
-- Idempotent. Safe to run repeatedly, in the SQL Editor or via
--   supabase db push
--
-- Fixes shipped here:
--   1.  UPDATE policies had no WITH CHECK - an owner could set
--       verification_status='verified' on their own business, rewrite the
--       rating/total_reviews, or reassign owner_id. Closed.
--   2.  A business owner could edit the *text and rating* of reviews left
--       on their business (the reviews UPDATE policy covers all columns).
--       Now they may only write owner_reply / owner_reply_at.
--   3.  is_verified_visit, user_name and user_email were client-supplied
--       and trivially spoofable. Now derived server-side.
--   4.  Owners could never read their own favourite counts (favorites is
--       select-own), so the analytics dashboard always showed 0.
--   5.  No indexes on any foreign key -> sequential scans on every screen.
--   6.  SECURITY DEFINER functions had a mutable search_path.
--   7.  Storage buckets had no size or MIME restrictions.
--   8.  The push trigger called a function that does not exist
--       (extensions.http_post) and read the service key from a server
--       setting that is never set, so pushes silently never fired.
-- =====================================================================


-- =====================================================================
-- 0. Helpers
-- =====================================================================

-- True when the statement runs with elevated rights: a service_role request,
-- a SECURITY DEFINER function owned by postgres (our own triggers), or an
-- explicitly flagged transaction. The column guards below consult this so
-- server-side code can still write protected columns.
CREATE OR REPLACE FUNCTION public.htbiz_is_privileged()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public, pg_catalog
AS $fn$
  SELECT
    coalesce(current_setting('htbiz.privileged', true), 'off') = 'on'
    OR coalesce(
         nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
         ''
       ) = 'service_role'
    OR current_user IN ('postgres', 'supabase_admin', 'service_role');
$fn$;

-- Admin allow-list. Previously "admin" existed only as an ADMIN_EMAILS env
-- var inside one edge function, so the database had no notion of an admin
-- and no admin could read a patent document through the API.
CREATE TABLE IF NOT EXISTS public.admins (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

-- Deliberately no policies: only service_role may read or write this table.
-- Add your first admin from the SQL editor:
--   INSERT INTO public.admins (user_id, note)
--   SELECT id, 'founder' FROM auth.users WHERE email = 'you@example.com'
--   ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.htbiz_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid());
$fn$;

GRANT EXECUTE ON FUNCTION public.htbiz_is_admin() TO authenticated;

-- Shared updated_at trigger.
CREATE OR REPLACE FUNCTION public.htbiz_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $fn$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;


-- =====================================================================
-- 1. Schema completions
-- =====================================================================

ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.reviews    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.profiles   ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Timestamps for the verification queue, so admins can order by age and the
-- owner dashboard can say "submitted 3 days ago".
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS verification_submitted_at TIMESTAMPTZ;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS verification_reviewed_at  TIMESTAMPTZ;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS verification_note         TEXT;

-- Soft delete: an accidental delete currently destroys every review, image
-- and favourite by cascade, with no way back.
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

DROP TRIGGER IF EXISTS trg_businesses_touch ON public.businesses;
CREATE TRIGGER trg_businesses_touch
  BEFORE UPDATE ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION public.htbiz_touch_updated_at();

DROP TRIGGER IF EXISTS trg_reviews_touch ON public.reviews;
CREATE TRIGGER trg_reviews_touch
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.htbiz_touch_updated_at();

DROP TRIGGER IF EXISTS trg_profiles_touch ON public.profiles;
CREATE TRIGGER trg_profiles_touch
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.htbiz_touch_updated_at();


-- =====================================================================
-- 2. Data integrity constraints
-- =====================================================================
-- ADD CONSTRAINT has no IF NOT EXISTS, so each one is guarded.

DO $blk$
BEGIN
  -- Ratings outside 1..5 break the star renderer, and a negative rating makes
  -- repeat('*', rating) in the notification trigger raise - which aborts the
  -- entire review insert.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_rating_range') THEN
    UPDATE public.reviews SET rating = least(greatest(coalesce(rating, 5), 1), 5)
      WHERE rating IS NULL OR rating < 1 OR rating > 5;
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_rating_range CHECK (rating BETWEEN 1 AND 5);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'businesses_verification_status_valid') THEN
    UPDATE public.businesses SET verification_status = 'none'
      WHERE verification_status IS NULL
         OR verification_status NOT IN ('none', 'pending', 'verified', 'rejected');
    ALTER TABLE public.businesses
      ADD CONSTRAINT businesses_verification_status_valid
      CHECK (verification_status IN ('none', 'pending', 'verified', 'rejected'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'businesses_latlng_range') THEN
    UPDATE public.businesses SET latitude = NULL, longitude = NULL
      WHERE (latitude  IS NOT NULL AND (latitude  < -90  OR latitude  > 90))
         OR (longitude IS NOT NULL AND (longitude < -180 OR longitude > 180));
    ALTER TABLE public.businesses
      ADD CONSTRAINT businesses_latlng_range CHECK (
        (latitude  IS NULL OR latitude  BETWEEN  -90 AND  90) AND
        (longitude IS NULL OR longitude BETWEEN -180 AND 180)
      );
  END IF;

  -- Bound user-generated text in the database, not only in the Dart
  -- sanitizer - that runs on the client and is therefore advisory.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'businesses_name_len') THEN
    ALTER TABLE public.businesses
      ADD CONSTRAINT businesses_name_len CHECK (char_length(name) BETWEEN 1 AND 120);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_comment_len') THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_comment_len
      CHECK (comment IS NULL OR char_length(comment) <= 2000);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_owner_reply_len') THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_owner_reply_len
      CHECK (owner_reply IS NULL OR char_length(owner_reply) <= 2000);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_image_urls_max') THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_image_urls_max
      CHECK (image_urls IS NULL
             OR array_length(image_urls, 1) IS NULL
             OR array_length(image_urls, 1) <= 6);
  END IF;
END $blk$;

-- One review per person per business. Non-destructive: if duplicates already
-- exist we report them rather than silently deleting somebody's data.
DO $blk$
DECLARE
  dupes INTEGER;
BEGIN
  SELECT count(*) INTO dupes FROM (
    SELECT user_id, business_id
    FROM public.reviews
    GROUP BY user_id, business_id
    HAVING count(*) > 1
  ) d;

  IF dupes = 0 THEN
    CREATE UNIQUE INDEX IF NOT EXISTS reviews_one_per_user_per_business
      ON public.reviews (user_id, business_id);
  ELSE
    RAISE NOTICE
      'Skipped reviews_one_per_user_per_business: % (user, business) pairs have duplicate reviews. Resolve them, then re-run.',
      dupes;
  END IF;
END $blk$;


-- =====================================================================
-- 3. Indexes - every foreign key the app filters on
-- =====================================================================

CREATE INDEX IF NOT EXISTS idx_businesses_owner_id     ON public.businesses (owner_id);
CREATE INDEX IF NOT EXISTS idx_businesses_category     ON public.businesses (category);
CREATE INDEX IF NOT EXISTS idx_businesses_created_at   ON public.businesses (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_businesses_pending      ON public.businesses (verification_submitted_at)
  WHERE verification_status = 'pending';

CREATE INDEX IF NOT EXISTS idx_reviews_business_id     ON public.reviews (business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id         ON public.reviews (user_id);

CREATE INDEX IF NOT EXISTS idx_favorites_user_id       ON public.favorites (user_id);
CREATE INDEX IF NOT EXISTS idx_favorites_business_id   ON public.favorites (business_id);

CREATE INDEX IF NOT EXISTS idx_business_images_biz     ON public.business_images (business_id, created_at);
CREATE INDEX IF NOT EXISTS idx_review_likes_review_id  ON public.review_likes (review_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_user_business ON public.check_ins (user_id, business_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_business_id   ON public.check_ins (business_id);

-- The unread badge runs on every app resume.
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON public.notifications (user_id, created_at DESC) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

-- Trigram index so ILIKE '%query%' search stops scanning the whole table.
-- Extension availability differs between a hosted project and a bare Postgres,
-- so a missing extension degrades to "no trigram index" rather than aborting
-- the whole migration.
DO $blk$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
  CREATE INDEX IF NOT EXISTS idx_businesses_name_trgm
    ON public.businesses USING gin (name gin_trgm_ops);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipped trigram index: %', SQLERRM;
END $blk$;


-- =====================================================================
-- 4. Column guards - the core security fix
-- =====================================================================
-- RLS decides *which rows* you may touch. It says nothing about *which
-- columns*. Both UPDATE policies were row-level only, so any owner could
-- PATCH /businesses?id=eq.<their id> with {"verification_status":"verified"}
-- and mint themselves a verified badge, and could rewrite the text of any
-- review left on their business. These BEFORE UPDATE triggers reinstate the
-- protected columns from OLD, which is enforced no matter what the client
-- sends.

-- NB: these guards are deliberately SECURITY INVOKER. A SECURITY DEFINER
-- trigger would run as postgres, htbiz_is_privileged() would always be true,
-- and the guard would let everything through.
CREATE OR REPLACE FUNCTION public.businesses_guard_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $fn$
BEGIN
  IF public.htbiz_is_privileged() THEN
    RETURN NEW;
  END IF;

  -- Never client-writable.
  NEW.owner_id                 := OLD.owner_id;
  NEW.created_at               := OLD.created_at;
  NEW.rating                   := OLD.rating;         -- maintained by trigger
  NEW.total_reviews            := OLD.total_reviews;  -- maintained by trigger
  NEW.verification_reviewed_at := OLD.verification_reviewed_at;
  NEW.verification_note        := OLD.verification_note;
  NEW.deleted_at               := OLD.deleted_at;

  -- The only verification transition a client may perform is submitting for
  -- review. Approval and rejection belong to the verify-business function.
  IF NEW.verification_status IS DISTINCT FROM OLD.verification_status THEN
    IF NEW.verification_status = 'pending'
       AND coalesce(OLD.verification_status, 'none') IN ('none', 'rejected') THEN
      NEW.verification_submitted_at := now();
    ELSE
      NEW.verification_status       := OLD.verification_status;
      NEW.verification_submitted_at := OLD.verification_submitted_at;
    END IF;
  ELSE
    NEW.verification_submitted_at := OLD.verification_submitted_at;
  END IF;

  -- A verified business that edits its patent document goes back in the queue,
  -- otherwise the badge could be earned with one document and kept with another.
  IF NEW.patent_doc_url IS DISTINCT FROM OLD.patent_doc_url
     AND OLD.verification_status = 'verified' THEN
    NEW.verification_status       := 'pending';
    NEW.verification_submitted_at := now();
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_businesses_guard ON public.businesses;
CREATE TRIGGER trg_businesses_guard
  BEFORE UPDATE ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION public.businesses_guard_columns();


CREATE OR REPLACE FUNCTION public.reviews_guard_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  biz_owner UUID;
BEGIN
  IF public.htbiz_is_privileged() THEN
    RETURN NEW;
  END IF;

  -- Identity of a review is immutable.
  NEW.id          := OLD.id;
  NEW.user_id     := OLD.user_id;
  NEW.business_id := OLD.business_id;
  NEW.created_at  := OLD.created_at;
  NEW.user_email  := OLD.user_email;

  SELECT owner_id INTO biz_owner FROM public.businesses WHERE id = OLD.business_id;

  IF auth.uid() = OLD.user_id THEN
    -- The author may edit their own review, but not answer on the owner's behalf.
    NEW.owner_reply       := OLD.owner_reply;
    NEW.owner_reply_at    := OLD.owner_reply_at;
    NEW.is_verified_visit := OLD.is_verified_visit;
    NEW.user_name         := OLD.user_name;

  ELSIF auth.uid() = biz_owner THEN
    -- The business owner may ONLY reply. Everything else is reinstated.
    NEW.rating            := OLD.rating;
    NEW.comment           := OLD.comment;
    NEW.image_urls        := OLD.image_urls;
    NEW.image_url         := OLD.image_url;
    NEW.is_verified_visit := OLD.is_verified_visit;
    NEW.user_name         := OLD.user_name;

    IF NEW.owner_reply IS DISTINCT FROM OLD.owner_reply THEN
      NEW.owner_reply_at := CASE WHEN NEW.owner_reply IS NULL THEN NULL ELSE now() END;
    END IF;

  ELSE
    RAISE EXCEPTION 'Not permitted to modify this review'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_reviews_guard ON public.reviews;
CREATE TRIGGER trg_reviews_guard
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.reviews_guard_columns();


-- Derive the review's trust signals server-side. The client used to send
-- is_verified_visit (computed from its own hasCheckedIn call) and the display
-- name, both of which any HTTP client could simply assert.
CREATE OR REPLACE FUNCTION public.reviews_stamp_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
BEGIN
  -- This one IS SECURITY DEFINER because it reads auth.users, so it must not
  -- consult htbiz_is_privileged(). auth.uid() reads the request JWT and is
  -- unaffected by the definer context: it is NULL for a service_role call,
  -- which is exactly when we want to trust the supplied user_id (seeding).
  NEW.user_id := coalesce(auth.uid(), NEW.user_id);

  NEW.is_verified_visit := EXISTS (
    SELECT 1 FROM public.check_ins
    WHERE user_id = NEW.user_id AND business_id = NEW.business_id
  );

  SELECT coalesce(p.full_name, split_part(u.email, '@', 1)), u.email
    INTO NEW.user_name, NEW.user_email
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE u.id = NEW.user_id;

  NEW.owner_reply    := NULL;
  NEW.owner_reply_at := NULL;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_reviews_stamp_identity ON public.reviews;
CREATE TRIGGER trg_reviews_stamp_identity
  BEFORE INSERT ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.reviews_stamp_identity();


-- Stop a client from rewriting its own primary key or promoting itself.
CREATE OR REPLACE FUNCTION public.profiles_guard_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $fn$
BEGIN
  IF public.htbiz_is_privileged() THEN
    RETURN NEW;
  END IF;

  NEW.id         := OLD.id;
  NEW.created_at := OLD.created_at;

  IF NEW.role IS DISTINCT FROM OLD.role
     AND NEW.role NOT IN ('client', 'business_owner') THEN
    NEW.role := OLD.role;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_profiles_guard ON public.profiles;
CREATE TRIGGER trg_profiles_guard
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_guard_columns();


-- =====================================================================
-- 5. RLS policies - add the missing WITH CHECK clauses
-- =====================================================================
-- Without WITH CHECK, a policy validates the row you started from but not the
-- row you are writing, so an owner could hand their business to another user.

DROP POLICY IF EXISTS "businesses_update_owner" ON public.businesses;
CREATE POLICY "businesses_update_owner"
  ON public.businesses FOR UPDATE
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "businesses_insert_authenticated" ON public.businesses;
CREATE POLICY "businesses_insert_authenticated"
  ON public.businesses FOR INSERT
  WITH CHECK (
    auth.uid() = owner_id
    AND coalesce(verification_status, 'none') = 'none'
  );

-- Hide soft-deleted rows from the public listing.
DROP POLICY IF EXISTS "businesses_select_public" ON public.businesses;
CREATE POLICY "businesses_select_public"
  ON public.businesses FOR SELECT
  USING (deleted_at IS NULL OR auth.uid() = owner_id);

DROP POLICY IF EXISTS "reviews_update_owner_or_biz_owner" ON public.reviews;
CREATE POLICY "reviews_update_owner_or_biz_owner"
  ON public.reviews FOR UPDATE
  USING (
    auth.uid() = user_id
    OR auth.uid() IN (SELECT owner_id FROM public.businesses WHERE id = reviews.business_id)
  )
  WITH CHECK (
    auth.uid() = user_id
    OR auth.uid() IN (SELECT owner_id FROM public.businesses WHERE id = reviews.business_id)
  );

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Signed-out visitors have no reason to enumerate the user table.
-- (profiles.email is still readable by any signed-in user; removing that
-- needs a column-level grant plus explicit column lists in every client
-- query, so it is tracked as a follow-up rather than done here - see the
-- backend plan, "Split public profile from private account".)
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
CREATE POLICY "profiles_select_authenticated"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

-- A user may withdraw a check-in; there was no DELETE policy at all.
DROP POLICY IF EXISTS "check_ins_delete_own" ON public.check_ins;
CREATE POLICY "check_ins_delete_own"
  ON public.check_ins FOR DELETE
  USING (auth.uid() = user_id);

-- Owners need to see check-ins against their own businesses for analytics.
DROP POLICY IF EXISTS "check_ins_select_own" ON public.check_ins;
CREATE POLICY "check_ins_select_own"
  ON public.check_ins FOR SELECT
  USING (
    auth.uid() = user_id
    OR auth.uid() IN (SELECT owner_id FROM public.businesses WHERE id = check_ins.business_id)
  );

-- fcm_tokens: the service-role policy from the push migration is redundant
-- (service_role bypasses RLS) and had no WITH CHECK.
DROP POLICY IF EXISTS "Service role full access on fcm_tokens" ON public.fcm_tokens;
DROP POLICY IF EXISTS "Users can manage their own tokens" ON public.fcm_tokens;
DROP POLICY IF EXISTS "fcm_tokens_own" ON public.fcm_tokens;
CREATE POLICY "fcm_tokens_own"
  ON public.fcm_tokens FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- =====================================================================
-- 6. Aggregates the client cannot compute under RLS
-- =====================================================================
-- favorites is select-own, so getFavoriteCount() always returned 0 for the
-- owner looking at their own analytics. Expose the count, not the rows.

CREATE OR REPLACE FUNCTION public.business_stats(p_business_id UUID)
RETURNS TABLE (
  favorite_count  INTEGER,
  check_in_count  INTEGER,
  review_count    INTEGER,
  average_rating  DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  biz_owner UUID;
BEGIN
  SELECT owner_id INTO biz_owner FROM public.businesses WHERE id = p_business_id;

  IF biz_owner IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;

  IF auth.uid() IS DISTINCT FROM biz_owner AND NOT public.htbiz_is_admin() THEN
    RAISE EXCEPTION 'Not permitted' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*)::INTEGER FROM public.favorites  WHERE business_id = p_business_id),
    (SELECT count(*)::INTEGER FROM public.check_ins  WHERE business_id = p_business_id),
    (SELECT count(*)::INTEGER FROM public.reviews    WHERE business_id = p_business_id),
    (SELECT coalesce(avg(rating), 0)::DOUBLE PRECISION FROM public.reviews WHERE business_id = p_business_id);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.business_stats(UUID) TO authenticated;

-- Unread badge without transferring 50 rows to count them.
CREATE OR REPLACE FUNCTION public.unread_notification_count()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
  SELECT count(*)::INTEGER
  FROM public.notifications
  WHERE user_id = auth.uid() AND is_read = false;
$fn$;

GRANT EXECUTE ON FUNCTION public.unread_notification_count() TO authenticated;

-- Soft delete, replacing the client's two-step "delete reviews, then delete
-- business" which is not atomic and leaves storage objects behind.
CREATE OR REPLACE FUNCTION public.soft_delete_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  biz_owner UUID;
BEGIN
  SELECT owner_id INTO biz_owner FROM public.businesses WHERE id = p_business_id;

  IF biz_owner IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;

  IF auth.uid() IS DISTINCT FROM biz_owner AND NOT public.htbiz_is_admin() THEN
    RAISE EXCEPTION 'Not permitted' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('htbiz.privileged', 'on', true);
  UPDATE public.businesses SET deleted_at = now() WHERE id = p_business_id;
  PERFORM set_config('htbiz.privileged', 'off', true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.soft_delete_business(UUID) TO authenticated;


-- =====================================================================
-- 7. Harden the existing SECURITY DEFINER functions
-- =====================================================================
-- Both were created without SET search_path. A SECURITY DEFINER function
-- with a mutable search_path can be hijacked by a caller who creates a
-- shadowing object in a schema earlier on the path.

CREATE OR REPLACE FUNCTION public.notify_on_new_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  biz_owner_id UUID;
  biz_name     TEXT;
BEGIN
  SELECT owner_id, name INTO biz_owner_id, biz_name
  FROM public.businesses WHERE id = NEW.business_id;

  IF biz_owner_id IS NOT NULL AND biz_owner_id <> NEW.user_id THEN
    INSERT INTO public.notifications (user_id, type, title, body, business_id, review_id, is_read)
    VALUES (
      biz_owner_id,
      'new_review',
      'New review on ' || coalesce(biz_name, 'your business'),
      coalesce(nullif(NEW.comment, ''), repeat('*', greatest(least(NEW.rating, 5), 1))),
      NEW.business_id,
      NEW.id,
      false
    );
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.update_business_review_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  target_business_id UUID;
  new_avg   DOUBLE PRECISION;
  new_count INTEGER;
BEGIN
  IF TG_OP = 'DELETE' THEN
    target_business_id := OLD.business_id;
  ELSE
    target_business_id := NEW.business_id;
  END IF;

  SELECT coalesce(avg(rating), 0), count(*)
    INTO new_avg, new_count
  FROM public.reviews
  WHERE business_id = target_business_id;

  -- Flag the transaction so businesses_guard_columns lets the write through.
  PERFORM set_config('htbiz.privileged', 'on', true);
  UPDATE public.businesses
     SET rating = new_avg, total_reviews = new_count
   WHERE id = target_business_id;
  PERFORM set_config('htbiz.privileged', 'off', true);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$fn$;


-- =====================================================================
-- 8. Storage: size and MIME limits
-- =====================================================================
-- Both buckets accepted any file of any size from any authenticated user.

INSERT INTO storage.buckets (id, name, public)
VALUES ('htbiz_patents', 'htbiz_patents', false)
ON CONFLICT (id) DO NOTHING;

UPDATE storage.buckets
   SET file_size_limit = 5242880,   -- 5 MB
       allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
 WHERE id = 'htbiz_images';

UPDATE storage.buckets
   SET file_size_limit = 10485760,  -- 10 MB
       allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
 WHERE id = 'htbiz_patents';

-- Uploads must land under a known top-level prefix, not just any folder whose
-- second segment happens to be the caller's uid.
DROP POLICY IF EXISTS "storage_images_insert_own" ON storage.objects;
CREATE POLICY "storage_images_insert_own"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'htbiz_images'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] IN ('businesses', 'reviews', 'avatars')
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

DROP POLICY IF EXISTS "storage_images_update_own" ON storage.objects;
CREATE POLICY "storage_images_update_own"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'htbiz_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'htbiz_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Admins must be able to read a patent to review it; before this, only the
-- uploader could, so the whole verification flow depended on service_role.
DROP POLICY IF EXISTS "storage_patents_select_own" ON storage.objects;
CREATE POLICY "storage_patents_select_own"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'htbiz_patents'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.htbiz_is_admin()
    )
  );

DROP POLICY IF EXISTS "storage_patents_delete_own" ON storage.objects;
CREATE POLICY "storage_patents_delete_own"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'htbiz_patents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );


-- =====================================================================
-- 9. Fix the push-notification trigger
-- =====================================================================
-- The previous version called extensions.http_post (pg_net installs into the
-- `net` schema, so that function does not exist) and read the service key
-- from current_setting('app.settings.service_role_key'), which is never set
-- on Supabase - so the IF guard was always false and no push ever fired.
--
-- Secrets now come from Vault. Register them once:
--
--   SELECT vault.create_secret('https://<ref>.supabase.co', 'htbiz_supabase_url');
--   SELECT vault.create_secret('<a long random string>', 'htbiz_push_secret');
--
-- and give the edge function the same value:
--   supabase secrets set PUSH_WEBHOOK_SECRET=<the same long random string>

DO $blk$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_net;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_net unavailable (%), push dispatch will no-op', SQLERRM;
END $blk$;

DO $blk$
BEGIN
  CREATE EXTENSION IF NOT EXISTS supabase_vault;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'supabase_vault unavailable (%)', SQLERRM;
END $blk$;

CREATE OR REPLACE FUNCTION public.trigger_send_push_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_catalog
AS $fn$
DECLARE
  base_url   TEXT;
  push_secret TEXT;
BEGIN
  SELECT decrypted_secret INTO base_url
    FROM vault.decrypted_secrets WHERE name = 'htbiz_supabase_url';
  SELECT decrypted_secret INTO push_secret
    FROM vault.decrypted_secrets WHERE name = 'htbiz_push_secret';

  IF base_url IS NULL OR push_secret IS NULL THEN
    RAISE WARNING 'Push skipped: vault secrets htbiz_supabase_url / htbiz_push_secret are not set';
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := rtrim(base_url, '/') || '/functions/v1/send-push-notification',
    body    := jsonb_build_object('record', to_jsonb(NEW)),
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-htbiz-push-secret', push_secret
               ),
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- A push failure must never roll back the notification insert, which would
  -- in turn roll back the review that produced it.
  RAISE WARNING 'Push dispatch failed: %', SQLERRM;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS on_notification_send_push ON public.notifications;
CREATE TRIGGER on_notification_send_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.trigger_send_push_notification();


-- =====================================================================
-- 10. Housekeeping
-- =====================================================================
-- Notifications are unbounded and the client only ever reads the newest 50.
CREATE OR REPLACE FUNCTION public.prune_old_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  removed INTEGER;
BEGIN
  WITH doomed AS (
    DELETE FROM public.notifications
    WHERE created_at < now() - INTERVAL '90 days' AND is_read = true
    RETURNING 1
  )
  SELECT count(*)::INTEGER INTO removed FROM doomed;
  RETURN removed;
END;
$fn$;

-- Schedule with pg_cron if available (Supabase: enable the extension first).
--   SELECT cron.schedule('prune-notifications', '0 3 * * 0',
--                        'SELECT public.prune_old_notifications()');

-- Refresh planner statistics for the new indexes.
ANALYZE public.businesses;
ANALYZE public.reviews;
ANALYZE public.favorites;
ANALYZE public.notifications;

-- =====================================================================
-- DONE
-- =====================================================================
-- After running:
--   1. INSERT your admin user into public.admins (see section 0).
--   2. Register the vault secrets in section 9.
--   3. supabase secrets set PUSH_WEBHOOK_SECRET=<same value>
--   4. supabase functions deploy send-push-notification --no-verify-jwt
--   5. supabase functions deploy verify-business
-- =====================================================================
