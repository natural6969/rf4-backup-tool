#Requires -Version 5.1
# Baut die ausgelieferten Einzeldateien aus src\ (UTF-8 mit BOM, damit PS 5.1 Kyrillisch/Chinesisch korrekt liest).
#   src\core.ps1 + src\lang\*.lang + src\themes\*.theme  ->  eingebettet in rf4sa-backup.ps1 und rf4sa-backup-gui.ps1
#   src\ui.cs                                              ->  eingebettet in rf4sa-backup-gui.ps1
#   src\cli.sh + Sprachtabelle                             ->  rf4sa-backup.sh
$root = $PSScriptRoot
$enc = New-Object Text.UTF8Encoding($true)
function ReadSrc($p) { [IO.File]::ReadAllText((Join-Path $root $p), [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) }

# ── Daten (Sprachen + Themes) als ein Textblock ─────────────────────────────────
$sbData = New-Object System.Text.StringBuilder
foreach ($f in @(Get-ChildItem (Join-Path $root 'src\lang') -Filter '*.lang' | Sort-Object Name) + @(Get-ChildItem (Join-Path $root 'src\themes') -Filter '*.theme' | Sort-Object Name)) {
    $rel = ($f.FullName.Substring($root.Length + 5)).Replace('\', '/')
    [void]$sbData.Append("@@FILE $rel`n").Append(([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)).Replace("`r`n", "`n").TrimEnd("`n")).Append("`n")
}
$dataBlock = "`$script:EmbeddedData = @'`n" + $sbData.ToString() + "'@`n"
$core = (ReadSrc 'src\core.ps1').Replace('# @@LOADER@@', $dataBlock)
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
    oder Umgebungsvariable RF4_LANG). Weitere Sprachen/Themes: Dateien in lang\ bzw. themes\
    neben diesem Skript oder in %APPDATA%\rf4-backup\ ablegen (siehe README).
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
    $ui = (ReadSrc 'src\ui.cs').Replace("`r`n", "`n")
    $uiBlock = "`$script:UiCsSource = @'`n" + $ui.TrimEnd("`n") + "`n'@`nAdd-Type -TypeDefinition `$script:UiCsSource -ReferencedAssemblies System.Windows.Forms, System.Drawing`n"
    $gui = (Head 'GUI') + $core + "`r`n" + (ReadSrc 'src\gui.ps1').Replace('# @@UICS@@', $uiBlock)
    [IO.File]::WriteAllText((Join-Path $root 'rf4sa-backup-gui.ps1'), $gui, $enc)
}

# ── Linux/macOS-Skript: Sprachtabelle aus den .lang-Dateien ─────────────────────
$shSrc = Join-Path $root 'src\cli.sh'
if (Test-Path $shSrc) {
    $sb = New-Object System.Text.StringBuilder
    $order = @('de', 'en', 'zh', 'ru')
    foreach ($f in (Get-ChildItem (Join-Path $root 'src\lang') -Filter '*.lang' | Sort-Object { $i = [Array]::IndexOf($order, $_.BaseName); if ($i -lt 0) { 99 } else { $i } }, Name)) {
        $code = $null; $name = $null
        foreach ($line in ([IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8))) {
            $l = $line.TrimStart([char]0xFEFF)
            if ($l.Length -eq 0 -or $l[0] -eq '#') { continue }
            $eq = $l.IndexOf('='); if ($eq -lt 1) { continue }
            $k = $l.Substring(0, $eq).Trim(); $v = $l.Substring($eq + 1)
            if ($k -eq '@code') { $code = $v.Trim(); [void]$sb.Append("LANGS+=('$code')`n"); continue }
            if ($k -eq '@name') { $name = $v.Trim(); [void]$sb.Append("LANG_NAMES[$code]='$name'`n"); continue }
            [void]$sb.Append("TX[${code}:$k]='").Append($v.Replace("'", "'\''")).Append("'`n")
        }
    }
    $sh = (ReadSrc 'src\cli.sh').Replace("`r`n", "`n").Replace('# @@STRINGS@@', $sb.ToString().TrimEnd("`n")).Replace('@@VERSION@@', $ver).Replace('@@DATE@@', $date)
    [IO.File]::WriteAllText((Join-Path $root 'rf4sa-backup.sh'), $sh, (New-Object Text.UTF8Encoding($false)))
}
Write-Host "Gebaut: v$ver"
