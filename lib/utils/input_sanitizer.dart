class InputSanitizer {
  /// Strip HTML tags and limit length for user-generated text content
  static String sanitize(String input, {int maxLength = 1000}) {
    // Remove HTML tags
    final stripped = input.replaceAll(RegExp(r'<[^>]*>'), '');
    // Collapse excessive whitespace
    final collapsed = stripped.replaceAll(RegExp(r'\s{3,}'), '  ');
    // Trim to max length
    if (collapsed.length > maxLength) {
      return collapsed.substring(0, maxLength);
    }
    return collapsed.trim();
  }

  /// Sanitize a business name (no HTML, max 100 chars)
  static String sanitizeName(String input) =>
      sanitize(input, maxLength: 100);

  /// Sanitize a description (no HTML, max 2000 chars)
  static String sanitizeDescription(String input) =>
      sanitize(input, maxLength: 2000);

  /// Sanitize a review comment (no HTML, max 1000 chars)
  static String sanitizeComment(String input) =>
      sanitize(input, maxLength: 1000);

  /// Sanitize an address (no HTML, max 200 chars)
  static String sanitizeAddress(String input) =>
      sanitize(input, maxLength: 200);

  /// Validate and clean a phone number
  static String? sanitizePhone(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    // Keep only digits, +, spaces, dashes, parentheses
    final cleaned = input.replaceAll(RegExp(r'[^\d+\s\-()]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Validate and clean a URL
  static String? sanitizeUrl(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final trimmed = input.trim();
    // Basic URL validation
    if (Uri.tryParse(trimmed)?.hasScheme == true ||
        Uri.tryParse('https://$trimmed')?.host.contains('.') == true) {
      return trimmed;
    }
    return null;
  }
}
