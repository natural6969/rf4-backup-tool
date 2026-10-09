#Requires -Version 5.1
# GUI-Test: baut das Fenster ohne ShowDialog und prüft
#   - alle Panels × Themes (dunkel/hell) × Sprachen × Skalierungen auf Textüberlauf/Abschneiden
#   - Sprach- und Designwechsel (Menü-Einträge), Windows-Automatik (RF4_THEME_BASE), Konfig-Speicherung
#   - Funktionsläufe über die echten Buttons/Karten (Backup, Restore mit vorhandenen Backups, Merge, Sync)
#   - speichert Screenshots nach tests\shots\ (mit -NoShots abschaltbar; -ShotDir <Pfad> für anderes Ziel)
param([switch]$NoShots, [string]$ShotDir = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing

$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$n, $d = '') { if ($c) { $script:pass++; Write-Host "  PASS  $n" -ForegroundColor Green } else { $script:fail++; Write-Host "  FAIL  $n  $d" -ForegroundColor Red } }

# ── Fixture ────────────────────────────────────────────────────────────────────
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rf4gui_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$me = Join-Path $tmp 'Users\tester'; New-Item -ItemType Directory -Force -Path (Join-Path $me 'AppData\Roaming\RussianFishingLLC') | Out-Null
$env:APPDATA = Join-Path $me 'AppData\Roaming'; $env:USERPROFILE = $me; $env:USERNAME = 'tester'
$env:RF4_NO_DRIVE_SCAN = '1'; $env:RF4_GUI_NOSHOW = '1'; $env:RF4_LANG = 'de'; $env:RF4_THEME_BASE = 'dark'; $env:RF4_GUI_SCALE = '1.25'
$base = Join-Path $env:APPDATA 'RussianFishingLLC'
function New-Msg([string]$id, [long]$c) { [pscustomobject]@{ meta = [pscustomobject]@{ id = $id; created = $c; text = 'x'; items = @() }; status = 1 } }
function New-Dat($path, $msgs) { New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null; [IO.File]::WriteAllText($path, ([pscustomobject]@{ id = 1; items = @($msgs) } | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($true))) }
foreach ($v in 'RussianFishing4Steam', 'RussianFishing4DE') {
    foreach ($acc in 1..2) { foreach ($n in 1..3) { New-Dat (Join-Path $base "$v\Mailbox_$acc$acc$acc\$n.dat") @((New-Msg "$v-$acc-$n-a" 1), (New-Msg "$v-$acc-$n-b" 2)) } }
}
Set-Content (Join-Path $base 'RussianFishing4Steam\Settings.dat') 'steam'
$fxShots = Join-Path $me 'Documents\Russian Fishing 4\Screenshots'; New-Item -ItemType Directory -Force -Path $fxShots | Out-Null
1..2 | ForEach-Object { Set-Content (Join-Path $fxShots "s$_.png") 'x' }
$shotsOut = if ($ShotDir) { $ShotDir } else { Join-Path $PSScriptRoot 'shots' }; if (-not $NoShots) { New-Item -ItemType Directory -Force -Path $shotsOut | Out-Null }

