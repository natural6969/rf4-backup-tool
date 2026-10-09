# ══════════════════════════════════════════════════════════════════════════════
#  Terminal-Oberfläche (nutzt core.ps1)
# ══════════════════════════════════════════════════════════════════════════════
try {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::InputEncoding  = [Text.Encoding]::UTF8
    $OutputEncoding = [Text.Encoding]::UTF8
} catch { }

Initialize-Lang $Lang

# ── Darstellung: Unicode-Rahmen wenn möglich, sonst ASCII (RF4_ASCII=1 erzwingt ASCII) ──
$script:Uni = ($env:RF4_ASCII -ne '1')
$script:G = if ($script:Uni) { @{ tl = '╔'; tr = '╗'; bl = '╚'; br = '╝'; h = '═'; v = '║'; line = '─'; ok = '✔'; warn = '!'; err = '✘'; info = '›'; dot = '·'; bar = '━'; on = '■'; off = '□' } }
            else { @{ tl = '+'; tr = '+'; bl = '+'; br = '+'; h = '='; v = '|'; line = '-'; ok = 'OK'; warn = '!'; err = 'X'; info = '>'; dot = '-'; bar = '='; on = '[X]'; off = '[ ]' } }
$script:Width = 64

# Anzeigebreite (CJK/Fullwidth = 2 Spalten) – für saubere Rahmen auch in 中文
function Get-DispWidth([string]$s) {
    $w = 0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE6F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $w += 2 } else { $w += 1 }
    }
    return $w
}
function Pad-Disp([string]$s, [int]$width) { $d = Get-DispWidth $s; if ($d -ge $width) { return $s }; return $s + (' ' * ($width - $d)) }

function Write-Ok($m)   { Write-Host "  $($script:G.ok) " -ForegroundColor Green -NoNewline; Write-Host $m }
function Write-Info($m) { Write-Host "  $($script:G.info) " -ForegroundColor Cyan -NoNewline; Write-Host $m }
function Write-Warn($m) { Write-Host "  $($script:G.warn) " -ForegroundColor Yellow -NoNewline; Write-Host $m -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "  $($script:G.err) " -ForegroundColor Red -NoNewline; Write-Host $m -ForegroundColor Red }
function Write-Sep      { Write-Host ('  ' + ($script:G.line * ($script:Width - 4))) -ForegroundColor DarkCyan }
function Write-Hdr($t)  {
    Write-Host ''
    $inner = ' ' + $t + ' '
    $fill = [Math]::Max(2, $script:Width - 6 - (Get-DispWidth $inner))
    Write-Host ('  ' + ($script:G.bar * 2)) -ForegroundColor Cyan -NoNewline; Write-Host $inner -ForegroundColor Cyan -NoNewline; Write-Host ($script:G.bar * $fill) -ForegroundColor Cyan
}
function Write-Box([string[]]$lines, [string]$color = 'Cyan') {
    $inner = $script:Width - 4
    Write-Host ('  ' + $script:G.tl + ($script:G.h * $inner) + $script:G.tr) -ForegroundColor $color
    foreach ($l in $lines) { Write-Host ('  ' + $script:G.v) -ForegroundColor $color -NoNewline; Write-Host (' ' + (Pad-Disp $l ($inner - 1))) -NoNewline; Write-Host $script:G.v -ForegroundColor $color }
    Write-Host ('  ' + $script:G.bl + ($script:G.h * $inner) + $script:G.br) -ForegroundColor $color
}
# Kennzahlen nach einer Operation
function Write-Summary {
    $st = Get-Stats
    $items = @(@((T 'sum_msgs'), $st.MsgAdded, 'Cyan'), @((T 'sum_convs'), ($st.ConvNew + $st.ConvMerged), 'Green'), @((T 'sum_files'), ($st.FilesNew + $st.FilesReplaced), 'Green'))
    if ($st.Shots -gt 0) { $items += , @((T 'sum_shots'), $st.Shots, 'Green') }
    if ($st.FilesSkipped -gt 0) { $items += , @((T 'sum_skipped'), $st.FilesSkipped, 'Yellow') }
    if ($st.Failed -gt 0) { $items += , @((T 'sum_failed'), $st.Failed, 'Red') }
    Write-Host ''
    Write-Host '  ' -NoNewline
    foreach ($i in $items) { Write-Host ("$($script:G.on) ") -NoNewline -ForegroundColor $i[2]; Write-Host ("$($i[1]) ") -NoNewline -ForegroundColor $i[2]; Write-Host ("$($i[0])   ") -NoNewline }
    Write-Host ''
    if ($st.Failed -gt 0) { Write-Err (T 'res_err' @($st.Failed)) } else { Write-Ok (T 'res_ok') }
}
$script:LogSink = {
    param($lvl, $msg)
    switch ($lvl) {
        'ok'   { Write-Ok $msg }
        'warn' { Write-Warn $msg }
        'err'  { Write-Err $msg }
        default { Write-Info $msg }
    }
}

