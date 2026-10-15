import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> preferences(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final saved = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(saved))],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    return container;
  }

  test('new installations use a conservative TUN MTU and five-minute checks', () async {
    final container = await preferences({});
    expect(container.read(ConfigOptions.mtu), 1400);
    expect(container.read(ConfigOptions.urlTestInterval), const Duration(minutes: 5));
    expect(container.read(ConfigOptions.connectionTestUrl), 'https://www.youtube.com/generate_204');
  });

  test('saved MTU and monitoring interval remain user-controlled', () async {
    final container = await preferences({'mtu': 1420, 'url-test-interval': 900});
    expect(container.read(ConfigOptions.mtu), 1420);
    expect(container.read(ConfigOptions.urlTestInterval), const Duration(minutes: 15));
  });
}
