import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/localization_service.dart';
import '../../services/usage_analytics_service.dart';
import '../../widgets/app_toast.dart';
import '../business/usage_dashboard_screen.dart';

class UsageSettingsScreen extends StatefulWidget {
  const UsageSettingsScreen({super.key});
  @override
  State<UsageSettingsScreen> createState() => _UsageSettingsScreenState();
}

class _UsageSettingsScreenState extends State<UsageSettingsScreen> {
  bool _admin = false;
  bool _busy = false;
  bool _retentionBusy = false;
  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    try {
      final allowed = await supabase.rpc('htbiz_is_admin');
      if (mounted) setState(() => _admin = allowed == true);
    } catch (_) {/* Access stays closed if authorization is unavailable. */}
  }

  Future<void> _changeConsent(bool value) async {
    setState(() => _busy = true);
    try {
      await UsageAnalyticsService.instance.setEnabled(value);
    } catch (_) {
      if (mounted) {
        AppToast.error(context, LocalizationService().t('usage_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRetention(int? value) async {
    if (value == null) return;
    setState(() => _retentionBusy = true);
    try {
      await UsageAnalyticsService.instance.setRetentionDays(value);
    } catch (_) {
      if (mounted) {
        AppToast.error(context, LocalizationService().t('usage_failed'));
      }
    } finally {
      if (mounted) setState(() => _retentionBusy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await UsageAnalyticsService.instance.setEnabled(false);
      await supabase.rpc('delete_my_usage');
      if (mounted) {
        AppToast.success(context, LocalizationService().t('usage_deleted'));
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, LocalizationService().t('usage_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(title: Text(loc.t('usage_privacy'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(loc.t('usage_disclosure_button'),
              style: Theme.of(context).textTheme.titleSmall),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(loc.t('usage_notice'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: UsageAnalyticsService.instance,
          builder: (context, _) => SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.t('usage_opt_in')),
            value: UsageAnalyticsService.instance.enabled,
            onChanged: _busy ? null : _changeConsent,
          ),
        ),
        ListenableBuilder(
          listenable: UsageAnalyticsService.instance,
          builder: (context, _) => DropdownButtonFormField<int>(
            key: ValueKey(UsageAnalyticsService.instance.retentionDays),
            value: UsageAnalyticsService.instance.retentionDays,
            decoration: InputDecoration(
              labelText: loc.t('usage_retention'),
              border: const OutlineInputBorder(),
            ),
            items: [7, 30, 90, 365]
                .map((days) => DropdownMenuItem(
                      value: days,
                      child: Text('$days ${loc.t('usage_days')}'),
                    ))
                .toList(),
            onChanged: _busy || _retentionBusy ? null : _changeRetention,
          ),
        ),
        if (_retentionBusy) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: Text(loc.t('usage_delete')),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_admin) ...[
          const Divider(height: 40),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(loc.t('usage_dashboard')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const UsageDashboardScreen())),
          ),
        ],
      ]),
    );
  }
}
