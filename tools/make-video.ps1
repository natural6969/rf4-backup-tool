#Requires -Version 5.1
<#
.SYNOPSIS
    Nimmt ein Vorführvideo des Programms auf (Demo-Daten, KEINE echten Dateien) und schreibt Videoscript + Untertitel dazu.
.DESCRIPTION
    Baut dasselbe Demo-Profil wie make-screenshots.ps1 (Benutzer "Angler" auf einem subst-Laufwerk), startet die GUI darin,
    arbeitet die Szenen unten ab und nimmt NUR den Bereich des Programmfensters + eine Untertitelleiste mit ffmpeg (gdigrab) auf.
    Es ist kein anderes Fenster und kein echter Pfad im Bild. Pro Szene bleibt genug Zeit zum Lesen (Dauer ~ Textlänge).
    Ausgabe (OutDir, Standard docs\video): rf4-backup-tool-<lang>.mp4, .srt (Untertitel), videoscript-<lang>.md (Sprechertext mit Zeitmarken)
.EXAMPLE
    powershell -STA -ExecutionPolicy Bypass -File tools\make-video.ps1 -Lang de
#>
param([string]$Lang = 'de', [string]$OutDir = '', [string]$Drive = 'R', [double]$Pace = 1.0, [int]$Fps = 20, [switch]$NoRecord)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'docs\video' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { $ffmpeg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe' }
if (-not $NoRecord -and -not (Test-Path $ffmpeg)) { throw 'ffmpeg nicht gefunden (winget install Gyan.FFmpeg).' }
if (Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue) { throw "Laufwerk ${Drive}: ist belegt – bitte -Drive angeben." }

# ── Sprechertexte je Sprache (Szene → Text). Dauer ergibt sich aus der Länge. ──
$VT = @{
 de = @{
  intro   = 'RF4 Backup & Migration – sichert, stellt wieder her, führt zusammen und synchronisiert Chats, Einstellungen und Screenshots von Russian Fishing 4.'
  head    = 'Oben rechts: Hilfe mit der Anleitung in deiner Sprache, Sprachwahl und Design – Dunkel oder Hell, automatisch nach Windows.'
  scan    = 'Schritt 1: Das Programm findet alle Installationen – Standalone, Steam, Wine und Proton, auch bei anderen Benutzern und Laufwerken.'
  action  = 'Vier Aktionen: Sichern, Wiederherstellen, Zusammenführen und Synchronisieren.'
  bk1     = 'Sichern: Quelle wählen – hier die Steam-Installation.'
  bk2     = 'Dann festlegen, was gesichert wird: Chats, Einstellungen, Screenshots. Das Ziel ist ein frei wählbarer Ordner.'
  bk3     = 'Fertig: Die Kennzahlen zeigen, wie viele Nachrichten, Dialoge und Dateien übertragen wurden.'
  rs1     = 'Wiederherstellen: Alle gefundenen Backups werden aufgelistet – mit Quelle (welche Installation, welcher PC) und Datum.'
  rs2     = 'Auch der Sync-Ordner vom NAS erscheint in der Liste und lässt sich direkt wiederherstellen.'
  rs3     = 'Ziel-Installation wählen, alles Vorhandene ist vorausgewählt. Ersetzte Dateien landen vorher in einem Undo-Ordner.'
  rs4     = 'Der Import ist durch. Es wird nichts gelöscht.'
  mg1     = 'Zusammenführen: Nachrichten mehrerer Installationen werden vereint – nur fehlende werden ergänzt, nichts doppelt.'
  mg2     = 'Ergebnis: neue Nachrichten, zusammengeführte Dialoge.'
  sy1     = 'Synchronisieren über Cloud oder NAS: ein gemeinsamer Ordner für alle deine Geräte.'
  sy2     = 'Der Status zeigt, was im Sync-Ordner liegt und welcher PC zuletzt synchronisiert hat.'
  sy3     = 'Beim Abgleich wird in beide Richtungen zusammengeführt – bei Einstellungen gewinnt die neuere Datei.'
  langs   = 'Die Sprache lässt sich jederzeit umschalten, ohne Neustart: Deutsch, English, 中文, Русский – weitere als einfache Textdatei.'
  theme   = 'Und das helle Design – genauso scharf, auch bei hoher Bildschirmauflösung.'
  outro   = 'Hilfe-Knopf oder [H] im Terminal öffnen die Anleitung mit Screenshots in der Programmsprache. Viel Spaß beim Angeln!'
 }
 en = @{
  intro   = 'RF4 Backup & Migration – back up, restore, merge and sync chats, settings and screenshots of Russian Fishing 4.'
  head    = 'Top right: help with the guide in your language, language switch and theme – dark or light, automatic with Windows.'
  scan    = 'Step 1: the tool finds all installations – Standalone, Steam, Wine and Proton, also for other users and drives.'
  action  = 'Four actions: back up, restore, merge and sync.'
  bk1     = 'Back up: choose the source – here the Steam installation.'
  bk2     = 'Then pick what to save: chats, settings, screenshots. The target is any folder you like.'
  bk3     = 'Done: the figures show how many messages, conversations and files were transferred.'
  rs1     = 'Restore: all backups found are listed – with source (which installation, which PC) and date.'
  rs2     = 'The sync folder from your NAS shows up in the list too and can be restored directly.'
  rs3     = 'Choose the target installation; everything available is preselected. Replaced files go to an undo folder first.'
  rs4     = 'Import finished. Nothing is ever deleted.'
  mg1     = 'Merge: messages from several installations are combined – only missing ones are added, no duplicates.'
  mg2     = 'Result: new messages, merged conversations.'
  sy1     = 'Sync via cloud or NAS: one shared folder for all your devices.'
  sy2     = 'The status shows what is in the sync folder and which PC synced last.'
  sy3     = 'The sync merges in both directions – for settings the newer file wins.'
  langs   = 'The language can be switched at any time without a restart: Deutsch, English, 中文, Русский – more via a plain text file.'
  theme   = 'And the light theme – just as sharp, even on high-resolution screens.'
  outro   = 'The help button or [H] in the terminal opens the guide with screenshots in the program language. Tight lines!'
 }
}
if (-not $VT.ContainsKey($Lang)) { throw "Videotexte nur für: $($VT.Keys -join ', ')" }
$V = $VT[$Lang]

# ── Demo-Profil (ausgedachte Daten, wie make-screenshots.ps1) ──
$demoRoot = Join-Path ([IO.Path]::GetTempPath()) ('rf4vid_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $demoRoot | Out-Null
& subst.exe "${Drive}:" $demoRoot | Out-Null
$D = "${Drive}:"
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
foreach ($c in 1..5) { New-Conv "$de\Mailbox_309850\$($c * 111 + 7).dat" ($c * 111 + 7) (3 + $c) 'S' }
Set-Content "$steam\Settings.dat" 'steam-settings'; Set-Content "$steam\Preferences.dat" 'steam-prefs'; Set-Content "$de\Settings.dat" 'de-settings'
New-Item -ItemType Directory -Force -Path "$user\Documents\Russian Fishing 4\Screenshots" | Out-Null; 1..6 | ForEach-Object { Set-Content "$user\Documents\Russian Fishing 4\Screenshots\rf4_$_.png" 'x' }

$env:APPDATA = "$user\AppData\Roaming"; $env:USERPROFILE = $user; $env:USERNAME = 'Angler'; $env:COMPUTERNAME = 'ANGLER-PC'
$env:RF4_NO_DRIVE_SCAN = '1'; $env:RF4_GUI_NOSHOW = '1'; $env:RF4_THEME_BASE = 'dark'; $env:RF4_LANG = $Lang

$script:ff = $null; $script:t0 = $null; $script:cues = New-Object System.Collections.Generic.List[object]
try {
    $ver = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'src\core.ps1')), "ToolVersion = '([\d\.]+)'").Groups[1].Value
    . (Join-Path $root "rf4sa-backup-gui-v$ver.ps1") -Lang $Lang
    $form.StartPosition = 'Manual'
    $vwa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $capH = [int](64 * $script:Scale)
    $form.ClientSize = New-Object System.Drawing.Size((S 1000), (S 690))
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    function Pump { [System.Windows.Forms.Application]::DoEvents() }
    function Wait-S([double]$sec) { $end = [DateTime]::Now.AddSeconds($sec); while ([DateTime]::Now -lt $end) { Pump; Start-Sleep -Milliseconds 25 } }
    function Walk($ctl) { foreach ($c in $ctl.Controls) { $c; Walk $c } }
    function Card-Index($cards, [string]$folder) { for ($i = 0; $i -lt $cards.Count; $i++) { if ($cards[$i].Tag2 -and $cards[$i].Tag2.Folder -eq $folder) { return $i } }; return -1 }
    $script:ConfirmOverwrite = { param($n) $true }

    # Hintergrund-Fläche (einfarbig, deckt alles dahinter ab) + Fenster + Untertitelleiste; aufgenommen wird nur diese Fläche
    $vwa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $mx = [int](14 * $script:Scale); $my = [int](10 * $script:Scale)
    $form.ClientSize = New-Object System.Drawing.Size((S 1000), (S 650)); Pump
    $fw = $form.Width; $fh = $form.Height
    $bdW = $fw + 2 * $mx; $bdH = $fh + $capH + 2 * $my; if ($bdW % 2) { $bdW++ }; if ($bdH % 2) { $bdH++ }
    $bd = New-Object System.Windows.Forms.Form
    $bd.FormBorderStyle = 'None'; $bd.StartPosition = 'Manual'; $bd.ShowInTaskbar = $false; $bd.TopMost = $true
    $bd.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 30)
    $bd.Bounds = New-Object System.Drawing.Rectangle(($vwa.Left + 4), ($vwa.Top + 2), $bdW, $bdH); $bd.Show(); Pump
    $form.TopMost = $true
    $form.Location = New-Object System.Drawing.Point(($bd.Left + $mx), ($bd.Top + $my)); Pump
    $cap = New-Object System.Windows.Forms.Form
    $cap.FormBorderStyle = 'None'; $cap.StartPosition = 'Manual'; $cap.ShowInTaskbar = $false; $cap.TopMost = $true
    $cap.Bounds = New-Object System.Drawing.Rectangle(($bd.Left + $mx), ($form.Bottom + 4), $fw, $capH)
    $cap.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 30)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Dock = 'Fill'; $lbl.ForeColor = [System.Drawing.Color]::FromArgb(236, 241, 248); $lbl.TextAlign = 'MiddleCenter'
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', [single](14 * $script:Scale * 96 / 72), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $cap.Controls.Add($lbl); $cap.Show(); $form.Activate(); Pump
    $rx = $bd.Left; $ry = $bd.Top; $rw = $bdW; $rh = $bdH
    if ($rw % 2) { $rw++ }; if ($rh % 2) { $rh++ }
    # Demo-Backups/Sync-Ordner wie bei den Screenshots
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
    [void](Set-Lang $Lang); Save-Lang $Lang; Save-ThemeChoice 'dark'; Rebuild-All; Pump

    # ── Aufnahme starten ──
    $mp4 = Join-Path $OutDir "rf4-backup-tool-$Lang.mp4"
    if (-not $NoRecord) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ffmpeg; $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
        $psi.Arguments = "-y -f gdigrab -framerate $Fps -draw_mouse 0 -offset_x $rx -offset_y $ry -video_size ${rw}x${rh} -i desktop -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p `"$mp4`""
        $script:ff = [System.Diagnostics.Process]::Start($psi)
        [void]$script:ff.StandardError.ReadToEndAsync()
        Wait-S 1.5
    }
    $script:t0 = [DateTime]::Now

    # Szene: Untertitel einblenden, dann Aktion ausführen (Zeit zählt mit), danach restliche Lesezeit (Zeichen/Sekunde) abwarten
    function Say([string]$key, [double]$min = 0, [scriptblock]$act = $null) {
        $txt = $V[$key]; $lbl.Text = $txt; Pump
        $t1 = [DateTime]::Now; $start = ($t1 - $script:t0).TotalSeconds
        $dur = [Math]::Max($min, 2.2 + $txt.Length / 15.0) * $Pace
        if ($act) { Wait-S 0.6; & $act; Pump }
        $left = $dur - ([DateTime]::Now - $t1).TotalSeconds; if ($left -gt 0) { Wait-S $left }
        $script:cues.Add([pscustomobject]@{ Start = $start; End = ([DateTime]::Now - $script:t0).TotalSeconds; Text = $txt })
    }
    $card = { param($lst, $f) $lst.Cards[(Card-Index $lst.Cards $f)].PerformClick() }

    Show-Panel { Render-Action }; Pump
    Say 'intro'
    Say 'head'
    Say 'scan' 5 { Show-Panel { Render-Scan } }
    Say 'action' 4 { Show-Panel { Render-Action } }

    # Sichern
    $script:state.Action = 'backup'
    Say 'bk1' 5 { Show-Panel { Render-Backup } }
    Say 'bk2' 7 {
        & $card $script:lstSrc 'RussianFishing4Steam'; Wait-S 1.5
        foreach ($c in $script:bkChecks) { if ($c.Text -match 'Crafting') { $c.Checked = $false } }; Pump
        $script:inDir.Text = "$D\Backups\Steam-$(Get-Date -Format 'yyyy-MM-dd')"; Pump
    }
    $script:btnPrimary.PerformClick(); Pump
    Say 'bk3' 7

    # Wiederherstellen
    $script:state.Action = 'restore'
    Say 'rs1' 7 { Show-Panel { Render-Restore } }
    Say 'rs2' 5 { $script:lstBk.SelectedIndex = 0 }
    Say 'rs3' 6 { & $card $script:lstDst 'RussianFishing4DE' }
    $script:btnPrimary.PerformClick(); Pump
    Say 'rs4' 6

    # Zusammenführen
    $script:state.Action = 'merge'
    Say 'mg1' 8 { Show-Panel { Render-Merge }; Wait-S 1.5; & $card $script:lstMgDst 'RussianFishing4DE'; Wait-S 1.2; & $card $script:lstMgSrc 'RussianFishing4Steam' }
    $script:btnPrimary.PerformClick(); Pump
    Say 'mg2' 6

    # Synchronisieren
    $script:state.Action = 'sync'
    Say 'sy1' 5 { Show-Panel { Render-Sync } }
    Say 'sy2' 6 { & $card $script:lstSyInst 'RussianFishing4DE'; Wait-S 1.2; $script:btnExtra.PerformClick() }
    $script:btnPrimary.PerformClick(); Pump
    Say 'sy3' 6
    # Sprachen + Design
    Show-Panel { Render-Action }; Pump
    $first = $true
    foreach ($l in 'en', 'zh', 'ru', $Lang) {
        [void](Set-Lang $l); Save-Lang $l; Rebuild-All; Pump
        if ($first) { $lbl.Text = $V.langs; $first = $false; $st = ([DateTime]::Now - $script:t0).TotalSeconds }
        Wait-S (2.2 * $Pace)
    }
    $script:cues.Add([pscustomobject]@{ Start = $st; End = ([DateTime]::Now - $script:t0).TotalSeconds; Text = $V.langs })
    Save-ThemeChoice 'light'; Rebuild-All; Pump
    Say 'theme' 4
    $script:state.Action = 'restore'; Show-Panel { Render-Restore }; Pump; Wait-S (2.5 * $Pace)
    Save-ThemeChoice 'dark'; Rebuild-All; Show-Panel { Render-Action }; Pump
    Say 'outro' 5
    Wait-S 1

    # ── Aufnahme beenden ──
    if ($script:ff) { $script:ff.StandardInput.WriteLine('q'); [void]$script:ff.WaitForExit(30000); if (-not $script:ff.HasExited) { $script:ff.Kill() }; $script:ff = $null }
    $cap.Close(); $bd.Close(); $form.Close()

    # ── Untertitel (.srt) + Videoscript (.md) ──
    function TC([double]$s, [string]$sep) { $ts = [TimeSpan]::FromSeconds($s); '{0:00}:{1:00}:{2:00}{3}{4:000}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $sep, $ts.Milliseconds }
    $srt = New-Object System.Text.StringBuilder; $md = New-Object System.Text.StringBuilder; $n = 0
    [void]$md.AppendLine("# Videoscript RF4 Backup & Migration v$ver ($Lang)"); [void]$md.AppendLine()
    [void]$md.AppendLine('Sprechertext mit Zeitmarken. Gleiche Texte erscheinen als Untertitel im Video (`.srt`). Alle Daten im Video sind Demo-Daten.'); [void]$md.AppendLine()
    [void]$md.AppendLine('| Zeit | Text |'); [void]$md.AppendLine('|---|---|')
    foreach ($c in $script:cues) {
        $n++; [void]$srt.AppendLine("$n"); [void]$srt.AppendLine("$(TC $c.Start ',') --> $(TC $c.End ',')"); [void]$srt.AppendLine($c.Text); [void]$srt.AppendLine()
        [void]$md.AppendLine(('| {0} | {1} |' -f (TC $c.Start '.').Substring(3, 5), $c.Text))
    }
    [IO.File]::WriteAllText((Join-Path $OutDir "rf4-backup-tool-$Lang.srt"), $srt.ToString(), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $OutDir "videoscript-$Lang.md"), $md.ToString(), (New-Object Text.UTF8Encoding($false)))
    Write-Host ("Fertig: {0} ({1:N0} s)" -f $mp4, ([DateTime]::Now - $script:t0).TotalSeconds) -ForegroundColor Green
}
finally {
    if ($script:ff -and -not $script:ff.HasExited) { try { $script:ff.Kill() } catch { } }
    try { $cap.Dispose(); $bd.Dispose() } catch { }
    try { $form.Dispose() } catch { }
    & subst.exe "${Drive}:" /d | Out-Null
    [IO.Directory]::Delete($demoRoot, $true)
}
