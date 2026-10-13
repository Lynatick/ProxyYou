param([string]$Version = '4.1.19', [string]$BuildNumber = '40119', [switch]$SkipTests, [switch]$InstallerOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..')
if ($env:OS -ne 'Windows_NT') { throw 'Требуется Windows с Visual Studio C++ Build Tools.' }
$flutterVersion = (& flutter --version | Out-String)
if ($LASTEXITCODE -ne 0 -or $flutterVersion -notmatch 'Flutter 3\.38\.5 ') { throw 'Требуется Flutter 3.38.5.' }
foreach ($file in @('hiddify-core.dll','libcronet.dll','HiddifyCli.exe')) {
  if (!(Test-Path "hiddify-core/windows-x64/$file")) { throw "Отсутствует Windows-ядро: $file. См. WINDOWS.md." }
}
$ErrorActionPreference = 'Continue' # Native stderr can contain ordinary build diagnostics.
& flutter pub get
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw 'Ошибка загрузки Flutter-зависимостей.' }
if (!$SkipTests) {
  $ErrorActionPreference = 'Continue'
  & flutter test --no-pub --reporter expanded --concurrency 1
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw 'Автоматические тесты не пройдены.' }
}
$ErrorActionPreference = 'Continue'
& flutter build windows --release --target lib/main.dart --build-name $Version --build-number $BuildNumber
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw 'Ошибка сборки Windows x64.' }
& "$PSScriptRoot/package_windows.ps1" -Version $Version -InstallerOnly:$InstallerOnly
