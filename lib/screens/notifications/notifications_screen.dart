import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/notification_model.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../business/business_detail_screen.dart';
import '../main_shell.dart';

class NotificationsScreen extends StatefulWidget {
  final bool embedded;
  final MainShellState? shell;
  const NotificationsScreen({super.key, this.embedded = false, this.shell});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _businessService = BusinessService();
  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final notifications = await _businessService.getNotifications(user.id);
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await _businessService.markAllNotificationsRead(user.id);
    await _loadNotifications();
    widget.shell?.refreshNotificationCount();
  }

  Future<void> _onTapNotification(AppNotification notification) async {
    if (!notification.isRead) {
      await _businessService.markNotificationRead(notification.id);
      // Update the list locally so the dot/tile-bg changes immediately,
      // and refresh the shell badge so the bell counter drops.
      if (mounted) {
        setState(() {
          final i = _notifications.indexWhere((n) => n.id == notification.id);
          if (i != -1) {
            _notifications[i] = _notifications[i].copyWith(isRead: true);
          }
        });
      }
      widget.shell?.refreshNotificationCount();
    }

    if (notification.businessId != null && mounted) {
      await Navigator.push(
        context,
        FadeSlideRoute(
          page: BusinessDetailScreen(businessId: notification.businessId!),
        ),
      );
      _loadNotifications();
      widget.shell?.refreshNotificationCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('notifications')),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                localization.t('mark_all_read'),
                style: const TextStyle(color: Color(0xFF006064)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        localization.t('no_notifications'),
                        style:
                            TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _NotificationTile(
                        notification: notification,
                        onTap: () => _onTapNotification(notification),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  IconData get _icon {
    switch (notification.type) {
      case 'new_review':
        return Icons.rate_review;
      case 'review_reply':
        return Icons.reply;
      default:
        return Icons.notifications;
    }
  }

  Color get _iconColor {
    switch (notification.type) {
      case 'new_review':
        return Colors.blue;
      case 'review_reply':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${diff.inDays ~/ 7}w';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: notification.isRead ? null : Colors.teal.withValues(alpha: 0.05),
      leading: CircleAvatar(
        backgroundColor: _iconColor.withValues(alpha: 0.15),
        child: Icon(_icon, color: _iconColor, size: 20),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
          fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        notification.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _timeAgo(notification.createdAt),
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          if (!notification.isRead)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.teal,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
