import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/youtube/youtube_card.dart';
import 'package:hiddify/features/youtube/youtube_playback.dart';
import 'package:hiddify/features/youtube/youtube_probe.dart';
import 'package:hiddify/features/youtube/youtube_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('missing thumbnail is distinguished from a failed network check', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final report = YoutubeReport([
      const ProbeResult(label: 'YouTube', outcome: ProbeOutcome.reachable, elapsed: Duration(milliseconds: 50)),
      const ProbeResult(
        label: 'Миниатюры',
        outcome: ProbeOutcome.rejected,
        elapsed: Duration(milliseconds: 70),
        statusCode: 404,
        isThumbnail: true,
      ),
    ]);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences)),
      serviceRunningProvider.overrideWithValue(true),
      youtubeReportProvider.overrideWith((ref) => Future.value(report)),
      youtubePlaybackProvider.overrideWith((ref) => YoutubePlaybackController(port: 12334, enabled: false)),
    ]);
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: YoutubeCard()))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Тестовая миниатюра недоступна'), findsOneWidget);
    expect(find.text('Миниатюры: тестовая миниатюра не найдена (HTTP 404)'), findsOneWidget);
    expect(find.text('YouTube: 50 мс'), findsOneWidget);
    expect(find.text('Предварительная проверка сети не пройдена'), findsNothing);
    expect(find.textContaining('Воспроизведение подтверждено'), findsNothing);
  });
}
