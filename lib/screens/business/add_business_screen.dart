  import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:provider/provider.dart';
  import '../../main.dart';
  import '../../models/business_model.dart';
  import '../../services/business_service.dart';
  import '../../services/localization_service.dart';

  class AddBusinessScreen extends StatefulWidget {
    const AddBusinessScreen({super.key});

    @override
    State<AddBusinessScreen> createState() => _AddBusinessScreenState();
  }

  class _AddBusinessScreenState extends State<AddBusinessScreen> {
    final _formKey = GlobalKey<FormState>();
    final _businessService = BusinessService();
    final _imagePicker = ImagePicker();

    // Controllers
    final _nameController = TextEditingController();
    final _descriptionController = TextEditingController();
    final _addressController = TextEditingController();
    final _phoneController = TextEditingController();
    final _whatsappController = TextEditingController();
    final _websiteController = TextEditingController();
    final _hoursController = TextEditingController();

    // State - USE ENGLISH KEYS INTERNALLY
    String _selectedCategoryKey = 'restaurant'; // CHANGED: Use lowercase key
    File? _selectedImage;
    bool _isLoading = false;

    // Category mapping - keys stay the same, labels translate
    final Map<String, String> _categoryKeys = {
      'restaurant': 'restaurant',
      'hotel': 'hotel',
      'shop': 'shop',
      'service': 'service',
      'entertainment': 'entertainment',
      'healthcare': 'healthcare',
      'education': 'education',
      'other': 'other',
    };

    @override
    void dispose() {
      _nameController.dispose();
      _descriptionController.dispose();
      _addressController.dispose();
      _phoneController.dispose();
      _whatsappController.dispose();
      _websiteController.dispose();
      _hoursController.dispose();
      super.dispose();
    }

    Future<void> _pickImage(ImageSource source) async {
      try {
        final XFile? image = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          setState(() {
            _selectedImage = File(image.path);
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error picking image: $e')),
          );
        }
      }
    }

    void _showImageSourceDialog() {
      final localization =
          Provider.of<LocalizationService>(context, listen: false);

      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(localization.t('choose_from_gallery')),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: Text(localization.t('take_photo')),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_selectedImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(localization.t('remove_photo')),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedImage = null);
                  },
                ),
            ],
          ),
        ),
      );
    }

    Future<void> _submitForm() async {
      if (!_formKey.currentState!.validate()) return;

      setState(() => _isLoading = true);

      try {
        String? imageUrl;

        // Upload image if selected
        if (_selectedImage != null) {
          imageUrl = await _businessService.uploadBusinessImage(_selectedImage!);
        }

        // Get translated category name for storage
        final localization =
            Provider.of<LocalizationService>(context, listen: false);
        final categoryDisplay = localization.t(_selectedCategoryKey);

        // Create business object
        final business = Business(
          id: '',
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          category: categoryDisplay,
          address: _addressController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
          whatsapp: _whatsappController.text.trim().isNotEmpty ? _whatsappController.text.trim() : null,
          website: _websiteController.text.trim().isNotEmpty ? _websiteController.text.trim() : null,
          hoursText: _hoursController.text.trim().isNotEmpty ? _hoursController.text.trim() : null,
          imageUrl: imageUrl,
          rating: 0.0,
          totalReviews: 0,
          ownerId: supabase.auth.currentUser!.id,
          createdAt: DateTime.now(),
        );

        // Save to Supabase
        await _businessService.createBusiness(business);

        if (mounted) {
          final localization =
              Provider.of<LocalizationService>(context, listen: false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localization.t('business_added_success')),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          final localization =
              Provider.of<LocalizationService>(context, listen: false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${localization.t('error')}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }

    @override
    Widget build(BuildContext context) {
      final localization = Provider.of<LocalizationService>(context);

      return Scaffold(
        appBar: AppBar(
          title: Text(localization.t('add_business')),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Image picker
                      GestureDetector(
                        onTap: _showImageSourceDialog,
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: _selectedImage != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 60,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      localization.t('add_business_photo'),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      localization.t('tap_to_select'),
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Business Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: '${localization.t('business_name')} *',
                          prefixIcon: const Icon(Icons.business),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return localization.t('please_enter_business_name');
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Category Dropdown - FIXED VERSION
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryKey,
                        decoration: InputDecoration(
                          labelText: '${localization.t('category')} *',
                          prefixIcon: const Icon(Icons.category),
                        ),
                        items: _categoryKeys.keys.map((key) {
                          return DropdownMenuItem(
                            value: key,
                            child: Text(localization.t(key)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedCategoryKey = value!);
                        },
                      ),

                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: '${localization.t('description')} *',
                          prefixIcon: const Icon(Icons.description),
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return localization.t('please_enter_description');
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Address
                      TextFormField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: '${localization.t('address')} *',
                          prefixIcon: const Icon(Icons.location_on),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return localization.t('please_enter_address');
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Phone Number
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: localization.t('phone_optional'),
                          prefixIcon: const Icon(Icons.phone),
                          hintText: '+509 XXXX XXXX',
                        ),
                        keyboardType: TextInputType.phone,
                      ),

                      const SizedBox(height: 16),

                      // WhatsApp
                      TextFormField(
                        controller: _whatsappController,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp (optional)',
                          prefixIcon: Icon(Icons.chat),
                          hintText: '+509 XXXX XXXX',
                        ),
                        keyboardType: TextInputType.phone,
                      ),

                      const SizedBox(height: 16),

                      // Website
                      TextFormField(
                        controller: _websiteController,
                        decoration: const InputDecoration(
                          labelText: 'Website (optional)',
                          prefixIcon: Icon(Icons.language),
                          hintText: 'https://example.com',
                        ),
                        keyboardType: TextInputType.url,
                      ),

                      const SizedBox(height: 16),

                      // Hours
                      TextFormField(
                        controller: _hoursController,
                        decoration: const InputDecoration(
                          labelText: 'Business Hours (optional)',
                          prefixIcon: Icon(Icons.schedule),
                          hintText: 'e.g. Mon-Fri 8am-6pm, Sat 9am-3pm',
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Submit Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                localization.t('add_business'),
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),

                      const SizedBox(height: 16),

                      // Cancel Button
                      OutlinedButton(
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
                        child: Text(localization.t('cancel')),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }
  }
