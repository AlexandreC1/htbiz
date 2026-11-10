-- =====================================================================
-- Assertions for 20261110000000_review_integrity_and_limits.sql
-- Fixtures come from 08_review_integrity_seed.sql.
-- =====================================================================

\set ON_ERROR_STOP on

-- "Log out": what a service_role request or the SQL editor looks like.
CREATE OR REPLACE FUNCTION test_logout()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', false);
END;
$$;
GRANT EXECUTE ON FUNCTION test_logout() TO authenticated;

RESET ROLE;
SELECT test_logout();

-- =====================================================================
-- 1. Cleanup: duplicates, orphans, image limit, rollups
-- =====================================================================
SELECT test_ok(
  (SELECT count(*) = 1 AND max(rating) = 5 FROM public.reviews
    WHERE business_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
      AND user_id = '33333333-3333-3333-3333-333333333333'),
  'duplicate reviews collapse to the most recently updated one');

SELECT test_ok(NOT EXISTS (
  SELECT 1 FROM public.reviews
   WHERE id IN ('c0000000-0000-0000-0000-000000000003',
                'c0000000-0000-0000-0000-000000000004')),
  'reviews of a missing author or a missing business are removed');

SELECT test_ok(
  (SELECT array_length(image_urls, 1) = 5 AND image_urls[5] = 'e.jpg'
     FROM public.reviews WHERE id = 'c0000000-0000-0000-0000-000000000005'),
  'a stored review with 6 images is trimmed to the first 5');

DO $$
BEGIN
  UPDATE public.reviews
     SET image_urls = ARRAY['1', '2', '3', '4', '5', '6']
   WHERE id = 'c0000000-0000-0000-0000-000000000005';
  RAISE EXCEPTION 'FAIL  a review accepted 6 images';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS  a review cannot hold more than 5 images';
END $$;

SELECT test_ok(
  (SELECT rating = 4 AND total_reviews = 2 FROM public.businesses
    WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  'rating rollup matches the reviews left after the cleanup');

SELECT test_ok(NOT EXISTS (
  SELECT 1
    FROM public.businesses b
    LEFT JOIN public.reviews r ON r.business_id = b.id
   GROUP BY b.id
  HAVING b.total_reviews <> count(r.id)
      OR abs(b.rating - coalesce(avg(r.rating), 0)) > 0.0001
), 'every business aggregate matches its reviews after the cleanup');

SELECT test_ok(EXISTS (
  SELECT 1 FROM pg_index i
   WHERE i.indexrelid = 'public.reviews_one_per_user_per_business'::regclass
     AND i.indisunique
), 'the one-review-per-user unique index exists');

SELECT test_ok(
  (SELECT count(*) = 2 FROM pg_constraint
    WHERE conrelid = 'public.reviews'::regclass AND contype = 'f'
      AND confdeltype = 'c'
      AND confrelid IN ('auth.users'::regclass, 'public.businesses'::regclass)),
  'reviews has cascading foreign keys to users and businesses');

DO $$
BEGIN
  INSERT INTO public.reviews (business_id, user_id, rating)
  VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc',
          'dddddddd-dddd-dddd-dddd-dddddddddddd', 3);
  RAISE EXCEPTION 'FAIL  a review was stored for a user that does not exist';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS  a review needs an existing user';
END $$;

-- =====================================================================
-- 2. Deleting an account removes its reviews and corrects the rating
-- =====================================================================
DELETE FROM auth.users WHERE id = '88888888-8888-8888-8888-888888888888';

SELECT test_ok(NOT EXISTS (
  SELECT 1 FROM public.reviews WHERE id = 'c0000000-0000-0000-0000-000000000006'
), 'deleting a user cascades to their reviews');

