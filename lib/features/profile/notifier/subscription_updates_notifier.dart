import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/subscription_revision_checker.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final subscriptionProfilesProvider = StreamProvider<List<RemoteProfileEntity>>((ref) async* {
  final repository = await ref.watch(profileRepositoryProvider.future);
  yield* repository.watchAll().map(
    (value) => value.getOrElse((error) => throw error).whereType<RemoteProfileEntity>().toList(),
  );
});

final subscriptionRevisionCheckerProvider = Provider<SubscriptionRevisionChecker>((ref) {
  final client = ref.watch(httpClientProvider);
  final xray = ref.watch(ConfigOptions.useXrayCoreWhenPossible);
  return SubscriptionRevisionChecker(
    client,
    ref.watch(sharedPreferencesProvider).requireValue,
    userAgent: xray ? client.userAgent.replaceAll('HiddifyNext', 'HiddifyNextX') : null,
  );
});

class SubscriptionUpdatesState {
  const SubscriptionUpdatesState({this.available = const {}, this.checking = false});
  final Set<String> available;
  final bool checking;
}

final subscriptionsUpdatingProvider = StateProvider<bool>((ref) => false);
final subscriptionUpdatesProvider = NotifierProvider<SubscriptionUpdatesNotifier, SubscriptionUpdatesState>(
  SubscriptionUpdatesNotifier.new,
);

class SubscriptionUpdatesNotifier extends Notifier<SubscriptionUpdatesState> {
  static const interval = Duration(minutes: 15);
  final _checked = <String, DateTime>{};
  Future<void>? _inFlight;
  bool _disposed = false;
  CancelToken? _cancel;

  @override
  SubscriptionUpdatesState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancel?.cancel();
    });
    ref.listen(subscriptionProfilesProvider, (_, next) {
      if (next.hasValue) {
        scheduleMicrotask(() {
          if (!_disposed) unawaited(check());
        });
      }
    }, fireImmediately: true);
    return const SubscriptionUpdatesState();
  }

  Future<void> check() {
    if (_disposed) return Future.value();
    if (_inFlight case final pending?) return pending;
    return _inFlight = _check().whenComplete(() => _inFlight = null);
  }

  Future<void> _check() async {
    final profiles = ref.read(subscriptionProfilesProvider).valueOrNull;
    if (profiles == null) return;
    final checker = ref.read(subscriptionRevisionCheckerProvider);
    final available = <String>{
      for (final profile in profiles)
        if (checker.cached(profile)?.available ?? state.available.contains(profile.id)) profile.id,
    };
    state = SubscriptionUpdatesState(available: Set.unmodifiable(available), checking: true);
    _cancel = CancelToken();
    try {
      // Sequential disk/network work prevents bursts for many subscriptions;
      // no native core calls and no copies of large contents on the UI isolate.
      for (final profile in profiles) {
        if (_disposed) return;
        final key = '${profile.id}\n${profile.url}';
        final last = _checked[key];
        if (last != null && DateTime.now().difference(last) < interval) continue;
        try {
          final revision = await checker.check(profile, _cancel!);
          if (_disposed) return;
          final current = ref
              .read(subscriptionProfilesProvider)
              .valueOrNull
              ?.where((p) => p.id == profile.id)
              .firstOrNull;
          if (current == null || current.url != profile.url) continue;
          // A manual update may finish while this HTTP request is pending.
          final isAvailable = appliedSubscriptionHash(current) != revision.observed && revision.available;
          if (isAvailable) {
            available.add(profile.id);
          } else {
            available.remove(profile.id);
          }
        } catch (_) {
          // Network errors preserve known updates and never manufacture one.
        } finally {
          _checked[key] = DateTime.now();
        }
      }
    } finally {
      if (!_disposed) {
        final current = ref.read(subscriptionProfilesProvider).valueOrNull ?? const <RemoteProfileEntity>[];
        final ids = current.map((p) => p.id).toSet();
        available.removeWhere((id) => !ids.contains(id));
        for (final profile in current) {
          final revision = checker.cached(profile);
          if (revision != null && !revision.available) available.remove(profile.id);
        }
        state = SubscriptionUpdatesState(available: Set.unmodifiable(available));
      }
    }
  }
}
