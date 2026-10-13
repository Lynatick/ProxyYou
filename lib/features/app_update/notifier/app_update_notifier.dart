import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/app_update/data/app_update_data_providers.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

part 'app_update_notifier.g.dart';

@riverpod
Upgrader upgrader(Ref ref) => Upgrader(
  storeController: UpgraderStoreController(
    onAndroid: () => ref.read(appInfoProvider).requireValue.release.allowCustomUpdateChecker
        ? UpgraderAppcastStore(appcastURL: Constants.appCastUrl)
        : UpgraderPlayStore(),
    oniOS: () => UpgraderAppStore(),
    onLinux: () => UpgraderAppcastStore(appcastURL: Constants.appCastUrl),
    onWindows: () => UpgraderAppcastStore(appcastURL: Constants.appCastUrl),
    onMacOS: () => UpgraderAppcastStore(appcastURL: Constants.appCastUrl),
    onWeb: () => UpgraderAppcastStore(appcastURL: Constants.appCastUrl),
  ),
  messages: UpgraderMessages(code: ref.watch(localePreferencesProvider).languageCode),
);

@Riverpod(keepAlive: true)
class AppUpdateNotifier extends _$AppUpdateNotifier with AppLogger {
  Future<AppUpdateState>? _inFlight;
  DateTime? _lastCheck;
  bool _disposed = false;
  static const checkInterval = Duration(hours: 6);
  static const retryInterval = Duration(minutes: 15);

  @override
  AppUpdateState build() {
    ref.onDispose(() => _disposed = true);
    return const AppUpdateState.initial();
  }

  PreferencesEntry<String?, dynamic> get _ignoreReleasePref => PreferencesEntry(
    preferences: ref.read(sharedPreferencesProvider).requireValue,
    key: 'ignored_release_version',
    defaultValue: null,
  );

  /// Focus changes share one request and reuse its result. Checking never
  /// restarts the proxy core or downloads/installs an application package.
  Future<AppUpdateState> check({bool force = false}) {
    if (_inFlight case final running?) return running;
    final interval = state is AppUpdateStateError ? retryInterval : checkInterval;
    if (!force && _lastCheck != null && DateTime.now().difference(_lastCheck!) < interval) {
      return Future.value(state);
    }
    final request = _check();
    _inFlight = request;
    return request.whenComplete(() {
      _lastCheck = DateTime.now();
      _inFlight = null;
    });
  }

  Future<AppUpdateState> _check() async {
    if (!Constants.allowUpdateNotifications) return state = const AppUpdateState.disabled();
    // Keep an existing banner visible while a later check is in progress.
    if (state is! AppUpdateStateAvailable && state is! AppUpdateStateIgnored) {
      state = const AppUpdateState.checking();
    }
    try {
      final appInfo = await ref.read(appInfoProvider.future);
      if (_disposed) return const AppUpdateState.disabled();
      final result = await ref.read(appUpdateRepositoryProvider).getLatestVersion().run();
      if (_disposed) return const AppUpdateState.disabled();
      return result.match(
        (error) {
          loggy.warning('failed to check application version', error);
          if (state is AppUpdateStateAvailable || state is AppUpdateStateIgnored) return state;
          return state = AppUpdateState.error(error);
        },
        (remote) {
          if (Version.parse(remote.version) > Version.parse(appInfo.version)) {
            return state = AppUpdateState.available(remote);
          }
          return state = const AppUpdateState.notAvailable();
        },
      );
    } catch (error, stackTrace) {
      if (_disposed) return const AppUpdateState.disabled();
      loggy.warning('failed to check application version', error, stackTrace);
      if (state is AppUpdateStateAvailable || state is AppUpdateStateIgnored) return state;
      return state = AppUpdateState.error(AppUpdateFailure.unexpected(error, stackTrace));
    }
  }

  Future<void> ignoreRelease(RemoteVersionEntity version) async {
    await _ignoreReleasePref.write(version.version);
    state = AppUpdateStateIgnored(version);
  }
}
