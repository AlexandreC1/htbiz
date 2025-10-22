import '../models/business_model.dart';
import '../models/review_model.dart';
import '../main.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class BusinessService {
  // Get all businesses
  Future<List<Business>> getAllBusinesses() async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .order('created_at', ascending: false);

      return (response as List).map((json) => Business.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load businesses: $e');
    }
  }

  // Get businesses by category
  Future<List<Business>> getBusinessesByCategory(String category) async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .eq('category', category)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Business.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load businesses: $e');
    }
  }

  // Search businesses by name
  Future<List<Business>> searchBusinesses(String query) async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .ilike('name', '%$query%')
          .order('created_at', ascending: false);

      return (response as List).map((json) => Business.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to search businesses: $e');
    }
  }

  // Get single business by ID
  Future<Business?> getBusinessById(String id) async {
    try {
      final response =
          await supabase.from('businesses').select().eq('id', id).single();

      return Business.fromJson(response);
    } catch (e) {
      throw Exception('Failed to load business: $e');
    }
  }

  // Create new business
  Future<Business> createBusiness(Business business) async {
    try {
      final response = await supabase
          .from('businesses')
          .insert(business.toJson())
          .select()
          .single();

      return Business.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create business: $e');
    }
  }

  // Update business
  Future<Business> updateBusiness(
      String id, Map<String, dynamic> updates) async {
    try {
      final response = await supabase
          .from('businesses')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return Business.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update business: $e');
    }
  }

  // Delete business
  Future<void> deleteBusiness(String id) async {
    try {
      await supabase.from('businesses').delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete business: $e');
    }
  }

  // Get reviews for a business
  Future<List<Review>> getBusinessReviews(String businessId) async {
    try {
      final response = await supabase
          .from('reviews')
          .select()
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Review.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load reviews: $e');
    }
  }

  // Add review
  Future<Review> addReview(Review review) async {
    try {
      final response = await supabase
          .from('reviews')
          .insert(review.toJson())
          .select()
          .single();

      return Review.fromJson(response);
    } catch (e) {
      throw Exception('Failed to add review: $e');
    }
  }

  // Upload business image to Supabase Storage
  Future<String> uploadBusinessImage(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final fileName = 'businesses/$userId/$timestamp$fileExtension';

      // Upload to Supabase Storage
      await supabase.storage.from('htbiz_images').upload(fileName, imageFile);

      // Get public URL
      final imageUrl =
          supabase.storage.from('htbiz_images').getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      throw Exception('Failed to upload business image: $e');
    }
  }

  // Upload review image to Supabase Storage
  Future<String> uploadReviewImage(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final fileName = 'reviews/$userId/$timestamp$fileExtension';

      // Upload to Supabase Storage - simplified without FileOptions
      await supabase.storage.from('htbiz_images').upload(
            fileName,
            imageFile,
          );

      // Get public URL
      final imageUrl =
          supabase.storage.from('htbiz_images').getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      throw Exception('Failed to upload review image: $e');
    }
  }
}
