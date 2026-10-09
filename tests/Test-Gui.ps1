#Requires -Version 5.1
# GUI-Test: baut das Fenster ohne ShowDialog, rendert jedes Panel in jeder Sprache,
# prüft Textüberlauf, speichert Screenshots (tests\shots\) und fährt Backup/Restore/Merge/Sync über die Buttons.
param([string]$RealDataDir = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing

$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$n, $d = '') { if ($c) { $script:pass++; Write-Host "  PASS  $n" -ForegroundColor Green } else { $script:fail++; Write-Host "  FAIL  $n  $d" -ForegroundColor Red } }

# Fixture
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rf4gui_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$me = Join-Path $tmp 'Users\tester'; New-Item -ItemType Directory -Force -Path (Join-Path $me 'AppData\Roaming\RussianFishingLLC') | Out-Null
$env:APPDATA = Join-Path $me 'AppData\Roaming'; $env:USERPROFILE = $me; $env:USERNAME = 'tester'
$env:RF4_NO_DRIVE_SCAN = '1'; $env:RF4_GUI_NOSHOW = '1'; $env:RF4_LANG = 'de'
$base = Join-Path $env:APPDATA 'RussianFishingLLC'
function New-Msg([string]$id, [long]$c) { [pscustomobject]@{ meta = [pscustomobject]@{ id = $id; created = $c; text = 'x'; items = @() }; status = 1 } }
function New-Dat($path, $msgs) { New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null; [IO.File]::WriteAllText($path, ([pscustomobject]@{ id = 1; items = @($msgs) } | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($true))) }
foreach ($v in 'RussianFishing4Steam', 'RussianFishing4DE') {
    foreach ($acc in 1..2) { foreach ($n in 1..3) { New-Dat (Join-Path $base "$v\Mailbox_$acc$acc$acc\$n.dat") @((New-Msg "$v-$acc-$n-a" 1), (New-Msg "$v-$acc-$n-b" 2)) } }
}
Set-Content (Join-Path $base 'RussianFishing4Steam\Settings.dat') 'steam'
$shotDir = Join-Path $me 'Documents\Russian Fishing 4\Screenshots'; New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
1..2 | ForEach-Object { Set-Content (Join-Path $shotDir "s$_.png") 'x' }

