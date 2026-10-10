import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in local copies: no downloaded server addresses are stored in the source tree.
void main() {
  final fixtureDirectory = Platform.environment['PROXYYOU_SUBSCRIPTION_TEST_DIRECTORY'];
  for (final name in ['subscription-load-test.json', 'subscription-all-load-test.json']) {
    test('actual subscription download, import and sorting: $name', () async {
      final input = File('$fixtureDirectory/$name');
      final temporary = await Directory.systemTemp.createTemp('proxyyou-public-sub-');
      addTearDown(() => temporary.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences))],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final parserProvider = Provider(
        (ref) => ProfileParser(
          ref: ref,
          httpClient: DioHttpClient(
            timeout: const Duration(seconds: 60),
            userAgent: 'ProxyYou subscription performance test',
            debug: false,
          ),
        ),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.contentLength = await input.length();
        await request.response.addStream(input.openRead());
        await request.response.close();
      });
      var ticks = 0;
      var previous = 0;
      var longestGap = 0;
      final watch = Stopwatch()..start();
      final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = watch.elapsedMilliseconds;
        final gap = now - previous;
        if (gap > longestGap) longestGap = gap;
        previous = now;
        ticks++;
      });
      addTearDown(heartbeat.cancel);
      final imported = await container
          .read(parserProvider)
          .addRemote(
            id: name,
            url: 'http://127.0.0.1:${server.port}/$name',
            tempFilePath: '${temporary.path}/download.json',
            userOverride: null,
          )
          .run();
      final duration = watch.elapsedMilliseconds;
      heartbeat.cancel();
      expect(imported.isRight(), true);
      expect(ticks, greaterThan(0));
      // Structured JSON must remain byte-for-byte intact after URL expansion.
      expect(await File('${temporary.path}/download.json').length(), await input.length());
      final group = await readActualGroup(input.path);
      final sorted = await sortOutboundGroup(group, ProxiesSort.delay);
      expect(sorted!.items.length, group.items.length);
      expect(sorted.items.first.isGroup, true);
      expect(group.items.length, greaterThan(30000));
      debugPrint(
        '$name: ${await input.length()} bytes, ${group.items.length} outbounds; '
        'download + import $duration ms, heartbeat $ticks ticks, longest gap $longestGap ms',
      );
    }, skip: fixtureDirectory == null);
  }
}

Future<OutboundGroup> readActualGroup(String path) => Isolate.run(() {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return OutboundGroup(
    tag: 'select',
    items: [
      for (final item in (json['outbounds'] as List).cast<Map<String, dynamic>>())
        OutboundInfo(
          tag: item['tag'] as String? ?? '',
          isGroup: item['type'] == 'selector' || item['type'] == 'urltest',
        ),
    ],
  );
});
