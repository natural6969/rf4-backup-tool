# ══════════════════════════════════════════════════════════════════════════════
#  Grafische Oberfläche (Windows Forms, nutzt core.ps1)
# ══════════════════════════════════════════════════════════════════════════════
# WinForms braucht einen STA-Thread (Windows PowerShell 5.1 ist es, PowerShell 7 standardmäßig nicht) -> neu starten
if ($env:RF4_GUI_NOSHOW -ne '1' -and $PSCommandPath -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process $exe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Lang', $Lang)
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }

Initialize-Lang $Lang

# GUI-eigene Texte
X 'overwrite_q'  '{0} existiert bereits.{1}Überschreiben?' '{0} already exists.{1}Overwrite?' '{0} 已存在。{1}是否覆盖？' '{0} уже существует.{1}Перезаписать?'
X 'sel_account'  'Account:' 'Account:' '账号:' 'Аккаунт:'
X 'scan_hint'    'Das Tool sucht automatisch auf allen Laufwerken nach RF4-Installationen.' 'The tool automatically searches all drives for RF4 installations.' '本工具会自动在所有驱动器上搜索 RF4 安装。' 'Программа автоматически ищет установки RF4 на всех дисках.'
X 'rescan'       'Neu suchen' 'Rescan' '重新扫描' 'Искать заново'
X 'target_none'  'Keine passende Ziel-Installation vorhanden.' 'No suitable target installation available.' '没有合适的目标安装。' 'Подходящая целевая установка отсутствует.'
X 'backup_to'    'Backup-Zielordner:' 'Backup target folder:' '备份目标文件夹:' 'Папка для копии:'
X 'preview'      'Inhalt des Backups:' 'Backup contents:' '备份内容:' 'Содержимое копии:'
X 'undo_hint'    'Ersetzte Dateien werden vorher nach _rf4tool_undo kopiert.' 'Files that get replaced are copied to _rf4tool_undo first.' '被替换的文件会先复制到 _rf4tool_undo。' 'Заменяемые файлы сначала копируются в _rf4tool_undo.'

# ── Schriften / Farben ─────────────────────────────────────────────────────────
$COL_BG     = [System.Drawing.Color]::FromArgb(15, 23, 42)
$COL_CARD   = [System.Drawing.Color]::FromArgb(30, 41, 59)
$COL_SEL    = [System.Drawing.Color]::FromArgb(15, 60, 90)
$COL_BORDER = [System.Drawing.Color]::FromArgb(51, 65, 85)
$COL_ACCENT = [System.Drawing.Color]::FromArgb(6, 182, 212)
$COL_GREEN  = [System.Drawing.Color]::FromArgb(34, 197, 94)
$COL_WARN   = [System.Drawing.Color]::FromArgb(251, 191, 36)
$COL_RED    = [System.Drawing.Color]::FromArgb(239, 68, 68)
$COL_TEXT   = [System.Drawing.Color]::FromArgb(241, 245, 249)
$COL_MUTED  = [System.Drawing.Color]::FromArgb(148, 163, 184)

