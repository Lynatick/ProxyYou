import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/utils/throttler.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_proxy_notifier.g.dart';

// mainOutboundsInfo returns the selected route from group to actual server.
// Use the leaf's delay rather than a selector/balancer's cached aggregate delay.
OutboundInfo connectedOutbound(List<OutboundGroup> groups) {
  for (final group in groups.reversed) {
    final server = group.items.where((item) => !item.isGroup).firstOrNull;
    if (server != null) return server;
  }
  return groups.firstOrNull?.items.firstOrNull ?? OutboundInfo();
}

// One native stream is shared by the selected server and the routing-mode label.
final activeProxyGroupsProvider = StreamProvider<List<OutboundGroup>>((ref) {
  if (!ref.watch(serviceRunningProvider)) return Stream.value(const []);
  return ref
      .watch(proxyRepositoryProvider)
      .watchActiveProxies()
      .map((event) => event.getOrElse((_) => const <OutboundGroup>[]));
});

String? connectedRoutingMode(List<OutboundGroup> groups) {
  // Read the actual main selection, never a server name containing these words.
  final main = groups.where((group) => group.tag == 'select').firstOrNull;
  if (main == null) return null;
  for (final item in main.items) {
    if (item.isGroup &&
        (item.tag == main.selected || item.isSelected) &&
        (item.tag == 'balance' || item.tag == 'lowest')) {
      return item.tag;
    }
  }
  return null;
}

final activeRoutingModeProvider = Provider<String?>(
  (ref) => connectedRoutingMode(ref.watch(activeProxyGroupsProvider).value ?? const []),
);

@riverpod
class IpInfoNotifier extends _$IpInfoNotifier with AppLogger {
  @override
  Future<oldipinfo.IpInfo> build() async {
    ref.disposeDelay(const Duration(seconds: 20));
    final cancelToken = CancelToken();
    Timer? timer;
    ref.onDispose(() {
      loggy.debug("disposing");
      cancelToken.cancel();
      timer?.cancel();
    });

    ref.listen(serviceRunningProvider, (_, next) => _idle = false);

    final autoCheck = ref.watch(Preferences.autoCheckIp);
    final serviceRunning = ref.watch(serviceRunningProvider);
    // loggy.debug(
    //   "idle? [$_idle], forced? [$_forceCheck], connected? [$serviceRunning]",
    // );
    if (!_forceCheck && !serviceRunning) {
      throw const ServiceNotRunning();
    } else if ((_idle && !_forceCheck) || (!_forceCheck && serviceRunning && !autoCheck)) {
      throw const UnknownIp();
    }

    _forceCheck = false;
    final info = await ref.watch(proxyRepositoryProvider).getCurrentIpInfo(cancelToken).getOrElse((err) {
      loggy.warning("error getting proxy ip info", err, StackTrace.current);
      // throw err; //hiddify: remove exception to be logged
      throw const UnknownIp();
    }).run();

    timer = Timer(const Duration(seconds: 10), () {
      loggy.debug("entering idle mode");
      _idle = true;
      ref.invalidateSelf();
    });

    return info;
  }

  bool _idle = false;
  bool _forceCheck = false;

  Future<void> refresh() async {
    if (state.isLoading) return;
    loggy.debug("refreshing");
    state = const AsyncLoading();
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    _forceCheck = true;
    ref.invalidateSelf();
  }
}

@Riverpod(keepAlive: true)
class ActiveProxyNotifier extends _$ActiveProxyNotifier with AppLogger {
  @override
  Stream<OutboundInfo> build() {
    // ref.disposeDelay(const Duration(seconds: 20));
    final serviceRunning = ref.watch(serviceRunningProvider);
    _wasConnectionValid = false;
    if (!serviceRunning) {
      return Stream.error(const ServiceNotRunning());
    }
    final controller = StreamController<OutboundInfo>();
    ref.onDispose(controller.close);
    ref.listen(activeProxyGroupsProvider, (_, next) {
      next.when(
        data: (groups) {
          final info = connectedOutbound(groups);
          _handleConnectionHaptic(info.urlTestDelay);
          controller.add(info);
        },
        error: controller.addError,
        loading: () {},
      );
    }, fireImmediately: true);
    return controller.stream;
  }

  /// Whether the tunnel currently has a valid ping. Tracked so haptics fire only
  /// on real transitions (connect / timeout / recover), not on every ping update.
  bool _wasConnectionValid = false;

  void _handleConnectionHaptic(int urlTestDelay) {
    final isValid = ConnectionConst.isValidDelay(urlTestDelay);
    if (isValid == _wasConnectionValid) return;
    _wasConnectionValid = isValid;
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (isValid) {
      // connected successfully, or recovered after a timeout
      haptic.heavyImpact();
    } else {
      // still connected but the ping timed out → medium then heavy
      haptic.mediumImpact();
      Future.delayed(const Duration(milliseconds: 150), haptic.heavyImpact);
    }
  }

  final _urlTestThrottler = Throttler(const Duration(seconds: 1));

  Future<void> urlTest(String? groupTag_) async {
    final groupTag = groupTag_ ?? "";
    _urlTestThrottler(() async {
      if (state case AsyncData()) {
        await ref.read(hapticServiceProvider.notifier).lightImpact();
        await ref.read(proxyRepositoryProvider).urlTest(groupTag).getOrElse((err) {
          loggy.warning("error testing group", err);
          throw err;
        }).run();
      }
    });
  }
}
