import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('only Russian is used even when another language was saved', () async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences))],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    expect(container.read(localePreferencesProvider), AppLocale.ru);
    await container.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en);
    expect(container.read(localePreferencesProvider), AppLocale.ru);
    expect(preferences.getString('locale'), 'ru');
    final translation = await container.read(translationsProvider.future);
    expect(translation.pages.settings.general.title, 'Общие');
  });
}
