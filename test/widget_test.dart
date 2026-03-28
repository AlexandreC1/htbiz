import 'package:flutter_test/flutter_test.dart';
import 'package:htbiz/models/business_model.dart';
import 'package:htbiz/services/localization_service.dart';

void main() {
  group('Business model', () {
    test('fromJson parses all fields including verification', () {
      final json = {
        'id': '123',
        'name': 'Test Biz',
        'description': 'A test business',
        'category': 'restaurant',
        'address': '123 Main St',
        'image_url': 'https://example.com/img.png',
        'phone': '555-0100',
        'whatsapp': '555-0101',
        'website': 'https://example.com',
        'hours_text': '9-5',
        'latitude': 18.54,
        'longitude': -72.34,
        'rating': 4.5,
        'total_reviews': 10,
        'owner_id': 'owner-abc',
        'created_at': '2025-01-01T00:00:00Z',
        'verification_status': 'verified',
        'patent_doc_url': 'https://example.com/patent.jpg',
      };

      final biz = Business.fromJson(json);

      expect(biz.id, '123');
      expect(biz.name, 'Test Biz');
      expect(biz.category, 'restaurant');
      expect(biz.rating, 4.5);
      expect(biz.totalReviews, 10);
      expect(biz.verificationStatus, 'verified');
      expect(biz.patentDocUrl, 'https://example.com/patent.jpg');
      expect(biz.latitude, 18.54);
      expect(biz.longitude, -72.34);
    });

    test('fromJson defaults verification_status to none', () {
      final json = {
        'id': '456',
        'name': 'Minimal Biz',
        'description': 'Desc',
        'category': 'shop',
        'address': 'Addr',
        'image_url': '',
        'rating': 0.0,
        'total_reviews': 0,
        'owner_id': 'owner-xyz',
        'created_at': '2025-06-01T00:00:00Z',
      };

      final biz = Business.fromJson(json);

      expect(biz.verificationStatus, 'none');
      expect(biz.patentDocUrl, isNull);
      expect(biz.phone, isNull);
    });

    test('toJson includes verification fields', () {
      final biz = Business(
        id: '1',
        name: 'Biz',
        description: 'D',
        category: 'service',
        address: 'A',
        imageUrl: '',
        rating: 3.0,
        totalReviews: 1,
        ownerId: 'o',
        createdAt: DateTime(2025),
        verificationStatus: 'pending',
        patentDocUrl: 'https://example.com/doc.jpg',
      );

      final json = biz.toJson();

      expect(json['verification_status'], 'pending');
      expect(json['patent_doc_url'], 'https://example.com/doc.jpg');
    });

    test('copyWith updates verification fields', () {
      final biz = Business(
        id: '1',
        name: 'Biz',
        description: 'D',
        category: 'shop',
        address: 'A',
        imageUrl: '',
        rating: 0,
        totalReviews: 0,
        ownerId: 'o',
        createdAt: DateTime(2025),
      );

      final updated = biz.copyWith(verificationStatus: 'verified');

      expect(updated.verificationStatus, 'verified');
      expect(updated.name, 'Biz'); // unchanged
    });
  });

  group('LocalizationService', () {
    test('all three languages have the same keys', () {
      const translations = LocalizationService.translations;
      final enKeys = translations['en']!.keys.toSet();
      final frKeys = translations['fr']!.keys.toSet();
      final htKeys = translations['ht']!.keys.toSet();

      final missingInFr = enKeys.difference(frKeys);
      final missingInHt = enKeys.difference(htKeys);
      final extraInFr = frKeys.difference(enKeys);
      final extraInHt = htKeys.difference(enKeys);

      expect(missingInFr, isEmpty,
          reason: 'FR missing keys: $missingInFr');
      expect(missingInHt, isEmpty,
          reason: 'HT missing keys: $missingInHt');
      expect(extraInFr, isEmpty,
          reason: 'FR has extra keys: $extraInFr');
      expect(extraInHt, isEmpty,
          reason: 'HT has extra keys: $extraInHt');
    });

    test('verification keys exist in all languages', () {
      final verificationKeys = [
        'verified_business',
        'upload_patent',
        'upload_patent_description',
        'uploading_patent',
        'verification_submitted',
        'verification_pending',
        'verification_rejected',
        'not_verified_hint',
        'verify_now',
      ];

      for (final lang in ['en', 'fr', 'ht']) {
        for (final key in verificationKeys) {
          expect(
            LocalizationService.translations[lang]!.containsKey(key),
            isTrue,
            reason: 'Missing "$key" in $lang',
          );
        }
      }
    });
  });
}
