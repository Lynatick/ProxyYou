import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hiddify/features/youtube/youtube_playback.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

Future<Map<String, dynamic>?> showWindowsPlayback(BuildContext context, Map<String, dynamic> arguments) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WindowsPlaybackDialog(arguments: arguments),
  );
}

class _WindowsPlaybackDialog extends ConsumerStatefulWidget {
  const _WindowsPlaybackDialog({required this.arguments});
  final Map<String, dynamic> arguments;

  @override
  ConsumerState<_WindowsPlaybackDialog> createState() => _WindowsPlaybackDialogState();
}

class _WindowsPlaybackDialogState extends ConsumerState<_WindowsPlaybackDialog> {
  // WebView2 shares one environment per process. Never reuse an environment
  // with a different proxy: that would invalidate the connection proof.
  static Future<void>? _environment;
  static int? _environmentPort;
  WebviewController? _controller;
  Timer? _pollTimer;
  Timer? _deadline;
  bool _polling = false;
  bool _finished = false;
  String _message = 'Загружаем плеер…';

  @override
  void initState() {
    super.initState();
    _deadline = Timer(const Duration(seconds: 90), () => _finish({'status': 'failed'}));
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final port = widget.arguments['port'] as int;
      if (await WebviewController.getWebViewVersion() == null) {
        _finish({'status': 'unsupported'});
        return;
      }
      if (_environmentPort != null && _environmentPort != port) {
        if (mounted) setState(() => _message = 'Порт прокси изменён. Перезапустите программу для проверки видео.');
        return;
      }
      if (_environment == null) {
        _environmentPort = port;
        _environment = _createEnvironment(port);
      }
      await _environment;
      if (!mounted || _finished) return;
      final controller = WebviewController();
      _controller = controller;
      await controller.initialize();
      if (!mounted || _finished) return;
      await controller.clearCache();
      await controller.setCacheDisabled(true);
      await controller.addScriptToExecuteOnDocumentCreated(
        'window.__proxyyouExpectedId = ${jsonEncode(widget.arguments['videoId'])};',
      );
      await controller.loadUrl('https://www.youtube.com/watch?v=${widget.arguments['videoId']}');
      if (!mounted || _finished) return;
      setState(() => _message = 'Нажмите Play. Для подтверждения нужны 5 секунд видео и 10 новых кадров.');
      _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_poll()));
    } catch (_) {
      _finish({'status': 'failed'});
    }
  }

  static Future<void> _createEnvironment(int port) async {
    final directory = await getApplicationSupportDirectory();
    await WebviewController.initializeEnvironment(
      userDataPath: p.join(directory.path, 'playback-webview'),
      additionalArguments:
          '--proxy-server=http://127.0.0.1:$port --proxy-bypass-list=<-loopback> --disable-quic --lang=ru',
    );
  }

  Future<void> _poll() async {
    if (_polling || _finished || !mounted) return;
    _polling = true;
    try {
      final proof = await _controller?.executeScript(widget.arguments['script'] as String);
      if (proof is Map && (proof['status'] == 'passed' || proof['status'] == 'unsupported')) {
        _finish(Map<String, dynamic>.from(proof));
      }
    } catch (_) {
      // Navigation may temporarily destroy the JavaScript execution context.
    } finally {
      _polling = false;
    }
  }

  void _finish(Map<String, dynamic> result) {
    if (!mounted || _finished) return;
    _finished = true;
    _pollTimer?.cancel();
    _deadline?.cancel();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _finished = true;
    _pollTimer?.cancel();
    _deadline?.cancel();
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(youtubePlaybackProvider, (previous, next) {
      if (next.status != PlaybackStatus.checking) _finish({'status': 'cancelled'});
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish({'status': 'cancelled'});
      },
      child: Dialog(
        child: SizedBox(
          width: 960,
          height: 680,
          child: Column(
            children: [
              ListTile(
                title: const Text('Проверка воспроизведения YouTube'),
                subtitle: Text(_message),
                trailing: IconButton(
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close),
                  onPressed: () => _finish({'status': 'cancelled'}),
                ),
              ),
              Expanded(
                child: _controller?.value.isInitialized == true
                    ? Webview(_controller!)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
