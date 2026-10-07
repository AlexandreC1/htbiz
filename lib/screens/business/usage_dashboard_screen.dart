import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/localization_service.dart';

class UsageDashboardScreen extends StatefulWidget {
  const UsageDashboardScreen({super.key});
  @override
  State<UsageDashboardScreen> createState() => _UsageDashboardScreenState();
}

class _UsageDashboardScreenState extends State<UsageDashboardScreen> {
  final List<Map<String, dynamic>> _events = [];
  bool _busy = true;
  bool _more = true;
  bool _failed = false;
  String? _before;
  String? _beforeId;
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (await supabase.rpc('htbiz_is_admin') != true) {
        throw StateError('Administrator access required');
      }
      final summary = await supabase.rpc('usage_summary');
      var query = supabase.from('usage_events').select();
      if (!reset && _before != null) {
        query = query.or(
            'occurred_at.lt.$_before,and(occurred_at.eq.$_before,id.lt.$_beforeId)');
      }
      final rows = await query
          .order('occurred_at', ascending: false)
          .order('id', ascending: false)
          .limit(51);
      if (!mounted) return;
      setState(() {
        if (reset) _events.clear();
        _summary = Map<String, dynamic>.from(summary as Map);
        _more = rows.length > 50;
        _events.addAll(rows.take(50));
        if (_events.isNotEmpty) {
          _before = _events.last['occurred_at'] as String;
          _beforeId = _events.last['id'] as String;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(title: Text(loc.t('usage_dashboard'))),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(loc.t('usage_window'),
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          if (_summary.isNotEmpty)
            Wrap(spacing: 24, runSpacing: 16, children: [
              Text('${loc.t('usage_users')}: ${_summary['users']}'),
              Text('${loc.t('usage_views')}: ${_summary['screen_views']}'),
              Text(
                  '${loc.t('usage_minutes')}: ${((_summary['active_seconds'] as num) / 60).toStringAsFixed(1)}'),
            ]),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_failed) ...[
            Text(loc.t('usage_failed')),
            TextButton.icon(
                onPressed: _busy ? null : () => _load(reset: true),
                icon: const Icon(Icons.refresh),
                label: Text(loc.t('retry'))),
          ],
          if (!_busy && !_failed && _events.isEmpty) Text(loc.t('usage_empty')),
          ..._events.map((event) => ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.insights_outlined),
                title: Text('${event['screen']} · ${event['event_name']}'),
                subtitle: Text(
                    '${event['os']} · ${event['screen_width']} × ${event['screen_height']}\n'
                    '${DateTime.parse(event['occurred_at'] as String).toLocal()}'),
                children: [
                  SelectableText(
                    'User: ${event['user_id']}\n'
                    'IP: ${event['request_ip'] ?? "—"} (${event['ip_source'] ?? "—"})\n'
                    'Location: ${event['latitude'] ?? "—"}, ${event['longitude'] ?? "—"}\n'
                    'Active seconds: ${event['duration_seconds']}\n'
                    'Media selected: ${event['media_source'] ?? "—"}',
                  ),
                  const SizedBox(height: 16),
                ],
              )),
          if (_more && !_busy && !_failed)
            OutlinedButton(
                onPressed: () => _load(), child: Text(loc.t('load_more'))),
        ]),
      ),
    );
  }
}
