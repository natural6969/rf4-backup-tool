#Requires -Version 5.1
# Terminal-Test: startet rf4sa-backup.ps1 als Kindprozess, füttert Eingaben über stdin und prüft die Ausgabe
# (alle Sprachen, Rahmenbreite auch mit CJK, ASCII-Fallback, Backup→Restore (vorhandene Backups)→Merge→Sync, Sprachwechsel).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $root 'rf4sa-backup.ps1'
$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$n, $d = '') { if ($c) { $script:pass++; Write-Host "  PASS  $n" -ForegroundColor Green } else { $script:fail++; Write-Host "  FAIL  $n  $d" -ForegroundColor Red } }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rf4cli_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$me = Join-Path $tmp 'Users\tester'; $ap = Join-Path $me 'AppData\Roaming'; $base = Join-Path $ap 'RussianFishingLLC'
New-Item -ItemType Directory -Force -Path $base | Out-Null
function New-Msg([string]$id, [long]$c) { [pscustomobject]@{ meta = [pscustomobject]@{ id = $id; created = $c; text = 'x'; items = @() }; status = 1 } }
function New-Dat($path, $msgs) { New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null; [IO.File]::WriteAllText($path, ([pscustomobject]@{ id = 1; items = @($msgs) } | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($true))) }
foreach ($n in 1..3) { New-Dat "$base\RussianFishing4Steam\Mailbox_309850\$n.dat" @((New-Msg "s$n-a" 1), (New-Msg "s$n-b" 2)) }
New-Dat "$base\RussianFishing4DE\Mailbox_309850\1.dat" @((New-Msg 's1-a' 1))
Set-Content "$base\RussianFishing4Steam\Settings.dat" 'steam'
$shots = "$me\Documents\Russian Fishing 4\Screenshots"; New-Item -ItemType Directory -Force -Path $shots | Out-Null; 1..3 | ForEach-Object { Set-Content "$shots\s$_.png" 'x' }

function Run-Cli([string[]]$inputs, [string]$lang = 'de', [hashtable]$env2 = @{}) {
    $saved = @{}; $vars = @{ APPDATA = $ap; USERPROFILE = "$me"; USERNAME = 'tester'; RF4_NO_DRIVE_SCAN = '1'; RF4_LANG = ''; RF4_BACKUP_DIRS = ''; RF4_ASCII = '' }; foreach ($k in $env2.Keys) { $vars[$k] = $env2[$k] }
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    try { ($inputs -join "`r`n") + "`r`n" | powershell -NoProfile -ExecutionPolicy Bypass -File $cli @(if ($lang) { @('-Lang', $lang) }) 2>&1 | Out-String -Width 300 }
    finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}
