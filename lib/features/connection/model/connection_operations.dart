import 'dart:async';

/// Start, reconnect and stop must not apply conflicting network changes.
class ConnectionOperationQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

/// Restore network preferences before stopping the listener. Concurrent stop
/// requests share work; a failed or timed-out attempt remains retryable.
class MacDisconnectController {
  Future<void>? _pending;

  Future<void> run({
    required Future<void> Function() restoreProxy,
    required Future<void> Function() stopCore,
    Duration restoreTimeout = const Duration(seconds: 17),
    Duration stopTimeout = const Duration(seconds: 10),
  }) => _pending ??= (() async {
    await restoreProxy().timeout(restoreTimeout);
    await stopCore().timeout(stopTimeout);
  })().whenComplete(() => _pending = null);
}
