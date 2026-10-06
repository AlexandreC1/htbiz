-- Recreates the dashboard-era policies exactly as they exist on the live
-- project, so the cleanup migration is tested against the real shape.
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-images', 'business-images', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Authenticated users can create businesses" ON public.businesses;
CREATE POLICY "Authenticated users can create businesses" ON public.businesses
  FOR INSERT TO authenticated WITH CHECK (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Businesses are viewable by everyone" ON public.businesses;
CREATE POLICY "Businesses are viewable by everyone" ON public.businesses
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Users can update own businesses" ON public.businesses;
CREATE POLICY "Users can update own businesses" ON public.businesses
  FOR UPDATE TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "Users can delete own businesses" ON public.businesses;
CREATE POLICY "Users can delete own businesses" ON public.businesses
  FOR DELETE USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "Authenticated users can create reviews" ON public.reviews;
CREATE POLICY "Authenticated users can create reviews" ON public.reviews
  FOR INSERT TO authenticated WITH CHECK (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Reviews are viewable by everyone" ON public.reviews;
CREATE POLICY "Reviews are viewable by everyone" ON public.reviews
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Delete reviews when business is deleted" ON public.reviews;
CREATE POLICY "Delete reviews when business is deleted" ON public.reviews
  FOR DELETE USING (auth.uid() IN (
    SELECT owner_id FROM public.businesses WHERE id = reviews.business_id));

DROP POLICY IF EXISTS "Allow authenticated users to upload images 1jik568_0" ON storage.objects;
CREATE POLICY "Allow authenticated users to upload images 1jik568_0" ON storage.objects
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Allow public read access to images 1jik568_0" ON storage.objects;
CREATE POLICY "Allow public read access to images 1jik568_0" ON storage.objects
  FOR SELECT USING (bucket_id = 'htbiz_images');
DROP POLICY IF EXISTS "Authenticated users can upload 14srpd1_0" ON storage.objects;
CREATE POLICY "Authenticated users can upload 14srpd1_0" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'business-images' AND auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Public Access 14srpd1_0" ON storage.objects;
CREATE POLICY "Public Access 14srpd1_0" ON storage.objects
  FOR SELECT USING (bucket_id = 'business-images');
