#Requires -Version 5.1
<#
.SYNOPSIS
    RF4 Standalone Backup & Migration Tool – GUI-Version (Windows Forms)
.DESCRIPTION
    Grafische Benutzeroberfläche für das RF4 SA Backup-Tool.
    Schritt-für-Schritt-Assistent: Scan → Auswahl → Backup/Restore/Merge.
    Keine Originaldateien werden verändert.
.NOTES
    Ausführen: Rechtsklick → "Mit PowerShell ausführen"
    Oder: powershell -ExecutionPolicy Bypass -File rf4sa-backup-gui.ps1
    Blog/Infos:    https://nga.li/rf4b
    Quellcode:     https://nga.li/rf4git  (Codeberg)
    Download:      https://nga.li/rf4dl
    SHA256 verify: Get-FileHash rf4sa-backup-gui.ps1
    Spenden/Donate: https://paypal.me/bjoernoppermann
.LINK
    https://nga.li/rf4b
#>
# Version 1.2.0 – 2026-07-04

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ── Sprache / Language ─────────────────────────────────────────────────────────
$LANG_CODE = switch ((Get-Culture).TwoLetterISOLanguageName.ToLower()) {
    'de' { 'de' }; 'ru' { 'ru' }; 'zh' { 'zh' }; default { 'en' }
}
if ($env:RF4_LANG) { $LANG_CODE = $env:RF4_LANG.ToLower().Substring(0,2) }

$GUI_STRINGS = @{
    'ACTION_BACKUP_TITLE'   = @{ de='Backup erstellen';             en='Create Backup';           ru='Создать резервную копию';          zh='创建备份' }
    'ACTION_BACKUP_DESC'    = @{ de='RF4-Daten (Chats, Einstellungen, Screenshots) in einen Ordner deiner Wahl sichern.'; en='Save RF4 data (chats, settings, screenshots) to a folder of your choice.'; ru='Сохранить данные RF4 (чаты, настройки, скриншоты) в выбранную папку.'; zh='将RF4数据（聊天、设置、截图）保存到您选择的文件夹。' }
    'ACTION_RESTORE_TITLE'  = @{ de='Backup wiederherstellen';      en='Restore Backup';          ru='Восстановить резервную копию';      zh='恢复备份' }
    'ACTION_RESTORE_DESC'   = @{ de='Gesicherte Daten in eine vorhandene RF4-Installation importieren.'; en='Import saved data into an existing RF4 installation.'; ru='Импортировать сохранённые данные в существующую установку RF4.'; zh='将保存的数据导入到现有的RF4安装中。' }
    'ACTION_MERGE_TITLE'    = @{ de='Installationen zusammenführen'; en='Merge Installations';    ru='Объединить установки';              zh='合并安装' }
    'ACTION_MERGE_DESC'     = @{ de='Daten aus einer anderen Installation übertragen – fehlende Nachrichten werden ergänzt, nichts überschrieben.'; en='Transfer data from another installation – missing messages are added, nothing overwritten.'; ru='Перенести данные из другой установки — недостающие сообщения добавляются, ничего не перезаписывается.'; zh='从另一个安装传输数据——添加缺失的消息，不覆盖任何内容。' }
    'ACTION_SYNC_TITLE'     = @{ de='Cloud / NAS Sync';             en='Cloud / NAS Sync';        ru='Синхронизация с облаком/NAS';       zh='云/NAS同步' }
    'ACTION_SYNC_DESC'      = @{ de='Mailboxen zwischen PC und Laptop/NAS synchronisieren – Nextcloud, Syncthing, Netzlaufwerk, USB oder jeder geteilte Ordner.'; en='Sync mailboxes between PC and laptop/NAS – Nextcloud, Syncthing, network drive, USB or any shared folder.'; ru='Синхронизировать почтовые ящики между ПК и ноутбуком/NAS – Nextcloud, Syncthing, сетевой диск, USB или любая общая папка.'; zh='在PC和笔记本/NAS之间同步邮箱——Nextcloud、Syncthing、网络驱动器、USB或任何共享文件夹。' }
    'BTN_BACK'              = @{ de='« Zurück';    en='« Back';    ru='« Назад';    zh='« 返回' }
    'BTN_NEXT'              = @{ de='Weiter »';    en='Next »';    ru='Далее »';    zh='下一步 »' }
    'BTN_START'             = @{ de='Starten »';   en='Start »';   ru='Старт »';    zh='开始 »' }
    'SELECT_ACTION'         = @{ de='Bitte eine Aktion wählen.'; en='Please select an action.'; ru='Пожалуйста, выберите действие.'; zh='请选择一个操作。' }
    'SELECT_SOURCE'         = @{ de='Bitte eine Quelle wählen.'; en='Please select a source.'; ru='Пожалуйста, выберите источник.'; zh='请选择来源。' }
    'DONATE_TEXT'           = @{ de='Spenden: paypal.me/bjoernoppermann'; en='Donate: paypal.me/bjoernoppermann'; ru='Поддержать: paypal.me/bjoernoppermann'; zh='捐赠: paypal.me/bjoernoppermann' }
}
function TG($key) {
    if ($GUI_STRINGS.ContainsKey($key) -and $GUI_STRINGS[$key].ContainsKey($LANG_CODE)) { return $GUI_STRINGS[$key][$LANG_CODE] }
    if ($GUI_STRINGS.ContainsKey($key)) { return $GUI_STRINGS[$key]['en'] }
    return $key
}

$SYNC_CONFIG_DIR = Join-Path $env:APPDATA "rf4-backup"
$SYNC_CONFIG     = Join-Path $SYNC_CONFIG_DIR "sync.conf"
function Get-SyncPath { if (Test-Path $SYNC_CONFIG) { return (Get-Content $SYNC_CONFIG -Raw -EA SilentlyContinue).Trim() }; return "" }
function Set-SyncPath($p) { New-Item -ItemType Directory -Force -Path $SYNC_CONFIG_DIR | Out-Null; Set-Content $SYNC_CONFIG $p -Encoding UTF8 }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Konfiguration ──────────────────────────────────────────────────────────────
$RF4_VARIANTS = @(
    @{ Folder = "RussianFishing4DE";      Label = "RF4 Standalone Deutsch";       Steam = $false },
    @{ Folder = "RussianFishing4DE_new";  Label = "RF4 Standalone Deutsch (neu)"; Steam = $false },
    @{ Folder = "RussianFishing4EN";      Label = "RF4 Standalone Englisch";       Steam = $false },
    @{ Folder = "RussianFishing4Steam";   Label = "RF4 Steam";                     Steam = $true  }
)
$RF4_BASE       = "AppData\Roaming\RussianFishingLLC"
$SCREENSHOT_SUB = "Documents\Russian Fishing 4\Screenshots"
$DEFAULT_BACKUP = "$env:USERPROFILE\RF4_Backup"

