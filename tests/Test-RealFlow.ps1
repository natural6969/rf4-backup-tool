#Requires -Version 5.1
# Durchlauf ALLER Funktionen mit ECHTEN Dialogen auf den Fake-Installationen (tools\fake-installs.ps1) im echten Profil.
#   - Steam/Standalone-Originale werden NIE geschrieben (Sicherung: Abbruch, wenn ein Ziel nicht RussianFishing4TEST_* ist)
#   - Backups/NAS liegen in %TEMP%; die Programm-Einstellungen (settings.json) werden gesichert und wiederhergestellt
#   - Dialoge (RF4 läuft / Überschreiben / Fehler) werden per Timer automatisch beantwortet
# Aufruf: powershell -STA -File tests\Test-RealFlow.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$n, $d = '') { if ($c) { $script:pass++; Write-Host "  PASS  $n" -ForegroundColor Green } else { $script:fail++; Write-Host "  FAIL  $n  $d" -ForegroundColor Red } }

$base = Join-Path $env:APPDATA 'RussianFishingLLC'
$cfgFile = Join-Path $env:APPDATA 'rf4-backup\settings.json'
$cfgBackup = if (Test-Path $cfgFile) { [IO.File]::ReadAllBytes($cfgFile) } else { $null }
$work = Join-Path ([IO.Path]::GetTempPath()) ('rf4real_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $work | Out-Null
& (Join-Path $root 'tools\fake-installs.ps1') -Create *>$null          # frischer Ausgangszustand
$fakeA = Join-Path $base 'RussianFishing4TEST_A'; $fakeB = Join-Path $base 'RussianFishing4TEST_B'; $fakeC = Join-Path $base 'RussianFishing4TEST_C'
$steam = Join-Path $base 'RussianFishing4Steam'
$steamHashBefore = (Get-ChildItem $steam -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join ''

$env:RF4_GUI_NOSHOW = '1'; $env:RF4_NO_DRIVE_SCAN = '1'; $env:RF4_LANG = 'de'; $env:RF4_THEME_BASE = 'dark'
function Count-Msgs([string]$dir) { $n = 0; foreach ($f in (Get-ChildItem $dir -Recurse -Filter '*.dat' -File | ? { $_.DirectoryName -match 'Mailbox_' })) { $n += @((([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) | ConvertFrom-Json).items).Count }; $n }
function Count-Convs([string]$dir) { @(Get-ChildItem $dir -Recurse -Filter '*.dat' -File | ? { $_.DirectoryName -match 'Mailbox_' }).Count }

try {
    . (Join-Path $root 'rf4sa-backup-gui.ps1') -Lang de
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    function Pump { [System.Windows.Forms.Application]::DoEvents() }
    function Walk($ctl) { foreach ($c in $ctl.Controls) { $c; Walk $c } }
    # Dialog-Beantworter: klickt in jedem Nebenfenster den gewünschten Button und merkt sich den Text
    $script:dialogLog = New-Object System.Collections.Generic.List[string]
    $script:answers = New-Object System.Collections.Generic.Queue[string]
    $script:answerTimer = New-Object System.Windows.Forms.Timer; $script:answerTimer.Interval = 250
    $script:answerTimer.Add_Tick({
        foreach ($f in @([System.Windows.Forms.Application]::OpenForms)) {
            if ($f -eq $script:form) { continue }
            $lbl = @($f.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })[0]
            $btns = @($f.Controls | Where-Object { $_ -is [Rf4Ui.UButton] })
            if (-not $btns.Count) { continue }
            $want = if ($script:answers.Count) { $script:answers.Dequeue() } else { 'yes' }
            $script:dialogLog.Add($(if ($lbl) { $lbl.Text } else { '?' }))
            $target = switch ($want) { 'yes' { T 'dialog_yes' } 'no' { T 'dialog_no' } default { T 'dialog_ok' } }
            $b = @($btns | Where-Object { $_.Text -eq $target })[0]; if (-not $b) { $b = $btns[0] }
            $b.PerformClick()
        }
    })
    $script:answerTimer.Start()
    function Answer([string[]]$a) { $script:answers.Clear(); foreach ($x in $a) { $script:answers.Enqueue($x) } }
    function Click-Primary { $script:btnPrimary.PerformClick(); Pump }
    function Card-Index($cards, [string]$folder) { for ($i = 0; $i -lt $cards.Count; $i++) { if ($cards[$i].Tag2 -and $cards[$i].Tag2.Folder -eq $folder) { return $i } }; return -1 }

    Write-Host "`n[1] Scan: echte + Fake-Installationen" -ForegroundColor Cyan
    $script:state.Installs = $null; Show-Panel { Render-Scan }; Pump
    $cardsScan = @(Walk $script:pContent | Where-Object { $_ -is [Rf4Ui.UCardList] })[0]
    $ex = @($script:state.Installs | Where-Object Exists)
    Ok (@($ex | Where-Object { $_.Folder -like 'RussianFishing4TEST_*' }).Count -eq 3) "3 Fake-Installationen gefunden (zusätzlich $(@($ex | Where-Object { $_.Folder -notlike 'RussianFishing4TEST_*' }).Count) echte)"
    Ok ($cardsScan.Cards.Count -ge 6) "Scan-Liste hat $($cardsScan.Cards.Count) Karten"
    # Scroll: Liste ist scrollbar und das Mausrad (auch über einer Karte) bewegt sie
    $form.ClientSize = New-Object System.Drawing.Size((S 900), (S 520)); Pump; Show-Panel { Render-Scan }; Pump
    $cardsScan = @(Walk $script:pContent | Where-Object { $_ -is [Rf4Ui.UCardList] })[0]
    Ok ($cardsScan.VerticalScroll.Visible) 'Kleines Fenster: Liste zeigt Scrollbalken'
    Add-Type -Namespace W32 -Name N -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);'
    $card0 = $cardsScan.Cards[0]; $y0 = -$cardsScan.AutoScrollPosition.Y
    $wheel = [IntPtr](-120 * 65536 -band 0xFFFFFFFF); [void][W32.N]::SendMessage($card0.Handle, 0x020A, [IntPtr]([int64](-120) -shl 16), [IntPtr]0); Pump
    Ok ((-$cardsScan.AutoScrollPosition.Y) -gt $y0) "Mausrad über einer Karte scrollt die Liste ($y0 → $(-$cardsScan.AutoScrollPosition.Y))"
    $form.ClientSize = New-Object System.Drawing.Size((S 1000), (S 740)); Pump

    Write-Host "`n[2] Backup von TEST_B (2 Accounts) mit Info-Datei" -ForegroundColor Cyan
    $bkDir = Join-Path $work 'bk_all'
    $script:state.Action = 'backup'; Show-Panel { Render-Backup }; Pump
    $script:lstSrc.Cards[(Card-Index $script:lstSrc.Cards 'RussianFishing4TEST_B')].PerformClick()
    foreach ($c in $script:bkChecks) { $c.Checked = $true }
    $script:inDir.Text = $bkDir
    Answer @('yes'); Click-Primary
    $info = Read-BackupInfo $bkDir
    Ok ($info -and $info.Folder -eq 'RussianFishing4TEST_B' -and $info.Created -match '^\d{4}-\d\d-\d\d \d\d:\d\d$' -and $info.Host -eq $env:COMPUTERNAME) "Info-Datei: Quelle $($info.Folder), erstellt $($info.Created), PC $($info.Host)"
    Ok ((Count-Convs $bkDir) -eq (Count-Convs $fakeB)) "Backup hat alle Konversationen von B ($(Count-Convs $bkDir))"
    Ok ($script:state.Step -eq 4) 'Backup endet im Ergebnis-Panel'
    # zweites Backup von A in denselben Ordner → inkrementell, Historie
    Start-Sleep -Milliseconds 1100
    $script:state.Action = 'backup'; Show-Panel { Render-Backup }; Pump
    Ok ($script:lblBkHint -ne $null) 'Backup-Panel hat Hinweiszeile'
    $script:lstSrc.Cards[(Card-Index $script:lstSrc.Cards 'RussianFishing4TEST_A')].PerformClick(); $script:inDir.Text = $bkDir; Pump
    Ok ($script:lblBkHint.Text -match 'TEST_B') "Hinweis zeigt vorhandenes Backup: '$($script:lblBkHint.Text.Substring(0,[Math]::Min(90,$script:lblBkHint.Text.Length)))…'"
    foreach ($c in $script:bkChecks) { $c.Checked = $true }
    Answer @('yes', 'yes'); Click-Primary
    $info2 = Read-BackupInfo $bkDir
    Ok ($info2.Folder -eq 'RussianFishing4TEST_A' -and $info2.Created -eq $info.Created -and @($info2.History).Count -eq 2) "Info nach 2. Backup: Quelle A, Erstelldatum bleibt, Historie $(@($info2.History).Count)"

    Write-Host "`n[3] Restore: Liste zeigt Quelle + Datum, Ziel C, Dialoge" -ForegroundColor Cyan
    $env:RF4_BACKUP_DIRS = $work
    Show-Panel { Render-Restore }; Pump
    $bk = @($script:rsBackups | Where-Object { $_.Path -eq $bkDir })[0]
    Ok ($bk -and $bk.SourceLabel -match 'TEST_A' -and $bk.Updated -match '\d{4}') "Backup in Liste mit Quelle: $($bk.SourceLabel)"
    $card = $script:lstBk.Cards[[Array]::IndexOf(@($script:rsBackups | % Path), $bkDir)]
    Ok ($card.Sub -match 'TEST_A' -and $card.Sub -match 'Erstellt' -and $card.Sub -match 'Mailboxen') 'Karte zeigt Pfad, Quelle, Inhalt, Erstellt/Aktualisiert'
    Ok (-not $card.Overflows()) 'Karte: Text nicht abgeschnitten'
    $card.PerformClick(); Pump
    $script:lstDst.Cards[(Card-Index $script:lstDst.Cards 'RussianFishing4TEST_C')].PerformClick()
    $env:RF4_FAKE_RUNNING = 'rf4_x64'                   # simuliert laufendes Spiel → Warndialog
    $script:dialogLog.Clear(); Answer @('no')            # erst ablehnen
    Click-Primary
    Ok ($script:dialogLog.Count -eq 1 -and $script:dialogLog[0] -match 'rf4_x64' -and $script:state.Step -eq 2) 'RF4 läuft: Warndialog, "Nein" bricht ab (kein Absturz)'
    $before = Count-Convs $fakeC
    $script:dialogLog.Clear(); Answer @('yes', 'yes', 'yes', 'yes'); Click-Primary
    $env:RF4_FAKE_RUNNING = ''
    Ok ($script:dialogLog.Count -ge 1 -and $script:state.Step -eq 4) 'RF4 läuft: "Ja" → Restore läuft durch'
    $convA = Count-Convs $fakeA; $convB = Count-Convs $fakeB; $convC = Count-Convs $fakeC
    Ok ($convC -gt $before -and $convC -ge [Math]::Max($convA, $convB)) "Restore nach C: $before → $convC Konversationen (A=$convA, B=$convB)"
    Ok (@($script:statCtls).Count -ge 3) 'Ergebnis-Kacheln vorhanden'

    Write-Host "`n[4] Merge: A ← B (mit Warn- und Überschreiben-Dialogen)" -ForegroundColor Cyan
    $msgsBefore = Count-Msgs $fakeA; $convBefore = Count-Convs $fakeA
    $script:state.Installs = $null; Show-Panel { Render-Merge }; Pump
    $script:lstMgDst.Cards[(Card-Index $script:lstMgDst.Cards 'RussianFishing4TEST_A')].PerformClick()
    $script:lstMgSrc.Cards[(Card-Index $script:lstMgSrc.Cards 'RussianFishing4TEST_B')].PerformClick()
    $env:RF4_FAKE_RUNNING = 'rf4_x64'; $script:dialogLog.Clear(); Answer @('yes'); Click-Primary; $env:RF4_FAKE_RUNNING = ''
    $msgsAfter = Count-Msgs $fakeA; $convAfter = Count-Convs $fakeA
    Ok ($msgsAfter -gt $msgsBefore -and $convAfter -gt $convBefore) "Merge A←B: Nachrichten $msgsBefore → $msgsAfter, Konversationen $convBefore → $convAfter"
    $statMsg = @($script:statCtls | Where-Object { $_.Caption -eq (T 'sum_msgs') })[0]
    Ok ($statMsg -and [int]$statMsg.Value -gt 0) "Ergebnis zeigt ergänzte Nachrichten ($($statMsg.Value))"
    Ok ((Count-Msgs $fakeA) -eq (Count-Msgs $fakeA)) 'Idempotenz-Vorbereitung'
    # zweiter Lauf: nichts mehr zu tun
    $script:state.Installs = $null; Show-Panel { Render-Merge }; Pump
    $script:lstMgDst.Cards[(Card-Index $script:lstMgDst.Cards 'RussianFishing4TEST_A')].PerformClick(); $script:lstMgSrc.Cards[(Card-Index $script:lstMgSrc.Cards 'RussianFishing4TEST_B')].PerformClick(); Click-Primary
    $statMsg2 = @($script:statCtls | Where-Object { $_.Caption -eq (T 'sum_msgs') })[0]
    Ok ($statMsg2.Value -eq '0' -and (Count-Msgs $fakeA) -eq $msgsAfter) 'Zweiter Merge: 0 neue Nachrichten (idempotent)'
    # Merge mit zwei Accounts: B hat Mailbox_111111 → A bekommt ihn
    Ok (Test-Path (Join-Path $fakeA 'Mailbox_111111')) 'Zweiter Account (Mailbox_111111) wurde mit übernommen'

    Write-Host "`n[5] Restore mit abweichender Settings.dat → Überschreiben-Dialog" -ForegroundColor Cyan
    $sA = [IO.File]::ReadAllText((Join-Path $fakeA 'Settings.dat'));
    Show-Panel { Render-Restore }; Pump
    $card = $script:lstBk.Cards[[Array]::IndexOf(@($script:rsBackups | % Path), $bkDir)]; $card.PerformClick()
    # in dem Backup liegt Settings.dat von A (zuletzt gesichert); ändere A lokal, damit sie abweicht
    [IO.File]::WriteAllText((Join-Path $fakeA 'Settings.dat'), $sA + "`r`n# lokal geändert", (New-Object Text.UTF8Encoding($true)))
    $script:lstDst.Cards[(Card-Index $script:lstDst.Cards 'RussianFishing4TEST_A')].PerformClick()
    $script:dialogLog.Clear(); Answer @('no'); Click-Primary
    Ok ($script:dialogLog.Count -eq 1 -and $script:dialogLog[0] -match 'Settings.dat') 'Überschreiben-Dialog erscheint für Settings.dat'
    Ok ([IO.File]::ReadAllText((Join-Path $fakeA 'Settings.dat')) -match 'lokal geändert') '"Nein" lässt die lokale Datei unverändert'
    Ok (@($script:statCtls | Where-Object { $_.Caption -eq (T 'sum_skipped') }).Count -eq 1) 'Ergebnis zeigt "übersprungen"'
    Show-Panel { Render-Restore }; Pump
    $card = $script:lstBk.Cards[[Array]::IndexOf(@($script:rsBackups | % Path), $bkDir)]; $card.PerformClick()
    $script:lstDst.Cards[(Card-Index $script:lstDst.Cards 'RussianFishing4TEST_A')].PerformClick()
    $script:dialogLog.Clear(); Answer @('yes'); Click-Primary
    Ok ([IO.File]::ReadAllText((Join-Path $fakeA 'Settings.dat')) -notmatch 'lokal geändert') '"Ja" ersetzt die Datei'
    $undoFiles = @(Get-ChildItem (Join-Path $fakeA '_rf4tool_undo') -Recurse -Filter 'Settings.dat' -ErrorAction SilentlyContinue)
    Ok ($undoFiles.Count -ge 1 -and ([IO.File]::ReadAllText($undoFiles[-1].FullName) -match 'lokal geändert')) 'Ersetzte Datei liegt im Undo-Ordner'

    Write-Host "`n[6] Sync A ↔ B über Netzlaufwerk-Ordner (NAS)" -ForegroundColor Cyan
    $nas = Join-Path $work 'omv_nas'; New-Item -ItemType Directory -Force -Path $nas | Out-Null
    # Ausgangslage: B hat 1 Konversation, die A nicht hat (neu anlegen)
    $mbd = Get-ChildItem $steam -Directory -Filter 'Mailbox_*' | Select-Object -First 1; $extra = Get-ChildItem $mbd.FullName -Filter '*.dat' | Select-Object -First 1
    $stray = Join-Path $fakeB 'Mailbox_222222'; New-Item -ItemType Directory -Force -Path $stray | Out-Null; Copy-Item $extra.FullName $stray
    foreach ($which in 'RussianFishing4TEST_A', 'RussianFishing4TEST_B', 'RussianFishing4TEST_A') {
        Show-Panel { Render-Sync }; Pump
        $script:inSync.Text = $nas; $script:lstSyInst.Cards[(Card-Index $script:lstSyInst.Cards $which)].PerformClick()
        $env:RF4_FAKE_RUNNING = 'rf4_x64'; Answer @('yes'); Click-Primary; $env:RF4_FAKE_RUNNING = ''
    }
    Ok ((Test-Path (Join-Path $fakeA 'Mailbox_222222')) -and (Test-Path (Join-Path $nas 'RF4_Sync\Mailbox_222222'))) 'Sync: neue Konversation von B kam über das NAS zu A'
    Ok ((Count-Msgs $fakeA) -eq (Count-Msgs $fakeB)) "Nach Sync haben A und B gleich viele Nachrichten ($(Count-Msgs $fakeA))"
    Show-Panel { Render-Sync }; Pump; $script:btnExtra.PerformClick(); Pump
    Ok ($script:lstSySt.Cards.Count -ge 4) "Sync-Status listet Mailboxen/Log ($($script:lstSySt.Cards.Count) Zeilen)"
    Ok ((Get-SyncPath) -eq $nas) 'Sync-Ordner gespeichert'

    Write-Host "`n[7] Fehlerfälle: Absturz-Schutz und Fehler im Ablauf" -ForegroundColor Cyan
    $script:dialogLog.Clear(); Answer @('ok')
    # unerwartete Ausnahme in einem Ereignis → freundlicher Dialog, Programm läuft weiter
    $script:pHeader.Add_Click({ throw 'Absichtlicher Testfehler' }); $script:pHeader.PerformLayout()
    [System.Windows.Forms.Application]::OpenForms | Out-Null
    $mi = $script:pHeader.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance'); try { $mi.Invoke($script:pHeader, @([EventArgs]::Empty)) } catch { }
    Start-Sleep -Milliseconds 800; Pump
    Ok ($script:dialogLog.Count -ge 0 -and -not $form.IsDisposed) 'Programm lebt nach einem Fehler im Ereignis weiter'
    # Backup-Ziel nicht schreibbar (gesperrte Datei als Ordnername) → Fehler im Ergebnis statt Absturz
    $blocker = Join-Path $work 'blocker.txt'; Set-Content $blocker 'x'
    $script:state.Action = 'backup'; Show-Panel { Render-Backup }; Pump
    $script:lstSrc.Cards[(Card-Index $script:lstSrc.Cards 'RussianFishing4TEST_A')].PerformClick(); $script:inDir.Text = (Join-Path $blocker 'unterordner')
    Answer @('yes'); Click-Primary
    Ok ($script:state.Step -eq 4) 'Backup in unmögliches Ziel: Ergebnis-Panel statt Absturz'
    Ok (@($script:statCtls | Where-Object { $_.Caption -eq (T 'sum_failed') }).Count -ge 1 -or $script:RunLog.ToString() -match '\[X\]') 'Fehler wird im Ergebnis angezeigt'

    Write-Host "`n[8] Die echten Originale wurden nicht verändert" -ForegroundColor Cyan
    $steamHashAfter = (Get-ChildItem $steam -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join ''
    Ok ($steamHashBefore -eq $steamHashAfter) 'Steam-Installation: alle Dateien bit-identisch'
    Ok (-not (Test-Path (Join-Path $steam '_rf4tool_undo'))) 'Kein Undo-Ordner in der echten Installation'
}
finally {
    try { $script:answerTimer.Stop(); $form.Close(); $form.Dispose() } catch { }
    $env:RF4_FAKE_RUNNING = ''; $env:RF4_BACKUP_DIRS = ''
    if ($null -ne $cfgBackup) { [IO.File]::WriteAllBytes($cfgFile, $cfgBackup) } elseif (Test-Path $cfgFile) { [IO.File]::Delete($cfgFile) }
    & (Join-Path $root 'tools\fake-installs.ps1') -Create *>$null          # Fakes für dich wieder frisch
    [IO.Directory]::Delete($work, $true)
}
Write-Host ""
Write-Host ("Ergebnis: {0} bestanden, {1} fehlgeschlagen" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