function Update-Fonts {
    $fam = if ($script:Lang -eq 'zh') { 'Microsoft YaHei UI' } else { 'Segoe UI' }
    $script:FONT_MAIN  = New-Object System.Drawing.Font($fam, 9)
    $script:FONT_BOLD  = New-Object System.Drawing.Font($fam, 9, [System.Drawing.FontStyle]::Bold)
    $script:FONT_TITLE = New-Object System.Drawing.Font($fam, 13, [System.Drawing.FontStyle]::Bold)
    $script:FONT_SMALL = New-Object System.Drawing.Font($fam, 8)
    $script:FONT_MONO  = New-Object System.Drawing.Font($(if ($script:Lang -eq 'zh') { 'Microsoft YaHei UI' } else { 'Consolas' }), 8.5)
}
Update-Fonts

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$W = 140, [int]$H = 34, $BG = $COL_ACCENT, $FG = $COL_BG) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = New-Object System.Drawing.Point($X, $Y); $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.BackColor = $BG; $b.ForeColor = $FG; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.Font = $script:FONT_BOLD; $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}
function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W = 400, [int]$H = 22, $Font = $null, $FG = $COL_TEXT) {
    $l = New-Object System.Windows.Forms.Label
    if (-not $Font) { $Font = $script:FONT_MAIN }
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.Font = $Font; $l.ForeColor = $FG; $l.BackColor = [System.Drawing.Color]::Transparent
    $l.UseMnemonic = $false   # '&' in 'Backup & Migration' nicht verschlucken
    return $l
}
function New-List([int]$X, [int]$Y, [int]$W, [int]$H, $Font = $null) {
    $l = New-Object System.Windows.Forms.ListBox
    if (-not $Font) { $Font = $script:FONT_MAIN }
    $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.BackColor = $COL_CARD; $l.ForeColor = $COL_TEXT; $l.Font = $Font; $l.BorderStyle = 'None'
    return $l
}
function New-Text([int]$X, [int]$Y, [int]$W, [string]$Value) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y); $t.Size = New-Object System.Drawing.Size($W, 24)
    $t.BackColor = $COL_CARD; $t.ForeColor = $COL_TEXT; $t.BorderStyle = 'FixedSingle'; $t.Font = $script:FONT_MAIN; $t.Text = $Value
    return $t
}
function New-Check([string]$Text, [int]$X, [int]$Y, [int]$W, [bool]$Checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Location = New-Object System.Drawing.Point($X, $Y); $c.Size = New-Object System.Drawing.Size($W, 22)
    $c.ForeColor = $COL_TEXT; $c.BackColor = [System.Drawing.Color]::Transparent; $c.Font = $script:FONT_MAIN; $c.Checked = $Checked
    return $c
}
function Show-Msg([string]$Text, [string]$Kind = 'Warning', [string]$Buttons = 'OK') {
    return [System.Windows.Forms.MessageBox]::Show($Text, (T 'app_title'),
        [System.Windows.Forms.MessageBoxButtons]::$Buttons, [System.Windows.Forms.MessageBoxIcon]::$Kind)
}

# ── SHA256 der eigenen Datei ───────────────────────────────────────────────────
function Get-SelfHash {
    try {
        $path = $PSCommandPath
        if ($path -and (Test-Path -LiteralPath $path)) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    } catch { }
    return $null
}

# ── Zustand ────────────────────────────────────────────────────────────────────
$script:state = @{ Installs = $null; Action = ''; Render = $null; Step = 0; LastOpen = ''; Busy = $false }
$script:RunLog = New-Object System.Text.StringBuilder

