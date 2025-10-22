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
    return _translations[_currentLanguage]?[key] ?? key;
  }

  // Short method name for convenience
  String t(String key) => translate(key);

  // All translations
  static const Map<String, Map<String, String>> _translations = {
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
      'dont_have_account': "Don't have an account?",
      'logout': 'Logout',

      // Validation
      'please_enter_email': 'Please enter your email',
      'please_enter_valid_email': 'Please enter a valid email',
      'please_enter_password': 'Please enter your password',
      'password_min_length': 'Password must be at least 6 characters',
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

      // Time
      'today': 'Today',
      'yesterday': 'Yesterday',
      'days_ago': 'days ago',
      'weeks_ago': 'weeks ago',
      'months_ago': 'months ago',
      'years_ago': 'years ago',
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
      'dont_have_account': "Vous n'avez pas de compte?",
      'logout': 'Se déconnecter',

      // Validation
      'please_enter_email': 'Veuillez entrer votre email',
      'please_enter_valid_email': 'Veuillez entrer un email valide',
      'please_enter_password': 'Veuillez entrer votre mot de passe',
      'password_min_length':
          'Le mot de passe doit contenir au moins 6 caractères',
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

      // Time
      'today': 'Aujourd\'hui',
      'yesterday': 'Hier',
      'days_ago': 'jours',
      'weeks_ago': 'semaines',
      'months_ago': 'mois',
      'years_ago': 'ans',
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
      'dont_have_account': "Ou pa gen kont?",
      'logout': 'Dekonekte',

      // Validation
      'please_enter_email': 'Tanpri antre imèl ou',
      'please_enter_valid_email': 'Tanpri antre yon imèl valab',
      'please_enter_password': 'Tanpri antre modpas ou',
      'password_min_length': 'Modpas la dwe gen omwen 6 karaktè',
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

      // Time
      'today': 'Jodi a',
      'yesterday': 'Yè',
      'days_ago': 'jou pase',
      'weeks_ago': 'semèn pase',
      'months_ago': 'mwa pase',
      'years_ago': 'ane pase',
    },
  };
}
