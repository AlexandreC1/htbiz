-- A stale business owner ID must not block customers from leaving reviews.
-- The notification is secondary; skip it if its recipient has no live account.
CREATE OR REPLACE FUNCTION public.notify_on_new_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  biz_owner_id UUID;
  biz_name     TEXT;
BEGIN
  SELECT owner_id, name INTO biz_owner_id, biz_name
  FROM public.businesses WHERE id = NEW.business_id;

  IF biz_owner_id IS NOT NULL
     AND biz_owner_id <> NEW.user_id
     AND EXISTS (SELECT 1 FROM auth.users WHERE id = biz_owner_id) THEN
    BEGIN
      INSERT INTO public.notifications (user_id, type, title, body, business_id, review_id, is_read)
      VALUES (
        biz_owner_id,
        'new_review',
        'New review on ' || coalesce(biz_name, 'your business'),
        coalesce(nullif(NEW.comment, ''), repeat('*', greatest(least(NEW.rating, 5), 1))),
        NEW.business_id,
        NEW.id,
        false
      );
    EXCEPTION WHEN foreign_key_violation THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$fn$;
