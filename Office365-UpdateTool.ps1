#requires -Version 5.1
<#
Microsoft 365 Channel and Update Tool

Fixes:
- Reads actual installed Office executable versions.
- Uses registry version only as a fallback.
- Shows the version source and registry version separately.
- Compares channel GUIDs instead of complete URLs.
- Processes up to 15 computers concurrently.
- Uses a real queue for additional computers.
- Saves an automatic activity log.
- Finishes early after a changed version remains stable.
#>

#region Assemblies and elevation

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object `
            Security.Principal.WindowsPrincipal($identity)

        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } catch {
        return $false
    }
}

if (-not (Test-IsAdministrator)) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Administrator rights are required.`r`n`r`nRestart as Administrator?",
        'Administrator Rights Required',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Start-Process `
                -FilePath "$PSHOME\powershell.exe" `
                -ArgumentList "-NoProfile -STA -File `"$PSCommandPath`"" `
                -Verb RunAs `
                -ErrorAction Stop
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Unable to restart as Administrator.`r`n`r`n$($_.Exception.Message)",
                'Elevation Failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }

    return
}

#endregion

#region Configuration

$script:MaximumConcurrency = 15

$script:ChannelDefinitions = @(
    [pscustomobject]@{
        Identifier  = 'Current'
        DisplayName = 'Current Channel'
        CdnId       = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        Description = 'Receives new features as soon as Microsoft releases them.'
    }
    [pscustomobject]@{
        Identifier  = 'MonthlyEnterprise'
        DisplayName = 'Monthly Enterprise Channel'
        CdnId       = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
        Description = 'Receives feature updates on a predictable monthly schedule.'
    }
    [pscustomobject]@{
        Identifier  = 'SemiAnnual'
        DisplayName = 'Semi-Annual Enterprise Channel'
        CdnId       = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'
        Description = 'Receives feature updates twice each year.'
    }
    [pscustomobject]@{
        Identifier  = 'SemiAnnualPreview'
        DisplayName = 'Semi-Annual Enterprise Channel (Preview)'
        CdnId       = 'b8f9b850-328d-4355-9145-c59439a0c4cf'
        Description = 'Preview of the next Semi-Annual Enterprise release.'
    }
    [pscustomobject]@{
        Identifier  = 'CurrentPreview'
        DisplayName = 'Current Channel (Preview)'
        CdnId       = '64256afe-f5d9-4f86-8936-8840a6a4f5be'
        Description = 'Preview of the next Current Channel release.'
    }
    [pscustomobject]@{
        Identifier  = 'BetaChannel'
        DisplayName = 'Beta Channel'
        CdnId       = '5440fd1f-7ecb-4221-8110-145efaa6372f'
        Description = 'Receives prerelease builds. Licensing restrictions may apply.'
    }
)

#endregion

#region Automatic log

$documentsPath = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::MyDocuments
)

if ([string]::IsNullOrWhiteSpace($documentsPath)) {
    $documentsPath = $env:USERPROFILE
}

$script:LogDirectory = Join-Path `
    $documentsPath `
    'Microsoft 365 Update Tool\Logs'

try {
    if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
        [void](New-Item `
            -Path $script:LogDirectory `
            -ItemType Directory `
            -Force)
    }
} catch {
    $script:LogDirectory = $env:TEMP
}

$script:LogPath = Join-Path $script:LogDirectory (
    'O365Updater_{0}.log' -f
    (Get-Date -Format 'yyyyMMdd_HHmmss')
)

try {
    @(
        'Microsoft 365 Channel and Update Tool'
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Operator: $env:USERDOMAIN\$env:USERNAME"
        "Management computer: $env:COMPUTERNAME"
        ('-' * 78)
    ) | Set-Content -LiteralPath $script:LogPath -Encoding UTF8
} catch {}

#endregion

#region Theme and helpers

$colorWindow      = [Drawing.Color]::FromArgb(245, 246, 248)
$colorWhite       = [Drawing.Color]::White
$colorText        = [Drawing.Color]::FromArgb(31, 35, 40)
$colorSecondary   = [Drawing.Color]::FromArgb(93, 102, 115)
$colorBorder      = [Drawing.Color]::FromArgb(210, 214, 220)
$colorAccent      = [Drawing.Color]::FromArgb(0, 120, 212)
$colorSuccess     = [Drawing.Color]::FromArgb(16, 124, 16)
$colorError       = [Drawing.Color]::FromArgb(196, 43, 28)
$colorConsole     = [Drawing.Color]::FromArgb(24, 24, 24)
$colorConsoleText = [Drawing.Color]::FromArgb(225, 225, 225)

$fontNormal  = New-Object Drawing.Font('Segoe UI', 9)
$fontHeading = New-Object Drawing.Font('Segoe UI Semibold', 18)
$fontSection = New-Object Drawing.Font('Segoe UI Semibold', 10)
$fontConsole = New-Object Drawing.Font('Consolas', 9)

function Set-PrimaryButtonStyle {
    param([System.Windows.Forms.Button]$Button)

    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 0
    $Button.BackColor = $colorAccent
    $Button.ForeColor = $colorWhite
    $Button.Font = New-Object Drawing.Font('Segoe UI Semibold', 9)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
}

function Set-SecondaryButtonStyle {
    param([System.Windows.Forms.Button]$Button)

    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = $colorBorder
    $Button.BackColor = $colorWhite
    $Button.ForeColor = $colorText
    $Button.Font = New-Object Drawing.Font('Segoe UI Semibold', 9)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
}

