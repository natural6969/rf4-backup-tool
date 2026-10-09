# ══════════════════════════════════════════════════════════════════════════════
#  RF4 Backup Tool – gemeinsamer Kern (Logik, Sprachen, Themes), keine UI
#  Wird von build.ps1 in rf4sa-backup.ps1 (CLI) und rf4sa-backup-gui.ps1 (GUI) eingebettet.
#  Sprachen:  src\lang\*.lang     (key=Text)          – weitere Sprachen: einfach Datei ablegen
#  Themes:    src\themes\*.theme  (key=#RRGGBB)       – weitere Themes: einfach Datei ablegen
# ══════════════════════════════════════════════════════════════════════════════
$script:ToolVersion = '1.5.0'
$script:ToolDate    = '2026-10-09'
$script:DatFiles    = @('Settings.dat', 'Preferences.dat', 'Crafting.dat')
$script:LogSink     = $null
$script:Stats       = $null

# ── Daten: Sprachen + Themes (eingebaut + externe Dateien) ─────────────────────
$script:TX       = @{}                # key -> @{ code = text }
$script:LangNames = [ordered]@{}      # code -> Anzeigename
$script:Langs    = @()                # Codes in Anzeige-Reihenfolge
$script:Themes   = [ordered]@{}       # code -> @{ name; base; colors = @{} }
$script:EmbeddedData = $null          # setzt build.ps1 (alle lang/themes-Dateien in einem Text)

# ── Sprachen + Themes laden ────────────────────────────────────────────────────
function ConvertFrom-KvText([string]$text) {
    $meta = @{}; $items = [ordered]@{}
    foreach ($raw in ($text -split "`n")) {
        $line = $raw.TrimEnd("`r")
        if ($line.Length -eq 0 -or $line[0] -eq '#') { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $line.Substring(0, $eq).Trim(); $v = $line.Substring($eq + 1)
        if ($k[0] -eq '@') { $meta[$k.Substring(1)] = $v.Trim() } else { $items[$k] = $v }
    }
    return @{ meta = $meta; items = $items }
}
function Add-LangData($p) {
    $code = ([string]$p.meta['code']).ToLowerInvariant()
    if (-not $code) { return }
    if (-not $script:LangNames.Contains($code)) { $script:LangNames[$code] = $(if ($p.meta['name']) { $p.meta['name'] } else { $code }); $script:Langs += $code }
    elseif ($p.meta['name']) { $script:LangNames[$code] = $p.meta['name'] }
    foreach ($k in $p.items.Keys) {
        if (-not $script:TX.ContainsKey($k)) { $script:TX[$k] = @{} }
        $script:TX[$k][$code] = $p.items[$k]
    }
}
function Add-ThemeData($p) {
    $code = ([string]$p.meta['code']).ToLowerInvariant()
    if (-not $code) { return }
    $colors = @{}; foreach ($k in $p.items.Keys) { if ($p.items[$k] -match '^#[0-9a-fA-F]{6}$') { $colors[$k] = $p.items[$k].Trim() } }
    $base = if ($p.meta['base'] -eq 'light') { 'light' } else { 'dark' }
    $script:Themes[$code] = @{ name = $(if ($p.meta['name']) { $p.meta['name'] } else { $code }); base = $base; colors = $colors }
}
function Import-DataDir([string]$dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $dir 'lang') -Filter '*.lang' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { Add-LangData (ConvertFrom-KvText ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF))) } catch { }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $dir 'themes') -Filter '*.theme' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { Add-ThemeData (ConvertFrom-KvText ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF))) } catch { }
    }
}
function Initialize-Data {
    $script:TX = @{}; $script:LangNames = [ordered]@{}; $script:Langs = @(); $script:Themes = [ordered]@{}
    if ($script:EmbeddedData) {                       # gebautes Skript: alles eingebaut
        $parts = [regex]::Split($script:EmbeddedData, '(?m)^@@FILE (.+?)\s*$')
        for ($i = 1; $i -lt $parts.Count; $i += 2) {
            $kv = ConvertFrom-KvText $parts[$i + 1]
            if ($parts[$i] -like '*.theme') { Add-ThemeData $kv } else { Add-LangData $kv }
        }
    } else {                                          # ungebaut (Tests/Entwicklung): src\lang + src\themes neben core.ps1
        Import-DataDir $PSScriptRoot
    }
    # Externe Erweiterungen: neben dem Skript und im Benutzerprofil
    if ($script:EmbeddedData -and $PSScriptRoot) { Import-DataDir $PSScriptRoot }
    if ($env:APPDATA) { Import-DataDir (Join-Path $env:APPDATA 'rf4-backup') }
    # Reihenfolge: de en zh ru zuerst, dann der Rest alphabetisch
    $first = @('de', 'en', 'zh', 'ru') | Where-Object { $script:Langs -contains $_ }
    $rest = @($script:Langs | Where-Object { $first -notcontains $_ } | Sort-Object)
    $script:Langs = @($first) + $rest
}
# @@LOADER@@
Initialize-Data

