[CmdletBinding()]
param([string]$OhosRoot)

$ErrorActionPreference = 'Stop'
if (-not $OhosRoot) { $OhosRoot = Join-Path $PSScriptRoot '../ohos' }
$strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
$module = [IO.File]::ReadAllText((Join-Path $OhosRoot 'entry/src/main/module.json5'), $strictUtf8) | ConvertFrom-Json
$reasonNames = @($module.module.requestPermissions | Where-Object { $_.reason -like '$string:*' } |
    ForEach-Object { $_.reason.Substring(8) } | Sort-Object -Unique)
foreach ($locale in @('base', 'zh_CN', 'en_US')) {
    $stringsPath = Join-Path $OhosRoot "entry/src/main/resources/$locale/element/string.json"
    $strings = ([IO.File]::ReadAllText($stringsPath, $strictUtf8) | ConvertFrom-Json).string
    foreach ($name in $reasonNames) {
        $entries = @($strings | Where-Object { $_.name -eq $name })
        if ($entries.Count -ne 1 -or [string]::IsNullOrWhiteSpace($entries[0].value) -or
            $entries[0].value -match '\?{3,}|\uFFFD') {
            throw "Invalid permission explanation: $locale/$name. Restore the UTF-8 text before building."
        }
    }
}
Write-Output 'PASS: permission explanations are present and readable in every supported locale.'