# ── Farben / Fonts ─────────────────────────────────────────────────────────────
$COL_BG      = [System.Drawing.Color]::FromArgb(15, 23, 42)
$COL_CARD    = [System.Drawing.Color]::FromArgb(30, 41, 59)
$COL_BORDER  = [System.Drawing.Color]::FromArgb(51, 65, 85)
$COL_ACCENT  = [System.Drawing.Color]::FromArgb(6, 182, 212)
$COL_GREEN   = [System.Drawing.Color]::FromArgb(34, 197, 94)
$COL_WARN    = [System.Drawing.Color]::FromArgb(251, 191, 36)
$COL_RED     = [System.Drawing.Color]::FromArgb(239, 68, 68)
$COL_TEXT    = [System.Drawing.Color]::FromArgb(241, 245, 249)
$COL_MUTED   = [System.Drawing.Color]::FromArgb(148, 163, 184)
$FONT_MAIN   = New-Object System.Drawing.Font("Segoe UI", 9)
$FONT_BOLD   = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$FONT_TITLE  = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$FONT_SMALL  = New-Object System.Drawing.Font("Segoe UI", 8)
$FONT_MONO   = New-Object System.Drawing.Font("Consolas", 8.5)

# ── Helfer: Button erstellen ───────────────────────────────────────────────────
function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W=140, [int]$H=34,
          [System.Drawing.Color]$BG=$COL_ACCENT, [System.Drawing.Color]$FG=$COL_BG)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text; $btn.Location = [System.Drawing.Point]::new($X,$Y)
    $btn.Size = [System.Drawing.Size]::new($W,$H)
    $btn.BackColor = $BG; $btn.ForeColor = $FG; $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.Font = $FONT_BOLD; $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W=400, [int]$H=22,
          [System.Drawing.Font]$Font=$FONT_MAIN,
          [System.Drawing.Color]$FG=$COL_TEXT)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text; $lbl.Location = [System.Drawing.Point]::new($X,$Y)
    $lbl.Size = [System.Drawing.Size]::new($W,$H)
    $lbl.Font = $Font; $lbl.ForeColor = $FG; $lbl.BackColor = [System.Drawing.Color]::Transparent
    return $lbl
}

# ── SHA256 Selbstverifikation ──────────────────────────────────────────────────
function Get-SelfHash {
    try {
        $path = $MyInvocation.ScriptName
        if (-not $path) { $path = $PSCommandPath }
        if ($path -and (Test-Path $path)) {
            $hash = (Get-FileHash $path -Algorithm SHA256).Hash
            return $hash
        }
    } catch {}
    return $null
}

