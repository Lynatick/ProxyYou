import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tv/tv_navigation.dart';

void main() {
  testWidgets('remote arrows move the visible ring and OK activates the focused button', (tester) async {
    var activated = '';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvNavigation(child: child!),
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(autofocus: true, onPressed: () => activated = 'first', child: const Text('Первый')),
                const SizedBox(width: 24),
                OutlinedButton(onPressed: () => activated = 'second', child: const Text('Второй')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ring = find.byKey(const ValueKey('tv-focus-ring'));
    expect(ring, findsOneWidget);
    final first = tester.getRect(ring);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getRect(ring).left, greaterThan(first.left));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(activated, 'second');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activated, 'first');
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus follows dialog controls and returns after closing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvNavigation(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                autofocus: true,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Подписка'),
                    actions: [
                      TextButton(
                        autofocus: true,
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Подписка'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-focus-ring')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Подписка'), findsNothing);
    expect(find.byKey(const ValueKey('tv-focus-ring')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('moving down scrolls the focused control into view', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvNavigation(child: child!),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 180,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: List.generate(
                    12,
                    (index) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: FilledButton(autofocus: index == 0, onPressed: () {}, child: Text('Сервер $index')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(scroll.offset, greaterThan(0));
    expect(find.byKey(const ValueKey('tv-focus-ring')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
