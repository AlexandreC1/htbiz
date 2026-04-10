import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService extends ChangeNotifier {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  String _currentLanguage = 'en'; // Default: English

  String get currentLanguage => _currentLanguage;

  // Initialize and load saved language
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString('language') ?? 'en';
    notifyListeners();
  }

  // Change language
  Future<void> setLanguage(String languageCode) async {
    _currentLanguage = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);
    notifyListeners();
  }

  // Get translated string
  String translate(String key) {
    return _translationsMap[_currentLanguage]?[key] ?? key;
  }

  // Short method name for convenience
  String t(String key) => translate(key);

  // All translations
  /// Exposed for testing — verifies all languages have matching keys.
  static const Map<String, Map<String, String>> translations = _translationsMap;

  static const Map<String, Map<String, String>> _translationsMap = {
    'en': {
      // App General
      'app_name': 'HTBIZ',
      'app_tagline': 'Discover Local Businesses in Haiti',

      // Authentication
      'welcome': 'Welcome to HTBIZ',
      'sign_in': 'Sign In',
      'sign_up': 'Sign Up',
      'sign_in_to_continue': 'Sign in to continue',
      'create_account': 'Create Account',
      'join_htbiz': 'Join HTBIZ',
      'email': 'Email',
      'password': 'Password',
      'confirm_password': 'Confirm Password',
      'continue_as_guest': 'Continue as Guest',
      'continue_with_google': 'Continue with Google',
      'or': 'or',
      'dont_have_account': "Don't have an account?",
      'logout': 'Logout',

      // Validation
      'please_enter_email': 'Please enter your email',
      'please_enter_valid_email': 'Please enter a valid email',
      'please_enter_password': 'Please enter your password',
      'password_min_length': 'Password must be at least 8 characters',
      'password_complexity': 'Must include uppercase, lowercase, and a number',
      'please_confirm_password': 'Please confirm your password',
      'passwords_dont_match': 'Passwords do not match',

      // Home Screen
      'search_businesses': 'Search businesses...',
      'all': 'All',
      'restaurant': 'Restaurant',
      'hotel': 'Hotel',
      'shop': 'Shop',
      'service': 'Service',
      'entertainment': 'Entertainment',
      'healthcare': 'Healthcare',
      'education': 'Education',
      'other': 'Other',
      'no_businesses_found': 'No businesses found',
      'be_first_to_add': 'Be the first to add one!',
      'add_business': 'Add Business',

      // Business Details
      'about': 'About',
      'contact': 'Contact',
      'reviews': 'Reviews',
      'favorites': 'Favorites',
      'write_review': 'Write a Review',
      'no_reviews_yet': 'No reviews yet',
      'be_first_to_review': 'Be the first to review!',
      'edit_business': 'Edit Business',
      'delete_business': 'Delete Business',
      'delete_confirmation':
          'Are you sure you want to delete this business? This action cannot be undone.',
      'cancel': 'Cancel',
      'delete': 'Delete',

      // Add Business
      'business_name': 'Business Name',
      'category': 'Category',
      'description': 'Description',
      'address': 'Address',
      'phone_number': 'Phone Number',
      'phone_optional': 'Phone Number (Optional)',
      'whatsapp_optional': 'WhatsApp (Optional)',
      'website_optional': 'Website (Optional)',
      'hours_optional': 'Opening Hours (Optional)',
      'add_business_photo': 'Add Business Photo',
      'tap_to_select': 'Tap to select',
      'please_enter_business_name': 'Please enter business name',
      'please_enter_description': 'Please enter description',
      'please_enter_address': 'Please enter address',
      'choose_from_gallery': 'Choose from Gallery',
      'take_photo': 'Take a Photo',
      'remove_photo': 'Remove Photo',

      // Reviews
      'add_review': 'Add Review',
      'rating': 'Rating',
      'comment': 'Comment',
      'comment_optional': 'Comment (Optional)',
      'submit': 'Submit',
      'please_sign_in_to_review': 'Please sign in to add a review',
      'post_anonymously': 'Post anonymously',
      'anonymous': 'Anonymous',
      'open_in_maps': 'Open in Google Maps',
      'approximate_location': 'Approximate location',

      // Profile
      'profile': 'Profile',
      'language': 'Language',
      'select_language': 'Select Language',
      'english': 'English',
      'french': 'Français',
      'haitian_creole': 'Kreyòl Ayisyen',

      // Messages
      'success': 'Success!',
      'error': 'Error',
      'business_added_success': 'Business added successfully!',
      'review_added_success': 'Review added successfully!',
      'business_deleted_success': 'Business deleted successfully',
      'account_created': 'Account created! Please check your email to verify.',
      'error_loading_businesses': 'Error loading businesses',
      'error_loading_business': 'Error loading business',
      'offline_showing_saved': "You're offline — showing saved data",
      'retry': 'Retry',

      // Notifications
      'notifications': 'Notifications',
      'no_notifications': 'No notifications yet',
      'mark_all_read': 'Mark all as read',
      'new_review_on': 'New review on',

      // Analytics
      'analytics': 'Analytics',
      'dashboard': 'Dashboard',
      'total_reviews': 'Total Reviews',
      'avg_rating': 'Avg Rating',
      'total_favorites': 'Total Favorites',
      'rating_distribution': 'Rating Distribution',
      'your_businesses': 'Your Businesses',
      'manage_businesses': 'Manage, create & view analytics',
      'no_businesses_yet': 'No businesses added yet',
      'recent_reviews': 'Recent Reviews',

      // Location
      'sort_by_distance': 'Nearest',
      'distance_km': 'km away',
      'location_unavailable': 'Location unavailable',
      'latitude_optional': 'Latitude (Optional)',
      'longitude_optional': 'Longitude (Optional)',
      'use_current_location': 'Use Current Location',

      // Time
      'today': 'Today',
      'yesterday': 'Yesterday',
      'days_ago': 'days ago',
      'weeks_ago': 'weeks ago',
      'months_ago': 'months ago',
      'years_ago': 'years ago',

      // Review likes & check-ins
      'like': 'Like',
      'likes': 'likes',
      'liked': 'Liked',
      'check_in': 'Check In',
      'checked_in': 'Checked In',
      'verified_visit': 'Verified Visit',
      'check_in_success': 'You checked in! Your reviews will be marked as verified.',
      'already_checked_in': 'You already checked in to this business.',
      'sign_in_to_like': 'Sign in to like reviews',
      'sign_in_to_check_in': 'Sign in to check in',

      // Business verification
      'verified_business': 'Verified Business',
      'upload_patent': 'Upload Business Patent',
      'upload_patent_description': 'Upload a photo of your business patent (patente) to get verified. This helps build trust with customers.',
      'uploading_patent': 'Uploading patent document...',
      'verification_submitted': 'Verification submitted! We will review your document shortly.',
      'verification_pending': 'Verification under review',
      'verification_rejected': 'Verification was rejected. Please try again with a clearer document.',
      'not_verified_hint': 'Upload your patent to get verified',
      'verify_now': 'Verify',

      // Map
      'map_view': 'Map',
      'my_location': 'My Location',
      'on_map': 'businesses on map',

      // Navigation & Profile
      'home': 'Home',
      'account': 'Account',
      'settings': 'Settings',
      'full_name': 'Full Name',
      'enter_full_name': 'Enter your full name',
      'not_set': 'Not set',
      'account_type': 'Account Type',
      'business_owner': 'Business Owner',
      'client': 'Client',
      'switch': 'Switch',
      'change_role': 'Change Account Type',
      'switch_to_owner_desc': 'Switch to Business Owner? You will be able to list and manage businesses.',
      'switch_to_client_desc': 'Switch to Client? You will no longer be able to add businesses.',
      'confirm': 'Confirm',
      'guest': 'Guest',
      'sign_out': 'Sign Out',
    },
    'fr': {
      // App General
      'app_name': 'HTBIZ',
      'app_tagline': 'Découvrez les entreprises locales en Haïti',

      // Authentication
      'welcome': 'Bienvenue à HTBIZ',
      'sign_in': 'Se connecter',
      'sign_up': "S'inscrire",
      'sign_in_to_continue': 'Connectez-vous pour continuer',
      'create_account': 'Créer un compte',
      'join_htbiz': 'Rejoignez HTBIZ',
      'email': 'Email',
      'password': 'Mot de passe',
      'confirm_password': 'Confirmer le mot de passe',
      'continue_as_guest': 'Continuer en tant qu\'invité',
      'continue_with_google': 'Continuer avec Google',
      'or': 'ou',
      'dont_have_account': "Vous n'avez pas de compte?",
      'logout': 'Se déconnecter',

      // Validation
      'please_enter_email': 'Veuillez entrer votre email',
      'please_enter_valid_email': 'Veuillez entrer un email valide',
      'please_enter_password': 'Veuillez entrer votre mot de passe',
      'password_min_length':
          'Le mot de passe doit contenir au moins 8 caractères',
      'password_complexity': 'Doit contenir majuscule, minuscule et chiffre',
      'please_confirm_password': 'Veuillez confirmer votre mot de passe',
      'passwords_dont_match': 'Les mots de passe ne correspondent pas',

      // Home Screen
      'search_businesses': 'Rechercher des entreprises...',
      'all': 'Tout',
      'restaurant': 'Restaurant',
      'hotel': 'Hôtel',
      'shop': 'Magasin',
      'service': 'Service',
      'entertainment': 'Divertissement',
      'healthcare': 'Santé',
      'education': 'Éducation',
      'other': 'Autre',
      'no_businesses_found': 'Aucune entreprise trouvée',
      'be_first_to_add': 'Soyez le premier à en ajouter une!',
      'add_business': 'Ajouter une entreprise',

      // Business Details
      'about': 'À propos',
      'contact': 'Contact',
      'reviews': 'Avis',
      'favorites': 'Favoris',
      'write_review': 'Écrire un avis',
      'no_reviews_yet': 'Pas encore d\'avis',
      'be_first_to_review': 'Soyez le premier à donner votre avis!',
      'edit_business': 'Modifier l\'entreprise',
      'delete_business': 'Supprimer l\'entreprise',
      'delete_confirmation':
          'Êtes-vous sûr de vouloir supprimer cette entreprise? Cette action ne peut pas être annulée.',
      'cancel': 'Annuler',
      'delete': 'Supprimer',

      // Add Business
      'business_name': 'Nom de l\'entreprise',
      'category': 'Catégorie',
      'description': 'Description',
      'address': 'Adresse',
      'phone_number': 'Numéro de téléphone',
      'phone_optional': 'Numéro de téléphone (Optionnel)',
      'whatsapp_optional': 'WhatsApp (Optionnel)',
      'website_optional': 'Site web (Optionnel)',
      'hours_optional': 'Heures d\'ouverture (Optionnel)',
      'add_business_photo': 'Ajouter une photo',
      'tap_to_select': 'Appuyez pour sélectionner',
      'please_enter_business_name': 'Veuillez entrer le nom de l\'entreprise',
      'please_enter_description': 'Veuillez entrer une description',
      'please_enter_address': 'Veuillez entrer l\'adresse',
      'choose_from_gallery': 'Choisir depuis la galerie',
      'take_photo': 'Prendre une photo',
      'remove_photo': 'Supprimer la photo',

      // Reviews
      'add_review': 'Ajouter un avis',
      'rating': 'Note',
      'comment': 'Commentaire',
      'comment_optional': 'Commentaire (Optionnel)',
      'submit': 'Soumettre',
      'please_sign_in_to_review':
          'Veuillez vous connecter pour ajouter un avis',
      'post_anonymously': 'Publier anonymement',
      'anonymous': 'Anonyme',
      'open_in_maps': 'Ouvrir dans Google Maps',
      'approximate_location': 'Emplacement approximatif',

      // Profile
      'profile': 'Profil',
      'language': 'Langue',
      'select_language': 'Sélectionner la langue',
      'english': 'English',
      'french': 'Français',
      'haitian_creole': 'Kreyòl Ayisyen',

      // Messages
      'success': 'Succès!',
      'error': 'Erreur',
      'business_added_success': 'Entreprise ajoutée avec succès!',
      'review_added_success': 'Avis ajouté avec succès!',
      'business_deleted_success': 'Entreprise supprimée avec succès',
      'account_created': 'Compte créé! Veuillez vérifier votre email.',
      'error_loading_businesses': 'Erreur lors du chargement des entreprises',
      'error_loading_business': 'Erreur lors du chargement de l\'entreprise',
      'offline_showing_saved': 'Hors ligne — affichage des données enregistrées',
      'retry': 'Réessayer',

      // Notifications
      'notifications': 'Notifications',
      'no_notifications': 'Aucune notification',
      'mark_all_read': 'Tout marquer comme lu',
      'new_review_on': 'Nouvel avis sur',

      // Analytics
      'analytics': 'Analytique',
      'dashboard': 'Tableau de bord',
      'total_reviews': 'Total des avis',
      'avg_rating': 'Note moyenne',
      'total_favorites': 'Total des favoris',
      'rating_distribution': 'Distribution des notes',
      'your_businesses': 'Vos entreprises',
      'manage_businesses': 'Gérer, créer et voir les analytiques',
      'no_businesses_yet': 'Aucune entreprise ajoutée',
      'recent_reviews': 'Avis récents',

      // Location
      'sort_by_distance': 'Plus proche',
      'distance_km': 'km',
      'location_unavailable': 'Localisation indisponible',
      'latitude_optional': 'Latitude (Optionnel)',
      'longitude_optional': 'Longitude (Optionnel)',
      'use_current_location': 'Utiliser la position actuelle',

      // Time
      'today': 'Aujourd\'hui',
      'yesterday': 'Hier',
      'days_ago': 'jours',
      'weeks_ago': 'semaines',
      'months_ago': 'mois',
      'years_ago': 'ans',

      // Review likes & check-ins
      'like': 'J\'aime',
      'likes': 'j\'aime',
      'liked': 'Aimé',
      'check_in': 'S\'enregistrer',
      'checked_in': 'Enregistré',
      'verified_visit': 'Visite vérifiée',
      'check_in_success': 'Enregistrement réussi! Vos avis seront marqués comme vérifiés.',
      'already_checked_in': 'Vous êtes déjà enregistré dans cette entreprise.',
      'sign_in_to_like': 'Connectez-vous pour aimer les avis',
      'sign_in_to_check_in': 'Connectez-vous pour vous enregistrer',

      // Business verification
      'verified_business': 'Entreprise vérifiée',
      'upload_patent': 'Téléverser la patente',
      'upload_patent_description': 'Téléversez une photo de votre patente commerciale pour être vérifié. Cela renforce la confiance des clients.',
      'uploading_patent': 'Téléversement de la patente...',
      'verification_submitted': 'Vérification soumise! Nous examinerons votre document sous peu.',
      'verification_pending': 'Vérification en cours d\'examen',
      'verification_rejected': 'Vérification refusée. Veuillez réessayer avec un document plus clair.',
      'not_verified_hint': 'Téléversez votre patente pour être vérifié',
      'verify_now': 'Vérifier',

      // Map
      'map_view': 'Carte',
      'my_location': 'Ma position',
      'on_map': 'entreprises sur la carte',

      // Navigation & Profile
      'home': 'Accueil',
      'account': 'Compte',
      'settings': 'Param\u00e8tres',
      'full_name': 'Nom complet',
      'enter_full_name': 'Entrez votre nom complet',
      'not_set': 'Non d\u00e9fini',
      'account_type': 'Type de compte',
      'business_owner': 'Propri\u00e9taire',
      'client': 'Client',
      'switch': 'Changer',
      'change_role': 'Changer le type de compte',
      'switch_to_owner_desc': 'Passer \u00e0 Propri\u00e9taire? Vous pourrez g\u00e9rer des entreprises.',
      'switch_to_client_desc': 'Passer \u00e0 Client? Vous ne pourrez plus ajouter d\'entreprises.',
      'confirm': 'Confirmer',
      'guest': 'Invit\u00e9',
      'sign_out': 'Se d\u00e9connecter',
    },
    'ht': {
      // App General
      'app_name': 'HTBIZ',
      'app_tagline': 'Dekouvri biznis lokal nan Ayiti',

      // Authentication
      'welcome': 'Byenveni nan HTBIZ',
      'sign_in': 'Konekte',
      'sign_up': 'Enskri',
      'sign_in_to_continue': 'Konekte pou kontinye',
      'create_account': 'Kreye yon kont',
      'join_htbiz': 'Vin jwenn HTBIZ',
      'email': 'Imèl',
      'password': 'Modpas',
      'confirm_password': 'Konfime modpas',
      'continue_as_guest': 'Kontinye tankou envite',
      'continue_with_google': 'Kontinye ak Google',
      'or': 'oswa',
      'dont_have_account': "Ou pa gen kont?",
      'logout': 'Dekonekte',

      // Validation
      'please_enter_email': 'Tanpri antre imèl ou',
      'please_enter_valid_email': 'Tanpri antre yon imèl valab',
      'please_enter_password': 'Tanpri antre modpas ou',
      'password_min_length': 'Modpas la dwe gen omwen 8 karaktè',
      'password_complexity': 'Dwe gen majiskil, miniskil, ak yon chif',
      'please_confirm_password': 'Tanpri konfime modpas ou',
      'passwords_dont_match': 'Modpas yo pa menm',

      // Home Screen
      'search_businesses': 'Chèche biznis...',
      'all': 'Tout',
      'restaurant': 'Restoran',
      'hotel': 'Otèl',
      'shop': 'Magazen',
      'service': 'Sèvis',
      'entertainment': 'Amizman',
      'healthcare': 'Sante',
      'education': 'Edikasyon',
      'other': 'Lòt',
      'no_businesses_found': 'Pa gen biznis',
      'be_first_to_add': 'Ou ka premye moun ki ajoute youn!',
      'add_business': 'Ajoute Biznis',

      // Business Details
      'about': 'Sou biznis la',
      'contact': 'Kontak',
      'reviews': 'Reviw',
      'favorites': 'Favori',
      'write_review': 'Ekri yon reviw',
      'no_reviews_yet': 'Poko gen reviw',
      'be_first_to_review': 'Ou ka premye moun ki bay reviw!',
      'edit_business': 'Modifye biznis la',
      'delete_business': 'Efase biznis la',
      'delete_confirmation':
          'Èske ou si ou vle efase biznis sa a? Ou pa ka anile aksyon sa a.',
      'cancel': 'Anile',
      'delete': 'Efase',

      // Add Business
      'business_name': 'Non biznis la',
      'category': 'Kategori',
      'description': 'Deskripsyon',
      'address': 'Adrès',
      'phone_number': 'Nimewo telefòn',
      'phone_optional': 'Nimewo telefòn (Opsyonèl)',
      'whatsapp_optional': 'WhatsApp (Opsyonèl)',
      'website_optional': 'Sit entènèt (Opsyonèl)',
      'hours_optional': 'Orè ouvèti (Opsyonèl)',
      'add_business_photo': 'Ajoute foto biznis la',
      'tap_to_select': 'Peze pou chwazi',
      'please_enter_business_name': 'Tanpri antre non biznis la',
      'please_enter_description': 'Tanpri antre yon deskripsyon',
      'please_enter_address': 'Tanpri antre adrès la',
      'choose_from_gallery': 'Chwazi nan galri',
      'take_photo': 'Pran yon foto',
      'remove_photo': 'Retire foto a',

      // Reviews
      'add_review': 'Ajoute yon reviw',
      'rating': 'Nòt',
      'comment': 'Kòmantè',
      'comment_optional': 'Kòmantè (Opsyonèl)',
      'submit': 'Soumèt',
      'please_sign_in_to_review': 'Tanpri konekte pou ajoute yon reviw',
      'post_anonymously': 'Pibliye anonim',
      'anonymous': 'Anonim',
      'open_in_maps': 'Ouvri nan Google Maps',
      'approximate_location': 'Anplasman apwoksimatif',

      // Profile
      'profile': 'Profil',
      'language': 'Lang',
      'select_language': 'Chwazi lang',
      'english': 'English',
      'french': 'Français',
      'haitian_creole': 'Kreyòl Ayisyen',

      // Messages
      'success': 'Siksè!',
      'error': 'Erè',
      'business_added_success': 'Biznis ajoute avèk siksè!',
      'review_added_success': 'Reviw ajoute avèk siksè!',
      'business_deleted_success': 'Biznis efase avèk siksè',
      'account_created': 'Kont kreye! Tanpri tcheke imèl ou.',
      'error_loading_businesses': 'Erè nan chajman biznis yo',
      'error_loading_business': 'Erè nan chajman biznis la',
      'offline_showing_saved': 'Pa gen entènèt — n ap montre done ki sere yo',
      'retry': 'Eseye ankò',

      // Notifications
      'notifications': 'Notifikasyon',
      'no_notifications': 'Pa gen notifikasyon ankò',
      'mark_all_read': 'Make tout kòm li',
      'new_review_on': 'Nouvo reviw sou',

      // Analytics
      'analytics': 'Analiz',
      'dashboard': 'Tablo',
      'total_reviews': 'Total reviw',
      'avg_rating': 'Nòt mwayèn',
      'total_favorites': 'Total favori',
      'rating_distribution': 'Distribisyon nòt',
      'your_businesses': 'Biznis ou yo',
      'manage_businesses': 'Jere, kreye epi wè analiz',
      'no_businesses_yet': 'Pa gen biznis ajoute ankò',
      'recent_reviews': 'Dènye reviw yo',

      // Location
      'sort_by_distance': 'Pi pre',
      'distance_km': 'km',
      'location_unavailable': 'Lokalizasyon pa disponib',
      'latitude_optional': 'Latitid (Opsyonèl)',
      'longitude_optional': 'Longitid (Opsyonèl)',
      'use_current_location': 'Itilize pozisyon aktyèl',

      // Time
      'today': 'Jodi a',
      'yesterday': 'Yè',
      'days_ago': 'jou pase',
      'weeks_ago': 'semèn pase',
      'months_ago': 'mwa pase',
      'years_ago': 'ane pase',

      // Review likes & check-ins
      'like': 'Renmen',
      'likes': 'renmen',
      'liked': 'Renmen',
      'check_in': 'Anrejistre',
      'checked_in': 'Anrejistre',
      'verified_visit': 'Vizit verifye',
      'check_in_success': 'Ou anrejistre! Reviw ou yo ap gen mak verifye.',
      'already_checked_in': 'Ou deja anrejistre nan biznis sa a.',
      'sign_in_to_like': 'Konekte pou renmen reviw',
      'sign_in_to_check_in': 'Konekte pou anrejistre',

      // Business verification
      'verified_business': 'Biznis verifye',
      'upload_patent': 'Voye patant biznis',
      'upload_patent_description': 'Voye yon foto patant biznis ou pou yo verifye ou. Sa ede kliyan yo fè ou konfyans.',
      'uploading_patent': 'Ap voye patant lan...',
      'verification_submitted': 'Verifikasyon soumèt! Nou pral egzamine dokiman ou talè.',
      'verification_pending': 'Verifikasyon ap revize',
      'verification_rejected': 'Verifikasyon refize. Tanpri eseye ankò ak yon dokiman pi klè.',
      'not_verified_hint': 'Voye patant ou pou yo verifye ou',
      'verify_now': 'Verifye',

      // Map
      'map_view': 'Kat',
      'my_location': 'Pozisyon mwen',
      'on_map': 'biznis sou kat la',

      // Navigation & Profile
      'home': 'Lakay',
      'account': 'Kont',
      'settings': 'Param\u00e8t',
      'full_name': 'Non konpl\u00e8',
      'enter_full_name': 'Antre non konpl\u00e8 ou',
      'not_set': 'Pa defini',
      'account_type': 'Tip kont',
      'business_owner': 'Propriyet\u00e8',
      'client': 'Kliyan',
      'switch': 'Chanje',
      'change_role': 'Chanje tip kont',
      'switch_to_owner_desc': 'Chanje an Propriyet\u00e8? Ou ap kapab jere biznis.',
      'switch_to_client_desc': 'Chanje an Kliyan? Ou p ap kapab ajoute biznis ank\u00f2.',
      'confirm': 'Konfime',
      'guest': 'Envite',
      'sign_out': 'Dekonekte',
    },
  };
}
