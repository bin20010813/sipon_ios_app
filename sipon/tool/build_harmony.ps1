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
& (Join-Path $PSScriptRoot 'check_harmony_resources.ps1')

if (-not $PrepareOnly) {
    if ([string]::IsNullOrWhiteSpace($FlutterSdk)) {
        throw 'Set FLUTTER_OHOS_HOME or pass -FlutterSdk pointing to Flutter OH 3.41.10-ohos-1.0.1.'
    }
    $flutterCommand = Join-Path $FlutterSdk 'bin/flutter.bat'
    $toolPaths = @((Join-Path $FlutterSdk 'bin'))
    if ($env:NODE_HOME) { $toolPaths += $env:NODE_HOME }
    if ($env:JAVA_HOME) { $toolPaths += (Join-Path $env:JAVA_HOME 'bin') }
    if ($env:DEVECO_SDK_HOME) {
        $commandLineBin = Join-Path (Split-Path $env:DEVECO_SDK_HOME -Parent) 'bin'
        if (Test-Path -LiteralPath $commandLineBin) { $toolPaths += $commandLineBin }
    }
    $env:Path = ($toolPaths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:Path
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
foreach ($directory in @('lib', 'assets', 'assest', 'ohos', 'test', 'tool/tests')) {
    $source = Join-Path $projectRoot $directory
    if (-not (Test-Path -LiteralPath $source)) { continue }
    & robocopy $source (Join-Path $stageRoot $directory) /E /NFL /NDL /NJH /NJS /NP `
        /XD build oh_modules .hvigor .dart_tool signing /XF local.properties | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Failed to copy $directory (robocopy $LASTEXITCODE)." }
}
# Relative signing paths in build-profile.json5 must exist in the generated
# project as well. These files remain under ignored build/ and ohos/signing/.
$signingSource = Join-Path $projectRoot 'ohos/signing'
if (Test-Path -LiteralPath $signingSource) {
    & robocopy $signingSource (Join-Path $stageRoot 'ohos/signing') /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw 'Failed to stage HarmonyOS signing files.' }
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
    & $flutterCommand test --no-pub tool/tests/harmony_map_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS map regression tests failed.' }
    & node --test tool/tests/harmony_sticker_test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS native sticker regression tests failed.' }
    & node --test tool/tests/petal_marker_layout_test.cjs tool/tests/petal_marker_artwork_test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS marker regression tests failed.' }
    $buildStarted = Get-Date
    & $flutterCommand build hap "--$Mode" --target ohos/flutter/main.dart 2>&1 | Tee-Object -Variable hapOutput
    if ($LASTEXITCODE -ne 0) {
        # Flutter OH asks for IDE signing even after Hvigor successfully creates
        # an unsigned HAP. This project signs separately with the official tool.
        $unsigned = Join-Path $stageRoot 'ohos/entry/build/default/outputs/default/entry-default-unsigned.hap'
        if (-not ($hapOutput -match 'Signing Configs') -or
            -not (Test-Path -LiteralPath $unsigned) -or
            (Get-Item -LiteralPath $unsigned).LastWriteTime -lt $buildStarted) {
            throw 'HAP build failed. See the compiler output above.'
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($unsigned)
        try {
            foreach ($entry in @('module.json', 'ets/modules.abc', 'libs/arm64-v8a/libapp.so', 'libs/arm64-v8a/libflutter.so')) {
                if (-not $archive.GetEntry($entry)) { throw "Incomplete unsigned HAP: missing $entry" }
            }
        } finally { $archive.Dispose() }
        Write-Output "Unsigned HAP ready: $unsigned"
        Write-Output 'For release signing, double-click tool/Sign-Harmony-Release.cmd.'
    }
} finally {
    Pop-Location
}
