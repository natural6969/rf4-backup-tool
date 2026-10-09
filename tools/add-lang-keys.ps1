#Requires -Version 5.1
# Hilfsskript: hängt neue Schlüssel an alle vier eingebauten Sprachdateien an (Zeilen: key|de|en|zh|ru).
# Aufruf: .\add-lang-keys.ps1 -File <textdatei mit Zeilen>
param([Parameter(Mandatory)][string]$File)
$root = Split-Path $PSScriptRoot -Parent
$enc = New-Object Text.UTF8Encoding($false); $idx = @{ de = 1; en = 2; zh = 3; ru = 4 }
$rows = [IO.File]::ReadAllLines($File, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() }
foreach ($l in 'de', 'en', 'zh', 'ru') {
    $p = Join-Path $root "src\lang\$l.lang"
    $cc = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8).TrimEnd("`n")
    foreach ($r in $rows) {
        $q = $r.Split('|'); if ($q.Count -ne 5) { throw "Spalten: $r" }
        $k = $q[0]; $cc = [regex]::Replace($cc, "(?m)^$([regex]::Escape($k))=.*\r?\n?", '')   # vorhandenen Schlüssel ersetzen
        $cc = $cc.TrimEnd("`n") + "`n$k=$($q[$idx[$l]])"
    }
    [IO.File]::WriteAllText($p, $cc + "`n", $enc)
}
Write-Host "$($rows.Count) Schlüssel in 4 Sprachen eingetragen."
