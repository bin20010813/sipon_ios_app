[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stageRoot = Join-Path $projectRoot 'build/harmony_workspace'
$cacheRoot = Join-Path $projectRoot 'build/harmony_plugin_cache'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$plugins = Get-Content -LiteralPath (Join-Path $projectRoot 'ohos/flutter/plugins.lock.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath (Join-Path $stageRoot 'pubspec.yaml'))) {
    throw 'Run build_harmony.ps1 -PrepareOnly first.'
}

function Invoke-PluginGit {
    param([string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Plugin source fetch failed (git $($Arguments[0]))." }
}

# Fetch only each pinned revision and package subtree. Pub's normal Git mirror
# downloads the entire multi-plugin repository and all of its history.
foreach ($group in ($plugins | Group-Object revision)) {
    $revision = $group.Name
    if ($revision -notmatch '^[a-f0-9]{40}$') { throw 'Invalid plugin revision in lock file.' }
    $checkout = Join-Path $cacheRoot $revision
    $marker = Join-Path $checkout '.sipon-plugin-revision'
    if (-not (Test-Path -LiteralPath $marker)) {
        $plugin = $group.Group[0]
        Write-Output "Fetching HarmonyOS plugin sources: $($plugin.repo) $($plugin.tag)"
        New-Item -ItemType Directory -Path $checkout -Force | Out-Null
        Invoke-PluginGit -Arguments @('init', '--quiet', $checkout)
        Invoke-PluginGit -Arguments @('-C', $checkout, 'config', 'remote.origin.url', "https://gitcode.com/CPF-Flutter/$($plugin.repo).git")
        Invoke-PluginGit -Arguments @('-C', $checkout, 'config', 'remote.origin.promisor', 'true')
        Invoke-PluginGit -Arguments @('-C', $checkout, 'config', 'remote.origin.partialclonefilter', 'blob:none')
        Invoke-PluginGit -Arguments @('-C', $checkout, 'fetch', '--depth=1', '--filter=blob:none', 'origin', $revision)
        Invoke-PluginGit -Arguments @('-C', $checkout, 'sparse-checkout', 'init', '--cone')
        $sparseArgs = @('-C', $checkout, 'sparse-checkout', 'set') + @($group.Group | ForEach-Object { $_.path })
        Invoke-PluginGit -Arguments $sparseArgs
        Invoke-PluginGit -Arguments @('-C', $checkout, 'checkout', '--quiet', '--detach', $revision)
        $actualRevision = & git -C $checkout rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $actualRevision.Trim() -ne $revision) { throw 'Plugin commit verification failed.' }
        [IO.File]::WriteAllText($marker, $revision, $utf8)
    }
    foreach ($plugin in $group.Group) {
        $destination = Join-Path $stageRoot ".harmony_plugins/$($plugin.name)"
        & robocopy (Join-Path $checkout $plugin.path) $destination /E /NFL /NDL /NJH /NJS /NP `
            /XD .git .dart_tool build example test | Out-Null
        if ($LASTEXITCODE -gt 7) { throw "Failed to copy plugin $($plugin.name)." }
        $packageManifest = Join-Path $destination 'pubspec.yaml'
        $packageText = [IO.File]::ReadAllText($packageManifest)
        # These packages are standalone dependencies of the app, outside their
        # upstream monorepo's Dart workspace.
        $packageText = [Text.RegularExpressions.Regex]::Replace($packageText, '(?m)^resolution: workspace\r?\n', '')
        [IO.File]::WriteAllText($packageManifest, $packageText, $utf8)
    }
}

foreach ($filename in @('pubspec.yaml', 'pubspec_overrides.yaml')) {
    $manifestPath = Join-Path $stageRoot $filename
    $manifest = [IO.File]::ReadAllText($manifestPath)
    foreach ($plugin in $plugins) {
        $name = [Text.RegularExpressions.Regex]::Escape($plugin.name)
        $pattern = "(?m)^  ${name}:\r?\n    git:\r?\n      url:[^\r\n]+\r?\n      ref:[^\r\n]+\r?\n      path:[^\r\n]+(?:\r?\n|$)"
        $manifest = [Text.RegularExpressions.Regex]::Replace($manifest, $pattern,
            "  $($plugin.name):`n    path: .harmony_plugins/$($plugin.name)`n")
    }
    [IO.File]::WriteAllText($manifestPath, $manifest, $utf8)
}
Write-Output 'Pinned HarmonyOS plugin sources are ready.'