function Write-GuiLog {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message

    if ($null -ne $txtLog -and -not $txtLog.IsDisposed) {
        $txtLog.AppendText("$line`r`n")
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
    }

    try {
        Add-Content `
            -LiteralPath $script:LogPath `
            -Value $line `
            -Encoding UTF8
    } catch {}
}

function Get-SelectedChannel {
    $enteredText = $cmbChannel.Text.Trim()

    foreach ($channel in $script:ChannelDefinitions) {
        if (
            $enteredText -ieq $channel.Identifier -or
            $enteredText -ieq $channel.DisplayName
        ) {
            return $channel
        }
    }

    return $null
}

function Get-TargetList {
    if ([string]::IsNullOrWhiteSpace($txtTargets.Text)) {
        return @('localhost')
    }

    $targets = @(
        $txtTargets.Text -split '[,;\s]+' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )

    if ($targets.Count -eq 0) {
        return @('localhost')
    }

    return $targets
}

function Set-RunningState {
    param([bool]$Running)

    $btnRun.Enabled = -not $Running
    $btnCredentials.Enabled = -not $Running
    $cmbChannel.Enabled = -not $Running
    $txtTargets.ReadOnly = $Running
    $chkAlternateCredential.Enabled = -not $Running
    $chkForceClose.Enabled = -not $Running
    $numTimeout.Enabled = -not $Running

    if ($Running) {
        $btnSaveResults.Enabled = $false
        $progress.Style =
            [System.Windows.Forms.ProgressBarStyle]::Marquee
        $progress.MarqueeAnimationSpeed = 30
        $lblStatus.Text = 'Running'
        $lblStatus.ForeColor = $colorAccent
    } else {
        $progress.MarqueeAnimationSpeed = 0
        $progress.Style =
            [System.Windows.Forms.ProgressBarStyle]::Blocks

        $progress.Minimum = 0
        $progress.Maximum = [Math]::Max(1, $script:TotalTasks)

        if (
            $script:TotalTasks -gt 0 -and
            $script:CompletedTasks -ge $script:TotalTasks
        ) {
            $progress.Value = $progress.Maximum
        } else {
            $progress.Value = 0
        }

        $btnSaveResults.Enabled = ($script:Results.Count -gt 0)
    }
}

function Update-ResultGrid {
    $gridResults.DataSource = $null

    if ($script:Results.Count -eq 0) {
        return
    }

    $table = New-Object Data.DataTable

    $columns = @(
        'ComputerName'
        'RequestedChannel'
        'PreviousVersion'
        'UpdatedVersion'
        'ExpectedVersion'
        'RegistryVersion'
        'VersionSource'
        'ReleaseCode'
        'VersionChanged'
        'ChannelConfigured'
        'PolicyDetected'
        'Status'
        'Message'
    )

    foreach ($column in $columns) {
        [void]$table.Columns.Add($column)
    }

    foreach ($result in $script:Results.ToArray()) {
        $row = $table.NewRow()

        foreach ($column in $columns) {
            $value = $result.$column

            if ($null -eq $value) {
                $value = ''
            }

            $row[$column] = [string]$value
        }

        $table.Rows.Add($row)
    }

    $gridResults.DataSource = $table
}

function Stop-AllTasks {
    if ($script:TaskTimer) {
        $script:TaskTimer.Stop()
    }

    if ($script:Tasks) {
        foreach ($task in $script:Tasks.ToArray()) {
            try {
                if ($task.PowerShell) {
                    $task.PowerShell.Stop()
                    $task.PowerShell.Dispose()
                }
            } catch {}
        }

        $script:Tasks.Clear()
    }

    if ($script:PendingTargets) {
        $script:PendingTargets.Clear()
    }

    if ($script:RunspacePool) {
        try {
            $script:RunspacePool.Close()
            $script:RunspacePool.Dispose()
        } catch {}

        $script:RunspacePool = $null
    }
}

#endregion

#region Main form

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Microsoft 365 Channel and Update Tool'
$form.ClientSize = New-Object Drawing.Size(1160, 850)
$form.MinimumSize = New-Object Drawing.Size(1050, 790)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $colorWindow
$form.ForeColor = $colorText
$form.Font = $fontNormal
$form.AutoScaleMode = 'Dpi'

$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location = New-Object Drawing.Point(0, 0)
$pnlHeader.Size = New-Object Drawing.Size(1160, 72)
$pnlHeader.Anchor = 'Top,Left,Right'
$pnlHeader.BackColor = $colorWhite

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = New-Object Drawing.Point(25, 19)
$lblTitle.Size = New-Object Drawing.Size(760, 35)
$lblTitle.Text = 'Microsoft 365 Channel and Update Tool'
$lblTitle.Font = $fontHeading

$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.Location = New-Object Drawing.Point(900, 22)
$lblAdmin.Size = New-Object Drawing.Size(225, 26)
$lblAdmin.TextAlign = 'MiddleCenter'
$lblAdmin.Font = New-Object Drawing.Font('Segoe UI Semibold', 9)
$lblAdmin.Text = 'Administrator: Yes'
$lblAdmin.ForeColor = $colorSuccess

$pnlHeader.Controls.AddRange(@($lblTitle, $lblAdmin))

$grpConfiguration = New-Object System.Windows.Forms.GroupBox
$grpConfiguration.Location = New-Object Drawing.Point(20, 90)
$grpConfiguration.Size = New-Object Drawing.Size(550, 330)
$grpConfiguration.Text = '  Update Configuration  '
$grpConfiguration.Font = $fontSection
$grpConfiguration.BackColor = $colorWhite

$lblChannel = New-Object System.Windows.Forms.Label
$lblChannel.Location = New-Object Drawing.Point(20, 34)
$lblChannel.Size = New-Object Drawing.Size(500, 20)
$lblChannel.Text = 'Microsoft 365 update channel'

$cmbChannel = New-Object System.Windows.Forms.ComboBox
$cmbChannel.Location = New-Object Drawing.Point(20, 58)
$cmbChannel.Size = New-Object Drawing.Size(505, 28)
$cmbChannel.DropDownStyle = 'DropDown'
$cmbChannel.AutoCompleteMode = 'SuggestAppend'
$cmbChannel.AutoCompleteSource = 'ListItems'
$cmbChannel.DisplayMember = 'DisplayName'

foreach ($channel in $script:ChannelDefinitions) {
    [void]$cmbChannel.Items.Add($channel)
}

$cmbChannel.SelectedIndex = 0

$lblChannelDescription = New-Object System.Windows.Forms.Label
$lblChannelDescription.Location = New-Object Drawing.Point(20, 94)
$lblChannelDescription.Size = New-Object Drawing.Size(505, 38)
$lblChannelDescription.Text =
    $script:ChannelDefinitions[0].Description
$lblChannelDescription.ForeColor = $colorSecondary

$lblTargets = New-Object System.Windows.Forms.Label
$lblTargets.Location = New-Object Drawing.Point(20, 139)
$lblTargets.Size = New-Object Drawing.Size(505, 38)
$lblTargets.Text = 'Leave blank to update this local computer. Enter remote computer names on separate lines or separated by commas.'

$txtTargets = New-Object System.Windows.Forms.TextBox
$txtTargets.Location = New-Object Drawing.Point(20, 181)
$txtTargets.Size = New-Object Drawing.Size(505, 78)
$txtTargets.Multiline = $true
$txtTargets.ScrollBars = 'Vertical'
$txtTargets.Text = ''

$lblBlankLocal = New-Object System.Windows.Forms.Label
$lblBlankLocal.Location = New-Object Drawing.Point(20, 266)
$lblBlankLocal.Size = New-Object Drawing.Size(505, 20)
$lblBlankLocal.Text = 'Blank computer list = update this local computer.'
$lblBlankLocal.ForeColor = $colorAccent
$lblBlankLocal.Font =
    New-Object Drawing.Font('Segoe UI Semibold', 9)

$chkForceClose = New-Object System.Windows.Forms.CheckBox
$chkForceClose.Location = New-Object Drawing.Point(20, 292)
$chkForceClose.Size = New-Object Drawing.Size(505, 25)
$chkForceClose.Text =
    'Allow Office applications to close automatically'

$grpConfiguration.Controls.AddRange(@(
    $lblChannel,
    $cmbChannel,
    $lblChannelDescription,
    $lblTargets,
    $txtTargets,
    $lblBlankLocal,
    $chkForceClose
))

$grpExecution = New-Object System.Windows.Forms.GroupBox
$grpExecution.Location = New-Object Drawing.Point(590, 90)
$grpExecution.Size = New-Object Drawing.Size(550, 330)
$grpExecution.Text = '  Credentials and Execution  '
$grpExecution.Font = $fontSection
$grpExecution.BackColor = $colorWhite

$chkAlternateCredential = New-Object System.Windows.Forms.CheckBox
$chkAlternateCredential.Location = New-Object Drawing.Point(20, 35)
$chkAlternateCredential.Size = New-Object Drawing.Size(500, 25)
$chkAlternateCredential.Text =
    'Use alternate credentials for remote computers'

$btnCredentials = New-Object System.Windows.Forms.Button
$btnCredentials.Location = New-Object Drawing.Point(20, 70)
$btnCredentials.Size = New-Object Drawing.Size(155, 34)
$btnCredentials.Text = 'Set Credentials'
Set-SecondaryButtonStyle $btnCredentials

$lblCredential = New-Object System.Windows.Forms.Label
$lblCredential.Location = New-Object Drawing.Point(190, 75)
$lblCredential.Size = New-Object Drawing.Size(335, 24)
$lblCredential.Text = 'Using current credentials'
$lblCredential.ForeColor = $colorSecondary

$lblTimeout = New-Object System.Windows.Forms.Label
$lblTimeout.Location = New-Object Drawing.Point(20, 121)
$lblTimeout.Size = New-Object Drawing.Size(265, 20)
$lblTimeout.Text = 'Maximum update wait time per computer'

$numTimeout = New-Object System.Windows.Forms.NumericUpDown
$numTimeout.Location = New-Object Drawing.Point(300, 118)
$numTimeout.Size = New-Object Drawing.Size(75, 25)
$numTimeout.Minimum = 5
$numTimeout.Maximum = 120
$numTimeout.Value = 45

$lblMinutes = New-Object System.Windows.Forms.Label
$lblMinutes.Location = New-Object Drawing.Point(385, 121)
$lblMinutes.Size = New-Object Drawing.Size(80, 20)
$lblMinutes.Text = 'minutes'

$lblConcurrency = New-Object System.Windows.Forms.Label
$lblConcurrency.Location = New-Object Drawing.Point(20, 156)
$lblConcurrency.Size = New-Object Drawing.Size(505, 42)
$lblConcurrency.Text = 'Up to 15 computers run at the same time. Additional computers remain queued until a slot becomes available.'
$lblConcurrency.ForeColor = $colorAccent
$lblConcurrency.Font =
    New-Object Drawing.Font('Segoe UI Semibold', 9)

$lblRemoteNotice = New-Object System.Windows.Forms.Label
$lblRemoteNotice.Location = New-Object Drawing.Point(20, 205)
$lblRemoteNotice.Size = New-Object Drawing.Size(505, 40)
$lblRemoteNotice.Text = "Remote computers require WinRM, PowerShell remoting,`r`nand remote administrator rights."
$lblRemoteNotice.ForeColor = $colorSecondary

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Location = New-Object Drawing.Point(20, 260)
$btnRun.Size = New-Object Drawing.Size(220, 48)
$btnRun.Text = 'Change Channel and Update'
Set-PrimaryButtonStyle $btnRun

$btnSaveResults = New-Object System.Windows.Forms.Button
$btnSaveResults.Location = New-Object Drawing.Point(255, 260)
$btnSaveResults.Size = New-Object Drawing.Size(125, 48)
$btnSaveResults.Text = 'Save Results'
$btnSaveResults.Enabled = $false
Set-SecondaryButtonStyle $btnSaveResults

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location = New-Object Drawing.Point(395, 260)
$btnClear.Size = New-Object Drawing.Size(125, 48)
$btnClear.Text = 'Clear Log'
Set-SecondaryButtonStyle $btnClear

$grpExecution.Controls.AddRange(@(
    $chkAlternateCredential,
    $btnCredentials,
    $lblCredential,
    $lblTimeout,
    $numTimeout,
    $lblMinutes,
    $lblConcurrency,
    $lblRemoteNotice,
    $btnRun,
    $btnSaveResults,
    $btnClear
))

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(20, 440)
$tabs.Size = New-Object Drawing.Size(1120, 325)
$tabs.Anchor = 'Top,Bottom,Left,Right'

$tabResults = New-Object System.Windows.Forms.TabPage
$tabResults.Text = 'Results'
$tabResults.BackColor = $colorWhite

$gridResults = New-Object System.Windows.Forms.DataGridView
$gridResults.Dock = 'Fill'
$gridResults.BackgroundColor = $colorWhite
$gridResults.BorderStyle = 'None'
$gridResults.AllowUserToAddRows = $false
$gridResults.AllowUserToDeleteRows = $false
$gridResults.AllowUserToResizeRows = $false
$gridResults.ReadOnly = $true
$gridResults.RowHeadersVisible = $false
$gridResults.AutoSizeColumnsMode = 'DisplayedCells'
$gridResults.SelectionMode = 'FullRowSelect'
$gridResults.MultiSelect = $false
$gridResults.EnableHeadersVisualStyles = $false

$tabResults.Controls.Add($gridResults)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = 'Activity Log'
$tabLog.BackColor = $colorConsole

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Dock = 'Fill'
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Both'
$txtLog.WordWrap = $false
$txtLog.BackColor = $colorConsole
$txtLog.ForeColor = $colorConsoleText
$txtLog.Font = $fontConsole
$txtLog.BorderStyle = 'None'

$tabLog.Controls.Add($txtLog)
$tabs.TabPages.AddRange(@($tabResults, $tabLog))

$lblLogPath = New-Object System.Windows.Forms.Label
$lblLogPath.Location = New-Object Drawing.Point(20, 772)
$lblLogPath.Size = New-Object Drawing.Size(1120, 20)
$lblLogPath.Anchor = 'Bottom,Left,Right'
$lblLogPath.Text = "Automatic log: $script:LogPath"
$lblLogPath.ForeColor = $colorSecondary
$lblLogPath.AutoEllipsis = $true

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(20, 805)
$progress.Size = New-Object Drawing.Size(755, 20)
$progress.Anchor = 'Bottom,Left,Right'
$progress.Minimum = 0
$progress.Maximum = 1

$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Location = New-Object Drawing.Point(785, 800)
$lblProgress.Size = New-Object Drawing.Size(145, 28)
$lblProgress.Text = '0 of 0'
$lblProgress.TextAlign = 'MiddleRight'
$lblProgress.Anchor = 'Bottom,Right'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object Drawing.Point(935, 800)
$lblStatus.Size = New-Object Drawing.Size(105, 28)
$lblStatus.Text = 'Ready'
$lblStatus.TextAlign = 'MiddleRight'
$lblStatus.ForeColor = $colorSecondary
$lblStatus.Anchor = 'Bottom,Right'

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Location = New-Object Drawing.Point(1045, 797)
$btnExit.Size = New-Object Drawing.Size(95, 34)
$btnExit.Text = 'Exit'
$btnExit.Anchor = 'Bottom,Right'
Set-SecondaryButtonStyle $btnExit

$form.Controls.AddRange(@(
    $pnlHeader,
    $grpConfiguration,
    $grpExecution,
    $tabs,
    $lblLogPath,
    $progress,
    $lblProgress,
    $lblStatus,
    $btnExit
))

#endregion

#region Per-computer worker

$script:ComputerUpdateScript = {
    param(
        [string]$Target,
        [string]$RequestedChannel,
        [string]$FriendlyName,
        [string]$ExpectedCdnId,
        [bool]$ForceApplicationsClosed,
        [int]$TimeoutMinutes,
        [Management.Automation.PSCredential]$Credential
    )

    $officeUpdateBlock = {
        param(
            [string]$RequestedChannel,
            [string]$FriendlyName,
            [string]$ExpectedCdnId,
            [bool]$ForceApplicationsClosed,
            [int]$TimeoutMinutes
        )

        $ErrorActionPreference = 'Stop'

        function Get-OfficeConfiguration {
            $paths = @(
                'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
            )

            foreach ($path in $paths) {
                try {
                    return Get-ItemProperty `
                        -LiteralPath $path `
                        -ErrorAction Stop
                } catch {}
            }

            return $null
        }

        function Get-RegistryOfficeVersion {
            $configuration = Get-OfficeConfiguration

            if ($configuration) {
                foreach ($propertyName in @(
                    'VersionToReport',
                    'ClientVersionToReport'
                )) {
                    $value = [string]$configuration.$propertyName

                    if ($value -match '16\.0\.\d+\.\d+') {
                        return $Matches[0]
                    }
                }
            }

            return 'N/A'
        }

        function Get-ActualOfficeVersion {
            $configuration = Get-OfficeConfiguration
            $roots = New-Object Collections.ArrayList

            if ($configuration -and $configuration.InstallationPath) {
                $installationPath =
                    [string]$configuration.InstallationPath

                [void]$roots.Add(
                    (Join-Path $installationPath 'root\Office16')
                )

                [void]$roots.Add(
                    (Join-Path $installationPath 'Office16')
                )
            }

            if ($env:ProgramFiles) {
                [void]$roots.Add(
                    "$env:ProgramFiles\Microsoft Office\root\Office16"
                )

                [void]$roots.Add(
                    "$env:ProgramFiles\Microsoft Office\Office16"
                )
            }

            if (${env:ProgramFiles(x86)}) {
                [void]$roots.Add(
                    "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16"
                )

                [void]$roots.Add(
                    "${env:ProgramFiles(x86)}\Microsoft Office\Office16"
                )
            }

            $officeFiles = @(
                'WINWORD.EXE',
                'EXCEL.EXE',
                'OUTLOOK.EXE',
                'POWERPNT.EXE',
                'MSACCESS.EXE',
                'ONENOTE.EXE'
            )

            $records = New-Object Collections.ArrayList

            foreach ($root in ($roots | Select-Object -Unique)) {
                foreach ($fileName in $officeFiles) {
                    $path = Join-Path $root $fileName

                    if (Test-Path -LiteralPath $path) {
                        try {
                            $item = Get-Item `
                                -LiteralPath $path `
                                -ErrorAction Stop

                            $versionText =
                                [string]$item.VersionInfo.ProductVersion

                            if (
                                $versionText -notmatch
                                '16\.0\.\d+\.\d+'
                            ) {
                                $versionText =
                                    [string]$item.VersionInfo.FileVersion
                            }

                            if (
                                $versionText -match
                                '16\.0\.\d+\.\d+'
                            ) {
                                [void]$records.Add(
                                    [pscustomobject]@{
                                        Version = $Matches[0]
                                        File    = $fileName
                                        Path    = $path
                                    }
                                )
                            }
                        } catch {}
                    }
                }
            }

            if ($records.Count -gt 0) {
                $selectedGroup = $records.ToArray() |
                    Group-Object Version |
                    Sort-Object Count -Descending |
                    Select-Object -First 1

                $sample = $records.ToArray() |
                    Where-Object {
                        $_.Version -eq $selectedGroup.Name
                    } |
                    Select-Object -First 1

                return [pscustomobject]@{
                    Version = [string]$selectedGroup.Name
                    Source  = "Office executable ($($sample.File))"
                }
            }

            $registryVersion = Get-RegistryOfficeVersion

            return [pscustomobject]@{
                Version = $registryVersion
                Source  = 'Click-to-Run registry fallback'
            }
        }

        function Get-OfficeTargetVersion {
            $paths = @(
                'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Updates',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Updates'
            )

            foreach ($path in $paths) {
                try {
                    $updates = Get-ItemProperty `
                        -LiteralPath $path `
                        -ErrorAction Stop

                    foreach ($propertyName in @(
                        'UpdateToVersion',
                        'UpdatesReadyToApply'
                    )) {
                        $value = [string]$updates.$propertyName

                        if ($value -match '16\.0\.\d+\.\d+') {
                            return $Matches[0]
                        }
                    }
                } catch {}
            }

            return $null
        }

        function Get-OfficeClient {
            $paths = @(
                "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe",
                "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
            )

            foreach ($path in $paths) {
                if ($path -and (Test-Path -LiteralPath $path)) {
                    return $path
                }
            }

            return $null
        }

        function Test-RequestedChannelConfigured {
            param([string]$ExpectedId)

            $configuration = Get-OfficeConfiguration

            if (-not $configuration) {
                return $false
            }

            foreach ($propertyName in @(
                'UpdateChannel',
                'CDNBaseUrl',
                'UpdateChannelChanged'
            )) {
                $value = [string]$configuration.$propertyName

                if (
                    -not [string]::IsNullOrWhiteSpace($value) -and
                    $value.IndexOf(
                        $ExpectedId,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -ge 0
                ) {
                    return $true
                }
            }

            return $false
        }

        function Get-ReleaseCode {
            param([string]$Version)

            $releaseMap = @{
                '20326' = '2608'
                '20214' = '2607'
                '20156' = '2606'
                '20042' = '2605'
                '19928' = '2604'
                '19817' = '2603'
                '19725' = '2602'
                '19628' = '2601'
            }

            if ($Version -match '^16\.0\.(\d+)\.\d+$') {
                $branch = $Matches[1]

                if ($releaseMap.ContainsKey($branch)) {
                    return $releaseMap[$branch]
                }
            }

            return 'N/A'
        }

        function Test-OfficePolicy {
            $paths = @(
                'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate',
                'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'
            )

            foreach ($path in $paths) {
                try {
                    $policy = Get-ItemProperty `
                        -LiteralPath $path `
                        -ErrorAction Stop

                    if (
                        $policy.UpdateBranch -or
                        $policy.UpdatePath -or
                        $policy.UpdateTargetVersion
                    ) {
                        return $true
                    }
                } catch {}
            }

            return $false
        }

        $result = [ordered]@{
            ComputerName     = $env:COMPUTERNAME
            RequestedChannel = $FriendlyName
            PreviousVersion  = 'N/A'
            UpdatedVersion   = 'N/A'
            ExpectedVersion  = 'Not reported'
            RegistryVersion  = 'N/A'
            VersionSource    = 'N/A'
            ReleaseCode      = 'N/A'
            VersionChanged   = $false
            ChannelConfigured = $false
            PolicyDetected   = $false
            ChannelExitCode  = $null
            UpdateExitCode   = $null
            Status           = 'Starting'
            Message          = ''
        }

        try {
            $identity =
                [Security.Principal.WindowsIdentity]::GetCurrent()

            $principal = New-Object `
                Security.Principal.WindowsPrincipal($identity)

            if (-not $principal.IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )) {
                throw 'The session does not have administrator rights.'
            }

            $client = Get-OfficeClient

            if (-not $client) {
                throw 'OfficeC2RClient.exe was not found. Microsoft 365 Click-to-Run may not be installed.'
            }

            $before = Get-ActualOfficeVersion

            $result.PreviousVersion = $before.Version
            $result.VersionSource = $before.Source
            $result.RegistryVersion = Get-RegistryOfficeVersion
            $result.PolicyDetected = Test-OfficePolicy

            $changeProcess = Start-Process `
                -FilePath $client `
                -ArgumentList @(
                    '/changesetting',
                    "Channel=$RequestedChannel"
                ) `
                -Wait `
                -PassThru `
                -WindowStyle Hidden `
                -ErrorAction Stop

            $result.ChannelExitCode = $changeProcess.ExitCode

            if ($changeProcess.ExitCode -ne 0) {
                throw "Channel change returned exit code $($changeProcess.ExitCode)."
            }

            Start-Sleep -Seconds 5

            $forceValue = if ($ForceApplicationsClosed) {
                'true'
            } else {
                'false'
            }

            $updateProcess = Start-Process `
                -FilePath $client `
                -ArgumentList @(
                    '/update',
                    'user',
                    'displaylevel=false',
                    "forceappshutdown=$forceValue",
                    'updatepromptuser=false'
                ) `
                -Wait `
                -PassThru `
                -WindowStyle Hidden `
                -ErrorAction Stop

            $result.UpdateExitCode = $updateProcess.ExitCode

            if ($updateProcess.ExitCode -ne 0) {
                throw "Office update request returned exit code $($updateProcess.ExitCode)."
            }

            $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
            $lastVersion = $result.PreviousVersion
            $stableChecks = 0
            $completed = $false
            $completionReason = ''

            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 10

                $current = Get-ActualOfficeVersion
                $targetVersion = Get-OfficeTargetVersion
                $channelConfigured =
                    Test-RequestedChannelConfigured $ExpectedCdnId

                if ($targetVersion) {
                    $result.ExpectedVersion = $targetVersion
                }

                if ($current.Version -eq $lastVersion) {
                    $stableChecks++
                } else {
                    $lastVersion = $current.Version
                    $stableChecks = 0
                }

                $versionChanged = (
                    $current.Version -ne 'N/A' -and
                    $current.Version -ne $result.PreviousVersion
                )

                # A changed executable version that remains stable for
                # 30 seconds is treated as complete.
                if ($versionChanged -and $stableChecks -ge 3) {
                    $completed = $true
                    $completionReason = 'ChangedAndStable'
                    break
                }

                # If the actual executable version matches Click-to-Run's
                # target, the update is complete.
                if (
                    $targetVersion -and
                    $current.Version -eq $targetVersion -and
                    $stableChecks -ge 2
                ) {
                    $completed = $true
                    $completionReason = 'TargetMatched'
                    break
                }

                # If the requested channel is configured and the reported
                # target already equals the executable version, Office was
                # already current on the requested channel.
                if (
                    $channelConfigured -and
                    $targetVersion -and
                    $current.Version -eq $targetVersion -and
                    $stableChecks -ge 3
                ) {
                    $completed = $true
                    $completionReason = 'AlreadyCurrent'
                    break
                }
            }

            Start-Sleep -Seconds 2

            $final = Get-ActualOfficeVersion
            $finalTarget = Get-OfficeTargetVersion

            $result.UpdatedVersion = $final.Version
            $result.VersionSource = $final.Source
            $result.RegistryVersion = Get-RegistryOfficeVersion
            $result.ReleaseCode =
                Get-ReleaseCode -Version $final.Version

            if ($finalTarget) {
                $result.ExpectedVersion = $finalTarget
            }

            $result.VersionChanged = (
                $final.Version -ne 'N/A' -and
                $final.Version -ne $result.PreviousVersion
            )

            $result.ChannelConfigured =
                Test-RequestedChannelConfigured $ExpectedCdnId

            if ($result.VersionChanged) {
                $result.Status = 'Updated'
                $result.Message =
                    'The installed Office executable version changed successfully.'
            } elseif (
                $finalTarget -and
                $final.Version -eq $finalTarget
            ) {
                $result.Status = 'Already Current'
                $result.Message =
                    'The installed Office executable version matches the offered version.'
            } elseif (
                $completed -and
                $completionReason -eq 'AlreadyCurrent'
            ) {
                $result.Status = 'Already Current'
                $result.Message =
                    'Office is already current on the requested channel.'
            } elseif ($result.ChannelConfigured) {
                $result.Status = 'Channel Changed / No Build Change'
                $result.Message =
                    'The requested channel is configured, but the installed executable version did not change. The same build may be available on both channels.'
            } else {
                $result.Status = 'Timed Out / Verify'
                $result.Message =
                    'The executable version did not change and the requested channel could not be confirmed before the timeout.'
            }

            if (
                $result.RegistryVersion -ne 'N/A' -and
                $result.RegistryVersion -ne $result.UpdatedVersion
            ) {
                $result.Message +=
                    ' The Click-to-Run registry version is stale and differs from the actual Office executable version.'
            }

            if ($result.PolicyDetected) {
                $result.Message +=
                    ' An Office update policy was detected and may control the channel or version.'
            }
        } catch {
            $final = Get-ActualOfficeVersion

            $result.UpdatedVersion = $final.Version
            $result.VersionSource = $final.Source
            $result.RegistryVersion = Get-RegistryOfficeVersion
            $result.ReleaseCode =
                Get-ReleaseCode -Version $final.Version

            $result.VersionChanged = (
                $final.Version -ne 'N/A' -and
                $final.Version -ne $result.PreviousVersion
            )

            $result.Status = 'Failed'
            $result.Message = $_.Exception.Message
        }

        [pscustomobject]$result
    }

    $localFqdn = if ($env:USERDNSDOMAIN) {
        "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
    } else {
        $env:COMPUTERNAME
    }

    $isLocal = (
        $Target -match '^(localhost|127\.0\.0\.1|\.)$' -or
        $Target -ieq $env:COMPUTERNAME -or
        $Target -ieq $localFqdn
    )

    try {
        if ($isLocal) {
            & $officeUpdateBlock `
                $RequestedChannel `
                $FriendlyName `
                $ExpectedCdnId `
                $ForceApplicationsClosed `
                $TimeoutMinutes
        } else {
            $invokeParameters = @{
                ComputerName = $Target
                ScriptBlock  = $officeUpdateBlock
                ArgumentList = @(
                    $RequestedChannel,
                    $FriendlyName,
                    $ExpectedCdnId,
                    $ForceApplicationsClosed,
                    $TimeoutMinutes
                )
                ErrorAction = 'Stop'
            }

            if ($Credential) {
                $invokeParameters.Credential = $Credential
            }

            Invoke-Command @invokeParameters
        }
    } catch {
        [pscustomobject]@{
            ComputerName      = $Target
            RequestedChannel  = $FriendlyName
            PreviousVersion   = 'N/A'
            UpdatedVersion    = 'N/A'
            ExpectedVersion   = 'N/A'
            RegistryVersion   = 'N/A'
            VersionSource     = 'N/A'
            ReleaseCode       = 'N/A'
            VersionChanged    = $false
            ChannelConfigured = $false
            PolicyDetected    = $false
            ChannelExitCode   = $null
            UpdateExitCode    = $null
            Status            = 'Connection Failed'
            Message           = $_.Exception.Message
        }
    }
}

#endregion

#region State and queue

$script:Credential = $null
$script:Results = New-Object Collections.ArrayList
$script:Tasks = New-Object Collections.ArrayList
$script:PendingTargets = New-Object Collections.ArrayList
$script:RunspacePool = $null
$script:RunConfiguration = $null
$script:TotalTasks = 0
$script:CompletedTasks = 0
$script:ClosingApplication = $false

function Start-QueuedTasks {
    if (-not $script:RunspacePool) {
        return
    }

    while (
        $script:Tasks.Count -lt $script:MaximumConcurrency -and
        $script:PendingTargets.Count -gt 0
    ) {
        $target = [string]$script:PendingTargets[0]
        $script:PendingTargets.RemoveAt(0)

        $powerShell = [Management.Automation.PowerShell]::Create()
        $powerShell.RunspacePool = $script:RunspacePool

        [void]$powerShell.AddScript(
            $script:ComputerUpdateScript.ToString()
        )

        [void]$powerShell.AddArgument($target)
        [void]$powerShell.AddArgument(
            $script:RunConfiguration.ChannelIdentifier
        )
        [void]$powerShell.AddArgument(
            $script:RunConfiguration.ChannelName
        )
        [void]$powerShell.AddArgument(
            $script:RunConfiguration.ExpectedCdnId
        )
        [void]$powerShell.AddArgument(
            $script:RunConfiguration.ForceClose
        )
        [void]$powerShell.AddArgument(
            $script:RunConfiguration.TimeoutMinutes
        )
        [void]$powerShell.AddArgument(
            $script:RunConfiguration.Credential
        )

        $handle = $powerShell.BeginInvoke()
        $now = Get-Date

        [void]$script:Tasks.Add(
            [pscustomobject]@{
                Target           = $target
                RequestedChannel = $script:RunConfiguration.ChannelName
                PowerShell       = $powerShell
                Handle           = $handle
                Started          = $now
                LastHeartbeat    = $now
            }
        )

        Write-GuiLog "$target`: Running. An update slot is active."
    }

    $lblStatus.Text = 'Running: {0}; queued: {1}' -f `
        $script:Tasks.Count,
        $script:PendingTargets.Count
}

#endregion

#region Task monitor

$script:TaskTimer = New-Object System.Windows.Forms.Timer
$script:TaskTimer.Interval = 500

$script:TaskTimer.Add_Tick({
    try {
        $finishedTasks = New-Object Collections.ArrayList

        foreach ($task in $script:Tasks.ToArray()) {
            if ($task.Handle.IsCompleted) {
                try {
                    $output = $task.PowerShell.EndInvoke($task.Handle)
                    $validResult = $false

                    foreach ($result in $output) {
                        if ($result.PSObject.Properties['ComputerName']) {
                            [void]$script:Results.Add($result)
                            $validResult = $true

                            Write-GuiLog (
                                '{0}: {1}; previous {2}; installed {3}; expected {4}; registry {5}; source {6}; release {7}' -f
                                $result.ComputerName,
                                $result.Status,
                                $result.PreviousVersion,
                                $result.UpdatedVersion,
                                $result.ExpectedVersion,
                                $result.RegistryVersion,
                                $result.VersionSource,
                                $result.ReleaseCode
                            )

                            Write-GuiLog (
                                '{0}: {1}' -f
                                $result.ComputerName,
                                $result.Message
                            )
                        }
                    }

                    if (-not $validResult) {
                        [void]$script:Results.Add(
                            [pscustomobject]@{
                                ComputerName      = $task.Target
                                RequestedChannel  = $task.RequestedChannel
                                PreviousVersion   = 'N/A'
                                UpdatedVersion    = 'N/A'
                                ExpectedVersion   = 'N/A'
                                RegistryVersion   = 'N/A'
                                VersionSource     = 'N/A'
                                ReleaseCode       = 'N/A'
                                VersionChanged    = $false
                                ChannelConfigured = $false
                                PolicyDetected    = $false
                                Status            = 'No Result'
                                Message           = 'The task returned no result.'
                            }
                        )
                    }
                } catch {
                    [void]$script:Results.Add(
                        [pscustomobject]@{
                            ComputerName      = $task.Target
                            RequestedChannel  = $task.RequestedChannel
                            PreviousVersion   = 'N/A'
                            UpdatedVersion    = 'N/A'
                            ExpectedVersion   = 'N/A'
                            RegistryVersion   = 'N/A'
                            VersionSource     = 'N/A'
                            ReleaseCode       = 'N/A'
                            VersionChanged    = $false
                            ChannelConfigured = $false
                            PolicyDetected    = $false
                            Status            = 'Task Failed'
                            Message           = $_.Exception.Message
                        }
                    )

                    Write-GuiLog (
                        '{0}: Task failed: {1}' -f
                        $task.Target,
                        $_.Exception.Message
                    )
                } finally {
                    try {
                        $task.PowerShell.Dispose()
                    } catch {}
                }

                [void]$finishedTasks.Add($task)
                $script:CompletedTasks++

                $lblProgress.Text = '{0} of {1}' -f `
                    $script:CompletedTasks,
                    $script:TotalTasks

                Update-ResultGrid
            } elseif (
                ((Get-Date) - $task.LastHeartbeat).TotalSeconds -ge 60
            ) {
                $task.LastHeartbeat = Get-Date

                $elapsed = [Math]::Floor(
                    ((Get-Date) - $task.Started).TotalMinutes
                )

                Write-GuiLog (
                    '{0}: Still running; elapsed time {1} minute(s).' -f
                    $task.Target,
                    $elapsed
                )
            }
        }

        foreach ($finished in $finishedTasks.ToArray()) {
            [void]$script:Tasks.Remove($finished)
        }

        Start-QueuedTasks

        if (
            $script:TotalTasks -gt 0 -and
            $script:CompletedTasks -ge $script:TotalTasks -and
            $script:Tasks.Count -eq 0 -and
            $script:PendingTargets.Count -eq 0
        ) {
            $script:TaskTimer.Stop()

            if ($script:RunspacePool) {
                try {
                    $script:RunspacePool.Close()
                    $script:RunspacePool.Dispose()
                } catch {}

                $script:RunspacePool = $null
            }

            $successful = @(
                $script:Results.ToArray() |
                    Where-Object {
                        $_.Status -in @(
                            'Updated',
                            'Already Current',
                            'Channel Changed / No Build Change'
                        )
                    }
            ).Count

            Write-GuiLog (
                'All tasks finished. Successful or current: {0}; total: {1}' -f
                $successful,
                $script:Results.Count
            )

            Write-GuiLog "Automatic log saved to: $script:LogPath"

            $lblStatus.Text = 'Finished'
            $lblStatus.ForeColor = $colorSuccess
            $tabs.SelectedTab = $tabResults

            Set-RunningState $false
        }
    } catch {
        $script:TaskTimer.Stop()
        Write-GuiLog "Task monitor error: $($_.Exception.Message)"
        $lblStatus.Text = 'Monitor Error'
        $lblStatus.ForeColor = $colorError
        Set-RunningState $false
    }
})

