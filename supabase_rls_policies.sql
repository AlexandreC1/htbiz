-- =====================================================
-- HTBIZ Row Level Security (RLS) Policies
-- Run this in your Supabase SQL Editor
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_images ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- BUSINESSES
-- =====================================================

-- Anyone can read businesses
CREATE POLICY "businesses_select_public"
  ON businesses FOR SELECT
  USING (true);

-- Only authenticated users can insert (owner_id must match)
CREATE POLICY "businesses_insert_own"
  ON businesses FOR INSERT
  WITH CHECK (auth.uid() = owner_id);

-- Only the owner can update their business
CREATE POLICY "businesses_update_own"
  ON businesses FOR UPDATE
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Only the owner can delete their business
CREATE POLICY "businesses_delete_own"
  ON businesses FOR DELETE
  USING (auth.uid() = owner_id);

-- =====================================================
-- REVIEWS
-- =====================================================

-- Anyone can read reviews
CREATE POLICY "reviews_select_public"
  ON reviews FOR SELECT
  USING (true);

-- Authenticated users can insert reviews (user_id must match)
CREATE POLICY "reviews_insert_own"
  ON reviews FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Reviewers can update their own review text/rating
-- Business owners can update owner_reply fields on reviews for their businesses
CREATE POLICY "reviews_update"
  ON reviews FOR UPDATE
  USING (
    auth.uid() = user_id
    OR auth.uid() IN (
      SELECT owner_id FROM businesses WHERE id = reviews.business_id
    )
  );

-- Reviewers can delete their own reviews
CREATE POLICY "reviews_delete_own"
  ON reviews FOR DELETE
  USING (auth.uid() = user_id);

-- =====================================================
-- FAVORITES
-- =====================================================

-- Users can read their own favorites
CREATE POLICY "favorites_select_own"
  ON favorites FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own favorites
CREATE POLICY "favorites_insert_own"
  ON favorites FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own favorites
CREATE POLICY "favorites_delete_own"
  ON favorites FOR DELETE
  USING (auth.uid() = user_id);

-- =====================================================
-- NOTIFICATIONS
-- =====================================================

-- Users can read their own notifications
CREATE POLICY "notifications_select_own"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

-- Authenticated users can create notifications for others
-- (triggered when leaving a review on someone's business)
CREATE POLICY "notifications_insert_authenticated"
  ON notifications FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Users can update (mark read) their own notifications
CREATE POLICY "notifications_update_own"
  ON notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own notifications
CREATE POLICY "notifications_delete_own"
  ON notifications FOR DELETE
  USING (auth.uid() = user_id);

-- =====================================================
-- PROFILES
-- =====================================================

-- Anyone can read profiles (needed for displaying user info)
CREATE POLICY "profiles_select_public"
  ON profiles FOR SELECT
  USING (true);

-- Users can insert their own profile
CREATE POLICY "profiles_insert_own"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- =====================================================
-- BUSINESS_IMAGES
-- =====================================================

-- Anyone can read business images
CREATE POLICY "business_images_select_public"
  ON business_images FOR SELECT
  USING (true);

-- Only the business owner can add images to their business
CREATE POLICY "business_images_insert_owner"
  ON business_images FOR INSERT
  WITH CHECK (
    auth.uid() IN (
      SELECT owner_id FROM businesses WHERE id = business_images.business_id
    )
  );

-- Only the business owner can delete images from their business
CREATE POLICY "business_images_delete_owner"
  ON business_images FOR DELETE
  USING (
    auth.uid() IN (
      SELECT owner_id FROM businesses WHERE id = business_images.business_id
    )
  );

-- =====================================================
-- REVIEW_LIKES
-- =====================================================

-- Create table if needed:
-- CREATE TABLE review_likes (
--   id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
--   review_id UUID NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
--   user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
--   created_at TIMESTAMPTZ DEFAULT now(),
--   UNIQUE(review_id, user_id)
-- );

ALTER TABLE review_likes ENABLE ROW LEVEL SECURITY;

-- Anyone can read like counts
CREATE POLICY "review_likes_select_public"
  ON review_likes FOR SELECT
  USING (true);

-- Authenticated users can like (must be their own user_id)
CREATE POLICY "review_likes_insert_own"
  ON review_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can remove their own likes
CREATE POLICY "review_likes_delete_own"
  ON review_likes FOR DELETE
  USING (auth.uid() = user_id);

-- =====================================================
-- CHECK_INS
-- =====================================================

-- Create table if needed:
-- CREATE TABLE check_ins (
--   id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
--   user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
--   business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
--   created_at TIMESTAMPTZ DEFAULT now(),
--   UNIQUE(user_id, business_id)
-- );

ALTER TABLE check_ins ENABLE ROW LEVEL SECURITY;

-- Users can read their own check-ins
CREATE POLICY "check_ins_select_own"
  ON check_ins FOR SELECT
  USING (auth.uid() = user_id);

-- Authenticated users can check in (must be their own user_id)
CREATE POLICY "check_ins_insert_own"
  ON check_ins FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- =====================================================
-- STORAGE POLICIES (htbiz_images bucket)
-- =====================================================
-- Run these separately if you haven't already:

-- Allow authenticated users to upload to their own folder
-- CREATE POLICY "storage_upload_own"
--   ON storage.objects FOR INSERT
--   WITH CHECK (
--     bucket_id = 'htbiz_images'
--     AND auth.role() = 'authenticated'
--     AND (storage.foldername(name))[2] = auth.uid()::text
--   );

-- Allow public read on all images
-- CREATE POLICY "storage_read_public"
--   ON storage.objects FOR SELECT
--   USING (bucket_id = 'htbiz_images');

-- Allow users to delete their own uploads
-- CREATE POLICY "storage_delete_own"
--   ON storage.objects FOR DELETE
--   USING (
--     bucket_id = 'htbiz_images'
--     AND auth.role() = 'authenticated'
--     AND (storage.foldername(name))[2] = auth.uid()::text
--   );
