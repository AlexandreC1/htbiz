-- Apply after production hardening. All review writes retain RLS enforcement.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS businesses_active_name_trgm
  ON public.businesses USING gin (name gin_trgm_ops)
  WHERE deleted_at IS NULL;

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.reviews_update_privacy()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
BEGIN
  IF auth.uid() IS DISTINCT FROM OLD.user_id THEN
    NEW.is_anonymous := OLD.is_anonymous;
  END IF;
  IF NEW.is_anonymous IS DISTINCT FROM OLD.is_anonymous THEN
    IF NEW.is_anonymous THEN
      NEW.user_name := 'Anonymous';
    ELSE
      SELECT coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Anonymous')
        INTO NEW.user_name FROM auth.users u
        LEFT JOIN public.profiles p ON p.id = u.id WHERE u.id = OLD.user_id;
    END IF;
  END IF;
  NEW.user_email := NULL;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS zz_reviews_privacy ON public.reviews;
CREATE TRIGGER zz_reviews_privacy BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.reviews_update_privacy();
UPDATE public.reviews SET user_email = NULL WHERE user_email IS NOT NULL;

CREATE OR REPLACE FUNCTION public.reviews_stamp_identity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog AS $$
BEGIN
  NEW.user_id := coalesce(auth.uid(), NEW.user_id);
  NEW.is_verified_visit := EXISTS (
    SELECT 1 FROM public.check_ins
    WHERE user_id = NEW.user_id AND business_id = NEW.business_id
  );
  SELECT coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Anonymous')
    INTO NEW.user_name
    FROM auth.users u LEFT JOIN public.profiles p ON p.id = u.id
    WHERE u.id = NEW.user_id;
  IF NEW.is_anonymous THEN NEW.user_name := 'Anonymous'; END IF;
  -- Reviews are public: email addresses do not belong in their payload.
  NEW.user_email := NULL;
  NEW.owner_reply := NULL;
  NEW.owner_reply_at := NULL;
  RETURN NEW;
END;
$$;

-- Repeating a save updates the author's rating rather than creating duplicate
-- reviews. Serializing the pair also covers legacy databases whose unique
-- index could not be created due to pre-existing duplicate reviews.
CREATE OR REPLACE FUNCTION public.save_review(
  p_business_id UUID, p_rating INTEGER, p_comment TEXT DEFAULT NULL,
  p_image_urls TEXT[] DEFAULT '{}', p_anonymous BOOLEAN DEFAULT false
) RETURNS SETOF public.reviews
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_catalog AS $$
DECLARE existing_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in to review' USING ERRCODE = '42501';
  END IF;
  IF p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.businesses
    WHERE id = p_business_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Business unavailable' USING ERRCODE = '23503';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_business_id::text, 0));
  SELECT id INTO existing_id FROM public.reviews
    WHERE business_id = p_business_id AND user_id = auth.uid()
    ORDER BY created_at, id LIMIT 1;
  IF existing_id IS NOT NULL THEN
    RETURN QUERY UPDATE public.reviews SET
      rating = p_rating, comment = nullif(btrim(p_comment), ''),
      is_anonymous = coalesce(p_anonymous, false),
      image_urls = coalesce(p_image_urls, '{}'), image_url = p_image_urls[1]
      WHERE id = existing_id RETURNING *;
  ELSE
    RETURN QUERY INSERT INTO public.reviews
      (business_id, user_id, rating, comment, image_urls, image_url, is_anonymous)
    VALUES (p_business_id, auth.uid(), p_rating, nullif(btrim(p_comment), ''),
      coalesce(p_image_urls, '{}'), p_image_urls[1], coalesce(p_anonymous, false))
    RETURNING *;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.save_review(UUID, INTEGER, TEXT, TEXT[], BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_review(UUID, INTEGER, TEXT, TEXT[], BOOLEAN) TO authenticated;
COMMIT;
