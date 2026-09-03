-- =====================================================================
-- Security assertions for 20260902000000_production_hardening.sql
--
-- Every test below reproduces something that WAS possible before the
-- hardening migration. Run with:  supabase/tests/run.sh
-- Any failure raises and aborts the run with a non-zero exit code.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION test_login(p_user UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION test_ok(p_condition BOOLEAN, p_label TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_condition THEN
    RAISE NOTICE 'PASS  %', p_label;
  ELSE
    RAISE EXCEPTION 'FAIL  %', p_label;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Fixtures (as the privileged owner, before dropping into `authenticated`)
-- ---------------------------------------------------------------------

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'owner@htbiz.test'),
  ('22222222-2222-2222-2222-222222222222', 'reviewer@htbiz.test'),
  ('33333333-3333-3333-3333-333333333333', 'stranger@htbiz.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role) VALUES
  ('11111111-1111-1111-1111-111111111111', 'owner@htbiz.test', 'Ovni Owner', 'business_owner'),
  ('22222222-2222-2222-2222-222222222222', 'reviewer@htbiz.test', 'Rita Reviewer', 'client'),
  ('33333333-3333-3333-3333-333333333333', 'stranger@htbiz.test', 'Sam Stranger', 'client')
ON CONFLICT DO NOTHING;

INSERT INTO public.businesses (id, name, description, category, address, owner_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Kay Manje', 'Good food',
        'Restaurant', 'Rue Capois, PAP', '11111111-1111-1111-1111-111111111111')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Run every test as `authenticated`, the role PostgREST actually uses.
-- ---------------------------------------------------------------------
SET ROLE authenticated;

-- =====================================================================
-- 1. An owner cannot mint their own verified badge.
--    Before: the UPDATE policy was row-level only, so
--    PATCH /businesses {"verification_status":"verified"} succeeded.
-- =====================================================================
SELECT test_login('11111111-1111-1111-1111-111111111111');

UPDATE public.businesses
   SET verification_status = 'verified'
 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT test_ok(
  (SELECT verification_status FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'none',
  'owner cannot self-verify'
);

-- ... but may submit for review.
UPDATE public.businesses
   SET verification_status = 'pending', patent_doc_url = '1111/patent.pdf'
 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT test_ok(
  (SELECT verification_status FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'pending',
  'owner can submit for verification'
);

SELECT test_ok(
  (SELECT verification_submitted_at IS NOT NULL FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'submission timestamp is stamped server-side'
);

-- =====================================================================
-- 2. An owner cannot hand their business to someone else, or fake its rating.
-- =====================================================================
UPDATE public.businesses
   SET owner_id = '33333333-3333-3333-3333-333333333333',
       rating = 5.0,
       total_reviews = 999
 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT test_ok(
  (SELECT owner_id FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
      = '11111111-1111-1111-1111-111111111111',
  'owner_id is immutable from the client'
);

SELECT test_ok(
  (SELECT rating = 0 AND total_reviews = 0 FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'rating and total_reviews are not client-writable'
);

-- =====================================================================
-- 3. Review identity is derived server-side, not taken from the client.
-- =====================================================================
SELECT test_login('22222222-2222-2222-2222-222222222222');

INSERT INTO public.reviews (id, business_id, user_id, rating, comment,
                            is_verified_visit, user_name, user_email)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '22222222-2222-2222-2222-222222222222',
        1, 'Slow service',
        true,                    -- claimed, with no check-in to back it
        'Totally Someone Else',  -- spoofed display name
        'spoofed@example.com');

SELECT test_ok(
  (SELECT NOT is_verified_visit FROM public.reviews
    WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'is_verified_visit cannot be claimed without a check-in'
);

SELECT test_ok(
  (SELECT user_name = 'Rita Reviewer' AND user_email = 'reviewer@htbiz.test'
     FROM public.reviews WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'reviewer name and email come from the session, not the payload'
);

-- The rating trigger fed the real average through, despite test 2.
SELECT test_ok(
  (SELECT rating = 1 AND total_reviews = 1 FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'review stats trigger still updates the business'
);

-- A real check-in makes the next review verified.
INSERT INTO public.check_ins (user_id, business_id)
VALUES ('22222222-2222-2222-2222-222222222222',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- =====================================================================
-- 4. A business owner may reply to a review but NOT rewrite it.
--    Before: the UPDATE policy let the owner change rating and comment.
-- =====================================================================
SELECT test_login('11111111-1111-1111-1111-111111111111');

UPDATE public.reviews
   SET rating = 5,
       comment = 'Actually it was wonderful!',
       owner_reply = 'Sorry to hear that, please come back.'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SELECT test_ok(
  (SELECT rating = 1 AND comment = 'Slow service' FROM public.reviews
    WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'business owner cannot rewrite a review'
);

SELECT test_ok(
  (SELECT owner_reply = 'Sorry to hear that, please come back.'
      AND owner_reply_at IS NOT NULL
     FROM public.reviews WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'business owner can reply, and the timestamp is server-side'
);

-- =====================================================================
-- 5. The review author may edit their own text but not answer for the owner.
-- =====================================================================
SELECT test_login('22222222-2222-2222-2222-222222222222');

UPDATE public.reviews
   SET comment = 'Slow service, but the food was good',
       owner_reply = 'We are the best!'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SELECT test_ok(
  (SELECT comment = 'Slow service, but the food was good' FROM public.reviews
    WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'author can edit their own review'
);

SELECT test_ok(
  (SELECT owner_reply = 'Sorry to hear that, please come back.' FROM public.reviews
    WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'author cannot forge an owner reply'
);

-- =====================================================================
-- 6. An unrelated user cannot touch the review at all.
-- =====================================================================
SELECT test_login('33333333-3333-3333-3333-333333333333');

DO $$
DECLARE
  affected INTEGER;
BEGIN
  UPDATE public.reviews SET comment = 'hijacked'
   WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  GET DIAGNOSTICS affected = ROW_COUNT;
  -- RLS filters the row out entirely, so this is 0 rather than an error.
  PERFORM test_ok(affected = 0, 'stranger cannot update someone else''s review');
END;
$$;

-- =====================================================================
-- 7. Constraints reject impossible data.
-- =====================================================================
SELECT test_login('22222222-2222-2222-2222-222222222222');

DO $$
BEGIN
  BEGIN
    INSERT INTO public.reviews (business_id, user_id, rating)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '22222222-2222-2222-2222-222222222222', 9);
    PERFORM test_ok(false, 'rating above 5 is rejected');
  EXCEPTION WHEN check_violation THEN
    PERFORM test_ok(true, 'rating above 5 is rejected');
  END;
END;
$$;

DO $$
BEGIN
  BEGIN
    -- Second review on the same business by the same user.
    INSERT INTO public.reviews (business_id, user_id, rating, comment)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '22222222-2222-2222-2222-222222222222', 4, 'spam');
    PERFORM test_ok(false, 'one review per user per business');
  EXCEPTION WHEN unique_violation THEN
    PERFORM test_ok(true, 'one review per user per business');
  END;
END;
$$;

-- =====================================================================
-- 8. A user cannot rewrite their own primary key or invent a role.
-- =====================================================================
UPDATE public.profiles
   SET id = '33333333-3333-3333-3333-333333333333', role = 'admin'
 WHERE id = '22222222-2222-2222-2222-222222222222';

SELECT test_ok(
  (SELECT role = 'client' FROM public.profiles
    WHERE id = '22222222-2222-2222-2222-222222222222'),
  'profile id and role cannot be escalated'
);

-- =====================================================================
-- 9. Owner analytics: the favourites count is visible via the RPC even though
--    the favorites table itself is select-own.
--    Before: getFavoriteCount always returned 0.
-- =====================================================================
INSERT INTO public.favorites (user_id, business_id)
VALUES ('22222222-2222-2222-2222-222222222222',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
ON CONFLICT DO NOTHING;

SELECT test_login('11111111-1111-1111-1111-111111111111');

SELECT test_ok(
  (SELECT count(*) = 0 FROM public.favorites
    WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'owner still cannot read other people''s favourite rows'
);

SELECT test_ok(
  (SELECT favorite_count = 1 FROM public.business_stats(
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'owner can read the favourite COUNT via business_stats'
);

SELECT test_ok(
  (SELECT check_in_count = 1 AND review_count = 1
     FROM public.business_stats('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'business_stats reports check-ins and reviews'
);

-- A stranger cannot read another business's analytics.
SELECT test_login('33333333-3333-3333-3333-333333333333');
DO $$
BEGIN
  BEGIN
    PERFORM public.business_stats('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    PERFORM test_ok(false, 'business_stats refuses a non-owner');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM test_ok(true, 'business_stats refuses a non-owner');
  END;
END;
$$;

-- =====================================================================
-- 10. Soft delete hides the business from the directory.
-- =====================================================================
SELECT test_login('11111111-1111-1111-1111-111111111111');
SELECT public.soft_delete_business('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT test_ok(
  (SELECT deleted_at IS NOT NULL FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'soft_delete_business marks the row deleted'
);

SELECT test_login('33333333-3333-3333-3333-333333333333');
SELECT test_ok(
  (SELECT count(*) = 0 FROM public.businesses
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'a deleted business disappears from the public listing'
);

-- =====================================================================
-- 11. The push trigger actually dispatches once the vault secrets exist.
--     Before: it called extensions.http_post (nonexistent) behind a guard
--     that was never true, so no push ever fired.
-- =====================================================================
RESET ROLE;

INSERT INTO vault.decrypted_secrets (name, decrypted_secret) VALUES
  ('htbiz_supabase_url', 'https://example.supabase.co'),
  ('htbiz_push_secret', 'test-secret')
ON CONFLICT (name) DO UPDATE SET decrypted_secret = EXCLUDED.decrypted_secret;

INSERT INTO public.notifications (user_id, type, title, body, is_read)
VALUES ('11111111-1111-1111-1111-111111111111', 'test', 'Hello', 'World', false);

SELECT test_ok(
  (SELECT count(*) = 1 FROM net.sent_requests
    WHERE url = 'https://example.supabase.co/functions/v1/send-push-notification'),
  'notification insert dispatches a push'
);

SELECT test_ok(
  (SELECT headers ->> 'x-htbiz-push-secret' = 'test-secret'
     FROM net.sent_requests ORDER BY id DESC LIMIT 1),
  'push request carries the shared secret'
);

-- A missing secret must warn, not abort the notification (and therefore not
-- abort the review that produced it).
DELETE FROM vault.decrypted_secrets WHERE name = 'htbiz_push_secret';

INSERT INTO public.notifications (user_id, type, title, body, is_read)
VALUES ('11111111-1111-1111-1111-111111111111', 'test', 'Second', 'World', false);

SELECT test_ok(
  (SELECT count(*) = 2 FROM public.notifications WHERE type = 'test'),
  'a push failure does not roll back the notification'
);

-- =====================================================================
-- 12. Storage buckets are bounded.
-- =====================================================================
SELECT test_ok(
  (SELECT file_size_limit = 5242880
      AND 'image/jpeg' = ANY(allowed_mime_types)
      AND NOT ('application/x-msdownload' = ANY(allowed_mime_types))
     FROM storage.buckets WHERE id = 'htbiz_images'),
  'htbiz_images has a size limit and a MIME allow-list'
);

SELECT test_ok(
  (SELECT NOT public FROM storage.buckets WHERE id = 'htbiz_patents'),
  'htbiz_patents is private'
);

-- =====================================================================
-- 13. Every SECURITY DEFINER function pins its search_path.
-- =====================================================================
SELECT test_ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND (p.proconfig IS NULL
           OR NOT EXISTS (
             SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search\_path=%'
           ))
  ),
  'no SECURITY DEFINER function has a mutable search_path'
);

-- =====================================================================
-- 14. Foreign keys the app filters on are indexed.
-- =====================================================================
SELECT test_ok(
  (SELECT count(*) = 4 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN ('idx_reviews_business_id', 'idx_favorites_business_id',
                        'idx_businesses_owner_id', 'idx_notifications_unread')),
  'hot-path indexes exist'
);

RESET ROLE;

SELECT 'ALL SECURITY ASSERTIONS PASSED' AS result;
