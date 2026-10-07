BEGIN;
CREATE TABLE IF NOT EXISTS public.usage_consent (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT false
);
ALTER TABLE public.usage_consent ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.usage_consent FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_usage_consent(p_enabled BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_catalog AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('usage:' || auth.uid()::text, 0));
  INSERT INTO public.usage_consent(user_id, enabled) VALUES (auth.uid(), coalesce(p_enabled, false))
    ON CONFLICT (user_id) DO UPDATE SET enabled = excluded.enabled;
END;
$$;
REVOKE ALL ON FUNCTION public.set_usage_consent(BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_usage_consent(BOOLEAN) TO authenticated;
CREATE TABLE IF NOT EXISTS public.usage_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_name TEXT NOT NULL CHECK (event_name IN ('screen_view', 'screen_time', 'media_selected', 'location_shared')),
  screen TEXT NOT NULL CHECK (length(screen) BETWEEN 1 AND 80),
  os TEXT NOT NULL CHECK (length(os) BETWEEN 1 AND 160),
  screen_width INTEGER NOT NULL CHECK (screen_width BETWEEN 1 AND 20000),
  screen_height INTEGER NOT NULL CHECK (screen_height BETWEEN 1 AND 20000),
  duration_seconds INTEGER NOT NULL DEFAULT 0 CHECK (duration_seconds BETWEEN 0 AND 3600),
  media_source TEXT CHECK (media_source IN ('camera', 'gallery')),
  latitude NUMERIC CHECK (latitude BETWEEN -90 AND 90),
  longitude NUMERIC CHECK (longitude BETWEEN -180 AND 180),
  request_ip INET,
  ip_source TEXT
);
CREATE INDEX IF NOT EXISTS usage_events_time ON public.usage_events(occurred_at DESC);
CREATE INDEX IF NOT EXISTS usage_events_cursor ON public.usage_events(occurred_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS usage_events_user_time ON public.usage_events(user_id, occurred_at DESC);
ALTER TABLE public.usage_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.usage_events FROM anon, authenticated;
GRANT SELECT ON public.usage_events TO authenticated;
DROP POLICY IF EXISTS usage_events_admin_read ON public.usage_events;
CREATE POLICY usage_events_admin_read ON public.usage_events FOR SELECT TO authenticated
  USING (public.htbiz_is_admin() AND occurred_at >= now() - interval '30 days');

CREATE OR REPLACE FUNCTION public.record_usage(
  p_event TEXT, p_screen TEXT, p_os TEXT, p_width INTEGER, p_height INTEGER,
  p_seconds INTEGER DEFAULT 0, p_media TEXT DEFAULT NULL,
  p_latitude NUMERIC DEFAULT NULL, p_longitude NUMERIC DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
DECLARE headers JSONB; remote_ip INET;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('usage:' || auth.uid()::text, 0));
  IF NOT EXISTS (SELECT 1 FROM public.usage_consent WHERE user_id = auth.uid() AND enabled) THEN RETURN; END IF;
  IF (SELECT count(*) FROM public.usage_events WHERE user_id = auth.uid()
      AND occurred_at > now() - interval '1 minute') >= 60 THEN RETURN; END IF;
  -- Proxy headers are informational, never identity or authorization signals.
  -- The deployment must verify its proxy overwrites these before treating them
  -- as authoritative. Do not accept an IP supplied in the event payload.
  BEGIN
    headers := nullif(current_setting('request.headers', true), '')::jsonb;
    remote_ip := nullif(btrim(split_part(headers->>'x-forwarded-for', ',', 1)), '')::inet;
  EXCEPTION WHEN OTHERS THEN remote_ip := NULL;
  END;
  INSERT INTO public.usage_events
    (user_id, event_name, screen, os, screen_width, screen_height,
     duration_seconds, media_source, latitude, longitude, request_ip, ip_source)
  VALUES (auth.uid(), p_event, p_screen, p_os, p_width, p_height,
    p_seconds, p_media, round(p_latitude, 2), round(p_longitude, 2), remote_ip,
    CASE WHEN remote_ip IS NOT NULL THEN 'proxy header (unverified)' END);
END;
$$;
REVOKE ALL ON FUNCTION public.record_usage(TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,TEXT,NUMERIC,NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_usage(TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,TEXT,NUMERIC,NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_usage()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_catalog AS $$
BEGIN
  PERFORM public.set_usage_consent(false);
  DELETE FROM public.usage_events WHERE user_id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.delete_my_usage() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_usage() TO authenticated;

CREATE OR REPLACE FUNCTION public.usage_summary()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
DECLARE result JSONB;
BEGIN
  IF NOT public.htbiz_is_admin() THEN
    RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object('events', count(*), 'users', count(DISTINCT user_id),
    'screen_views', count(*) FILTER (WHERE event_name = 'screen_view'),
    'active_seconds', coalesce(sum(duration_seconds) FILTER (WHERE event_name = 'screen_time'), 0))
    INTO result FROM public.usage_events WHERE occurred_at >= now() - interval '30 days';
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.usage_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.usage_summary() TO authenticated;

-- Physical retention: invoke daily from the deployment scheduler.
CREATE OR REPLACE FUNCTION public.purge_expired_usage()
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_catalog AS $$
  DELETE FROM public.usage_events WHERE occurred_at < now() - interval '30 days';
$$;
REVOKE ALL ON FUNCTION public.purge_expired_usage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_usage() TO service_role;
COMMIT;
