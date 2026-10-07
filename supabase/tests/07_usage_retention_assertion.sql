SET ROLE authenticated;
SELECT test_login('22222222-2222-2222-2222-222222222222');
SELECT test_ok(public.get_usage_retention_days() = 30,
  'retention defaults to 30 days');
SELECT public.set_usage_retention_days(7::smallint);
SELECT test_ok(public.get_usage_retention_days() = 7,
  'users can select and read their retention');
SELECT public.set_usage_retention_days(90::smallint);
RESET ROLE;
SELECT test_ok((SELECT enabled FROM public.usage_consent
  WHERE user_id = '22222222-2222-2222-2222-222222222222') = false,
  'setting retention does not silently enable analytics');
SET ROLE authenticated;
SELECT test_login('22222222-2222-2222-2222-222222222222');
SELECT public.set_usage_retention_days(7::smallint);
DO $$ BEGIN
  PERFORM public.set_usage_retention_days(8::smallint);
  RAISE EXCEPTION 'FAIL unsupported retention period accepted';
EXCEPTION WHEN invalid_parameter_value THEN NULL;
END $$;
SELECT public.set_usage_consent(true);
SELECT public.record_usage('screen_view', 'home', 'android', 390, 844);
RESET ROLE;
UPDATE public.usage_events SET occurred_at = now() - interval '31 days'
  WHERE user_id = '22222222-2222-2222-2222-222222222222';
SELECT public.purge_expired_usage();
SELECT test_ok((SELECT count(*) = 0 FROM public.usage_events
  WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  'purge follows the selected retention period');
