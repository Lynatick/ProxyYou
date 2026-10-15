param([string]$Version = '4.1.21', [string]$BuildNumber = '40121', [switch]$SkipTests, [switch]$InstallerOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..')
if ($env:OS -ne 'Windows_NT') { throw 'Требуется Windows с Visual Studio C++ Build Tools.' }
$flutterVersion = (& flutter --version | Out-String)
$requiredFlutterMatch = Select-String -Path pubspec.yaml -Pattern '^  flutter:\s*\^?(\d+\.\d+\.\d+)\s*$'
if (!$requiredFlutterMatch) { throw 'Версия Flutter не найдена в pubspec.yaml.' }
$requiredFlutter = $requiredFlutterMatch.Matches[0].Groups[1].Value
if ($LASTEXITCODE -ne 0 -or $flutterVersion -notmatch ('Flutter ' + [regex]::Escape($requiredFlutter) + ' ')) { throw "Требуется Flutter $requiredFlutter." }
foreach ($file in @('hiddify-core.dll','libcronet.dll','HiddifyCli.exe')) {
  if (!(Test-Path "hiddify-core/windows-x64/$file")) { throw "Отсутствует Windows-ядро: $file. См. WINDOWS.md." }
}
$ErrorActionPreference = 'Continue' # Native stderr can contain ordinary build diagnostics.
& flutter pub get
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw 'Ошибка загрузки Flutter-зависимостей.' }
& dart run slang
if ($LASTEXITCODE -ne 0) { throw 'Ошибка генерации переводов.' }
& dart run build_runner build
if ($LASTEXITCODE -ne 0) { throw 'Ошибка генерации Dart-кода.' }
if (!$SkipTests) {
  $ErrorActionPreference = 'Continue'
  & flutter test --no-pub --reporter expanded --concurrency 1
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw 'Автоматические тесты не пройдены.' }
}
$dartRuntime = (& dart --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $dartRuntime -notmatch 'windows_x64') { throw 'Windows x64 build requires an x64 Flutter/Dart SDK.' }
$ErrorActionPreference = 'Continue'
& flutter build windows --release --target lib/main.dart --build-name $Version --build-number $BuildNumber
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw 'Ошибка сборки Windows x64.' }
& "$PSScriptRoot/package_windows.ps1" -Version $Version -InstallerOnly:$InstallerOnly
