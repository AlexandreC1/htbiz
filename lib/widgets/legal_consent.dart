import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/legal_links.dart';
import '../main.dart';
import '../services/localization_service.dart';
import 'app_toast.dart';

/// A localized sentence whose `{terms}`, `{guidelines}` and `{privacy}`
/// placeholders become links to the published documents.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({
    super.key,
    required this.templateKey,
    this.textAlign = TextAlign.start,
    this.fontSize = 13,
  });

  /// Localization key of the sentence, for example `terms_agree`.
  final String templateKey;
  final TextAlign textAlign;
  final double fontSize;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  static final _placeholder = RegExp(r'\{(terms|guidelines|privacy)\}');

  static const _labelKeys = {
    'terms': 'terms_of_use',
    'guidelines': 'community_guidelines',
    'privacy': 'privacy_policy',
  };

  final _terms = TapGestureRecognizer();
  final _guidelines = TapGestureRecognizer();
  final _privacy = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _terms.onTap = () => _open(LegalLinks.terms);
    _guidelines.onTap = () => _open(LegalLinks.guidelines);
    _privacy.onTap = () => _open(LegalLinks.privacy);
  }

  @override
  void dispose() {
    _terms.dispose();
    _guidelines.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(Uri url) async {
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Could not open $url: $error');
    }
    if (!opened && mounted) {
      AppToast.error(context, LocalizationService().t('link_open_failed'));
    }
  }

  TapGestureRecognizer _recognizerFor(String name) {
    switch (name) {
      case 'terms':
        return _terms;
      case 'guidelines':
        return _guidelines;
      default:
        return _privacy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final template = localization.t(widget.templateKey);
    const linkStyle = TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _placeholder.allMatches(template)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: template.substring(cursor, match.start)));
      }
      final name = match.group(1)!;
      spans.add(
        TextSpan(
          text: localization.t(_labelKeys[name]!),
          style: linkStyle,
          recognizer: _recognizerFor(name),
        ),
      );
      cursor = match.end;
    }
    if (cursor < template.length) {
      spans.add(TextSpan(text: template.substring(cursor)));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: widget.textAlign,
      style: TextStyle(
        fontSize: widget.fontSize,
        height: 1.4,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// The required "I agree" row of the sign up form.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.showError = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// True once the user tried to continue without accepting.
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final missing = showError && !value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              isError: missing,
              onChanged: (checked) => onChanged(checked ?? false),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: LegalConsentText(templateKey: 'terms_agree'),
              ),
            ),
          ],
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 4),
            child: Text(
              localization.t('terms_required'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