function Pause-Menu { Write-Host ''; [void](Read-Host "  $(T 'continue')") }

function Ask-Overwrite($name) {
    $a = Read-Host ('  ' + (T 'yn_overwrite' @($name)))
    return ($a.Trim().ToLowerInvariant() -in @('j', 'y', 'д', 'yes', 'ja', 'да'))
}

function Show-Menu([string]$Title, [string[]]$Options) {
    Write-Host ''; Write-Host "  $Title" -ForegroundColor Cyan; Write-Sep
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "  [$($i + 1)]" -ForegroundColor Yellow -NoNewline; Write-Host " $($Options[$i])" }
    Write-Host "  [0]" -ForegroundColor Yellow -NoNewline; Write-Host " $(T 'back')"
    Write-Host ''
    while ($true) {
        $raw = Read-Host "  $(T 'choose')"
        if ($null -eq $raw) { return 0 }
        $raw = $raw.Trim()
        if ($raw -eq '0') { return 0 }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $Options.Count) { return [int]$raw }
        Write-Warn (T 'invalid')
    }
}

# Rückgabe: Array der gewählten Indizes (0-basiert), leeres Array = nichts, $null = zurück
function Show-MultiSelect([string]$Title, [string[]]$Options) {
    $chosen = New-Object bool[] $Options.Count
    while ($true) {
        Write-Host ''; Write-Host "  $Title" -ForegroundColor Cyan
        Write-Host "  $(T 'toggle_hint')" -ForegroundColor DarkYellow; Write-Sep
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $mark = if ($chosen[$i]) { $script:G.on } else { $script:G.off }
            if ($chosen[$i]) { Write-Host "  $mark $($i + 1))" -ForegroundColor Green -NoNewline; Write-Host " $($Options[$i])" -ForegroundColor Green }
            else { Write-Host "  $mark $($i + 1))" -ForegroundColor DarkYellow -NoNewline; Write-Host " $($Options[$i])" }
        }
        Write-Host ''
        $raw = Read-Host "  $(T 'choose')"
        if ($null -eq $raw) { return $null }
        $raw = $raw.Trim().ToLowerInvariant()
        if ($raw -eq '') { $sel = @(); for ($i = 0; $i -lt $Options.Count; $i++) { if ($chosen[$i]) { $sel += $i } }; return , $sel }
        if ($raw -eq '0') { return $null }
        if ($raw -eq 'a') { for ($i = 0; $i -lt $chosen.Count; $i++) { $chosen[$i] = $true }; continue }
        if ($raw -eq 'n') { for ($i = 0; $i -lt $chosen.Count; $i++) { $chosen[$i] = $false }; continue }
        foreach ($tok in ($raw -split '[,\s]+' | Where-Object { $_ })) {
            if ($tok -match '^\d+$') { $ix = [int]$tok - 1; if ($ix -ge 0 -and $ix -lt $chosen.Count) { $chosen[$ix] = -not $chosen[$ix] } }
        }
    }
}

