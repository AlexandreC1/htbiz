-- The resync must clear aggregates with no reviews behind them and leave
-- every business matching its reviews table.
SELECT test_ok((SELECT rating = 0 AND total_reviews = 0 FROM public.businesses
  WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  'resync clears an aggregate with no reviews behind it');
SELECT test_ok(NOT EXISTS (
  SELECT 1
    FROM public.businesses b
    LEFT JOIN public.reviews r ON r.business_id = b.id
   GROUP BY b.id
  HAVING b.total_reviews <> count(r.id)
      OR abs(b.rating - coalesce(avg(r.rating), 0)) > 0.0001
), 'every business aggregate matches its reviews after resync');

DELETE FROM public.businesses WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
