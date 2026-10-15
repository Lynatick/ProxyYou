#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-}"
case "$platform" in
  android) archive="hiddify-lib-android.tar.gz"; destination="android/app/libs" ;;
  macos)
    if ! xcodebuild -version >/dev/null 2>&1; then
      echo "Для сборки macOS установите полный Xcode и выберите его как активный набор инструментов." >&2
      exit 1
    fi
    archive="hiddify-lib-macos.tar.gz"; destination="hiddify-core/bin" ;;
  *) echo "Usage: scripts/build-proxyyou.sh android|macos" >&2; exit 2 ;;
esac
required_flutter="$(sed -n '/environment:/,/flutter:/ s/.*flutter:[[:space:]]*//p' pubspec.yaml | tr -d " '^\"")"
command -v flutter >/dev/null || { echo "Требуется Flutter ${required_flutter} в PATH." >&2; exit 1; }
flutter_version="$(flutter --version)"
[[ "$flutter_version" == *"Flutter ${required_flutter} "* ]] || { echo "Требуется Flutter ${required_flutter}." >&2; exit 1; }
core_version="$(sed -n 's/^core.version=//p' dependencies.properties)"
mkdir -p "$destination" .build-cache
curl --fail --location --retry 3 \
  "https://github.com/hiddify/hiddify-core/releases/download/v${core_version}/${archive}" \
  --output ".build-cache/${archive}"
expected="$(awk -v name="$archive" '$2 == name {print $1}' scripts/core-checksums.txt)"
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum ".build-cache/${archive}" | awk '{print $1}')"
else
  actual="$(shasum -a 256 ".build-cache/${archive}" | awk '{print $1}')"
fi
[[ -n "$expected" && "$actual" == "$expected" ]] || { echo "Неверная контрольная сумма ${archive}." >&2; exit 1; }
tar -xzf ".build-cache/${archive}" -C "$destination"
flutter pub get
dart run slang
dart run build_runner build
scripts/generate-test-certificates.sh
flutter test test/features/youtube
node --test test/playback/proof.test.cjs
case "$platform" in
  android) flutter build apk --release --target lib/main.dart ;;
  macos) FLUTTER_XCODE_ARCHS="$(uname -m)" flutter build macos --release --target lib/main.dart ;;
esac
