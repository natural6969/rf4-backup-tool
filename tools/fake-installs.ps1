#Requires -Version 5.1
<#
.SYNOPSIS
    Erzeugt FAKE-Installationen aus einer echten RF4-Installation zum gefahrlosen Testen (und entfernt sie wieder).
.DESCRIPTION
    Legt unter %APPDATA%\RussianFishingLLC die Ordner RussianFishing4TEST_A / _B / _C an, mit Kopien echter
    Konversationen (A und B überlappen teilweise, A hat teilweise gekürzte Dateien, B hat einen zweiten Account,
    C ist fast leer). So lassen sich Scan, Backup, Restore, Merge und Sync mit realistischen Daten ausprobieren,
    ohne die echten Installationen zu verändern.
    Jeder Fake-Ordner enthält die Marker-Datei _FAKE_TEST_INSTALL.txt; -Remove löscht NUR solche Ordner.
.EXAMPLE
    .\fake-installs.ps1 -Create            # aus der Steam-Installation (oder -Source <Ordner>)
    .\fake-installs.ps1 -Status
    .\fake-installs.ps1 -Remove
#>
param([switch]$Create, [switch]$Remove, [switch]$Status, [string]$Source = '', [string]$Base = '')
$ErrorActionPreference = 'Stop'
if (-not $Base) { $Base = Join-Path $env:APPDATA 'RussianFishingLLC' }
$marker = '_FAKE_TEST_INSTALL.txt'
$names = @('RussianFishing4TEST_A', 'RussianFishing4TEST_B', 'RussianFishing4TEST_C')
$enc = New-Object Text.UTF8Encoding($true)

function Get-Fakes { @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $marker) }) }

if ($Status -or (-not $Create -and -not $Remove)) {
    $f = Get-Fakes
    if ($f.Count -eq 0) { Write-Host 'Keine Fake-Installationen vorhanden.' }
    foreach ($d in $f) { $n = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -Filter '*.dat' -File).Count; Write-Host ("{0}  ({1} .dat-Dateien)" -f $d.FullName, $n) }
    return
}

if ($Remove) {
    foreach ($d in (Get-Fakes)) { [IO.Directory]::Delete($d.FullName, $true); Write-Host "entfernt: $($d.FullName)" }
    return
}

# ── Create ─────────────────────────────────────────────────────────────────────
if (-not $Source) {
    $cand = @(Get-ChildItem -LiteralPath $Base -Directory | Where-Object { $_.Name -notlike 'RussianFishing4TEST_*' } | Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'Mailbox_*' -ErrorAction SilentlyContinue).Count -gt 0 } | Sort-Object { @(Get-ChildItem $_.FullName -Recurse -Filter '*.dat' -File).Count } -Descending)
    if ($cand.Count -eq 0) { throw "Keine echte Installation mit Mailbox unter $Base gefunden – bitte -Source angeben." }
    $Source = $cand[0].FullName
}
Write-Host "Quelle (wird nur gelesen): $Source"
$mbs = @(Get-ChildItem -LiteralPath $Source -Directory -Filter 'Mailbox_*')
if ($mbs.Count -eq 0) { throw 'Quelle hat keine Mailbox_*-Ordner.' }
$mb = $mbs[0]; $files = @(Get-ChildItem -LiteralPath $mb.FullName -Filter '*.dat' -File | Sort-Object Name)
if ($files.Count -lt 4) { throw 'Quelle hat zu wenige Konversationen für sinnvolle Tests.' }
foreach ($n in $names) { $p = Join-Path $Base $n; if ((Test-Path -LiteralPath $p) -and -not (Test-Path -LiteralPath (Join-Path $p $marker))) { throw "$p existiert und ist keine Fake-Installation – abgebrochen." } }

