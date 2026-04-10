import 'dart:async';
import 'package:flutter/material.dart';

enum AppToastType { info, success, error, warning }

/// Top-right overlay toast (replaces bottom SnackBar for in-app notifications).
class AppToast {
  static final List<_ToastEntry> _active = [];

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = _ToastEntry(message: message, type: type);
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (ctx) => _ToastStack(entry: entry),
    );
    entry.overlayEntry = overlayEntry;

    _active.add(entry);
    overlay.insert(overlayEntry);

    Timer(duration, () => _dismiss(entry));
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: AppToastType.success);
  static void error(BuildContext context, String message) =>
      show(context, message, type: AppToastType.error);
  static void warning(BuildContext context, String message) =>
      show(context, message, type: AppToastType.warning);

  static void _dismiss(_ToastEntry entry) {
    if (!_active.contains(entry)) return;
    entry.dismissing.value = true;
    Future.delayed(const Duration(milliseconds: 250), () {
      entry.overlayEntry?.remove();
      _active.remove(entry);
    });
  }
}

class _ToastEntry {
  final String message;
  final AppToastType type;
  final ValueNotifier<bool> dismissing = ValueNotifier(false);
  OverlayEntry? overlayEntry;
  _ToastEntry({required this.message, required this.type});
}

class _ToastStack extends StatelessWidget {
  final _ToastEntry entry;
  const _ToastStack({required this.entry});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      top: mq.padding.top + 12,
      right: 12,
      left: 12,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _AnimatedToast(entry: entry),
          ),
        ),
      ),
    );
  }
}

class _AnimatedToast extends StatefulWidget {
  final _ToastEntry entry;
  const _AnimatedToast({required this.entry});

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    widget.entry.dismissing.addListener(_onDismiss);
  }

  void _onDismiss() {
    if (widget.entry.dismissing.value) _ctrl.reverse();
  }

  @override
  void dispose() {
    widget.entry.dismissing.removeListener(_onDismiss);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _styleFor(widget.entry.type);
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.entry.message,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, IconData) _styleFor(AppToastType t) {
    switch (t) {
      case AppToastType.success:
        return (const Color(0xFF1E8449), Colors.white, Icons.check_circle);
      case AppToastType.error:
        return (const Color(0xFFC0392B), Colors.white, Icons.error_outline);
      case AppToastType.warning:
        return (const Color(0xFFE8A838), Colors.white, Icons.warning_amber);
      case AppToastType.info:
        return (const Color(0xFF1B4F72), Colors.white, Icons.info_outline);
    }
  }
}
