[CmdletBinding()]
param(
    [string]$FlutterSdk = $env:FLUTTER_OHOS_HOME,
    [ValidateSet('debug', 'profile', 'release')][string]$Mode = 'debug',
    [switch]$PrepareOnly,
    [switch]$ResolvePlugins
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stageRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build/harmony_workspace'))
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $PrepareOnly) {
    if ([string]::IsNullOrWhiteSpace($FlutterSdk)) {
        throw 'Set FLUTTER_OHOS_HOME or pass -FlutterSdk pointing to Flutter OH 3.41.10-ohos-1.0.1.'
    }
    $flutterCommand = Join-Path $FlutterSdk 'bin/flutter.bat'
    $platformSource = Join-Path $FlutterSdk 'packages/flutter/lib/src/foundation/platform.dart'
    if (-not (Test-Path -LiteralPath $flutterCommand) -or
        -not (Test-Path -LiteralPath $platformSource) -or
        -not (Select-String -LiteralPath $platformSource -Pattern '\bohos\b' -Quiet)) {
        throw 'This Flutter SDK has no HarmonyOS support. Use the Flutter OH SDK.'
    }
}

# Recreate only this generated workspace. Validate the absolute target before deletion.
if (-not $stageRoot.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Generated workspace escaped the project directory.'
}
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
foreach ($directory in @('lib', 'assets', 'assest', 'ohos', 'test')) {
    $source = Join-Path $projectRoot $directory
    if (-not (Test-Path -LiteralPath $source)) { continue }
    & robocopy $source (Join-Path $stageRoot $directory) /E /NFL /NDL /NJH /NJS /NP `
        /XD build oh_modules .hvigor .dart_tool signing /XF local.properties | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Failed to copy $directory (robocopy $LASTEXITCODE)." }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'analysis_options.yaml') -Destination $stageRoot
$analysisOptions = [IO.File]::ReadAllText((Join-Path $stageRoot 'analysis_options.yaml'))
$analysisOptions = [Text.RegularExpressions.Regex]::Replace($analysisOptions, '(?m)^\s*- ohos/\*\*\r?\n', '')
[IO.File]::WriteAllText((Join-Path $stageRoot 'analysis_options.yaml'), $analysisOptions, $utf8)
$manifest = [IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml'))
$dependencies = [IO.File]::ReadAllText((Join-Path $projectRoot 'ohos/flutter/dependencies.yaml'))
$pattern = New-Object Text.RegularExpressions.Regex('(?m)^dependencies:\s*\r?\n')
if ($pattern.Matches($manifest).Count -ne 1) { throw 'Expected one dependencies section in pubspec.yaml.' }
$manifest = $pattern.Replace($manifest, [Text.RegularExpressions.MatchEvaluator]{
    param($match)
    return "dependencies:`n" + $dependencies.TrimEnd() + "`n"
}, 1)
[IO.File]::WriteAllText((Join-Path $stageRoot 'pubspec.yaml'), $manifest, $utf8)
Copy-Item -LiteralPath (Join-Path $projectRoot 'ohos/flutter/pubspec_overrides.yaml') `
    -Destination (Join-Path $stageRoot 'pubspec_overrides.yaml')

Write-Output "HarmonyOS workspace: $stageRoot"
if ($ResolvePlugins -or -not $PrepareOnly) {
    & (Join-Path $PSScriptRoot 'prepare_harmony_plugins.ps1')
}
if ($PrepareOnly) { return }

Push-Location $stageRoot
try {
    & $flutterCommand pub get
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS dependency resolution failed.' }
    & $flutterCommand analyze --no-pub --no-fatal-warnings --no-fatal-infos lib ohos/flutter/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS Dart analysis failed.' }
    & $flutterCommand build hap "--$Mode" --target ohos/flutter/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'HAP build failed. Check the HarmonyOS SDK and signing configuration.' }
} finally {
    Pop-Location
}
