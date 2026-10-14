import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/subscription_fingerprint.dart';
import 'package:hiddify/features/profile/data/subscription_revision_checker.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/subscription_updates_notifier.dart';
import 'package:hiddify/features/profile/widget/subscription_update_button.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const original = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const changed = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class TestChecker implements SubscriptionRevisionChecker {
  final pending = Completer<SubscriptionRevision>();
  SubscriptionRevision? snapshot;
  int calls = 0;
  @override
  SubscriptionRevision? cached(RemoteProfileEntity profile) => snapshot == null
      ? null
      : SubscriptionRevision(
          baseline: appliedSubscriptionHash(profile) ?? snapshot!.baseline,
          observed: snapshot!.observed,
        );
  @override
  Future<SubscriptionRevision> check(RemoteProfileEntity profile, CancelToken cancelToken) async {
    calls++;
    return snapshot = await pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class KnownUpdates extends SubscriptionUpdatesNotifier {
  @override
  SubscriptionUpdatesState build() => const SubscriptionUpdatesState(available: {'one'});
}

void main() {
  final profile =
      ProfileEntity.remote(
            id: 'one',
            active: true,
            name: 'Подписка',
            url: 'https://example.com/sub',
            lastUpdate: DateTime(2026),
            populatedHeaders: {subscriptionSourceHash: original},
          )
          as RemoteProfileEntity;

  test('concurrent focus checks share a request, applied revision clears badge immediately', () async {
    final profiles = StreamController<List<RemoteProfileEntity>>();
    final checker = TestChecker();
    final container = ProviderContainer(
      overrides: [
        subscriptionProfilesProvider.overrideWith((ref) => profiles.stream),
        subscriptionRevisionCheckerProvider.overrideWithValue(checker),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(profiles.close);
    container.listen(subscriptionUpdatesProvider, (_, _) {});
    profiles.add([profile]);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(subscriptionUpdatesProvider.notifier);
    final first = notifier.check();
    final second = notifier.check();
    expect(identical(first, second), isTrue);
    expect(checker.calls, 1);
    checker.pending.complete(const SubscriptionRevision(baseline: original, observed: changed));
    await first;
    expect(container.read(subscriptionUpdatesProvider).available, {'one'});
    await notifier.check();
    expect(checker.calls, 1);
    profiles.add([
      profile.copyWith(populatedHeaders: {subscriptionSourceHash: changed}),
    ]);
    await Future<void>.delayed(Duration.zero);
    await notifier.check();
    expect(container.read(subscriptionUpdatesProvider).available, isEmpty);
    expect(checker.calls, 1);
    profiles.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(subscriptionUpdatesProvider).available, isEmpty);
  });

  testWidgets('global refresh button displays the count of changed subscriptions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProfilesProvider.overrideWith((ref) => Stream.value([profile])),
          subscriptionUpdatesProvider.overrideWith(KnownUpdates.new),
        ],
        child: const MaterialApp(home: Scaffold(body: SubscriptionUpdateButton())),
      ),
    );
    await tester.pump();
    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Есть изменения в подписках: 1. Обновить'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);
  });
}
