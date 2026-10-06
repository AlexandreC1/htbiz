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

DROP POLICY IF EXISTS "Users can manage their own tokens" ON fcm_tokens;
CREATE POLICY "Users can manage their own tokens"
  ON fcm_tokens FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Allow service role full access (for edge function cleanup)
DROP POLICY IF EXISTS "Service role full access on fcm_tokens" ON fcm_tokens;
CREATE POLICY "Service role full access on fcm_tokens"
  ON fcm_tokens FOR ALL
  USING (auth.role() = 'service_role');

-- This migration only provisions token storage. The outbound push trigger is
-- defined later by production_hardening, where its endpoint and shared secret
-- come from Vault instead of a stale project URL and session settings.
DROP TRIGGER IF EXISTS on_notification_send_push ON notifications;
DROP FUNCTION IF EXISTS public.trigger_send_push_notification();
