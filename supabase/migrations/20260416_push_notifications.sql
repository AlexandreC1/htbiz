-- FCM tokens table to store device push tokens
CREATE TABLE IF NOT EXISTS fcm_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, token)
);

-- Index for fast lookups by user
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id ON fcm_tokens(user_id);

-- RLS policies
ALTER TABLE fcm_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own tokens"
  ON fcm_tokens FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Allow service role full access (for edge function cleanup)
CREATE POLICY "Service role full access on fcm_tokens"
  ON fcm_tokens FOR ALL
  USING (auth.role() = 'service_role');

-- Enable pg_net for HTTP calls from triggers.
-- pg_net is not relocatable (it always installs into the `net` schema), so the
-- original `WITH SCHEMA extensions` was rejected, and the extension is not
-- available at all on a plain Postgres. Either way a hard failure here aborts
-- the whole migration, so it degrades to a notice.
-- Superseded by 20260902000000_production_hardening.sql, which replaces the
-- trigger function below with one that calls net.http_post correctly.
DO $blk$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_net;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_net unavailable (%)', SQLERRM;
END $blk$;

-- Function to call the send-push-notification edge function
CREATE OR REPLACE FUNCTION trigger_send_push_notification()
RETURNS TRIGGER AS $$
DECLARE
  supabase_url TEXT;
  service_role_key TEXT;
BEGIN
  -- Get the Supabase URL and service role key from vault or config
  supabase_url := current_setting('app.settings.supabase_url', true);
  service_role_key := current_setting('app.settings.service_role_key', true);

  -- If settings are not available, try environment-based URL
  IF supabase_url IS NULL THEN
    supabase_url := 'https://mgamhhssdmeripqdkogs.supabase.co';
  END IF;

  IF service_role_key IS NOT NULL THEN
    PERFORM extensions.http_post(
      url := supabase_url || '/functions/v1/send-push-notification',
      body := json_build_object('record', row_to_json(NEW))::text,
      headers := json_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      )::jsonb
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on notification insert
DROP TRIGGER IF EXISTS on_notification_send_push ON notifications;
CREATE TRIGGER on_notification_send_push
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION trigger_send_push_notification();
