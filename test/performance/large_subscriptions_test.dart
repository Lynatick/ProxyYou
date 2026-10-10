import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/utils/latest_async_map.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/core_interface/responsive_core_client.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';

class SyntheticCore extends CoreServiceBase {
  @override
  Future<ParseResponse> parse(ServiceCall call, ParseRequest request) async => ParseResponse(
    responseCode: request.debug ? ResponseCode.FAILED : ResponseCode.OK,
    message: request.debug ? 'synthetic-invalid' : '',
    content: 'x' * (20 * 1024 * 1024),
  );
  @override
  Stream<OutboundGroupList> outboundsInfo(ServiceCall call, Empty request) async* {
    yield OutboundGroupList(
      items: [
        OutboundGroup(
          tag: 'select',
          selected: 'server-42',
          items: [for (var i = 0; i < 10000; i++) OutboundInfo(tag: 'server-$i')],
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('raw outbound RPC matches the core protocol over an actual local channel', () async {
    final server = Server.create(services: [SyntheticCore()]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
    final channel = ClientChannel(
      '127.0.0.1',
      port: server.port!,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    addTearDown(() async {
      await channel.shutdown();
      await server.shutdown();
    });
    final bytes = await ResponsiveCoreClient(channel).rawOutbounds().first.timeout(const Duration(seconds: 5));
    final group = (await decodeOutboundSnapshot(bytes))!;
    expect(group.selected, 'server-42');
    expect(group.items, hasLength(10000));
  });

  test('validation RPC decodes a large result off UI and retains errors without returning content', () async {
    final server = Server.create(services: [SyntheticCore()]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
    final channel = ClientChannel(
      '127.0.0.1',
      port: server.port!,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    addTearDown(() async {
      await channel.shutdown();
      await server.shutdown();
    });
    final core = ResponsiveCoreClient(channel);
    final valid = await core.parseForValidation(ParseRequest());
    expect(valid.responseCode, ResponseCode.OK);
    expect(valid.content, isEmpty);
    final invalid = await core.parseForValidation(ParseRequest(debug: true));
    expect(invalid.responseCode, ResponseCode.FAILED);
    expect(invalid.message, 'synthetic-invalid');
    expect(invalid.content, isEmpty);
  });

  test('burst retains only newest snapshot while work runs', () async {
    final source = StreamController<int>();
    final gate = Completer<void>();
    final calls = <int>[];
    final results = latestAsyncMap(source.stream, (value) async {
      calls.add(value);
      if (value == 0) await gate.future;
      return value;
    }).toList();
    source.add(0);
    await Future<void>.delayed(Duration.zero);
    for (var i = 1; i <= 10000; i++) {
      source.add(i);
    }
    await source.close();
    gate.complete();
    expect(await results, [0, 10000]);
    expect(calls, [0, 10000]);
  });

  test('cancellation stops pending work and cancels upstream', () async {
    final source = StreamController<int>();
    final gate = Completer<void>();
    final calls = <int>[];
    final subscription = latestAsyncMap(source.stream, (value) async {
      calls.add(value);
      await gate.future;
      return value;
    }).listen((_) => fail('result after cancellation'));
    source.add(1);
    await Future<void>.delayed(Duration.zero);
    source.add(2);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    gate.complete();
    await source.close();
    expect(calls, [1]);
  });

  test('conversion error does not discard newest update', () async {
    final source = StreamController<int>();
    final gate = Completer<void>();
    final received = <int>[];
    final errors = <Object>[];
    final finished = Completer<void>();
    latestAsyncMap(source.stream, (value) async {
      if (value == 1) {
        await gate.future;
        throw StateError('synthetic');
      }
      return value;
    }).listen(received.add, onError: errors.add, onDone: finished.complete);
    source.add(1);
    await Future<void>.delayed(Duration.zero);
    source.add(2);
    await source.close();
    gate.complete();
    await finished.future;
    expect(errors, hasLength(1));
    expect(received, [2]);
  });

  test('50000 servers sort correctly without blocking UI heartbeat or mutating input', () async {
    final group = OutboundGroup(
      tag: 'select',
      selected: 'server-42',
      items: [
        OutboundInfo(tag: 'balancer', isGroup: true),
        for (var i = 49999; i >= 0; i--)
          OutboundInfo(tag: 'server-${i.toString().padLeft(5, '0')}', urlTestDelay: i % 400),
      ],
    );
    var ticks = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
    final watch = Stopwatch()..start();
    final sorted = (await sortOutboundGroup(group, ProxiesSort.delay))!;
    heartbeat.cancel();
    debugPrint('50000 servers: ${watch.elapsedMilliseconds} ms, UI heartbeat $ticks ticks');
    expect(ticks, greaterThan(0));
    expect(sorted.items, hasLength(50001));
    expect(sorted.selected, group.selected);
    expect(sorted.items.first.isGroup, true);
    expect(sorted.items[1].urlTestDelay, 1);
    expect(sorted.items.last.urlTestDelay, 0);
    expect(group.items[1].tag, 'server-49999');
    final names = (await sortOutboundGroup(group, ProxiesSort.name))!;
    expect(names.items[1].tag, 'server-00000');
    final usage = (await sortOutboundGroup(
      OutboundGroup(
        items: [
          OutboundInfo(tag: 'small', upload: Int64(2), download: Int64(3)),
          OutboundInfo(tag: 'large', upload: Int64(100), download: Int64(200)),
        ],
      ),
      ProxiesSort.usage,
    ))!;
    expect(usage.items.first.tag, 'large');
  });

  test('raw core snapshots decode on a worker and preserve group metadata', () async {
    final bytes = OutboundGroupList(
      items: [
        OutboundGroup(
          tag: 'select',
          selected: 'server',
          selectable: true,
          items: [for (var i = 0; i < 10000; i++) OutboundInfo(tag: 'server-$i', urlTestDelay: i)],
        ),
        OutboundGroup(tag: 'secondary'),
      ],
    ).writeToBuffer();
    final group = (await decodeOutboundSnapshot(bytes))!;
    expect(group.tag, 'select');
    expect(group.selected, 'server');
    expect(group.selectable, true);
    expect(group.items, hasLength(10000));
    expect(await decodeOutboundSnapshot(OutboundGroupList().writeToBuffer()), isNull);
  });

  test('50000 subscription links and base64 headers parse off UI isolate', () async {
    final directory = await Directory.systemTemp.createTemp('proxyyou-large-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/subscription.txt');
    final content =
        '#profile-title: Large subscription\n${List.generate(50000, (i) => 'vless://synthetic-$i@example.invalid:443#server-$i').join('\n')}';
    await file.writeAsString(base64.encode(utf8.encode(content)));
    var ticks = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
    final watch = Stopwatch()..start();
    final result = await ProfileParser.parseFileAsync(
      tempFilePath: file.path,
      profile: ProfileEntity.remote(
        id: 'synthetic',
        active: true,
        name: '',
        url: 'https://example.invalid/subscription',
        lastUpdate: DateTime.now(),
      ),
    ).run();
    heartbeat.cancel();
    debugPrint('50000 links: ${watch.elapsedMilliseconds} ms, UI heartbeat $ticks ticks');
    expect(ticks, greaterThan(0));
    expect(result.getOrElse((error) => throw error).name, 'Large subscription');
    await file.writeAsString(content);
    expect(await readSubscriptionLines(file.path), hasLength(50001));
    final local = await ProfileParser.parseFileAsync(
      tempFilePath: file.path,
      profile: ProfileEntity.local(id: 'local', active: true, name: '', lastUpdate: DateTime.now()),
      refreshHeaders: false,
    ).run();
    expect(local.getOrElse((error) => throw error).name, 'server-0');
  });
}
