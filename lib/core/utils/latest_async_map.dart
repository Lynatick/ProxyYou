import 'dart:async';

/// Process one snapshot at a time, retaining only the newest waiting snapshot.
/// Unlike asyncMap, the source keeps draining while expensive work is running.
Stream<R> latestAsyncMap<T, R>(Stream<T> source, Future<R> Function(T) convert, {Duration interval = Duration.zero}) {
  late StreamController<R> controller;
  StreamSubscription<T>? subscription;
  T? pending;
  bool hasPending = false;
  bool running = false;
  bool ended = false;
  bool cancelled = false;

  Future<void> drain() async {
    if (running || cancelled) return;
    running = true;
    while (hasPending && !cancelled) {
      final value = pending as T;
      pending = null;
      hasPending = false;
      try {
        final result = await convert(value);
        if (!cancelled) controller.add(result);
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
      }
      if (!ended && !cancelled && interval > Duration.zero) {
        await Future<void>.delayed(interval);
      }
    }
    running = false;
    if (ended && !cancelled) await controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subscription = source.listen(
        (value) {
          pending = value;
          hasPending = true;
          unawaited(drain());
        },
        onError: controller.addError,
        onDone: () {
          ended = true;
          if (!running) unawaited(controller.close());
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      cancelled = true;
      pending = null;
      hasPending = false;
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
