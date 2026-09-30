import 'package:flutter_test/flutter_test.dart';
import 'package:htbiz/models/business_model.dart';
import 'package:htbiz/utils/business_statistics.dart';

Business business(double rating, int count) => Business(
      id: '$rating',
      name: 'Business',
      description: '',
      category: 'shop',
      address: '',
      ownerId: 'owner',
      createdAt: DateTime(2026),
      rating: rating,
      totalReviews: count,
    );

void main() {
  test('weights by reviews rather than businesses', () {
    expect(weightedBusinessRating([business(5, 1), business(1, 99)]), 1.04);
  });
  test('unrated businesses do not lower the average', () {
    expect(weightedBusinessRating([business(0, 0), business(4, 3)]), 4);
    expect(weightedBusinessRating([]), 0);
  });
}
