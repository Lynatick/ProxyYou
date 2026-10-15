import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TestRules extends RulesNotifier {
  TestRules(this.destination);
  final File destination;

  @override
  List<Rule> build() {
    file = destination;
    return [for (var i = 0; i < 3; i++) Rule(name: '$i', listOrder: i)];
  }
}

void main() {
  for (final move in [
    (0, 2, ['1', '2', '0']),
    (2, 0, ['2', '0', '1']),
    (1, 1, ['0', '1', '2']),
  ]) {
    test('onReorderItem ${move.$1} -> ${move.$2} persists the adjusted destination', () async {
      final directory = await Directory.systemTemp.createTemp('proxyyou-rules-test-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/route_rule.proto');
      final container = ProviderContainer(overrides: [rulesNotifierProvider.overrideWith(() => TestRules(file))]);
      addTearDown(container.dispose);
      container.listen(rulesNotifierProvider, (_, _) {});
      await container.read(rulesNotifierProvider.notifier).reorder(move.$1, move.$2);
      expect(container.read(rulesNotifierProvider).map((rule) => rule.name), move.$3);
      final saved = RouteRule.fromBuffer(await file.readAsBytes()).rules;
      expect(saved.map((rule) => rule.name), move.$3);
      expect(saved.map((rule) => rule.listOrder), [0, 1, 2]);
    });
  }
}
