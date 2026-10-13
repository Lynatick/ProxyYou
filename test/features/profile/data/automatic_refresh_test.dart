import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);
  RemoteProfileEntity profile({UserOverride? override, Duration interval = const Duration(hours: 6)}) =>
      ProfileEntity.remote(
            id: 'p',
            active: true,
            name: 'Подписка',
            url: 'https://example.com/',
            lastUpdate: now.subtract(const Duration(days: 1)),
            userOverride: override,
            options: ProfileOptions(updateInterval: interval),
          )
          as RemoteProfileEntity;
  test('default is disabled; explicit saved choice survives serialization', () {
    expect(const UserOverride().isAutoUpdateDisable, isTrue);
    expect(UserOverride.fromStr('{"version":2,"isAutoUpdateDisable":false}')!.isAutoUpdateDisable, isFalse);
    expect(UserOverride.fromStr('{"version":2}')!.isAutoUpdateDisable, isTrue);
  });
  test('header interval cannot enable refresh implicitly; explicit opt-in enables it', () {
    for (final o in [null, const UserOverride(), const UserOverride(isAutoUpdateDisable: false)]) {
      final parsed = ProfileParser.parse(
        tempFilePath: '',
        profile: profile(
          override: o,
        ).copyWith(populatedHeaders: {'profile-title': 'Подписка', 'profile-update-interval': '6'}),
      );
      parsed.match((err) => fail('$err'), (entity) {
        final rp = entity as RemoteProfileEntity;
        expect(rp.options?.updateInterval, o?.isAutoUpdateDisable == false ? const Duration(hours: 6) : null);
      });
    }
  });
  test('automatic worker respects disable flag and rejects zero intervals; manual refresh still works', () {
    expect(profileUpdateDue(profile(), now), isFalse);
    expect(profileUpdateDue(profile(override: const UserOverride()), now), isFalse);
    expect(profileUpdateDue(profile(override: const UserOverride(isAutoUpdateDisable: false)), now), isTrue);
    expect(
      profileUpdateDue(profile(override: const UserOverride(isAutoUpdateDisable: false), interval: Duration.zero), now),
      isFalse,
    );
    expect(profileUpdateDue(profile(), now, force: true), isTrue);
    expect(
      profileUpdateDue(
        profile(override: const UserOverride(isAutoUpdateDisable: false)).copyWith(lastUpdate: now),
        now,
      ),
      isFalse,
    );
  });
}
