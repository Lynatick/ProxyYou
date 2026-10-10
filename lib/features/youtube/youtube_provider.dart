import 'package:hiddify/features/app_based_routing/mac_app_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/youtube/youtube_probe.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Watching the outbound tag, rather than latency, prevents probe loops on each ping.
final youtubeReportProvider = FutureProvider.autoDispose<YoutubeReport?>((ref) {
  final running = ref.watch(serviceRunningProvider);
  ref.watch(activeProfileProvider.select((profile) => profile.valueOrNull?.id));
  ref.watch(activeProxyNotifierProvider.select((proxy) => proxy.valueOrNull?.tag));
  final mixedPort = ref.watch(ConfigOptions.mixedPort);
  final port = ref.watch(macDiagnosticPortProvider) ?? mixedPort;
  final enabled = ref.watch(ConfigOptions.enableMixedPort);
  // A status transition invalidates results even if a reconnect uses the same profile.
  ref.watch(connectionNotifierProvider);
  if (!running || !enabled) return null;
  final probe = YoutubeProbe(proxyPort: port);
  ref.onDispose(probe.close);
  return probe.check();
});
