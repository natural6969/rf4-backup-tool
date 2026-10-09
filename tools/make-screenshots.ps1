#Requires -Version 5.1
<#
.SYNOPSIS
    Erzeugt die Screenshots für README/Anleitung: je Sprache (de, en, zh, ru) dieselben Bilder, mit ausgedachten Demo-Daten.
.DESCRIPTION
    Baut ein Demo-Profil (Benutzer "Angler", zwei Installationen, mehrere Backups, NAS-Sync-Ordner) auf einem per `subst`
    eingebundenen Laufwerk (Standard R:), damit die Pfade in den Bildern sauber aussehen. Es werden KEINE echten Daten verwendet.
    Ausgabe: <OutDir>\<sprache>\<design>-<panel>.png     (Standard OutDir = docs\img)
.EXAMPLE
    powershell -STA -ExecutionPolicy Bypass -File tools\make-screenshots.ps1
#>
param([string]$OutDir = '', [string]$Drive = 'R', [double]$Scale = 1.25)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'docs\img' }
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing

if ((Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue)) { throw "Laufwerk ${Drive}: ist belegt – bitte -Drive <Buchstabe> angeben." }
$demoRoot = Join-Path ([IO.Path]::GetTempPath()) ('rf4demo_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $demoRoot | Out-Null
& subst.exe "${Drive}:" $demoRoot | Out-Null
$D = "${Drive}:"

# ── Demo-Daten (ausgedachte Texte) ─────────────────────────────────────────────
$texts = @('Petri Heil! Wie läuft es am Fluss?', 'Hast du den Karpfen auf Boilies gefangen?', 'Heute Abend Turnier?', 'Danke für den Tipp mit dem Vorfach!', 'Gleich geht es los.', 'Die Hechte beißen am Steg.', 'Bis später am See.', 'Nice catch!', 'Treffen wir uns am Nordufer?', 'Ich brauche noch Köder.')
$rnd = New-Object System.Random 42
function New-Conv([string]$path, [int]$id, [int]$count, [string]$prefix) {
    $items = for ($i = 0; $i -lt $count; $i++) {
        [pscustomobject]@{ meta = [pscustomobject]@{ id = ('{0}-{1}-{2}' -f $prefix, $id, $i); created = (133292355165425967 + $i * 6000000000 + $id); sender = $(if ($i % 2) { 309850 } else { $id }); type = 0; text = $texts[$rnd.Next($texts.Count)]; items = @() }; status = 1281 }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path, ([pscustomobject]@{ id = $id; items = @($items) } | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($true)))
}
$user = "$D\Users\Angler"; $base = "$user\AppData\Roaming\RussianFishingLLC"
$steam = "$base\RussianFishing4Steam"; $de = "$base\RussianFishing4DE"
foreach ($c in 1..9) { New-Conv "$steam\Mailbox_309850\$($c * 111 + 7).dat" ($c * 111 + 7) (6 + $c) 'S' }
foreach ($c in 1..4) { New-Conv "$steam\Mailbox_555123\$($c * 97 + 3).dat" ($c * 97 + 3) (4 + $c) 'S' }
foreach ($c in 1..5) { New-Conv "$de\Mailbox_309850\$($c * 111 + 7).dat" ($c * 111 + 7) (3 + $c) 'S' }      # überlappt mit Steam, teils kürzer
Set-Content "$steam\Settings.dat" 'steam-settings'; Set-Content "$steam\Preferences.dat" 'steam-prefs'; Set-Content "$de\Settings.dat" 'de-settings'
New-Item -ItemType Directory -Force -Path "$user\Documents\Russian Fishing 4\Screenshots" | Out-Null; 1..6 | ForEach-Object { Set-Content "$user\Documents\Russian Fishing 4\Screenshots\rf4_$_.png" 'x' }

$env:APPDATA = "$user\AppData\Roaming"; $env:USERPROFILE = $user; $env:USERNAME = 'Angler'; $env:COMPUTERNAME = 'ANGLER-PC'
$env:RF4_NO_DRIVE_SCAN = '1'; $env:RF4_GUI_NOSHOW = '1'; $env:RF4_THEME_BASE = 'dark'; $env:RF4_GUI_SCALE = [string]$Scale; $env:RF4_LANG = 'de'

try {
    $ver = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'src\core.ps1')), "ToolVersion = '([\d\.]+)'").Groups[1].Value
    . (Join-Path $root "rf4sa-backup-gui-v$ver.ps1") -Lang de
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    function Pump { [System.Windows.Forms.Application]::DoEvents() }
    function Walk($ctl) { foreach ($c in $ctl.Controls) { $c; Walk $c } }
    function Card-Index($cards, [string]$folder) { for ($i = 0; $i -lt $cards.Count; $i++) { if ($cards[$i].Tag2 -and $cards[$i].Tag2.Folder -eq $folder) { return $i } }; return -1 }
    $script:ConfirmOverwrite = { param($n) $true }

    # Backups mit Quelle/Datum + Sync-Ordner anlegen (über die echte Programmlogik, Zeitstempel danach geschönt)
    $insts = @(Find-Installations)
    $iSteam = @($insts | Where-Object { $_.Folder -eq 'RussianFishing4Steam' })[0]; $iDe = @($insts | Where-Object { $_.Folder -eq 'RussianFishing4DE' })[0]
    Reset-Stats
    $bk1 = "$user\RF4_Backup"; Copy-Rf4Data -SrcDir $steam -DstDir $bk1 -Items @('mail', 'Settings.dat', 'Preferences.dat') -Confirm { $true }
    Write-BackupInfo $bk1 $iSteam @('mail', 'Settings.dat', 'Preferences.dat')
    $bk2 = "$D\Backups\USB-Stick\RF4_Laptop-2026"; Copy-Rf4Data -SrcDir $de -DstDir $bk2 -Items @('mail', 'Settings.dat') -Confirm { $true }
    $env:COMPUTERNAME = 'ALTER-LAPTOP'; Write-BackupInfo $bk2 $iDe @('mail', 'Settings.dat'); $env:COMPUTERNAME = 'ANGLER-PC'
    foreach ($f in @("$bk2\rf4-backup.info")) { $t = [IO.File]::ReadAllText($f) -replace '(?m)^created=.*$', 'created=2026-06-14 20:15' -replace '(?m)^updated=.*$', 'updated=2026-08-30 22:40' -replace '(?m)^history=.*\r?\n', ''; [IO.File]::WriteAllText($f, $t) }
    foreach ($f in Get-ChildItem $bk2 -Recurse -File) { $f.LastWriteTime = [datetime]'2026-08-30 22:40' }
    $nas = "$D\NAS\RF4-Sync"; New-Item -ItemType Directory -Force -Path $nas | Out-Null
    Invoke-SyncRun -InstPath $de -SyncBase $nas
    Set-SyncPath $nas; Add-BackupDir "$D\Backups\USB-Stick"
    $script:state.Installs = $null

    $outRoot = $OutDir; New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
    function Snap([string]$lang, [string]$name) {
        Pump; Start-Sleep -Milliseconds 150; Pump
        $dir = Join-Path $outRoot $lang; New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $full = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($full, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $o = $form.PointToScreen([System.Drawing.Point]::Empty); $dx = $o.X - $form.Left; $dy = $o.Y - $form.Top
        $bmp = $full.Clone((New-Object System.Drawing.Rectangle($dx, $dy, $form.ClientSize.Width, $form.ClientSize.Height)), $full.PixelFormat); $full.Dispose()
        $bmp.Save((Join-Path $dir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
    $form.ClientSize = New-Object System.Drawing.Size((S 1000), (S 740)); Pump

    foreach ($lang in 'de', 'en', 'zh', 'ru') {
        foreach ($theme in 'dark', 'light') {
            Save-ThemeChoice $theme; [void](Set-Lang $lang); Save-Lang $lang; Rebuild-All; Pump
            $script:state.Installs = $null; $script:state.Action = 'backup'
            $dark = ($theme -eq 'dark')
            if ($dark) { Show-Panel { Render-Scan }; Pump; Snap $lang "$theme-scan" }
            Show-Panel { Render-Action }; Pump; Snap $lang "$theme-action"

            if ($dark) {
                Show-Panel { Render-Backup }; Pump
                $script:lstSrc.Cards[(Card-Index $script:lstSrc.Cards 'RussianFishing4Steam')].PerformClick()
                foreach ($c in $script:bkChecks) { $c.Checked = ($c.Text -notmatch 'Crafting') }; Pump; Snap $lang "$theme-backup"
            }

            Show-Panel { Render-Restore }; Pump
            $script:lstBk.SelectedIndex = 0
            $script:lstDst.Cards[(Card-Index $script:lstDst.Cards 'RussianFishing4DE')].PerformClick(); Pump; Snap $lang "$theme-restore"

            if ($dark) {
                Show-Panel { Render-Merge }; Pump
                $script:lstMgDst.Cards[(Card-Index $script:lstMgDst.Cards 'RussianFishing4DE')].PerformClick()
                $script:lstMgSrc.Cards[(Card-Index $script:lstMgSrc.Cards 'RussianFishing4Steam')].PerformClick(); Pump; Snap $lang "$theme-merge"
                Show-Panel { Render-Sync }; Pump
                $script:lstSyInst.Cards[(Card-Index $script:lstSyInst.Cards 'RussianFishing4DE')].PerformClick(); $script:btnExtra.PerformClick(); Pump; Snap $lang "$theme-sync"
            }

            # Ergebnis: echtes Backup von Steam in einen neuen Ordner
            $script:state.Action = 'backup'; Show-Panel { Render-Backup }; Pump
            $script:lstSrc.Cards[(Card-Index $script:lstSrc.Cards 'RussianFishing4Steam')].PerformClick()
            foreach ($c in $script:bkChecks) { $c.Checked = ($c.Text -notmatch 'Crafting') }
            $script:inDir.Text = "$D\Out\Steam_$lang-$theme"; $script:btnPrimary.PerformClick(); Pump; Pump
            Snap $lang "$theme-result"
            $cfg = Get-Config; $cfg.backupDirs = @("$D\Backups\USB-Stick"); Save-Config $cfg   # Ergebnis-Ordner nicht in der Backup-Liste der nächsten Bilder
        }
    }
    $form.Close()
    $n = @(Get-ChildItem $outRoot -Recurse -Filter '*.png').Count
    Write-Host "$n Screenshots in $outRoot" -ForegroundColor Green
}
finally {
    try { $form.Dispose() } catch { }
    & subst.exe "${Drive}:" /d | Out-Null
    [IO.Directory]::Delete($demoRoot, $true)
}