$script:LogSink = {
    param($lvl, $msg)
    $prefix = switch ($lvl) { 'ok' { '[OK] ' } 'warn' { '[!]  ' } 'err' { '[X]  ' } default { '     ' } }
    [void]$script:RunLog.AppendLine("$prefix$msg")
    if ($script:txtLog) {
        $script:txtLog.AppendText("$prefix$msg`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ── Hauptfenster ───────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(820, 680)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $COL_BG; $form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false; $form.Font = $script:FONT_MAIN

$pHeader = New-Object System.Windows.Forms.Panel
$pHeader.Location = New-Object System.Drawing.Point(0, 0); $pHeader.Size = New-Object System.Drawing.Size(820, 76); $pHeader.BackColor = $COL_CARD
$form.Controls.Add($pHeader)
$lblTitle = New-Label '' 18 10 460 30 $script:FONT_TITLE $COL_ACCENT
$lblSub   = New-Label '' 18 46 480 20 $script:FONT_SMALL $COL_MUTED
$lblHash  = New-Label '' 470 42 330 30 $script:FONT_SMALL $COL_MUTED; $lblHash.TextAlign = 'MiddleRight'; $lblHash.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblLang  = New-Label '' 520 12 90 22 $script:FONT_MAIN $COL_MUTED; $lblLang.TextAlign = 'MiddleRight'
$cmbLang  = New-Object System.Windows.Forms.ComboBox
$cmbLang.DropDownStyle = 'DropDownList'; $cmbLang.Location = New-Object System.Drawing.Point(620, 10); $cmbLang.Size = New-Object System.Drawing.Size(180, 26)
$cmbLang.BackColor = $COL_BG; $cmbLang.ForeColor = $COL_TEXT; $cmbLang.FlatStyle = 'Flat'
foreach ($l in $script:Langs) { [void]$cmbLang.Items.Add($script:LangNames[$l]) }
$pHeader.Controls.AddRange(@($lblTitle, $lblSub, $lblHash, $lblLang, $cmbLang))

$pStepper = New-Object System.Windows.Forms.Panel
$pStepper.Location = New-Object System.Drawing.Point(0, 76); $pStepper.Size = New-Object System.Drawing.Size(820, 36); $pStepper.BackColor = $COL_BG
$form.Controls.Add($pStepper)
$script:stepLabels = @()
for ($i = 0; $i -lt 5; $i++) {
    $sl = New-Label '' (20 + $i * 156) 8 150 22 $script:FONT_SMALL $COL_MUTED; $sl.TextAlign = 'MiddleCenter'
    $pStepper.Controls.Add($sl); $script:stepLabels += $sl
}

$pContent = New-Object System.Windows.Forms.Panel
$pContent.Location = New-Object System.Drawing.Point(0, 112); $pContent.Size = New-Object System.Drawing.Size(820, 460); $pContent.BackColor = $COL_BG
$form.Controls.Add($pContent)

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Location = New-Object System.Drawing.Point(12, 576); $script:txtLog.Size = New-Object System.Drawing.Size(790, 66)
$script:txtLog.Multiline = $true; $script:txtLog.ReadOnly = $true; $script:txtLog.BackColor = $COL_CARD; $script:txtLog.ForeColor = $COL_MUTED
$script:txtLog.Font = $script:FONT_MONO; $script:txtLog.BorderStyle = 'None'; $script:txtLog.ScrollBars = 'Vertical'
$form.Controls.Add($script:txtLog)

$script:selfHash = Get-SelfHash

function Set-Step([int]$step) {
    $script:state.Step = $step
    for ($i = 0; $i -lt 5; $i++) {
        $sl = $script:stepLabels[$i]; $sl.Text = T ('step' + ($i + 1))
        if ($i -eq $step) { $sl.ForeColor = $COL_ACCENT; $sl.Font = $script:FONT_BOLD }
        elseif ($i -lt $step) { $sl.ForeColor = $COL_GREEN; $sl.Font = $script:FONT_SMALL }
        else { $sl.ForeColor = $COL_MUTED; $sl.Font = $script:FONT_SMALL }
    }
}

function Apply-Header {
    $form.Text = (T 'app_title') + ' v' + $script:ToolVersion
    $form.Font = $script:FONT_MAIN
    $lblTitle.Text = T 'app_title'; $lblTitle.Font = $script:FONT_TITLE
    $lblSub.Text = T 'donate'; $lblSub.Font = $script:FONT_SMALL
    $lblLang.Text = T 'language'; $lblLang.Font = $script:FONT_MAIN
    $cmbLang.Font = $script:FONT_MAIN
    if ($script:selfHash) { $lblHash.Text = (T 'hash_label' @($script:selfHash.Substring(0, 16))) + ' ' + (T 'hash_click') }
    else { $lblHash.Text = T 'hash_unknown' }
    $lblHash.Font = $script:FONT_SMALL
    $script:txtLog.Font = $script:FONT_MONO
    Set-Step $script:state.Step
}
$lblHash.Add_Click({
    if ($script:selfHash) {
        [System.Windows.Forms.Clipboard]::SetText($script:selfHash)
        [void](Show-Msg ((T 'hash_copied') + "`n" + $script:selfHash) 'Information')
    }
})

function Show-Panel([scriptblock]$render) {
    $script:state.Render = $render
    $pContent.SuspendLayout()
    while ($pContent.Controls.Count -gt 0) { $c = $pContent.Controls[0]; $pContent.Controls.RemoveAt(0); $c.Dispose() }
    & $render
    $pContent.ResumeLayout()
}

function Set-Language([string]$code) {
    [void](Set-Lang $code)
    try { Save-Lang $script:Lang } catch { }
    Update-Fonts
    $script:suppressLang = $true; $cmbLang.SelectedIndex = [Array]::IndexOf($script:Langs, $script:Lang); $script:suppressLang = $false
    Apply-Header
    if ($script:state.Render) { Show-Panel $script:state.Render }
}
$cmbLang.Add_SelectedIndexChanged({
    if ($script:suppressLang) { return }
    $ix = $cmbLang.SelectedIndex
    if ($ix -ge 0 -and $script:Langs[$ix] -ne $script:Lang) { Set-Language $script:Langs[$ix] }
})

function Get-ExistingInstalls { @($script:state.Installs | Where-Object { $_.Exists }) }

function Confirm-GameClosedGui {
    $run = Test-Rf4Running
    if (-not $run) { return $true }
    return ((Show-Msg ((T 'running_warn' @($run)) + "`n`n" + (T 'running_ask')) 'Warning' 'YesNo') -eq 'Yes')
}
$script:ConfirmOverwrite = { param($name) ((Show-Msg (T 'overwrite_q' @($name, "`n")) 'Warning' 'YesNo') -eq 'Yes') }

function Add-BackBtn([scriptblock]$target) {
    $b = New-Button (T 'back') 18 400 120 34 $COL_BORDER $COL_TEXT
    $script:backTarget = $target
    $b.Add_Click({ Show-Panel $script:backTarget })
    $pContent.Controls.Add($b)
}

# ── Panel 1: Scan ──────────────────────────────────────────────────────────────
function Render-Scan {
    Set-Step 0
    $pContent.Controls.Add((New-Label (T 'hdr_scan') 18 12 600 24 $script:FONT_BOLD $COL_TEXT))
    $pContent.Controls.Add((New-Label (T 'scan_hint') 18 38 780 20 $script:FONT_SMALL $COL_MUTED))
    $lst = New-List 18 64 780 270 $script:FONT_MONO; $lst.SelectionMode = 'None'
    $pContent.Controls.Add($lst)
    $lblP = New-Label (T 'scanning') 18 342 600 20 $script:FONT_SMALL $COL_ACCENT
    $pContent.Controls.Add($lblP)
    $pContent.Controls.Add((New-Label (T 'scan_readonly') 18 366 780 20 $script:FONT_SMALL $COL_GREEN))
    $script:btnScanNext = New-Button (T 'next') 658 400 140 34
    $script:btnScanNext.Enabled = $false
    $script:btnScanNext.Add_Click({ Show-Panel { Render-Action } })
    $pContent.Controls.Add($script:btnScanNext)
    $btnRe = New-Button (T 'rescan') 18 400 150 34 $COL_BORDER $COL_TEXT
    $btnRe.Add_Click({ $script:state.Installs = $null; Show-Panel { Render-Scan } })
    $pContent.Controls.Add($btnRe)
    $form.Update()

    if ($null -eq $script:state.Installs) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $script:state.Installs = @(Find-Installations)
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    $found = 0
    foreach ($i in $script:state.Installs) {
        if ($i.Exists) {
            $info = Get-InstInfo $i.Path
            [void]$lst.Items.Add('[OK]  ' + (Get-InstLabel $i))
            [void]$lst.Items.Add('      ' + (T 'scan_stats' @($info.Mailboxes.Count, $info.Convs)) + $(if ($info.Ids) { '  |  ' + (T 'scan_accounts' @($info.Ids)) } else { '' }))
            [void]$lst.Items.Add('')
            $found++
        } else {
            [void]$lst.Items.Add('[--]  ' + (Get-InstLabel $i) + '  ' + (T 'scan_empty'))
        }
    }
    $lblP.Text = if ($found -gt 0) { T 'found_n' @($found) } else { T 'none_found' }
    $lblP.ForeColor = if ($found -gt 0) { $COL_GREEN } else { $COL_WARN }
    $script:btnScanNext.Enabled = ($found -gt 0)
}

# ── Panel 2: Aktion ────────────────────────────────────────────────────────────
function Render-Action {
    Set-Step 1
    $pContent.Controls.Add((New-Label (T 'what_todo') 18 12 600 24 $script:FONT_BOLD $COL_TEXT))
    $acts = @(@('backup', 'act_backup', 'act_backup_d'), @('restore', 'act_restore', 'act_restore_d'), @('merge', 'act_merge', 'act_merge_d'), @('sync', 'act_sync', 'act_sync_d'))
    $script:cards = @{}
    $y = 46
    foreach ($a in $acts) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(18, $y); $card.Size = New-Object System.Drawing.Size(780, 76)
        $card.BackColor = $(if ($script:state.Action -eq $a[0]) { $COL_SEL } else { $COL_CARD }); $card.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Tag = $a[0]
        $t1 = New-Label (T $a[1]) 14 8 740 22 $script:FONT_BOLD $COL_TEXT; $t1.Tag = $a[0]
        $t2 = New-Label (T $a[2]) 14 32 750 44 $script:FONT_SMALL $COL_MUTED; $t2.Tag = $a[0]
        $card.Controls.AddRange(@($t1, $t2))
        $handler = {
            param($s, $e)
            $script:state.Action = [string]$s.Tag
            foreach ($k in $script:cards.Keys) { $script:cards[$k].BackColor = $(if ($k -eq $script:state.Action) { $COL_SEL } else { $COL_CARD }) }
        }
        $card.Add_Click($handler); $t1.Add_Click($handler); $t2.Add_Click($handler)
        $pContent.Controls.Add($card); $script:cards[$a[0]] = $card
        $y += 84
    }
    Add-BackBtn { Render-Scan }
    $n = New-Button (T 'next') 658 400 140 34
    $n.Add_Click({
        switch ($script:state.Action) {
            'backup'  { Show-Panel { Render-Backup } }
            'restore' { Show-Panel { Render-Restore } }
            'merge'   { Show-Panel { Render-Merge } }
            'sync'    { Show-Panel { Render-Sync } }
            default   { [void](Show-Msg (T 'pick_action')) }
        }
    })
    $pContent.Controls.Add($n)
}

function Add-AccountCombo($boxes, [int]$x, [int]$y) {
    $script:cmbAcct = $null
    $boxes = @($boxes)
    if ($boxes.Count -le 1) { return }
    $pContent.Controls.Add((New-Label (T 'sel_account') $x $y 80 22 $script:FONT_MAIN $COL_MUTED))
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.Location = New-Object System.Drawing.Point(($x + 84), ($y - 2)); $c.Size = New-Object System.Drawing.Size(380, 24)
    $c.BackColor = $COL_CARD; $c.ForeColor = $COL_TEXT; $c.FlatStyle = 'Flat'; $c.Font = $script:FONT_MAIN
    [void]$c.Items.Add((T 'all_accts' @($boxes.Count)))
    foreach ($b in $boxes) { [void]$c.Items.Add((T 'acct_line' @($b.Id, $b.Convs))) }
    $c.SelectedIndex = 0
    $pContent.Controls.Add($c); $script:cmbAcct = $c
    $script:acctBoxes = $boxes
}
function Get-SelectedAccounts {
    if ($script:cmbAcct -and $script:cmbAcct.SelectedIndex -gt 0) { return @($script:acctBoxes[$script:cmbAcct.SelectedIndex - 1].Name) }
    return $null
}

# ── Panel 3a: Backup ───────────────────────────────────────────────────────────
function Render-Backup {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'pick_source') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $script:exSrc = Get-ExistingInstalls
    $lst = New-List 18 34 780 112; foreach ($i in $script:exSrc) { [void]$lst.Items.Add((Get-InstLabel $i)) }
    if ($lst.Items.Count -gt 0) { $lst.SelectedIndex = 0 }
    $pContent.Controls.Add($lst); $script:lstSrc = $lst
    $pContent.Controls.Add((New-Label (T 'what_backup') 18 156 780 22 $script:FONT_BOLD $COL_TEXT))
    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $script:bkKeys = $keys; $script:bkChecks = @()
    $y = 180
    foreach ($k in $keys) {
        $c = New-Check (T ('item_' + $k)) 18 $y 600 ($k -in @('mail', 'Settings.dat', 'Preferences.dat'))
        $pContent.Controls.Add($c); $script:bkChecks += $c; $y += 24
    }
    $script:acctY = $y + 2
    $lst.Add_SelectedIndexChanged({
        if ($script:cmbAcct) { $pContent.Controls.Remove($script:cmbAcct); $script:cmbAcct = $null }
        # Account-Auswahl neu aufbauen
        foreach ($ctl in @($pContent.Controls | Where-Object { $_.Tag -eq 'acctlbl' })) { $pContent.Controls.Remove($ctl) }
        if ($script:lstSrc.SelectedIndex -ge 0) {
            Add-AccountCombo (Get-Mailboxes $script:exSrc[$script:lstSrc.SelectedIndex].Path) 18 $script:acctY
            foreach ($ctl in @($pContent.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq (T 'sel_account') })) { $ctl.Tag = 'acctlbl' }
        }
    })
    if ($lst.SelectedIndex -ge 0) {
        Add-AccountCombo (Get-Mailboxes $script:exSrc[$lst.SelectedIndex].Path) 18 $script:acctY
        foreach ($ctl in @($pContent.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq (T 'sel_account') })) { $ctl.Tag = 'acctlbl' }
    }
    $pContent.Controls.Add((New-Label (T 'backup_to') 18 ($y + 34) 170 22 $script:FONT_MAIN $COL_MUTED))
    $script:txtDir = New-Text 190 ($y + 32) 480 (Get-DefaultBackupDir); $pContent.Controls.Add($script:txtDir)
    $bb = New-Button (T 'btn_browse') 680 ($y + 30) 118 28 $COL_BORDER $COL_TEXT
    $bb.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.SelectedPath = $script:txtDir.Text; if ($fb.ShowDialog() -eq 'OK') { $script:txtDir.Text = $fb.SelectedPath } })
    $pContent.Controls.Add($bb)
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'run_backup') 598 400 200 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        if ($script:lstSrc.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        $items = @(); for ($i = 0; $i -lt $script:bkKeys.Count; $i++) { if ($script:bkChecks[$i].Checked) { $items += $script:bkKeys[$i] } }
        if ($items.Count -eq 0) { [void](Show-Msg (T 'pick_item')); return }
        $src = $script:exSrc[$script:lstSrc.SelectedIndex]
        $dest = $script:txtDir.Text.Trim(); if (-not $dest) { $dest = Get-DefaultBackupDir }
        $acc = Get-SelectedAccounts
        Start-Operation 'hdr_backup' $dest {
            Copy-Rf4Data -SrcDir $src.Path -DstDir $dest -Items $items -Accounts $acc `
                -ShotsSrc (Get-ScreenshotDir $src.Path) -ShotsDst (Join-Path $dest 'Screenshots') -Confirm $script:ConfirmOverwrite
            Write-Log 'ok' 'backup_done' @($dest)
        }
    })
    $pContent.Controls.Add($go)
}

# ── Panel 3b: Restore ──────────────────────────────────────────────────────────
function Update-RestorePreview {
    $script:lstPrev.Items.Clear()
    $dir = $script:txtDir.Text
    if (-not (Test-Path -LiteralPath $dir)) { [void]$script:lstPrev.Items.Add((T 'folder_missing' @($dir))); $script:rsBC = $null; return }
    $bc = Get-BackupContents $dir; $script:rsBC = $bc
    foreach ($m in $bc.Mailboxes) { [void]$script:lstPrev.Items.Add('[OK] ' + (T 'bk_mailbox' @($m.Name, $m.Convs))) }
    foreach ($f in $bc.Files) { [void]$script:lstPrev.Items.Add("[OK] $f") }
    if ($bc.Shots -gt 0) { [void]$script:lstPrev.Items.Add('[OK] ' + (T 'bk_shots' @($bc.Shots))) }
    if ($bc.Empty) { [void]$script:lstPrev.Items.Add('[!]  ' + (T 'no_backup_here')) }
}
function Render-Restore {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'pick_backup') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $pContent.Controls.Add((New-Label (T 'pick_backup_d') 18 32 780 18 $script:FONT_SMALL $COL_MUTED))
    $script:txtDir = New-Text 18 56 650 (Get-DefaultBackupDir); $pContent.Controls.Add($script:txtDir)
    $bb = New-Button (T 'btn_browse') 680 54 118 28 $COL_BORDER $COL_TEXT
    $bb.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.SelectedPath = $script:txtDir.Text; if ($fb.ShowDialog() -eq 'OK') { $script:txtDir.Text = $fb.SelectedPath } })
    $pContent.Controls.Add($bb)
    $pContent.Controls.Add((New-Label (T 'preview') 18 90 500 18 $script:FONT_SMALL $COL_MUTED))
    $script:lstPrev = New-List 18 110 780 110 $script:FONT_MONO; $script:lstPrev.SelectionMode = 'None'; $pContent.Controls.Add($script:lstPrev)
    $pContent.Controls.Add((New-Label (T 'pick_target') 18 228 780 22 $script:FONT_BOLD $COL_TEXT))
    $script:rsIns = @($script:state.Installs)
    $script:lstDst = New-List 18 252 780 100
    foreach ($i in $script:rsIns) { [void]$script:lstDst.Items.Add((Get-InstLabel $i) + $(if (-not $i.Exists) { '  ' + (T 'scan_empty') } else { '' })) }
    $pContent.Controls.Add($script:lstDst)
    $pContent.Controls.Add((New-Label (T 'undo_hint') 18 360 780 18 $script:FONT_SMALL $COL_MUTED))
    $script:txtDir.Add_TextChanged({ Update-RestorePreview })
    Update-RestorePreview
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'run_restore') 598 400 200 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        if (-not $script:rsBC -or $script:rsBC.Empty) { [void](Show-Msg (T 'no_backup_here')); return }
        if ($script:lstDst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dst = $script:rsIns[$script:lstDst.SelectedIndex].Path; $src = $script:txtDir.Text; $bc = $script:rsBC
        $items = @(); if ($bc.Mailboxes.Count -gt 0) { $items += 'mail' }; $items += @($bc.Files); if ($bc.Shots -gt 0) { $items += 'shots' }
        Start-Operation 'hdr_restore' $dst {
            Write-Log 'info' 'importing_to' @($dst)
            Copy-Rf4Data -SrcDir $src -DstDir $dst -Items $items -ShotsSrc (Join-Path $src 'Screenshots') -ShotsDst (Get-ScreenshotDir $dst -Create) `
                -Confirm $script:ConfirmOverwrite -UndoRoot (New-UndoRoot $dst)
            Write-Log 'ok' 'restore_done'
        }
    })
    $pContent.Controls.Add($go)
}

