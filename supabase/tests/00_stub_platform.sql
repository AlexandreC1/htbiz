-- =====================================================================
-- Test harness: the parts of a hosted Supabase project that a bare Postgres
-- container does not have.
--
-- This is ONLY loaded by supabase/tests/run.sh. It is never applied to a real
-- project, where GoTrue, Storage and pg_net provide the real versions.
-- =====================================================================

-- ---- Roles PostgREST switches into ----------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- A hosted Supabase project ships default privileges so that any table created
-- later in `public` is automatically reachable by the API roles, with RLS doing
-- the actual restricting. Without this, tables added by a later migration
-- (check_ins, review_likes, notifications) are invisible to `authenticated`.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- ---- auth schema ----------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email      TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- GoTrue's auth.uid() / auth.role() read the JWT claims that PostgREST puts
-- into the `request.jwt.claims` GUC. Same contract here, so tests can "log in"
-- with set_config('request.jwt.claims', ...).
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(
    coalesce(
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
      ''
    ),
    ''
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user::text
  );
$$;

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated, service_role;

-- ---- storage schema -------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id                 TEXT PRIMARY KEY,
  name               TEXT NOT NULL,
  public             BOOLEAN NOT NULL DEFAULT false,
  file_size_limit    BIGINT,
  allowed_mime_types TEXT[],
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id  TEXT REFERENCES storage.buckets(id),
  name       TEXT NOT NULL,
  owner      UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Real signature: returns the path segments excluding the file name.
CREATE OR REPLACE FUNCTION storage.foldername(name TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  parts TEXT[];
BEGIN
  parts := string_to_array(name, '/');
  RETURN parts[1 : array_length(parts, 1) - 1];
END;
$$;

GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

-- ---- vault ----------------------------------------------------------------
-- The real supabase_vault extension exposes vault.decrypted_secrets.
CREATE SCHEMA IF NOT EXISTS vault;

CREATE TABLE IF NOT EXISTS vault.decrypted_secrets (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name             TEXT UNIQUE,
  decrypted_secret TEXT
);

-- ---- pg_net ---------------------------------------------------------------
-- Records calls instead of making them, so tests can assert a push was
-- dispatched without any network access.
CREATE SCHEMA IF NOT EXISTS net;

CREATE TABLE IF NOT EXISTS net.sent_requests (
  id      BIGSERIAL PRIMARY KEY,
  url     TEXT,
  body    JSONB,
  headers JSONB,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION net.http_post(
  url TEXT,
  body JSONB DEFAULT '{}'::jsonb,
  params JSONB DEFAULT '{}'::jsonb,
  headers JSONB DEFAULT '{}'::jsonb,
  timeout_milliseconds INT DEFAULT 5000
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  new_id BIGINT;
BEGIN
  INSERT INTO net.sent_requests (url, body, headers)
  VALUES (url, body, headers)
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$$;