#endregion

#region Events

$cmbChannel.Add_SelectedIndexChanged({
    if ($cmbChannel.SelectedItem) {
        $lblChannelDescription.Text =
            $cmbChannel.SelectedItem.Description
    }
})

$btnCredentials.Add_Click({
    $credential = Get-Credential `
        -Message 'Enter remote administrator credentials'

    if ($credential) {
        $script:Credential = $credential
        $chkAlternateCredential.Checked = $true
        $lblCredential.Text = "Credential: $($credential.UserName)"
        $lblCredential.ForeColor = $colorAccent
        Write-GuiLog "Alternate credentials selected for $($credential.UserName)."
    }
})

$chkAlternateCredential.Add_CheckedChanged({
    if (-not $chkAlternateCredential.Checked) {
        $script:Credential = $null
        $lblCredential.Text = 'Using current credentials'
        $lblCredential.ForeColor = $colorSecondary
    }
})

$btnClear.Add_Click({
    $txtLog.Clear()
    Write-GuiLog 'Visible log cleared. The automatic log file was preserved.'
})

$btnSaveResults.Add_Click({
    if ($script:Results.Count -eq 0) {
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = 'Save Microsoft 365 Update Results'
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    $dialog.DefaultExt = 'csv'
    $dialog.FileName =
        "OfficeChannelUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    if (
        $dialog.ShowDialog() -eq
        [System.Windows.Forms.DialogResult]::OK
    ) {
        $script:Results.ToArray() |
            Select-Object ComputerName, RequestedChannel,
                PreviousVersion, UpdatedVersion, ExpectedVersion,
                RegistryVersion, VersionSource, ReleaseCode,
                VersionChanged, ChannelConfigured, PolicyDetected,
                Status, Message |
            Export-Csv `
                -LiteralPath $dialog.FileName `
                -NoTypeInformation `
                -Encoding UTF8

        Write-GuiLog "CSV results saved to: $($dialog.FileName)"
    }
})

