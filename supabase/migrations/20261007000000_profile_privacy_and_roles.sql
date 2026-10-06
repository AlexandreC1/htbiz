-- Profiles contain account email addresses; only the matching user should be
-- able to read them. Remove dashboard-era policies too, regardless of name,
-- because permissive PostgreSQL policies are combined with OR.
DO $policies$
DECLARE existing_policy RECORD;
BEGIN
  FOR existing_policy IN
    SELECT policyname
      FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'profiles'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.profiles', existing_policy.policyname);
  END LOOP;
END
$policies$;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- The app supports exactly these roles. Normalize nulls before enforcing the
-- invariant so older dashboard-created schemas also get a safe default.
UPDATE public.profiles
   SET role = 'client'
 WHERE role IS NULL;

ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'client',
  ALTER COLUMN role SET NOT NULL;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND conname = 'profiles_role_valid'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_role_valid
      CHECK (role IN ('client', 'business_owner'));
  END IF;
END
$migration$;

-- Enforce role choice on profile creation as well as later updates.
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = id
    AND role IN ('client', 'business_owner')
  );

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role IN ('client', 'business_owner')
  );
