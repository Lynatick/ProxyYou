import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'haptic_service.g.dart';

@Riverpod(keepAlive: true)
class HapticService extends _$HapticService with AppLogger {
  @override
  bool build() {
    return _preferences.getBool(hapticFeedbackPrefKey) ?? true;
  }

  static const String hapticFeedbackPrefKey = "haptic_feedback";
  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  Future<void> updatePreference(bool value) async {
    state = value;
    await _preferences.setBool(hapticFeedbackPrefKey, value);
  }

  Future<void> lightImpact() => _impact(HapticFeedback.lightImpact);

  Future<void> mediumImpact() => _impact(HapticFeedback.mediumImpact);

  Future<void> heavyImpact() => _impact(HapticFeedback.heavyImpact);

  Future<void> _impact(Future<void> Function() feedback) async {
    if (!state || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    // Feedback is optional. Native replies must never gate connection actions.
    unawaited(
      feedback().timeout(const Duration(milliseconds: 500)).catchError((Object error) {
        loggy.debug('haptic feedback unavailable: $error');
      }),
    );
  }
}