# ── Panel 3c: Merge ────────────────────────────────────────────────────────────
function Render-Merge {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'hdr_merge') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $ex = Get-ExistingInstalls; $script:mgEx = $ex
    if ($ex.Count -lt 2) {
        $pContent.Controls.Add((New-Label (T 'merge_need2') 18 40 780 22 $script:FONT_MAIN $COL_WARN))
        Add-BackBtn { Render-Action }; return
    }
    $pContent.Controls.Add((New-Label (T 'merge_note') 18 32 780 32 $script:FONT_SMALL $COL_WARN))
    $pContent.Controls.Add((New-Label (T 'merge_safe') 18 66 780 18 $script:FONT_SMALL $COL_GREEN))
    $pContent.Controls.Add((New-Label (T 'merge_dst') 18 92 780 20 $script:FONT_BOLD $COL_TEXT))
    $script:lstMgDst = New-List 18 114 780 84; foreach ($i in $ex) { [void]$script:lstMgDst.Items.Add((Get-InstLabel $i)) }
    $pContent.Controls.Add($script:lstMgDst)
    $pContent.Controls.Add((New-Label (T 'merge_src_ctrl') 18 206 780 20 $script:FONT_BOLD $COL_TEXT))
    $script:lstMgSrc = New-List 18 228 780 120; $script:lstMgSrc.SelectionMode = 'MultiExtended'
    foreach ($i in $ex) { [void]$script:lstMgSrc.Items.Add((Get-InstLabel $i)) }
    $pContent.Controls.Add($script:lstMgSrc)
    $pContent.Controls.Add((New-Label (T 'undo_hint') 18 356 780 18 $script:FONT_SMALL $COL_MUTED))
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'run_merge') 598 400 200 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        $d = $script:lstMgDst.SelectedIndex; $s = @($script:lstMgSrc.SelectedIndices)
        if ($d -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        if ($s.Count -eq 0) { [void](Show-Msg (T 'pick_one_src')); return }
        if ($s -contains $d) { [void](Show-Msg (T 'merge_same')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dstPath = $script:mgEx[$d].Path; $srcs = @($s | ForEach-Object { $script:mgEx[$_] }); $undo = New-UndoRoot $dstPath
        Start-Operation 'hdr_merge' $dstPath {
            foreach ($si in $srcs) {
                Write-Log 'info' 'merge_src_hdr' @((Get-InstLabel $si))
                Copy-Rf4Data -SrcDir $si.Path -DstDir $dstPath -Items @('mail') -UndoRoot $undo
            }
            Write-Log 'ok' 'merge_done'
        }
    })
    $pContent.Controls.Add($go)
}

