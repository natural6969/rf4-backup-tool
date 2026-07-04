#Requires -Version 5.1
<#
.SYNOPSIS
    RF4 Standalone Backup & Migration Tool (Windows PowerShell)
.DESCRIPTION
    Findet automatisch alle RF4-Installationen auf diesem PC und ermöglicht
    Backup, Restore und Merge von Mailboxen, Einstellungen und Screenshots.
    Kompatibel mit Windows 7 / 10 / 11.
.NOTES
    Ausführen: Rechtsklick → "Mit PowerShell ausführen"
    Oder: powershell -ExecutionPolicy Bypass -File rf4sa-backup.ps1
    Blog/Infos:    https://nga.li/rf4backup
    RF4 Offiziell: https://nga.li/rf4de  (DE) | https://nga.li/rf4en  (EN)
    Steam:         https://nga.li/rf4steam
    Download SA:   https://nga.li/rf4dl
    Transfer-Info: https://nga.li/rf4transfer  (nur Steam → Standalone)
.LINK
    https://nga.li/rf4backup
#>
# Version 1.1.0 – 2026-06-23
# Changelog:
#   1.1.0  Standalone-Labels, Account-IDs im Scan, Per-Account Backup/Restore,
#          Multi-Quellen Merge, nga.li-Links, Laufwerksbuchstabe im Scan
#   1.0.0  Erstveröffentlichung

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Konfiguration ──────────────────────────────────────────────────────────────
$RF4_VARIANTS = @(
    @{ Folder = "RussianFishing4DE";      Label = "RF4 Standalone Deutsch";       Steam = $false },
    @{ Folder = "RussianFishing4DE_new";  Label = "RF4 Standalone Deutsch (neu)"; Steam = $false },
    @{ Folder = "RussianFishing4EN";      Label = "RF4 Standalone Englisch";       Steam = $false },
    @{ Folder = "RussianFishing4Steam";   Label = "RF4 Steam";                     Steam = $true  }
)
$RF4_BASE        = "AppData\Roaming\RussianFishingLLC"
$SCREENSHOT_SUB  = "Documents\Russian Fishing 4\Screenshots"
$DEFAULT_BACKUP  = "$env:USERPROFILE\RF4_Backup"

# ── Farben / Ausgabe ───────────────────────────────────────────────────────────
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  --> $msg"  -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "  [!] $msg"  -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [X] $msg"  -ForegroundColor Red }
function Write-Sep()      { Write-Host ("─" * 56) -ForegroundColor DarkGray }
function Write-Hdr($t)    {
    Write-Host ""
    Write-Host "╔══ $t ══╗" -ForegroundColor Blue
    Write-Sep
}

function Pause-Menu {
    Write-Host ""
    Read-Host "  [Enter] zum Fortfahren" | Out-Null
}

# ── Numerisches Menü ───────────────────────────────────────────────────────────
function Show-Menu {
    param([string]$Title, [string[]]$Options)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White
    Write-Sep
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  [$($i+1)] $($Options[$i])" -ForegroundColor Yellow
    }
    Write-Host "  [0] Zurück" -ForegroundColor Yellow
    Write-Host ""
    do {
        $raw = Read-Host "  Wähle"
        if ($raw -eq "0") { return 0 }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $Options.Count) {
            return [int]$raw
        }
        Write-Warn "Ungültige Eingabe."
    } while ($true)
}

