import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrayConnection extends ConnectionNotifier {
  TrayConnection(this.updates);
  final Stream<ConnectionStatus> updates;
  @override
  Stream<ConnectionStatus> build() => updates;
}

class TrayProxy extends ActiveProxyNotifier {
  TrayProxy(this.updates);
  final Stream<OutboundInfo> updates;
  @override
  Stream<OutboundInfo> build() => updates;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late StreamController<ConnectionStatus> connection;
  late StreamController<OutboundInfo> proxy;
  late List<MethodCall> calls;
  Future<void> Function(MethodCall)? intercept;

  Future<void> flush() async {
    await container.pump();
    await container.read(systemTrayNotifierProvider.future);
    await container.pump();
  }

  List<MethodCall> icons() => calls.where((call) => call.method == 'setIcon').toList();
  bool isTemplate(MethodCall call) => (call.arguments as Map)['isTemplate'] as bool;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls = [];
    intercept = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (call) async {
      calls.add(call);
      await intercept?.call(call);
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final translations = await AppLocale.ru.build();
    connection = StreamController<ConnectionStatus>.broadcast();
    proxy = StreamController<OutboundInfo>.broadcast();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences)),
        translationsProvider.overrideWith((ref) => Future.value(translations)),
        connectionNotifierProvider.overrideWith(() => TrayConnection(connection.stream)),
        activeProxyNotifierProvider.overrideWith(() => TrayProxy(proxy.stream)),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    container.listen(systemTrayNotifierProvider, (_, _) {});
    await flush();
  });

  tearDown(() async {
    container.dispose();
    await connection.close();
    await proxy.close();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('connected icon preserves its color while the ping stream has no value', () async {
    connection.add(const Connected());
    await flush();
    expect(isTemplate(icons().last), isFalse);
    final menu = calls.lastWhere((call) => call.method == 'setContextMenu').arguments.toString();
    expect(menu, contains((await AppLocale.ru.build()).connection.disconnect));
    proxy.add(OutboundInfo(urlTestDelay: 65000));
    await flush();
    expect(isTemplate(icons().last), isFalse);
  }, skip: !Platform.isMacOS);

  test('ping changes update the tooltip without replacing the connected icon', () async {
    connection.add(const Connected());
    await flush();
    final count = icons().length;
    proxy.add(OutboundInfo(urlTestDelay: 25));
    await flush();
    expect(icons(), hasLength(count));
    expect(calls.lastWhere((call) => call.method == 'setToolTip').arguments.toString(), contains('25 мс'));
  }, skip: !Platform.isMacOS);

  test('disconnect waits for a delayed native icon update and finishes with the neutral icon', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    intercept = (call) async {
      if (call.method == 'setIcon' && !isTemplate(call)) {
        entered.complete();
        await release.future;
      }
    };
    connection.add(const Connected());
    await entered.future;
    connection.add(const Disconnected());
    await container.pump();
    release.complete();
    await flush();
    expect(isTemplate(icons().last), isTrue);
  }, skip: !Platform.isMacOS);

  test('a connection stream error clears the previous connected icon', () async {
    connection.add(const Connected());
    await flush();
    connection.addError(StateError('core unavailable'));
    await flush();
    expect(isTemplate(icons().last), isTrue);
  }, skip: !Platform.isMacOS);
}
