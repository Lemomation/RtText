import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/core/app_theme.dart';
import 'package:rttext/widgets/bead_icon.dart';

/// In-app toast: a floating card that drops in from the top with the shared
/// spring motion and auto-dismisses. Replaces the default Material SnackBar,
/// which read as generic Android chrome.
enum AppToastStyle { error, success, info }

/// Shows [message] as a floating toast. Safe to call from anywhere with a
/// context; the toast lives in the root overlay outlives the caller.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastStyle style = AppToastStyle.info,
  String? actionLabel,
  VoidCallback? onAction,
  Widget? leading,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _ToastView(
      message: message,
      style: style,
      leading: leading,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: remove,
    ),
  );
  overlay.insert(entry);
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.style,
    required this.onDismiss,
    this.leading,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppToastStyle style;
  final VoidCallback onDismiss;
  final Widget? leading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  bool _leaving = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 3600), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _leaving) return;
    setState(() => _leaving = true);
    // Let the exit animation play before the overlay entry is removed.
    Timer(const Duration(milliseconds: 280), widget.onDismiss);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, tint) = switch (widget.style) {
      AppToastStyle.error => (
          const Icon(Icons.error_outline_rounded, size: 20),
          theme.colorScheme.error,
        ),
      AppToastStyle.success => (
          const Icon(Icons.check_rounded, size: 20),
          theme.colorScheme.primary,
        ),
      AppToastStyle.info => (const BeadIcon(size: 22), null),
    };

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: AnimatedSlide(
        offset: _leaving ? const Offset(0, -1.4) : Offset.zero,
        duration: _leaving ? Motion.standard : Motion.emphasized,
        curve: _leaving ? Motion.emphasizedCurve.flipped : Motion.springCurve,
        child: AnimatedOpacity(
          opacity: _leaving ? 0 : 1,
          duration: Motion.standard,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (widget.leading != null)
                      widget.leading!
                    else
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: (tint ?? theme.colorScheme.primary)
                            .withValues(alpha: 0.16),
                        child: IconTheme.merge(
                          data: IconThemeData(
                              color: tint ?? theme.colorScheme.primary,
                              size: 20),
                          child: icon,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (widget.actionLabel != null)
                      TextButton(
                        onPressed: () {
                          _dismiss();
                          widget.onAction?.call();
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        child: Text(widget.actionLabel!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
