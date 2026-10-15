import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_operations.dart';

void main() {
  test('stop waits until start has finished applying network preferences', () async {
    final queue = ConnectionOperationQueue();
    final start = Completer<void>();
    final events = <String>[];
    final first = queue.run(() async {
      events.add('start');
      await start.future;
      events.add('proxy-enabled');
    });
    final second = queue.run(() async => events.add('proxy-restored'));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['start']);
    start.complete();
    await Future.wait([first, second]);
    expect(events, ['start', 'proxy-enabled', 'proxy-restored']);
  });

  test('failed operations do not block later stop requests', () async {
    final queue = ConnectionOperationQueue();
    await expectLater(queue.run<void>(() async => throw StateError('failed')), throwsStateError);
    expect(await queue.run(() async => 42), 42);
  });

  test('concurrent disconnects share restore and stop in the correct order', () async {
    final controller = MacDisconnectController();
    final restored = Completer<void>();
    final events = <String>[];
    Future<void> restore() async {
      events.add('restore');
      await restored.future;
    }

    Future<void> stop() async => events.add('stop');
    final a = controller.run(restoreProxy: restore, stopCore: stop);
    final b = controller.run(restoreProxy: restore, stopCore: stop);
    expect(identical(a, b), isTrue);
    expect(events, ['restore']);
    restored.complete();
    await Future.wait([a, b]);
    expect(events, ['restore', 'stop']);
  });

  test('restore failure keeps listener alive and a later stop can retry', () async {
    final controller = MacDisconnectController();
    var stops = 0;
    await expectLater(
      controller.run(restoreProxy: () async => throw StateError('busy'), stopCore: () async => stops++),
      throwsStateError,
    );
    expect(stops, 0);
    await controller.run(restoreProxy: () async {}, stopCore: () async => stops++);
    expect(stops, 1);
  });

  test('unresponsive stop times out and does not lock out the next attempt', () async {
    final controller = MacDisconnectController();
    await expectLater(
      controller.run(
        restoreProxy: () async {},
        stopCore: () => Completer<void>().future,
        stopTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await controller.run(restoreProxy: () async {}, stopCore: () async {});
  });

  test('late restoration after timeout cannot unexpectedly stop the core', () async {
    final controller = MacDisconnectController();
    final restored = Completer<void>();
    var stopped = false;
    await expectLater(
      controller.run(
        restoreProxy: () => restored.future,
        stopCore: () async => stopped = true,
        restoreTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    restored.complete();
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
  });

  test('core failure is not reported as a successful disconnect', () async {
    await expectLater(
      MacDisconnectController().run(restoreProxy: () async {}, stopCore: () async => throw StateError('stop failed')),
      throwsStateError,
    );
  });
}