$btnRun.Add_Click({
    $channel = Get-SelectedChannel

    if (-not $channel) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select a valid Microsoft 365 channel.',
            'Invalid Channel',
            'OK',
            'Warning'
        ) | Out-Null

        return
    }

    $targets = @(Get-TargetList)

    if (
        $chkAlternateCredential.Checked -and
        -not $script:Credential
    ) {
        $script:Credential = Get-Credential `
            -Message 'Enter remote administrator credentials'

        if (-not $script:Credential) {
            return
        }
    }

    $displayTargets = if (
        [string]::IsNullOrWhiteSpace($txtTargets.Text)
    ) {
        'This local computer'
    } else {
        $targets -join ', '
    }

    $confirmation = @"
Channel: $($channel.DisplayName)

Computers:
$displayTargets

Up to 15 computers will run concurrently.

The tool now checks actual Office executable files instead of depending only on the Click-to-Run registry version.

Continue?
"@

    $answer = [System.Windows.Forms.MessageBox]::Show(
        $confirmation,
        'Confirm Microsoft 365 Update',
        'YesNo',
        'Question'
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Stop-AllTasks

    $script:Results.Clear()
    $script:Tasks.Clear()
    $script:PendingTargets.Clear()
    $gridResults.DataSource = $null

    foreach ($target in $targets) {
        [void]$script:PendingTargets.Add($target)
    }

    $script:TotalTasks = $targets.Count
    $script:CompletedTasks = 0

    $progress.Style = 'Blocks'
    $progress.Minimum = 0
    $progress.Maximum = [Math]::Max(1, $targets.Count)
    $progress.Value = 0

    $lblProgress.Text = "0 of $($targets.Count)"
    $tabs.SelectedTab = $tabLog

    Write-GuiLog ('-' * 78)
    Write-GuiLog "Requested channel: $($channel.DisplayName)"
    Write-GuiLog "Computers: $displayTargets"
    Write-GuiLog "Maximum concurrency: $script:MaximumConcurrency"
    Write-GuiLog "Maximum wait per computer: $($numTimeout.Value) minutes"

    foreach ($target in $targets) {
        Write-GuiLog "$target`: Queued for processing."
    }

    Set-RunningState $true

    try {
        $script:RunspacePool =
            [Management.Automation.Runspaces.RunspaceFactory]::
                CreateRunspacePool(
                    1,
                    $script:MaximumConcurrency
                )

        $script:RunspacePool.Open()

        $credentialToUse = $null

        if ($chkAlternateCredential.Checked) {
            $credentialToUse = $script:Credential
        }

        $script:RunConfiguration = [pscustomobject]@{
            ChannelIdentifier = $channel.Identifier
            ChannelName       = $channel.DisplayName
            ExpectedCdnId     = $channel.CdnId
            ForceClose        = $chkForceClose.Checked
            TimeoutMinutes    = [int]$numTimeout.Value
            Credential        = $credentialToUse
        }

        Start-QueuedTasks
        $script:TaskTimer.Start()
    } catch {
        Write-GuiLog "Unable to start tasks: $($_.Exception.Message)"
        Stop-AllTasks
        $lblStatus.Text = 'Failed'
        $lblStatus.ForeColor = $colorError
        Set-RunningState $false
    }
})

$btnExit.Add_Click({
    $remaining = $script:Tasks.Count +
        $script:PendingTargets.Count

    if ($remaining -gt 0) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "$remaining task(s) are still running or queued. Exit?",
            'Confirm Exit',
            'YesNo',
            'Warning'
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    $script:ClosingApplication = $true
    Stop-AllTasks
    $form.Close()
})

$form.Add_FormClosing({
    Stop-AllTasks
})

#endregion

#region Start

Write-GuiLog 'Microsoft 365 Channel and Update Tool started.'
Write-GuiLog "Automatic activity log: $script:LogPath"
Write-GuiLog 'Actual Office executable versions will be used when available.'
Write-GuiLog 'Registry versions are displayed separately for troubleshooting.'
Write-GuiLog 'Leave the computer list blank to update this local computer.'
Write-GuiLog 'Up to 15 computers will run concurrently.'

[void]$form.ShowDialog()

#endregion