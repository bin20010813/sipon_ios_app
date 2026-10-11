[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$signingDir = Join-Path $projectRoot 'ohos/signing'
$keyFile = Join-Path $signingDir 'sipon-release.p12'
$csrFile = Join-Path $signingDir 'sipon-release.csr'
$keyAlias = 'sipon_release'
$passwordVariable = 'SIPON_CSR_KEYSTORE_PASSWORD'

function Read-KeyPassword {
    param([bool]$NewKeystore)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Sipon - Keystore password'
    $form.ClientSize = New-Object System.Drawing.Size(450, 215)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $prompt = New-Object System.Windows.Forms.Label
    $prompt.Text = if ($NewKeystore) { 'Set a password (at least 8 characters), then confirm it.' } else { 'Enter the password for your existing keystore.' }
    $prompt.Location = New-Object System.Drawing.Point(15, 15)
    $prompt.Size = New-Object System.Drawing.Size(420, 25)
    $form.Controls.Add($prompt)
    $password = New-Object System.Windows.Forms.TextBox
    $password.Location = New-Object System.Drawing.Point(15, 47)
    $password.Size = New-Object System.Drawing.Size(420, 25)
    $password.UseSystemPasswordChar = $true
    $form.Controls.Add($password)
    $confirmLabel = New-Object System.Windows.Forms.Label
    $confirmLabel.Text = 'Confirm password:'
    $confirmLabel.Location = New-Object System.Drawing.Point(15, 82)
    $confirmLabel.Size = New-Object System.Drawing.Size(420, 20)
    $confirmLabel.Visible = $NewKeystore
    $form.Controls.Add($confirmLabel)
    $confirmation = New-Object System.Windows.Forms.TextBox
    $confirmation.Location = New-Object System.Drawing.Point(15, 106)
    $confirmation.Size = New-Object System.Drawing.Size(420, 25)
    $confirmation.UseSystemPasswordChar = $true
    $confirmation.Visible = $NewKeystore
    $form.Controls.Add($confirmation)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Location = New-Object System.Drawing.Point(260, 164)
    $ok.Add_Click({
        if ([string]::IsNullOrEmpty($password.Text) -or
            ($NewKeystore -and $password.Text.Length -lt 8)) {
            [System.Windows.Forms.MessageBox]::Show('Enter a password. New passwords need at least 8 characters.', 'Sipon') | Out-Null
            return
        }
        if ($NewKeystore -and $password.Text -cne $confirmation.Text) {
            [System.Windows.Forms.MessageBox]::Show('The two passwords do not match.', 'Sipon') | Out-Null
            return
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(350, 164)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Add_Shown({ $password.Focus() })
    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw 'Password entry cancelled. Existing key files have been preserved.'
        }
        return $password.Text
    } finally {
        $password.Clear()
        $confirmation.Clear()
        $form.Dispose()
    }
}

function Format-IdentityValue {
    param([string]$Value)
    $escaped = $Value.Trim().Replace('\', '\\')
    foreach ($character in @(',', '+', '"', '<', '>', ';', '=', '#')) {
        $escaped = $escaped.Replace($character, ('\' + $character))
    }
    return $escaped
}

function Read-DeveloperIdentity {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Sipon - 开发者资料'
    $form.ClientSize = New-Object System.Drawing.Size(500, 335)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = '填写真实资料。选填项可以留空，不用填写 null。'
    $tip.Location = New-Object System.Drawing.Point(15, 15)
    $tip.Size = New-Object System.Drawing.Size(470, 25)
    $form.Controls.Add($tip)
    $fields = [ordered]@{
        CN = '姓名（必填）'
        OU = '部门（选填）'
        O = '组织或公司（选填）'
        L = '城市（选填）'
        ST = '省份（选填）'
        C = '国家代码（中国填 CN）'
    }
    $boxes = @{}
    $row = 0
    foreach ($name in $fields.Keys) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $fields[$name]
        $label.Location = New-Object System.Drawing.Point(15, (52 + 35 * $row))
        $label.Size = New-Object System.Drawing.Size(185, 25)
        $form.Controls.Add($label)
        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(200, (48 + 35 * $row))
        $box.Size = New-Object System.Drawing.Size(285, 25)
        if ($name -eq 'C') { $box.Text = 'CN' }
        $boxes[$name] = $box
        $form.Controls.Add($box)
        $row++
    }
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '生成'
    $ok.Location = New-Object System.Drawing.Point(310, 285)
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($boxes['CN'].Text) -or
            $boxes['C'].Text.Trim() -notmatch '^[A-Za-z]{2}$') {
            [System.Windows.Forms.MessageBox]::Show('请填写姓名和两位字母的国家代码。', 'Sipon') | Out-Null
            return
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.Location = New-Object System.Drawing.Point(400, 285)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Add_Shown({ $boxes['CN'].Focus() })
    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw 'Developer identity entry cancelled. Existing key files have been preserved.'
        }
        $parts = foreach ($name in $fields.Keys) {
            $value = $boxes[$name].Text.Trim()
            if ($name -eq 'C') { $value = $value.ToUpperInvariant() }
            if ($value) { $name + '=' + (Format-IdentityValue $value) }
        }
        return $parts -join ','
    } finally {
        $form.Dispose()
    }
}

try {
    $keytool = $null
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
        if (Test-Path -LiteralPath $candidate) { $keytool = $candidate }
    }
    if (-not $keytool) { $keytool = (Get-Command keytool.exe -ErrorAction Stop).Source }
    if ($CheckOnly) {
        Write-Host "Keytool: $keytool"
        Write-Host "Output directory: $signingDir"
        Write-Host 'PASS: prerequisite check only; no key or CSR was generated.'
        exit 0
    }

    Write-Host 'Sipon HarmonyOS release key and CSR' -ForegroundColor Cyan
    Write-Host "Key alias: $keyAlias"
    Write-Host 'A password window will open; typed characters appear as dots.'
    Write-Host 'For a new key, developer identity is entered in a second window.'
    Write-Host 'Country code: CN for China. Remember the password; it is needed for signing.'
    Write-Host 'Remember the password. It is not written to a file or passed on the command line.'
    New-Item -ItemType Directory -Path $signingDir -Force | Out-Null

    if (Test-Path -LiteralPath $csrFile) {
        if (-not (Test-Path -LiteralPath $keyFile)) {
            throw 'CSR exists but its private keystore is missing. Locate the matching keystore before continuing.'
        }
        Write-Host 'Key and CSR already exist. Keeping the existing files.' -ForegroundColor Green
    } else {
        $newKeystore = -not (Test-Path -LiteralPath $keyFile)
        $keyPassword = Read-KeyPassword -NewKeystore $newKeystore
        $previousPassword = [Environment]::GetEnvironmentVariable($passwordVariable, 'Process')
        try {
            [Environment]::SetEnvironmentVariable($passwordVariable, $keyPassword, 'Process')
            $keyPassword = $null
            if ($newKeystore) {
                $identity = Read-DeveloperIdentity
                & $keytool -genkeypair -alias $keyAlias -keyalg EC -groupname secp256r1 `
                    -sigalg SHA256withECDSA -storetype PKCS12 -validity 9125 -keystore $keyFile `
                    -storepass:env $passwordVariable -keypass:env $passwordVariable -dname $identity
                if ($LASTEXITCODE -ne 0) { throw 'Key generation failed. Read the keytool error above.' }
            } else {
                Write-Host 'Reusing the existing keystore to create its CSR.'
            }
            Write-Host 'Generating CSR using the password already entered...'
            & $keytool -certreq -alias $keyAlias -sigalg SHA256withECDSA `
                -keystore $keyFile -storetype PKCS12 -file $csrFile `
                -storepass:env $passwordVariable -keypass:env $passwordVariable
            if ($LASTEXITCODE -ne 0) { throw 'CSR generation failed. The existing keystore has been preserved.' }
        } finally {
            [Environment]::SetEnvironmentVariable($passwordVariable, $previousPassword, 'Process')
            $keyPassword = $null
            $previousPassword = $null
        }
    }

    if (-not (Test-Path -LiteralPath $keyFile) -or
        -not (Test-Path -LiteralPath $csrFile) -or
        (Get-Item -LiteralPath $csrFile).Length -eq 0) {
        throw 'Expected key or CSR output is missing or empty.'
    }
    Write-Host ''
    Write-Host "Keystore: $keyFile"
    Write-Host "Upload this CSR to AGC: $csrFile" -ForegroundColor Green
    Write-Host 'AGC: Certificates, App IDs and Profiles -> Certificates -> Add -> Release.'
    Write-Host 'Then create a RELEASE Profile for cn.hangzhoutanji.sipon.'
    Write-Host 'Save the downloaded .cer and .p7b in the output directory above.'
    exit 0
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
