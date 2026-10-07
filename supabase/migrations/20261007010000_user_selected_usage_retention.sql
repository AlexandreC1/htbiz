BEGIN;

ALTER TABLE public.usage_consent
  ADD COLUMN IF NOT EXISTS retention_days SMALLINT NOT NULL DEFAULT 30;
ALTER TABLE public.usage_consent
  DROP CONSTRAINT IF EXISTS usage_consent_retention_days_check;
ALTER TABLE public.usage_consent
  ADD CONSTRAINT usage_consent_retention_days_check
  CHECK (retention_days IN (7, 30, 90, 365));

CREATE OR REPLACE FUNCTION public.get_usage_retention_days()
RETURNS SMALLINT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
DECLARE days SMALLINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT retention_days INTO days FROM public.usage_consent WHERE user_id = auth.uid();
  RETURN coalesce(days, 30);
END;
$$;
REVOKE ALL ON FUNCTION public.get_usage_retention_days() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_usage_retention_days() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_usage_retention_days(p_days SMALLINT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_days IS NULL OR p_days NOT IN (7, 30, 90, 365) THEN
    RAISE EXCEPTION 'Unsupported retention period' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('usage:' || auth.uid()::text, 0));
  INSERT INTO public.usage_consent(user_id, enabled, retention_days)
  VALUES (auth.uid(), false, p_days)
  ON CONFLICT (user_id) DO UPDATE SET retention_days = excluded.retention_days;
END;
$$;
REVOKE ALL ON FUNCTION public.set_usage_retention_days(SMALLINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_usage_retention_days(SMALLINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.usage_retention_days_for_admin(p_user_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
DECLARE days SMALLINT;
BEGIN
  IF NOT public.htbiz_is_admin() THEN
    RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501';
  END IF;
  SELECT retention_days INTO days FROM public.usage_consent WHERE user_id = p_user_id;
  RETURN coalesce(days, 30);
END;
$$;
REVOKE ALL ON FUNCTION public.usage_retention_days_for_admin(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.usage_retention_days_for_admin(UUID) TO authenticated;

DROP POLICY IF EXISTS usage_events_admin_read ON public.usage_events;
CREATE POLICY usage_events_admin_read ON public.usage_events FOR SELECT TO authenticated
  USING (
    public.htbiz_is_admin()
    AND occurred_at >= now() - make_interval(days =>
      public.usage_retention_days_for_admin(usage_events.user_id)::int)
  );

CREATE OR REPLACE FUNCTION public.usage_summary()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
DECLARE result JSONB;
BEGIN
  IF NOT public.htbiz_is_admin() THEN
    RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object('events', count(*), 'users', count(DISTINCT e.user_id),
    'screen_views', count(*) FILTER (WHERE e.event_name = 'screen_view'),
    'active_seconds', coalesce(sum(e.duration_seconds) FILTER (WHERE e.event_name = 'screen_time'), 0))
    INTO result
    FROM public.usage_events e
    LEFT JOIN public.usage_consent c ON c.user_id = e.user_id
    WHERE e.occurred_at >= now() - make_interval(days => coalesce(c.retention_days::int, 30));
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.usage_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.usage_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.purge_expired_usage()
RETURNS VOID LANGUAGE sql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
  DELETE FROM public.usage_events e
  WHERE e.occurred_at < now() - make_interval(days => coalesce(
    (SELECT c.retention_days::int FROM public.usage_consent c
     WHERE c.user_id = e.user_id), 30));
$$;
REVOKE ALL ON FUNCTION public.purge_expired_usage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_usage() TO service_role;

-- Supabase includes pg_cron, but local/test Postgres images may not. Enable and
-- schedule the purge where the extension is available; replace the named job
-- on migration replay so this migration remains idempotent.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron';
    IF to_regclass('cron.job') IS NOT NULL THEN
      EXECUTE 'SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = ''htbiz-purge-expired-usage''';
      EXECUTE 'SELECT cron.schedule(''htbiz-purge-expired-usage'', ''17 3 * * *'', ''SELECT public.purge_expired_usage()'')';
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron is unavailable; expired usage must be purged by an external scheduler';
  END IF;
END;
$$;

COMMIT;