# ── Panel 3d: Sync ─────────────────────────────────────────────────────────────
function Render-Sync {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'hdr_sync') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $pContent.Controls.Add((New-Label (T 'sync_intro') 18 32 780 18 $script:FONT_SMALL $COL_MUTED))
    $pContent.Controls.Add((New-Label (T 'sync_dir_lbl') 18 66 150 22 $script:FONT_MAIN $COL_MUTED))
    $script:txtSync = New-Text 170 64 500 (Get-SyncPath); $pContent.Controls.Add($script:txtSync)
    $bb = New-Button (T 'btn_browse') 680 62 118 28 $COL_BORDER $COL_TEXT
    $bb.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.Description = T 'sync_pick_dir'
        if ($script:txtSync.Text -and (Test-Path -LiteralPath $script:txtSync.Text)) { $fb.SelectedPath = $script:txtSync.Text }
        if ($fb.ShowDialog() -eq 'OK') { $script:txtSync.Text = $fb.SelectedPath; Set-SyncPath $fb.SelectedPath }
    })
    $pContent.Controls.Add($bb)
    $pContent.Controls.Add((New-Label (T 'sync_hint') 170 92 628 18 $script:FONT_SMALL $COL_MUTED))
    $pContent.Controls.Add((New-Label (T 'sync_inst_lbl') 18 124 150 22 $script:FONT_MAIN $COL_MUTED))
    $script:syEx = Get-ExistingInstalls
    $script:lstSyInst = New-List 170 122 628 90; foreach ($i in $script:syEx) { [void]$script:lstSyInst.Items.Add((Get-InstLabel $i)) }
    if ($script:lstSyInst.Items.Count -gt 0) { $script:lstSyInst.SelectedIndex = 0 }
    $pContent.Controls.Add($script:lstSyInst)
    $script:lblSyState = New-Label '' 18 222 780 20 $script:FONT_SMALL $COL_MUTED; $pContent.Controls.Add($script:lblSyState)
    $script:lstSySt = New-List 18 246 780 140 $script:FONT_MONO; $script:lstSySt.SelectionMode = 'None'; $pContent.Controls.Add($script:lstSySt)
    $btnSt = New-Button (T 'sync_status') 146 400 250 34 $COL_BORDER $COL_TEXT
    $btnSt.Add_Click({
        $script:lstSySt.Items.Clear(); $sp = $script:txtSync.Text.Trim()
        if (-not $sp) { $script:lblSyState.Text = T 'sync_none'; return }
        if (-not (Test-Path -LiteralPath $sp)) { $script:lblSyState.Text = T 'sync_unreach' @($sp); return }
        Set-SyncPath $sp; $script:lblSyState.Text = T 'sync_ok' @($sp)
        $st = Get-SyncStatus $sp
        if (-not $st.Exists) { [void]$script:lstSySt.Items.Add((T 'sync_st_nodir')); return }
        if ($st.Mailboxes.Count -eq 0) { [void]$script:lstSySt.Items.Add((T 'sync_st_none')) }
        foreach ($m in $st.Mailboxes) { [void]$script:lstSySt.Items.Add((T 'sync_st_boxes' @($m.Name, $m.Convs))) }
        foreach ($f in $st.Files) { [void]$script:lstSySt.Items.Add("$($f.Name): $($f.Time)") }
        foreach ($l in $st.Log) { [void]$script:lstSySt.Items.Add($l) }
    })
    $pContent.Controls.Add($btnSt)
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'sync_run') 528 400 270 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        $sp = $script:txtSync.Text.Trim()
        if (-not $sp) { [void](Show-Msg (T 'sync_first')); return }
        if (-not (Test-Path -LiteralPath $sp)) { [void](Show-Msg ((T 'sync_unreach' @($sp)) + "`n" + (T 'sync_unreach_h'))); return }
        if ($script:lstSyInst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        Set-SyncPath $sp; $inst = $script:syEx[$script:lstSyInst.SelectedIndex]
        Start-Operation 'hdr_sync' $inst.Path { Invoke-SyncRun -InstPath $inst.Path -SyncBase $sp }
    })
    $pContent.Controls.Add($go)
}

