[CmdletBinding()]
param([string]$HapPath, [switch]$CheckOnly, [switch]$ValidatePackage)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$keyDir = Join-Path $projectRoot 'ohos/signing'
$buildRoot = Join-Path $projectRoot 'build/harmony_workspace'
$passwordEnvironment = 'SIPON_HAP_SIGN_PASSWORD'
$previousPassword = [Environment]::GetEnvironmentVariable($passwordEnvironment, 'Process')

try {
    if (-not $env:JAVA_HOME -or -not $env:DEVECO_SDK_HOME) {
        throw 'JAVA_HOME and DEVECO_SDK_HOME must point to your JDK and HarmonyOS SDK.'
    }
    $java = Join-Path $env:JAVA_HOME 'bin/java.exe'
    $signTool = Join-Path $env:DEVECO_SDK_HOME 'default/openharmony/toolchains/lib/hap-sign-tool.jar'
    $keyFile = Join-Path $keyDir 'sipon-release.p12'
    foreach ($required in @($java, $signTool, $keyFile)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing file: $required" }
    }
    $certificates = @(Get-ChildItem -LiteralPath $keyDir -File -Filter '*.cer')
    $profiles = @(Get-ChildItem -LiteralPath $keyDir -File -Filter '*.p7b')
    if ($certificates.Count -ne 1 -or $profiles.Count -ne 1) {
        throw 'Keep exactly one release .cer and one .p7b in ohos/signing so the signing files are unambiguous.'
    }
    Add-Type -AssemblyName System.Security
    $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
    $cms.Decode([IO.File]::ReadAllBytes($profiles[0].FullName))
    $profile = [Text.Encoding]::UTF8.GetString($cms.ContentInfo.Content) | ConvertFrom-Json
    $app = Get-Content -LiteralPath (Join-Path $projectRoot 'ohos/AppScope/app.json5') -Raw | ConvertFrom-Json
    if ($profile.type -ne 'release' -or $profile.'bundle-info'.'bundle-name' -ne $app.app.bundleName) {
        throw 'The Profile must be a release Profile for the project bundle name.'
    }
    if (-not $profile.'app-services-capabilities'.PSObject.Properties['com.huawei.service.mapkit']) {
        throw 'The Profile does not include Map Kit. Enable Map Kit and download a new Profile.'
    }
    if ($CheckOnly) {
        Write-Host "PASS: release Profile for $($app.app.bundleName) includes Map Kit. Signing tools and files are present."
        exit 0
    }
    if (-not $HapPath) {
        $hap = Get-ChildItem -Path (Join-Path $buildRoot 'ohos/entry/build/*/outputs/*/*unsigned.hap') -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $hap) { throw 'No unsigned HAP found. Run build_harmony.ps1 -Mode release first.' }
        $HapPath = $hap.FullName
    }
    if (-not (Test-Path -LiteralPath $HapPath)) { throw "HAP not found: $HapPath" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($HapPath)
    try {
        $moduleEntry = $archive.GetEntry('module.json')
        if (-not $moduleEntry) { throw 'HAP module.json is missing.' }
        $reader = New-Object IO.StreamReader($moduleEntry.Open())
        try { $module = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ($module.app.bundleName -ne $app.app.bundleName -or $module.app.debug -ne $false) {
            throw 'The HAP must be a Release build with the registered bundle name.'
        }
    } finally { $archive.Dispose() }
    if ($ValidatePackage) {
        Write-Host "PASS: Release HAP and signing prerequisites: $HapPath"
        exit 0
    }
    $outputDir = Join-Path $projectRoot 'build/harmony_release'
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $output = Join-Path $outputDir ('sipon-release-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-signed.hap')
    . (Join-Path $PSScriptRoot 'harmony_password_dialog.ps1')
    $password = Read-KeyPassword -NewKeystore $false
    [Environment]::SetEnvironmentVariable($passwordEnvironment, $password, 'Process')
    $password = $null
    & $java --class-path $signTool (Join-Path $PSScriptRoot 'SiponHapSigner.java') `
        sign-app -mode localSign -keyAlias sipon_release -appCertFile $certificates[0].FullName `
        -profileFile $profiles[0].FullName -inFile $HapPath -signAlg SHA256withECDSA `
        -keystoreFile $keyFile -outFile $output -compatibleVersion 20 -signCode 1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
        throw 'HAP signing failed. Check the password and signing files.'
    }
    [Environment]::SetEnvironmentVariable($passwordEnvironment, $previousPassword, 'Process')
    & $java -jar $signTool verify-app -inFile $output `
        -outCertChain (Join-Path $outputDir 'verified-certificates.cer') `
        -outProfile (Join-Path $outputDir 'verified-profile.p7b')
    if ($LASTEXITCODE -ne 0) { throw 'Signed HAP verification failed.' }
    Write-Host ''
    Write-Host "SUCCESS: $output" -ForegroundColor Green
    Write-Host 'Upload this signed HAP to HarmonyOS cloud debugging (API 20 or higher).'
    exit 0
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    [Environment]::SetEnvironmentVariable($passwordEnvironment, $previousPassword, 'Process')
    $password = $null
}
