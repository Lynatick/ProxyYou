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
case "$platform" in
  android) native_file="android/app/libs/hiddify-core.aar" ;;
  macos) native_file="hiddify-core/bin/hiddify-core.dylib" ;;
esac
if [[ -n "${PROXYYOU_CORE_SOURCE:-}" ]]; then
  bash "scripts/build-${platform}-core.sh" "$PROXYYOU_CORE_SOURCE"
fi
[[ -f "$native_file" ]] || { echo "Сначала соберите ядро через scripts/build-$platform-core.sh." >&2; exit 1; }
python3 scripts/native-core-stamp.py verify "$native_file"

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
