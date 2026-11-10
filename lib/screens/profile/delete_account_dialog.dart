import 'package:flutter/material.dart';
import '../../services/localization_service.dart';

/// Asks the user to confirm the permanent deletion of their account.
///
/// Pops with `true` only after the confirmation word was typed.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.localization});

  final LocalizationService localization;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = widget.localization;
    final word = localization.t('delete_account_confirm_word').toUpperCase();
    final promptTemplate = localization.t('delete_account_type_to_confirm');
    final prompt = promptTemplate.replaceAll('{word}', word);
    const items = [
      'delete_account_item_profile',
      'delete_account_item_reviews',
      'delete_account_item_favorites',
      'delete_account_item_businesses',
    ];

    return AlertDialog(
      title: Text(localization.t('delete_account_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localization.t('delete_account_intro')),
            const SizedBox(height: 8),
            for (final key in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(localization.t(key))),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              localization.t('delete_account_irreversible'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Text(prompt),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: word),
              onChanged: (value) {
                final matches = value.trim().toUpperCase() == word;
                if (matches != _matches) setState(() => _matches = matches);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(localization.t('cancel')),
        ),
        ElevatedButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(localization.t('delete_account_confirm_button')),
        ),
      ],
    );
  }
}
