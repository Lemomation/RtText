import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/services/updater_service.dart';
import 'package:rttext/widgets/app_toast.dart';

/// Shows an update popup asking the user to update now or later.
Future<void> showUpdatePromptDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UpdatePromptDialog(info: info),
  );
}

enum _DialogUpdateState { prompt, downloading, error }

/// Dialog shown on app launch when a newer release is ready on GitHub.
/// Allows the user to choose 'Later' or 'Update now'. When 'Update now'
/// is tapped, it streams the APK with a progress bar and hands it off
/// to the system installer.
class UpdatePromptDialog extends StatefulWidget {
  const UpdatePromptDialog({
    super.key,
    required this.info,
    this.updater,
  });

  final UpdateInfo info;
  final UpdaterService? updater;

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends State<UpdatePromptDialog> {
  late final UpdaterService _updater;
  _DialogUpdateState _state = _DialogUpdateState.prompt;
  int _received = 0;
  int _total = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _updater = widget.updater ?? UpdaterService();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }

  Future<void> _startDownload() async {
    final url = widget.info.downloadUrl;
    if (url == null) return;
    setState(() {
      _state = _DialogUpdateState.downloading;
      _received = 0;
      _total = 0;
      _errorMessage = null;
    });
    try {
      final apk = await _updater.download(
        url,
        onProgress: (received, total) {
          if (!mounted || (received == _received && total == _total)) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      try {
        await _updater.install(apk);
      } catch (_) {
        if (!mounted) return;
        showAppToast(
          context,
          'Install failed — allow installs from this app in system settings',
          style: AppToastStyle.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _DialogUpdateState.error;
        _errorMessage = 'Download failed — please check your connection and try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloading = _state == _DialogUpdateState.downloading;

    return PopScope(
      canPop: !isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
            ).animate().scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: Motion.slow,
                  curve: Motion.springCurve,
                ),
            const SizedBox(height: 16),
            Text(
              'Update available',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A new version of RtText (v${widget.info.latestVersion}) is ready to install.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.info.apkSize != null && widget.info.apkSize! > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Download size: ${_formatBytes(widget.info.apkSize!)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (widget.info.notes != null && widget.info.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.notes!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            if (isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _total > 0 ? _received / _total : null,
                borderRadius: BorderRadius.circular(6),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Text(
                _total > 0
                    ? '${_formatBytes(_received)} / ${_formatBytes(_total)} (${((_received / _total) * 100).toInt()}%)'
                    : 'Downloading update…',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_state == _DialogUpdateState.error && _errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!isDownloading) ...[
            TextButton(
              key: const Key('update-later-button'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              key: const Key('update-now-button'),
              onPressed: _startDownload,
              child: Text(_state == _DialogUpdateState.error ? 'Retry' : 'Update now'),
            ),
          ],
        ],
      ),
    );
  }
}
