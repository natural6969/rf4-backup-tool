#Requires -Version 5.1
# Tests für src\core.ps1 – läuft komplett in einem Temp-Verzeichnis, fasst echte RF4-Daten nicht an.
# Aufruf: powershell -ExecutionPolicy Bypass -File tests\Test-Core.ps1 [-RealDataDir <Mailbox-Quellordner>]
param([string]$RealDataDir = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\core.ps1')

$script:pass = 0; $script:fail = 0
function Ok([bool]$cond, [string]$name, $detail = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red }
}

# ── Fixture ────────────────────────────────────────────────────────────────────
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rf4test_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$users = Join-Path $tmp 'Users'; $me = Join-Path $users 'tester'
New-Item -ItemType Directory -Force -Path (Join-Path $me 'AppData\Roaming') | Out-Null
$env:APPDATA = Join-Path $me 'AppData\Roaming'
$env:USERPROFILE = $me; $env:USERNAME = 'tester'
$env:RF4_NO_DRIVE_SCAN = '1'; $env:RF4_LANG = ''
$base = Join-Path $env:APPDATA 'RussianFishingLLC'

function New-Msg([string]$id, [long]$created, [string]$text = 'x') {
    [pscustomobject]@{ meta = [pscustomobject]@{ id = $id; created = $created; sender = 1; type = 0; text = $text; items = @() }; status = 1281 }
}
function New-Dat([string]$path, [object[]]$msgs, [int]$convId = 1) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    $o = [pscustomobject]@{ id = $convId; items = @($msgs) }
    [IO.File]::WriteAllText($path, ($o | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($true)))
}
function Get-Ids($path) { @((Read-JsonFile $path).items | ForEach-Object { $_.meta.id }) }

$logs = New-Object System.Collections.Generic.List[string]
$script:LogSink = { param($lvl, $msg) $logs.Add("$lvl|$msg") }

