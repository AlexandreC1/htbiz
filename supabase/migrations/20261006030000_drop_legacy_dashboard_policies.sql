-- Policies created by hand in the Supabase dashboard before the migrations
-- existed were never dropped. Postgres ORs permissive policies together, so
-- each of these silently re-opened a hole the hardening migration closed:
--
--   businesses "Authenticated users can create businesses"
--       any signed-in user could insert a business for another owner, or one
--       that is already verification_status = 'verified'.
--   businesses "Businesses are viewable by everyone"
--       soft-deleted businesses stayed readable by anyone.
--   reviews "Delete reviews when business is deleted"
--       a business owner could delete any customer review on their business.
--   reviews "Authenticated users can create reviews"
--       bypassed the auth.uid() = user_id check on insert.
--   storage "Allow authenticated users to upload images"
--       uploads into ANY bucket and path, including the private patents bucket.
--   storage "Authenticated users can upload" on the unused business-images bucket.
--
-- The others are duplicates of the hardened policies and are dropped so the
-- live policy list matches the migrations. The hardened replacements
-- (businesses_*, reviews_*, storage_images_*, storage_patents_*) are untouched.
-- Public read on the legacy business-images bucket stays so old image URLs work.

DROP POLICY IF EXISTS "Authenticated users can create businesses" ON public.businesses;
DROP POLICY IF EXISTS "Businesses are viewable by everyone"       ON public.businesses;
DROP POLICY IF EXISTS "Users can update own businesses"           ON public.businesses;
DROP POLICY IF EXISTS "Users can delete own businesses"           ON public.businesses;

DROP POLICY IF EXISTS "Authenticated users can create reviews"    ON public.reviews;
DROP POLICY IF EXISTS "Reviews are viewable by everyone"          ON public.reviews;
DROP POLICY IF EXISTS "Delete reviews when business is deleted"   ON public.reviews;

DROP POLICY IF EXISTS "Allow authenticated users to upload images 1jik568_0" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read access to images 1jik568_0"         ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload 14srpd1_0"             ON storage.objects;
