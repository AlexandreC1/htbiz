-- =====================================================================
-- Baseline schema: production as it stood BEFORE supabase_full_migration.sql.
--
-- The core tables were created by hand in the Supabase dashboard, so the repo
-- has never had a schema of record. This file reconstructs that starting point
-- from the Dart models and from the ALTER TABLE statements in
-- supabase_full_migration.sql, so the migrations can be replayed from zero.
--
-- Keep it in sync if you ever change a base column: it is what the test run
-- migrates forward from.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT NOT NULL,
  full_name  TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.businesses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  description   TEXT DEFAULT '',
  category      TEXT NOT NULL,
  address       TEXT NOT NULL,
  phone         TEXT,
  image_url     TEXT,
  rating        DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_reviews INTEGER NOT NULL DEFAULT 0,
  owner_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.reviews (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating         INTEGER NOT NULL,
  comment        TEXT,
  image_url      TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The public images bucket, created from the dashboard in production.
INSERT INTO storage.buckets (id, name, public)
VALUES ('htbiz_images', 'htbiz_images', true)
ON CONFLICT (id) DO NOTHING;

-- PostgREST grants: every table is reachable by the API roles, and RLS is what
-- actually restricts access.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
  TO authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
  TO authenticated, service_role;
