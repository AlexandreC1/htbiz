import '../models/business_model.dart';

/// Weight ratings by the number of reviews, not the number of businesses.
double weightedBusinessRating(Iterable<Business> businesses) {
  var count = 0;
  var total = 0.0;
  for (final business in businesses) {
    count += business.totalReviews;
    total += business.rating * business.totalReviews;
  }
  return count == 0 ? 0 : total / count;
}