# ── Mehrfachauswahl ────────────────────────────────────────────────────────────
function Show-MultiSelect {
    param([string]$Title, [string[]]$Options)
    $chosen = @($false) * $Options.Count

    while ($true) {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor White
        Write-Host "  (Nummer ein/ausschalten, a=alle, n=keine, Enter=OK, 0=Zurück)" -ForegroundColor DarkGray
        Write-Sep
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $mark = if ($chosen[$i]) { "[X]" } else { "[ ]" }
            $col  = if ($chosen[$i]) { "Green" } else { "DarkGray" }
            Write-Host "  $mark $($i+1)) $($Options[$i])" -ForegroundColor $col
        }
        Write-Host ""
        $raw = Read-Host "  Wähle"

        if ($raw -eq "") {
            $sel = @()
            for ($i = 0; $i -lt $Options.Count; $i++) {
                if ($chosen[$i]) { $sel += $Options[$i] }
            }
            return $sel
        }
        if ($raw -eq "0") { return $null }
        if ($raw -eq "a") { $chosen = @($true)  * $Options.Count; continue }
        if ($raw -eq "n") { $chosen = @($false) * $Options.Count; continue }
        if ($raw -match '^\d+$') {
            $idx = [int]$raw - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) {
                $chosen[$idx] = -not $chosen[$idx]
            }
        }
    }
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
    $userRoot = [System.IO.Path]::GetDirectoryName($env:APPDATA)  # C:\Users\<Name>
    $driveLetter = $env:APPDATA.Substring(0,2)
    foreach ($v in $RF4_VARIANTS) {
        $p = Join-Path $userRoot "$RF4_BASE\$($v.Folder)"
        $tag = if ($v.Steam) { " [Steam]" } else { "" }
        Add-Install "$($v.Label)$tag [$driveLetter / $env:USERNAME]" $p "local"
    }

    # 2) Alle anderen Benutzer auf diesem System
    $usersRoot = Split-Path $userRoot -Parent  # C:\Users
    foreach ($uDir in (Get-ChildItem $usersRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($uDir.Name -in @("Public", "Default", "Default User", "All Users")) { continue }
        if ($uDir.FullName -eq $userRoot) { continue }
        foreach ($v in $RF4_VARIANTS) {
            $p = Join-Path $uDir.FullName "$RF4_BASE\$($v.Folder)"
            $tag = if ($v.Steam) { " [Steam]" } else { "" }
            Add-Install "$($v.Label)$tag [User: $($uDir.Name)]" $p "other_user"
        }
    }

    # 3) Alle Laufwerke durchsuchen (externe Festplatten, USBs, alte Installs)
    $drives = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -in @("Fixed","Removable","Network") -and $_.IsReady }
    foreach ($drv in $drives) {
        $label = if ($drv.VolumeLabel) { $drv.VolumeLabel } else { $drv.Name.TrimEnd('\') }
        # Windows Users-Ordner auf diesem Laufwerk
        $uRoot = Join-Path $drv.RootDirectory.FullName "Users"
        if (-not (Test-Path $uRoot)) { continue }
        foreach ($uDir in (Get-ChildItem $uRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($uDir.Name -in @("Public", "Default", "Default User", "All Users")) { continue }
            foreach ($v in $RF4_VARIANTS) {
                $p = Join-Path $uDir.FullName "$RF4_BASE\$($v.Folder)"
                $tag = if ($v.Steam) { " [Steam]" } else { "" }
                Add-Install "$($v.Label)$tag [Laufwerk: $label / $($uDir.Name)]" $p "drive"
            }
        }
    }

    return $results
}

# ── Mailboxen mergen ───────────────────────────────────────────────────────────
function Merge-Mailbox {
    param([string]$SrcDir, [string]$DstDir)
    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null
    $merged = 0; $copied = 0

    foreach ($srcFile in (Get-ChildItem $SrcDir -Filter "*.dat" -ErrorAction SilentlyContinue)) {
        $dstFile = Join-Path $DstDir $srcFile.Name
        if (-not (Test-Path $dstFile)) {
            Copy-Item $srcFile.FullName $dstFile
            $copied++
        } else {
            # JSON-Merge per UUID-Dedup
            try {
                $s = Get-Content $srcFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $d = Get-Content $dstFile         -Raw -Encoding UTF8 | ConvertFrom-Json
                $seenIds = @{}
                foreach ($item in $d.items) { $seenIds[$item.meta.id] = $true }
                $extra = $s.items | Where-Object { -not $seenIds.ContainsKey($_.meta.id) }
                $d.items = @($d.items) + @($extra) |
                    Sort-Object { try { [long]$_.meta.created } catch { 0 } }
                $d | ConvertTo-Json -Depth 20 | Set-Content $dstFile -Encoding UTF8
                Write-Info "  Merge $($srcFile.Name): +$($extra.Count) Nachrichten"
                $merged++
            } catch {
                Write-Warn "  Merge fehlgeschlagen: $($srcFile.Name) – $_"
            }
        }
    }
    Write-Ok "Mailbox: $merged Dateien gemergt, $copied neu kopiert"
}

# ── Screenshot-Ordner finden ───────────────────────────────────────────────────
function Find-Screenshots($rf4Path) {
    # Aus dem RF4-Pfad den Benutzerordner ableiten
    $userDir = $rf4Path
    for ($i = 0; $i -lt 4; $i++) { $userDir = Split-Path $userDir -Parent }
    $shotPath = Join-Path $userDir $SCREENSHOT_SUB
    if (Test-Path $shotPath) { return $shotPath }
    # Fallback: Documents direkt
    $docs = [Environment]::GetFolderPath("MyDocuments")
    $alt  = Join-Path $docs "Russian Fishing 4\Screenshots"
    if (Test-Path $alt) { return $alt }
    return $null
}

# ── SCAN ──────────────────────────────────────────────────────────────────────
function Do-Scan {
    Write-Hdr "INSTALLATIONEN SCANNEN"
    Write-Info "Suche auf allen Laufwerken…"
    $installs = Find-Installations
    if ($installs.Count -eq 0) { Write-Warn "Keine gefunden."; Pause-Menu; return }

    foreach ($inst in $installs) {
        if (Test-Path $inst.Path) {
            $mboxDirs = Get-ChildItem $inst.Path -Directory -Filter "Mailbox_*" -EA SilentlyContinue
            $mboxes = $mboxDirs.Count
            $convs  = (Get-ChildItem $inst.Path -Recurse -Filter "*.dat" -EA SilentlyContinue |
                       Where-Object { $_.DirectoryName -match "Mailbox_" }).Count
            $accIds = ($mboxDirs | ForEach-Object { $_.Name -replace '^Mailbox_','' }) -join ', '
            Write-Ok $inst.Label
            Write-Info "  Pfad: $($inst.Path)"
            Write-Info "  Mailboxen: $mboxes  Konversationen: $convs"
            if ($accIds) { Write-Info "  Account-IDs: $accIds" }
        } else {
            Write-Host "  [leer] $($inst.Label)" -ForegroundColor DarkGray
            Write-Info "  Pfad: $($inst.Path) (nicht vorhanden)"
        }
        Write-Host ""
    }
    Write-Host "  Gesamt: $($installs.Count) Pfade" -ForegroundColor DarkGray
    Pause-Menu
}

# ── BACKUP ────────────────────────────────────────────────────────────────────
function Do-Backup {
    Write-Hdr "BACKUP"
    $installs = Find-Installations
    $existing = @($installs | Where-Object { Test-Path $_.Path })
    if ($existing.Count -eq 0) { Write-Err "Keine Installationen gefunden."; Pause-Menu; return }

    $choice = Show-Menu "Quelle wählen" ($existing | ForEach-Object { $_.Label })
    if ($choice -eq 0) { return }
    $src = $existing[$choice - 1]

    $items = @("Mailboxen (private Nachrichten)", "Settings.dat", "Preferences.dat", "Crafting.dat", "Screenshots")
    $sel   = Show-MultiSelect "Was sichern?" $items
    if ($null -eq $sel -or $sel.Count -eq 0) { Write-Warn "Nichts ausgewählt."; Pause-Menu; return }

    Write-Host ""
    $dest = Read-Host "  Backup-Ordner [$DEFAULT_BACKUP] (Enter=Standard)"
    if ([string]::IsNullOrWhiteSpace($dest)) { $dest = $DEFAULT_BACKUP }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    Write-Info "Von: $($src.Path)"
    Write-Info "Nach: $dest"
    Write-Sep

    foreach ($s in $sel) {
        switch -Wildcard ($s) {
            "Mailboxen*" {
                $mboxDirs = @(Get-ChildItem $src.Path -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
                if ($mboxDirs.Count -eq 0) { Write-Warn "Keine Mailboxen gefunden."; break }
                $selectedMboxes = $mboxDirs
                if ($mboxDirs.Count -gt 1) {
                    $mbOpts = @("Alle Accounts ($($mboxDirs.Count))") + @($mboxDirs | ForEach-Object {
                        $id = $_.Name -replace '^Mailbox_',''
                        $cnt = (Get-ChildItem $_.FullName -Filter '*.dat').Count
                        "Account $id  ($cnt Konversationen)"
                    })
                    $mbChoice = Show-Menu "Welchen Account sichern?" $mbOpts
                    if ($mbChoice -eq 0) { break }
                    if ($mbChoice -gt 1) { $selectedMboxes = @($mboxDirs[$mbChoice - 2]) }
                }
                foreach ($mbox in $selectedMboxes) {
                    $cnt = (Get-ChildItem $mbox.FullName -Filter "*.dat").Count
                    Write-Info "Mailbox $($mbox.Name) ($cnt Konversationen)…"
                    Merge-Mailbox $mbox.FullName (Join-Path $dest $mbox.Name)
                }
            }
            "Settings*" {
                $f = Join-Path $src.Path "Settings.dat"
                if (-not (Test-Path $f)) { Write-Warn "Settings.dat nicht gefunden"; break }
                $d = Join-Path $dest "Settings.dat"
                if (Test-Path $d) {
                    $ow = Read-Host "  Settings.dat existiert im Backup. Überschreiben? [j/N]"
                    if ($ow -eq "j") { Copy-Item $f $d -Force; Write-Ok "Settings.dat überschrieben" } else { Write-Warn "Settings.dat übersprungen" }
                } else { Copy-Item $f $dest; Write-Ok "Settings.dat" }
            }
            "Preferences*" {
                $f = Join-Path $src.Path "Preferences.dat"
                if (-not (Test-Path $f)) { Write-Warn "Preferences.dat nicht gefunden"; break }
                $d = Join-Path $dest "Preferences.dat"
                if (Test-Path $d) {
                    $ow = Read-Host "  Preferences.dat existiert im Backup. Überschreiben? [j/N]"
                    if ($ow -eq "j") { Copy-Item $f $d -Force; Write-Ok "Preferences.dat überschrieben" } else { Write-Warn "Preferences.dat übersprungen" }
                } else { Copy-Item $f $dest; Write-Ok "Preferences.dat" }
            }
            "Crafting*" {
                $f = Join-Path $src.Path "Crafting.dat"
                if (-not (Test-Path $f)) { Write-Warn "Crafting.dat nicht gefunden"; break }
                $d = Join-Path $dest "Crafting.dat"
                if (Test-Path $d) {
                    $ow = Read-Host "  Crafting.dat existiert im Backup. Überschreiben? [j/N]"
                    if ($ow -eq "j") { Copy-Item $f $d -Force; Write-Ok "Crafting.dat überschrieben" } else { Write-Warn "Crafting.dat übersprungen" }
                } else { Copy-Item $f $dest; Write-Ok "Crafting.dat" }
            }
            "Screenshots*" {
                $shotSrc = Find-Screenshots $src.Path
                if ($shotSrc) {
                    $shotDst = Join-Path $dest "Screenshots"
                    New-Item -ItemType Directory -Force -Path $shotDst | Out-Null
                    $count = 0
                    foreach ($img in (Get-ChildItem $shotSrc -Include "*.png","*.jpg" -Recurse -EA SilentlyContinue)) {
                        $tgt = Join-Path $shotDst $img.Name
                        if (-not (Test-Path $tgt)) { Copy-Item $img.FullName $tgt; $count++ }
                    }
                    Write-Ok "Screenshots: $count Bilder"
                } else { Write-Warn "Screenshot-Ordner nicht gefunden" }
            }
        }
    }

    Write-Host ""
    Write-Ok "Backup fertig: $dest"
    Get-ChildItem $dest | Format-Table Name, Length -AutoSize
    Pause-Menu
}

# ── RESTORE ───────────────────────────────────────────────────────────────────
function Do-Restore {
    Write-Hdr "RESTORE / IMPORT"

    $src = Read-Host "  Backup-Ordner [$DEFAULT_BACKUP] (Enter=Standard)"
    if ([string]::IsNullOrWhiteSpace($src)) { $src = $DEFAULT_BACKUP }
    if (-not (Test-Path $src)) { Write-Err "Nicht gefunden: $src"; Pause-Menu; return }

    # Backup-Inhalt anzeigen
    $mboxes = Get-ChildItem $src -Directory -Filter "Mailbox_*" -EA SilentlyContinue
    foreach ($m in $mboxes) {
        Write-Info "  $($m.Name): $((Get-ChildItem $m.FullName -Filter '*.dat').Count) Gespräche"
    }
    foreach ($f in @("Settings.dat","Preferences.dat","Crafting.dat")) {
        if (Test-Path (Join-Path $src $f)) { Write-Info "  $f" }
    }
    $shots = (Get-ChildItem (Join-Path $src "Screenshots") -EA SilentlyContinue).Count
    if ($shots -gt 0) { Write-Info "  Screenshots: $shots Dateien" }

    # Ziel
    $installs = Find-Installations
    $opts = ($installs | ForEach-Object { $_.Label }) + "→ Pfad manuell eingeben"
    $choice = Show-Menu "Ziel-Installation" $opts
    if ($choice -eq 0) { return }

    $dstPath = if ($choice -le $installs.Count) {
        $installs[$choice - 1].Path
    } else {
        Read-Host "  Pfad eingeben"
    }
    if ([string]::IsNullOrWhiteSpace($dstPath)) { Write-Err "Kein Pfad."; Pause-Menu; return }
    New-Item -ItemType Directory -Force -Path $dstPath | Out-Null

    # Was importieren
    $avail = @()
    if ($mboxes.Count -gt 0)  { $avail += "Mailboxen ($($mboxes.Count) Ordner)" }
    if (Test-Path "$src\Settings.dat")    { $avail += "Settings.dat" }
    if (Test-Path "$src\Preferences.dat") { $avail += "Preferences.dat" }
    if (Test-Path "$src\Crafting.dat")    { $avail += "Crafting.dat" }
    if ($shots -gt 0)                    { $avail += "Screenshots ($shots Dateien)" }

    $sel = Show-MultiSelect "Was importieren?" $avail
    if ($null -eq $sel -or $sel.Count -eq 0) { Write-Warn "Nichts ausgewählt."; Pause-Menu; return }

    Write-Info "Importiere nach: $dstPath"
    Write-Sep

    foreach ($s in $sel) {
        switch -Wildcard ($s) {
            "Mailboxen*" {
                $selMboxes = $mboxes
                if ($mboxes.Count -gt 1) {
                    $mbOpts = @("Alle Accounts ($($mboxes.Count))") + @($mboxes | ForEach-Object {
                        $id = $_.Name -replace '^Mailbox_',''
                        $cnt = (Get-ChildItem $_.FullName -Filter '*.dat').Count
                        "Account $id  ($cnt Konversationen)"
                    })
                    $mbChoice = Show-Menu "Welchen Account importieren?" $mbOpts
                    if ($mbChoice -eq 0) { break }
                    if ($mbChoice -gt 1) { $selMboxes = @($mboxes[$mbChoice - 2]) }
                }
                foreach ($mbox in $selMboxes) {
                    Write-Info "Mailbox $($mbox.Name)…"
                    Merge-Mailbox $mbox.FullName (Join-Path $dstPath $mbox.Name)
                }
            }
            "Settings*" {
                $f = Join-Path $src "Settings.dat"; $dst = Join-Path $dstPath "Settings.dat"
                if (Test-Path $dst) {
                    $ow = Read-Host "  Settings.dat existiert. Überschreiben? [j/N]"
                    if ($ow -eq "j") { Copy-Item $f $dst -Force; Write-Ok "Settings.dat überschrieben" }
                    else { Write-Warn "Übersprungen" }
                } else { Copy-Item $f $dst; Write-Ok "Settings.dat kopiert" }
            }
            "Preferences*" {
                $f = Join-Path $src "Preferences.dat"; $dst = Join-Path $dstPath "Preferences.dat"
                if (Test-Path $dst) {
                    $ow = Read-Host "  Preferences.dat existiert. Überschreiben? [j/N]"
                    if ($ow -eq "j") { Copy-Item $f $dst -Force; Write-Ok "Preferences.dat überschrieben" }
                    else { Write-Warn "Übersprungen" }
                } else { Copy-Item $f $dst; Write-Ok "Preferences.dat" }
            }
            "Crafting*" {
                $f = Join-Path $src "Crafting.dat"; $dst = Join-Path $dstPath "Crafting.dat"
                if (Test-Path $dst) {
                    $ow = Read-Host "  Crafting.dat existiert. Überschreiben? [j/N]"
                    if ($ow -eq "j") { Copy-Item $f $dst -Force; Write-Ok "Crafting.dat überschrieben" }
                    else { Write-Warn "Übersprungen" }
                } else { Copy-Item $f $dst; Write-Ok "Crafting.dat" }
            }
            "Screenshots*" {
                $shotSrc = Join-Path $src "Screenshots"
                $shotDst = Find-Screenshots $dstPath
                if (-not $shotDst) {
                    $userDir = $dstPath
                    for ($i = 0; $i -lt 4; $i++) { $userDir = Split-Path $userDir -Parent }
                    $shotDst = Join-Path $userDir $SCREENSHOT_SUB
                }
                New-Item -ItemType Directory -Force -Path $shotDst | Out-Null
                $count = 0
                foreach ($img in (Get-ChildItem $shotSrc -Include "*.png","*.jpg" -EA SilentlyContinue)) {
                    $tgt = Join-Path $shotDst $img.Name
                    if (-not (Test-Path $tgt)) { Copy-Item $img.FullName $tgt; $count++ }
                }
                Write-Ok "Screenshots: $count Bilder → $shotDst"
            }
        }
    }

    Write-Ok "Import abgeschlossen."
    Pause-Menu
}

# ── MERGE ────────────────────────────────────────────────────────────────────
function Do-Merge {
    Write-Hdr "INSTALLATIONEN MERGEN"
    $installs = Find-Installations
    $existing = @($installs | Where-Object { Test-Path $_.Path })
    if ($existing.Count -lt 2) { Write-Warn "Mindestens 2 Installationen nötig."; Pause-Menu; return }

    Write-Host ""
    Write-Host "  WICHTIG:" -ForegroundColor Yellow -NoNewline
    Write-Host " RF4 erlaubt nur den Wechsel Steam → Standalone," -ForegroundColor White
    Write-Host "           nicht umgekehrt. Standalone → Steam ist NICHT möglich." -ForegroundColor White
    Write-Info "  Details: https://nga.li/rf4transfer"
    Write-Host ""
    Write-Info "  Unterstützte Szenarien:"
    Write-Info "   · Steam → Standalone  (Versionswechsel)"
    Write-Info "   · Steam → Steam       (PC-Wechsel / neue Installation)"
    Write-Info "   · Standalone → Standalone  (PC-Wechsel / neue Installation)"
    Write-Info "   · Mehrere alte → eine neue Installation (alle Quellen auswählen)"
    Write-Host ""

    # Ziel wählen
    $dstChoice = Show-Menu "Ziel-Installation (Hauptinstallation)" ($existing | ForEach-Object { $_.Label })
    if ($dstChoice -eq 0) { return }
    $dstPath = $existing[$dstChoice - 1].Path

    # Quellen wählen (Mehrfachauswahl, Ziel ausschließen)
    $srcOptions = @($existing | Where-Object { $_.Path -ne $dstPath })
    if ($srcOptions.Count -eq 0) { Write-Err "Keine weiteren Installationen als Quellen verfügbar."; Pause-Menu; return }
    $selSrcs = Show-MultiSelect "Quellen wählen (mehrere möglich)" ($srcOptions | ForEach-Object { $_.Label })
    if ($null -eq $selSrcs -or $selSrcs.Count -eq 0) { Write-Warn "Keine Quelle gewählt."; Pause-Menu; return }

    Write-Info "Ziel: $dstPath"
    Write-Sep

    foreach ($srcLabel in $selSrcs) {
        $srcInst = $srcOptions | Where-Object { $_.Label -eq $srcLabel } | Select-Object -First 1
        if (-not $srcInst) { continue }
        Write-Info "=== Quelle: $($srcInst.Label)"
        $mboxDirs = @(Get-ChildItem $srcInst.Path -Directory -Filter "Mailbox_*" -EA SilentlyContinue)
        if ($mboxDirs.Count -eq 0) { Write-Warn "  Keine Mailboxen gefunden."; continue }

        $selectedMboxes = $mboxDirs
        if ($mboxDirs.Count -gt 1) {
            $mbOpts = @("Alle Accounts ($($mboxDirs.Count))") + @($mboxDirs | ForEach-Object {
                $id  = $_.Name -replace '^Mailbox_',''
                $cnt = (Get-ChildItem $_.FullName -Filter '*.dat').Count
                "Account $id  ($cnt Konversationen)"
            })
            $mbChoice = Show-Menu "Welche Accounts aus dieser Quelle mergen?" $mbOpts
            if ($mbChoice -eq 0) { continue }
            if ($mbChoice -gt 1) { $selectedMboxes = @($mboxDirs[$mbChoice - 2]) }
        }

        foreach ($mbox in $selectedMboxes) {
            Write-Info "Mailbox $($mbox.Name)…"
            Merge-Mailbox $mbox.FullName (Join-Path $dstPath $mbox.Name)
        }
    }

    Write-Ok "Merge abgeschlossen."
    Pause-Menu
}

# ── Hauptmenü ─────────────────────────────────────────────────────────────────
while ($true) {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║   RF4 Standalone  Backup & Migration         ║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host "  RF4: nga.li/rf4de | Steam: nga.li/rf4steam | Download: nga.li/rf4dl" -ForegroundColor DarkGray
    Write-Host "  Blog: nga.li/rf4backup | Forum: nga.li/rf4forum" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Scan     – Alle Installationen anzeigen" -ForegroundColor Yellow
    Write-Host "  [2] Backup   – Daten sichern"                -ForegroundColor Yellow
    Write-Host "  [3] Restore  – In Installation importieren"  -ForegroundColor Yellow
    Write-Host "  [4] Merge    – Installationen zusammenführen" -ForegroundColor Yellow
    Write-Host "  [0] Beenden"                                  -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "  Wähle"
    switch ($choice) {
        "1" { Do-Scan    }
        "2" { Do-Backup  }
        "3" { Do-Restore }
        "4" { Do-Merge   }
        "0" { exit 0 }
    }
}
