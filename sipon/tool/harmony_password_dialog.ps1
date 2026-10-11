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