SELECT test_ok(
  (SELECT b.total_reviews = (SELECT count(*) FROM public.reviews r
                              WHERE r.business_id = b.id)
     FROM public.businesses b WHERE b.id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'the business rollup follows a cascaded review delete');

-- =====================================================================
-- 3. save_review is the only way to create a review
-- =====================================================================
SET ROLE authenticated;
SELECT test_login('44444444-4444-4444-4444-444444444444');

DO $$
BEGIN
  INSERT INTO public.reviews (business_id, user_id, rating, comment)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          '44444444-4444-4444-4444-444444444444', 5, 'straight through REST');
  RAISE EXCEPTION 'FAIL  a client inserted a review directly';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  a client cannot insert into reviews directly';
END $$;

SELECT test_ok(
  (SELECT count(*) = 1 FROM public.save_review(
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 2, '  Fresh review  ')),
  'save_review creates a review without table INSERT rights');

SELECT test_ok(
  (SELECT user_id = '44444444-4444-4444-4444-444444444444'
      AND comment = 'Fresh review' AND rating = 2
      AND user_name = 'new-user' AND user_email IS NULL
      AND NOT is_verified_visit AND owner_reply IS NULL
     FROM public.reviews
    WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      AND user_id = auth.uid()),
  'identity is still stamped from the session inside save_review');

-- =====================================================================
-- 4. Existing review behaviours still hold
-- =====================================================================
-- The owner replies with a direct update, and cannot rewrite the review.
SELECT test_login('11111111-1111-1111-1111-111111111111');
UPDATE public.reviews
   SET owner_reply = 'Thanks for coming', rating = 5, comment = 'Perfect'
 WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
   AND user_id = '44444444-4444-4444-4444-444444444444';

SELECT test_login('44444444-4444-4444-4444-444444444444');
SELECT test_ok(
  (SELECT owner_reply = 'Thanks for coming' AND owner_reply_at IS NOT NULL
      AND rating = 2 AND comment = 'Fresh review'
     FROM public.reviews
    WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      AND user_id = auth.uid()),
  'owner can still reply and still cannot rewrite the review');

-- The author edits directly; protected columns are reinstated by the guard.
UPDATE public.reviews
   SET comment = 'Edited by the author', owner_reply = 'forged',
       user_id = '33333333-3333-3333-3333-333333333333',
       is_verified_visit = true, user_name = 'Somebody Else'
 WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
   AND user_id = auth.uid();

SELECT test_ok(
  (SELECT comment = 'Edited by the author' AND owner_reply = 'Thanks for coming'
      AND NOT is_verified_visit AND user_name = 'new-user'
     FROM public.reviews
    WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      AND user_id = auth.uid()),
  'author can still edit their review and the guard columns still hold');

