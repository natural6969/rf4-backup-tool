#Requires -Version 5.1
# Baut die ausgelieferten Einzeldateien aus src\ (UTF-8 mit BOM, damit PS 5.1 Kyrillisch/Chinesisch korrekt liest).
$root = $PSScriptRoot
$enc = New-Object Text.UTF8Encoding($true)
function ReadSrc($p) { [IO.File]::ReadAllText((Join-Path $root $p), [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) }
$core = ReadSrc 'src\core.ps1'
$ver  = ([regex]::Match($core, "ToolVersion = '([\d\.]+)'")).Groups[1].Value
$date = ([regex]::Match($core, "ToolDate\s+= '([\d\-]+)'")).Groups[1].Value
$tpl = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    RF4 Backup & Migration Tool – @@KIND@@
.DESCRIPTION
    Findet RF4-Installationen (Standalone + Steam) und sichert, stellt wieder her, führt zusammen
    und synchronisiert Mailboxen, Einstellungen und Screenshots. Es wird nichts gelöscht; ersetzte
    Dateien landen in <Installation>\_rf4tool_undo\<Zeitstempel>.
    Sprachen: Deutsch, English, 中文, Русский (im Programm umschaltbar, oder -Lang de|en|zh|ru,
    oder Umgebungsvariable RF4_LANG).
.NOTES
    Start: Rechtsklick -> "Mit PowerShell ausführen"  oder  powershell -ExecutionPolicy Bypass -File <Datei>
    Blog: https://nga.li/rf4b | Quellcode: https://nga.li/rf4git | Download: https://nga.li/rf4dl
    Spenden/Donate: https://paypal.me/bjoernoppermann
.LINK
    https://nga.li/rf4b
#>
# Version @@VER@@ – @@DATE@@
param([string]$Lang = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

'@
function Head($kind) { $tpl.Replace('@@KIND@@', $kind).Replace('@@VER@@', $ver).Replace('@@DATE@@', $date) }
$cli = (Head 'Terminal') + $core + "`r`n" + (ReadSrc 'src\cli.ps1')
[IO.File]::WriteAllText((Join-Path $root 'rf4sa-backup.ps1'), $cli, $enc)
if (Test-Path (Join-Path $root 'src\gui.ps1')) {
    $guiSrc = ReadSrc 'src\gui.ps1'
    if ($guiSrc.Trim().Length -gt 0) {
        [IO.File]::WriteAllText((Join-Path $root 'rf4sa-backup-gui.ps1'), ((Head 'GUI') + $core + "`r`n" + $guiSrc), $enc)
    }
}
# ── Linux/macOS-Skript: Übersetzungstabelle aus core.ps1 erzeugen ──────────────────
$shSrc = Join-Path $root 'src\cli.sh'
if (Test-Path $shSrc) {
    . (Join-Path $root 'src\core.ps1')          # definiert $script:TX
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in @('de', 'en', 'zh', 'ru')) {
        foreach ($k in ($script:TX.Keys | Sort-Object)) {
            $v = [string]$script:TX[$k][$l]
            [void]$sb.Append("TX[${l}:$k]='").Append($v.Replace("'", "'\''")).Append("'`n")
        }
    }
    $sh = (ReadSrc 'src\cli.sh').Replace("`r`n", "`n").Replace('# @@STRINGS@@', $sb.ToString().TrimEnd("`n")).Replace('@@VERSION@@', $ver).Replace('@@DATE@@', $date)
    [IO.File]::WriteAllText((Join-Path $root 'rf4sa-backup.sh'), $sh, (New-Object Text.UTF8Encoding($false)))
}
Write-Host "Gebaut: v$ver"
