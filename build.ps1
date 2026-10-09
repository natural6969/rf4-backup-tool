#Requires -Version 5.1
# Baut die ausgelieferten Einzeldateien aus src\ (UTF-8 mit BOM, damit PS 5.1 Kyrillisch/Chinesisch korrekt liest).
#   src\core.ps1 + src\lang\*.lang + src\themes\*.theme  ->  eingebettet in rf4sa-backup-v<Version>.ps1 und rf4sa-backup-gui-v<Version>.ps1
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
[IO.File]::WriteAllText((Join-Path $root "rf4sa-backup-v$ver.ps1"), $cli, $enc)

if (Test-Path (Join-Path $root 'src\gui.ps1')) {
    $ui = (ReadSrc 'src\ui.cs').Replace("`r`n", "`n")
    $uiBlock = "`$script:UiCsSource = @'`n" + $ui.TrimEnd("`n") + "`n'@`nAdd-Type -TypeDefinition `$script:UiCsSource -ReferencedAssemblies System.Windows.Forms, System.Drawing`n"
    $gui = (Head 'GUI') + $core + "`r`n" + (ReadSrc 'src\gui.ps1').Replace('# @@UICS@@', $uiBlock)
    [IO.File]::WriteAllText((Join-Path $root "rf4sa-backup-gui-v$ver.ps1"), $gui, $enc)
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
    [IO.File]::WriteAllText((Join-Path $root "rf4sa-backup-v$ver.sh"), $sh, (New-Object Text.UTF8Encoding($false)))
}