try {
    . (Join-Path $root 'rf4sa-backup-gui.ps1') -Lang de
    $dialogs = New-Object System.Collections.Generic.List[string]
    function Show-Msg([string]$Text, [string]$Kind = 'Warning', [string]$Buttons = 'OK') { $dialogs.Add($Text); if ($Buttons -eq 'YesNo') { return 'Yes' } return 'OK' }
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()

    function Walk($ctl) { foreach ($c in $ctl.Controls) { $c; Walk $c } }
    function Pump { [System.Windows.Forms.Application]::DoEvents() }
    function Set-TestScale([double]$s) {
        $script:Scale = $s
        $form.ClientSize = New-Object System.Drawing.Size((S 1000), (S 740)); Rebuild-All; Pump
    }
    function Test-Overflow {
        $bad = @()
        $cw = $script:pContent.ClientSize.Width
        foreach ($c in @(Walk $form)) {
            if (-not $c.Visible) { continue }
            if ($c -is [System.Windows.Forms.Label] -and $c.Text) {
                $sz = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font, (New-Object System.Drawing.Size($c.Width, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPadding)
                if ($sz.Height -gt $c.Height + 2) { $bad += "Label '$($c.Text.Substring(0,[Math]::Min(40,$c.Text.Length)))' h=$($sz.Height)>$($c.Height)" }
            } elseif ($c -is [Rf4Ui.UButton]) {
                if ($c.Text -and $c.Measure().Width -gt $c.Width + 2) { $bad += "Button '$($c.Text)' w=$($c.Measure().Width)>$($c.Width)" }
            } elseif ($c -is [Rf4Ui.UCard]) {
                if ($c.Overflows()) { $bad += "Karte '$($c.Title.Substring(0,[Math]::Min(40,$c.Title.Length)))' abgeschnitten" }
            } elseif ($c -is [Rf4Ui.UStat]) {
                if ($c.Overflows()) { $bad += "Kachel '$($c.Caption)' abgeschnitten" }
            } elseif ($c -is [Rf4Ui.UCheck]) {
                if ($c.PreferredWidth() -gt $c.Width + 2) { $bad += "Check '$($c.Text)'" }
            }
            if ($c.Parent -eq $script:pContent -and ($c.Right -gt $cw + 2)) { $bad += "$($c.GetType().Name) ragt rechts hinaus ($($c.Right)>$cw)" }
        }
        if ($script:headLang.Left -lt $script:lblTitle.Left + [System.Windows.Forms.TextRenderer]::MeasureText($script:lblTitle.Text, $script:lblTitle.Font).Width) { $bad += 'Kopfzeile: Titel überlappt Sprach-Button' }
        if ($script:btnPrimary.Visible -and $script:btnExtra.Visible -and $script:btnExtra.Right -gt $script:btnPrimary.Left) { $bad += 'Fußzeile: Buttons überlappen' }
        return $bad
    }
    function Snap([string]$name) {
        if ($NoShots) { return }
        Pump; $full = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($full, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        # nur den Client-Bereich speichern (ohne helle Standard-Titelleiste)
        $o = $form.PointToScreen([System.Drawing.Point]::Empty); $dx = $o.X - $form.Left; $dy = $o.Y - $form.Top
        $crop = New-Object System.Drawing.Rectangle($dx, $dy, $form.ClientSize.Width, $form.ClientSize.Height)
        $bmp = $full.Clone($crop, $full.PixelFormat); $full.Dispose()
        $bmp.Save((Join-Path $shotsOut "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
    function Click-Primary { $script:btnPrimary.PerformClick(); Pump }
    function Find-Cards { @(Walk $script:pContent | Where-Object { $_ -is [Rf4Ui.UCardList] }) }

    Write-Host "`n[1] Matrix: Panels × Design × Sprache × Skalierung" -ForegroundColor Cyan
    $script:state.Action = 'backup'
    $dflt = Get-DefaultBackupDir
    Copy-Rf4Data -SrcDir (Join-Path $base 'RussianFishing4Steam') -DstDir $dflt -Items @('mail', 'Settings.dat') -ShotsSrc '' -ShotsDst '' -Confirm { $true }
    $shotsCombos = @('dark/de', 'light/de', 'dark/zh', 'light/ru', 'dark/en')
    foreach ($theme in 'dark', 'light') {
        foreach ($lang in $script:Langs) {
            foreach ($scale in 1.0, 1.5) {
                Save-ThemeChoice $theme; [void](Set-Lang $lang); Save-Lang $lang
                Set-TestScale $scale
                $panels = [ordered]@{ scan = { Render-Scan }; action = { Render-Action }; backup = { Render-Backup }; restore = { Render-Restore }; merge = { Render-Merge }; sync = { Render-Sync } }
                $allBad = @()
                foreach ($k in $panels.Keys) {
                    try {
                        $script:state.Installs = $null; Show-Panel $panels[$k]; Pump
                        $bad = @(Test-Overflow); if ($bad.Count) { $allBad += $bad | ForEach-Object { "$k : $_" } }
                        if ($scale -eq 1.0 -and ("$theme/$lang" -in $shotsCombos)) { Snap "$theme-$lang-$k" }
                        $raw = @(Walk $form | Where-Object { $_ -is [System.Windows.Forms.Label] -and ($script:TX.Keys -ccontains $_.Text) })
                        if ($raw.Count) { $allBad += "$k : roher Schlüssel sichtbar: $($raw[0].Text)" }
                    } catch { $allBad += "$k : Ausnahme $($_.Exception.Message)" }
                }
                Ok ($allBad.Count -eq 0) "$theme · $lang · ${scale}x : 6 Panels ohne Überlauf/Fehler" ($allBad -join ' | ')
            }
        }
    }
    Save-ThemeChoice 'auto'; [void](Set-Lang 'de'); Save-Lang 'de'; Set-TestScale 1.25

    Write-Host "`n[2] Design: automatisch (Windows) + manuell" -ForegroundColor Cyan
    $env:RF4_THEME_BASE = 'light'; Rebuild-All
    Ok ($script:ThemeCode -eq 'light' -and -not [Rf4Ui.UiTheme]::Dark) 'Automatisch folgt Windows-Hell'
    $env:RF4_THEME_BASE = 'dark'; Rebuild-All
    Ok ($script:ThemeCode -eq 'dark' -and [Rf4Ui.UiTheme]::Dark) 'Automatisch folgt Windows-Dunkel'
    Ok ($script:pContent.BackColor.ToArgb() -eq $script:Col.bg.ToArgb() -and $form.BackColor.ToArgb() -eq (ColorOf '#0B1B2B').ToArgb()) 'Dunkel: Hintergrund = Marine #0B1B2B'
    $menu = $script:headTheme.Tag; $labels = @($menu.Items | ForEach-Object { $_.Text })
    Ok ($menu.Items.Count -ge 3) "Design-Menü: Automatisch + alle Themes ($($labels -join ' | '))"
    $menu.Items[1].PerformClick(); Pump
    Ok ((Get-Config).theme -eq $menu.Items[1].Tag) 'Design-Auswahl wird gespeichert'
    Set-ThemeChoice 'light'; Pump
    Ok ($script:ThemeCode -eq 'light' -and $script:pContent.BackColor.ToArgb() -eq (ColorOf '#F3F6FA').ToArgb()) 'Hell: Hintergrund #F3F6FA'
    Ok ($script:Col.accent.ToArgb() -eq (ColorOf '#C77700').ToArgb()) 'Hell: Akzentfarbe Bernstein #C77700 (Kontrast geprüft)'
    Set-ThemeChoice 'auto'

    Write-Host "`n[3] Sprache über das Menü" -ForegroundColor Cyan
    $lm = $script:headLang.Tag
    Ok ($lm.Items.Count -eq $script:Langs.Count) "Sprachmenü listet $($script:Langs.Count) Sprachen"
    $zhIdx = [Array]::IndexOf($script:Langs, 'zh'); $lm.Items[$zhIdx].PerformClick(); Pump
    Ok ($script:Lang -eq 'zh' -and $script:headLang.Text -eq '中文') 'Menü → 中文: Sprache + Button-Text'
    Ok ((Get-Config).lang -eq 'zh') 'Sprache gespeichert'
    Show-Panel { Render-Scan }; Pump
    Ok ($script:lblTitle.Text -eq (T 'app_title') -and $script:btnPrimary.Text -eq (T 'next') -and $script:btnBack.Text -eq (T 'rescan')) 'Titel und Footer-Buttons übersetzt'
    $script:headLang.Tag.Items[[Array]::IndexOf($script:Langs, 'ru')].PerformClick(); Pump
    Ok ($script:Lang -eq 'ru' -and $script:stepper.Steps[4] -eq (T 'step5')) 'Menü → Русский: Stepper übersetzt'
    $script:headLang.Tag.Items[[Array]::IndexOf($script:Langs, 'de')].PerformClick(); Pump

    Write-Host "`n[4] Modularität: externe Sprache + externes Theme" -ForegroundColor Cyan
    $ext = Join-Path $env:APPDATA 'rf4-backup'; New-Item -ItemType Directory -Force -Path "$ext\lang", "$ext\themes" | Out-Null
    [IO.File]::WriteAllText("$ext\lang\xx.lang", "@code=xx`n@name=Testsprache`napp_title=XX Titel`nback=Zurueck-XX`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText("$ext\themes\wald.theme", "@code=wald`n@name=Wald`n@base=dark`nbg=#0E1F14`nsurface=#16301F`naccent=#9BD36B`n", (New-Object Text.UTF8Encoding($false)))
    Initialize-Data; Rebuild-All
    Ok (($script:Langs -contains 'xx') -and $script:LangNames['xx'] -eq 'Testsprache') 'Externe Sprache xx wird geladen'
    Ok ($script:Themes.Contains('wald') -and (Get-ThemeColors 'wald').surface -eq '#16301F' -and (Get-ThemeColors 'wald').text -eq '#E8EEF4') 'Externes Theme: eigene Farben + Rest aus Standard'
    [void](Set-Lang 'xx'); Ok ((T 'app_title') -eq 'XX Titel' -and (T 'next') -eq 'Next') 'Fehlende Schlüssel fallen auf Englisch zurück'
    Set-Language 'xx'; Ok ($script:headLang.Text -eq 'Testsprache') 'Neue Sprache im Menü wählbar'
    Set-ThemeChoice 'wald'; Ok ($script:ThemeCode -eq 'wald' -and (Get-ThemeName 'wald') -eq 'Wald') 'Neues Theme wählbar'
    Remove-Item "$ext\lang", "$ext\themes" -Recurse -Force; Set-ThemeChoice 'auto'; Initialize-Data; Set-Language 'de'

    Write-Host "`n[5] Funktionsläufe über Karten und Buttons" -ForegroundColor Cyan
    $script:state.Installs = $null; Show-Panel { Render-Scan }; Pump
    $lst = @(Find-Cards)[0]
    Ok (@($script:state.Installs | Where-Object Exists).Count -eq 2) 'Scan findet Steam + DE'
    Ok ($lst.Cards.Count -ge 4 -and $script:btnPrimary.Enabled) 'Scan-Liste: vorhandene + mögliche Installationen, "Weiter" aktiv'
    Click-Primary
    Ok ($script:state.Step -eq 1) 'Weiter → Aktions-Auswahl'
    $script:actCards['backup'].PerformClick(); Ok ($script:state.Action -eq 'backup' -and $script:actCards['backup'].Selected -and -not $script:actCards['sync'].Selected) 'Aktions-Karte wählbar (Einfachauswahl)'
    Click-Primary
    Ok ($script:state.Step -eq 2 -and $script:btnPrimary.Text -eq (T 'run_backup')) 'Backup-Panel mit "Backup starten"'

    $bk = Join-Path $tmp 'bk'
    $steamIdx = [Array]::FindIndex($script:exSrc, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4Steam' })
    $script:lstSrc.Cards[$steamIdx].PerformClick()
    $script:inDir.Text = $bk
    foreach ($c in $script:bkChecks) { $c.Checked = $true }
    Ok ($null -ne $script:bkAcct -and @($script:bkAcct.Tag.Items).Count -eq 3) 'Account-Dropdown bei 2 Mailboxen (Alle + 2)'
    Click-Primary
    Ok (@(Get-Mailboxes $bk).Count -eq 2 -and (Test-Path (Join-Path $bk 'Settings.dat')) -and @(Get-ChildItem (Join-Path $bk 'Screenshots') -ea SilentlyContinue).Count -eq 2) 'Backup: 2 Mailboxen, Settings, 2 Screenshots' "mb=$(@(Get-Mailboxes $bk).Count) settings=$(Test-Path (Join-Path $bk 'Settings.dat')) shots=$(@(Get-ChildItem (Join-Path $bk 'Screenshots') -ea SilentlyContinue).Count) log=$($script:RunLog)"
    Ok ($script:state.Step -eq 4 -and $script:statCtls.Count -ge 3) "Ergebnis-Panel mit Kennzahlen ($($script:statCtls.Count) Kacheln)"
    $msgStat = @($script:statCtls | Where-Object { $_.Caption -eq (T 'sum_msgs') })[0]
    Ok ($msgStat -and $msgStat.Value -eq '0') 'Kennzahl "Nachrichten ergänzt" = 0 (alles neu kopiert, nichts gemergt)'
    Ok (-not $script:tbDetails.Visible) 'Details sind eingeklappt'
    $script:btnDetails.PerformClick(); Pump
    Ok ($script:tbDetails.Visible -and $script:tbDetails.Text -match '\[OK\]') 'Details ausklappbar, enthalten [OK]-Zeilen'
    Snap 'result'
    Ok ((Get-Config).backupDirs -contains $bk) 'Backup-Ordner wurde gemerkt'

    $bk2 = Join-Path $tmp 'bk2'; $script:state.Action = 'backup'; Show-Panel { Render-Backup }; Pump
    $script:lstSrc.Cards[$steamIdx].PerformClick(); $script:inDir.Text = $bk2
    for ($i = 0; $i -lt $script:bkChecks.Count; $i++) { $script:bkChecks[$i].Checked = ($script:bkKeys[$i] -eq 'mail') }
    $script:bkAcct.Tag.Items[2].PerformClick(); Pump
    Ok ($script:bkAcctValue -eq 'Mailbox_222' -and $script:bkAcct.Text -match '222') 'Account-Dropdown: Auswahl + Beschriftung'
    Click-Primary
    Ok (@(Get-Mailboxes $bk2).Count -eq 1) 'Backup mit Account-Filter: genau 1 Mailbox'

    Show-Panel { Render-Restore }; Pump
    $bkList = $script:lstBk
    Ok ($bkList.Cards.Count -ge 2) "Restore zeigt vorhandene Backups ($($bkList.Cards.Count): Standardordner + gemerkte)"
    Ok ($bkList.Cards[0].Sub -match 'Mailboxen' -and $bkList.Cards[0].Sub -match '\d{4}-\d\d-\d\d') 'Backup-Karte zeigt Inhalt und Datum'
    $enPath = Join-Path $base 'RussianFishing4EN'
    $bkIdx = [Array]::FindIndex($script:rsBackups, [Predicate[object]] { param($b) $b.Path -eq $bk })
    $bkList.Cards[$bkIdx].PerformClick(); Pump
    Ok ($script:rsCurrent -and $script:rsCurrent.Path -eq $bk -and $script:rsChecks[0].Checked -and -not $script:rsChecks[3].Enabled) 'Backup gewählt: Häkchen nur für Vorhandenes (Crafting aus)'
    $enIdx = [Array]::FindIndex($script:lstDst.Cards.ToArray(), [Predicate[object]] { param($c) $c.Tag2.Folder -eq 'RussianFishing4EN' })
    $script:lstDst.Cards[$enIdx].PerformClick(); Click-Primary
    Ok ((@(Get-Mailboxes $enPath).Count -eq 2) -and (Test-Path (Join-Path $enPath 'Settings.dat'))) 'Restore: Mailboxen + Settings in neuer EN-Installation'

    $script:state.Installs = @(Find-Installations); Show-Panel { Render-Merge }; Pump
    $deI = [Array]::FindIndex($script:mgEx, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4DE' })
    $stI = [Array]::FindIndex($script:mgEx, [Predicate[object]] { param($i) $i.Folder -eq 'RussianFishing4Steam' })
    $script:lstMgDst.Cards[$deI].PerformClick(); $script:lstMgSrc.Cards[$stI].PerformClick(); Click-Primary
    $ids = @((Read-JsonFile (Join-Path $base 'RussianFishing4DE\Mailbox_111\1.dat')).items | ForEach-Object { $_.meta.id })
    Ok ($ids.Count -eq 4) "Merge: DE-Konversation hat 4 Nachrichten ($($ids -join ','))"
    Ok ((Test-Path (Join-Path $base 'RussianFishing4DE\_rf4tool_undo')) -and (@($script:statCtls | Where-Object { $_.Caption -eq (T 'sum_msgs') })[0].Value -ne '0')) 'Merge: Undo-Ordner + Kennzahl Nachrichten > 0'
    Show-Panel { Render-Merge }; $dialogs.Clear()
    $script:lstMgDst.Cards[0].PerformClick(); $script:lstMgSrc.Cards[0].PerformClick(); Click-Primary
    Ok ($dialogs.Count -eq 1 -and $dialogs[0] -eq (T 'merge_same')) 'Merge: Quelle = Ziel wird abgefangen'

    $nas = Join-Path $tmp 'nas'; New-Item -ItemType Directory -Force -Path $nas | Out-Null
    Show-Panel { Render-Sync }; Pump
    $script:inSync.Text = $nas; $script:btnPrimary.PerformClick(); Pump
    Ok (@(Get-Mailboxes (Join-Path $nas 'RF4_Sync')).Count -ge 2) 'Sync: Mailboxen im Sync-Ordner'
    Ok ((Get-SyncPath) -eq $nas) 'Sync-Ordner gespeichert'
    Show-Panel { Render-Sync }; Pump; $script:btnExtra.PerformClick(); Pump
    Ok ($script:lstSySt.Cards.Count -ge 3) "Sync-Status listet Mailboxen/Log ($($script:lstSySt.Cards.Count) Zeilen)"
    $dialogs.Clear(); $script:inSync.Text = ''; $script:btnPrimary.PerformClick()
    Ok ($dialogs.Count -eq 1) 'Sync ohne Ordner: Hinweisdialog'

    Write-Host "`n[6] Fehlerfälle" -ForegroundColor Cyan
    Show-Panel { Render-Restore }; $dialogs.Clear(); $script:rsCurrent = $null; $script:btnPrimary.PerformClick()
    Ok ($dialogs.Count -eq 1 -and $dialogs[0] -eq (T 'select_backup_first')) 'Restore ohne gewähltes Backup: Hinweis'
    $script:state.Action = 'backup'; Show-Panel { Render-Backup }; for ($i = 0; $i -lt $script:bkChecks.Count; $i++) { $script:bkChecks[$i].Checked = $false }
    $dialogs.Clear(); $script:btnPrimary.PerformClick()
    Ok ($dialogs.Count -eq 1 -and $dialogs[0] -eq (T 'pick_item')) 'Backup ohne Auswahl: Hinweis'
    $form.ClientSize = New-Object System.Drawing.Size(((S 880) - 20), (S 560)); Show-Panel { Render-Backup }; Pump
    Ok ($script:pContent.AutoScrollMinSize.Height -gt 0) 'Kleines Fenster: Inhalt scrollbar statt abgeschnitten'
}
finally {
    try { $form.Close(); $form.Dispose() } catch { }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host ("Ergebnis: {0} bestanden, {1} fehlgeschlagen" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
