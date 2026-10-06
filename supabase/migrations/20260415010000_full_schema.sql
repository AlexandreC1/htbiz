-- =====================================================
-- HTBIZ FULL MIGRATION
-- Run this in Supabase SQL Editor (Dashboard > SQL Editor)
-- Safe to run multiple times (uses IF NOT EXISTS / IF EXISTS)
-- =====================================================

-- =====================================================
-- STEP 1: Add missing columns to existing tables
-- =====================================================

-- Businesses: location columns
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Businesses: verification columns
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'none';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS patent_doc_url TEXT;

-- Reviews: verified visit flag
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_verified_visit BOOLEAN DEFAULT false;

-- Reviews: user display name and email
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS user_name TEXT;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS user_email TEXT;

-- Reviews: multiple images (replaces single image_url going forward; old column kept for backward compat)
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS image_urls TEXT[] DEFAULT '{}'::TEXT[];
-- Backfill: move any existing single image_url into the array
UPDATE reviews
  SET image_urls = ARRAY[image_url]
  WHERE image_url IS NOT NULL
    AND (image_urls IS NULL OR array_length(image_urls, 1) IS NULL);

-- =====================================================
-- STEP 2: Create new tables
-- =====================================================

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  business_id UUID REFERENCES businesses(id) ON DELETE CASCADE,
  review_id UUID REFERENCES reviews(id) ON DELETE CASCADE,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Review likes
CREATE TABLE IF NOT EXISTS review_likes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  review_id UUID NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(review_id, user_id)
);

-- Check-ins
CREATE TABLE IF NOT EXISTS check_ins (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, business_id)
);

-- =====================================================
-- STEP 3: Enable RLS on all tables
-- =====================================================

ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_images ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- STEP 4: RLS Policies (DROP IF EXISTS + CREATE)
-- =====================================================

-- ---- BUSINESSES ----
DROP POLICY IF EXISTS "businesses_select_public" ON businesses;
CREATE POLICY "businesses_select_public"
  ON businesses FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "businesses_insert_authenticated" ON businesses;
CREATE POLICY "businesses_insert_authenticated"
  ON businesses FOR INSERT
  WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "businesses_update_owner" ON businesses;
CREATE POLICY "businesses_update_owner"
  ON businesses FOR UPDATE
  USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "businesses_delete_owner" ON businesses;
CREATE POLICY "businesses_delete_owner"
  ON businesses FOR DELETE
  USING (auth.uid() = owner_id);

-- ---- REVIEWS ----
DROP POLICY IF EXISTS "reviews_select_public" ON reviews;
CREATE POLICY "reviews_select_public"
  ON reviews FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "reviews_insert_authenticated" ON reviews;
CREATE POLICY "reviews_insert_authenticated"
  ON reviews FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "reviews_update_owner_or_biz_owner" ON reviews;
CREATE POLICY "reviews_update_owner_or_biz_owner"
  ON reviews FOR UPDATE
  USING (
    auth.uid() = user_id
    OR auth.uid() IN (
      SELECT owner_id FROM businesses WHERE id = reviews.business_id
    )
  );

DROP POLICY IF EXISTS "reviews_delete_own" ON reviews;
CREATE POLICY "reviews_delete_own"
  ON reviews FOR DELETE
  USING (auth.uid() = user_id);

-- ---- PROFILES ----
DROP POLICY IF EXISTS "profiles_select_public" ON profiles;
CREATE POLICY "profiles_select_public"
  ON profiles FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "profiles_upsert_own" ON profiles;
CREATE POLICY "profiles_upsert_own"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

-- ---- FAVORITES ----
DROP POLICY IF EXISTS "favorites_select_own" ON favorites;
CREATE POLICY "favorites_select_own"
  ON favorites FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "favorites_insert_own" ON favorites;
CREATE POLICY "favorites_insert_own"
  ON favorites FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "favorites_delete_own" ON favorites;
CREATE POLICY "favorites_delete_own"
  ON favorites FOR DELETE
  USING (auth.uid() = user_id);

-- ---- NOTIFICATIONS ----
-- Users can only read/update/delete their OWN notifications.
-- INSERT is restricted: only DB triggers and service_role (edge functions) can create.
DROP POLICY IF EXISTS "notifications_select_own" ON notifications;
CREATE POLICY "notifications_select_own"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

-- REMOVE the old open insert policy if it exists
DROP POLICY IF EXISTS "notifications_insert_authenticated" ON notifications;

-- New: only service_role can insert (edge functions + triggers bypass RLS)
-- No INSERT policy for regular users = they cannot insert.

DROP POLICY IF EXISTS "notifications_update_own" ON notifications;
CREATE POLICY "notifications_update_own"
  ON notifications FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "notifications_delete_own" ON notifications;
CREATE POLICY "notifications_delete_own"
  ON notifications FOR DELETE
  USING (auth.uid() = user_id);

-- ---- REVIEW LIKES ----
DROP POLICY IF EXISTS "review_likes_select_public" ON review_likes;
CREATE POLICY "review_likes_select_public"
  ON review_likes FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "review_likes_insert_own" ON review_likes;
CREATE POLICY "review_likes_insert_own"
  ON review_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "review_likes_delete_own" ON review_likes;
