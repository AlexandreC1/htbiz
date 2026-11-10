-- =====================================================================
-- Assertions for 20261111000000_account_deletion.sql
-- Fixtures come from 09_account_deletion_seed.sql.
-- =====================================================================

\set ON_ERROR_STOP on

RESET ROLE;
SELECT test_logout();

-- =====================================================================
-- 1. The migration: orphans removed, every key cascades
-- =====================================================================
SELECT test_ok(NOT EXISTS (
  SELECT 1 FROM public.profiles
   WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
), 'a profile without an account is removed');

SELECT test_ok(NOT EXISTS (
  SELECT 1 FROM public.favorites
   WHERE user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
), 'a favorite without an account is removed');

SELECT test_ok(
  (SELECT count(*) = 3 FROM public.profiles
    WHERE id IN ('11111111-1111-1111-1111-111111111111',
                 '22222222-2222-2222-2222-222222222222',
                 '99999999-9999-9999-9999-999999999999')),
  'profiles of existing accounts are kept by the cleanup');

-- Every column that points at an account, a business or a review must have
-- exactly one single-column foreign key, and it must cascade.
SELECT test_ok(
  (SELECT count(*) = 1 AND bool_and(c.confdeltype = 'c')
     FROM pg_constraint c
     JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.conrelid = ('public.' || t.tbl)::regclass
      AND c.contype = 'f'
      AND c.confrelid = t.ref::regclass
      AND array_length(c.conkey, 1) = 1
      AND a.attname = t.col),
  format('%s.%s cascades from %s', t.tbl, t.col, t.ref))
  FROM (VALUES
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
  ) AS t(tbl, col, ref);

DO $$
BEGIN
  INSERT INTO public.profiles (id, email, role)
  VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'ghost@htbiz.test', 'client');
  RAISE EXCEPTION 'FAIL  a profile was stored for an account that does not exist';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS  a profile needs an existing account';
END $$;

SELECT test_ok(
  (SELECT rating = 3 AND total_reviews = 2 FROM public.businesses
    WHERE id = 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0'),
  'fixture: the other business starts at 3.0 from 2 reviews');

-- =====================================================================
-- 2. Deleting the account, exactly as the admin API does
-- =====================================================================
DELETE FROM auth.users WHERE id = '99999999-9999-9999-9999-999999999999';

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.profiles
               WHERE id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes its profile');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.reviews
               WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes the reviews it wrote');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.review_likes
               WHERE user_id = '99999999-9999-9999-9999-999999999999'
                  OR review_id = 'd0000000-0000-0000-0000-000000000002'),
  'deleting an account removes its likes and the likes on its reviews');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.favorites
               WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes its favorites');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.check_ins
               WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes its check-ins');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.notifications
               WHERE user_id = '99999999-9999-9999-9999-999999999999'
                  OR review_id = 'd0000000-0000-0000-0000-000000000002'),
  'deleting an account removes its notifications and those about its reviews');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.fcm_tokens
               WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes its push tokens');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.usage_consent
               WHERE user_id = '99999999-9999-9999-9999-999999999999')
  AND NOT EXISTS (SELECT 1 FROM public.usage_events
                   WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes its analytics consent and events');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.admins
               WHERE user_id = '99999999-9999-9999-9999-999999999999')
  AND NOT EXISTS (SELECT 1 FROM public.rate_limit_events
                   WHERE user_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes its admin grant and rate limit ledger');

-- ---- Businesses the account owned ------------------------------------
SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.businesses
               WHERE owner_id = '99999999-9999-9999-9999-999999999999'),
  'deleting an account removes the businesses it owned');

SELECT test_ok(
  NOT EXISTS (SELECT 1 FROM public.business_images
               WHERE business_id = 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0')
  AND NOT EXISTS (SELECT 1 FROM public.reviews
                   WHERE business_id = 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0')
  AND NOT EXISTS (SELECT 1 FROM public.favorites
                   WHERE business_id = 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0')
  AND NOT EXISTS (SELECT 1 FROM public.check_ins
                   WHERE business_id = 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0')
  AND NOT EXISTS (SELECT 1 FROM public.notifications
                   WHERE business_id = 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0'),
  'images, reviews, favorites, check-ins and notifications of those businesses go too');

-- ---- What must not be touched -----------------------------------------
SELECT test_ok(
  (SELECT rating = 5 AND total_reviews = 1 FROM public.businesses
    WHERE id = 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0'),
  'the rating of a business the account reviewed is recomputed (5.0 from 1)');

SELECT test_ok(NOT EXISTS (
  SELECT 1
    FROM public.businesses b
    LEFT JOIN public.reviews r ON r.business_id = b.id
   GROUP BY b.id
  HAVING b.total_reviews <> count(r.id)
      OR abs(b.rating - coalesce(avg(r.rating), 0)) > 0.0001
), 'every business aggregate matches its reviews after the deletion');

SELECT test_ok(
  EXISTS (SELECT 1 FROM public.reviews
           WHERE id = 'd0000000-0000-0000-0000-000000000003')
  AND EXISTS (SELECT 1 FROM public.review_likes
               WHERE review_id = 'd0000000-0000-0000-0000-000000000003'
                 AND user_id = '33333333-3333-3333-3333-333333333333')
  AND EXISTS (SELECT 1 FROM public.favorites
               WHERE user_id = '33333333-3333-3333-3333-333333333333'
                 AND business_id = 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0')
  AND EXISTS (SELECT 1 FROM public.notifications
               WHERE review_id = 'd0000000-0000-0000-0000-000000000003')
  AND (SELECT count(*) = 3 FROM public.profiles
        WHERE id IN ('11111111-1111-1111-1111-111111111111',
                     '22222222-2222-2222-2222-222222222222',
                     '33333333-3333-3333-3333-333333333333')),
  'data of other accounts is left alone');

SELECT 'ALL ACCOUNT DELETION ASSERTIONS PASSED' AS result;
