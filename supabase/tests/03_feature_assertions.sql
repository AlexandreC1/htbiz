-- The prior security suite deliberately soft-deletes this fixture.
UPDATE public.businesses SET deleted_at = NULL
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET ROLE authenticated;
SELECT test_login('22222222-2222-2222-2222-222222222222');
SELECT * FROM public.save_review('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 4, 'Updated review');
SELECT * FROM public.save_review('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 4, 'Updated review');
SELECT test_ok((SELECT count(*) = 1 FROM public.reviews
  WHERE user_id = auth.uid() AND business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'repeated saves do not duplicate a review');
SELECT test_ok((SELECT rating = 4 FROM public.reviews
  WHERE user_id = auth.uid() AND business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'rating edits persist');
SELECT test_ok((SELECT rating = 4 AND total_reviews = 1 FROM public.businesses
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'saved rating updates business stats');
SELECT * FROM public.save_review('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 4, 'Updated review', '{}', true);
SELECT test_ok((SELECT is_anonymous AND user_name = 'Anonymous' AND user_email IS NULL
  FROM public.reviews WHERE user_id = auth.uid() AND business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'anonymous display preference persists and email is not public');
DO $$ BEGIN
  PERFORM public.usage_summary();
  RAISE EXCEPTION 'FAIL non-admin could read aggregate usage';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;

SELECT public.record_usage('screen_view', 'home', 'android', 390, 844);
RESET ROLE;
SELECT test_ok((SELECT count(*) = 0 FROM public.usage_events), 'no telemetry without consent');
SET ROLE authenticated;
SELECT test_login('22222222-2222-2222-2222-222222222222');
SELECT public.set_usage_consent(true);
DO $$ BEGIN
  FOR i IN 1..65 LOOP
    PERFORM public.record_usage('screen_view', 'home', 'android', 390, 844);
  END LOOP;
END $$;
RESET ROLE;
SELECT test_ok((SELECT count(*) = 60 FROM public.usage_events), 'ingest is rate limited per user');
UPDATE public.usage_events SET occurred_at = now() - interval '31 days';
SELECT public.purge_expired_usage();
SELECT test_ok((SELECT count(*) = 0 FROM public.usage_events), 'expired usage is physically deleted');
SET ROLE authenticated;
SELECT public.set_usage_consent(true);
SELECT public.record_usage('screen_view', 'home', 'android', 390, 844);
SELECT test_ok((SELECT count(*) = 0 FROM public.usage_events), 'users cannot read usage events');
SELECT test_login('11111111-1111-1111-1111-111111111111');
SELECT test_ok((SELECT count(*) = 0 FROM public.usage_events), 'business owners cannot read usage events');
RESET ROLE;
INSERT INTO public.admins(user_id) VALUES ('33333333-3333-3333-3333-333333333333') ON CONFLICT DO NOTHING;
SET ROLE authenticated;
SELECT test_login('33333333-3333-3333-3333-333333333333');
SELECT test_ok((SELECT count(*) = 1 FROM public.usage_events), 'allowlisted administrators can read usage');
SELECT test_ok((public.usage_summary()->>'users')::int = 1, 'admin summaries count users');
SELECT test_login('22222222-2222-2222-2222-222222222222');
DO $$ BEGIN
  PERFORM public.record_usage('screen_view', 'home', 'android', -1, 844);
  RAISE EXCEPTION 'FAIL invalid screen size accepted';
EXCEPTION WHEN check_violation THEN NULL;
END $$;
SELECT public.delete_my_usage();
SELECT public.record_usage('screen_view', 'home', 'android', 390, 844);
SELECT test_login('33333333-3333-3333-3333-333333333333');
SELECT test_ok((SELECT count(*) = 0 FROM public.usage_events), 'users can delete their own telemetry');
SELECT test_ok(EXISTS(SELECT 1 FROM pg_indexes WHERE indexname = 'businesses_active_name_trgm'),
  'substring search is indexed');
RESET ROLE;