function Resolve-Lang([string]$code) {
    if ([string]::IsNullOrWhiteSpace($code)) { return $null }
    $c = $code.Trim().ToLowerInvariant().Replace('_', '-')
    if ($script:Langs -contains $c) { return $c }
    if ($c.Length -ge 2 -and ($script:Langs -contains $c.Substring(0, 2))) { return $c.Substring(0, 2) }
    return $null
}
function Set-Lang([string]$code) {
    $l = Resolve-Lang $code
    if (-not $l) { $l = 'en' }
    $script:Lang = $l
    return $l
}
function T([string]$key, [object[]]$a) {
    $row = $script:TX[$key]
    if (-not $row) { return $key }
    $s = $row[$script:Lang]
    if ([string]::IsNullOrEmpty($s)) { $s = $row['en'] }
    if ([string]::IsNullOrEmpty($s)) { return $key }
    if ($a -and $a.Count -gt 0) { return [string]::Format($s, $a) }
    return $s
}

# ── Themes ─────────────────────────────────────────────────────────────────────
function Get-SystemThemeBase {
    if ($env:RF4_THEME_BASE -in @('dark', 'light')) { return $env:RF4_THEME_BASE }
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ($v -eq 0) { return 'dark' } else { return 'light' }
    } catch { return 'dark' }
}
# choice: '' / 'auto' (= Windows-Einstellung) oder ein Theme-Code
function Resolve-ThemeCode([string]$choice) {
    $c = ([string]$choice).Trim().ToLowerInvariant()
    if ($c -and $c -ne 'auto' -and $script:Themes.Contains($c)) { return $c }
    $base = Get-SystemThemeBase
    if ($script:Themes.Contains($base)) { return $base }
    foreach ($k in $script:Themes.Keys) { if ($script:Themes[$k].base -eq $base) { return $k } }
    return @($script:Themes.Keys)[0]
}
function Get-ThemeColors([string]$code) {
    $t = $script:Themes[$code]
    $fallback = $script:Themes['dark']
    $out = @{}
    foreach ($k in @('bg', 'surface', 'surface2', 'border', 'text', 'muted', 'accent', 'accentHover', 'accentText', 'success', 'warn', 'danger', 'selection')) {
        $v = $null
        if ($t -and $t.colors.ContainsKey($k)) { $v = $t.colors[$k] } elseif ($fallback -and $fallback.colors.ContainsKey($k)) { $v = $fallback.colors[$k] } else { $v = '#808080' }
        $out[$k] = $v
    }
    return $out
}

