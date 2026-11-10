-- Puts the reviews table into the shape the live project is in before
-- 20261110000000_review_integrity_and_limits.sql: no foreign keys, no unique
-- index, and the orphaned and duplicate rows that state allowed.
ALTER TABLE public.reviews DROP CONSTRAINT IF EXISTS reviews_user_id_fkey;
ALTER TABLE public.reviews DROP CONSTRAINT IF EXISTS reviews_business_id_fkey;
DROP INDEX IF EXISTS public.reviews_one_per_user_per_business;

-- The storage API reads objects as anon; the stub only granted authenticated.
GRANT SELECT ON storage.objects TO anon;

INSERT INTO auth.users (id, email) VALUES
  ('66666666-6666-6666-6666-666666666666', 'limits@htbiz.test'),
  ('77777777-7777-7777-7777-777777777777', 'builder@htbiz.test'),
  ('88888888-8888-8888-8888-888888888888', 'leaving@htbiz.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.businesses (id, name, category, address, owner_id)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Boutik Integrite', 'Shop',
        'Delmas 33', '11111111-1111-1111-1111-111111111111')
ON CONFLICT DO NOTHING;

DELETE FROM public.reviews
 WHERE business_id IN ('cccccccc-cccc-cccc-cccc-cccccccccccc',
                       'f0f0f0f0-f0f0-f0f0-f0f0-f0f0f0f0f0f0');

INSERT INTO public.reviews (id, business_id, user_id, rating, comment, image_urls, updated_at)
VALUES
  -- Two reviews by the same user: the newer one (5 stars) must survive.
  ('c0000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
   '33333333-3333-3333-3333-333333333333', 1, 'old duplicate', '{}',
   now() - interval '10 days'),
  ('c0000000-0000-0000-0000-000000000002', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
   '33333333-3333-3333-3333-333333333333', 5, 'current duplicate', '{}',
   now() - interval '1 day'),
  -- The author's account no longer exists.
  ('c0000000-0000-0000-0000-000000000003', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
   'dddddddd-dddd-dddd-dddd-dddddddddddd', 1, 'orphaned author', '{}', now()),
  -- The business no longer exists.
  ('c0000000-0000-0000-0000-000000000004', 'f0f0f0f0-f0f0-f0f0-f0f0-f0f0f0f0f0f0',
   '44444444-4444-4444-4444-444444444444', 2, 'orphaned business', '{}', now()),
  -- Six images, allowed by the old constraint.
  ('c0000000-0000-0000-0000-000000000005', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
   '44444444-4444-4444-4444-444444444444', 3, 'six photos',
   ARRAY['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg', 'e.jpg', 'f.jpg'], now());

-- A review that must disappear with its author once the foreign key exists.
INSERT INTO public.reviews (id, business_id, user_id, rating, comment)
VALUES ('c0000000-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '88888888-8888-8888-8888-888888888888', 5, 'leaving soon');