-- Saving again edits the same row and leaves the owner reply alone.
SELECT * FROM public.save_review('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 3, 'Second thoughts');
SELECT test_ok(
  (SELECT count(*) = 1 AND max(rating) = 3
      AND max(owner_reply) = 'Thanks for coming'
     FROM public.reviews
    WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      AND user_id = auth.uid()),
  'save_review edits the existing review and keeps the owner reply');

SELECT test_login('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE
  affected INTEGER;
BEGIN
  UPDATE public.reviews SET comment = 'hijacked'
   WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id = '44444444-4444-4444-4444-444444444444';
  GET DIAGNOSTICS affected = ROW_COUNT;
  PERFORM test_ok(affected = 0, 'a stranger still cannot update a review');
END;
$$;

SELECT test_login('44444444-4444-4444-4444-444444444444');
DELETE FROM public.reviews
 WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND user_id = auth.uid();
SELECT test_ok(NOT EXISTS (
  SELECT 1 FROM public.reviews
   WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND user_id = auth.uid()
), 'author can still delete their own review');

-- =====================================================================
-- 5. An owner cannot review their own business
-- =====================================================================
SELECT test_login('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  PERFORM public.save_review('cccccccc-cccc-cccc-cccc-cccccccccccc', 5, 'Best shop');
  RAISE EXCEPTION 'FAIL  an owner reviewed their own business';
EXCEPTION WHEN SQLSTATE 'HT001' THEN
  RAISE NOTICE 'PASS  an owner cannot review their own business';
END $$;

-- =====================================================================
-- 6. At most 10 new reviews per user per rolling 24 hours
-- =====================================================================
RESET ROLE;
SELECT test_logout();
INSERT INTO public.businesses (id, name, category, address, owner_id)
SELECT ('b1000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'Limit target ' || n, 'Shop', 'PAP',
       '11111111-1111-1111-1111-111111111111'
  FROM generate_series(1, 12) AS n
ON CONFLICT DO NOTHING;
SELECT test_ok(
  (SELECT count(*) = 0 FROM public.rate_limit_events
    WHERE action = 'business_create'),
  'privileged inserts are exempt from the business limit');

SET ROLE authenticated;
SELECT test_login('66666666-6666-6666-6666-666666666666');

DO $$
BEGIN
  FOR n IN 1..10 LOOP
    PERFORM public.save_review(
      ('b1000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 4);
  END LOOP;
  RAISE NOTICE 'PASS  10 reviews in a day are accepted';
END $$;

DO $$
BEGIN
  PERFORM public.save_review('b1000000-0000-0000-0000-000000000011', 4);
  RAISE EXCEPTION 'FAIL  an 11th review in a day was accepted';
EXCEPTION WHEN SQLSTATE 'HT002' THEN
  RAISE NOTICE 'PASS  the 11th new review in a day is rejected';
END $$;

SELECT * FROM public.save_review('b1000000-0000-0000-0000-000000000001', 1, 'Changed my mind');
SELECT test_ok(
  (SELECT rating = 1 FROM public.reviews
    WHERE business_id = 'b1000000-0000-0000-0000-000000000001'
      AND user_id = auth.uid()),
  'editing an existing review does not count toward the limit');

-- Deleting a review does not hand the allowance back.
DELETE FROM public.reviews
 WHERE business_id = 'b1000000-0000-0000-0000-000000000002' AND user_id = auth.uid();
DO $$
BEGIN
  PERFORM public.save_review('b1000000-0000-0000-0000-000000000011', 4);
  RAISE EXCEPTION 'FAIL  deleting a review reset the daily limit';
EXCEPTION WHEN SQLSTATE 'HT002' THEN
  RAISE NOTICE 'PASS  deleting a review does not reset the daily limit';
END $$;

DO $$
BEGIN
  PERFORM count(*) FROM public.rate_limit_events;
  RAISE EXCEPTION 'FAIL  a client can read the rate limit ledger';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  clients cannot read the rate limit ledger';
END $$;

-- The window is rolling: once the entries are a day old, reviewing works.
RESET ROLE;
UPDATE public.rate_limit_events
   SET occurred_at = now() - interval '25 hours'
 WHERE user_id = '66666666-6666-6666-6666-666666666666';
SET ROLE authenticated;
SELECT test_ok(
  (SELECT count(*) = 1 FROM public.save_review(
     'b1000000-0000-0000-0000-000000000011', 4)),
  'the review limit lifts after 24 hours');

-- =====================================================================
-- 7. At most 3 new businesses per day and 10 unverified in total
-- =====================================================================
SELECT test_login('77777777-7777-7777-7777-777777777777');

INSERT INTO public.businesses (name, category, address, owner_id)
SELECT 'Day shop ' || n, 'Shop', 'PAP', '77777777-7777-7777-7777-777777777777'
  FROM generate_series(1, 3) AS n;

DO $$
BEGIN
  INSERT INTO public.businesses (name, category, address, owner_id)
  VALUES ('Day shop 4', 'Shop', 'PAP', '77777777-7777-7777-7777-777777777777');
  RAISE EXCEPTION 'FAIL  a 4th business in a day was accepted';
EXCEPTION WHEN SQLSTATE 'HT003' THEN
  RAISE NOTICE 'PASS  the 4th new business in a day is rejected';
END $$;

SELECT test_ok(
  (SELECT count(*) = 3 FROM public.businesses WHERE owner_id = auth.uid()),
  '3 new businesses in a day are accepted and the rejected one is not stored');

-- Bring the owner to 10 unverified businesses with the daily allowance reset.
RESET ROLE;
SELECT test_logout();
INSERT INTO public.businesses (name, category, address, owner_id)
SELECT 'Older shop ' || n, 'Shop', 'PAP', '77777777-7777-7777-7777-777777777777'
  FROM generate_series(1, 7) AS n;
DELETE FROM public.rate_limit_events
 WHERE user_id = '77777777-7777-7777-7777-777777777777';

SET ROLE authenticated;
SELECT test_login('77777777-7777-7777-7777-777777777777');
DO $$
BEGIN
  INSERT INTO public.businesses (name, category, address, owner_id)
  VALUES ('One too many', 'Shop', 'PAP', '77777777-7777-7777-7777-777777777777');
  RAISE EXCEPTION 'FAIL  an 11th unverified business was accepted';
EXCEPTION WHEN SQLSTATE 'HT004' THEN
  RAISE NOTICE 'PASS  an owner cannot hold more than 10 unverified businesses';
END $$;

-- A verified business does not count toward the cap.
RESET ROLE;
UPDATE public.businesses SET verification_status = 'verified'
 WHERE owner_id = '77777777-7777-7777-7777-777777777777' AND name = 'Older shop 1';
SET ROLE authenticated;
INSERT INTO public.businesses (name, category, address, owner_id)
VALUES ('After verification', 'Shop', 'PAP', '77777777-7777-7777-7777-777777777777');
SELECT test_ok(true, 'a verified business frees a place under the cap');

-- Neither does a soft-deleted one.
SELECT public.soft_delete_business(
  (SELECT id FROM public.businesses
    WHERE owner_id = auth.uid() AND name = 'Older shop 2'));
INSERT INTO public.businesses (name, category, address, owner_id)
VALUES ('After soft delete', 'Shop', 'PAP', '77777777-7777-7777-7777-777777777777');
SELECT test_ok(true, 'a soft-deleted business frees a place under the cap');

-- =====================================================================
-- 8. At most 100 review likes per rolling 24 hours
-- =====================================================================
SELECT test_login('66666666-6666-6666-6666-666666666666');

INSERT INTO public.review_likes (review_id, user_id)
VALUES ('c0000000-0000-0000-0000-000000000002', '66666666-6666-6666-6666-666666666666');
-- The app upserts with ignoreDuplicates: a repeat must not use up the limit.
INSERT INTO public.review_likes (review_id, user_id)
VALUES ('c0000000-0000-0000-0000-000000000002', '66666666-6666-6666-6666-666666666666')
ON CONFLICT (review_id, user_id) DO NOTHING;

RESET ROLE;
SELECT test_ok(
  (SELECT count(*) = 1 FROM public.rate_limit_events
    WHERE user_id = '66666666-6666-6666-6666-666666666666'
      AND action = 'review_like'),
  'a like is counted once and a repeated like is not counted');

INSERT INTO public.rate_limit_events (user_id, action)
SELECT '66666666-6666-6666-6666-666666666666', 'review_like'
  FROM generate_series(1, 99);

SET ROLE authenticated;
DO $$
BEGIN
  INSERT INTO public.review_likes (review_id, user_id)
  VALUES ('c0000000-0000-0000-0000-000000000005', '66666666-6666-6666-6666-666666666666');
  RAISE EXCEPTION 'FAIL  a 101st like in a day was accepted';
EXCEPTION WHEN SQLSTATE 'HT005' THEN
  RAISE NOTICE 'PASS  the 101st like in a day is rejected';
END $$;

DELETE FROM public.review_likes
 WHERE review_id = 'c0000000-0000-0000-0000-000000000002' AND user_id = auth.uid();
SELECT test_ok(
  (SELECT count(*) = 0 FROM public.review_likes WHERE user_id = auth.uid()),
  'unliking still works at the limit');

-- =====================================================================
-- 9. Function privileges
-- =====================================================================
RESET ROLE;
SELECT test_logout();

SELECT test_ok(
  NOT has_function_privilege('anon', 'public.prune_old_notifications()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.prune_old_notifications()', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.prune_old_notifications()', 'EXECUTE'),
  'only the service role may execute prune_old_notifications');

SET ROLE anon;
DO $$
BEGIN
  PERFORM public.prune_old_notifications();
  RAISE EXCEPTION 'FAIL  anon executed prune_old_notifications';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  anon cannot execute prune_old_notifications';
END $$;

DO $$
BEGIN
  PERFORM public.save_review('cccccccc-cccc-cccc-cccc-cccccccccccc', 5);
  RAISE EXCEPTION 'FAIL  anon executed save_review';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS  anon cannot execute save_review';
END $$;

-- Policies that apply to anon call htbiz_is_admin(); it must stay callable or
-- the read itself fails.
SELECT test_ok((SELECT count(*) >= 0 FROM storage.objects),
  'anon can still read storage objects through the patents policy');
SELECT test_ok((SELECT count(*) > 0 FROM public.reviews),
  'anon can still read reviews');
RESET ROLE;

SELECT test_ok(NOT EXISTS (
  SELECT 1
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND (p.prorettype = 'pg_catalog.trigger'::regtype
          OR p.proname IN ('prune_old_notifications', 'purge_expired_usage',
                           'htbiz_consume_rate_limit'))
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
), 'no trigger or maintenance function is executable through the API');

SELECT test_ok(NOT EXISTS (
  SELECT 1
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname NOT IN ('htbiz_is_admin', 'test_login', 'test_ok', 'test_logout')
     AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = p.oid AND d.deptype = 'e')
     AND has_function_privilege('anon', p.oid, 'EXECUTE')
), 'anon can execute nothing in public except htbiz_is_admin');

SELECT test_ok(
  (SELECT bool_and(has_function_privilege('authenticated', f::regprocedure, 'EXECUTE'))
     FROM unnest(ARRAY[
       'public.save_review(uuid,integer,text,text[],boolean)',
       'public.business_stats(uuid)',
       'public.unread_notification_count()',
       'public.soft_delete_business(uuid)',
       'public.set_usage_consent(boolean)',
       'public.record_usage(text,text,text,integer,integer,integer,text,numeric,numeric)',
       'public.delete_my_usage()',
       'public.usage_summary()',
       'public.get_usage_retention_days()',
       'public.set_usage_retention_days(smallint)',
       'public.htbiz_is_admin()',
       'public.htbiz_is_privileged()'
     ]) AS f),
  'every function the app calls is still executable when signed in');

-- New functions start closed.
CREATE FUNCTION public.test_default_privileges() RETURNS INTEGER
LANGUAGE sql AS 'SELECT 1';
SELECT test_ok(
  NOT has_function_privilege('anon', 'public.test_default_privileges()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.test_default_privileges()', 'EXECUTE'),
  'a new function is not executable through the API by default');
DROP FUNCTION public.test_default_privileges();

-- The signed-in app paths that go through helpers and RPCs still work.
SET ROLE authenticated;
SELECT test_login('11111111-1111-1111-1111-111111111111');
SELECT test_ok(public.htbiz_is_admin() = false, 'htbiz_is_admin still answers');
SELECT test_ok(public.unread_notification_count() >= 0,
  'unread_notification_count still answers');
SELECT test_ok(
  (SELECT review_count = 2 FROM public.business_stats(
     'cccccccc-cccc-cccc-cccc-cccccccccccc')),
  'business_stats still answers for the owner');
UPDATE public.businesses SET description = 'Still editable'
 WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
SELECT test_ok(
  (SELECT description = 'Still editable' FROM public.businesses
    WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  'owner can still edit a business through the guard trigger');

RESET ROLE;
SELECT test_logout();

SELECT 'ALL REVIEW INTEGRITY ASSERTIONS PASSED' AS result;
