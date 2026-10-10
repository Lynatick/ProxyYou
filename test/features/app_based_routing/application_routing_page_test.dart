import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_based_routing/application_routing_page.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdleConnection extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Disconnected());
}

void main() {
  Future<SharedPreferences> render(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences)),
        connectionNotifierProvider.overrideWith(IdleConnection.new),
        macApplicationsProvider.overrideWith(
          (ref) => Future.value([
            {'name': 'Chrome', 'path': '/Applications/Chrome.app', 'supported': true},
            {'name': 'Firefox', 'path': '/Applications/Firefox.app', 'supported': true},
            {'name': 'Safari', 'path': '/Applications/Safari.app', 'supported': false},
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ApplicationRoutingPage()),
      ),
    );
    await tester.pumpAndSettle();
    return preferences;
  }

  testWidgets('selection is saved only when Apply is pressed and survives reopening', (tester) async {
    final preferences = await render(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chrome'));
    await tester.pumpAndSettle();
    expect(preferences.getString('mac-app-routing-bundles'), isNull);
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(preferences.getBool('mac-app-routing-enabled'), isTrue);
    expect(preferences.getString('mac-app-routing-bundles'), '/Applications/Chrome.app');
    final root = tester.widget<UncontrolledProviderScope>(find.byType(UncontrolledProviderScope));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(root);
    await tester.pumpAndSettle();
    final checkbox = tester.widget<CheckboxListTile>(
      find.ancestor(of: find.text('Chrome'), matching: find.byType(CheckboxListTile)),
    );
    expect(checkbox.value, isTrue);
    expect(preferences.getString('mac-app-routing-bundles'), '/Applications/Chrome.app');
  }, skip: !Platform.isMacOS);

  testWidgets('empty inclusion is rejected and search finds only matching programs', (tester) async {
    final preferences = await render(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(find.text('Выберите хотя бы одну программу.'), findsOneWidget);
    expect(preferences.getBool('mac-app-routing-enabled'), isNull);
    await tester.enterText(find.byType(TextField), 'fire');
    await tester.pumpAndSettle();
    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Chrome'), findsNothing);
  }, skip: !Platform.isMacOS);
}
