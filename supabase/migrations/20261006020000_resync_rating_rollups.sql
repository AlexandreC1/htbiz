-- The review trigger only recalculates a business when one of its reviews
-- changes. Rows seeded or imported with a rating/total_reviews and no matching
-- reviews kept those numbers forever (e.g. 4.5 stars from "12 reviews" that
-- do not exist). Recompute every aggregate from the reviews table once.
-- Only mismatched rows are touched so updated_at stays meaningful elsewhere.
BEGIN;

-- businesses_guard_columns reinstates rating/total_reviews unless privileged.
SELECT set_config('htbiz.privileged', 'on', true);

WITH actual AS (
  SELECT b.id,
         coalesce(avg(r.rating), 0)::DOUBLE PRECISION AS avg_rating,
         count(r.id)::INTEGER                         AS review_count
    FROM public.businesses b
    LEFT JOIN public.reviews r ON r.business_id = b.id
   GROUP BY b.id
)
UPDATE public.businesses b
   SET rating = a.avg_rating, total_reviews = a.review_count
  FROM actual a
 WHERE a.id = b.id
   AND (b.total_reviews IS DISTINCT FROM a.review_count
        OR abs(coalesce(b.rating, 0) - a.avg_rating) > 0.0001);

SELECT set_config('htbiz.privileged', 'off', true);

COMMIT;