# ── Hilfe: Anleitung in der Sprache des Programms öffnen ──────────────────────
function Get-GuideCode { if (@('de', 'en', 'zh', 'ru') -contains $script:Lang) { return $script:Lang } else { return 'en' } }
function Get-GuidePath {
    $code = Get-GuideCode
    foreach ($dir in @($PSScriptRoot, $(if ($PSScriptRoot) { Join-Path $PSScriptRoot '..' }))) {
        if (-not $dir) { continue }
        $p = Join-Path $dir "docs\guide.$code.html"
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}
function Get-GuideUrl {
    $code = Get-GuideCode; $suffix = $(if ($code -eq 'de') { '' } else { ".$code" })
    return "https://codeberg.org/Natural78/rf4-backup-tool/src/branch/main/README$suffix.md"
}
function Open-Guide { $p = Get-GuidePath; try { if ($p) { Start-Process -FilePath $p } else { Start-Process (Get-GuideUrl) } } catch { } }
# ── Konfiguration (Sprache, Theme, Sync-Ordner, Backup-Ordner) ─────────────────
function Get-ConfigDir  { Join-Path $env:APPDATA 'rf4-backup' }
function Get-ConfigFile { Join-Path (Get-ConfigDir) 'settings.json' }
function Get-Config {
    $cfg = @{ lang = ''; theme = ''; syncPath = ''; backupDirs = @() }
    $f = Get-ConfigFile
    if (Test-Path -LiteralPath $f) {
        try {
            $j = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            foreach ($k in @('lang', 'theme', 'syncPath')) {
                $p = $j.PSObject.Properties[$k]
                if ($p -and $p.Value) { $cfg[$k] = [string]$p.Value }
            }
            $bp = $j.PSObject.Properties['backupDirs']
            if ($bp -and $null -ne $bp.Value) { $cfg.backupDirs = @($bp.Value | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
        } catch { }
    }
    # Altformat (v1.2/1.3): sync.conf
    if (-not $cfg.syncPath) {
        $old = Join-Path (Get-ConfigDir) 'sync.conf'
        if (Test-Path -LiteralPath $old) { try { $cfg.syncPath = ([IO.File]::ReadAllText($old)).Trim().TrimStart([char]0xFEFF) } catch { } }
    }
    return $cfg
}
function Save-Config([hashtable]$cfg) {
    New-Item -ItemType Directory -Force -Path (Get-ConfigDir) | Out-Null
    $o = [pscustomobject]@{ lang = [string]$cfg.lang; theme = [string]$cfg.theme; syncPath = [string]$cfg.syncPath; backupDirs = @($cfg.backupDirs) }
    [IO.File]::WriteAllText((Get-ConfigFile), ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))
}
function Get-SyncPath { [string](Get-Config).syncPath }
function Set-SyncPath([string]$p) { $c = Get-Config; $c.syncPath = $p; Save-Config $c }
function Save-Lang([string]$l)    { $c = Get-Config; $c.lang = $l;     Save-Config $c }
function Save-ThemeChoice([string]$t) { $c = Get-Config; $c.theme = $t; Save-Config $c }
function Add-BackupDir([string]$dir) {
    if ([string]::IsNullOrWhiteSpace($dir)) { return }
    $c = Get-Config
    $full = try { [IO.Path]::GetFullPath($dir) } catch { $dir }
    $list = @($full) + @($c.backupDirs | Where-Object { $_ -ne $full })
    $c.backupDirs = @($list | Select-Object -First 8)
    Save-Config $c
}

function Initialize-Lang([string]$Override) {
    $l = Resolve-Lang $Override
    if (-not $l) { $l = Resolve-Lang $env:RF4_LANG }
    if (-not $l) { $l = Resolve-Lang (Get-Config).lang }
    if (-not $l) { $l = Resolve-Lang (Get-Culture).Name }
    if (-not $l) { $l = Resolve-Lang (Get-Culture).TwoLetterISOLanguageName }
    if (-not $l) { $l = 'en' }
    [void](Set-Lang $l)
}

# ── Logging an die UI ──────────────────────────────────────────────────────────
# ── Statistik der letzten Operation (für Ergebnis-Anzeige) ─────────────────────
function Reset-Stats { $script:Stats = @{ MsgAdded = 0; ConvNew = 0; ConvMerged = 0; FilesNew = 0; FilesReplaced = 0; FilesSkipped = 0; Shots = 0; Failed = 0 } }
function Add-Stat([string]$k, [int]$n = 1) { if (-not $script:Stats) { Reset-Stats }; $script:Stats[$k] += $n }
function Get-Stats { if (-not $script:Stats) { Reset-Stats }; return $script:Stats.Clone() }
Reset-Stats

function Write-Log([string]$level, [string]$key, [object[]]$a) {
    $msg = T $key $a
    if ($script:LogSink) { & $script:LogSink $level $msg }
}

# ── Hilfsfunktionen ────────────────────────────────────────────────────────────
function Count-Of($x) { if ($null -eq $x) { 0 } else { @($x).Count } }
function Get-Dats([string]$dir) {
    @(Get-ChildItem -LiteralPath $dir -Filter '*.dat' -File -ErrorAction SilentlyContinue)
}
function Test-Rf4Running {
    if ($env:RF4_FAKE_RUNNING) { return $env:RF4_FAKE_RUNNING }   # Test-Hook
    $p = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^rf4_x(32|64)$' })
    if ($p.Count -eq 0) { return $null }
    return (($p | Select-Object -ExpandProperty Name -Unique) -join ', ')
}
function Read-JsonFile([string]$path) {
    $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    return ($t | ConvertFrom-Json)
}
function Write-JsonFile($obj, [string]$path) {
    $json = $obj | ConvertTo-Json -Depth 100
    $tmp = "$path.rf4tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($true)))
    # Gegenprobe: muss wieder lesbar sein, sonst Original behalten
    [void](Read-JsonFile $tmp)
    Move-Item -LiteralPath $tmp -Destination $path -Force
}
function Get-MsgId($item) {
    if ($null -eq $item) { return $null }
    $m = $item.PSObject.Properties['meta']
    if ($m -and $m.Value) { $i = $m.Value.PSObject.Properties['id']; if ($i) { return [string]$i.Value } }
    return $null
}
function Get-MsgCreated($item) {
    try { $m = $item.PSObject.Properties['meta'].Value; return [long]$m.PSObject.Properties['created'].Value } catch { return [long]0 }
}
function Save-Undo([string]$file, [string]$undoRoot) {
    if (-not $undoRoot -or -not (Test-Path -LiteralPath $file)) { return }
    $rel = Split-Path $file -Leaf
    $parent = Split-Path (Split-Path $file -Parent) -Leaf
    $target = Join-Path $undoRoot (Join-Path $parent $rel)
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $file -Destination $target -Force
}
function New-UndoRoot([string]$instPath) {
    Join-Path $instPath ('_rf4tool_undo\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

# ── Installationen finden ──────────────────────────────────────────────────────
$script:RF4_BASE    = 'AppData\Roaming\RussianFishingLLC'
$script:SHOT_SUB    = 'Documents\Russian Fishing 4\Screenshots'
$script:KnownVariants = [ordered]@{
    'RussianFishing4DE'     = 'DE'
    'RussianFishing4DE_new' = 'DE_new'
    'RussianFishing4EN'     = 'EN'
    'RussianFishing4Steam'  = 'Steam'
}
# %APPDATA% = <User>\AppData\Roaming -> zwei Ebenen hoch = Benutzerordner.
# (v1.3 ging nur eine Ebene hoch und fand dadurch die eigene Installation nie.)
function Get-UserRoot { Split-Path (Split-Path $env:APPDATA.TrimEnd('\') -Parent) -Parent }
function Get-DefaultBackupDir { Join-Path $env:USERPROFILE 'RF4_Backup' }

function Find-Installations {
    $list = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $skip = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')

    function Add-User($userDir, $whereType, $whereArg1, $whereArg2, $isCurrent) {
        $baseDir = Join-Path $userDir $script:RF4_BASE
        $folders = New-Object System.Collections.Generic.List[string]
        if ($isCurrent) { foreach ($k in $script:KnownVariants.Keys) { $folders.Add($k) } }
        if (Test-Path -LiteralPath $baseDir) {
            foreach ($d in (Get-ChildItem -LiteralPath $baseDir -Directory -ErrorAction SilentlyContinue)) {
                if (-not $folders.Contains($d.Name)) { $folders.Add($d.Name) }
            }
        }
        foreach ($f in $folders) {
            $p = Join-Path $baseDir $f
            $norm = $p.TrimEnd('\').ToLowerInvariant()
            if (-not $seen.Add($norm)) { continue }
            $exists = Test-Path -LiteralPath $p
            if (-not $exists -and -not $isCurrent) { continue }
            $v = if ($script:KnownVariants.Contains($f)) { $script:KnownVariants[$f] } else { 'Other' }
            $list.Add([pscustomobject]@{
                Variant = $v; Folder = $f; Path = $p; Exists = $exists
                WhereType = $whereType; Where1 = $whereArg1; Where2 = $whereArg2
                Steam = ($v -eq 'Steam' -or $f -match 'Steam')
            })
        }
    }

    # 1) aktueller Benutzer
    $userRoot = Get-UserRoot
    $drive = if ($env:APPDATA.Length -ge 2) { $env:APPDATA.Substring(0, 2) } else { '' }
    Add-User $userRoot 'local' $drive $env:USERNAME $true

    # 2) andere Benutzer dieses Systems
    $usersRoot = Split-Path $userRoot -Parent
    if ($usersRoot -and (Test-Path -LiteralPath $usersRoot)) {
        foreach ($u in (Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($skip -contains $u.Name -or $u.FullName -eq $userRoot) { continue }
            Add-User $u.FullName 'user' $u.Name '' $false
        }
    }

    # 3) Zusätzliche Pfade (Env RF4_SCAN_USERS, ';'-getrennt, "Users"-ähnliche Ordner)
    foreach ($x in @(([string]$env:RF4_SCAN_USERS) -split ';' | Where-Object { $_ })) {
        if (-not (Test-Path -LiteralPath $x)) { continue }
        foreach ($u in (Get-ChildItem -LiteralPath $x -Directory -ErrorAction SilentlyContinue)) {
            if ($skip -contains $u.Name) { continue }
            Add-User $u.FullName 'extra' $u.Name '' $false
        }
    }

    # 4) alle Laufwerke (externe Platten, USB, alte Installs)
    if ($env:RF4_NO_DRIVE_SCAN -ne '1') {
        $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -in @('Fixed', 'Removable', 'Network') -and $_.IsReady })
        foreach ($drv in $drives) {
            $label = if ($drv.VolumeLabel) { $drv.VolumeLabel } else { $drv.Name.TrimEnd('\') }
            $uRoot = Join-Path $drv.RootDirectory.FullName 'Users'
            if (-not (Test-Path -LiteralPath $uRoot)) { continue }
            foreach ($u in (Get-ChildItem -LiteralPath $uRoot -Directory -ErrorAction SilentlyContinue)) {
                if ($skip -contains $u.Name) { continue }
                Add-User $u.FullName 'drive' $label $u.Name $false
            }
        }
    }
    return $list.ToArray()
}

function Get-InstLabel($inst) {
    $name = if ($inst.Variant -eq 'Other') { T 'v_Other' @($inst.Folder) } else { T ('v_' + $inst.Variant) }
    $where = switch ($inst.WhereType) {
        'local' { "$($inst.Where1) / $($inst.Where2)" }
        'user'  { T 'w_user' @($inst.Where1) }
        'drive' { T 'w_drive' @($inst.Where1, $inst.Where2) }
        'win'    { T 'w_win' @($inst.Where1, $inst.Where2) }
        'wine'   { T 'w_wine' @($inst.Where2) }
        'proton' { T 'w_proton' @($inst.Where1) }
        default { T 'w_extra' @($inst.Where1) }
    }
    return "$name [$where]"
}

# Immer mit @() aufrufen: Get-Mailboxes liefert 0, 1 oder n Objekte.
function Get-Mailboxes([string]$path) {
    $out = @()
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    foreach ($d in (Get-ChildItem -LiteralPath $path -Directory -Filter 'Mailbox_*' -ErrorAction SilentlyContinue)) {
        $out += [pscustomobject]@{
            Name  = $d.Name
            Id    = ($d.Name -replace '^Mailbox_', '')
            Path  = $d.FullName
            Convs = (Count-Of (Get-Dats $d.FullName))
        }
    }
    return $out
}

function Get-InstInfo([string]$path) {
    $mb = @(Get-Mailboxes $path)
    $convs = 0; foreach ($m in $mb) { $convs += $m.Convs }
    $files = @($script:DatFiles | Where-Object { Test-Path -LiteralPath (Join-Path $path $_) })
    [pscustomobject]@{ Mailboxes = $mb; Convs = $convs; Files = $files; Ids = (($mb | ForEach-Object { $_.Id }) -join ', ') }
}

function Get-ScreenshotDir([string]$instPath, [switch]$Create) {
    $userDir = $instPath.TrimEnd('\')
    for ($i = 0; $i -lt 4; $i++) { $userDir = Split-Path $userDir -Parent }
    $cands = @()
    $cands += (Join-Path $userDir $script:SHOT_SUB)
    $cands += (Join-Path $userDir 'OneDrive\Documents\Russian Fishing 4\Screenshots')
    if ($userDir -eq (Get-UserRoot)) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if ($docs) { $cands += (Join-Path $docs 'Russian Fishing 4\Screenshots') }
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    if ($Create) { return $cands[0] }
    return $null
}

# ── Mailboxen mergen (Kernstück) ───────────────────────────────────────────────
function Merge-Mailbox {
    param([string]$SrcDir, [string]$DstDir, [string]$UndoRoot)
    $r = [pscustomobject]@{ Merged = 0; Copied = 0; Unchanged = 0; Added = 0; Failed = 0 }
    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null

    foreach ($srcFile in (Get-Dats $SrcDir)) {
        $dstFile = Join-Path $DstDir $srcFile.Name
        if (-not (Test-Path -LiteralPath $dstFile)) {
            Copy-Item -LiteralPath $srcFile.FullName -Destination $dstFile
            $r.Copied++
            try { $ci = (Read-JsonFile $srcFile.FullName).PSObject.Properties['items']; if ($ci -and $null -ne $ci.Value) { $r.Added += @($ci.Value).Count } } catch { }
            continue
        }
        try {
            $s = Read-JsonFile $srcFile.FullName
            $d = Read-JsonFile $dstFile
            $sp = $s.PSObject.Properties['items']; $dp = $d.PSObject.Properties['items']
            $srcItems = if ($sp -and $null -ne $sp.Value) { @($sp.Value) } else { @() }
            $dstItems = if ($dp -and $null -ne $dp.Value) { @($dp.Value) } else { @() }

            $seen = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($it in $dstItems) { $id = Get-MsgId $it; if ($id) { [void]$seen.Add($id) } }
            $extra = @()
            foreach ($it in $srcItems) {
                $id = Get-MsgId $it
                if (-not $id) { continue }
                if ($seen.Add($id)) { $extra += $it }
            }
            if ($extra.Count -eq 0) { $r.Unchanged++; continue }

            Save-Undo $dstFile $UndoRoot
            $all = @($dstItems) + @($extra)
            $order = 0
            $sorted = @($all | ForEach-Object { [pscustomobject]@{ k = (Get-MsgCreated $_); o = $order++; v = $_ } } |
                Sort-Object k, o | ForEach-Object { $_.v })
            if ($dp) { $d.items = $sorted } else { Add-Member -InputObject $d -NotePropertyName items -NotePropertyValue $sorted }
            Write-JsonFile $d $dstFile
            $r.Added += $extra.Count; $r.Merged++
            Write-Log 'info' 'mb_merge_file' @($srcFile.Name, $extra.Count)
        } catch {
            $r.Failed++
            Write-Log 'warn' 'mb_merge_fail' @($srcFile.Name, $_.Exception.Message)
        }
    }
    Add-Stat MsgAdded $r.Added; Add-Stat ConvNew $r.Copied; Add-Stat ConvMerged $r.Merged; Add-Stat Failed $r.Failed
    Write-Log 'ok' 'mb_summary' @($r.Merged, $r.Copied, $r.Unchanged)
    return $r
}

# Einzeldatei (Settings/Preferences/Crafting). $Confirm: scriptblock($name) -> $true = überschreiben
function Copy-DatFile {
    param([string]$Src, [string]$Dst, [scriptblock]$Confirm, [string]$UndoRoot)
    $name = Split-Path $Src -Leaf
    if (-not (Test-Path -LiteralPath $Src)) { Write-Log 'warn' 'f_missing' @($name); return 'missing' }
    try {
        if (Test-Path -LiteralPath $Dst) {
            if ((Get-FileHash -LiteralPath $Src).Hash -eq (Get-FileHash -LiteralPath $Dst).Hash) {
                Write-Log 'info' 'f_identical' @($name); return 'identical'
            }
            $yes = if ($Confirm) { [bool](& $Confirm $name) } else { $false }
            if (-not $yes) { Add-Stat FilesSkipped; Write-Log 'warn' 'f_skipped' @($name); return 'skipped' }
            Save-Undo $Dst $UndoRoot
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
            Add-Stat FilesReplaced; Write-Log 'ok' 'f_overwritten' @($name); return 'overwritten'
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
        Copy-Item -LiteralPath $Src -Destination $Dst
        Add-Stat FilesNew; Write-Log 'ok' 'f_copied' @($name); return 'copied'
    } catch {
        Add-Stat Failed; Write-Log 'err' 'f_failed' @($name, $_.Exception.Message); return 'failed'
    }
}

function Copy-Screenshots([string]$SrcDir, [string]$DstDir) {
    if (-not $SrcDir -or -not (Test-Path -LiteralPath $SrcDir)) { Write-Log 'warn' 'shots_none'; return 0 }
    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null
    $n = 0
    foreach ($img in @(Get-ChildItem -LiteralPath $SrcDir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.png', '.jpg', '.jpeg') })) {
        $t = Join-Path $DstDir $img.Name
        if (-not (Test-Path -LiteralPath $t)) { Copy-Item -LiteralPath $img.FullName -Destination $t; $n++ }
    }
    Add-Stat Shots $n
    Write-Log 'ok' 'shots_done' @($n, $DstDir)
    return $n
}

# Gemeinsame Routine für Backup UND Restore:  SrcDir → DstDir
#   Items:    'mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots'
#   Accounts: $null/leer = alle, sonst Liste von Ordnernamen (Mailbox_123)
function Copy-Rf4Data {
    param([string]$SrcDir, [string]$DstDir, [string[]]$Items, [string[]]$Accounts,
          [string]$ShotsSrc, [string]$ShotsDst, [scriptblock]$Confirm, [string]$UndoRoot)
    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null
    foreach ($it in $Items) {
        if ($it -eq 'mail') {
            $boxes = @(Get-Mailboxes $SrcDir)
            if ($Accounts -and $Accounts.Count -gt 0) { $boxes = @($boxes | Where-Object { $Accounts -contains $_.Name }) }
            if ($boxes.Count -eq 0) { Write-Log 'warn' 'no_mailboxes'; continue }
            foreach ($b in $boxes) {
                Write-Log 'info' 'mb_header' @($b.Name)
                [void](Merge-Mailbox -SrcDir $b.Path -DstDir (Join-Path $DstDir $b.Name) -UndoRoot $UndoRoot)
            }
        } elseif ($it -eq 'shots') {
            [void](Copy-Screenshots $ShotsSrc $ShotsDst)
        } elseif ($script:DatFiles -contains $it) {
            [void](Copy-DatFile -Src (Join-Path $SrcDir $it) -Dst (Join-Path $DstDir $it) -Confirm $Confirm -UndoRoot $UndoRoot)
        }
    }
    if ($UndoRoot -and (Test-Path -LiteralPath $UndoRoot)) { Write-Log 'info' 'undo_saved' @($UndoRoot) }
}

# Vorhandene Backups: Standardordner, gemerkte Ordner (settings.json) und je eine Ebene darunter
function Test-LooksLikeBackup([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
    if (@(Get-ChildItem -LiteralPath $dir -Directory -Filter 'Mailbox_*' -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    foreach ($f in $script:DatFiles) { if (Test-Path -LiteralPath (Join-Path $dir $f)) { return $true } }
    return (Test-Path -LiteralPath (Join-Path $dir 'Screenshots') -PathType Container)
}
# ── Backup-Info (von wann, von welcher Installation) ────────────────────────────
# Datei rf4-backup.info im Backup-Ordner, Format key=value (sprachneutral; auch vom Bash-Skript lesbar/schreibbar)
function Get-BackupInfoFile([string]$dir) { Join-Path $dir 'rf4-backup.info' }
function Read-BackupInfo([string]$dir) {
    $f = Get-BackupInfoFile $dir
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $o = @{ history = @() }
        foreach ($line in [IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8)) {
            $l = $line.TrimStart([char]0xFEFF); if ($l.Length -eq 0 -or $l[0] -eq '#') { continue }
            $eq = $l.IndexOf('='); if ($eq -lt 1) { continue }
            $k = $l.Substring(0, $eq).Trim(); $v = $l.Substring($eq + 1)
            if ($k -eq 'history') { $o.history += $v } else { $o[$k] = $v }
        }
        return [pscustomobject]@{
            Created = [string]$o['created']; Updated = [string]$o['updated']; Host = [string]$o['host']; Tool = [string]$o['tool']
            Variant = [string]$o['variant']; Folder = [string]$o['folder']; WhereType = [string]$o['wtype']; Where1 = [string]$o['w1']; Where2 = [string]$o['w2']
            SourcePath = [string]$o['srcpath']; Items = [string]$o['items']; History = @($o.history)
        }
    } catch { return $null }
}
function Write-BackupInfo([string]$Dest, $Inst, [string[]]$Items) {
    try {
        $now = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $old = Read-BackupInfo $Dest
        $created = if ($old -and $old.Created) { $old.Created } else { $now }
        $hist = @("$now|$($Inst.Variant)|$($Inst.Folder)|$env:COMPUTERNAME") + @($(if ($old) { $old.History } else { @() }))
        $lines = @('# RF4 Backup Tool - Informationen zu diesem Backup (von wann, von welcher Installation)',
            "created=$created", "updated=$now", "tool=$script:ToolVersion", "host=$env:COMPUTERNAME", "user=$env:USERNAME",
            "variant=$($Inst.Variant)", "folder=$($Inst.Folder)", "wtype=$($Inst.WhereType)", "w1=$($Inst.Where1)", "w2=$($Inst.Where2)", "srcpath=$($Inst.Path)", "items=$($Items -join ',')")
        foreach ($h in ($hist | Select-Object -First 10)) { $lines += "history=$h" }
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        [IO.File]::WriteAllText((Get-BackupInfoFile $Dest), (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
    } catch { }
}
function Get-BackupSourceLabel($info) {
    if (-not $info -or -not $info.Variant) { return (T 'bk_source_unknown') }
    $pseudo = [pscustomobject]@{ Variant = $info.Variant; Folder = $info.Folder; WhereType = $(if ($info.WhereType) { $info.WhereType } else { 'extra' }); Where1 = $info.Where1; Where2 = $info.Where2 }
    $s = Get-InstLabel $pseudo
    if ($info.Host) { $s += '  ' + (T 'bk_from_pc' @($info.Host)) }
    return (T 'bk_source' @($s))
}
function Format-BackupDates($bk) {
    if ($bk.PSObject.Properties['IsSync'] -and $bk.IsSync) { return (T 'bk_sync_hint') }
    $c = if ($bk.Created) { $bk.Created } else { '?' }; $u = if ($bk.Updated) { $bk.Updated } else { $bk.Time.ToString('yyyy-MM-dd HH:mm') }
    return (T 'bk_dates' @($c, $u))
}
function Get-BackupEntry([string]$c) {
    $bc = Get-BackupContents $c
    $files = @(Get-ChildItem -LiteralPath $c -Recurse -File -ErrorAction SilentlyContinue)
    $size = 0L; $latest = [datetime]::MinValue
    foreach ($fi in $files) { $size += $fi.Length; if ($fi.LastWriteTime -gt $latest) { $latest = $fi.LastWriteTime } }
    $convs = 0; foreach ($m in $bc.Mailboxes) { $convs += $m.Convs }
    $inf = Read-BackupInfo $c
    $isSync = ((Split-Path $c -Leaf) -eq 'RF4_Sync')
    $label = Get-BackupSourceLabel $inf; $upd = $(if ($inf) { $inf.Updated } else { '' })
    if ($isSync -and -not $inf) {
        $sl = Get-SyncLogInfo $c
        $label = if ($sl) { T 'bk_source_sync' @($sl.Host, $sl.Time) } else { T 'bk_source_sync_unknown' }
        if ($sl) { $upd = $sl.Time }
    }
    return [pscustomobject]@{ Path = $c; Name = (Split-Path $c -Leaf); Time = $latest; SizeBytes = $size; Mailboxes = $bc.Mailboxes.Count; Convs = $convs; Files = $bc.Files; Shots = $bc.Shots
        Info = $inf; Created = $(if ($inf) { $inf.Created } else { '' }); Updated = $upd; SourceLabel = $label; IsSync = $isSync }
}
# Mehrzeiliger Beschreibungstext eines Backups (für Karten/Menüs)
function Format-BackupCard($bk) { return ($bk.Path + "`n" + $bk.SourceLabel + "`n" + (Format-BackupInfo $bk) + "`n" + (Format-BackupDates $bk)) }
# Akzeptiert auch den ÜBERGEORDNETEN Ordner eines Sync-Ordners (…\RF4_Sync): liefert den Pfad, aus dem wiederhergestellt werden kann, sonst $null
function Resolve-BackupPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (Test-LooksLikeBackup $p) { return $p }
    $s = Join-Path $p 'RF4_Sync'
    if (Test-LooksLikeBackup $s) { return $s }
    return $null
}
# letzte Zeile von .sync_log: "2026-10-09T09:01:08Z HOSTNAME"
function Get-SyncLogInfo([string]$dir) {
    $f = Join-Path $dir '.sync_log'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $last = @(Get-Content -LiteralPath $f -ErrorAction Stop | Where-Object { $_.Trim() } | Select-Object -Last 1)[0]
        $m = [regex]::Match([string]$last, '^(\S+)\s+(.*)$')
        if (-not $m.Success) { return $null }
        $dt = [datetime]::MinValue; [void][datetime]::TryParse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$dt)
        return [pscustomobject]@{ Host = $m.Groups[2].Value.Trim(); Time = $(if ($dt -ne [datetime]::MinValue) { $dt.ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { $m.Groups[1].Value }) }
    } catch { return $null }
}
function Find-Backups {
    $bases = New-Object System.Collections.Generic.List[string]
    $bases.Add((Get-DefaultBackupDir))
    foreach ($d in @((Get-Config).backupDirs)) { if ($d) { $bases.Add($d) } }
    $sp = Get-SyncPath; if ($sp) { try { if (Test-Path -LiteralPath $sp -PathType Container) { $bases.Add($sp) } } catch { } }
    foreach ($x in @(([string]$env:RF4_BACKUP_DIRS) -split ';' | Where-Object { $_ })) { $bases.Add($x) }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($b in $bases) {
        if (-not (Test-Path -LiteralPath $b -PathType Container)) { continue }
        $cands = @($b) + @(Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'Mailbox_*' -and $_.Name -ne 'Screenshots' } | ForEach-Object { $_.FullName })
        foreach ($c in $cands) {
            $norm = $c.TrimEnd('\').ToLowerInvariant()
            if ($seen.Contains($norm) -or -not (Test-LooksLikeBackup $c)) { continue }
            [void]$seen.Add($norm)
            $found.Add((Get-BackupEntry $c))
        }
    }
    return @($found | Sort-Object Time -Descending)
}
function Format-Size([long]$b) {
    if ($b -ge 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return "$b B"
}
function Format-BackupInfo($bk) {
    $parts = @((T 'bk_mailbox_n' @($bk.Mailboxes, $bk.Convs)))
    if ($bk.Files.Count -gt 0) { $parts += (T 'bk_files_n' @($bk.Files.Count)) }
    if ($bk.Shots -gt 0) { $parts += (T 'bk_shots_n' @($bk.Shots)) }
    $parts += (Format-Size $bk.SizeBytes)
    return ($parts -join '  ·  ')
}

function Get-BackupContents([string]$dir) {
    $mb = @(Get-Mailboxes $dir)
    $files = @($script:DatFiles | Where-Object { Test-Path -LiteralPath (Join-Path $dir $_) })
    $shots = 0
    $sd = Join-Path $dir 'Screenshots'
    if (Test-Path -LiteralPath $sd) { $shots = Count-Of (Get-ChildItem -LiteralPath $sd -File -Recurse -ErrorAction SilentlyContinue) }
    [pscustomobject]@{ Mailboxes = $mb; Files = $files; Shots = $shots; Empty = (($mb.Count + $files.Count + $shots) -eq 0) }
}

# ── Sync ───────────────────────────────────────────────────────────────────────
function Invoke-SyncRun {
    param([string]$InstPath, [string]$SyncBase)
    $syncDir = Join-Path $SyncBase 'RF4_Sync'
    New-Item -ItemType Directory -Force -Path $syncDir | Out-Null
    $undo = New-UndoRoot $InstPath
    Write-Log 'info' 'sync_local'  @($InstPath)
    Write-Log 'info' 'sync_remote' @($syncDir)

    Write-Log 'info' 'sync_p1'
    $local = @(Get-Mailboxes $InstPath)
    if ($local.Count -eq 0) { Write-Log 'warn' 'sync_nolocal' }
    foreach ($b in $local) {
        Write-Log 'info' 'mb_header' @($b.Name)
        [void](Merge-Mailbox -SrcDir $b.Path -DstDir (Join-Path $syncDir $b.Name))
    }

    Write-Log 'info' 'sync_p2'
    $remote = @(Get-Mailboxes $syncDir)
    if ($remote.Count -eq 0) { Write-Log 'warn' 'sync_noremote' }
    foreach ($b in $remote) {
        Write-Log 'info' 'mb_header' @($b.Name)
        [void](Merge-Mailbox -SrcDir $b.Path -DstDir (Join-Path $InstPath $b.Name) -UndoRoot $undo)
    }

    Write-Log 'info' 'sync_p3'
    foreach ($dat in $script:DatFiles) {
        $lf = Join-Path $InstPath $dat; $sf = Join-Path $syncDir $dat
        $hasL = Test-Path -LiteralPath $lf; $hasS = Test-Path -LiteralPath $sf
        if ($hasL -and -not $hasS) { Copy-Item -LiteralPath $lf -Destination $sf; Write-Log 'ok' 'sync_up' @($dat) }
        elseif (-not $hasL -and $hasS) { Copy-Item -LiteralPath $sf -Destination $lf; Write-Log 'ok' 'sync_down' @($dat) }
        elseif ($hasL -and $hasS) {
            $lt = (Get-Item -LiteralPath $lf).LastWriteTimeUtc; $st = (Get-Item -LiteralPath $sf).LastWriteTimeUtc
            if ((Get-FileHash -LiteralPath $lf).Hash -eq (Get-FileHash -LiteralPath $sf).Hash) { Write-Log 'info' 'sync_same' @($dat) }
            elseif ($lt -gt $st) { Copy-Item -LiteralPath $lf -Destination $sf -Force; Write-Log 'ok' 'sync_up_new' @($dat) }
            elseif ($st -gt $lt) { Save-Undo $lf $undo; Copy-Item -LiteralPath $sf -Destination $lf -Force; Write-Log 'ok' 'sync_down_new' @($dat) }
            else { Write-Log 'info' 'sync_same' @($dat) }
        }
    }
    $line = "$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')) $env:COMPUTERNAME"
    Add-Content -LiteralPath (Join-Path $syncDir '.sync_log') -Value $line -Encoding UTF8
    if (Test-Path -LiteralPath $undo) { Write-Log 'info' 'undo_saved' @($undo) }
    Write-Log 'ok' 'sync_done'
}

function Get-SyncStatus([string]$SyncBase) {
    $syncDir = Join-Path $SyncBase 'RF4_Sync'
    $o = [pscustomobject]@{ Exists = (Test-Path -LiteralPath $syncDir); Mailboxes = @(); Files = @(); Log = @() }
    if (-not $o.Exists) { return $o }
    $o.Mailboxes = @(Get-Mailboxes $syncDir)
    $o.Files = @($script:DatFiles | Where-Object { Test-Path -LiteralPath (Join-Path $syncDir $_) } |
        ForEach-Object { [pscustomobject]@{ Name = $_; Time = (Get-Item -LiteralPath (Join-Path $syncDir $_)).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } })
    $lf = Join-Path $syncDir '.sync_log'
    if (Test-Path -LiteralPath $lf) { $o.Log = @(Get-Content -LiteralPath $lf | Select-Object -Last 5) }
    return $o
}