try {
    Write-Host "`n[1] Hauptmenü in allen Sprachen" -ForegroundColor Cyan
    foreach ($l in 'de', 'en', 'zh', 'ru') {
        $o = Run-Cli @('0') $l
        $lines = $o -split "`r?`n"
        $box = @($lines | Where-Object { $_ -match '^\s*[╔║╚]' })
        Ok ($box.Count -eq 5) "($l) Banner-Rahmen mit 5 Zeilen" "$($box.Count)"
        $widths = @(); foreach ($b in $box) { $d = 0; foreach ($ch in $b.ToCharArray()) { $c = [int]$ch; if (($c -ge 0x2E80 -and $c -le 0xA4CF) -or ($c -ge 0xFF00 -and $c -le 0xFF60)) { $d += 2 } else { $d += 1 } }; $widths += $d }
        Ok ((@($widths | Sort-Object -Unique)).Count -eq 1) "($l) Rahmenzeilen gleich breit (Anzeigebreite $($widths -join ','))"
        Ok ($o -match '\[1\]' -and $o -match '\[L\]' -and $o -match '\[0\]') "($l) Menüpunkte [1] [L] [0]"
    }
    $o = Run-Cli @('0') 'en' @{ RF4_ASCII = '1' }
    Ok ($o -notmatch '[╔║╚═✔✘›■□]' -and $o -match '\+=+\+') 'ASCII-Modus: keine Unicode-Rahmen/Symbole'

    Write-Host "`n[2] Scan (4 Sprachen)" -ForegroundColor Cyan
    foreach ($l in 'de', 'en', 'zh', 'ru') {
        $o = Run-Cli @('1', '', '0') $l
        Ok ($o -match 'RussianFishing4Steam' -and $o -match '309850') "($l) Scan zeigt Steam-Installation + Account-ID"
    }

    Write-Host "`n[3] Backup → Zusammenfassung" -ForegroundColor Cyan
    $bk = Join-Path $tmp 'Users\tester\RF4_Backup'
    $o = Run-Cli @('2', '2', 'a', '', '', '', '0') 'de'
    Ok ($o -match 'Backup fertig' -and $o -match '■ 3 Konversationen' -and $o -match '■ 1 Dateien kopiert|■ 1 Dateien') 'Backup: Meldung + Kennzahlen (3 Konversationen)' ($o -split "`n" | Select-String 'Konversationen|fertig|Fehler' | Out-String)
    Ok ((Test-Path "$bk\Mailbox_309850\1.dat") -and (Test-Path "$bk\Settings.dat") -and @(Get-ChildItem "$bk\Screenshots").Count -eq 3) 'Backup: Dateien im Standardordner'
    Ok ($o -match 'Crafting.dat nicht gefunden|Crafting.dat not found') 'Backup: fehlende Datei nur als Warnung'

    Write-Host "`n[4] Restore: vorhandene Backups werden angeboten" -ForegroundColor Cyan
    $o = Run-Cli @('3', '1', '1', 'a', '', '', '', '0') 'en'
    Ok ($o -match 'Choose a backup' -and $o -match 'RF4_Backup' -and $o -match '3 conversations') 'Restore: Liste mit Name, Pfad, Inhalt' ($o -split "`n" | Select-String 'backup|RF4_Backup' | Out-String)
    Ok ($o -match 'Import finished') 'Restore: Abschlussmeldung'
    $o = Run-Cli @('3', '0', '0') 'ru'
    Ok ($o -match 'Выберите резервную копию' -and $o -match 'вручную') 'Restore (ru): Überschriften übersetzt'

    Write-Host "`n[5] Merge" -ForegroundColor Cyan
    $de = "$base\RussianFishing4DE\Mailbox_309850"; foreach ($n in 2, 3) { if (Test-Path "$de\$n.dat") { [IO.File]::Delete("$de\$n.dat") } }
    $before = @(Get-ChildItem $de -Filter *.dat).Count
    $o = Run-Cli @('4', '1', '1', '', '', '0') 'zh'
    Ok ($before -le 2 -and @(Get-ChildItem $de -Filter *.dat).Count -eq 3) "Merge (zh): DE hat danach 3 Konversationen (vorher $before)" ($o -split "`n" | Select-String '合并|merge' | Out-String)
    Ok ($o -match '■ \d+ 个对话|■ \d+ 条消息') 'Merge (zh): Zusammenfassung chinesisch'

    Write-Host "`n[6] Sync" -ForegroundColor Cyan
    $nas = Join-Path $tmp 'nas'
    $o = Run-Cli @('5', '2', $nas, '', '1', '1', '', '3', '', '0', '0') 'de'
    Ok ((Test-Path "$nas\RF4_Sync\Mailbox_309850") -and $o -match 'Sync abgeschlossen') 'Sync: Ordner konfiguriert, Lauf erfolgreich'
    Ok ($o -match 'Letzte Sync-Einträge') 'Sync: Statusanzeige'

    Write-Host "`n[7] Sprachwechsel im Menü" -ForegroundColor Cyan
    $o = Run-Cli @('l', '3', '0') 'de'
    Ok ($o -match '语言已更改') 'L → 3 (中文): Bestätigung auf Chinesisch'
    $cfg = Get-Content "$ap\rf4-backup\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Ok ($cfg.lang -eq 'zh') 'Sprache gespeichert'
    $o = Run-Cli @('0') ''
    Ok ($o -match '备份') 'Neustart ohne -Lang nutzt gespeichertes Chinesisch'
    # externe Sprache
    New-Item -ItemType Directory -Force -Path "$ap\rf4-backup\lang" | Out-Null
    [IO.File]::WriteAllText("$ap\rf4-backup\lang\nl.lang", "@code=nl`n@name=Nederlands`nmenu_scan=Scannen – alles`nexit=Afsluiten`n", (New-Object Text.UTF8Encoding($false)))
    $o = Run-Cli @('l', '5', '0') 'de'
    Ok ($o -match 'Nederlands') 'Externe Sprache (nl.lang) erscheint im Sprachmenü'
    $o = Run-Cli @('0') 'nl'
    Ok ($o -match 'Scannen – alles' -and $o -match 'Afsluiten') 'Externe Sprache: eigene Texte aktiv'
    Ok ($o -match 'Backup' -and $o -match 'Restore') 'Externe Sprache: fehlende Texte fallen auf Englisch zurück'
    Ok (-not ($o -match 'menu_backup')) 'Kein roher Schlüssel sichtbar'
    $o = Run-Cli @('9', 'x', '0') 'en'; Ok ($o -match 'RF4') 'Ungültige Eingaben beenden das Programm nicht'

    Write-Host "`n[8] Backup-Info im Restore + 'RF4 läuft'-Rückfrage" -ForegroundColor Cyan
    Ok (Test-Path "$bk\rf4-backup.info") 'Backup hat rf4-backup.info geschrieben'
    $o = Run-Cli @('3', '0', '0') 'en'
    Ok ($o -match 'Source: ' -and $o -match 'Created: ' -and $o -match 'Updated: ') 'Restore-Liste (en): Quelle, Erstellt, Aktualisiert' ($o -split "`n" | Select-String 'Source|Created|RF4_Backup' | Out-String)
    $o = Run-Cli @('3', '0', '0') 'de'; Ok ($o -match 'Quelle: ' -and $o -match 'Erstellt: ') 'Restore-Liste (de): Quelle/Erstellt'
    $o = Run-Cli @('3', '1', '1', 'a', '', 'n', '', '0') 'en' @{ RF4_FAKE_RUNNING = 'rf4_x64' }
    Ok ($o -match 'seems to be running' -and $o -match 'Cancelled' -and $o -notmatch 'Import finished') 'RF4 läuft + "n": Abbruch ohne Import'
    $o = Run-Cli @('3', '1', '1', 'a', '', 'y', '', '0') 'en' @{ RF4_FAKE_RUNNING = 'rf4_x64' }
    Ok ($o -match 'seems to be running' -and $o -match 'Import finished') 'RF4 läuft + "y": Import läuft durch'
    $o = Run-Cli @('4', '1', '1', '', 'n', '', '0') 'en' @{ RF4_FAKE_RUNNING = 'rf4_x64' }
    Ok ($o -match 'seems to be running' -and $o -match 'Cancelled') 'Merge: Rückfrage bei laufendem RF4'
    $o = Run-Cli @('5', '1', '', '0') 'en' @{ RF4_FAKE_RUNNING = 'rf4_x64' }; Ok ($o -match 'RF4') 'Sync-Menü ohne Ordner: kein Absturz'
}
finally { [IO.Directory]::Delete($tmp, $true) }
Write-Host ""
Write-Host ("Ergebnis: {0} bestanden, {1} fehlgeschlagen" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