function New-Fake([string]$name, [string]$note) {
    $p = Join-Path $Base $name
    if (Test-Path -LiteralPath $p) { [IO.Directory]::Delete($p, $true) }
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    [IO.File]::WriteAllText((Join-Path $p $marker), "FAKE-Installation zum Testen des RF4 Backup Tools. Gefahrlos löschbar (fake-installs.ps1 -Remove).`r`n$note`r`nQuelle: $Source`r`n", $enc)
    return $p
}
function Read-J($f) { [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json }
function Write-J($o, $f) { [IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Depth 100), $enc) }
function Copy-Truncated($src, $dst, [double]$keep) {   # behält nur den ersten Teil der Nachrichten
    $j = Read-J $src; $items = @($j.items); $k = [Math]::Max(1, [int][Math]::Floor($items.Count * $keep))
    $j.items = @($items | Select-Object -First $k); Write-J $j $dst
}
$half = [int][Math]::Ceiling($files.Count / 2)

# A: erste Hälfte der Konversationen, davon jede zweite nur zu 50 % (→ Merge hat etwas zu ergänzen) + Einstellungen
$A = New-Fake 'RussianFishing4TEST_A' 'A: erste Hälfte der Konversationen, jede zweite gekürzt; Settings.dat + Preferences.dat'
$dirA = Join-Path $A $mb.Name; New-Item -ItemType Directory -Force -Path $dirA | Out-Null
$i = 0; foreach ($f in ($files | Select-Object -First $half)) { if ($i % 2 -eq 1) { Copy-Truncated $f.FullName (Join-Path $dirA $f.Name) 0.5 } else { Copy-Item -LiteralPath $f.FullName -Destination $dirA }; $i++ }
foreach ($s in 'Settings.dat', 'Preferences.dat') { if (Test-Path -LiteralPath (Join-Path $Source $s)) { Copy-Item -LiteralPath (Join-Path $Source $s) -Destination $A } }

# B: zweite Hälfte (überlappt in der Mitte um 2) + ZWEITER Account + abweichende Settings.dat (→ Überschreiben-Rückfrage)
$B = New-Fake 'RussianFishing4TEST_B' 'B: zweite Hälfte der Konversationen (überlappend), zweiter Account Mailbox_111111, abweichende Settings.dat'
$dirB = Join-Path $B $mb.Name; New-Item -ItemType Directory -Force -Path $dirB | Out-Null
foreach ($f in ($files | Select-Object -Skip ([Math]::Max(0, $half - 2)))) { Copy-Item -LiteralPath $f.FullName -Destination $dirB }
$dirB2 = Join-Path $B 'Mailbox_111111'; New-Item -ItemType Directory -Force -Path $dirB2 | Out-Null
foreach ($f in ($files | Select-Object -First 2)) { Copy-Item -LiteralPath $f.FullName -Destination $dirB2 }
if (Test-Path -LiteralPath (Join-Path $Source 'Settings.dat')) { $t = [IO.File]::ReadAllText((Join-Path $Source 'Settings.dat'), [Text.Encoding]::UTF8); [IO.File]::WriteAllText((Join-Path $B 'Settings.dat'), $t.TrimEnd() + "`r`n", $enc); (Get-Item (Join-Path $B 'Settings.dat')).LastWriteTime = (Get-Date).AddDays(-3) }

# C: fast leer (Ziel für Restore)
$C = New-Fake 'RussianFishing4TEST_C' 'C: fast leer – Ziel für Restore/Merge'
if (Test-Path -LiteralPath (Join-Path $Source 'Preferences.dat')) { Copy-Item -LiteralPath (Join-Path $Source 'Preferences.dat') -Destination $C }

foreach ($d in $A, $B, $C) { $n = @(Get-ChildItem -LiteralPath $d -Recurse -Filter '*.dat' -File).Count; Write-Host ("angelegt: {0}  ({1} .dat-Dateien)" -f $d, $n) -ForegroundColor Green }
Write-Host "`nEntfernen mit:  powershell -File `"$PSCommandPath`" -Remove" -ForegroundColor DarkYellow
