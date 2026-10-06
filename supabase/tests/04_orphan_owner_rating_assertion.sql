-- Legacy/migrated rows can refer to an owner who no longer exists in auth.users.
-- A notification FK failure must not roll back the customer's review/rating.
BEGIN;
SET LOCAL session_replication_role = replica;
UPDATE public.businesses
   SET owner_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET LOCAL session_replication_role = origin;

DO $$
DECLARE
  test_review_id UUID;
  count_before INTEGER;
  count_after INTEGER;
  avg_before NUMERIC;
  avg_after NUMERIC;
BEGIN
  SELECT count(*)::INTEGER, coalesce(avg(rating), 0)
    INTO count_before, avg_before
    FROM public.reviews
   WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  INSERT INTO public.reviews (business_id, user_id, rating, comment)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          '44444444-4444-4444-4444-444444444444', 1, 'rating trigger regression')
  RETURNING id INTO test_review_id;

  SELECT count(*)::INTEGER, coalesce(avg(rating), 0)
    INTO count_after, avg_after
    FROM public.reviews
   WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  PERFORM test_ok(count_after = count_before + 1,
    'orphan business owner does not block review submission');
  PERFORM test_ok(
    (SELECT total_reviews = count_after AND abs(rating - avg_after) < 0.0001
       FROM public.businesses WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'rating trigger updates aggregate when owner account is missing');
  PERFORM test_ok(NOT EXISTS (
    SELECT 1 FROM public.notifications n WHERE n.review_id = test_review_id
  ), 'no notification is created for a missing owner account');

  DELETE FROM public.reviews WHERE id = test_review_id;
END $$;
ROLLBACK;
