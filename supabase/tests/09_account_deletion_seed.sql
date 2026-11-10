-- Puts the user-owned tables into the shapes a dashboard-created project can
-- be in before 20261111000000_account_deletion.sql: profiles without a
-- foreign key (and an orphaned profile that state allowed), favorites
-- without one (and an orphaned favorite), check_ins with a key that does
-- not cascade.
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;
ALTER TABLE public.favorites DROP CONSTRAINT IF EXISTS favorites_user_id_fkey;
ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS check_ins_user_id_fkey;
ALTER TABLE public.check_ins
  ADD CONSTRAINT check_ins_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users (id);

RESET ROLE;
SELECT set_config('request.jwt.claims', '', false);

INSERT INTO auth.users (id, email) VALUES
  ('99999999-9999-9999-9999-999999999999', 'deleting@htbiz.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role) VALUES
  ('99999999-9999-9999-9999-999999999999', 'deleting@htbiz.test',
   'Dina Deleting', 'business_owner'),
  -- No such account: must be removed before the foreign key can exist.
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'ghost@htbiz.test',
   'Ghost Profile', 'client')
ON CONFLICT DO NOTHING;

INSERT INTO public.businesses (id, name, category, address, owner_id) VALUES
  -- Owned by the account that will be deleted.
  ('d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0', 'Boutik Dina', 'Shop',
   'Petion-Ville', '99999999-9999-9999-9999-999999999999'),
  -- Owned by somebody else, reviewed by the account that will be deleted.
  ('e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0', 'Resto Rete', 'Restaurant',
   'Delmas 60', '11111111-1111-1111-1111-111111111111')
ON CONFLICT DO NOTHING;

INSERT INTO public.business_images (business_id, image_url)
VALUES ('d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0', 'https://example.test/d.jpg');

INSERT INTO public.reviews (id, business_id, user_id, rating, comment) VALUES
  -- Somebody else's review of the deleted user's business.
  ('d0000000-0000-0000-0000-000000000001', 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0',
   '22222222-2222-2222-2222-222222222222', 4, 'goes with the business'),
  -- The deleted user's review of another business (1 star) next to one
  -- that stays (5 stars): the rollup must go from 3.0 / 2 to 5.0 / 1.
  ('d0000000-0000-0000-0000-000000000002', 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0',
   '99999999-9999-9999-9999-999999999999', 1, 'goes with the author'),
  ('d0000000-0000-0000-0000-000000000003', 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0',
   '22222222-2222-2222-2222-222222222222', 5, 'stays');

INSERT INTO public.review_likes (review_id, user_id) VALUES
  -- A like given by the deleted user, and a like on the deleted user's review.
  ('d0000000-0000-0000-0000-000000000003', '99999999-9999-9999-9999-999999999999'),
  ('d0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333'),
  -- Unrelated: must survive.
  ('d0000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333');

INSERT INTO public.favorites (user_id, business_id) VALUES
  ('99999999-9999-9999-9999-999999999999', 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0'),
  -- Somebody else's favorite of the deleted user's business.
  ('33333333-3333-3333-3333-333333333333', 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0'),
  -- Unrelated: must survive.
  ('33333333-3333-3333-3333-333333333333', 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0'),
  -- No such account.
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0');

INSERT INTO public.check_ins (user_id, business_id) VALUES
  ('99999999-9999-9999-9999-999999999999', 'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0'),
  ('33333333-3333-3333-3333-333333333333', 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0');

INSERT INTO public.notifications (user_id, type, title, body, business_id, review_id) VALUES
  ('99999999-9999-9999-9999-999999999999', 'new_review', 'For Dina', 'x',
   'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0', 'd0000000-0000-0000-0000-000000000001'),
  -- Sent to somebody else about the deleted user's review.
  ('11111111-1111-1111-1111-111111111111', 'new_review', 'About Dina', 'x',
   'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0', 'd0000000-0000-0000-0000-000000000002'),
  -- Unrelated: must survive.
  ('11111111-1111-1111-1111-111111111111', 'new_review', 'Unrelated', 'x',
   'e0e0e0e0-e0e0-e0e0-e0e0-e0e0e0e0e0e0', 'd0000000-0000-0000-0000-000000000003');

INSERT INTO public.fcm_tokens (user_id, token)
VALUES ('99999999-9999-9999-9999-999999999999', 'token-of-dina');

INSERT INTO public.usage_consent (user_id, enabled)
VALUES ('99999999-9999-9999-9999-999999999999', true);

INSERT INTO public.usage_events
  (user_id, event_name, screen, os, screen_width, screen_height)
VALUES ('99999999-9999-9999-9999-999999999999', 'screen_view', 'home',
        'android', 400, 800);

INSERT INTO public.admins (user_id, note)
VALUES ('99999999-9999-9999-9999-999999999999', 'deletion test');

INSERT INTO public.rate_limit_events (user_id, action)
VALUES ('99999999-9999-9999-9999-999999999999', 'review');
