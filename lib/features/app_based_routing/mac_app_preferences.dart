import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hooks_riverpod/legacy.dart';

final macDiagnosticPortProvider = StateProvider<int?>((ref) => null);

abstract class MacAppPreferences {
  static final enabled = PreferencesNotifier.create<bool, bool>('mac-app-routing-enabled', false);
  static final mode = PreferencesNotifier.create<String, String>(
    'mac-app-routing-mode',
    'include',
    validator: (value) => value == 'include' || value == 'exclude',
  );
  static final bundles = PreferencesNotifier.create<List<String>, List<String>>('mac-app-routing-bundles', []);
}