$shotsOut = Join-Path $PSScriptRoot 'shots'; New-Item -ItemType Directory -Force -Path $shotsOut | Out-Null
try {
    # GUI laden (dot-source → Funktionen und $form im Scope dieses Skripts)
    . (Join-Path $root 'rf4sa-backup-gui.ps1') -Lang de
    $dialogs = New-Object System.Collections.Generic.List[string]
    function Show-Msg([string]$Text, [string]$Kind = 'Warning', [string]$Buttons = 'OK') { $dialogs.Add($Text); if ($Buttons -eq 'YesNo') { return 'Yes' } return 'OK' }
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()

    function Walk($ctl) { foreach ($c in $ctl.Controls) { $c; Walk $c } }
    function Test-Overflow([string]$tag) {
        $bad = @()
        foreach ($c in @(Walk $form)) {
            if (-not $c.Visible -or [string]::IsNullOrEmpty($c.Text)) { continue }
            if ($c -is [System.Windows.Forms.Label]) {
                $sz = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font, (New-Object System.Drawing.Size($c.Width, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
                if ($sz.Height -gt $c.Height + 2) { $bad += "Label '$($c.Text.Substring(0,[Math]::Min(40,$c.Text.Length)))' h=$($sz.Height)>$($c.Height)" }
            } elseif ($c -is [System.Windows.Forms.Button]) {
                $sz = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font)
                if ($sz.Width -gt $c.Width - 8) { $bad += "Button '$($c.Text)' w=$($sz.Width)>$($c.Width - 8)" }
            } elseif ($c -is [System.Windows.Forms.CheckBox]) {
                $sz = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font)
                if ($sz.Width + 22 -gt $c.Width) { $bad += "Check '$($c.Text)'" }
            } elseif ($c -is [System.Windows.Forms.ListBox]) {
                foreach ($it in $c.Items) { $s = [string]$it; if (-not $s) { continue }; $sz = [System.Windows.Forms.TextRenderer]::MeasureText($s, $c.Font); if ($sz.Width -gt $c.Width - 6) { $bad += "ListItem '$($s.Substring(0,[Math]::Min(40,$s.Length)))…' w=$($sz.Width)>$($c.Width)" } }
            }
        }
        return $bad
    }
    function Snap([string]$name) {
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save((Join-Path $shotsOut "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }

    Write-Host "`n[1] Alle Panels in allen Sprachen" -ForegroundColor Cyan
    $script:state.Action = 'backup'
    foreach ($lang in $script:Langs) {
        Set-Language $lang
        Ok ($form.Text -match [regex]::Escape((T 'app_title'))) "($lang) Fenstertitel übersetzt: $($form.Text)"
        Ok ($cmbLang.SelectedIndex -eq [Array]::IndexOf($script:Langs, $lang)) "($lang) Sprach-ComboBox folgt Set-Language"
        Ok (($lblTitle.Text -match '&') -eq ((T 'app_title') -match '&') -and -not $lblTitle.UseMnemonic) "($lang) Titel-Label zeigt & (UseMnemonic aus)"
        $panels = [ordered]@{ scan = { Render-Scan }; action = { Render-Action }; backup = { Render-Backup }; restore = { Render-Restore }; merge = { Render-Merge }; sync = { Render-Sync } }
        foreach ($k in $panels.Keys) {
            try {
                Show-Panel $panels[$k]; [System.Windows.Forms.Application]::DoEvents()
                $bad = @(Test-Overflow $k)
                Ok ($bad.Count -eq 0) "($lang) Panel '$k' ohne Textüberlauf" ($bad -join ' | ')
                Snap "$lang-$k"
                $untranslated = @(Walk $form | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -match '^[a-z_]+\.?[a-z_]*$' -and ($script:TX.Keys -ccontains $_.Text) })
                Ok ($untranslated.Count -eq 0) "($lang) Panel '$k' ohne rohe Schlüssel"
            } catch { Ok $false "($lang) Panel '$k' rendert" $_.Exception.Message }
        }
    }
    Set-Language 'de'

    Write-Host "`n[2] Sprachwechsel über die ComboBox" -ForegroundColor Cyan
    Show-Panel { Render-Action }
    $before = (Walk $form | Where-Object { $_ -is [System.Windows.Forms.Label] } | ForEach-Object Text) -join '|'
    $cmbLang.SelectedIndex = [Array]::IndexOf($script:Langs, 'ru')
    [System.Windows.Forms.Application]::DoEvents()
    $after = (Walk $form | Where-Object { $_ -is [System.Windows.Forms.Label] } | ForEach-Object Text) -join '|'
    Ok ($script:Lang -eq 'ru' -and $before -ne $after) 'ComboBox schaltet auf Russisch und baut Panel neu auf'
    Ok ((Get-Config).lang -eq 'ru') 'Sprache persistent gespeichert'
    Ok ($after -match '[Ѐ-ӿ]') 'Panel enthält kyrillischen Text'
    $cmbLang.SelectedIndex = [Array]::IndexOf($script:Langs, 'de'); [System.Windows.Forms.Application]::DoEvents()

    Write-Host "`n[3] Funktions-Läufe über die Buttons" -ForegroundColor Cyan
    function Find-Btn([string]$key) { $t = T $key; @(Walk $form | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq $t })[0] }
    $script:state.Installs = $null; Show-Panel { Render-Scan }; [System.Windows.Forms.Application]::DoEvents()
    Ok (@($script:state.Installs | Where-Object Exists).Count -eq 2) 'Scan findet Steam + DE'
    Ok ($script:btnScanNext.Enabled) '"Weiter" nach Scan aktiv'

    # Backup (Steam, alle Accounts)
    $bk = Join-Path $tmp 'bk'
    Show-Panel { Render-Backup }
    $lst = @(Walk $form | Where-Object { $_ -is [System.Windows.Forms.ListBox] })[0]
    $script:lstSrc.SelectedIndex = [Array]::FindIndex($script:exSrc, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4Steam' })
    $script:txtDir.Text = $bk
    foreach ($c in $script:bkChecks) { $c.Checked = $true }
    Ok ($null -ne $script:cmbAcct -and $script:cmbAcct.Items.Count -eq 3) 'Account-Auswahl bei 2 Mailboxen sichtbar (Alle + 2)'
    (Find-Btn 'run_backup').PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Ok (@(Get-Mailboxes $bk).Count -eq 2) 'Backup: 2 Mailboxen im Zielordner'
    Ok ((Test-Path (Join-Path $bk 'Settings.dat')) -and @(Get-ChildItem (Join-Path $bk 'Screenshots') -ea SilentlyContinue).Count -eq 2) 'Backup: Settings + 2 Screenshots'
    Ok ($script:state.Render.ToString() -match 'Render-Result') 'Backup endet im Ergebnis-Panel'
    Ok ($script:RunLog.ToString() -match '\[OK\]') 'Ergebnis-Log enthält [OK]-Zeilen'
    Snap 'de-result'

    # Backup nur ein Account
    $bk2 = Join-Path $tmp 'bk2'
    Show-Panel { Render-Backup }
    $script:lstSrc.SelectedIndex = 0; $script:txtDir.Text = $bk2
    for ($i = 0; $i -lt $script:bkChecks.Count; $i++) { $script:bkChecks[$i].Checked = ($script:bkKeys[$i] -eq 'mail') }
    $script:cmbAcct.SelectedIndex = 2
    (Find-Btn 'run_backup').PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Ok ((@(Get-Mailboxes $bk2).Count -eq 1)) 'Backup mit Account-Filter: genau 1 Mailbox'

    # Restore in neue Installation (EN, existiert noch nicht)
    Show-Panel { Render-Restore }
    $script:txtDir.Text = $bk; [System.Windows.Forms.Application]::DoEvents()
    Ok ($script:lstPrev.Items.Count -ge 4) "Restore-Vorschau zeigt Inhalt ($($script:lstPrev.Items.Count) Zeilen)"
    $enIdx = [Array]::FindIndex($script:rsIns, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4EN' })
    $script:lstDst.SelectedIndex = $enIdx
    (Find-Btn 'run_restore').PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    $enPath = Join-Path $base 'RussianFishing4EN'
    Ok ((@(Get-Mailboxes $enPath).Count -eq 2) -and (Test-Path (Join-Path $enPath 'Settings.dat'))) 'Restore: Mailboxen + Settings in neuer EN-Installation'

    # Merge DE ← Steam (gleiche Dateinamen, andere Nachrichten)
    Show-Panel { Render-Merge }
    $script:state.Installs = @(Find-Installations); Show-Panel { Render-Merge }
    $deI = [Array]::FindIndex($script:mgEx, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4DE' })
    $stI = [Array]::FindIndex($script:mgEx, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4Steam' })
    $script:lstMgDst.SelectedIndex = $deI; $script:lstMgSrc.SelectedIndices.Clear(); $script:lstMgSrc.SelectedIndices.Add($stI) | Out-Null
    (Find-Btn 'run_merge').PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    $ids = @((Read-JsonFile (Join-Path $base 'RussianFishing4DE\Mailbox_111\1.dat')).items | ForEach-Object { $_.meta.id })
    Ok ($ids.Count -eq 4) "Merge: DE-Konversation hat 4 Nachrichten (2 eigene + 2 aus Steam)" "$($ids -join ',')"
    Ok (Test-Path (Join-Path $base 'RussianFishing4DE\_rf4tool_undo')) 'Merge legt Undo-Ordner an'
    # Quelle = Ziel
    Show-Panel { Render-Merge }; $dialogs.Clear()
    $script:lstMgDst.SelectedIndex = 0; $script:lstMgSrc.SelectedIndices.Clear(); $script:lstMgSrc.SelectedIndices.Add(0) | Out-Null
    (Find-Btn 'run_merge').PerformClick()
    Ok ($dialogs.Count -eq 1 -and $dialogs[0] -eq (T 'merge_same')) 'Merge: Quelle=Ziel wird abgefangen'

    # Sync
    $nas = Join-Path $tmp 'nas'; New-Item -ItemType Directory -Force -Path $nas | Out-Null
    Show-Panel { Render-Sync }
    $script:txtSync.Text = $nas; $script:lstSyInst.SelectedIndex = 0
    (Find-Btn 'sync_run').PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Ok (@(Get-Mailboxes (Join-Path $nas 'RF4_Sync')).Count -ge 2) 'Sync: Mailboxen im Sync-Ordner'
    Ok ((Get-SyncPath) -eq $nas) 'Sync-Ordner wurde gespeichert'
    Show-Panel { Render-Sync }; (Find-Btn 'sync_status').PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Ok ($script:lstSySt.Items.Count -ge 3) 'Sync-Status listet Mailboxen/Log'
    # Sync ohne Ordner
    $dialogs.Clear(); $script:txtSync.Text = ''; (Find-Btn 'sync_run').PerformClick()
    Ok ($dialogs.Count -eq 1) 'Sync ohne Ordner: Hinweisdialog'

    Write-Host "`n[4] Fehlerfälle" -ForegroundColor Cyan
    Show-Panel { Render-Restore }; $script:txtDir.Text = (Join-Path $tmp 'gibtsnicht'); [System.Windows.Forms.Application]::DoEvents()
    Ok ($script:lstPrev.Items[0] -match 'gibtsnicht') 'Restore: nicht vorhandener Ordner → Hinweis in Vorschau'
    $dialogs.Clear(); (Find-Btn 'run_restore').PerformClick()
    Ok ($dialogs.Count -eq 1) 'Restore ohne gültiges Backup: Hinweisdialog'
    Show-Panel { Render-Backup }; for ($i = 0; $i -lt $script:bkChecks.Count; $i++) { $script:bkChecks[$i].Checked = $false }
    $dialogs.Clear(); (Find-Btn 'run_backup').PerformClick()
    Ok ($dialogs.Count -eq 1 -and $dialogs[0] -eq (T 'pick_item')) 'Backup ohne Auswahl: Hinweis'
}
finally {
    try { $form.Close(); $form.Dispose() } catch { }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host ("Ergebnis: {0} bestanden, {1} fehlgeschlagen" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