# ── Installationen finden ──────────────────────────────────────────────────────
function Find-Installations {
    $results = [System.Collections.Generic.List[hashtable]]::new()
    $seen    = [System.Collections.Generic.HashSet[string]]::new()

    function Add-Install($label, $path, $type) {
        $norm = $path.TrimEnd('\').ToLower()
        if ($seen.Contains($norm)) { return }
        $null = $seen.Add($norm)
        $results.Add(@{ Label = $label; Path = $path; Type = $type })
    }

    # 1) Lokaler Benutzer
    $userRoot    = [System.IO.Path]::GetDirectoryName($env:APPDATA)
    $driveLetter = $env:APPDATA.Substring(0,2)
    foreach ($v in $RF4_VARIANTS) {
        $p   = Join-Path $userRoot "$RF4_BASE\$($v.Folder)"
        $tag = if ($v.Steam) { " [Steam]" } else { "" }
        Add-Install "$($v.Label)$tag [$driveLetter / $env:USERNAME]" $p "local"
    }

    # 2) Andere Benutzer auf diesem System
    $usersRoot = Split-Path $userRoot -Parent
    foreach ($uDir in (Get-ChildItem $usersRoot -Directory -EA SilentlyContinue)) {
        if ($uDir.Name -in @("Public","Default","Default User","All Users")) { continue }
        if ($uDir.FullName -eq $userRoot) { continue }
        foreach ($v in $RF4_VARIANTS) {
            $p   = Join-Path $uDir.FullName "$RF4_BASE\$($v.Folder)"
            $tag = if ($v.Steam) { " [Steam]" } else { "" }
            Add-Install "$($v.Label)$tag [User: $($uDir.Name)]" $p "other_user"
        }
    }

    # 3) Alle Laufwerke
    $drives = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -in @("Fixed","Removable","Network") -and $_.IsReady }
    foreach ($drv in $drives) {
        $lbl   = if ($drv.VolumeLabel) { $drv.VolumeLabel } else { $drv.Name.TrimEnd('\') }
        $uRoot = Join-Path $drv.RootDirectory.FullName "Users"
        if (-not (Test-Path $uRoot)) { continue }
        foreach ($uDir in (Get-ChildItem $uRoot -Directory -EA SilentlyContinue)) {
            if ($uDir.Name -in @("Public","Default","Default User","All Users")) { continue }
            foreach ($v in $RF4_VARIANTS) {
                $p   = Join-Path $uDir.FullName "$RF4_BASE\$($v.Folder)"
                $tag = if ($v.Steam) { " [Steam]" } else { "" }
                Add-Install "$($v.Label)$tag [Laufwerk: $lbl / $($uDir.Name)]" $p "drive"
            }
        }
    }
    return $results
}

# ── Mailbox mergen ─────────────────────────────────────────────────────────────
function Merge-Mailbox {
    param([string]$SrcDir, [string]$DstDir, [ref]$Log)
    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null
    $merged = 0; $copied = 0

    foreach ($srcFile in (Get-ChildItem $SrcDir -Filter "*.dat" -EA SilentlyContinue)) {
        $dstFile = Join-Path $DstDir $srcFile.Name
        if (-not (Test-Path $dstFile)) {
            Copy-Item $srcFile.FullName $dstFile; $copied++
        } else {
            try {
                $s = Get-Content $srcFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $d = Get-Content $dstFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $seenIds = @{}; foreach ($item in $d.items) { $seenIds[$item.meta.id] = $true }
                $extra = $s.items | Where-Object { -not $seenIds.ContainsKey($_.meta.id) }
                $d.items = @($d.items) + @($extra) |
                    Sort-Object { try { [long]$_.meta.created } catch { 0 } }
                $d | ConvertTo-Json -Depth 20 | Set-Content $dstFile -Encoding UTF8
                $Log.Value += "  + $($srcFile.Name): $($extra.Count) neue Nachrichten`n"
                $merged++
            } catch {
                $Log.Value += "  ! Merge fehlgeschlagen: $($srcFile.Name)`n"
            }
        }
    }
    $Log.Value += "  Mailbox: $merged gemergt, $copied neu kopiert`n"
}

# ════════════════════════════════════════════════════════════════════════════════
# HAUPT-FENSTER
# ════════════════════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$form.Text = "RF4 Backup & Migration Tool v1.2"
$form.Size = [System.Drawing.Size]::new(780, 620)
$form.StartPosition = "CenterScreen"
$form.BackColor = $COL_BG
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.Font = $FONT_MAIN

# ── Panel: Header ─────────────────────────────────────────────────────────────
$pHeader = New-Object System.Windows.Forms.Panel
$pHeader.Location = [System.Drawing.Point]::new(0,0)
$pHeader.Size = [System.Drawing.Size]::new(780,72)
$pHeader.BackColor = $COL_CARD
$form.Controls.Add($pHeader)

$lblTitle = New-Label "RF4 Backup & Migration" 18 14 400 30 $FONT_TITLE $COL_ACCENT
$pHeader.Controls.Add($lblTitle)

$lblSub = New-Label "Backup, Restore, Merge, Sync – $(TG 'DONATE_TEXT')" 18 46 700 18 $FONT_SMALL $COL_MUTED
$pHeader.Controls.Add($lblSub)

# SHA256 self-hash anzeigen
$selfHash = Get-SelfHash
$hashText = if ($selfHash) { "SHA256: $($selfHash.Substring(0,16))…" } else { "SHA256: (Pfad unbekannt)" }
$lblHash = New-Label $hashText 590 14 175 18 $FONT_SMALL $COL_MUTED
$lblHash.TextAlign = "MiddleRight"
$pHeader.Controls.Add($lblHash)
$lblHashFull = New-Label "(Klicken zum Kopieren)" 590 30 175 14 (New-Object System.Drawing.Font("Segoe UI",7)) $COL_MUTED
$lblHashFull.TextAlign = "MiddleRight"; $lblHashFull.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblHashFull.Add_Click({ if ($selfHash) { [System.Windows.Forms.Clipboard]::SetText($selfHash); [System.Windows.Forms.MessageBox]::Show("SHA256-Hash kopiert:`n$selfHash","Prüfsumme",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) } })
$pHeader.Controls.Add($lblHashFull)

# ── Panel: Stepper ─────────────────────────────────────────────────────────────
$pStepper = New-Object System.Windows.Forms.Panel
$pStepper.Location = [System.Drawing.Point]::new(0,72)
$pStepper.Size = [System.Drawing.Size]::new(780,40)
$pStepper.BackColor = $COL_BG
$form.Controls.Add($pStepper)

$STEPS = @("1. Scan","2. Aktion","3. Quelle","4. Optionen","5. Fertig")
$stepLabels = @()
for ($i=0; $i -lt $STEPS.Count; $i++) {
    $lbl = New-Label $STEPS[$i] (20+$i*148) 10 140 22 $FONT_SMALL $COL_MUTED
    $lbl.TextAlign = "MiddleCenter"
    $pStepper.Controls.Add($lbl)
    $stepLabels += $lbl
}

function Set-Step {
    param([int]$Step)
    for ($i=0; $i -lt $stepLabels.Count; $i++) {
        if ($i -eq $Step) { $stepLabels[$i].ForeColor = $COL_ACCENT; $stepLabels[$i].Font = $FONT_BOLD }
        elseif ($i -lt $Step) { $stepLabels[$i].ForeColor = $COL_GREEN; $stepLabels[$i].Font = $FONT_SMALL }
        else { $stepLabels[$i].ForeColor = $COL_MUTED; $stepLabels[$i].Font = $FONT_SMALL }
    }
}

# ── Panel: Content-Bereich ────────────────────────────────────────────────────
$pContent = New-Object System.Windows.Forms.Panel
$pContent.Location = [System.Drawing.Point]::new(0,112)
$pContent.Size = [System.Drawing.Size]::new(780,430)
$pContent.BackColor = $COL_BG
$form.Controls.Add($pContent)

# ── Log-Box unten ─────────────────────────────────────────────────────────────
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = [System.Drawing.Point]::new(12,542)
$txtLog.Size = [System.Drawing.Size]::new(756,50)
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true
$txtLog.BackColor = $COL_CARD; $txtLog.ForeColor = $COL_MUTED
$txtLog.Font = $FONT_MONO; $txtLog.BorderStyle = "None"
$txtLog.ScrollBars = "Vertical"
$form.Controls.Add($txtLog)

function Add-Log {
    param([string]$msg, [string]$type="info")
    $prefix = switch($type) { "ok" {"[OK] "} "warn" {"[!]  "} "err" {"[X]  "} default {"     "} }
    $txtLog.AppendText("$prefix$msg`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

# ════════════════════════════════════════════════════════════════════════════════
# SCHRITT-PANELS
# ════════════════════════════════════════════════════════════════════════════════

# ── globaler Zustand ──────────────────────────────────────────────────────────
$state = @{
    Installs    = $null
    Action      = ""       # backup / restore / merge
    SrcIndex    = -1
    DstIndex    = -1
    SrcPath     = ""
    DstPath     = ""
    BackupDir   = $DEFAULT_BACKUP
    SelItems    = @()
    MergeIdx    = @()
}

# ────────────────────────────────────────────────────────────────────
# PANEL 1: SCAN
# ────────────────────────────────────────────────────────────────────
function Show-ScanPanel {
    $pContent.Controls.Clear()
    Set-Step 0

    $lbl = New-Label "RF4-Installationen suchen" 18 12 500 24 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lbl)

    $lblInfo = New-Label "Das Tool sucht automatisch auf allen Laufwerken nach RF4-Installationen." 18 38 680 18 $FONT_SMALL $COL_MUTED
    $pContent.Controls.Add($lblInfo)

    # Ergebnis-ListBox
    $lstBox = New-Object System.Windows.Forms.ListBox
    $lstBox.Location = [System.Drawing.Point]::new(18,62)
    $lstBox.Size = [System.Drawing.Size]::new(740,260)
    $lstBox.BackColor = $COL_CARD; $lstBox.ForeColor = $COL_TEXT
    $lstBox.Font = $FONT_MONO; $lstBox.BorderStyle = "None"
    $lstBox.SelectionMode = "None"
    $pContent.Controls.Add($lstBox)

    # Fortschritts-Label
    $lblProgress = New-Label "Suche läuft…" 18 330 400 20 $FONT_SMALL $COL_ACCENT
    $pContent.Controls.Add($lblProgress)

    # Scannen im Hintergrund
    $form.Update()
    $installs = Find-Installations
    $state.Installs = $installs

    $lstBox.Items.Clear()
    $found = 0
    foreach ($inst in $installs) {
        if (Test-Path $inst.Path) {
            $mboxDirs = Get-ChildItem $inst.Path -Directory -Filter "Mailbox_*" -EA SilentlyContinue
            $mboxes   = $mboxDirs.Count
            $convs    = (Get-ChildItem $inst.Path -Recurse -Filter "*.dat" -EA SilentlyContinue |
                         Where-Object { $_.DirectoryName -match "Mailbox_" }).Count
            $accIds   = ($mboxDirs | ForEach-Object { $_.Name -replace '^Mailbox_','' }) -join ', '
            $lstBox.Items.Add("[OK]  $($inst.Label)")
            $lstBox.Items.Add("      Mailboxen: $mboxes  |  Nachrichten: $convs  |  Accounts: $accIds")
            $lstBox.Items.Add("")
            $found++
        } else {
            $lstBox.Items.Add("[--]  $($inst.Label)  (noch nicht vorhanden)")
        }
    }
    $lblProgress.Text = if ($found -gt 0) { "Gefunden: $found Installation(en)" } else { "Keine Installationen gefunden." }
    $lblProgress.ForeColor = if ($found -gt 0) { $COL_GREEN } else { $COL_WARN }

    # Sicherheits-Hinweis
    $lblSafe = New-Label "Sicher: Das Tool liest nur – keine Originaldaten werden verändert." 18 358 620 18 $FONT_SMALL $COL_GREEN
    $pContent.Controls.Add($lblSafe)

    $btnNext = New-Button (TG 'BTN_NEXT') 600 390 140 34 $COL_ACCENT $COL_BG
    $btnNext.Enabled = ($found -gt 0)
    $btnNext.Add_Click({ Show-ActionPanel })
    $pContent.Controls.Add($btnNext)
}

# ────────────────────────────────────────────────────────────────────
# PANEL 2: AKTION WÄHLEN
# ────────────────────────────────────────────────────────────────────
function Show-ActionPanel {
    $pContent.Controls.Clear()
    Set-Step 1

    $lbl = New-Label "Was möchtest du tun?" 18 12 500 24 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lbl)

    $actions = @(
        @{ Key="backup";  Title=(TG 'ACTION_BACKUP_TITLE');  Desc=(TG 'ACTION_BACKUP_DESC') },
        @{ Key="restore"; Title=(TG 'ACTION_RESTORE_TITLE'); Desc=(TG 'ACTION_RESTORE_DESC') },
        @{ Key="merge";   Title=(TG 'ACTION_MERGE_TITLE');   Desc=(TG 'ACTION_MERGE_DESC') },
        @{ Key="sync";    Title=(TG 'ACTION_SYNC_TITLE');    Desc=(TG 'ACTION_SYNC_DESC') }
    )

    $y = 50
    $selectedAction = ""
    $btns = @()

    foreach ($a in $actions) {
        $pCard = New-Object System.Windows.Forms.Panel
        $pCard.Location = [System.Drawing.Point]::new(18,$y)
        $pCard.Size = [System.Drawing.Size]::new(740,88)
        $pCard.BackColor = $COL_CARD; $pCard.Cursor = [System.Windows.Forms.Cursors]::Hand

        $lTitle = New-Label $a.Title 14 10 540 22 $FONT_BOLD $COL_TEXT
        $lTitle.BackColor = [System.Drawing.Color]::Transparent
        $pCard.Controls.Add($lTitle)

        $lDesc = New-Label $a.Desc 14 34 700 36 $FONT_SMALL $COL_MUTED
        $lDesc.BackColor = [System.Drawing.Color]::Transparent
        $pCard.Controls.Add($lDesc)

        $key = $a.Key
        $clickHandler = [System.EventHandler]{
            param($s,$e)
            $state.Action = $key
            foreach ($b2 in $btns) { $b2.BackColor = $COL_CARD }
            $s.BackColor = [System.Drawing.Color]::FromArgb(15,40,70)
            $lBorder.ForeColor = $COL_ACCENT
        }.GetNewClosure()

        # Closure for key
        $keyCapture = $key
        $pCard.Add_Click({
            param($s,$e)
            $state.Action = $keyCapture
            foreach ($b2 in $script:btns) { $b2.BackColor = $COL_CARD }
            $s.BackColor = [System.Drawing.Color]::FromArgb(15,40,70)
        })
        foreach ($child in $pCard.Controls) {
            $child.Add_Click({
                param($s,$e)
                $state.Action = $keyCapture
                foreach ($b2 in $script:btns) { $b2.BackColor = $COL_CARD }
                $s.Parent.BackColor = [System.Drawing.Color]::FromArgb(15,40,70)
            })
        }

        $pContent.Controls.Add($pCard)
        $btns += $pCard
        $y += 98
    }
    $script:btns = $btns

    $btnBack = New-Button (TG 'BTN_BACK') 18 390 120 34 $COL_BORDER $COL_TEXT
    $btnBack.Add_Click({ Show-ScanPanel })
    $pContent.Controls.Add($btnBack)

    $btnNext = New-Button (TG 'BTN_NEXT') 600 390 140 34 $COL_ACCENT $COL_BG
    $btnNext.Add_Click({
        if (-not $state.Action) { [System.Windows.Forms.MessageBox]::Show((TG 'SELECT_ACTION'),"RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        switch ($state.Action) {
            "backup"  { Show-SourcePanel "backup" }
            "restore" { Show-RestoreSourcePanel }
            "merge"   { Show-MergePanel }
            "sync"    { Show-SyncPanel }
        }
    })
    $pContent.Controls.Add($btnNext)
}

# ────────────────────────────────────────────────────────────────────
# PANEL 3a: BACKUP – Quelle wählen
# ────────────────────────────────────────────────────────────────────
function Show-SourcePanel {
    $pContent.Controls.Clear()
    Set-Step 2

    $lbl = New-Label "Quelle wählen – Von welcher Installation sichern?" 18 12 680 24 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lbl)

    $existing = @($state.Installs | Where-Object { Test-Path $_.Path })

    $lstSrc = New-Object System.Windows.Forms.ListBox
    $lstSrc.Location = [System.Drawing.Point]::new(18,44)
    $lstSrc.Size = [System.Drawing.Size]::new(740,200)
    $lstSrc.BackColor = $COL_CARD; $lstSrc.ForeColor = $COL_TEXT
    $lstSrc.Font = $FONT_MAIN; $lstSrc.BorderStyle = "None"
    foreach ($inst in $existing) { $lstSrc.Items.Add($inst.Label) | Out-Null }
    $pContent.Controls.Add($lstSrc)

    # Was sichern?
    $lblWhat = New-Label "Was soll gesichert werden? (Mehrfachauswahl)" 18 258 500 22 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lblWhat)

    $checkItems = @("Mailboxen (private Nachrichten)", "Settings.dat (Grafik/Audio/Tasten)", "Preferences.dat", "Crafting.dat", "Screenshots")
    $checks = @()
    $y = 284
    foreach ($ci in $checkItems) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $ci; $cb.Location = [System.Drawing.Point]::new(18,$y)
        $cb.Size = [System.Drawing.Size]::new(400,22)
        $cb.ForeColor = $COL_TEXT; $cb.BackColor = [System.Drawing.Color]::Transparent
        $cb.Font = $FONT_MAIN; $cb.Checked = ($ci -match "Mailboxen|Settings")
        $pContent.Controls.Add($cb); $checks += $cb; $y += 26
    }

    # Backup-Zielordner
    $lblDir = New-Label "Backup-Zielordner:" 18 $y 200 20 $FONT_MAIN $COL_MUTED
    $pContent.Controls.Add($lblDir)
    $txtDir = New-Object System.Windows.Forms.TextBox
    $txtDir.Location = [System.Drawing.Point]::new(170,$y)
    $txtDir.Size = [System.Drawing.Size]::new(460,22)
    $txtDir.BackColor = $COL_CARD; $txtDir.ForeColor = $COL_TEXT
    $txtDir.BorderStyle = "None"; $txtDir.Font = $FONT_MAIN
    $txtDir.Text = $DEFAULT_BACKUP
    $pContent.Controls.Add($txtDir)
    $btnBrowse = New-Button "…" 640 ($y-2) 48 26 $COL_BORDER $COL_TEXT
    $btnBrowse.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.SelectedPath = $txtDir.Text
        if ($fb.ShowDialog() -eq "OK") { $txtDir.Text = $fb.SelectedPath }
    })
    $pContent.Controls.Add($btnBrowse)

    $btnBack = New-Button (TG 'BTN_BACK') 18 390 120 34 $COL_BORDER $COL_TEXT
    $btnBack.Add_Click({ Show-ActionPanel })
    $pContent.Controls.Add($btnBack)

    $btnStart = New-Button "Backup starten" 560 390 180 34 $COL_GREEN $COL_BG
    $btnStart.Add_Click({
        if ($lstSrc.SelectedIndex -lt 0) { [System.Windows.Forms.MessageBox]::Show("Bitte eine Quelle wählen.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        $sel = @($checks | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
        if ($sel.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Bitte mindestens eine Option wählen.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        $state.SrcPath   = $existing[$lstSrc.SelectedIndex].Path
        $state.BackupDir = $txtDir.Text
        $state.SelItems  = $sel
        Do-Backup
    })
    $pContent.Controls.Add($btnStart)
}

# ────────────────────────────────────────────────────────────────────
# BACKUP AUSFÜHREN
# ────────────────────────────────────────────────────────────────────
function Do-Backup {
    Show-ProgressPanel "Backup läuft…"

    $src  = $state.SrcPath
    $dest = $state.BackupDir
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $log = ""

    foreach ($s in $state.SelItems) {
        switch -Wildcard ($s) {
            "Mailboxen*" {
                $mboxDirs = @(Get-ChildItem $src -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
                if ($mboxDirs.Count -eq 0) { $log += "[!] Keine Mailboxen gefunden`n"; break }
                foreach ($mbox in $mboxDirs) {
                    $log += "Mailbox $($mbox.Name)…`n"
                    Merge-Mailbox $mbox.FullName (Join-Path $dest $mbox.Name) ([ref]$log)
                }
            }
            "Settings*" {
                $f = Join-Path $src "Settings.dat"; $d = Join-Path $dest "Settings.dat"
                if (-not (Test-Path $f)) { $log += "[!] Settings.dat nicht gefunden`n"; break }
                if ((Test-Path $d)) {
                    $ow = [System.Windows.Forms.MessageBox]::Show(
                        "Settings.dat existiert bereits im Backup.`nÜberschreiben?",
                        "RF4 Tool – Warnung",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning)
                    if ($ow -eq "Yes") { Copy-Item $f $d -Force; $log += "[OK] Settings.dat überschrieben`n" }
                    else { $log += "     Settings.dat übersprungen`n" }
                } else { Copy-Item $f $dest; $log += "[OK] Settings.dat`n" }
            }
            "Preferences*" {
                $f = Join-Path $src "Preferences.dat"; $d = Join-Path $dest "Preferences.dat"
                if (-not (Test-Path $f)) { $log += "[!] Preferences.dat nicht gefunden`n"; break }
                if ((Test-Path $d)) {
                    $ow = [System.Windows.Forms.MessageBox]::Show("Preferences.dat existiert bereits.`nÜberschreiben?","RF4 Tool – Warnung",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
                    if ($ow -eq "Yes") { Copy-Item $f $d -Force; $log += "[OK] Preferences.dat überschrieben`n" }
                    else { $log += "     Preferences.dat übersprungen`n" }
                } else { Copy-Item $f $dest; $log += "[OK] Preferences.dat`n" }
            }
            "Crafting*" {
                $f = Join-Path $src "Crafting.dat"; $d = Join-Path $dest "Crafting.dat"
                if (-not (Test-Path $f)) { $log += "[!] Crafting.dat nicht gefunden`n"; break }
                if ((Test-Path $d)) {
                    $ow = [System.Windows.Forms.MessageBox]::Show("Crafting.dat existiert bereits.`nÜberschreiben?","RF4 Tool – Warnung",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
                    if ($ow -eq "Yes") { Copy-Item $f $d -Force; $log += "[OK] Crafting.dat überschrieben`n" }
                    else { $log += "     Crafting.dat übersprungen`n" }
                } else { Copy-Item $f $dest; $log += "[OK] Crafting.dat`n" }
            }
            "Screenshots*" {
                $uDir = $src; for ($i=0;$i -lt 4;$i++){$uDir=Split-Path $uDir -Parent}
                $shotSrc = Join-Path $uDir $SCREENSHOT_SUB
                if (Test-Path $shotSrc) {
                    $shotDst = Join-Path $dest "Screenshots"
                    New-Item -ItemType Directory -Force -Path $shotDst | Out-Null
                    $cnt = 0
                    foreach ($img in (Get-ChildItem $shotSrc -Include "*.png","*.jpg" -Recurse -EA SilentlyContinue)) {
                        $t = Join-Path $shotDst $img.Name
                        if (-not (Test-Path $t)) { Copy-Item $img.FullName $t; $cnt++ }
                    }
                    $log += "[OK] Screenshots: $cnt Bilder`n"
                } else { $log += "[!] Screenshot-Ordner nicht gefunden`n" }
            }
        }
    }

    Show-ResultPanel "Backup abgeschlossen" $log $dest
}

# ────────────────────────────────────────────────────────────────────
# PANEL 3b: RESTORE – Backup-Ordner wählen
# ────────────────────────────────────────────────────────────────────
function Show-RestoreSourcePanel {
    $pContent.Controls.Clear()
    Set-Step 2

    $lbl = New-Label "Backup-Ordner wählen" 18 12 500 24 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lbl)

    $lblInfo = New-Label "Wähle den Ordner, der dein RF4-Backup enthält." 18 38 600 18 $FONT_SMALL $COL_MUTED
    $pContent.Controls.Add($lblInfo)

    $txtDir = New-Object System.Windows.Forms.TextBox
    $txtDir.Location = [System.Drawing.Point]::new(18,68)
    $txtDir.Size = [System.Drawing.Size]::new(640,24)
    $txtDir.BackColor = $COL_CARD; $txtDir.ForeColor = $COL_TEXT
    $txtDir.BorderStyle = "None"; $txtDir.Font = $FONT_MAIN
    $txtDir.Text = $DEFAULT_BACKUP
    $pContent.Controls.Add($txtDir)

    $btnBrowse = New-Button "…" 668 66 60 26 $COL_BORDER $COL_TEXT
    $btnBrowse.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.SelectedPath = $txtDir.Text
        if ($fb.ShowDialog() -eq "OK") { $txtDir.Text = $fb.SelectedPath }
    })
    $pContent.Controls.Add($btnBrowse)

    # Vorschau
    $lblPreview = New-Label "Inhalt (nach Ordnerauswahl):" 18 102 400 18 $FONT_SMALL $COL_MUTED
    $pContent.Controls.Add($lblPreview)

    $lstPreview = New-Object System.Windows.Forms.ListBox
    $lstPreview.Location = [System.Drawing.Point]::new(18,122)
    $lstPreview.Size = [System.Drawing.Size]::new(740,160)
    $lstPreview.BackColor = $COL_CARD; $lstPreview.ForeColor = $COL_TEXT
    $lstPreview.Font = $FONT_MONO; $lstPreview.BorderStyle = "None"
    $lstPreview.SelectionMode = "None"
    $pContent.Controls.Add($lstPreview)

    function Update-Preview {
        $lstPreview.Items.Clear()
        $src = $txtDir.Text
        if (-not (Test-Path $src)) { $lstPreview.Items.Add("Ordner nicht gefunden: $src"); return }
        $mboxes = Get-ChildItem $src -Directory -Filter "Mailbox_*" -EA SilentlyContinue
        if ($mboxes) {
            foreach ($m in $mboxes) {
                $cnt = (Get-ChildItem $m.FullName -Filter "*.dat" -EA SilentlyContinue).Count
                $lstPreview.Items.Add("[OK] $($m.Name)  –  $cnt Gespräche")
            }
        }
        foreach ($f in @("Settings.dat","Preferences.dat","Crafting.dat")) {
            if (Test-Path (Join-Path $src $f)) { $lstPreview.Items.Add("[OK] $f") }
        }
        $shots = (Get-ChildItem (Join-Path $src "Screenshots") -EA SilentlyContinue).Count
        if ($shots -gt 0) { $lstPreview.Items.Add("[OK] Screenshots: $shots Dateien") }
        if ($lstPreview.Items.Count -eq 0) { $lstPreview.Items.Add("[!]  Kein RF4-Backup in diesem Ordner gefunden.") }
    }

    $txtDir.Add_TextChanged({ Update-Preview })
    Update-Preview

    # Ziel-Installation wählen
    $lblDst = New-Label "Ziel-Installation:" 18 292 300 20 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lblDst)

    $existing = @($state.Installs | Where-Object { Test-Path $_.Path })
    $lstDst = New-Object System.Windows.Forms.ListBox
    $lstDst.Location = [System.Drawing.Point]::new(18,314)
    $lstDst.Size = [System.Drawing.Size]::new(740,70)
    $lstDst.BackColor = $COL_CARD; $lstDst.ForeColor = $COL_TEXT
    $lstDst.Font = $FONT_MAIN; $lstDst.BorderStyle = "None"
    foreach ($i in $existing) { $lstDst.Items.Add($i.Label) | Out-Null }
    $pContent.Controls.Add($lstDst)

    $btnBack = New-Button (TG 'BTN_BACK') 18 390 120 34 $COL_BORDER $COL_TEXT
    $btnBack.Add_Click({ Show-ActionPanel })
    $pContent.Controls.Add($btnBack)

    $btnNext = New-Button (TG 'BTN_NEXT') 600 390 140 34 $COL_ACCENT $COL_BG
    $btnNext.Add_Click({
        if (-not (Test-Path $txtDir.Text)) { [System.Windows.Forms.MessageBox]::Show("Backup-Ordner nicht gefunden.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        if ($lstDst.SelectedIndex -lt 0) { [System.Windows.Forms.MessageBox]::Show("Bitte Ziel-Installation wählen.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        $state.BackupDir = $txtDir.Text
        $state.DstPath   = $existing[$lstDst.SelectedIndex].Path
        Do-Restore
    })
    $pContent.Controls.Add($btnNext)
}

# ────────────────────────────────────────────────────────────────────
# RESTORE AUSFÜHREN
# ────────────────────────────────────────────────────────────────────
function Do-Restore {
    Show-ProgressPanel "Restore läuft…"
    $src = $state.BackupDir
    $dst = $state.DstPath
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $log = ""

    $mboxes = @(Get-ChildItem $src -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
    foreach ($mbox in $mboxes) {
        $log += "Mailbox $($mbox.Name)…`n"
        Merge-Mailbox $mbox.FullName (Join-Path $dst $mbox.Name) ([ref]$log)
    }
    foreach ($f in @("Settings.dat","Preferences.dat","Crafting.dat")) {
        $srcF = Join-Path $src $f; $dstF = Join-Path $dst $f
        if (Test-Path $srcF) {
            if (Test-Path $dstF) {
                $ow = [System.Windows.Forms.MessageBox]::Show(
                    "$f existiert bereits in der Zielinstallation.`nÜberschreiben?`n`nOriginal wird NICHT gelöscht — nur ersetzt.",
                    "RF4 Tool – Überschreiben?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($ow -eq "Yes") { Copy-Item $srcF $dstF -Force; $log += "[OK] $f überschrieben`n" }
                else { $log += "     $f übersprungen`n" }
            } else { Copy-Item $srcF $dstF; $log += "[OK] $f importiert`n" }
        }
    }
    $shots = (Get-ChildItem (Join-Path $src "Screenshots") -EA SilentlyContinue).Count
    if ($shots -gt 0) {
        $uDir = $dst; for ($i=0;$i -lt 4;$i++){$uDir=Split-Path $uDir -Parent}
        $shotDst = Join-Path $uDir $SCREENSHOT_SUB
        New-Item -ItemType Directory -Force -Path $shotDst | Out-Null
        $cnt = 0
        foreach ($img in (Get-ChildItem (Join-Path $src "Screenshots") -Include "*.png","*.jpg" -EA SilentlyContinue)) {
            $t = Join-Path $shotDst $img.Name
            if (-not (Test-Path $t)) { Copy-Item $img.FullName $t; $cnt++ }
        }
        $log += "[OK] Screenshots: $cnt Bilder → $shotDst`n"
    }
    Show-ResultPanel "Restore abgeschlossen" $log $dst
}

# ────────────────────────────────────────────────────────────────────
# PANEL 3c: MERGE
# ────────────────────────────────────────────────────────────────────
function Show-MergePanel {
    $pContent.Controls.Clear()
    Set-Step 2

    $lbl = New-Label "Installationen zusammenführen" 18 12 500 24 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lbl)

    $lblWarn = New-Label "HINWEIS: Nur fehlende Nachrichten werden hinzugefügt. Keine vorhandenen Daten werden überschrieben." 18 40 720 36 $FONT_SMALL $COL_GREEN
    $lblWarn.AutoSize = $false
    $pContent.Controls.Add($lblWarn)

    $existing = @($state.Installs | Where-Object { Test-Path $_.Path })
    if ($existing.Count -lt 2) {
        $lbl2 = New-Label "Mindestens 2 vorhandene Installationen nötig." 18 80 500 22 $FONT_MAIN $COL_WARN
        $pContent.Controls.Add($lbl2)
        $btnBack = New-Button (TG 'BTN_BACK') 18 390 120 34 $COL_BORDER $COL_TEXT
        $btnBack.Add_Click({ Show-ActionPanel }); $pContent.Controls.Add($btnBack)
        return
    }

    $lblDst = New-Label "Ziel (Hauptinstallation, bleibt erhalten):" 18 82 500 20 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lblDst)
    $lstDst = New-Object System.Windows.Forms.ListBox
    $lstDst.Location = [System.Drawing.Point]::new(18,104)
    $lstDst.Size = [System.Drawing.Size]::new(740,80)
    $lstDst.BackColor = $COL_CARD; $lstDst.ForeColor = $COL_TEXT; $lstDst.Font = $FONT_MAIN; $lstDst.BorderStyle = "None"
    foreach ($i in $existing) { $lstDst.Items.Add($i.Label) | Out-Null }
    $pContent.Controls.Add($lstDst)

    $lblSrc = New-Label "Quellen (Strg+Klick für Mehrfachauswahl):" 18 196 500 20 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lblSrc)
    $lstSrc = New-Object System.Windows.Forms.ListBox
    $lstSrc.Location = [System.Drawing.Point]::new(18,218)
    $lstSrc.Size = [System.Drawing.Size]::new(740,120)
    $lstSrc.BackColor = $COL_CARD; $lstSrc.ForeColor = $COL_TEXT; $lstSrc.Font = $FONT_MAIN; $lstSrc.BorderStyle = "None"
    $lstSrc.SelectionMode = "MultiExtended"
    foreach ($i in $existing) { $lstSrc.Items.Add($i.Label) | Out-Null }
    $pContent.Controls.Add($lstSrc)

    $btnBack = New-Button (TG 'BTN_BACK') 18 390 120 34 $COL_BORDER $COL_TEXT
    $btnBack.Add_Click({ Show-ActionPanel }); $pContent.Controls.Add($btnBack)

    $btnStart = New-Button "Merge starten" 560 390 180 34 $COL_GREEN $COL_BG
    $btnStart.Add_Click({
        $dstIdx = $lstDst.SelectedIndex
        $srcIdxs = @($lstSrc.SelectedIndices)
        if ($dstIdx -lt 0) { [System.Windows.Forms.MessageBox]::Show("Bitte Ziel-Installation wählen.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        if ($srcIdxs.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Bitte mindestens eine Quelle wählen.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }
        if ($srcIdxs -contains $dstIdx) { [System.Windows.Forms.MessageBox]::Show("Quelle und Ziel dürfen nicht identisch sein.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return }

        Show-ProgressPanel "Merge läuft…"
        $log = ""
        $dst = $existing[$dstIdx].Path
        New-Item -ItemType Directory -Force -Path $dst | Out-Null

        foreach ($si in $srcIdxs) {
            $srcPath = $existing[$si].Path
            $log += "=== Quelle: $($existing[$si].Label)`n"
            $mboxDirs = @(Get-ChildItem $srcPath -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
            if ($mboxDirs.Count -eq 0) { $log += "[!] Keine Mailboxen gefunden`n"; continue }
            foreach ($mbox in $mboxDirs) {
                $log += "Mailbox $($mbox.Name)…`n"
                Merge-Mailbox $mbox.FullName (Join-Path $dst $mbox.Name) ([ref]$log)
            }
        }
        Show-ResultPanel "Merge abgeschlossen" $log $dst
    })
    $pContent.Controls.Add($btnStart)
}

# ────────────────────────────────────────────────────────────────────
# PANEL 3d: SYNC
# ────────────────────────────────────────────────────────────────────
function Show-SyncPanel {
    $pContent.Controls.Clear()
    Set-Step 2

    $lbl = New-Label "Cloud / NAS Sync" 18 12 500 24 $FONT_BOLD $COL_TEXT
    $pContent.Controls.Add($lbl)

    $lblInfo = New-Label "Synchronisiert Mailboxen bidirektional zwischen diesem PC und dem Sync-Ordner." 18 38 700 18 $FONT_SMALL $COL_MUTED
    $pContent.Controls.Add($lblInfo)

    # Sync-Ordner Zeile
    $lblDir = New-Label "Sync-Ordner:" 18 72 110 22 $FONT_MAIN $COL_MUTED
    $pContent.Controls.Add($lblDir)

    $txtSync = New-Object System.Windows.Forms.TextBox
    $txtSync.Location = [System.Drawing.Point]::new(130,70)
    $txtSync.Size = [System.Drawing.Size]::new(518,24)
    $txtSync.BackColor = $COL_CARD; $txtSync.ForeColor = $COL_TEXT
    $txtSync.BorderStyle = "None"; $txtSync.Font = $FONT_MAIN
    $txtSync.Text = (Get-SyncPath)
    $pContent.Controls.Add($txtSync)

    $btnBrowse = New-Button "…" 656 68 60 26 $COL_BORDER $COL_TEXT
    $btnBrowse.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = "Sync-Ordner wählen (z.B. Nextcloud-Ordner oder NAS-Laufwerk)"
        if ($txtSync.Text -and (Test-Path $txtSync.Text)) { $fb.SelectedPath = $txtSync.Text }
        if ($fb.ShowDialog() -eq "OK") { $txtSync.Text = $fb.SelectedPath; Set-SyncPath $fb.SelectedPath; Update-SyncStatus }
    })
    $pContent.Controls.Add($btnBrowse)

    # Hinweis-Text
    $lblHint = New-Label "Nextcloud-Ordner  ·  NAS-Netzlaufwerk (N:\)  ·  Syncthing-Ordner  ·  USB-Stick" 130 96 550 18 (New-Object System.Drawing.Font("Segoe UI",7.5)) $COL_MUTED
    $pContent.Controls.Add($lblHint)

    # Installation wählen
    $lblInst = New-Label "Installation:" 18 126 110 22 $FONT_MAIN $COL_MUTED
    $pContent.Controls.Add($lblInst)

    $existing = @($state.Installs | Where-Object { Test-Path $_.Path })
    $lstInst = New-Object System.Windows.Forms.ComboBox
    $lstInst.Location = [System.Drawing.Point]::new(130,124)
    $lstInst.Size = [System.Drawing.Size]::new(586,24)
    $lstInst.BackColor = $COL_CARD; $lstInst.ForeColor = $COL_TEXT
    $lstInst.Font = $FONT_MAIN; $lstInst.FlatStyle = "Flat"; $lstInst.DropDownStyle = "DropDownList"
    foreach ($i in $existing) { $lstInst.Items.Add($i.Label) | Out-Null }
    if ($lstInst.Items.Count -gt 0) { $lstInst.SelectedIndex = 0 }
    $pContent.Controls.Add($lstInst)

    # Status-Box
    $lblStatus = New-Label "Sync-Ordner Status:" 18 162 200 18 $FONT_SMALL $COL_MUTED
    $pContent.Controls.Add($lblStatus)

    $lstStatus = New-Object System.Windows.Forms.ListBox
    $lstStatus.Location = [System.Drawing.Point]::new(18,182)
    $lstStatus.Size = [System.Drawing.Size]::new(740,148)
    $lstStatus.BackColor = $COL_CARD; $lstStatus.ForeColor = $COL_TEXT
    $lstStatus.Font = $FONT_MONO; $lstStatus.BorderStyle = "None"; $lstStatus.SelectionMode = "None"
    $pContent.Controls.Add($lstStatus)

    function Update-SyncStatus {
        $lstStatus.Items.Clear()
        $p = $txtSync.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($p)) { $lstStatus.Items.Add("Kein Sync-Ordner angegeben."); return }
        if (-not (Test-Path $p)) { $lstStatus.Items.Add("[!]  Ordner nicht erreichbar: $p"); return }
        $syncDir = Join-Path $p "RF4_Sync"
        if (-not (Test-Path $syncDir)) { $lstStatus.Items.Add("[OK] Ordner erreichbar. Noch kein RF4_Sync-Unterordner – wird beim ersten Sync angelegt."); return }
        $mboxes = @(Get-ChildItem $syncDir -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
        if ($mboxes.Count -eq 0) {
            $lstStatus.Items.Add("[OK] Sync-Ordner vorhanden. Noch keine Mailboxen gespeichert.")
        } else {
            foreach ($m in $mboxes) {
                $cnt = (Get-ChildItem $m.FullName -Filter "*.dat" -EA SilentlyContinue).Count
                $lstStatus.Items.Add("[OK] $($m.Name)  –  $cnt Konversationen")
            }
        }
        foreach ($dat in @("Settings.dat","Preferences.dat","Crafting.dat")) {
            $f = Join-Path $syncDir $dat
            if (Test-Path $f) { $lstStatus.Items.Add("[OK] $dat  ($(((Get-Item $f).LastWriteTime).ToString('yyyy-MM-dd HH:mm')))") }
        }
        $logFile = Join-Path $syncDir ".sync_log"
        if (Test-Path $logFile) {
            $last = Get-Content $logFile | Select-Object -Last 1
            if ($last) { $lstStatus.Items.Add("     Letzter Sync: $last") }
        }
    }

    $txtSync.Add_TextChanged({ Update-SyncStatus })
    Update-SyncStatus

    $btnRefresh = New-Button "Status aktualisieren" 18 338 180 28 $COL_BORDER $COL_TEXT
    $btnRefresh.Add_Click({ Update-SyncStatus })
    $pContent.Controls.Add($btnRefresh)

    $btnBack = New-Button (TG 'BTN_BACK') 18 390 120 34 $COL_BORDER $COL_TEXT
    $btnBack.Add_Click({ Show-ActionPanel })
    $pContent.Controls.Add($btnBack)

    $btnSync = New-Button "Sync starten" 570 390 170 34 $COL_GREEN $COL_BG
    $btnSync.Add_Click({
        $syncPath = $txtSync.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($syncPath)) {
            [System.Windows.Forms.MessageBox]::Show("Bitte Sync-Ordner angeben.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return
        }
        if (-not (Test-Path $syncPath)) {
            [System.Windows.Forms.MessageBox]::Show("Sync-Ordner nicht erreichbar:`n$syncPath`n`nNAS eingebunden? Cloud-Sync aktiv?","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return
        }
        if ($lstInst.SelectedIndex -lt 0) {
            [System.Windows.Forms.MessageBox]::Show("Bitte Installation auswählen.","RF4 Tool",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning); return
        }
        Set-SyncPath $syncPath
        $instPath = $existing[$lstInst.SelectedIndex].Path
        Do-SyncRunGUI -InstPath $instPath -SyncBase $syncPath
    })
    $pContent.Controls.Add($btnSync)
}

function Do-SyncRunGUI {
    param([string]$InstPath, [string]$SyncBase)
    Show-ProgressPanel "Sync läuft…"
    $syncDir = Join-Path $SyncBase "RF4_Sync"
    New-Item -ItemType Directory -Force -Path $syncDir | Out-Null
    $log = "Lokal:  $InstPath`nSync:   $syncDir`n`n"

    # Phase 1: Lokal → Sync
    $log += "=== Phase 1: Lokal -> Sync (hochladen) ===`n"
    $localMboxes = @(Get-ChildItem $InstPath -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
    if ($localMboxes.Count -gt 0) {
        foreach ($mbox in $localMboxes) {
            $log += "Up $($mbox.Name)...`n"
            Merge-Mailbox $mbox.FullName (Join-Path $syncDir $mbox.Name) ([ref]$log)
        }
    } else { $log += "[!] Keine lokalen Mailboxen – nur Pull.`n" }

    # Phase 2: Sync → Lokal
    $log += "`n=== Phase 2: Sync -> Lokal (herunterladen) ===`n"
    $syncMboxes = @(Get-ChildItem $syncDir -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
    if ($syncMboxes.Count -gt 0) {
        foreach ($mbox in $syncMboxes) {
            $log += "Down $($mbox.Name)...`n"
            Merge-Mailbox $mbox.FullName (Join-Path $InstPath $mbox.Name) ([ref]$log)
        }
    } else { $log += "[!] Noch keine Mailboxen von anderen Geräten im Sync-Ordner.`n" }

    # Settings: neuere Version gewinnt
    $log += "`n=== Einstellungen (neuere Version gewinnt) ===`n"
    foreach ($dat in @("Settings.dat","Preferences.dat","Crafting.dat")) {
        $lf = Join-Path $InstPath $dat; $sf = Join-Path $syncDir $dat
        $hasL = Test-Path $lf; $hasS = Test-Path $sf
        if ($hasL -and -not $hasS) {
            Copy-Item $lf $sf; $log += "[OK] $dat -> Sync (neu hochgeladen)`n"
        } elseif (-not $hasL -and $hasS) {
            Copy-Item $sf $lf; $log += "[OK] $dat <- Sync (neu heruntergeladen)`n"
        } elseif ($hasL -and $hasS) {
            $lt = (Get-Item $lf).LastWriteTimeUtc; $st = (Get-Item $sf).LastWriteTimeUtc
            if    ($lt -gt $st) { Copy-Item $lf $sf -Force; $log += "[OK] $dat -> Sync (lokal neuer)`n" }
            elseif ($st -gt $lt){ Copy-Item $sf $lf -Force; $log += "[OK] $dat <- Sync (Sync neuer)`n" }
            else                 { $log += "     ${dat}: identisch, übersprungen`n" }
        }
    }

    $logLine = "$(([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:mm:ssZ')) $env:COMPUTERNAME"
    Add-Content (Join-Path $syncDir ".sync_log") $logLine -Encoding UTF8

    Show-ResultPanel "Sync abgeschlossen" $log $syncDir
}

# ────────────────────────────────────────────────────────────────────
# PANEL: FORTSCHRITT
# ────────────────────────────────────────────────────────────────────
function Show-ProgressPanel {
    param([string]$msg)
    $pContent.Controls.Clear()
    Set-Step 3
    $lbl = New-Label $msg 18 180 740 30 $FONT_TITLE $COL_ACCENT
    $lbl.TextAlign = "MiddleCenter"
    $pContent.Controls.Add($lbl)
    $form.Update()
}

# ────────────────────────────────────────────────────────────────────
# PANEL 5: FERTIG / ERGEBNIS
# ────────────────────────────────────────────────────────────────────
function Show-ResultPanel {
    param([string]$Title, [string]$Log, [string]$Path)
    $pContent.Controls.Clear()
    Set-Step 4

    $lblTitle = New-Label $Title 18 12 500 28 $FONT_TITLE $COL_GREEN
    $pContent.Controls.Add($lblTitle)

    if ($Path) {
        $lblPath = New-Label "Speicherort: $Path" 18 44 720 18 $FONT_SMALL $COL_MUTED
        $pContent.Controls.Add($lblPath)
        $btnOpen = New-Button "Ordner öffnen" 560 38 180 28 $COL_BORDER $COL_TEXT
        $btnOpen.Add_Click({ if (Test-Path $Path) { Start-Process explorer.exe $Path } })
        $pContent.Controls.Add($btnOpen)
    }

    $lblSafe = New-Label "Originaldaten wurden nicht verändert – nur Kopien wurden erstellt." 18 68 680 18 $FONT_SMALL $COL_GREEN
    $pContent.Controls.Add($lblSafe)

    $txtResult = New-Object System.Windows.Forms.TextBox
    $txtResult.Location = [System.Drawing.Point]::new(18,94)
    $txtResult.Size = [System.Drawing.Size]::new(740,280)
    $txtResult.Multiline = $true; $txtResult.ReadOnly = $true; $txtResult.ScrollBars = "Vertical"
    $txtResult.BackColor = $COL_CARD; $txtResult.ForeColor = $COL_TEXT
    $txtResult.Font = $FONT_MONO; $txtResult.BorderStyle = "None"
    $txtResult.Text = $Log
    $pContent.Controls.Add($txtResult)

    $btnNew = New-Button "Nochmal" 18 390 140 34 $COL_BORDER $COL_TEXT
    $btnNew.Add_Click({ Show-ScanPanel })
    $pContent.Controls.Add($btnNew)

    $btnClose = New-Button "Fertig & Schließen" 580 390 160 34 $COL_ACCENT $COL_BG
    $btnClose.Add_Click({ $form.Close() })
    $pContent.Controls.Add($btnClose)
}

# ── Start ─────────────────────────────────────────────────────────────────────
Show-ScanPanel
[System.Windows.Forms.Application]::Run($form)
