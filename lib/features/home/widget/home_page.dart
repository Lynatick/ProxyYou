import 'package:flutter/material.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/app_based_routing/application_routing_page.dart';
import 'package:hiddify/features/home/widget/connection_controls.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/tv/tv_mode.dart';
import 'package:hiddify/features/youtube/youtube_card.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final isTv = ref.watch(televisionProvider).valueOrNull ?? false;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ProxyYou'),
        actions: [
          if (PlatformUtils.isMacOS || PlatformUtils.isAndroid)
            IconButton(
              tooltip: 'Проксирование программ',
              icon: const Icon(Icons.apps),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ApplicationRoutingPage())),
            ),
          IconButton(
            tooltip: 'Добавить подписку',
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Обновить подписки',
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Настройки соединения',
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings(),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTv ? 900 : 720),
          child: ListView(
            padding: EdgeInsets.all(
              isTv
                  ? 32
                  : MediaQuery.sizeOf(context).width < 480
                  ? 12
                  : 20,
            ),
            children: [
              if (profile != null) ProfileTile(profile: profile, isMain: true),
              if (profile != null) const SizedBox(height: 16),
              const ConnectionControls(),
              const SizedBox(height: 12),
              const ActiveProxyFooter(),
              const SizedBox(height: 12),
              const YoutubeCard(),
              const SizedBox(height: 20),
              Text(
                'На основе открытого проекта Hiddify • локальная версия для тестирования',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