# ── Ausführen + Ergebnis ───────────────────────────────────────────────────────
function Start-Operation([string]$titleKey, [string]$openPath, [scriptblock]$work) {
    if ($script:state.Busy) { return }
    $script:state.Busy = $true
    $script:state.LastOpen = $openPath
    $script:RunLog.Clear() | Out-Null; $script:txtLog.Clear()
    Set-Step 3
    Show-Panel { Set-Step 3; $pContent.Controls.Add((New-Label (T 'working') 18 12 780 24 $script:FONT_BOLD $COL_ACCENT)) }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    try { & $work } catch { Write-Log 'err' 'f_failed' @($titleKey, $_.Exception.Message) }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $script:state.Busy = $false
    $script:state.ResultKey = $titleKey
    Show-Panel { Render-Result }
}
function Render-Result {
    Set-Step 4
    $pContent.Controls.Add((New-Label ((T $script:state.ResultKey) + ' – ' + (T 'result_title')) 18 8 780 24 $script:FONT_BOLD $COL_GREEN))
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(18, 40); $tb.Size = New-Object System.Drawing.Size(780, 340)
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.BackColor = $COL_CARD; $tb.ForeColor = $COL_TEXT
    $tb.Font = $script:FONT_MONO; $tb.BorderStyle = 'None'; $tb.Text = $script:RunLog.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")
    $pContent.Controls.Add($tb)
    $bo = New-Button (T 'btn_open') 18 400 170 34 $COL_BORDER $COL_TEXT
    $bo.Add_Click({ if ($script:state.LastOpen -and (Test-Path -LiteralPath $script:state.LastOpen)) { Start-Process explorer.exe -ArgumentList ('"' + $script:state.LastOpen + '"') } })
    $pContent.Controls.Add($bo)
    $bh = New-Button (T 'btn_home') 598 400 200 34
    $bh.Add_Click({ $script:state.Installs = $null; Show-Panel { Render-Scan } })
    $pContent.Controls.Add($bh)
}

# ── Start ──────────────────────────────────────────────────────────────────────
$script:suppressLang = $true
$cmbLang.SelectedIndex = [Array]::IndexOf($script:Langs, $script:Lang)
$script:suppressLang = $false
Apply-Header
if ($env:RF4_GUI_NOSHOW -ne '1') {
    $form.Add_Shown({ Show-Panel { Render-Scan } })
    [void]$form.ShowDialog()
}
