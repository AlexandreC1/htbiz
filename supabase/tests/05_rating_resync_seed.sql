-- A business imported with an aggregate but no reviews behind it, the shape
-- the review trigger alone can never correct.
INSERT INTO public.businesses (id, owner_id, name, category, address, rating, total_reviews)
VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '11111111-1111-1111-1111-111111111111',
        'Stale seed', 'Restaurant', 'Rue Pavée, PAP', 4.5, 12)
ON CONFLICT (id) DO UPDATE SET rating = 4.5, total_reviews = 12;