CREATE POLICY "review_likes_delete_own"
  ON review_likes FOR DELETE
  USING (auth.uid() = user_id);

-- ---- CHECK-INS ----
DROP POLICY IF EXISTS "check_ins_select_own" ON check_ins;
CREATE POLICY "check_ins_select_own"
  ON check_ins FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "check_ins_insert_own" ON check_ins;
CREATE POLICY "check_ins_insert_own"
  ON check_ins FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ---- BUSINESS IMAGES ----
DROP POLICY IF EXISTS "business_images_select_public" ON business_images;
CREATE POLICY "business_images_select_public"
  ON business_images FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "business_images_insert_owner" ON business_images;
CREATE POLICY "business_images_insert_owner"
  ON business_images FOR INSERT
  WITH CHECK (
    auth.uid() IN (
      SELECT owner_id FROM businesses WHERE id = business_images.business_id
    )
  );

DROP POLICY IF EXISTS "business_images_delete_owner" ON business_images;
CREATE POLICY "business_images_delete_owner"
  ON business_images FOR DELETE
  USING (
    auth.uid() IN (
      SELECT owner_id FROM businesses WHERE id = business_images.business_id
    )
  );

-- =====================================================
-- STEP 5: DB Trigger — auto-create notification on new review
-- (replaces the client-side notification creation)
-- =====================================================

CREATE OR REPLACE FUNCTION notify_on_new_review()
RETURNS TRIGGER AS $$
DECLARE
  biz_owner_id UUID;
  biz_name TEXT;
BEGIN
  -- Get the business owner
  SELECT owner_id, name INTO biz_owner_id, biz_name
  FROM businesses WHERE id = NEW.business_id;

  -- Don't notify if reviewing own business
  IF biz_owner_id IS NOT NULL AND biz_owner_id != NEW.user_id THEN
    INSERT INTO notifications (user_id, type, title, body, business_id, review_id, is_read)
    VALUES (
      biz_owner_id,
      'new_review',
      'New review on ' || biz_name,
      COALESCE(NEW.comment, repeat('★', NEW.rating)),
      NEW.business_id,
      NEW.id,
      false
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_notify_on_new_review ON reviews;
CREATE TRIGGER trigger_notify_on_new_review
  AFTER INSERT ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION notify_on_new_review();

-- =====================================================
-- STEP 6: DB Trigger — auto-update business rating/total_reviews
-- (runs on review insert, update, or delete so stats are always correct)
-- =====================================================

CREATE OR REPLACE FUNCTION update_business_review_stats()
RETURNS TRIGGER AS $$
DECLARE
  target_business_id UUID;
  new_avg DOUBLE PRECISION;
  new_count INTEGER;
BEGIN
  -- Determine which business to update
  IF TG_OP = 'DELETE' THEN
    target_business_id := OLD.business_id;
  ELSE
    target_business_id := NEW.business_id;
  END IF;

  -- Recalculate stats
  SELECT COALESCE(AVG(rating), 0), COUNT(*)
  INTO new_avg, new_count
  FROM reviews
  WHERE business_id = target_business_id;

  -- Update the business record (SECURITY DEFINER bypasses RLS)
  UPDATE businesses
  SET rating = new_avg, total_reviews = new_count
  WHERE id = target_business_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_business_review_stats ON reviews;
CREATE TRIGGER trigger_update_business_review_stats
  AFTER INSERT OR UPDATE OF rating OR DELETE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION update_business_review_stats();

-- =====================================================
-- STEP 7: Storage — create private bucket for patents
-- =====================================================
-- Run this via Supabase Dashboard > Storage > New Bucket:
--   Name: htbiz_patents
--   Public: OFF (PRIVATE)
--
-- Or via SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('htbiz_patents', 'htbiz_patents', false)
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- STEP 8: Storage RLS Policies
-- =====================================================

-- ---- htbiz_images (public bucket) ----
-- Anyone can view images
DROP POLICY IF EXISTS "storage_images_select_public" ON storage.objects;
CREATE POLICY "storage_images_select_public"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'htbiz_images');

-- Authenticated users upload to their own folder only
DROP POLICY IF EXISTS "storage_images_insert_own" ON storage.objects;
CREATE POLICY "storage_images_insert_own"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'htbiz_images'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Users can delete their own uploads
DROP POLICY IF EXISTS "storage_images_delete_own" ON storage.objects;
CREATE POLICY "storage_images_delete_own"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'htbiz_images'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- ---- htbiz_patents (PRIVATE bucket) ----
-- Only the uploader can read their own patent docs
DROP POLICY IF EXISTS "storage_patents_select_own" ON storage.objects;
CREATE POLICY "storage_patents_select_own"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'htbiz_patents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Authenticated users upload to their own folder
DROP POLICY IF EXISTS "storage_patents_insert_own" ON storage.objects;
CREATE POLICY "storage_patents_insert_own"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'htbiz_patents'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- DONE
-- =====================================================
-- After running this, also:
-- 1. Deploy the edge function:  supabase functions deploy verify-business
-- 2. Set ADMIN_EMAILS secret:   supabase secrets set ADMIN_EMAILS=your@email.com
-- 3. Remove client-side notification creation from the Flutter code
--    (the DB trigger now handles it automatically)
