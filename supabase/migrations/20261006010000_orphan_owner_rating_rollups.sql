-- Older imports can contain businesses whose owner account was not restored.
-- A foreign key on owner_id makes *every* update of those rows fail, including
-- the review aggregate update. Keep validating new ownership writes in a
-- trigger while allowing existing orphaned rows to receive rating updates.
ALTER TABLE public.businesses
  DROP CONSTRAINT IF EXISTS businesses_owner_id_fkey;

CREATE OR REPLACE FUNCTION public.validate_business_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_catalog
AS $fn$
BEGIN
  IF (TG_OP = 'INSERT' OR NEW.owner_id IS DISTINCT FROM OLD.owner_id)
     AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.owner_id) THEN
    RAISE EXCEPTION 'Business owner account does not exist'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS businesses_validate_owner ON public.businesses;
CREATE TRIGGER businesses_validate_owner
  BEFORE INSERT OR UPDATE ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION public.validate_business_owner();

-- Preserve the old ON DELETE CASCADE behavior for owner account deletion.
CREATE OR REPLACE FUNCTION public.delete_owned_businesses_before_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
BEGIN
  DELETE FROM public.businesses WHERE owner_id = OLD.id;
  RETURN OLD;
END;
$fn$;

DROP TRIGGER IF EXISTS auth_user_delete_owned_businesses ON auth.users;
CREATE TRIGGER auth_user_delete_owned_businesses
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.delete_owned_businesses_before_user();
