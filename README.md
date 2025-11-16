# HTBIZ

A business directory application for Haiti built with Flutter and Supabase.

## Features

- **Animated Onboarding Flow**: Slick, production-ready onboarding experience for first-time users
- **User Authentication**: Email/Password and Guest mode
- **Business Directory**: Listings with advanced search and category filters
- **Business Management**: Add, edit, and delete your businesses
- **Enhanced Profile**:
  - Avatar upload with image picker
  - User statistics (businesses count, reviews count)
  - Quick access to My Businesses and Reviews
  - Language selection (English, French, Haitian Creole)
  - Settings and Help & Support
- **Rating & Review System**: Write reviews with photo uploads
- **Trilingual Support**: EN, FR, and Haitian Creole

## Getting Started

### Prerequisites

- Flutter (3.4.3 or higher)
- Dart (3.0.0 or higher)
- A Supabase account and project

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/htbiz.git
   ```

2. Navigate to the project directory
   ```bash
   cd htbiz
   ```

3. Install dependencies
   ```bash
   flutter pub get
   ```

4. Run the app
   ```bash
   flutter run
   ```

## Configuration

### Supabase Setup

1. Update the Supabase configuration in `lib/config/supabase_config.dart` with your project credentials.

2. Create the following Storage buckets in your Supabase project:
   - `business-images` (for business photos)
   - `avatars` (for user profile pictures)
   - `review-images` (for review photos)

3. Set the bucket policies to allow:
   - Public read access
   - Authenticated users can upload/update their own files

### First Launch

On first app launch, users will see a beautiful animated onboarding flow. This can be reset by clearing app data or the `onboarding_completed` shared preference.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