function Confirm-GameClosed {
    $run = Test-Rf4Running
    if (-not $run) { return $true }
    Write-Warn (T 'running_warn' @($run))
    $a = Read-Host ('  ' + (T 'running_ask') + ' [' + (T 'yes_char') + '/N]')
    return ($a.Trim().ToLowerInvariant() -in @('j', 'y', 'д'))
}

# Account-Auswahl → Liste der Ordnernamen oder $null (= alle)  /  'BACK' bei Rückwärts
function Select-Accounts($boxes, [string]$titleKey) {
    $boxes = @($boxes)
    if ($boxes.Count -le 1) { return $null }
    $opts = @(T 'all_accts' @($boxes.Count)) + @($boxes | ForEach-Object { T 'acct_line' @($_.Id, $_.Convs) })
    $c = Show-Menu (T $titleKey) $opts
    if ($c -eq 0) { return 'BACK' }
    if ($c -eq 1) { return $null }
    return @($boxes[$c - 2].Name)
}

function Item-Label([string]$k) { T ('item_' + $k) }

# ── SCAN ───────────────────────────────────────────────────────────────────────
function Do-Scan {
    Write-Hdr (T 'hdr_scan'); Write-Info (T 'scanning')
    $ins = @(Find-Installations)
    if ($ins.Count -eq 0) { Write-Warn (T 'none_found'); Pause-Menu; return }
    foreach ($i in $ins) {
        if ($i.Exists) {
            $info = Get-InstInfo $i.Path
            Write-Ok (Get-InstLabel $i)
            Write-Info ('  ' + (T 'scan_path' @($i.Path)))
            Write-Info ('  ' + (T 'scan_stats' @($info.Mailboxes.Count, $info.Convs)))
            if ($info.Ids) { Write-Info ('  ' + (T 'scan_accounts' @($info.Ids))) }
        } else {
            Write-Host ('  [--] ' + (Get-InstLabel $i) + '  ' + (T 'scan_empty')) -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    Write-Host ('  ' + (T 'scan_total' @($ins.Count))) -ForegroundColor DarkGray
    Pause-Menu
}

# ── BACKUP ─────────────────────────────────────────────────────────────────────
function Do-Backup {
    Write-Hdr (T 'hdr_backup')
    $ex = @(Find-Installations | Where-Object { $_.Exists })
    if ($ex.Count -eq 0) { Write-Err (T 'no_inst'); Pause-Menu; return }
    $c = Show-Menu (T 'pick_source') @($ex | ForEach-Object { Get-InstLabel $_ })
    if ($c -eq 0) { return }
    $src = $ex[$c - 1]

    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $sel = Show-MultiSelect (T 'what_backup') @($keys | ForEach-Object { Item-Label $_ })
    if ($null -eq $sel -or @($sel).Count -eq 0) { Write-Warn (T 'nothing_sel'); Pause-Menu; return }
    $items = @($sel | ForEach-Object { $keys[$_] })

    $accounts = $null
    if ($items -contains 'mail') {
        $accounts = Select-Accounts (Get-Mailboxes $src.Path) 'which_acct_b'
        if ($accounts -is [string] -and $accounts -eq 'BACK') { return }
    }

    $def = Get-DefaultBackupDir
    $dest = Read-Host ('  ' + (T 'backup_dir_p' @($def)))
    if ([string]::IsNullOrWhiteSpace($dest)) { $dest = $def }
    Write-Info (T 'from' @($src.Path)); Write-Info (T 'to' @($dest)); Write-Sep
    try {
        Reset-Stats
        Copy-Rf4Data -SrcDir $src.Path -DstDir $dest -Items $items -Accounts $accounts `
            -ShotsSrc (Get-ScreenshotDir $src.Path) -ShotsDst (Join-Path $dest 'Screenshots') -Confirm { param($n) Ask-Overwrite $n }
        Add-BackupDir $dest
        Write-Host ''; Write-Ok (T 'backup_done' @($dest)); Write-Summary
    } catch { Write-Err $_.Exception.Message }
    Pause-Menu
}

# ── RESTORE ────────────────────────────────────────────────────────────────────
function Do-Restore {
    Write-Hdr (T 'hdr_restore')
    $def = Get-DefaultBackupDir
    $bks = @(Find-Backups)
    $src = $null
    if ($bks.Count -gt 0) {
        $opts = @($bks | ForEach-Object { "$($_.Name)   $($script:G.dot)   $($_.Time.ToString('yyyy-MM-dd HH:mm'))`n        $($_.Path)`n        $(Format-BackupInfo $_)" }) + @(T 'manual_path')
        $c = Show-Menu (T 'pick_backup_list') $opts
        if ($c -eq 0) { return }
        if ($c -le $bks.Count) { $src = $bks[$c - 1].Path }
    } else { Write-Warn (T 'no_backup_found_cli') }
    if (-not $src) {
        $src = Read-Host ('  ' + (T 'backup_dir_p' @($def)))
        if ([string]::IsNullOrWhiteSpace($src)) { $src = $def }
    }
    if (-not (Test-Path -LiteralPath $src)) { Write-Err (T 'folder_missing' @($src)); Pause-Menu; return }
    $bc = Get-BackupContents $src
    if ($bc.Empty) { Write-Warn (T 'no_backup_here'); Pause-Menu; return }
    Write-Info (T 'contents')
    foreach ($m in $bc.Mailboxes) { Write-Info ('  ' + (T 'bk_mailbox' @($m.Name, $m.Convs))) }
    foreach ($f in $bc.Files) { Write-Info "  $f" }
    if ($bc.Shots -gt 0) { Write-Info ('  ' + (T 'bk_shots' @($bc.Shots))) }

    $ins = @(Find-Installations)
    $opts = @($ins | ForEach-Object { (Get-InstLabel $_) + $(if (-not $_.Exists) { '  ' + (T 'scan_empty') } else { '' }) }) + @(T 'manual_path')
    $c = Show-Menu (T 'pick_target') $opts
    if ($c -eq 0) { return }
    $dstPath = if ($c -le $ins.Count) { $ins[$c - 1].Path } else { Read-Host ('  ' + (T 'enter_path')) }
    if ([string]::IsNullOrWhiteSpace($dstPath)) { Write-Err (T 'no_path'); Pause-Menu; return }

    $avail = @(); $labels = @()
    if ($bc.Mailboxes.Count -gt 0) { $avail += 'mail'; $labels += (Item-Label 'mail') + " ($($bc.Mailboxes.Count))" }
    foreach ($f in $bc.Files) { $avail += $f; $labels += (Item-Label $f) }
    if ($bc.Shots -gt 0) { $avail += 'shots'; $labels += (Item-Label 'shots') + " ($($bc.Shots))" }
    $sel = Show-MultiSelect (T 'what_restore') $labels
    if ($null -eq $sel -or @($sel).Count -eq 0) { Write-Warn (T 'nothing_sel'); Pause-Menu; return }
    $items = @($sel | ForEach-Object { $avail[$_] })
    $accounts = $null
    if ($items -contains 'mail') {
        $accounts = Select-Accounts $bc.Mailboxes 'which_acct_r'
        if ($accounts -is [string] -and $accounts -eq 'BACK') { return }
    }
    if (-not (Confirm-GameClosed)) { Write-Warn (T 'cancelled'); Pause-Menu; return }

    Write-Info (T 'importing_to' @($dstPath)); Write-Sep
    try {
        Reset-Stats
        Copy-Rf4Data -SrcDir $src -DstDir $dstPath -Items $items -Accounts $accounts `
            -ShotsSrc (Join-Path $src 'Screenshots') -ShotsDst (Get-ScreenshotDir $dstPath -Create) `
            -Confirm { param($n) Ask-Overwrite $n } -UndoRoot (New-UndoRoot $dstPath)
        Add-BackupDir (Split-Path $src -Parent)
        Write-Ok (T 'restore_done'); Write-Summary
    } catch { Write-Err $_.Exception.Message }
    Pause-Menu
}

# ── MERGE ──────────────────────────────────────────────────────────────────────
function Do-Merge {
    Write-Hdr (T 'hdr_merge')
    $ex = @(Find-Installations | Where-Object { $_.Exists })
    if ($ex.Count -lt 2) { Write-Warn (T 'merge_need2'); Pause-Menu; return }
    Write-Host ''; Write-Warn (T 'merge_note'); Write-Info (T 'merge_safe')
    $c = Show-Menu (T 'merge_dst') @($ex | ForEach-Object { Get-InstLabel $_ })
    if ($c -eq 0) { return }
    $dst = $ex[$c - 1]
    $srcs = @($ex | Where-Object { $_.Path -ne $dst.Path })
    if ($srcs.Count -eq 0) { Write-Err (T 'merge_nosrc'); Pause-Menu; return }
    $sel = Show-MultiSelect (T 'merge_src') @($srcs | ForEach-Object { Get-InstLabel $_ })
    if ($null -eq $sel -or @($sel).Count -eq 0) { Write-Warn (T 'pick_one_src'); Pause-Menu; return }
    if (-not (Confirm-GameClosed)) { Write-Warn (T 'cancelled'); Pause-Menu; return }
    $undo = New-UndoRoot $dst.Path; Reset-Stats
    Write-Info (T 'to' @($dst.Path)); Write-Sep
    foreach ($ix in $sel) {
        $s = $srcs[$ix]
        Write-Info (T 'merge_src_hdr' @((Get-InstLabel $s)))
        $acc = Select-Accounts (Get-Mailboxes $s.Path) 'which_acct_m'
        if ($acc -is [string] -and $acc -eq 'BACK') { continue }
        try { Copy-Rf4Data -SrcDir $s.Path -DstDir $dst.Path -Items @('mail') -Accounts $acc -UndoRoot $undo } catch { Write-Err $_.Exception.Message }
    }
    Write-Ok (T 'merge_done'); Write-Summary
    Pause-Menu
}

# ── SYNC ───────────────────────────────────────────────────────────────────────
function Do-Sync {
    Write-Hdr (T 'hdr_sync'); Write-Host ('  ' + (T 'sync_intro')) -ForegroundColor DarkGray
    while ($true) {
        $sp = Get-SyncPath; Write-Host ''
        if ([string]::IsNullOrWhiteSpace($sp)) { Write-Host ('  ' + (T 'sync_none')) -ForegroundColor Yellow }
        elseif (Test-Path -LiteralPath $sp) { Write-Ok (T 'sync_ok' @($sp)) }
        else { Write-Warn (T 'sync_unreach' @($sp)); Write-Host ('  ' + (T 'sync_unreach_h')) -ForegroundColor DarkGray }
        Write-Host ''
        Write-Host "  [1] $(T 'sync_run')"    -ForegroundColor Yellow
        Write-Host "  [2] $(T 'sync_cfg')"    -ForegroundColor Yellow
        Write-Host "  [3] $(T 'sync_status')" -ForegroundColor Yellow
        Write-Host "  [0] $(T 'back')"        -ForegroundColor Yellow
        Write-Host ''
        $raw = Read-Host "  $(T 'choose')"
        if ($null -eq $raw) { return }
        switch ($raw.Trim()) {
            '0' { return }
            '2' {
                Write-Host ''; Write-Host ('  ' + (T 'sync_enter')) -ForegroundColor White
                $np = Read-Host '  >'
                if (-not [string]::IsNullOrWhiteSpace($np)) {
                    try { New-Item -ItemType Directory -Force -Path $np | Out-Null; Set-SyncPath $np; Write-Ok (T 'sync_saved' @($np)) }
                    catch { Write-Err (T 'sync_mkfail' @($_.Exception.Message)) }
                }
                Pause-Menu
            }
            '3' {
                if ([string]::IsNullOrWhiteSpace($sp)) { Write-Warn (T 'sync_none'); Pause-Menu; continue }
                if (-not (Test-Path -LiteralPath $sp)) { Write-Err (T 'sync_unreach' @($sp)); Pause-Menu; continue }
                $st = Get-SyncStatus $sp
                Write-Info (T 'sync_ok' @($sp))
                if (-not $st.Exists) { Write-Warn (T 'sync_st_nodir') }
                else {
                    if ($st.Mailboxes.Count -eq 0) { Write-Warn (T 'sync_st_none') }
                    foreach ($m in $st.Mailboxes) { Write-Info ('  ' + (T 'sync_st_boxes' @($m.Name, $m.Convs))) }
                    foreach ($f in $st.Files) { Write-Info "  $($f.Name): $($f.Time)" }
                    if ($st.Log.Count -gt 0) { Write-Host ''; Write-Info (T 'sync_st_log'); foreach ($l in $st.Log) { Write-Info "  $l" } }
                }
                Pause-Menu
            }
            '1' {
                if ([string]::IsNullOrWhiteSpace($sp)) { Write-Warn (T 'sync_first'); Pause-Menu; continue }
                if (-not (Test-Path -LiteralPath $sp)) { Write-Err (T 'sync_unreach' @($sp)); Write-Info (T 'sync_unreach_h'); Pause-Menu; continue }
                $ex = @(Find-Installations | Where-Object { $_.Exists })
                if ($ex.Count -eq 0) { Write-Err (T 'no_inst'); Pause-Menu; continue }
                if ($ex.Count -eq 1) { $inst = $ex[0]; Write-Info (Get-InstLabel $inst) }
                else {
                    $c = Show-Menu (T 'sync_which') @($ex | ForEach-Object { Get-InstLabel $_ })
                    if ($c -eq 0) { continue }
                    $inst = $ex[$c - 1]
                }
                if (-not (Confirm-GameClosed)) { Write-Warn (T 'cancelled'); Pause-Menu; continue }
                try { Reset-Stats; Invoke-SyncRun -InstPath $inst.Path -SyncBase $sp; Write-Summary } catch { Write-Err $_.Exception.Message }
                Pause-Menu
            }
            default { Write-Warn (T 'invalid') }
        }
    }
}

# ── Sprache wählen ─────────────────────────────────────────────────────────────
function Do-Language {
    $names = @($script:Langs | ForEach-Object { $script:LangNames[$_] })
    $c = Show-Menu (T 'lang_prompt') $names
    if ($c -eq 0) { return }
    [void](Set-Lang $script:Langs[$c - 1])
    try { Save-Lang $script:Lang } catch { }
    Write-Ok (T 'lang_changed')
}

# ── Hauptmenü ──────────────────────────────────────────────────────────────────
function Show-Main {
    while ($true) {
        try { Clear-Host } catch { }
        Write-Box @(
            ((T 'app_title') + '   v' + $script:ToolVersion),
            ('RF4: nga.li/rf4de  ' + $script:G.dot + '  Blog: nga.li/rf4b'),
            (T 'donate')
        ) 'Cyan'
        Write-Host ''
        $mi = @(@('1', 'menu_scan'), @('2', 'menu_backup'), @('3', 'menu_restore'), @('4', 'menu_merge'), @('5', 'menu_sync'))
        foreach ($m in $mi) { Write-Host "   [$($m[0])]" -ForegroundColor Yellow -NoNewline; Write-Host " $(T $m[1])" }
        Write-Host '   [L]' -ForegroundColor Yellow -NoNewline; Write-Host " $(T 'menu_lang')  " -NoNewline; Write-Host "($($script:LangNames[$script:Lang]))" -ForegroundColor Cyan
        Write-Host '   [0]' -ForegroundColor Yellow -NoNewline; Write-Host " $(T 'exit')"
        Write-Host ''
        $raw = Read-Host "  $(T 'choose')"
        if ($null -eq $raw) { return }
        try {
            switch ($raw.Trim().ToLowerInvariant()) {
                '1' { Do-Scan } '2' { Do-Backup } '3' { Do-Restore } '4' { Do-Merge } '5' { Do-Sync }
                'l' { Do-Language }
                '0' { return }
            }
        } catch { Write-Err $_.Exception.Message; Pause-Menu }
    }
}

if ($env:RF4_NO_MAIN -ne '1') { Show-Main }
