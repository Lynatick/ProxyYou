import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/router/dialog/widgets/new_version_dialog.dart';
import 'package:hiddify/features/app_update/data/app_update_data_providers.dart';
import 'package:hiddify/features/app_update/data/app_update_repository.dart';
import 'package:hiddify/features/app_update/data/github_release_parser.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/features/app_update/widget/app_update_card.dart';
import 'package:hiddify/features/tv/tv_navigation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class RecordingLauncher extends UrlLauncherPlatform {
  String? launchedUrl;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) => Future.value(true);
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    launchedUrl = url;
    return Future.value(true);
  }
}

RemoteVersionEntity version(String value) => RemoteVersionEntity(
  version: value,
  buildNumber: '',
  releaseTag: 'v$value',
  preRelease: false,
  url: 'https://github.com/lynatick/proxyyou/releases/tag/v$value',
  publishedAt: DateTime(2026),
  flavor: Environment.prod,
);
Map<String, dynamic> release(String value, {String platform = 'Android', String suffix = 'apk'}) => {
  'tag_name': 'v$value',
  'prerelease': false,
  'draft': false,
  'published_at': '2026-10-13T10:00:00Z',
  'html_url': 'https://github.com/lynatick/proxyyou/releases/tag/v$value',
  'assets': [
    {'name': 'ProxyYou-$platform-$value.$suffix', 'size': 100},
  ],
};

class TestAppInfo extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => const AppInfoEntity(
    name: 'ProxyYou',
    version: '4.1.19',
    buildNumber: '40119',
    release: Release.general,
    operatingSystem: 'android',
    operatingSystemVersion: '16',
    environment: Environment.prod,
  );
}

class TestRepository implements AppUpdateRepository {
  int calls = 0;
  Future<Either<AppUpdateFailure, RemoteVersionEntity>> Function() response = () async => Right(version('4.1.20'));
  @override
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  }) => TaskEither(() {
    calls++;
    return response();
  });
}

class TestUpdate extends AppUpdateNotifier {
  TestUpdate(this.initial);
  final AppUpdateState initial;
  @override
  AppUpdateState build() => initial;
}

void main() {
  test('selection skips drafts, prereleases, broken records, foreign links, missing packages and backports', () {
    final entries = [
      release('4.1.18'),
      {'tag_name': 'broken'},
      {...release('4.1.25'), 'prerelease': true},
      {...release('4.1.26'), 'draft': true},
      {...release('4.1.27'), 'html_url': 'https://example.com/update'},
      release('4.1.28', platform: 'iOS', suffix: 'ipa'),
      release('4.1.21'),
      release('4.1.20'),
    ];
    expect(GithubReleaseParser.latest(entries, operatingSystem: 'android')?.version, '4.1.21');
    expect(GithubReleaseParser.latest(entries, operatingSystem: 'ios')?.version, '4.1.28');
    expect(GithubReleaseParser.latest(entries, operatingSystem: 'windows'), isNull);
  });
  test('macOS checks offer a package matching the running architecture', () {
    final arm = release('4.1.20', platform: 'macOS-AppleSilicon', suffix: 'zip');
    final intel = release('4.1.21', platform: 'macOS-Intel', suffix: 'zip');
    expect(GithubReleaseParser.latest([intel, arm], operatingSystem: 'macos')?.version, '4.1.20');
    expect(GithubReleaseParser.latest([intel, arm], operatingSystem: 'macos', macOSIntel: true)?.version, '4.1.21');
    expect(GithubReleaseParser.latest([arm], operatingSystem: 'macos', macOSIntel: true), isNull);
  });
  test('concurrent focus events share a request; normal checks reuse cache; manual check refreshes', () async {
    final repo = TestRepository();
    final pending = Completer<Either<AppUpdateFailure, RemoteVersionEntity>>();
    repo.response = () => pending.future;
    final container = ProviderContainer(
      overrides: [appInfoProvider.overrideWith(TestAppInfo.new), appUpdateRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(appUpdateNotifierProvider.notifier);
    final first = notifier.check();
    final second = notifier.check();
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, 1);
    pending.complete(Right(version('4.1.20')));
    await Future.wait([first, second]);
    expect(container.read(appUpdateNotifierProvider), isA<AppUpdateStateAvailable>());
    await notifier.check();
    expect(repo.calls, 1);
    repo.response = () async => Right(version('4.1.21'));
    await notifier.check(force: true);
    expect(repo.calls, 2);
    expect((container.read(appUpdateNotifierProvider) as AppUpdateStateAvailable).versionInfo.version, '4.1.21');
    repo.response = () async => const Left(AppUpdateFailure.unexpected());
    await notifier.check(force: true);
    expect((container.read(appUpdateNotifierProvider) as AppUpdateStateAvailable).versionInfo.version, '4.1.21');
  });
  test('equal and older versions do not show an update; offline startup is nonfatal', () async {
    final repo = TestRepository();
    final container = ProviderContainer(
      overrides: [appInfoProvider.overrideWith(TestAppInfo.new), appUpdateRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(appUpdateNotifierProvider.notifier);
    for (final v in ['4.1.19', '4.1.18']) {
      repo.response = () async => Right(version(v));
      expect(await notifier.check(force: true), isA<AppUpdateStateNotAvailable>());
    }
    repo.response = () async => throw StateError('offline');
    expect(await notifier.check(force: true), isA<AppUpdateStateError>());
  });
  testWidgets('Russian banner fits narrow screen and remains focusable on TV', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateNotifierProvider.overrideWith(() => TestUpdate(AppUpdateState.available(version('4.1.20')))),
        ],
        child: MaterialApp(
          builder: (context, child) => TvNavigation(child: child!),
          home: const Scaffold(body: AppUpdateCard()),
        ),
      ),
    );
    expect(find.text('Доступна новая версия'), findsOneWidget);
    expect(find.text('ProxyYou 4.1.20'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is FilledButton), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-focus-ring')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('update actions open the download website on ${platform.name}', (tester) async {
      final launcher = RecordingLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      final translations = (await tester.runAsync(() => AppLocale.ru.build()))!;
      final info = version('4.1.20');
      final surfaces = <Widget>[const AppUpdateCard(), NewVersionDialog('4.1.19', info, canIgnore: false)];
      for (final surface in surfaces) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(surface.runtimeType),
            overrides: [
              appUpdateNotifierProvider.overrideWith(() => TestUpdate(AppUpdateState.available(info))),
              translationsProvider.overrideWithValue(AsyncData(translations)),
            ],
            child: MaterialApp(home: Scaffold(body: surface)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(surface is AppUpdateCard ? 'Скачать обновление' : translations.dialogs.newVersion.updateNow),
        );
        await tester.pumpAndSettle();
        expect(launcher.launchedUrl, Constants.downloadPageUrl);
        expect(launcher.launchedUrl, 'https://lynatick.github.io/proxyyou/');
        launcher.launchedUrl = null;
      }
    }, variant: TargetPlatformVariant({platform}));
  }
  testWidgets('no banner is shown for unavailable or failed checks', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateNotifierProvider.overrideWith(
            () => TestUpdate(const AppUpdateState.error(AppUpdateFailure.unexpected())),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AppUpdateCard())),
      ),
    );
    expect(find.text('Доступна новая версия'), findsNothing);
    expect(find.byWidgetPredicate((widget) => widget is FilledButton), findsNothing);
  });
}
