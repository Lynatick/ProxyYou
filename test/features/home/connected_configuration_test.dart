import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  test('mode comes only from the selected automatic group', () {
    for (final mode in ['balance', 'lowest']) {
      expect(
        connectedRoutingMode([
          OutboundGroup(
            tag: 'select',
            selected: mode,
            items: [OutboundInfo(tag: mode, isGroup: true)],
          ),
        ]),
        mode,
      );
    }
    expect(
      connectedRoutingMode([
        OutboundGroup(
          tag: 'select',
          selected: 'server-lowest',
          items: [OutboundInfo(tag: 'server-lowest')],
        ),
      ]),
      isNull,
    );
    expect(
      connectedRoutingMode([
        OutboundGroup(
          tag: 'select',
          selected: 'balance',
          items: [OutboundInfo(tag: 'balance')],
        ),
      ]),
      isNull,
    );
    expect(connectedRoutingMode([]), isNull);
  });
  testWidgets('connected card shows mode above name with no IP details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectedConfigurationButton(name: 'Сервер', protocol: 'VLESS', mode: 'lowest', onPressed: () {}),
        ),
      ),
    );
    expect(find.text('lowest'), findsOneWidget);
    expect(tester.getTopLeft(find.text('lowest')).dy, lessThan(tester.getTopLeft(find.text('Сервер')).dy));
    expect(find.textContaining('IP'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectedConfigurationButton(name: 'Другой сервер', protocol: 'VLESS', onPressed: () {}),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('connected-routing-mode')), findsNothing);
  });
}