# ── Anleitung als HTML (aus den READMEs; für Installer/Startmenü, mit Screenshots + klickbaren Links) ──────────
function ConvertTo-GuideHtml([string]$md, [string]$lang, [string]$code) {
    $repo = 'https://codeberg.org/Natural78/rf4-backup-tool/src/branch/main/'
    function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
    function FixUrl([string]$u) {
        if ($u -match '^(https?:|mailto:|#)') { return $u }
        if ($u -match '^README(\.(en|zh|ru))?\.md$') { $c = if ($matches[2]) { $matches[2] } else { 'de' }; return "guide.$c.html" }
        if ($u -match '^docs/img/(.+)$') { return "img/$($matches[1])" }
        if ($u -match '^examples/') { return "../$u" }
        return $repo + $u
    }
    function Inline([string]$s) {
        $out = New-Object System.Text.StringBuilder
        foreach ($part in ($s -split '(`[^`]+`)')) {
            if ($part.Length -gt 1 -and $part[0] -eq '`' -and $part[-1] -eq '`') { [void]$out.Append('<code>' + (Esc $part.Substring(1, $part.Length - 2)) + '</code>'); continue }
            $p = Esc $part
            $p = [regex]::Replace($p, '!\[([^\]]*)\]\(([^)]+)\)', { param($m) '<img alt="' + $m.Groups[1].Value + '" src="' + (FixUrl $m.Groups[2].Value.Replace('&amp;', '&')) + '">' })
            $p = [regex]::Replace($p, '\[([^\]]+)\]\(([^)]+)\)', { param($m) '<a href="' + (FixUrl $m.Groups[2].Value.Replace('&amp;', '&')) + '">' + $m.Groups[1].Value + '</a>' })
            $p = [regex]::Replace($p, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
            $p = [regex]::Replace($p, '(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])', '<em>$1</em>')
            $p = [regex]::Replace($p, '(?<!["=>\w/])(https?://[^\s<)"]+)', '<a href="$1">$1</a>')
            [void]$out.Append($p)
        }
        return $out.ToString()
    }
    $lines = $md.Replace("`r`n", "`n").Split("`n")
    $h = New-Object System.Text.StringBuilder; $title = 'RF4 Backup Tool'; $i = 0; $list = ''
    function CloseList { if ($script:listOpen) { [void]$h.Append("</$($script:listOpen)>`n"); $script:listOpen = '' } }
    $script:listOpen = ''
    while ($i -lt $lines.Count) {
        $l = $lines[$i]
        if ($l -match '^```') { CloseList; $i++; $code2 = New-Object System.Text.StringBuilder; while ($i -lt $lines.Count -and $lines[$i] -notmatch '^```') { [void]$code2.AppendLine((Esc $lines[$i])); $i++ }; [void]$h.Append('<pre><code>' + $code2.ToString() + "</code></pre>`n"); $i++; continue }
        if ($l -match '^\s*$') { CloseList; $i++; continue }
        if ($l -match '^---+\s*$') { CloseList; [void]$h.Append("<hr>`n"); $i++; continue }
        if ($l -match '^(#{1,4})\s+(.*)$') { CloseList; $n = $matches[1].Length; $txt = $matches[2]; if ($n -eq 1 -and $title -eq 'RF4 Backup Tool') { $title = ($txt -replace '[*`]', '') }
            $id = ([regex]::Replace(($txt.ToLowerInvariant() -replace '[^\p{L}\p{N}\s-]', ''), '\s+', '-')); [void]$h.Append("<h$n id=`"$id`">" + (Inline $txt) + "</h$n>`n"); $i++; continue }
        if ($l -match '^\s*\|') {
            CloseList; $rows = @(); while ($i -lt $lines.Count -and $lines[$i] -match '^\s*\|') { $rows += $lines[$i]; $i++ }
            function Cells([string]$r) { $r = $r.Trim(); if ($r.StartsWith('|')) { $r = $r.Substring(1) }; if ($r.EndsWith('|')) { $r = $r.Substring(0, $r.Length - 1) }; ($r -split '(?<!\\)\|') | ForEach-Object { $_.Trim().Replace('\|', '|') } }
            [void]$h.Append('<div class="tw"><table>'); $hd = Cells $rows[0]; [void]$h.Append('<thead><tr>' + (($hd | ForEach-Object { '<th>' + (Inline $_) + '</th>' }) -join '') + '</tr></thead><tbody>')
            for ($r = 2; $r -lt $rows.Count; $r++) { [void]$h.Append('<tr>' + ((Cells $rows[$r] | ForEach-Object { '<td>' + (Inline $_) + '</td>' }) -join '') + '</tr>') }
            [void]$h.Append("</tbody></table></div>`n"); continue }
        if ($l -match '^\s*>\s?(.*)$') { CloseList; $q = @(); while ($i -lt $lines.Count -and $lines[$i] -match '^\s*>\s?(.*)$') { $q += $matches[1]; $i++ }; [void]$h.Append('<blockquote>' + (Inline ($q -join ' ')) + "</blockquote>`n"); continue }
        if ($l -match '^\s*([-*]|\d+\.)\s+(.*)$') {
            $mark = $matches[1]; $itemText = $matches[2]
            $kind = if ($mark -match '\d') { 'ol' } else { 'ul' }
            if ($script:listOpen -ne $kind) { CloseList; [void]$h.Append("<$kind>"); $script:listOpen = $kind }
            [void]$h.Append('<li>' + (Inline $itemText) + '</li>'); $i++; continue }
        CloseList
        $para = @($l); $i++
        while ($i -lt $lines.Count -and $lines[$i] -notmatch '^\s*$' -and $lines[$i] -notmatch '^(#{1,4}\s|```|\s*\||\s*>|\s*([-*]|\d+\.)\s|---)') { $para += $lines[$i]; $i++ }
        [void]$h.Append('<p>' + (Inline ($para -join ' ')) + "</p>`n")
    }
    CloseList
    $nav = ('de', 'en', 'zh', 'ru' | ForEach-Object { $n = @{ de = 'Deutsch'; en = 'English'; zh = '中文'; ru = 'Русский' }[$_]; if ($_ -eq $code) { "<span class=`"cur`">$n</span>" } else { "<a href=`"guide.$_.html`">$n</a>" } }) -join ' · '
    $css = 'body{margin:0;font:16px/1.6 "Segoe UI",system-ui,sans-serif;background:#f3f6fa;color:#13253a}main{max-width:960px;margin:0 auto;padding:24px 28px 80px}nav{position:sticky;top:0;background:#fff;border-bottom:1px solid #d0dce8;padding:10px 28px;text-align:right}nav a,a{color:#a85f00}nav .cur{font-weight:700}h1{font-size:30px;margin:.4em 0}h2{margin-top:2em;border-bottom:2px solid #d0dce8;padding-bottom:.2em}h3{margin-top:1.6em}img{max-width:100%;height:auto;border:1px solid #d0dce8;border-radius:12px;margin:10px 0;box-shadow:0 4px 18px #0002}code{background:#e9f0f7;padding:1px 6px;border-radius:5px;font-family:Consolas,monospace;font-size:.92em}pre{background:#0b1b2b;color:#e8eef4;padding:14px 16px;border-radius:10px;overflow:auto}pre code{background:none;color:inherit;padding:0}blockquote{margin:1em 0;padding:.6em 1em;border-left:4px solid #c77700;background:#fff7e8;border-radius:0 8px 8px 0}.tw{overflow-x:auto}table{border-collapse:collapse;margin:1em 0;background:#fff}th,td{border:1px solid #d0dce8;padding:6px 12px;text-align:left;vertical-align:top}th{background:#e9f0f7}hr{border:0;border-top:1px solid #d0dce8;margin:2em 0}@media(prefers-color-scheme:dark){body{background:#0b1b2b;color:#e8eef4}nav{background:#12293f;border-color:#27445f}h2,th,td,hr,img{border-color:#27445f}a,nav a{color:#f2a93b}code{background:#1a3652}table{background:#12293f}th{background:#1a3652}blockquote{background:#1a2a1f33;border-color:#f2a93b}}'
    return "<!doctype html>`n<html lang=`"$lang`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width,initial-scale=1`"><title>$(Esc $title)</title><style>$css</style></head><body><nav>$nav</nav><main>`n$($h.ToString())</main></body></html>`n"
}
$docsDir = Join-Path $root 'docs'
if (Test-Path (Join-Path $root 'README.md')) {
    New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
    foreach ($pair in @(@('de', 'README.md'), @('en', 'README.en.md'), @('zh', 'README.zh.md'), @('ru', 'README.ru.md'))) {
        $mdFile = Join-Path $root $pair[1]
        if (Test-Path $mdFile) { [IO.File]::WriteAllText((Join-Path $docsDir "guide.$($pair[0]).html"), (ConvertTo-GuideHtml ([IO.File]::ReadAllText($mdFile, [Text.Encoding]::UTF8)) $pair[0] $pair[0]), (New-Object Text.UTF8Encoding($false))) }
    }
}
# Alte Ausgaben (ohne Version oder frühere Versionen) entfernen – es gibt immer genau eine Datei je Variante
foreach ($f in @(Get-ChildItem $root -File | Where-Object { $_.Name -match '^rf4sa-backup(-gui)?(-v[\d\.]+)?\.(ps1|sh)$' })) { if ($f.Name -notmatch [regex]::Escape("-v$ver.")) { [IO.File]::Delete($f.FullName) } }
Write-Host "Gebaut: v$ver"
