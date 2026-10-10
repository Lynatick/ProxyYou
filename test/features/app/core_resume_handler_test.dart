import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/app/core_resume_handler.dart';

void main() {
  test('desktop starts once across repeated window focus changes', () async {
    final handler = CoreResumeHandler(isDesktop: true);
    var starts = 0;
    Future<void> initialize() async => starts++;
    for (var i = 0; i < 100; i++) {
      await handler.resume(initialize);
    }
    expect(starts, 1);
  });

  test('desktop shares initialization while the core is still starting', () async {
    final handler = CoreResumeHandler(isDesktop: true);
    final completion = Completer<void>();
    var starts = 0;
    Future<void> initialize() {
      starts++;
      return completion.future;
    }

    final first = handler.resume(initialize);
    final second = handler.resume(initialize);
    expect(starts, 1);
    expect(identical(first, second), isTrue);
    completion.complete();
    await Future.wait([first, second]);
  });

  test('mobile platforms still reinitialize after returning from background', () async {
    final handler = CoreResumeHandler(isDesktop: false);
    var starts = 0;
    Future<void> initialize() async => starts++;
    await handler.resume(initialize);
    await handler.resume(initialize);
    expect(starts, 2);
  });
}
