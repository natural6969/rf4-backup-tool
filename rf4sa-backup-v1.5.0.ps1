#Requires -Version 5.1
<#
.SYNOPSIS
    RF4 Backup & Migration Tool – Terminal
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
# Version 1.5.0 – 2026-10-09
param([string]$Lang = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
$script:EmbeddedData = @'
@@FILE lang/de.lang
# RF4 Backup Tool - Sprachdatei / language file / 语言文件 / файл языка
# Format: key=Text   ({0} {1} ... = Platzhalter). Fehlende Schlüssel fallen auf Englisch zurück.
@code=de
@name=Deutsch

acct_line=Account {0}  ({1} Konversationen)
act_backup=Backup erstellen
act_backup_d=RF4-Daten (Chats, Einstellungen, Screenshots) in einen Ordner sichern.
act_merge=Installationen zusammenführen
act_merge_d=Nachrichten aus anderen Installationen ergänzen – nichts wird überschrieben.
act_restore=Backup wiederherstellen
act_restore_d=Gesicherte Daten in eine RF4-Installation importieren. Nachrichten werden zusammengeführt.
act_sync=Cloud / NAS Sync
act_sync_d=Mailboxen zwischen PC, Laptop und NAS abgleichen (Nextcloud, Syncthing, Netzlaufwerk, USB).
all_accts=Alle Accounts ({0})
app_title=RF4 Backup & Migration
back=Zurück
backup_dir=Backup-Ordner
backup_dir_p=Backup-Ordner [{0}] (Enter = Standard)
backup_done=Backup fertig: {0}
bk_mailbox={0}: {1} Konversationen
bk_shots=Screenshots: {0} Dateien
btn_browse=Durchsuchen…
btn_close=Schließen
btn_home=Zum Start
btn_open=Ordner öffnen
cancelled=Abgebrochen.
choose=Auswahl
contents=Inhalt:
continue=[Enter] zum Fortfahren
donate=Spenden: paypal.me/bjoernoppermann
enter_path=Pfad eingeben
exit=Beenden
f_copied={0} kopiert
f_failed={0} fehlgeschlagen: {1}
f_identical={0} identisch, nichts zu tun
f_missing={0} nicht gefunden
f_overwritten={0} überschrieben
f_skipped={0} übersprungen
folder_missing=Ordner nicht gefunden: {0}
found_n=Gefunden: {0} Installation(en)
from=Von: {0}
hash_click=(Klicken zum Kopieren)
hash_copied=SHA256-Prüfsumme kopiert:
hash_label=SHA256: {0}…
hash_unknown=SHA256: (Pfad unbekannt)
hdr_backup=BACKUP
hdr_merge=INSTALLATIONEN MERGEN
hdr_restore=RESTORE / IMPORT
hdr_scan=INSTALLATIONEN SCANNEN
hdr_sync=CLOUD / NAS SYNC
importing_to=Importiere nach: {0}
invalid=Ungültige Eingabe
item_Crafting.dat=Crafting.dat
item_mail=Mailboxen (private Nachrichten)
item_Preferences.dat=Preferences.dat
item_Settings.dat=Settings.dat (Grafik/Audio/Tasten)
item_shots=Screenshots
lang_changed=Sprache geändert.
lang_prompt=Sprache wählen
language=Sprache
manual_path=→ Pfad manuell eingeben
mb_header=Mailbox {0}…
mb_merge_fail=Merge fehlgeschlagen: {0} – {1}
mb_merge_file=Merge {0}: +{1} Nachrichten
mb_summary=Mailbox: {0} gemergt, {1} neu kopiert, {2} unverändert
menu_backup=Backup – Daten sichern
menu_lang=Sprache wechseln
menu_merge=Merge – Installationen zusammenführen
menu_restore=Restore – Aus Backup importieren
menu_scan=Scan – Alle Installationen anzeigen
menu_sync=Sync – Mit Cloud/NAS abgleichen
merge_done=Merge abgeschlossen.
merge_dst=Ziel (Hauptinstallation, bleibt erhalten)
merge_need2=Mindestens 2 vorhandene Installationen nötig.
merge_nosrc=Keine weiteren Installationen als Quellen verfügbar.
merge_note=RF4 erlaubt nur den Wechsel Steam → Standalone, nicht umgekehrt. Details: https://nga.li/rf4transfer
merge_safe=Nur fehlende Nachrichten werden ergänzt. Vorhandene Daten werden nicht überschrieben.
merge_same=Quelle und Ziel dürfen nicht identisch sein.
merge_src=Quellen (mehrere möglich)
merge_src_ctrl=Quellen (Strg+Klick = Mehrfachauswahl)
merge_src_hdr=Quelle: {0}
need_python=python3 wird für das Zusammenführen der Nachrichten benötigt (Debian/Ubuntu: sudo apt install python3).
next=Weiter
no_backup_here=Kein RF4-Backup in diesem Ordner gefunden.
no_inst=Keine Installationen gefunden.
no_mailboxes=Keine Mailboxen gefunden.
no_path=Kein Pfad angegeben.
none_found=Keine Installationen gefunden.
nothing_sel=Nichts ausgewählt.
pick_action=Bitte eine Aktion wählen.
pick_backup=Backup-Ordner wählen
pick_backup_d=Wähle den Ordner, der dein RF4-Backup enthält.
pick_dst=Bitte Ziel-Installation wählen.
pick_item=Bitte mindestens eine Option wählen.
pick_one_src=Bitte mindestens eine Quelle wählen.
pick_source=Quelle wählen – von welcher Installation sichern?
pick_src=Bitte eine Quelle wählen.
pick_target=Ziel-Installation
restore_done=Import abgeschlossen.
result_title=Fertig
run_backup=Backup starten
run_merge=Merge starten
run_restore=Restore starten
running_ask=Trotzdem fortfahren?
running_warn=RF4 scheint zu laufen ({0}). Bitte das Spiel VOR Restore/Merge/Sync beenden, sonst werden Änderungen überschrieben.
scan_accounts=Account-IDs: {0}
scan_empty=(noch nicht vorhanden)
scan_path=Pfad: {0}
scan_readonly=Sicher: Das Tool liest nur – Originaldaten werden nicht verändert.
scan_stats=Mailboxen: {0}  Konversationen: {1}
scan_total=Gesamt: {0} Pfade geprüft
scanning=Suche auf allen Laufwerken…
shots_done=Screenshots: {0} Bilder → {1}
shots_none=Screenshot-Ordner nicht gefunden
step1=Scan
step2=Aktion
step3=Auswahl
step4=Ausführen
step5=Ergebnis
sync_cfg=Sync-Ordner konfigurieren
sync_dir_lbl=Sync-Ordner:
sync_done=Sync abgeschlossen!
sync_down={0} ← Sync (heruntergeladen)
sync_down_new={0} ← Sync (Sync neuer)
sync_enter=Sync-Ordner eingeben (z.B. N:\RF4-Sync, D:\RF4-Sync):
sync_first=Bitte zuerst den Sync-Ordner konfigurieren.
sync_hint=Nextcloud-Ordner · NAS-Netzlaufwerk (N:\) · Syncthing-Ordner · USB-Stick
sync_inst_lbl=Installation:
sync_intro=Ordnerbasierter Sync – Nextcloud, NAS-Laufwerk, Syncthing, USB, OneDrive.
sync_local=Lokal:  {0}
sync_mkfail=Ordner konnte nicht erstellt werden: {0}
sync_nolocal=Keine lokalen Mailboxen – nur Download wird ausgeführt.
sync_none=Kein Sync-Ordner konfiguriert.
sync_noremote=Der Sync-Ordner enthält noch keine Mailboxen anderer Geräte.
sync_ok=Sync-Ordner: {0}
sync_p1=Phase 1: Lokal → Sync (neue Nachrichten hochladen)
sync_p2=Phase 2: Sync → Lokal (neue Nachrichten herunterladen)
sync_p3=Einstellungen (neuere Version gewinnt)
sync_pick_dir=Sync-Ordner wählen (z.B. Nextcloud-Ordner oder NAS-Laufwerk)
sync_remote=Sync:   {0}
sync_run=Sync jetzt ausführen (bidirektional)
sync_same={0}: identisch, übersprungen
sync_saved=Gespeichert: {0}
sync_st_boxes={0}: {1} Konversationen
sync_st_log=Letzte Sync-Einträge:
sync_st_nodir=Noch kein RF4_Sync-Unterordner. Bitte zuerst einen Sync ausführen.
sync_st_none=Noch keine Mailboxen im Sync-Ordner.
sync_status=Sync-Status anzeigen
sync_unreach=Sync-Ordner nicht erreichbar: {0}
sync_unreach_h=NAS eingebunden? Cloud-Sync aktiv? USB angesteckt?
sync_up={0} → Sync (hochgeladen)
sync_up_new={0} → Sync (lokal neuer)
sync_which=Welche Installation synchronisieren?
to=Nach: {0}
toggle_hint=(Nummer = ein/aus, a = alle, n = keine, Enter = OK, 0 = Zurück)
undo_saved=Ersetzte Dateien gesichert in: {0}
usage=Aufruf: rf4sa-backup.sh [-l de|en|zh|ru]
v_DE=RF4 Standalone Deutsch
v_DE_new=RF4 Standalone Deutsch (neu)
v_EN=RF4 Standalone Englisch
v_Other=RF4 ({0})
v_Steam=RF4 Steam
w_drive=Laufwerk: {0} / {1}
w_extra=Pfad: {0}
w_proton=Proton: AppID {0}
w_user=Benutzer: {0}
w_win=Windows: {0} / {1}
w_wine=Wine: {0}
what_backup=Was soll gesichert werden?
what_restore=Was soll importiert werden?
what_todo=Was möchtest du tun?
which_acct_b=Welchen Account sichern?
which_acct_m=Welche Accounts aus dieser Quelle mergen?
which_acct_r=Welchen Account importieren?
working=Bitte warten…
yes_char=j
yn_overwrite={0} existiert bereits. Überschreiben? [j/N]

# --- GUI / Backups / Ergebnis ---
overwrite_q={0} existiert bereits.{1}Überschreiben?
sel_account=Account:
scan_hint=Das Tool sucht automatisch auf allen Laufwerken nach RF4-Installationen.
rescan=Neu suchen
target_none=Keine passende Ziel-Installation vorhanden.
backup_to=Backup-Zielordner
preview=Inhalt des Backups:
undo_hint=Ersetzte Dateien werden vorher nach _rf4tool_undo kopiert.
theme_label=Design
theme_auto=Automatisch (wie Windows)
tip_lang=Sprache ändern
tip_theme=Design ändern
bk_mailbox_n={0} Mailboxen · {1} Konversationen
bk_files_n=Einstellungsdateien: {0}
bk_shots_n=Screenshots: {0}
existing_backups=Vorhandene Backups
no_existing_backups=Noch keine Backups gefunden – wähle einen Ordner.
other_folder=Anderen Ordner wählen…
last_change=Zuletzt geändert: {0}
chip_found=vorhanden
chip_missing=nicht vorhanden
convs_short=Konversationen
sum_msgs=Nachrichten übertragen
sum_convs=Konversationen
sum_files=Dateien kopiert
sum_shots=Screenshots
sum_skipped=übersprungen
sum_failed=Fehler
show_details=Details anzeigen
hide_details=Details ausblenden
res_ok=Fertig – ohne Fehler.
res_err=Abgeschlossen, aber mit {0} Fehler(n). Details ansehen.
working_title=Bitte nicht schließen – das kann einen Moment dauern.
btn_done=Fertig
btn_start_over=Neue Aktion
hdr_scan_t=Installationen
hdr_action_t=Was möchtest du tun?
hdr_backup_t=Backup erstellen
hdr_restore_t=Backup wiederherstellen
hdr_merge_t=Installationen zusammenführen
hdr_sync_t=Cloud / NAS Sync
to_target=Ziel
no_backup_found_cli=Keine Backups in den üblichen Ordnern – Pfad eingeben.
pick_backup_list=Backup wählen
theme_name_dark=Dunkel (Marine)
theme_name_light=Hell
open_folder_tip=Öffnet den Ordner im Explorer
accounts_all=Alle Accounts
tip_card_select=Zum Auswählen anklicken
select_backup_first=Bitte zuerst ein Backup wählen.
sync_run_btn=Sync starten
sync_status_btn=Status anzeigen
dialog_yes=Ja
dialog_no=Nein
dialog_ok=OK
err_unexpected=Ein unerwarteter Fehler ist aufgetreten. Das Programm läuft weiter, es wurde nichts gelöscht.
err_logged=Details: {0}
bk_source=Quelle: {0}
bk_source_unknown=Quelle: unbekannt (Backup ohne Info-Datei)
bk_from_pc=(PC {0})
bk_dates=Erstellt: {0}   ·   Aktualisiert: {1}
bk_existing_here=Hier liegt schon ein Backup. {0}
bk_source_sync=Quelle: gemeinsamer Sync-Ordner – zuletzt abgeglichen von PC {0} am {1}
bk_source_sync_unknown=Quelle: gemeinsamer Sync-Ordner (noch keine Sync-Einträge)
bk_sync_hint=Gemeinsamer Ordner aller Geräte – Restore holt den abgeglichenen Stand von dort.
bk_badge_sync=Sync
menu_help=Hilfe / Anleitung
help_btn=Hilfe
tip_help=Anleitung mit Screenshots in deiner Sprache öffnen
restore_path_bad=Dort wurde kein Backup gefunden (auch nicht im Unterordner RF4_Sync). Ordner nicht erreichbar?
@@FILE lang/en.lang
# RF4 Backup Tool - Sprachdatei / language file / 语言文件 / файл языка
# Format: key=Text   ({0} {1} ... = Platzhalter). Fehlende Schlüssel fallen auf Englisch zurück.
@code=en
@name=English

acct_line=Account {0}  ({1} conversations)
act_backup=Create backup
act_backup_d=Save RF4 data (chats, settings, screenshots) to a folder.
act_merge=Merge installations
act_merge_d=Add messages from other installations – nothing is overwritten.
act_restore=Restore backup
act_restore_d=Import saved data into an RF4 installation. Messages are merged.
act_sync=Cloud / NAS sync
act_sync_d=Sync mailboxes between PC, laptop and NAS (Nextcloud, Syncthing, network drive, USB).
all_accts=All accounts ({0})
app_title=RF4 Backup & Migration
back=Back
backup_dir=Backup folder
backup_dir_p=Backup folder [{0}] (Enter = default)
backup_done=Backup finished: {0}
bk_mailbox={0}: {1} conversations
bk_shots=Screenshots: {0} files
btn_browse=Browse…
btn_close=Close
btn_home=Back to start
btn_open=Open folder
cancelled=Cancelled.
choose=Choice
contents=Contents:
continue=[Enter] to continue
donate=Donate: paypal.me/bjoernoppermann
enter_path=Enter path
exit=Exit
f_copied={0} copied
f_failed={0} failed: {1}
f_identical={0} identical, nothing to do
f_missing={0} not found
f_overwritten={0} overwritten
f_skipped={0} skipped
folder_missing=Folder not found: {0}
found_n=Found: {0} installation(s)
from=From: {0}
hash_click=(click to copy)
hash_copied=SHA256 checksum copied:
hash_label=SHA256: {0}…
hash_unknown=SHA256: (path unknown)
hdr_backup=BACKUP
hdr_merge=MERGE INSTALLATIONS
hdr_restore=RESTORE / IMPORT
hdr_scan=SCAN INSTALLATIONS
hdr_sync=CLOUD / NAS SYNC
importing_to=Importing to: {0}
invalid=Invalid input
item_Crafting.dat=Crafting.dat
item_mail=Mailboxes (private messages)
item_Preferences.dat=Preferences.dat
item_Settings.dat=Settings.dat (graphics/audio/keys)
item_shots=Screenshots
lang_changed=Language changed.
lang_prompt=Choose language
language=Language
manual_path=→ Enter path manually
mb_header=Mailbox {0}…
mb_merge_fail=Merge failed: {0} – {1}
mb_merge_file=Merge {0}: +{1} messages
mb_summary=Mailbox: {0} merged, {1} newly copied, {2} unchanged
menu_backup=Backup – Save data to a folder
menu_lang=Change language
menu_merge=Merge – Combine installations
menu_restore=Restore – Import from a backup
menu_scan=Scan – Show all installations
menu_sync=Sync – Synchronize with cloud/NAS
merge_done=Merge finished.
merge_dst=Target (main installation, is kept)
merge_need2=At least 2 existing installations are required.
merge_nosrc=No other installations available as sources.
merge_note=RF4 only allows switching Steam → Standalone, not the other way round. Details: https://nga.li/rf4transfer
merge_safe=Only missing messages are added. Existing data is not overwritten.
merge_same=Source and target must not be the same.
merge_src=Sources (multiple allowed)
merge_src_ctrl=Sources (Ctrl+click = multi-select)
merge_src_hdr=Source: {0}
need_python=python3 is required to merge messages (Debian/Ubuntu: sudo apt install python3).
next=Next
no_backup_here=No RF4 backup found in this folder.
no_inst=No installations found.
no_mailboxes=No mailboxes found.
no_path=No path given.
none_found=No installations found.
nothing_sel=Nothing selected.
pick_action=Please select an action.
pick_backup=Choose backup folder
pick_backup_d=Choose the folder that contains your RF4 backup.
pick_dst=Please select a target installation.
pick_item=Please select at least one option.
pick_one_src=Please select at least one source.
pick_source=Choose source – back up which installation?
pick_src=Please select a source.
pick_target=Target installation
restore_done=Import finished.
result_title=Done
run_backup=Start backup
run_merge=Start merge
run_restore=Start restore
running_ask=Continue anyway?
running_warn=RF4 seems to be running ({0}). Please close the game BEFORE restore/merge/sync, otherwise changes get overwritten.
scan_accounts=Account IDs: {0}
scan_empty=(not present yet)
scan_path=Path: {0}
scan_readonly=Safe: the tool only reads – original data is not modified.
scan_stats=Mailboxes: {0}  Conversations: {1}
scan_total=Total: {0} paths checked
scanning=Searching all drives…
shots_done=Screenshots: {0} images → {1}
shots_none=Screenshot folder not found
step1=Scan
step2=Action
step3=Selection
step4=Run
step5=Result
sync_cfg=Configure sync folder
sync_dir_lbl=Sync folder:
sync_done=Sync finished!
sync_down={0} ← sync (downloaded)
sync_down_new={0} ← sync (sync is newer)
sync_enter=Enter sync folder (e.g. N:\RF4-Sync, D:\RF4-Sync):
sync_first=Please configure the sync folder first.
sync_hint=Nextcloud folder · NAS network drive (N:\) · Syncthing folder · USB stick
sync_inst_lbl=Installation:
sync_intro=Folder-based sync – Nextcloud, NAS drive, Syncthing, USB, OneDrive.
sync_local=Local:  {0}
sync_mkfail=Folder could not be created: {0}
sync_nolocal=No local mailboxes – download only.
sync_none=No sync folder configured.
sync_noremote=The sync folder has no mailboxes from other devices yet.
sync_ok=Sync folder: {0}
sync_p1=Phase 1: local → sync (upload new messages)
sync_p2=Phase 2: sync → local (download new messages)
sync_p3=Settings (newer version wins)
sync_pick_dir=Choose sync folder (e.g. Nextcloud folder or NAS drive)
sync_remote=Sync:   {0}
sync_run=Run sync now (bidirectional)
sync_same={0}: identical, skipped
sync_saved=Saved: {0}
sync_st_boxes={0}: {1} conversations
sync_st_log=Recent sync entries:
sync_st_nodir=No RF4_Sync subfolder yet. Please run a sync first.
sync_st_none=No mailboxes in the sync folder yet.
sync_status=Show sync status
sync_unreach=Sync folder not reachable: {0}
sync_unreach_h=NAS mounted? Cloud sync running? USB plugged in?
sync_up={0} → sync (uploaded)
sync_up_new={0} → sync (local is newer)
sync_which=Which installation to sync?
to=To: {0}
toggle_hint=(number = toggle, a = all, n = none, Enter = OK, 0 = back)
undo_saved=Replaced files saved in: {0}
usage=Usage: rf4sa-backup.sh [-l de|en|zh|ru]
v_DE=RF4 Standalone German
v_DE_new=RF4 Standalone German (new)
v_EN=RF4 Standalone English
v_Other=RF4 ({0})
v_Steam=RF4 Steam
w_drive=Drive: {0} / {1}
w_extra=Path: {0}
w_proton=Proton: AppID {0}
w_user=User: {0}
w_win=Windows: {0} / {1}
w_wine=Wine: {0}
what_backup=What should be backed up?
what_restore=What should be imported?
what_todo=What would you like to do?
which_acct_b=Which account to back up?
which_acct_m=Which accounts to merge from this source?
which_acct_r=Which account to import?
working=Please wait…
yes_char=y
yn_overwrite={0} already exists. Overwrite? [y/N]

# --- GUI / Backups / Ergebnis ---
overwrite_q={0} already exists.{1}Overwrite?
sel_account=Account:
scan_hint=The tool automatically searches all drives for RF4 installations.
rescan=Rescan
target_none=No suitable target installation available.
backup_to=Backup target folder
preview=Backup contents:
undo_hint=Files that get replaced are copied to _rf4tool_undo first.
theme_label=Theme
theme_auto=Automatic (like Windows)
tip_lang=Change language
tip_theme=Change theme
bk_mailbox_n={0} mailboxes · {1} conversations
bk_files_n=settings files: {0}
bk_shots_n=screenshots: {0}
existing_backups=Existing backups
no_existing_backups=No backups found yet – choose a folder.
other_folder=Choose another folder…
last_change=Last changed: {0}
chip_found=found
chip_missing=not present
convs_short=conversations
sum_msgs=messages transferred
sum_convs=conversations
sum_files=files copied
sum_shots=screenshots
sum_skipped=skipped
sum_failed=errors
show_details=Show details
hide_details=Hide details
res_ok=Done – no errors.
res_err=Finished, but with {0} error(s). See details.
working_title=Please do not close – this may take a moment.
btn_done=Done
btn_start_over=New action
hdr_scan_t=Installations
hdr_action_t=What would you like to do?
hdr_backup_t=Create backup
hdr_restore_t=Restore backup
hdr_merge_t=Merge installations
hdr_sync_t=Cloud / NAS sync
to_target=Target
no_backup_found_cli=No backups in the usual folders – enter a path.
pick_backup_list=Choose a backup
theme_name_dark=Dark (navy)
theme_name_light=Light
open_folder_tip=Opens the folder in Explorer
accounts_all=All accounts
tip_card_select=Click to select
select_backup_first=Please choose a backup first.
sync_run_btn=Start sync
sync_status_btn=Show status
dialog_yes=Yes
dialog_no=No
dialog_ok=OK
err_unexpected=An unexpected error occurred. The program keeps running; nothing was deleted.
err_logged=Details: {0}
bk_source=Source: {0}
bk_source_unknown=Source: unknown (backup without info file)
bk_from_pc=(PC {0})
bk_dates=Created: {0}   ·   Updated: {1}
bk_existing_here=There is already a backup here. {0}
bk_source_sync=Source: shared sync folder – last synced by PC {0} on {1}
bk_source_sync_unknown=Source: shared sync folder (no sync entries yet)
bk_sync_hint=Shared folder of all devices – restore pulls the synced state from here.
bk_badge_sync=Sync
menu_help=Help / guide
help_btn=Help
tip_help=Open the guide with screenshots in your language
restore_path_bad=No backup found there (not in a RF4_Sync subfolder either). Folder not reachable?
@@FILE lang/ru.lang
# RF4 Backup Tool - Sprachdatei / language file / 语言文件 / файл языка
# Format: key=Text   ({0} {1} ... = Platzhalter). Fehlende Schlüssel fallen auf Englisch zurück.
@code=ru
@name=Русский

acct_line=Аккаунт {0}  (диалогов: {1})
act_backup=Создать резервную копию
act_backup_d=Сохранить данные RF4 (чаты, настройки, скриншоты) в папку.
act_merge=Объединить установки
act_merge_d=Добавить сообщения из других установок — ничего не перезаписывается.
act_restore=Восстановить из копии
act_restore_d=Импортировать сохранённые данные в установку RF4. Сообщения объединяются.
act_sync=Синхронизация облако / NAS
act_sync_d=Синхронизация почты между ПК, ноутбуком и NAS (Nextcloud, Syncthing, сетевой диск, USB).
all_accts=Все аккаунты ({0})
app_title=RF4 Резервное копирование и перенос
back=Назад
backup_dir=Папка резервной копии
backup_dir_p=Папка копии [{0}] (Enter = по умолчанию)
backup_done=Резервная копия готова: {0}
bk_mailbox={0}: диалогов {1}
bk_shots=Скриншоты: файлов {0}
btn_browse=Обзор…
btn_close=Закрыть
btn_home=В начало
btn_open=Открыть папку
cancelled=Отменено.
choose=Выбор
contents=Содержимое:
continue=[Enter] — продолжить
donate=Поддержать: paypal.me/bjoernoppermann
enter_path=Введите путь
exit=Выход
f_copied={0} скопирован
f_failed={0}: ошибка: {1}
f_identical={0} идентичен, ничего не делаем
f_missing={0} не найден
f_overwritten={0} перезаписан
f_skipped={0} пропущен
folder_missing=Папка не найдена: {0}
found_n=Найдено установок: {0}
from=Откуда: {0}
hash_click=(нажмите, чтобы скопировать)
hash_copied=Контрольная сумма SHA256 скопирована:
hash_label=SHA256: {0}…
hash_unknown=SHA256: (путь неизвестен)
hdr_backup=РЕЗЕРВНАЯ КОПИЯ
hdr_merge=ОБЪЕДИНЕНИЕ УСТАНОВОК
hdr_restore=ВОССТАНОВЛЕНИЕ / ИМПОРТ
hdr_scan=ПОИСК УСТАНОВОК
hdr_sync=СИНХРОНИЗАЦИЯ ОБЛАКО / NAS
importing_to=Импорт в: {0}
invalid=Неверный ввод
item_Crafting.dat=Crafting.dat
item_mail=Почтовые ящики (личные сообщения)
item_Preferences.dat=Preferences.dat
item_Settings.dat=Settings.dat (графика/звук/клавиши)
item_shots=Скриншоты
lang_changed=Язык изменён.
lang_prompt=Выберите язык
language=Язык
manual_path=→ Ввести путь вручную
mb_header=Ящик {0}…
mb_merge_fail=Ошибка слияния: {0} – {1}
mb_merge_file=Слияние {0}: +{1} сообщ.
mb_summary=Ящик: слито {0}, скопировано новых {1}, без изменений {2}
menu_backup=Резервная копия – сохранить данные в папку
menu_lang=Сменить язык
menu_merge=Объединить – слить установки
menu_restore=Восстановить – импорт из резервной копии
menu_scan=Сканировать – показать все установки
menu_sync=Синхронизация – облако/NAS
merge_done=Объединение завершено.
merge_dst=Цель (основная установка, сохраняется)
merge_need2=Нужно минимум 2 существующие установки.
merge_nosrc=Нет других установок в качестве источников.
merge_note=RF4 позволяет переходить только Steam → Standalone, но не наоборот. Подробнее: https://nga.li/rf4transfer
merge_safe=Добавляются только недостающие сообщения. Существующие данные не перезаписываются.
merge_same=Источник и цель не должны совпадать.
merge_src=Источники (можно несколько)
merge_src_ctrl=Источники (Ctrl+клик = несколько)
merge_src_hdr=Источник: {0}
need_python=Для объединения сообщений нужен python3 (Debian/Ubuntu: sudo apt install python3).
next=Далее
no_backup_here=В этой папке нет резервной копии RF4.
no_inst=Установки не найдены.
no_mailboxes=Почтовые ящики не найдены.
no_path=Путь не указан.
none_found=Установки не найдены.
nothing_sel=Ничего не выбрано.
pick_action=Выберите действие.
pick_backup=Выберите папку резервной копии
pick_backup_d=Выберите папку с вашей резервной копией RF4.
pick_dst=Выберите целевую установку.
pick_item=Выберите хотя бы один пункт.
pick_one_src=Выберите хотя бы один источник.
pick_source=Выберите источник — какую установку копировать?
pick_src=Выберите источник.
pick_target=Целевая установка
restore_done=Импорт завершён.
result_title=Готово
run_backup=Начать копирование
run_merge=Начать объединение
run_restore=Начать восстановление
running_ask=Всё равно продолжить?
running_warn=RF4, похоже, запущена ({0}). Закройте игру ПЕРЕД восстановлением/объединением/синхронизацией, иначе изменения будут перезаписаны.
scan_accounts=ID аккаунтов: {0}
scan_empty=(пока отсутствует)
scan_path=Путь: {0}
scan_readonly=Безопасно: программа только читает — исходные данные не меняются.
scan_stats=Ящиков: {0}  Диалогов: {1}
scan_total=Всего проверено путей: {0}
scanning=Поиск на всех дисках…
shots_done=Скриншоты: {0} изобр. → {1}
shots_none=Папка скриншотов не найдена
step1=Поиск
step2=Действие
step3=Выбор
step4=Запуск
step5=Итог
sync_cfg=Настроить папку синхронизации
sync_dir_lbl=Папка синхронизации:
sync_done=Синхронизация завершена!
sync_down={0} ← синхр. (скачано)
sync_down_new={0} ← синхр. (в синхр. новее)
sync_enter=Введите папку синхронизации (напр. N:\RF4-Sync, D:\RF4-Sync):
sync_first=Сначала настройте папку синхронизации.
sync_hint=Папка Nextcloud · сетевой диск NAS (N:\) · папка Syncthing · USB-накопитель
sync_inst_lbl=Установка:
sync_intro=Синхронизация через папку — Nextcloud, NAS, Syncthing, USB, OneDrive.
sync_local=Локально:  {0}
sync_mkfail=Не удалось создать папку: {0}
sync_nolocal=Локальных ящиков нет — только загрузка.
sync_none=Папка синхронизации не настроена.
sync_noremote=В папке синхронизации ещё нет ящиков с других устройств.
sync_ok=Папка синхронизации: {0}
sync_p1=Этап 1: локально → синхр. (загрузка новых сообщений)
sync_p2=Этап 2: синхр. → локально (скачивание новых сообщений)
sync_p3=Настройки (побеждает более новая версия)
sync_pick_dir=Выберите папку синхронизации (напр. Nextcloud или диск NAS)
sync_remote=Синхр.:   {0}
sync_run=Синхронизировать сейчас (двусторонне)
sync_same={0}: одинаковы, пропущено
sync_saved=Сохранено: {0}
sync_st_boxes={0}: диалогов {1}
sync_st_log=Последние записи синхронизации:
sync_st_nodir=Подпапки RF4_Sync ещё нет. Сначала выполните синхронизацию.
sync_st_none=В папке синхронизации ещё нет ящиков.
sync_status=Показать состояние синхронизации
sync_unreach=Папка синхронизации недоступна: {0}
sync_unreach_h=NAS подключён? Облачная синхронизация активна? USB вставлен?
sync_up={0} → синхр. (загружено)
sync_up_new={0} → синхр. (локальный новее)
sync_which=Какую установку синхронизировать?
to=Куда: {0}
toggle_hint=(номер = вкл/выкл, a = все, n = ничего, Enter = ОК, 0 = назад)
undo_saved=Заменённые файлы сохранены в: {0}
usage=Использование: rf4sa-backup.sh [-l de|en|zh|ru]
v_DE=RF4 Standalone (немецкая)
v_DE_new=RF4 Standalone (немецкая, новая)
v_EN=RF4 Standalone (английская)
v_Other=RF4 ({0})
v_Steam=RF4 Steam
w_drive=Диск: {0} / {1}
w_extra=Путь: {0}
w_proton=Proton: AppID {0}
w_user=Пользователь: {0}
w_win=Windows: {0} / {1}
w_wine=Wine: {0}
what_backup=Что копировать?
what_restore=Что импортировать?
what_todo=Что вы хотите сделать?
which_acct_b=Какой аккаунт копировать?
which_acct_m=Какие аккаунты объединить из этого источника?
which_acct_r=Какой аккаунт импортировать?
working=Пожалуйста, подождите…
yes_char=д
yn_overwrite={0} уже существует. Перезаписать? [д/Н]

# --- GUI / Backups / Ergebnis ---
overwrite_q={0} уже существует.{1}Перезаписать?
sel_account=Аккаунт:
scan_hint=Программа автоматически ищет установки RF4 на всех дисках.
rescan=Искать заново
target_none=Подходящая целевая установка отсутствует.
backup_to=Папка для копии
preview=Содержимое копии:
undo_hint=Заменяемые файлы сначала копируются в _rf4tool_undo.
theme_label=Тема
theme_auto=Автоматически (как в Windows)
tip_lang=Сменить язык
tip_theme=Сменить тему
bk_mailbox_n=Ящиков: {0} · диалогов: {1}
bk_files_n=файлов настроек: {0}
bk_shots_n=скриншотов: {0}
existing_backups=Найденные резервные копии
no_existing_backups=Резервные копии не найдены — выберите папку.
other_folder=Выбрать другую папку…
last_change=Изменено: {0}
chip_found=найдено
chip_missing=нет
convs_short=диалогов
sum_msgs=сообщений перенесено
sum_convs=диалогов
sum_files=файлов скопировано
sum_shots=скриншотов
sum_skipped=пропущено
sum_failed=ошибок
show_details=Показать подробности
hide_details=Скрыть подробности
res_ok=Готово — без ошибок.
res_err=Завершено, но с ошибками: {0}. Смотрите подробности.
working_title=Не закрывайте — это может занять некоторое время.
btn_done=Готово
btn_start_over=Новое действие
hdr_scan_t=Установки
hdr_action_t=Что вы хотите сделать?
hdr_backup_t=Создать резервную копию
hdr_restore_t=Восстановить из копии
hdr_merge_t=Объединить установки
hdr_sync_t=Синхронизация облако / NAS
to_target=Цель
no_backup_found_cli=В обычных папках копий нет — введите путь.
pick_backup_list=Выберите резервную копию
theme_name_dark=Тёмная (морская)
theme_name_light=Светлая
open_folder_tip=Открывает папку в проводнике
accounts_all=Все аккаунты
tip_card_select=Нажмите, чтобы выбрать
select_backup_first=Сначала выберите резервную копию.
sync_run_btn=Начать синхронизацию
sync_status_btn=Показать состояние
dialog_yes=Да
dialog_no=Нет
dialog_ok=ОК
err_unexpected=Произошла непредвиденная ошибка. Программа продолжает работу, ничего не удалено.
err_logged=Подробности: {0}
bk_source=Источник: {0}
bk_source_unknown=Источник: неизвестен (копия без информационного файла)
bk_from_pc=(ПК {0})
bk_dates=Создана: {0}   ·   Обновлена: {1}
bk_existing_here=Здесь уже есть копия. {0}
bk_source_sync=Источник: общая папка синхронизации – последний раз синхронизировал ПК {0}, {1}
bk_source_sync_unknown=Источник: общая папка синхронизации (записей синхронизации пока нет)
bk_sync_hint=Общая папка всех устройств — восстановление берёт отсюда синхронизированное состояние.
bk_badge_sync=Sync
menu_help=Справка / руководство
help_btn=Справка
tip_help=Открыть руководство со скриншотами на вашем языке
restore_path_bad=Там не найдена резервная копия (в подпапке RF4_Sync тоже). Папка недоступна?
@@FILE lang/zh.lang
# RF4 Backup Tool - Sprachdatei / language file / 语言文件 / файл языка
# Format: key=Text   ({0} {1} ... = Platzhalter). Fehlende Schlüssel fallen auf Englisch zurück.
@code=zh
@name=中文

acct_line=账号 {0}  ({1} 个对话)
act_backup=创建备份
act_backup_d=将 RF4 数据（聊天、设置、截图）保存到文件夹。
act_merge=合并安装
act_merge_d=从其他安装补充消息——不会覆盖任何内容。
act_restore=恢复备份
act_restore_d=将已保存的数据导入 RF4 安装。消息会被合并。
act_sync=云 / NAS 同步
act_sync_d=在电脑、笔记本和 NAS 之间同步邮箱（Nextcloud、Syncthing、网络驱动器、USB）。
all_accts=所有账号 ({0})
app_title=RF4 备份与迁移
back=返回
backup_dir=备份文件夹
backup_dir_p=备份文件夹 [{0}]（Enter = 默认）
backup_done=备份完成: {0}
bk_mailbox={0}: {1} 个对话
bk_shots=截图: {0} 个文件
btn_browse=浏览…
btn_close=关闭
btn_home=返回开始
btn_open=打开文件夹
cancelled=已取消。
choose=选择
contents=内容:
continue=按 [Enter] 继续
donate=捐赠: paypal.me/bjoernoppermann
enter_path=输入路径
exit=退出
f_copied={0} 已复制
f_failed={0} 失败: {1}
f_identical={0} 相同，无需处理
f_missing=未找到 {0}
f_overwritten={0} 已覆盖
f_skipped={0} 已跳过
folder_missing=未找到文件夹: {0}
found_n=已找到：{0} 个安装
from=来源: {0}
hash_click=（点击复制）
hash_copied=SHA256 校验和已复制:
hash_label=SHA256: {0}…
hash_unknown=SHA256: （路径未知）
hdr_backup=备份
hdr_merge=合并安装
hdr_restore=恢复 / 导入
hdr_scan=扫描安装
hdr_sync=云 / NAS 同步
importing_to=正在导入到: {0}
invalid=输入无效
item_Crafting.dat=Crafting.dat
item_mail=邮箱（私人消息）
item_Preferences.dat=Preferences.dat
item_Settings.dat=Settings.dat（画面/音频/按键）
item_shots=截图
lang_changed=语言已更改。
lang_prompt=选择语言
language=语言
manual_path=→ 手动输入路径
mb_header=邮箱 {0}…
mb_merge_fail=合并失败: {0} – {1}
mb_merge_file=合并 {0}: +{1} 条消息
mb_summary=邮箱: {0} 个已合并, {1} 个新复制, {2} 个未变化
menu_backup=备份 – 将数据保存到文件夹
menu_lang=切换语言
menu_merge=合并 – 合并多个安装
menu_restore=恢复 – 从备份导入
menu_scan=扫描 – 显示所有安装
menu_sync=同步 – 与云/NAS同步
merge_done=合并完成。
merge_dst=目标（主安装，将保留）
merge_need2=至少需要 2 个现有安装。
merge_nosrc=没有其他可用作来源的安装。
merge_note=RF4 只允许从 Steam 切换到独立版，反之不行。详情: https://nga.li/rf4transfer
merge_safe=仅补充缺失的消息，不会覆盖现有数据。
merge_same=来源和目标不能相同。
merge_src=来源（可多选）
merge_src_ctrl=来源（Ctrl+点击 = 多选）
merge_src_hdr=来源: {0}
need_python=合并消息需要 python3（Debian/Ubuntu: sudo apt install python3）。
next=下一步
no_backup_here=该文件夹中没有 RF4 备份。
no_inst=未找到安装。
no_mailboxes=未找到邮箱。
no_path=未提供路径。
none_found=未找到安装。
nothing_sel=未选择任何内容。
pick_action=请选择一个操作。
pick_backup=选择备份文件夹
pick_backup_d=请选择包含 RF4 备份的文件夹。
pick_dst=请选择目标安装。
pick_item=请至少选择一项。
pick_one_src=请至少选择一个来源。
pick_source=选择来源——备份哪个安装？
pick_src=请选择来源。
pick_target=目标安装
restore_done=导入完成。
result_title=完成
run_backup=开始备份
run_merge=开始合并
run_restore=开始恢复
running_ask=仍要继续吗？
running_warn=检测到 RF4 正在运行 ({0})。请在恢复/合并/同步之前关闭游戏，否则更改会被覆盖。
scan_accounts=账号 ID: {0}
scan_empty=(尚不存在)
scan_path=路径: {0}
scan_readonly=安全：本工具只读取，不会修改原始数据。
scan_stats=邮箱: {0}  对话: {1}
scan_total=共检查 {0} 个路径
scanning=正在搜索所有驱动器…
shots_done=截图: {0} 张 → {1}
shots_none=未找到截图文件夹
step1=扫描
step2=操作
step3=选择
step4=执行
step5=结果
sync_cfg=配置同步文件夹
sync_dir_lbl=同步文件夹:
sync_done=同步完成！
sync_down={0} ← 同步（已下载）
sync_down_new={0} ← 同步（同步版较新）
sync_enter=输入同步文件夹（例如 N:\RF4-Sync, D:\RF4-Sync）:
sync_first=请先配置同步文件夹。
sync_hint=Nextcloud 文件夹 · NAS 网络驱动器 (N:\) · Syncthing 文件夹 · U 盘
sync_inst_lbl=安装:
sync_intro=基于文件夹的同步——Nextcloud、NAS 驱动器、Syncthing、USB、OneDrive。
sync_local=本地:  {0}
sync_mkfail=无法创建文件夹: {0}
sync_nolocal=没有本地邮箱——仅执行下载。
sync_none=尚未配置同步文件夹。
sync_noremote=同步文件夹中还没有来自其他设备的邮箱。
sync_ok=同步文件夹: {0}
sync_p1=阶段 1：本地 → 同步（上传新消息）
sync_p2=阶段 2：同步 → 本地（下载新消息）
sync_p3=设置（以较新版本为准）
sync_pick_dir=选择同步文件夹（例如 Nextcloud 文件夹或 NAS 驱动器）
sync_remote=同步:   {0}
sync_run=立即同步（双向）
sync_same={0}: 相同，已跳过
sync_saved=已保存: {0}
sync_st_boxes={0}: {1} 个对话
sync_st_log=最近的同步记录:
sync_st_nodir=还没有 RF4_Sync 子文件夹。请先执行一次同步。
sync_st_none=同步文件夹中还没有邮箱。
sync_status=显示同步状态
sync_unreach=无法访问同步文件夹: {0}
sync_unreach_h=NAS 已挂载？云同步已启动？U 盘已插入？
sync_up={0} → 同步（已上传）
sync_up_new={0} → 同步（本地较新）
sync_which=同步哪个安装？
to=目标: {0}
toggle_hint=(数字 = 切换, a = 全选, n = 全不选, Enter = 确定, 0 = 返回)
undo_saved=被替换的文件已保存到: {0}
usage=用法: rf4sa-backup.sh [-l de|en|zh|ru]
v_DE=RF4 独立版（德语）
v_DE_new=RF4 独立版（德语，新）
v_EN=RF4 独立版（英语）
v_Other=RF4 ({0})
v_Steam=RF4 Steam 版
w_drive=驱动器: {0} / {1}
w_extra=路径: {0}
w_proton=Proton: AppID {0}
w_user=用户: {0}
w_win=Windows: {0} / {1}
w_wine=Wine: {0}
what_backup=要备份什么？
what_restore=要导入什么？
what_todo=您想做什么？
which_acct_b=备份哪个账号？
which_acct_m=从该来源合并哪些账号？
which_acct_r=导入哪个账号？
working=请稍候…
yes_char=y
yn_overwrite={0} 已存在。是否覆盖？[y/N]

# --- GUI / Backups / Ergebnis ---
overwrite_q={0} 已存在。{1}是否覆盖？
sel_account=账号:
scan_hint=本工具会自动在所有驱动器上搜索 RF4 安装。
rescan=重新扫描
target_none=没有合适的目标安装。
backup_to=备份目标文件夹
preview=备份内容:
undo_hint=被替换的文件会先复制到 _rf4tool_undo。
theme_label=外观
theme_auto=自动（跟随 Windows）
tip_lang=切换语言
tip_theme=切换外观
bk_mailbox_n={0} 个邮箱 · {1} 个对话
bk_files_n=设置文件: {0}
bk_shots_n=截图: {0}
existing_backups=现有备份
no_existing_backups=尚未找到备份——请选择一个文件夹。
other_folder=选择其他文件夹…
last_change=最后修改: {0}
chip_found=已找到
chip_missing=不存在
convs_short=对话
sum_msgs=条消息已传输
sum_convs=个对话
sum_files=个文件已复制
sum_shots=张截图
sum_skipped=已跳过
sum_failed=个错误
show_details=显示详情
hide_details=隐藏详情
res_ok=完成——没有错误。
res_err=已完成，但有 {0} 个错误。请查看详情。
working_title=请勿关闭——这可能需要一点时间。
btn_done=完成
btn_start_over=新操作
hdr_scan_t=安装
hdr_action_t=您想做什么？
hdr_backup_t=创建备份
hdr_restore_t=恢复备份
hdr_merge_t=合并安装
hdr_sync_t=云 / NAS 同步
to_target=目标
no_backup_found_cli=常用文件夹中没有备份——请输入路径。
pick_backup_list=选择备份
theme_name_dark=深色（海军蓝）
theme_name_light=浅色
open_folder_tip=在资源管理器中打开文件夹
accounts_all=所有账号
tip_card_select=点击选择
select_backup_first=请先选择一个备份。
sync_run_btn=开始同步
sync_status_btn=显示状态
dialog_yes=是
dialog_no=否
dialog_ok=确定
err_unexpected=发生意外错误。程序继续运行，没有删除任何内容。
err_logged=详情: {0}
bk_source=来源: {0}
bk_source_unknown=来源: 未知（备份没有信息文件）
bk_from_pc=（电脑 {0}）
bk_dates=创建: {0}   ·   更新: {1}
bk_existing_here=此处已有备份。{0}
bk_source_sync=来源: 共享同步文件夹 – 最后由电脑 {0} 于 {1} 同步
bk_source_sync_unknown=来源: 共享同步文件夹（尚无同步记录）
bk_sync_hint=所有设备共用的文件夹——恢复会从这里取回已同步的内容。
bk_badge_sync=同步
menu_help=帮助 / 指南
help_btn=帮助
tip_help=用您的语言打开带截图的指南
restore_path_bad=在那里没有找到备份（RF4_Sync 子文件夹中也没有）。文件夹无法访问？
@@FILE themes/dark.theme
# RF4 Backup Tool - Theme. Eigene Themes: Datei in themes\ (neben dem Skript) oder %APPDATA%\rf4-backup\themes\ ablegen.
# @base = dark|light  (welcher Windows-Modus dieses Theme bei 'Automatisch' ersetzt)
@code=dark
@name=Marine / Navy
@base=dark
bg=#0B1B2B
surface=#12293F
surface2=#1A3652
border=#27445F
text=#E8EEF4
muted=#8FA6BC
accent=#F2A93B
accentHover=#FFBD5C
accentText=#1B1204
success=#3DD68C
warn=#F2C94C
danger=#FF6B6B
selection=#1F4469
@@FILE themes/light.theme
# RF4 Backup Tool - Theme (hell)
@code=light
@name=Hell / Light
@base=light
bg=#F3F6FA
surface=#FFFFFF
surface2=#E9F0F7
border=#D0DCE8
text=#13253A
muted=#5A7186
accent=#C77700
accentHover=#DB8A10
accentText=#1B1204
success=#1E9E62
warn=#B7791F
danger=#D64545
selection=#DCEAF8
'@

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
        Write-BackupInfo $dest $src $items
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
        $opts = @($bks | ForEach-Object { "$($_.Name)$(if ($_.IsSync) { "  [" + (T 'bk_badge_sync') + "]" })`n        $($_.Path)`n        $($_.SourceLabel)`n        $(Format-BackupInfo $_)`n        $(Format-BackupDates $_)" }) + @(T 'manual_path')
        $c = Show-Menu (T 'pick_backup_list') $opts
        if ($c -eq 0) { return }
        if ($c -le $bks.Count) { $src = $bks[$c - 1].Path }
    } else { Write-Warn (T 'no_backup_found_cli') }
    if (-not $src) {
        $src = Read-Host ('  ' + (T 'backup_dir_p' @($def)))
        if ([string]::IsNullOrWhiteSpace($src)) { $src = $def }
    }
    if (-not (Test-Path -LiteralPath $src)) { Write-Err (T 'folder_missing' @($src)); Pause-Menu; return }
    $rp = Resolve-BackupPath $src
    if (-not $rp) { Write-Err (T 'restore_path_bad'); Pause-Menu; return }
    $src = $rp
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
        Write-Host '   [H]' -ForegroundColor Yellow -NoNewline; Write-Host " $(T 'menu_help')"
        Write-Host '   [L]' -ForegroundColor Yellow -NoNewline; Write-Host " $(T 'menu_lang')  " -NoNewline; Write-Host "($($script:LangNames[$script:Lang]))" -ForegroundColor Cyan
        Write-Host '   [0]' -ForegroundColor Yellow -NoNewline; Write-Host " $(T 'exit')"
        Write-Host ''
        $raw = Read-Host "  $(T 'choose')"
        if ($null -eq $raw) { return }
        try {
            switch ($raw.Trim().ToLowerInvariant()) {
                '1' { Do-Scan } '2' { Do-Backup } '3' { Do-Restore } '4' { Do-Merge } '5' { Do-Sync }
                'l' { Do-Language }
                'h' { Open-Guide }
                '0' { return }
            }
        } catch { Write-Err $_.Exception.Message; Pause-Menu }
    }
}

if ($env:RF4_NO_MAIN -ne '1') { Show-Main }
