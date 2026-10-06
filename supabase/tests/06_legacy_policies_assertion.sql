-- After the cleanup, each hole the legacy policies opened must be closed and
-- the normal app paths must still work.
SELECT test_ok(NOT EXISTS (
  SELECT 1 FROM pg_policies
   WHERE policyname IN (
     'Authenticated users can create businesses', 'Businesses are viewable by everyone',
     'Users can update own businesses', 'Users can delete own businesses',
     'Authenticated users can create reviews', 'Reviews are viewable by everyone',
     'Delete reviews when business is deleted',
     'Allow authenticated users to upload images 1jik568_0',
     'Allow public read access to images 1jik568_0',
     'Authenticated users can upload 14srpd1_0')
), 'legacy dashboard policies are gone');

BEGIN;
SELECT test_login('33333333-3333-3333-3333-333333333333');
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  INSERT INTO public.businesses (name, category, address, owner_id, verification_status)
  VALUES ('Fake verified', 'Shop', 'PAP', '33333333-3333-3333-3333-333333333333', 'verified');
  RAISE EXCEPTION 'FAIL  a user can create an already-verified business';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  a user cannot create an already-verified business';
END $$;

DO $$
BEGIN
  INSERT INTO public.businesses (name, category, address, owner_id)
  VALUES ('Planted', 'Shop', 'PAP', '11111111-1111-1111-1111-111111111111');
  RAISE EXCEPTION 'FAIL  a user can create a business owned by someone else';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  a user cannot create a business owned by someone else';
END $$;

DO $$
BEGIN
  INSERT INTO storage.objects (bucket_id, name)
  VALUES ('htbiz_patents', '11111111-1111-1111-1111-111111111111/forged.pdf');
  RAISE EXCEPTION 'FAIL  a user can upload into another user''s patent folder';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  a user cannot upload into another user''s patent folder';
END $$;

INSERT INTO storage.objects (bucket_id, name)
VALUES ('htbiz_images', 'reviews/33333333-3333-3333-3333-333333333333/photo.jpg');
SELECT test_ok(true, 'own review image upload still works');

INSERT INTO public.businesses (name, category, address, owner_id)
VALUES ('My shop', 'Shop', 'PAP', '33333333-3333-3333-3333-333333333333');
SELECT test_ok(true, 'creating your own business still works');
ROLLBACK;

-- A business owner must not be able to delete a customer's review.
BEGIN;
SELECT test_login('11111111-1111-1111-1111-111111111111');
SET LOCAL ROLE authenticated;
WITH gone AS (
  DELETE FROM public.reviews
   WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id <> '11111111-1111-1111-1111-111111111111'
  RETURNING 1)
SELECT test_ok((SELECT count(*) FROM gone) = 0,
  'a business owner cannot delete customer reviews');
ROLLBACK;