try {
    Write-Host "`n[1] Sprachen / Übersetzungen" -ForegroundColor Cyan
    Ok ((Resolve-Lang 'zh-CN') -eq 'zh') 'Resolve zh-CN'
    Ok ((Resolve-Lang 'DE') -eq 'de') 'Resolve DE'
    Ok ($null -eq (Resolve-Lang 'xx')) 'Resolve unbekannt = null'
    Ok ($null -eq (Resolve-Lang '')) 'Resolve leer = null'
    Ok ($null -eq (Resolve-Lang 'r' )) 'Resolve 1 Zeichen (früher Substring-Crash)'
    foreach ($l in $script:Langs) {
        $miss = @($script:TX.Keys | Where-Object { [string]::IsNullOrWhiteSpace($script:TX[$_][$l]) })
        Ok ($miss.Count -eq 0) "Alle Schlüssel in '$l' vorhanden" ($miss -join ',')
    }
    $bad = @()
    foreach ($k in $script:TX.Keys) {
        $sets = foreach ($l in $script:Langs) { (([regex]::Matches($script:TX[$k][$l], '\{(\d+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ',') }
        if (@($sets | Sort-Object -Unique).Count -ne 1) { $bad += $k }
    }
    Ok ($bad.Count -eq 0) 'Platzhalter {0}{1}… in allen Sprachen identisch' ($bad -join ',')
    $cjk = @($script:TX.Keys | Where-Object { $script:TX[$_]['zh'] -notmatch '[\u4e00-\u9fff]' -and $_ -notmatch '^(v_Steam|v_Other|hash_label|hash_unknown|app_title|yes_char|w_win|w_wine|w_proton)$' -and $_ -notmatch '^item_' })
    Ok ($cjk.Count -le 4) 'zh enthält chinesische Zeichen' ($cjk -join ',')
    $cyr = @($script:TX.Keys | Where-Object { $script:TX[$_]['ru'] -notmatch '[\u0400-\u04FF]' -and $_ -notmatch '^(item_|v_Steam|v_Other|hash_|w_win|w_wine|w_proton)' })
    Ok ($cyr.Count -le 3) 'ru enthält kyrillische Zeichen' ($cyr -join ',')
    foreach ($l in $script:Langs) {
        [void](Set-Lang $l)
        $s = T 'mb_merge_file' @('a.dat', 5)
        Ok ($s -match 'a\.dat' -and $s -match '5' -and $s -notmatch '\{\d\}') "T() mit Argumenten ($l)" $s
    }
    [void](Set-Lang 'de'); Ok ((T 'nicht_vorhanden') -eq 'nicht_vorhanden') 'T() unbekannter Schlüssel liefert Schlüssel'
    Ok ((Set-Lang 'klingon') -eq 'en') 'Set-Lang Fallback en'

    Write-Host "`n[2] Konfiguration" -ForegroundColor Cyan
    Save-Lang 'ru'; Ok ((Get-Config).lang -eq 'ru') 'Sprache wird gespeichert'
    Initialize-Lang ''; Ok ($script:Lang -eq 'ru') 'Initialize-Lang liest Config'
    $env:RF4_LANG = 'zh'; Initialize-Lang ''; Ok ($script:Lang -eq 'zh') 'Env RF4_LANG schlägt Config'
    Initialize-Lang 'de'; Ok ($script:Lang -eq 'de') 'Parameter schlägt Env'
    $env:RF4_LANG = ''
    Set-SyncPath 'C:\Sync Ordner\ü ß 中'; Ok ((Get-SyncPath) -eq 'C:\Sync Ordner\ü ß 中') 'Sync-Pfad mit Umlauten/CJK roundtrip'
    Save-Lang 'en'; Ok ((Get-SyncPath) -eq 'C:\Sync Ordner\ü ß 中') 'Lang speichern behält Sync-Pfad'
    Remove-Item (Get-ConfigFile) -Force
    New-Item -ItemType Directory -Force -Path (Get-ConfigDir) | Out-Null
    Set-Content (Join-Path (Get-ConfigDir) 'sync.conf') 'D:\Alt' -Encoding UTF8
    Ok ((Get-SyncPath) -eq 'D:\Alt') 'Altes sync.conf wird gelesen'

    Write-Host "`n[3] Installationen finden" -ForegroundColor Cyan
    $steam = Join-Path $base 'RussianFishing4Steam'; $de = Join-Path $base 'RussianFishing4DE'
    New-Dat (Join-Path $steam 'Mailbox_309850\100.dat') @((New-Msg 'a' 1), (New-Msg 'b' 2), (New-Msg 'c' 3))
    New-Dat (Join-Path $steam 'Mailbox_309850\200.dat') @((New-Msg 'z' 9))   # genau EIN Eintrag (StrictMode-Falle)
    New-Item -ItemType Directory -Force -Path (Join-Path $steam 'Mailbox_555') | Out-Null  # leere Mailbox
    Set-Content (Join-Path $steam 'Settings.dat') 'steam-settings'
    Set-Content (Join-Path $steam 'Preferences.dat') 'steam-prefs'
    New-Dat (Join-Path $de 'Mailbox_309850\100.dat') @((New-Msg 'a' 1), (New-Msg 'd' 4))
    Set-Content (Join-Path $de 'Settings.dat') 'de-settings'
    New-Item -ItemType Directory -Force -Path (Join-Path $base 'RussianFishing4Foo') | Out-Null
    $other = Join-Path $users 'bruder\AppData\Roaming\RussianFishingLLC\RussianFishing4EN'
    New-Dat (Join-Path $other 'Mailbox_777\1.dat') @((New-Msg 'q' 1))
    $emptyUser = Join-Path $users 'leer'; New-Item -ItemType Directory -Force -Path $emptyUser | Out-Null
    $ins = @(Find-Installations)
    Ok ($ins.Count -ge 5) "Find-Installations liefert Einträge ($($ins.Count))"
    $names = $ins | ForEach-Object { $_.Folder }
    Ok ($names -contains 'RussianFishing4Foo') 'Unbekannter Ordner wird als Other erkannt'
    Ok (@($ins | Where-Object { $_.WhereType -eq 'user' -and $_.Where1 -eq 'bruder' }).Count -eq 1) 'Anderer Benutzer gefunden, leerer Benutzer nicht'
    Ok (@($ins | Where-Object { -not $_.Exists -and $_.WhereType -ne 'local' }).Count -eq 0) 'Nicht vorhandene Fremd-Pfade werden ausgeblendet'
    $ex = @($ins | Where-Object Exists)
    foreach ($l in $script:Langs) { [void](Set-Lang $l); $lab = Get-InstLabel $ex[0]; Ok ($lab.Length -gt 5 -and $lab -notmatch '\{\d\}') "Label ($l): $lab" }
    [void](Set-Lang 'de')
    $env:RF4_SCAN_USERS = (Join-Path $tmp 'usb\Users'); New-Dat (Join-Path $tmp 'usb\Users\alt\AppData\Roaming\RussianFishingLLC\RussianFishing4DE\Mailbox_1\1.dat') @((New-Msg 'u' 1))
    Ok (@(Find-Installations | Where-Object { $_.WhereType -eq 'extra' }).Count -eq 1) 'RF4_SCAN_USERS Zusatzpfad'
    $env:RF4_SCAN_USERS = ''
    $info = Get-InstInfo $steam
    Ok ($info.Mailboxes.Count -eq 2 -and $info.Convs -eq 2) 'Get-InstInfo: 2 Mailboxen, 2 Konversationen'
    Ok ($info.Files.Count -eq 2) 'Get-InstInfo: Settings+Preferences'
    $one = Get-InstInfo (Join-Path $base 'RussianFishing4Foo')
    Ok ($one.Mailboxes.Count -eq 0 -and $one.Convs -eq 0) 'Leere Installation crasht nicht (StrictMode)'
    $inf2 = Get-InstInfo (Join-Path $de 'Mailbox_309850')
    Ok ($inf2.Convs -eq 0) 'Pfad ohne Mailbox_* ok'

    Write-Host "`n[4] Merge" -ForegroundColor Cyan
    $dst = Join-Path $tmp 'merge_dst'
    $undo = Join-Path $tmp 'undo1'
    New-Dat (Join-Path $dst '100.dat') @((New-Msg 'a' 1), (New-Msg 'd' 4))
    $r = Merge-Mailbox -SrcDir (Join-Path $steam 'Mailbox_309850') -DstDir $dst -UndoRoot $undo
    Ok ($r.Added -eq 2 -and $r.Merged -eq 1 -and $r.Copied -eq 1) 'Merge: +2 (b,c), 1 neu kopiert (200.dat)' "$($r | ConvertTo-Json -Compress)"
    $ids = Get-Ids (Join-Path $dst '100.dat')
    Ok (($ids -join ',') -eq 'a,b,c,d') 'Reihenfolge nach created sortiert, keine Duplikate' ($ids -join ',')
    Ok (Test-Path (Join-Path $undo 'merge_dst\100.dat')) 'Undo-Kopie des Originals angelegt'
    $b = [IO.File]::ReadAllBytes((Join-Path $dst '100.dat'))[0..2]
    Ok ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'UTF-8 BOM bleibt erhalten'
    $r2 = Merge-Mailbox -SrcDir (Join-Path $steam 'Mailbox_309850') -DstDir $dst
    Ok ($r2.Added -eq 0 -and $r2.Unchanged -eq 2 -and $r2.Merged -eq 0) 'Zweiter Lauf idempotent (nichts geschrieben)'
    $h1 = (Get-FileHash (Join-Path $dst '100.dat')).Hash
    [void](Merge-Mailbox -SrcDir (Join-Path $steam 'Mailbox_309850') -DstDir $dst)
    Ok ($h1 -eq (Get-FileHash (Join-Path $dst '100.dat')).Hash) 'Datei bei No-op unverändert (Hash)'
    # kaputte Datei
    $bad = Join-Path $tmp 'badsrc'; New-Dat (Join-Path $bad '1.dat') @((New-Msg 'k' 1)); New-Dat (Join-Path $bad '2.dat') @((New-Msg 'm' 2))
    $bd = Join-Path $tmp 'baddst'; New-Dat (Join-Path $bd '1.dat') @((New-Msg 'x' 1)); Set-Content (Join-Path $bd '2.dat') '{kaputt'
    $logs.Clear(); $r3 = Merge-Mailbox -SrcDir $bad -DstDir $bd
    Ok ($r3.Failed -eq 1 -and $r3.Merged -eq 1) 'Kaputte JSON: 1 Fehler, restliche Dateien laufen weiter'
    Ok ((Get-Content (Join-Path $bd '2.dat') -Raw).Trim() -eq '{kaputt') 'Kaputte Zieldatei bleibt unangetastet'
    Ok (@($logs | Where-Object { $_ -like 'warn|*' }).Count -ge 1) 'Warnung wurde geloggt'
    Ok (@(Get-ChildItem $bd -Filter '*.rf4tmp').Count -eq 0) 'Keine .rf4tmp-Reste'
    # Ziel leer / items fehlt
    $e1 = Join-Path $tmp 'e1'; New-Dat (Join-Path $e1 '1.dat') @(); $es = Join-Path $tmp 'es'; New-Dat (Join-Path $es '1.dat') @((New-Msg 'n1' 5), (New-Msg 'n2' 6))
    $r4 = Merge-Mailbox -SrcDir $es -DstDir $e1
    Ok ($r4.Added -eq 2) 'Leeres Ziel (items=[]) wird gefüllt'
    $e2 = Join-Path $tmp 'e2'; New-Item -ItemType Directory -Force -Path $e2 | Out-Null
    [IO.File]::WriteAllText((Join-Path $e2 '1.dat'), '{"id":1}', (New-Object Text.UTF8Encoding($true)))
    $r5 = Merge-Mailbox -SrcDir $es -DstDir $e2
    Ok ($r5.Added -eq 2 -and (Get-Ids (Join-Path $e2 '1.dat')).Count -eq 2) 'Ziel ohne items-Eigenschaft' "$($r5|ConvertTo-Json -Compress)"
    # Unicode
    $u1 = Join-Path $tmp 'u1'; $u2 = Join-Path $tmp 'u2'
    New-Dat (Join-Path $u1 '1.dat') @((New-Msg 'u1' 1 'Привет 你好 ä ö ü ß <b>&</b> "q" ''s'''))
    New-Dat (Join-Path $u2 '1.dat') @((New-Msg 'u2' 2 'ok'))
    [void](Merge-Mailbox -SrcDir $u1 -DstDir $u2)
    $txt = (Read-JsonFile (Join-Path $u2 '1.dat')).items | Where-Object { $_.meta.id -eq 'u1' } | ForEach-Object { $_.meta.text }
    Ok ($txt -eq 'Привет 你好 ä ö ü ß <b>&</b> "q" ''s''') 'Unicode/Sonderzeichen überstehen Merge' $txt
    # große IDs
    $big = Join-Path $tmp 'big'; New-Dat (Join-Path $big '1.dat') @((New-Msg 'g1' 133292355165425967)); $big2 = Join-Path $tmp 'big2'; New-Dat (Join-Path $big2 '1.dat') @((New-Msg 'g2' 133292355165425000))
    [void](Merge-Mailbox -SrcDir $big -DstDir $big2)
    $c = @((Read-JsonFile (Join-Path $big2 '1.dat')).items | ForEach-Object { [long]$_.meta.created })
    Ok ($c[0] -eq 133292355165425000 -and $c[1] -eq 133292355165425967) 'FILETIME-Zahlen (18 Stellen) verlustfrei + sortiert'

    Write-Host "`n[5] Backup / Restore (Copy-Rf4Data)" -ForegroundColor Cyan
    $bk = Join-Path $tmp 'backup'
    $shots = Join-Path $me 'Documents\Russian Fishing 4\Screenshots'
    New-Item -ItemType Directory -Force -Path (Join-Path $shots 'sub') | Out-Null
    1..3 | ForEach-Object { Set-Content (Join-Path $shots "s$_.png") "png$_" }
    Set-Content (Join-Path $shots 'sub\deep.jpg') 'jpg'; Set-Content (Join-Path $shots 'note.txt') 'x'
    $sd = Get-ScreenshotDir $steam
    Ok ($sd -eq $shots) 'Screenshot-Ordner gefunden' "$sd"
    $logs.Clear()
    Copy-Rf4Data -SrcDir $steam -DstDir $bk -Items @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots') -ShotsSrc $sd -ShotsDst (Join-Path $bk 'Screenshots') -Confirm { $false }
    Ok (@(Get-Mailboxes $bk).Count -eq 2) 'Backup: beide Mailboxen (inkl. leerer)'
    Ok ((Test-Path (Join-Path $bk 'Settings.dat')) -and (Test-Path (Join-Path $bk 'Preferences.dat'))) 'Backup: Settings+Preferences kopiert'
    Ok (-not (Test-Path (Join-Path $bk 'Crafting.dat'))) 'Backup: fehlende Crafting.dat nur Warnung'
    Ok (@(Get-ChildItem (Join-Path $bk 'Screenshots') -File).Count -eq 4) 'Backup: 4 Bilder (rekursiv), txt ignoriert'
    Ok (@($logs | Where-Object { $_ -like 'warn|*' }).Count -ge 1) 'Warnung für Crafting.dat geloggt'
    # Konto-Filter
    $bk2 = Join-Path $tmp 'backup2'
    Copy-Rf4Data -SrcDir $steam -DstDir $bk2 -Items @('mail') -Accounts @('Mailbox_555')
    Ok (@(Get-Mailboxes $bk2).Count -eq 1 -and @(Get-Mailboxes $bk2)[0].Name -eq 'Mailbox_555') 'Account-Filter: nur gewählte Mailbox'
    # Restore in frische Installation
    $newInst = Join-Path $users 'neu\AppData\Roaming\RussianFishingLLC\RussianFishing4DE'
    $newShots = Get-ScreenshotDir $newInst -Create
    Ok ($newShots -eq (Join-Path $users 'neu\Documents\Russian Fishing 4\Screenshots')) 'Screenshot-Zielordner (Create) für neuen User' $newShots
    $undoR = New-UndoRoot $newInst
    Copy-Rf4Data -SrcDir $bk -DstDir $newInst -Items @('mail', 'Settings.dat', 'shots') -ShotsSrc (Join-Path $bk 'Screenshots') -ShotsDst $newShots -Confirm { $true } -UndoRoot $undoR
    Ok ((Get-InstInfo $newInst).Convs -eq 2) 'Restore: Konversationen vorhanden'
    Ok (@(Get-ChildItem $newShots -File).Count -eq 4) 'Restore: Screenshots (früher 0 wegen -Include ohne -Recurse)' "$(@(Get-ChildItem $newShots -File -ea SilentlyContinue).Count)"
    # Überschreiben-Dialog
    Set-Content (Join-Path $newInst 'Settings.dat') 'lokal-anders'
    $calls = New-Object System.Collections.Generic.List[string]
    Copy-Rf4Data -SrcDir $bk -DstDir $newInst -Items @('Settings.dat') -Confirm { param($n) $calls.Add($n); $false } -UndoRoot $undoR
    Ok ((Get-Content (Join-Path $newInst 'Settings.dat')) -eq 'lokal-anders' -and $calls.Count -eq 1) 'Überschreiben abgelehnt → Datei bleibt'
    Copy-Rf4Data -SrcDir $bk -DstDir $newInst -Items @('Settings.dat') -Confirm { $true } -UndoRoot $undoR
    Ok ((Get-Content (Join-Path $newInst 'Settings.dat')) -eq 'steam-settings') 'Überschreiben bestätigt → ersetzt'
    Ok ((Get-Content (Join-Path $undoR 'RussianFishing4DE\Settings.dat')) -eq 'lokal-anders') 'Undo enthält die ersetzte Datei'
    $calls.Clear(); Copy-Rf4Data -SrcDir $bk -DstDir $newInst -Items @('Settings.dat') -Confirm { param($n) $calls.Add($n); $true }
    Ok ($calls.Count -eq 0) 'Identische Datei: keine Rückfrage'

    Write-Host "`n[6] Sync" -ForegroundColor Cyan
    $sync = Join-Path $tmp 'nas'; New-Item -ItemType Directory -Force -Path $sync | Out-Null
    $pcA = Join-Path $users 'pcA\AppData\Roaming\RussianFishingLLC\RussianFishing4DE'
    $pcB = Join-Path $users 'pcB\AppData\Roaming\RussianFishingLLC\RussianFishing4DE'
    New-Dat (Join-Path $pcA 'Mailbox_1\1.dat') @((New-Msg 'a1' 1), (New-Msg 'a2' 2)); Set-Content (Join-Path $pcA 'Settings.dat') 'A-alt'
    New-Dat (Join-Path $pcB 'Mailbox_1\1.dat') @((New-Msg 'a1' 1), (New-Msg 'b1' 3)); Set-Content (Join-Path $pcB 'Settings.dat') 'B-neu'
    (Get-Item (Join-Path $pcA 'Settings.dat')).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-2)
    Invoke-SyncRun -InstPath $pcA -SyncBase $sync
    Invoke-SyncRun -InstPath $pcB -SyncBase $sync
    Invoke-SyncRun -InstPath $pcA -SyncBase $sync
    Ok ((Get-Ids (Join-Path $pcA 'Mailbox_1\1.dat')) -join ',' -eq 'a1,a2,b1') 'Sync: PC A hat a1,a2,b1' ((Get-Ids (Join-Path $pcA 'Mailbox_1\1.dat')) -join ',')
    Ok ((Get-Ids (Join-Path $pcB 'Mailbox_1\1.dat')) -join ',' -eq 'a1,a2,b1') 'Sync: PC B hat a1,a2,b1'
    Ok ((Get-Content (Join-Path $pcA 'Settings.dat')) -eq 'B-neu') 'Sync: neuere Settings gewinnen'
    $st = Get-SyncStatus $sync
    Ok ($st.Exists -and $st.Mailboxes.Count -eq 1 -and $st.Log.Count -ge 3) 'Sync-Status: Mailbox + Log-Zeilen'
    Ok (-not (Get-SyncStatus (Join-Path $tmp 'gibtsnicht')).Exists) 'Sync-Status ohne Ordner'

    Write-Host "`n[7] Echte Daten (nur Kopie, read-only Quelle)" -ForegroundColor Cyan
    if ($RealDataDir -and (Test-Path $RealDataDir)) {
        $rc = Join-Path $tmp 'real_copy'; Copy-Item $RealDataDir $rc -Recurse
        $files = @(Get-ChildItem $rc -Filter '*.dat' -File)
        $okAll = $true; $semOk = $true
        $emptyDst = Join-Path $tmp 'real_empty'; New-Item -ItemType Directory -Force -Path $emptyDst | Out-Null
        foreach ($f in $files) {                      # jede Datei: leeres JSON-Ziel mit nur 1 Nachricht, dann Merge der echten Datei
            $orig = Read-JsonFile $f.FullName
            $oi = @($orig.items)
            if ($oi.Count -lt 2) { continue }
            $partial = [pscustomobject]@{ id = $orig.id; items = @($oi[0]) }
            [IO.File]::WriteAllText((Join-Path $emptyDst $f.Name), ($partial | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($true)))
        }
        $rr = Merge-Mailbox -SrcDir $rc -DstDir $emptyDst
        foreach ($f in $files) {
            $a = @((Read-JsonFile $f.FullName).items | ForEach-Object { $_.meta.id } | Sort-Object)
            $b2 = @((Read-JsonFile (Join-Path $emptyDst $f.Name)).items | ForEach-Object { $_.meta.id } | Sort-Object)
            if (($a -join ',') -ne ($b2 -join ',')) { $okAll = $false }
        }
        Ok ($okAll -and $rr.Failed -eq 0) "Echte Mailbox ($($files.Count) Dateien): Merge rekonstruiert alle Nachrichten-IDs" "failed=$($rr.Failed)"
        $rr2 = Merge-Mailbox -SrcDir $rc -DstDir $emptyDst
        Ok ($rr2.Added -eq 0) 'Echte Mailbox: zweiter Merge = no-op'
        # semantischer Vergleich eines Roundtrips (parse→write→parse)
        $f0 = $files | Sort-Object Length -Descending | Select-Object -First 1
        $copy = Join-Path $tmp 'rt.dat'; Write-JsonFile (Read-JsonFile $f0.FullName) $copy
        $j1 = (Read-JsonFile $f0.FullName) | ConvertTo-Json -Depth 100 -Compress
        $j2 = (Read-JsonFile $copy) | ConvertTo-Json -Depth 100 -Compress
        Ok ($j1 -eq $j2) 'Roundtrip parse→write→parse semantisch identisch (größte echte Datei)'
        $t1 = [IO.File]::ReadAllText($f0.FullName, [Text.Encoding]::UTF8); $t2 = [IO.File]::ReadAllText($copy, [Text.Encoding]::UTF8)
        $nonAscii1 = ([regex]::Matches($t1, '[^\u0000-\u007F]')).Count; $nonAscii2 = ([regex]::Matches($t2, '[^\u0000-\u007F]')).Count
        Write-Host ("        Info: Zeichen >127 Original={0}, Roundtrip={1}; Bytes {2} → {3}" -f $nonAscii1, $nonAscii2, (Get-Item $f0.FullName).Length, (Get-Item $copy).Length) -ForegroundColor DarkGray
    } else { Write-Host '  (übersprungen – -RealDataDir nicht angegeben)' -ForegroundColor DarkGray }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host ("Ergebnis: {0} bestanden, {1} fehlgeschlagen" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
