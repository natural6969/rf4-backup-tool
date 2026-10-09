#Requires -Version 5.1
<#
.SYNOPSIS
    RF4 Backup & Migration Tool – GUI
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
#  Grafische Oberfläche (Windows Forms, selbst gezeichnet, DPI-scharf, Dunkel/Hell automatisch)
#  Nutzt core.ps1 (Logik, Sprachen, Themes) und ui.cs (Bausteine).
# ══════════════════════════════════════════════════════════════════════════════
# WinForms braucht einen STA-Thread (Windows PowerShell 5.1 ist es, PowerShell 7 standardmäßig nicht) -> neu starten
if ($env:RF4_GUI_NOSHOW -ne '1' -and $PSCommandPath -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process $exe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Lang', $Lang)
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:UiCsSource = @'
// RF4 Backup Tool – UI-Bausteine (WinForms, selbst gezeichnet: scharf bei jeder DPI, theme-fähig).
// Wird von build.ps1 in rf4sa-backup-gui.ps1 eingebettet und per Add-Type kompiliert (C# 5!).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Rf4Ui
{
    public static class UiTheme
    {
        public static Color Bg = Color.Black, Surface = Color.Black, Surface2 = Color.Black, Border = Color.Gray, Text = Color.White, Muted = Color.Gray;
        public static Color Accent = Color.Orange, AccentHover = Color.Orange, AccentText = Color.Black, Success = Color.Green, Warn = Color.Yellow, Danger = Color.Red, Selection = Color.Navy;
        public static bool Dark = true;

        public static Color Hex(string s)
        {
            s = s.TrimStart('#');
            return Color.FromArgb(Convert.ToInt32(s.Substring(0, 2), 16), Convert.ToInt32(s.Substring(2, 2), 16), Convert.ToInt32(s.Substring(4, 2), 16));
        }
        public static Color Mix(Color a, Color b, float t)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }
        public static Color Kind(string kind)
        {
            switch (kind)
            {
                case "ok": return Success;
                case "warn": return Warn;
                case "danger": return Danger;
                case "accent": return Accent;
                default: return Muted;
            }
        }
        public static void Invalidate(Control c)
        {
            c.Invalidate();
            foreach (Control ch in c.Controls) Invalidate(ch);
        }
    }

    public static class Native
    {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hwnd, string appName, string idList);
        // dunkle bzw. helle Scrollbars (Win10 1809+)
        public static void DarkScroll(IntPtr h, bool dark) { try { SetWindowTheme(h, dark ? "DarkMode_Explorer" : "Explorer", null); } catch { } }

        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern uint GetConsoleProcessList(uint[] list, uint count);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
        // Konsolenfenster ausblenden, aber nur wenn es dem Programm allein gehoert (Doppelklick/Rechtsklick), nicht bei Start aus einem Terminal
        public static void HideConsole()
        {
            try { IntPtr h = GetConsoleWindow(); if (h != IntPtr.Zero && GetConsoleProcessList(new uint[4], 4) <= 1) ShowWindow(h, 0); } catch { }
        }
        public static void EnableDpi()
        {
            try { if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) SetProcessDPIAware(); }
            catch { try { SetProcessDPIAware(); } catch { } }
        }
        // dunkle Titelleiste (Win10 1809+/Win11) + Titelleistenfarbe passend zum Hintergrund (Win11)
        public static void TitleBar(IntPtr h, bool dark, Color caption, Color text)
        {
            try
            {
                int d = dark ? 1 : 0;
                if (DwmSetWindowAttribute(h, 20, ref d, 4) != 0) DwmSetWindowAttribute(h, 19, ref d, 4);
                int c = caption.R | (caption.G << 8) | (caption.B << 16);
                DwmSetWindowAttribute(h, 35, ref c, 4);
                int t = text.R | (text.G << 8) | (text.B << 16);
                DwmSetWindowAttribute(h, 36, ref t, 4);
            }
            catch { }
        }
    }

    public static class Gfx
    {
        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = Math.Max(0.01f, Math.Min(rad * 2f, Math.Min(r.Width, r.Height)));
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        static PointF P(RectangleF r, float x, float y) { return new PointF(r.X + r.Width * x, r.Y + r.Height * y); }

        public static void Icon(Graphics g, string kind, RectangleF r, Color c, float w)
        {
            SmoothingMode old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(c, w))
            using (SolidBrush br = new SolidBrush(c))
            {
                pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                switch (kind)
                {
                    case "backup":
                        g.DrawLines(pen, new PointF[] { P(r, .15f, .58f), P(r, .15f, .86f), P(r, .85f, .86f), P(r, .85f, .58f) });
                        g.DrawLine(pen, P(r, .5f, .1f), P(r, .5f, .64f));
                        g.DrawLines(pen, new PointF[] { P(r, .3f, .48f), P(r, .5f, .66f), P(r, .7f, .48f) });
                        break;
                    case "restore":
                        g.DrawLines(pen, new PointF[] { P(r, .15f, .58f), P(r, .15f, .86f), P(r, .85f, .86f), P(r, .85f, .58f) });
                        g.DrawLine(pen, P(r, .5f, .66f), P(r, .5f, .12f));
                        g.DrawLines(pen, new PointF[] { P(r, .3f, .3f), P(r, .5f, .1f), P(r, .7f, .3f) });
                        break;
                    case "merge":
                        g.DrawLine(pen, P(r, .18f, .1f), P(r, .5f, .46f));
                        g.DrawLine(pen, P(r, .82f, .1f), P(r, .5f, .46f));
                        g.DrawLine(pen, P(r, .5f, .46f), P(r, .5f, .88f));
                        g.DrawLines(pen, new PointF[] { P(r, .32f, .72f), P(r, .5f, .9f), P(r, .68f, .72f) });
                        break;
                    case "sync":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .14f, r.Y + r.Height * .14f, r.Width * .72f, r.Height * .72f);
                            g.DrawArc(pen, a, 200, 130);
                            g.DrawArc(pen, a, 20, 130);
                            ArrowHead(g, pen, a, 330);
                            ArrowHead(g, pen, a, 150);
                        }
                        break;
                    case "globe":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .1f, r.Y + r.Height * .1f, r.Width * .8f, r.Height * .8f);
                            g.DrawEllipse(pen, a);
                            g.DrawEllipse(pen, new RectangleF(a.X + a.Width * .3f, a.Y, a.Width * .4f, a.Height));
                            g.DrawLine(pen, P(r, .1f, .5f), P(r, .9f, .5f));
                        }
                        break;
                    case "sun":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .32f, r.Y + r.Height * .32f, r.Width * .36f, r.Height * .36f);
                            g.DrawEllipse(pen, a);
                            for (int i = 0; i < 8; i++)
                            {
                                double an = i * Math.PI / 4;
                                float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
                                float r1 = r.Width * .30f, r2 = r.Width * .46f;
                                g.DrawLine(pen, cx + (float)Math.Cos(an) * r1, cy + (float)Math.Sin(an) * r1, cx + (float)Math.Cos(an) * r2, cy + (float)Math.Sin(an) * r2);
                            }
                        }
                        break;
                    case "moon":
                        {
                            using (GraphicsPath p1 = new GraphicsPath())
                            using (GraphicsPath p2 = new GraphicsPath())
                            {
                                p1.AddEllipse(new RectangleF(r.X + r.Width * .14f, r.Y + r.Height * .14f, r.Width * .72f, r.Height * .72f));
                                p2.AddEllipse(new RectangleF(r.X + r.Width * .36f, r.Y + r.Height * .04f, r.Width * .66f, r.Height * .66f));
                                using (Region rg = new Region(p1)) { rg.Exclude(p2); g.FillRegion(br, rg); }
                            }
                        }
                        break;
                    case "auto":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .14f, r.Y + r.Height * .14f, r.Width * .72f, r.Height * .72f);
                            g.DrawEllipse(pen, a);
                            g.FillPie(br, Rectangle.Round(a), 270, 180);
                        }
                        break;
                    case "chevron":
                        g.DrawLines(pen, new PointF[] { P(r, .25f, .38f), P(r, .5f, .64f), P(r, .75f, .38f) });
                        break;
                    case "check":
                        g.DrawLines(pen, new PointF[] { P(r, .18f, .52f), P(r, .42f, .76f), P(r, .84f, .26f) });
                        break;
                    case "folder":
                        g.DrawLines(pen, new PointF[] { P(r, .1f, .26f), P(r, .1f, .8f), P(r, .9f, .8f), P(r, .9f, .34f), P(r, .46f, .34f), P(r, .38f, .22f), P(r, .1f, .22f), P(r, .1f, .26f) });
                        break;
                    case "help":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .1f, r.Y + r.Height * .1f, r.Width * .8f, r.Height * .8f);
                            g.DrawEllipse(pen, a);
                            using (Font qf = new Font("Segoe UI", Math.Max(6f, r.Height * .5f), FontStyle.Bold, GraphicsUnit.Pixel))
                            using (StringFormat sf = new StringFormat())
                            {
                                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                                g.DrawString("?", qf, br, new RectangleF(a.X, a.Y + a.Height * .04f, a.Width, a.Height), sf);
                            }
                        }
                        break;
                    case "disk":
                        g.DrawRectangle(pen, r.X + r.Width * .16f, r.Y + r.Height * .1f, r.Width * .68f, r.Height * .8f);
                        g.DrawLine(pen, P(r, .16f, .36f), P(r, .84f, .36f));
                        g.DrawEllipse(pen, r.X + r.Width * .38f, r.Y + r.Height * .5f, r.Width * .24f, r.Height * .24f);
                        break;
                }
            }
            g.SmoothingMode = old;
        }
        static void ArrowHead(Graphics g, Pen pen, RectangleF a, float angleDeg)
        {
            double an = angleDeg * Math.PI / 180.0;
            float cx = a.X + a.Width / 2, cy = a.Y + a.Height / 2, rad = a.Width / 2;
            PointF p = new PointF(cx + (float)Math.Cos(an) * rad, cy + (float)Math.Sin(an) * rad);
            double tx = -Math.Sin(an), ty = Math.Cos(an);   // Tangente im Uhrzeigersinn
            float h = a.Width * .30f;
            for (int s = -1; s <= 1; s += 2)
            {
                double rot = s * 0.75;
                double dx = -(tx * Math.Cos(rot) - ty * Math.Sin(rot)), dy = -(tx * Math.Sin(rot) + ty * Math.Cos(rot));
                g.DrawLine(pen, p, new PointF(p.X + (float)dx * h, p.Y + (float)dy * h));
            }
        }
    }

    // ── Button ────────────────────────────────────────────────────────────────
    public class UButton : Control
    {
        public string Kind = "secondary";   // primary | secondary | ghost
        public string IconKind = "";
        public bool ShowChevron = false;
        public float Dpi = 1f;
        bool hover, down;
        public UButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.StandardClick | ControlStyles.UseTextForAccessibility, true);
            TabStop = true; Cursor = Cursors.Hand;
        }
        public void PerformClick() { if (Enabled) OnClick(EventArgs.Empty); }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Focus(); Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Enter || k == Keys.Space || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { PerformClick(); e.Handled = true; }
            base.OnKeyDown(e);
        }
        public Size Measure()
        {
            Size t = TextRenderer.MeasureText(Text, Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
            int w = t.Width + (int)(32 * Dpi);
            if (IconKind != "") w += (int)(t.Height * 1.2f) + (int)(8 * Dpi);
            if (ShowChevron) w += (int)(t.Height * .9f) + (int)(6 * Dpi);
            return new Size(w, t.Height + (int)(18 * Dpi));
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color parent = Parent != null ? Parent.BackColor : UiTheme.Bg;
            using (SolidBrush pb = new SolidBrush(parent)) g.FillRectangle(pb, ClientRectangle);
            RectangleF rc = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            float rad = 9f * Dpi;
            Color fill, fore, border = Color.Empty;
            bool en = Enabled;
            if (Kind == "primary")
            {
                fill = !en ? UiTheme.Mix(UiTheme.Surface2, UiTheme.Bg, .3f) : (down ? UiTheme.Mix(UiTheme.Accent, Color.Black, .14f) : (hover ? UiTheme.AccentHover : UiTheme.Accent));
                fore = en ? UiTheme.AccentText : UiTheme.Muted;
            }
            else if (Kind == "ghost")
            {
                fill = (hover || down) && en ? UiTheme.Surface2 : Color.Empty;
                fore = en ? UiTheme.Text : UiTheme.Muted;
            }
            else
            {
                fill = !en ? UiTheme.Surface : (down ? UiTheme.Mix(UiTheme.Surface2, UiTheme.Border, .5f) : (hover ? UiTheme.Surface2 : UiTheme.Surface));
                fore = en ? UiTheme.Text : UiTheme.Muted;
                border = UiTheme.Border;
            }
            using (GraphicsPath p = Gfx.Round(rc, rad))
            {
                if (fill != Color.Empty) using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                if (border != Color.Empty) using (Pen pn = new Pen(border, 1f)) g.DrawPath(pn, p);
                if (Focused && ShowFocusCues) using (Pen fp = new Pen(UiTheme.Accent, 2f * Dpi)) { RectangleF fr = RectangleF.Inflate(rc, -2f * Dpi, -2f * Dpi); using (GraphicsPath fpth = Gfx.Round(fr, rad - 2f * Dpi)) g.DrawPath(fp, fpth); }
            }
            Size ts = TextRenderer.MeasureText(g, Text, Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
            float ih = ts.Height * 1.1f;
            float total = ts.Width;
            if (IconKind != "") total += ih + 8f * Dpi;
            if (ShowChevron) total += ih * .8f + 6f * Dpi;
            float avail = Width - 20f * Dpi;
            float x = (Width - Math.Min(total, avail)) / 2f;
            float cy = Height / 2f;
            if (IconKind != "") { Gfx.Icon(g, IconKind, new RectangleF(x, cy - ih / 2f, ih, ih), fore, Math.Max(1.5f, 1.6f * Dpi)); x += ih + 8f * Dpi; }
            Rectangle tr = new Rectangle((int)x, 0, (int)Math.Max(10, avail - (x - (Width - avail) / 2f) - (ShowChevron ? ih : 0)), Height);
            TextRenderer.DrawText(g, Text, Font, tr, fore, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            if (ShowChevron) Gfx.Icon(g, "chevron", new RectangleF(Math.Min(x + ts.Width + 6f * Dpi, Width - 14f * Dpi - ih * .8f), cy - ih * .4f, ih * .8f, ih * .8f), fore, Math.Max(1.5f, 1.6f * Dpi));
        }
    }

    // ── Karte (Text, Icon, Badge; auswählbar) ─────────────────────────────────
    public class UCard : Control
    {
        public string Title = "", Sub = "", Badge = "", BadgeKind = "muted", IconKind = "";
        public bool Selected, Hovered, Clickable = true, ShowCheck, Dim, IconTop;
        public Font TitleFont, SubFont, BadgeFont;
        public float Dpi = 1f;
        public object Tag2;
        public UCard()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable | ControlStyles.StandardClick, true);
            TabStop = true; Cursor = Cursors.Hand;
        }
        public void PerformClick() { OnClick(EventArgs.Empty); }
        protected override void OnMouseEnter(EventArgs e) { Hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { Hovered = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Space || k == Keys.Enter || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
            base.OnKeyDown(e);
        }
        protected override void OnMouseDown(MouseEventArgs e) { Focus(); base.OnMouseDown(e); }

        const TextFormatFlags TF = TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis | TextFormatFlags.WordBreak | TextFormatFlags.Left | TextFormatFlags.Top;
        void Areas(out Rectangle icon, out Rectangle text, out Rectangle badge, Graphics g)
        {
            int pad = (int)(14 * Dpi);
            int x = pad;
            icon = Rectangle.Empty;
            if (ShowCheck) { x += (int)(26 * Dpi); }
            if (IconKind != "") { int d = (int)(Math.Min(Height - 2 * pad + 8 * Dpi, 56 * Dpi)); icon = new Rectangle(x, IconTop ? pad : (Height - d) / 2, d, d); x += d + (int)(14 * Dpi); }
            badge = Rectangle.Empty;
            int right = Width - pad;
            if (Badge != "" && BadgeFont != null)
            {
                Size bs = TextRenderer.MeasureText(g, Badge, BadgeFont, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                int bw = bs.Width + (int)(20 * Dpi), bh = bs.Height + (int)(8 * Dpi);
                badge = new Rectangle(Width - pad - bw, pad - (int)(2 * Dpi), bw, bh);
                right = badge.X - (int)(10 * Dpi);
            }
            text = new Rectangle(x, pad - (int)(2 * Dpi), Math.Max(10, right - x), Height - 2 * pad + (int)(4 * Dpi));
        }
        // Prüft, ob Titel (einzeilig) bzw. Untertitel (im verfügbaren Platz) abgeschnitten würden
        public bool Overflows()
        {
            using (Graphics g = CreateGraphics())
            {
                Rectangle ic, tx, bd; Areas(out ic, out tx, out bd, g);
                Font tf = TitleFont ?? Font; Font sf = SubFont ?? Font;
                Size t = TextRenderer.MeasureText(g, Title, tf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                if (t.Width > tx.Width) return true;
                if (Sub != "")
                {
                    int th = TextRenderer.MeasureText(g, "Ag", tf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Height + (int)(4 * Dpi);
                    Size s = TextRenderer.MeasureText(g, Sub, sf, new Size(tx.Width, 0), TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                    if (s.Height > tx.Height - th + (int)(4 * Dpi)) return true;
                }
            }
            return false;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color parent = Parent != null ? Parent.BackColor : UiTheme.Bg;
            using (SolidBrush pb = new SolidBrush(parent)) g.FillRectangle(pb, ClientRectangle);
            float bw = Selected ? 2f * Dpi : 1f;
            RectangleF rc = new RectangleF(bw / 2f, bw / 2f, Width - bw - 0.5f, Height - bw - 0.5f);
            Color fill = Selected ? UiTheme.Selection : ((Hovered && Clickable) ? UiTheme.Surface2 : UiTheme.Surface);
            Color border = Selected ? UiTheme.Accent : ((Hovered && Clickable) ? UiTheme.Mix(UiTheme.Border, UiTheme.Accent, .35f) : UiTheme.Border);
            using (GraphicsPath p = Gfx.Round(rc, 12f * Dpi))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                using (Pen pn = new Pen(border, bw)) g.DrawPath(pn, p);
            }
            if (Focused && ShowFocusCues)
                using (Pen fp = new Pen(UiTheme.Accent, 1.5f * Dpi)) { fp.DashStyle = DashStyle.Dot; using (GraphicsPath fpth = Gfx.Round(RectangleF.Inflate(rc, -4f * Dpi, -4f * Dpi), 9f * Dpi)) g.DrawPath(fp, fpth); }

            Rectangle ic, tx, bd; Areas(out ic, out tx, out bd, g);
            Color titleCol = Dim ? UiTheme.Muted : UiTheme.Text;
            if (ShowCheck)
            {
                int d = (int)(18 * Dpi); int cx = (int)(14 * Dpi); int cy = (Height - d) / 2;
                RectangleF box = new RectangleF(cx, cy, d, d);
                using (GraphicsPath bp = Gfx.Round(box, 5f * Dpi))
                {
                    if (Selected) { using (SolidBrush ab = new SolidBrush(UiTheme.Accent)) g.FillPath(ab, bp); Gfx.Icon(g, "check", box, UiTheme.AccentText, 2f * Dpi); }
                    else using (Pen bpn = new Pen(UiTheme.Muted, 1.5f * Dpi)) g.DrawPath(bpn, bp);
                }
            }
            if (!ic.IsEmpty)
            {
                using (SolidBrush cb = new SolidBrush(Selected ? UiTheme.Accent : UiTheme.Surface2)) g.FillEllipse(cb, ic);
                float pad = ic.Width * .24f;
                Gfx.Icon(g, IconKind, new RectangleF(ic.X + pad, ic.Y + pad, ic.Width - 2 * pad, ic.Height - 2 * pad), Selected ? UiTheme.AccentText : (Dim ? UiTheme.Muted : UiTheme.Accent), Math.Max(1.6f, 1.9f * Dpi));
            }
            Font tf = TitleFont ?? Font; Font sf = SubFont ?? Font;
            int th = TextRenderer.MeasureText(g, "Ag", tf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Height;
            TextRenderer.DrawText(g, Title, tf, new Rectangle(tx.X, tx.Y, tx.Width, th + 2), titleCol, TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | TextFormatFlags.Left | TextFormatFlags.Top);
            if (Sub != "")
                TextRenderer.DrawText(g, Sub, sf, new Rectangle(tx.X, tx.Y + th + (int)(4 * Dpi), tx.Width, Math.Max(10, tx.Height - th - (int)(4 * Dpi))), UiTheme.Muted, TF);
            if (!bd.IsEmpty)
            {
                Color kc = UiTheme.Kind(BadgeKind);
                using (GraphicsPath bp = Gfx.Round(bd, bd.Height / 2f))
                {
                    using (SolidBrush bb = new SolidBrush(UiTheme.Mix(fill, kc, .18f))) g.FillPath(bb, bp);
                    using (Pen bpn = new Pen(UiTheme.Mix(fill, kc, .55f), 1f)) g.DrawPath(bpn, bp);
                }
                TextRenderer.DrawText(g, Badge, BadgeFont, bd, kc, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }
        }
    }

    // ── Liste aus Karten ──────────────────────────────────────────────────────
    public class UCardList : Panel
    {
        public List<UCard> Cards = new List<UCard>();
        public string Mode = "one";          // none | one | multi
        public float Dpi = 1f;
        public int CardHeight = 64, Gap = 8;
        public Font TitleFont, SubFont, BadgeFont;
        public event EventHandler SelectionChanged;
        public UCardList()
        {
            AutoScroll = true; DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }
        public UCard Add(string title, string sub, string badge, string badgeKind, string icon, object tag)
        {
            UCard c = new UCard();
            c.Title = title; c.Sub = sub; c.Badge = badge; c.BadgeKind = badgeKind; c.IconKind = icon; c.Tag2 = tag;
            c.Dpi = Dpi; c.TitleFont = TitleFont; c.SubFont = SubFont; c.BadgeFont = BadgeFont; c.Font = SubFont ?? Font;
            c.ShowCheck = (Mode == "multi"); c.Clickable = (Mode != "none"); c.Cursor = Mode == "none" ? Cursors.Default : Cursors.Hand;
            c.Click += CardClick;
            Cards.Add(c); Controls.Add(c);
            LayoutCards();
            return c;
        }
        public void ClearItems() { foreach (UCard c in Cards) { Controls.Remove(c); c.Dispose(); } Cards.Clear(); }
        void CardClick(object s, EventArgs e)
        {
            UCard c = (UCard)s;
            if (Mode == "none") return;
            if (Mode == "one") { foreach (UCard o in Cards) o.Selected = (o == c); }
            else c.Selected = !c.Selected;
            foreach (UCard o in Cards) o.Invalidate();
            if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
        }
        public int SelectedIndex
        {
            get { for (int i = 0; i < Cards.Count; i++) if (Cards[i].Selected) return i; return -1; }
            set
            {
                for (int i = 0; i < Cards.Count; i++) Cards[i].Selected = (i == value);
                foreach (UCard o in Cards) o.Invalidate();
                if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
            }
        }
        public int[] SelectedIndices
        {
            get { List<int> l = new List<int>(); for (int i = 0; i < Cards.Count; i++) if (Cards[i].Selected) l.Add(i); return l.ToArray(); }
        }
        public void SetSelected(int i, bool sel) { if (i >= 0 && i < Cards.Count) { Cards[i].Selected = sel; Cards[i].Invalidate(); } }
        public int ContentHeight { get { return Cards.Count * (CardHeight + Gap); } }
        public void LayoutCards()
        {
            SuspendLayout();
            int w = ClientSize.Width;
            int y = 0;
            foreach (UCard c in Cards) { c.SetBounds(0, y, Math.Max(10, w), CardHeight); y += CardHeight + Gap; }
            AutoScrollMinSize = new Size(0, Math.Max(0, y - Gap));
            try { VerticalScroll.SmallChange = Math.Max(20, CardHeight / 2); VerticalScroll.LargeChange = Math.Max(60, CardHeight * 2); } catch { }
            ResumeLayout(false);
        }
        protected override void OnResize(EventArgs e) { base.OnResize(e); LayoutCards(); }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Native.DarkScroll(Handle, UiTheme.Dark); }
    }

    // ── Schritt-Anzeige ───────────────────────────────────────────────────────
    public class UStepper : Control
    {
        public string[] Steps = new string[0];
        public int Current = 0;
        public float Dpi = 1f;
        public UStepper() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            int n = Steps.Length; if (n == 0) return;
            float d = 24f * Dpi, slot = (float)Width / n, cy = d / 2f + 6f * Dpi;
            for (int i = 0; i < n - 1; i++)
            {
                float x1 = slot * i + slot / 2f + d / 2f + 4f * Dpi, x2 = slot * (i + 1) + slot / 2f - d / 2f - 4f * Dpi;
                using (Pen p = new Pen(i < Current ? UiTheme.Success : UiTheme.Border, 2f * Dpi)) g.DrawLine(p, x1, cy, x2, cy);
            }
            for (int i = 0; i < n; i++)
            {
                float cx = slot * i + slot / 2f;
                RectangleF c = new RectangleF(cx - d / 2f, cy - d / 2f, d, d);
                bool done = i < Current, cur = i == Current;
                using (SolidBrush b = new SolidBrush(done ? UiTheme.Success : (cur ? UiTheme.Accent : UiTheme.Surface2))) g.FillEllipse(b, c);
                if (!done && !cur) using (Pen p = new Pen(UiTheme.Border, 1f)) g.DrawEllipse(p, c);
                if (done) Gfx.Icon(g, "check", new RectangleF(c.X + 4 * Dpi, c.Y + 4 * Dpi, c.Width - 8 * Dpi, c.Height - 8 * Dpi), UiTheme.AccentText, 2f * Dpi);
                else TextRenderer.DrawText(g, (i + 1).ToString(), Font, Rectangle.Round(c), cur ? UiTheme.AccentText : UiTheme.Muted, TextFormatFlags.NoPadding | TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                Rectangle lr = new Rectangle((int)(slot * i), (int)(cy + d / 2f + 4f * Dpi), (int)slot, Height - (int)(cy + d / 2f + 4f * Dpi));
                using (Font f = new Font(Font, cur ? FontStyle.Bold : FontStyle.Regular))
                    TextRenderer.DrawText(g, Steps[i], f, lr, cur ? UiTheme.Text : (done ? UiTheme.Success : UiTheme.Muted), TextFormatFlags.NoPadding | TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            }
        }
    }

    // ── Checkbox ──────────────────────────────────────────────────────────────
    public class UCheck : Control
    {
        public bool Checked = false;
        public float Dpi = 1f;
        public event EventHandler CheckedChanged;
        public UCheck()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable | ControlStyles.StandardClick | ControlStyles.UseTextForAccessibility, true);
            TabStop = true; Cursor = Cursors.Hand;
        }
        public void Toggle() { Checked = !Checked; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        protected override void OnClick(EventArgs e) { if (Enabled) Toggle(); base.OnClick(e); }
        protected override void OnMouseDown(MouseEventArgs e) { Focus(); base.OnMouseDown(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Space || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space) { Toggle(); e.Handled = true; } base.OnKeyDown(e); }
        public int PreferredWidth()
        {
            return TextRenderer.MeasureText(Text, Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Width + (int)(34 * Dpi);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            float d = 18f * Dpi; RectangleF box = new RectangleF(1f, (Height - d) / 2f, d, d);
            Color fore = Enabled ? UiTheme.Text : UiTheme.Muted;
            using (GraphicsPath bp = Gfx.Round(box, 5f * Dpi))
            {
                if (Checked) { using (SolidBrush ab = new SolidBrush(Enabled ? UiTheme.Accent : UiTheme.Mix(UiTheme.Accent, UiTheme.Bg, .6f))) g.FillPath(ab, bp); Gfx.Icon(g, "check", box, UiTheme.AccentText, 2f * Dpi); }
                else { using (SolidBrush sb = new SolidBrush(UiTheme.Surface)) g.FillPath(sb, bp); using (Pen pn = new Pen(Focused && ShowFocusCues ? UiTheme.Accent : UiTheme.Muted, 1.5f * Dpi)) g.DrawPath(pn, bp); }
            }
            TextRenderer.DrawText(g, Text, Font, new Rectangle((int)(d + 10f * Dpi), 0, Width - (int)(d + 10f * Dpi), Height), fore, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        }
    }

    // ── Eingabefeld ───────────────────────────────────────────────────────────
    public class UInput : Control
    {
        public TextBox Box = new TextBox();
        public float Dpi = 1f;
        bool focused;
        public UInput()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Box.BorderStyle = BorderStyle.None;
            Box.Enter += delegate { focused = true; Invalidate(); };
            Box.Leave += delegate { focused = false; Invalidate(); };
            Controls.Add(Box);
        }
        public override string Text { get { return Box.Text; } set { Box.Text = value; } }
        public void ApplyTheme() { Box.BackColor = UiTheme.Surface; Box.ForeColor = UiTheme.Text; Box.Font = Font; PositionBox(); Invalidate(); }
        void PositionBox()
        {
            int pad = (int)(12 * Dpi);
            Box.Font = Font;
            int h = Box.PreferredHeight;
            Box.SetBounds(pad, Math.Max(0, (Height - h) / 2), Math.Max(10, Width - 2 * pad), h);
        }
        protected override void OnResize(EventArgs e) { base.OnResize(e); PositionBox(); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); PositionBox(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            RectangleF rc = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (GraphicsPath p = Gfx.Round(rc, 9f * Dpi))
            {
                using (SolidBrush b = new SolidBrush(UiTheme.Surface)) g.FillPath(b, p);
                using (Pen pn = new Pen(focused ? UiTheme.Accent : UiTheme.Border, focused ? 1.6f * Dpi : 1f)) g.DrawPath(pn, p);
            }
        }
    }

    // ── Fortschrittsbalken ────────────────────────────────────────────────────
    public class UProgress : Control
    {
        public bool Indeterminate = true;
        public int Value = 0;     // 0..100
        public float Dpi = 1f;
        float phase = 0f;
        Timer timer = new Timer();
        public UProgress()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            timer.Interval = 30; timer.Tick += delegate { Step(); };
            timer.Start();
        }
        public void Step() { phase += 0.018f; if (phase > 1f) phase -= 1f; Invalidate(); }
        protected override void Dispose(bool disposing) { if (disposing) { timer.Stop(); timer.Dispose(); } base.Dispose(disposing); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            RectangleF tr = new RectangleF(0, 0, Width - 1, Height - 1);
            using (GraphicsPath tp = Gfx.Round(tr, tr.Height / 2f)) using (SolidBrush tb = new SolidBrush(UiTheme.Surface2)) g.FillPath(tb, tp);
            RectangleF bar;
            if (Indeterminate)
            {
                float w = tr.Width * .32f, x = (tr.Width + w) * phase - w;
                float x0 = Math.Max(0, x), x1 = Math.Min(tr.Width, x + w);
                if (x1 <= x0) return;
                bar = new RectangleF(x0, 0, x1 - x0, tr.Height);
            }
            else bar = new RectangleF(0, 0, Math.Max(tr.Height, tr.Width * Value / 100f), tr.Height);
            using (GraphicsPath bp = Gfx.Round(bar, bar.Height / 2f)) using (SolidBrush bb = new SolidBrush(UiTheme.Accent)) g.FillPath(bb, bp);
        }
    }

    // ── Kennzahl-Kachel ───────────────────────────────────────────────────────
    public class UStat : Control
    {
        public string Value = "0", Caption = "", Kind = "muted";
        public Font ValueFont;
        public float Dpi = 1f;
        public UStat() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        public bool Overflows()
        {
            using (Graphics g = CreateGraphics())
            {
                Size c = TextRenderer.MeasureText(g, Caption, Font, new Size(Width - (int)(24 * Dpi), 0), TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                Size v = TextRenderer.MeasureText(g, Value, ValueFont ?? Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                return v.Width > Width - (int)(24 * Dpi) || (v.Height + c.Height + (int)(26 * Dpi)) > Height;
            }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            RectangleF rc = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color kc = UiTheme.Kind(Kind);
            using (GraphicsPath p = Gfx.Round(rc, 12f * Dpi))
            {
                using (SolidBrush b = new SolidBrush(UiTheme.Surface)) g.FillPath(b, p);
                using (Pen pn = new Pen(UiTheme.Border, 1f)) g.DrawPath(pn, p);
            }
            using (GraphicsPath ap = Gfx.Round(new RectangleF(0.5f, 0.5f, 5f * Dpi, Height - 1.5f), 3f * Dpi)) using (SolidBrush ab = new SolidBrush(kc)) g.FillPath(ab, ap);
            int pad = (int)(16 * Dpi);
            Font vf = ValueFont ?? Font;
            int vh = TextRenderer.MeasureText(g, "0", vf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Height;
            TextRenderer.DrawText(g, Value, vf, new Rectangle(pad, (int)(8 * Dpi), Width - pad - (int)(8 * Dpi), vh), kc, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            TextRenderer.DrawText(g, Caption, Font, new Rectangle(pad, (int)(8 * Dpi) + vh, Width - pad - (int)(8 * Dpi), Height - vh - (int)(12 * Dpi)), UiTheme.Muted, TextFormatFlags.NoPadding | TextFormatFlags.WordBreak | TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis);
        }
    }

    // ── Menü-Darstellung (Sprach-/Design-Auswahl) ─────────────────────────────
    public class MenuColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return UiTheme.Surface; } }
        public override Color ImageMarginGradientBegin { get { return UiTheme.Surface; } }
        public override Color ImageMarginGradientMiddle { get { return UiTheme.Surface; } }
        public override Color ImageMarginGradientEnd { get { return UiTheme.Surface; } }
        public override Color MenuBorder { get { return UiTheme.Border; } }
        public override Color MenuItemBorder { get { return UiTheme.Accent; } }
        public override Color MenuItemSelected { get { return UiTheme.Surface2; } }
        public override Color MenuItemSelectedGradientBegin { get { return UiTheme.Surface2; } }
        public override Color MenuItemSelectedGradientEnd { get { return UiTheme.Surface2; } }
        public override Color SeparatorDark { get { return UiTheme.Border; } }
        public override Color SeparatorLight { get { return UiTheme.Border; } }
        public override Color CheckBackground { get { return UiTheme.Selection; } }
        public override Color CheckSelectedBackground { get { return UiTheme.Selection; } }
        public override Color CheckPressedBackground { get { return UiTheme.Selection; } }
    }
    public class ThemedRenderer : ToolStripProfessionalRenderer
    {
        public ThemedRenderer() : base(new MenuColors()) { RoundedEdges = false; }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) { e.TextColor = UiTheme.Text; base.OnRenderItemText(e); }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) { e.ArrowColor = UiTheme.Text; base.OnRenderArrow(e); }
    }

    // Mausrad: Nachricht an das Steuerelement UNTER dem Mauszeiger leiten (WinForms schickt sie sonst an das fokussierte)
    public class WheelFilter : IMessageFilter
    {
        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point p);
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        static bool installed;
        public static void Install() { if (!installed) { Application.AddMessageFilter(new WheelFilter()); installed = true; } }
        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != 0x020A) return false;
            long lp = m.LParam.ToInt64();
            Point p = new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF));
            IntPtr h = WindowFromPoint(p);
            if (h != IntPtr.Zero && h != m.HWnd && Control.FromHandle(h) != null) { SendMessage(h, m.Msg, m.WParam, m.LParam); return true; }
            return false;
        }
    }
}
'@
Add-Type -TypeDefinition $script:UiCsSource -ReferencedAssemblies System.Windows.Forms, System.Drawing

if (-not ('Rf4Ui.UButton' -as [type])) {
    $uiPath = Join-Path $PSScriptRoot 'ui.cs'
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($uiPath, [Text.Encoding]::UTF8)) -ReferencedAssemblies System.Windows.Forms, System.Drawing
}
[Rf4Ui.Native]::EnableDpi()
[Rf4Ui.Native]::HideConsole()
[Rf4Ui.WheelFilter]::Install()
# ── Globaler Fehlerfänger: Fehler in Ereignissen führen nicht mehr zum .NET-Absturzdialog ──
function Write-ErrorLog([string]$msg) {
    try { New-Item -ItemType Directory -Force -Path (Get-ConfigDir) | Out-Null; Add-Content -LiteralPath (Join-Path (Get-ConfigDir) 'error.log') -Value ("{0}  {1}`r`n" -f (Get-Date -Format 's'), $msg) -Encoding UTF8 } catch { }
}
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { }
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    $m = $e.Exception.Message; Write-ErrorLog ($m + ' | ' + $e.Exception.StackTrace)
    $script:state.Busy = $false; $script:lblCur = $null
    try { $form.Cursor = [System.Windows.Forms.Cursors]::Default } catch { }
    try { [void](Show-Msg ((T 'err_unexpected') + "`n`n" + $m + "`n`n" + (T 'err_logged' @((Join-Path (Get-ConfigDir) 'error.log')))) 'Error' 'OK') } catch { }
})
                       # VOR dem ersten Fenster: sonst skaliert Windows das Bild hoch (unscharf)
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
Initialize-Lang $Lang

# ── Skalierung, Schriften, Theme ───────────────────────────────────────────────
function Get-SystemScale {
    if ($env:RF4_GUI_SCALE) { return [double]$env:RF4_GUI_SCALE }
    try { $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $s = $g.DpiX / 96.0; $g.Dispose(); return $s } catch { return 1.0 }
}
$script:Scale = Get-SystemScale
function S([double]$n) { [int][Math]::Round($n * $script:Scale) }

function New-F([double]$pt, [bool]$bold = $false) {
    $fam = if ($script:Lang -eq 'zh') { 'Microsoft YaHei UI' } else { 'Segoe UI' }
    $st = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    New-Object System.Drawing.Font($fam, [single]($pt * $script:Scale * 96.0 / 72.0), $st, [System.Drawing.GraphicsUnit]::Pixel)
}
function Update-Fonts {
    $script:F = @{ body = (New-F 9.5); bold = (New-F 9.5 $true); small = (New-F 8.5); smallb = (New-F 8.5 $true); h1 = (New-F 16 $true); h2 = (New-F 12 $true); big = (New-F 20 $true); card = (New-F 10.5 $true) }
}
function Get-ThemeName([string]$code) {
    $k = "theme_name_$code"
    if ($script:TX.ContainsKey($k)) { return (T $k) }
    return [string]$script:Themes[$code].name
}
function ColorOf([string]$hex) { [Rf4Ui.UiTheme]::Hex($hex) }
function Apply-Theme {
    $cfg = Get-Config
    $script:ThemeChoice = if ($cfg.theme) { $cfg.theme } else { 'auto' }
    $script:ThemeCode = Resolve-ThemeCode $script:ThemeChoice
    $c = Get-ThemeColors $script:ThemeCode
    $script:Col = @{}
    foreach ($k in $c.Keys) { $script:Col[$k] = ColorOf $c[$k] }
    [Rf4Ui.UiTheme]::Bg = $script:Col.bg; [Rf4Ui.UiTheme]::Surface = $script:Col.surface; [Rf4Ui.UiTheme]::Surface2 = $script:Col.surface2
    [Rf4Ui.UiTheme]::Border = $script:Col.border; [Rf4Ui.UiTheme]::Text = $script:Col.text; [Rf4Ui.UiTheme]::Muted = $script:Col.muted
    [Rf4Ui.UiTheme]::Accent = $script:Col.accent; [Rf4Ui.UiTheme]::AccentHover = $script:Col.accentHover; [Rf4Ui.UiTheme]::AccentText = $script:Col.accentText
    [Rf4Ui.UiTheme]::Success = $script:Col.success; [Rf4Ui.UiTheme]::Warn = $script:Col.warn; [Rf4Ui.UiTheme]::Danger = $script:Col.danger
    [Rf4Ui.UiTheme]::Selection = $script:Col.selection
    [Rf4Ui.UiTheme]::Dark = ($script:Themes[$script:ThemeCode].base -eq 'dark')
}
Update-Fonts
Apply-Theme

# ── Bausteine ──────────────────────────────────────────────────────────────────
function New-Lbl([string]$text, $font = $null, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $false; $l.UseMnemonic = $false; $l.Text = $text
    $l.Font = $(if ($font) { $font } else { $script:F.body })
    $l.ForeColor = $(if ($color) { $color } else { $script:Col.text })
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}
function New-Btn([string]$text, [string]$kind = 'secondary', [string]$icon = '', [bool]$chevron = $false) {
    $b = New-Object Rf4Ui.UButton
    $b.Kind = $kind; $b.IconKind = $icon; $b.ShowChevron = $chevron; $b.Dpi = [single]$script:Scale
    $b.Font = $script:F.bold; $b.Text = $text; $b.BackColor = $script:Col.bg
    $m = $b.Measure(); $b.Size = New-Object System.Drawing.Size($m.Width, [Math]::Max($m.Height, (S 38)))
    return $b
}
function New-Cards([string]$mode = 'one', [int]$cardH = 0) {
    $l = New-Object Rf4Ui.UCardList
    $l.Mode = $mode; $l.Dpi = [single]$script:Scale; $l.CardHeight = $(if ($cardH) { $cardH } else { S 66 }); $l.Gap = (S 8)
    $l.TitleFont = $script:F.card; $l.SubFont = $script:F.small; $l.BadgeFont = $script:F.smallb; $l.Font = $script:F.small
    $l.BackColor = $script:Col.bg
    return $l
}
function New-Check([string]$text, [bool]$checked = $false) {
    $c = New-Object Rf4Ui.UCheck
    $c.Dpi = [single]$script:Scale; $c.Font = $script:F.body; $c.Text = $text; $c.Checked = $checked; $c.BackColor = $script:Col.bg
    $c.Size = New-Object System.Drawing.Size($c.PreferredWidth(), (S 28))
    return $c
}
function New-Input([string]$value) {
    $i = New-Object Rf4Ui.UInput
    $i.Dpi = [single]$script:Scale; $i.Font = $script:F.body; $i.BackColor = $script:Col.bg; $i.Height = (S 40); $i.Text = $value; $i.ApplyTheme()
    return $i
}
# Auswahl-Button mit Menü (Sprache, Design, Account …):  items = @( @{ text=..; value=.. } … )
function New-Dropdown([string]$text, [string]$icon, $items, [string]$selected, [scriptblock]$onPick) {
    $b = New-Btn $text 'secondary' $icon $true
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Renderer = New-Object Rf4Ui.ThemedRenderer
    $menu.Font = $script:F.body; $menu.BackColor = $script:Col.surface; $menu.ForeColor = $script:Col.text; $menu.ShowImageMargin = $true
    foreach ($it in $items) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($it.text)
        $mi.Tag = [string]$it.value; $mi.Checked = ([string]$it.value -eq $selected)
        $mi.ForeColor = $script:Col.text; $mi.BackColor = $script:Col.surface; $mi.Padding = New-Object System.Windows.Forms.Padding((S 4), (S 6), (S 4), (S 6))
        $cb = $onPick
        $mi.Add_Click({ param($s, $e) & $cb ([string]$s.Tag) }.GetNewClosure())
        [void]$menu.Items.Add($mi)
    }
    $b.Tag = $menu
    $b.Add_Click({ param($s, $e) $s.Tag.Show($s, (New-Object System.Drawing.Point(0, ($s.Height + (S 4))))) })
    return $b
}

# Eigenes, themefähiges Meldungsfenster (statt weißem MessageBox im dunklen Design).
# WICHTIG: Closures sehen $script:-Variablen nicht -> alles Nötige vorher in lokale Variablen holen.
function Show-Msg([string]$Text, [string]$Kind = 'Warning', [string]$Buttons = 'OK') {
    $colBg = $script:Col.bg; $colSurface = $script:Col.surface; $colText = $script:Col.text
    $isDark = [Rf4Ui.UiTheme]::Dark
    $res = @{ v = $(if ($Buttons -eq 'YesNo') { 'No' } else { 'OK' }) }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = T 'app_title'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.StartPosition = 'CenterParent'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false; $dlg.BackColor = $colBg
    $w = (S 560); $dlg.ClientSize = New-Object System.Drawing.Size($w, (S 210))
    $icon = switch ($Kind) { 'Warning' { 'warn' } 'Error' { 'danger' } default { 'accent' } }
    $lbl = New-Lbl $Text $script:F.body $colText
    $lbl.SetBounds((S 30), (S 22), ($w - (S 60)), (S 120)); $lbl.AutoEllipsis = $true
    $bar = New-Object System.Windows.Forms.Panel; $bar.SetBounds(0, (S 18), (S 5), (S 110)); $bar.BackColor = [Rf4Ui.UiTheme]::Kind($icon)
    $dlg.Controls.AddRange(@($bar, $lbl))
    $by = (S 152)
    if ($Buttons -eq 'YesNo') {
        $y = New-Btn (T 'dialog_yes') 'primary'; $n = New-Btn (T 'dialog_no') 'secondary'
        $y.BackColor = $colBg; $n.BackColor = $colBg
        $y.Width = [Math]::Max($y.Width, (S 120)); $n.Width = [Math]::Max($n.Width, (S 120))
        $n.Location = New-Object System.Drawing.Point(($w - $n.Width - (S 24)), $by); $y.Location = New-Object System.Drawing.Point(($n.Left - $y.Width - (S 10)), $by)
        $y.Add_Click({ $res.v = 'Yes'; $dlg.Close() }.GetNewClosure()); $n.Add_Click({ $res.v = 'No'; $dlg.Close() }.GetNewClosure())
        $dlg.Controls.AddRange(@($y, $n))
    } else {
        $o = New-Btn (T 'dialog_ok') 'primary'; $o.BackColor = $colBg; $o.Width = [Math]::Max($o.Width, (S 120))
        $o.Location = New-Object System.Drawing.Point(($w - $o.Width - (S 24)), $by)
        $o.Add_Click({ $res.v = 'OK'; $dlg.Close() }.GetNewClosure()); $dlg.Controls.Add($o)
    }
    $dlg.Add_HandleCreated({ try { [Rf4Ui.Native]::TitleBar($dlg.Handle, $isDark, $colSurface, $colText) } catch { } }.GetNewClosure())
    try {
        if ($script:form -and $script:form.Visible) { [void]$dlg.ShowDialog($script:form) } else { [void]$dlg.ShowDialog() }
    } finally { $dlg.Dispose() }
    return $res.v
}
function New-AppIcon {
    try {
        $bmp = New-Object System.Drawing.Bitmap(64, 64); $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
        $p = [Rf4Ui.Gfx]::Round((New-Object System.Drawing.RectangleF(2, 2, 60, 60)), 14)
        $br = New-Object System.Drawing.SolidBrush($script:Col.accent); $g.FillPath($br, $p)
        [Rf4Ui.Gfx]::Icon($g, 'backup', (New-Object System.Drawing.RectangleF(13, 13, 38, 38)), $script:Col.accentText, 5)
        $g.Dispose(); return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    } catch { return $null }
}

# ── Hauptfenster ───────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$script:form = $form
$form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'None'
# Startgröße: Wunschgröße, aber nie größer als der Bildschirm (kleine Laptops: 1366x768 bei 125 %)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.ClientSize = New-Object System.Drawing.Size([Math]::Min((S 1000), [int]($wa.Width * 0.94)), [Math]::Min((S 740), [int]($wa.Height * 0.90) - (S 40)))
$form.MinimumSize = New-Object System.Drawing.Size([Math]::Min((S 780), $wa.Width), [Math]::Min((S 520), $wa.Height))
$ic = New-AppIcon; if ($ic) { $form.Icon = $ic }

$script:pContent = New-Object System.Windows.Forms.Panel; $script:pContent.Dock = 'Fill'; $script:pContent.AutoScroll = $true
$script:pContent.Add_HandleCreated({ try { [Rf4Ui.Native]::DarkScroll($script:pContent.Handle, [Rf4Ui.UiTheme]::Dark) } catch { } })
$script:stepper = New-Object Rf4Ui.UStepper; $script:stepper.Dock = 'Top'
$script:pHeader = New-Object System.Windows.Forms.Panel; $script:pHeader.Dock = 'Top'
$script:pFooter = New-Object System.Windows.Forms.Panel; $script:pFooter.Dock = 'Bottom'
$form.Controls.Add($script:pContent); $form.Controls.Add($script:stepper); $form.Controls.Add($script:pHeader); $form.Controls.Add($script:pFooter)

$script:lblTitle = New-Lbl '' $script:F.h1; $script:lblSub = New-Lbl '' $script:F.small
$script:lblDonate = New-Lbl '' $script:F.small; $script:lblDonate.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:lblDonate.Add_Click({ try { Start-Process 'https://paypal.me/bjoernoppermann' } catch { } })
$script:pHeader.Controls.AddRange(@($script:lblTitle, $script:lblSub, $script:lblDonate))
$script:btnBack = New-Btn '' 'secondary'; $script:btnExtra = New-Btn '' 'ghost'; $script:btnPrimary = New-Btn '' 'primary'
$script:pFooter.Controls.AddRange(@($script:btnBack, $script:btnExtra, $script:btnPrimary))
$script:btnBack.Add_Click({ if ($script:BackAction) { & $script:BackAction } })
$script:btnExtra.Add_Click({ if ($script:ExtraAction) { & $script:ExtraAction } })
$script:btnPrimary.Add_Click({ if ($script:PrimaryAction) { & $script:PrimaryAction } })
$script:state = @{ Installs = $null; Action = ''; Render = $null; Step = 0; LastOpen = ''; Busy = $false; ResultKey = '' }
$script:RunLog = New-Object System.Text.StringBuilder
$script:L = @()                                   # Layout-Einträge des aktuellen Panels
foreach ($n in @('lblCur', 'BackAction', 'PrimaryAction', 'ExtraAction', 'headHelp', 'headLang', 'headTheme', 'bkAcct', 'bkAcctItems', 'rsCurrent', 'statCtls', 'tbDetails', 'dlgResult', 'cmbDirty')) { Set-Variable -Name $n -Value $null -Scope Script }
$script:bkAcctValue = ''
$script:inLayout = $false
$script:Tip = New-Object System.Windows.Forms.ToolTip

# Rebuild der Kopfzeile (Texte, Schriften, Farben, Position)
function Build-Header {
    $script:pHeader.Height = (S 68); $script:pHeader.BackColor = $script:Col.surface
    $script:pFooter.Height = (S 68); $script:pFooter.BackColor = $script:Col.surface
    $script:pContent.BackColor = $script:Col.bg; $form.BackColor = $script:Col.bg
    $script:stepper.Height = (S 70); $script:stepper.BackColor = $script:Col.bg; $script:stepper.Dpi = [single]$script:Scale; $script:stepper.Font = $script:F.small
    $script:stepper.Steps = @((T 'step1'), (T 'step2'), (T 'step3'), (T 'step4'), (T 'step5'))
    $script:lblTitle.Font = $script:F.h1; $script:lblTitle.ForeColor = $script:Col.text; $script:lblTitle.Text = T 'app_title'
    $script:lblSub.Font = $script:F.small; $script:lblSub.ForeColor = $script:Col.muted; $script:lblSub.Text = 'v' + $script:ToolVersion + '  ·  '
    $script:lblDonate.Font = New-Object System.Drawing.Font($script:F.small, [System.Drawing.FontStyle]::Underline); $script:lblDonate.ForeColor = $script:Col.accent; $script:lblDonate.Text = T 'donate'
    $script:Tip.SetToolTip($script:lblDonate, 'https://paypal.me/bjoernoppermann')
    foreach ($b in @($script:headHelp, $script:headLang, $script:headTheme)) { if ($b) { $script:pHeader.Controls.Remove($b); $b.Dispose() } }
    # Hilfe: Anleitung in der aktuellen Sprache öffnen
    $script:headHelp = New-Btn (T 'help_btn') 'secondary' 'help'
    $script:headHelp.Add_Click({ Open-Guide })
    $script:Tip.SetToolTip($script:headHelp, (T 'tip_help'))
    # Sprache
    $langItems = @($script:Langs | ForEach-Object { @{ text = $script:LangNames[$_]; value = $_ } })
    $script:headLang = New-Dropdown $script:LangNames[$script:Lang] 'globe' $langItems $script:Lang { param($v) Set-Language $v }
    $script:Tip.SetToolTip($script:headLang, (T 'tip_lang'))
    # Design
    $items = @(@{ text = (T 'theme_auto'); value = 'auto' }) + @($script:Themes.Keys | ForEach-Object { @{ text = (Get-ThemeName $_); value = $_ } })
    $icon = if ($script:ThemeChoice -eq 'auto') { 'auto' } elseif ($script:Themes[$script:ThemeCode].base -eq 'dark') { 'moon' } else { 'sun' }
    $label = if ($script:ThemeChoice -eq 'auto') { T 'theme_auto' } else { Get-ThemeName $script:ThemeCode }
    $script:headTheme = New-Dropdown $label $icon $items $script:ThemeChoice { param($v) Set-ThemeChoice $v }
    $script:Tip.SetToolTip($script:headTheme, (T 'tip_theme'))
    $script:pHeader.Controls.AddRange(@($script:headHelp, $script:headLang, $script:headTheme))
    Position-Header
    $script:stepper.Current = $script:state.Step; $script:stepper.Invalidate()
    try { if ($script:pContent.IsHandleCreated) { [Rf4Ui.Native]::DarkScroll($script:pContent.Handle, [Rf4Ui.UiTheme]::Dark) } } catch { }
    $form.Text = (T 'app_title') + ' v' + $script:ToolVersion
    try { if ($form.IsHandleCreated) { [Rf4Ui.Native]::TitleBar($form.Handle, [Rf4Ui.UiTheme]::Dark, $script:Col.surface, $script:Col.text) } } catch { }
}
function Position-Header {
    $w = $script:pHeader.ClientSize.Width; $pad = (S 24)
    $script:lblTitle.SetBounds($pad, (S 8), [Math]::Max((S 200), $w - (S 560)), (S 32))
    $subW = [System.Windows.Forms.TextRenderer]::MeasureText($script:lblSub.Text, $script:lblSub.Font).Width
    $script:lblSub.SetBounds($pad, (S 40), $subW + (S 2), (S 20))
    $dw = [System.Windows.Forms.TextRenderer]::MeasureText($script:lblDonate.Text, $script:lblDonate.Font).Width
    $script:lblDonate.SetBounds($pad + $subW, (S 40), $dw + (S 4), (S 20))
    $h = $script:headLang.Height; $y = [int](($script:pHeader.Height - $h) / 2)
    $script:headTheme.Location = New-Object System.Drawing.Point(($w - $pad - $script:headTheme.Width), $y)
    $script:headLang.Location = New-Object System.Drawing.Point(($script:headTheme.Left - (S 10) - $script:headLang.Width), $y)
    $script:headHelp.Location = New-Object System.Drawing.Point(($script:headLang.Left - (S 10) - $script:headHelp.Width), $y)
}
function Position-Footer {
    $pad = (S 24); $w = $script:pFooter.ClientSize.Width; $y = [int](($script:pFooter.Height - $script:btnPrimary.Height) / 2)
    $script:btnBack.Location = New-Object System.Drawing.Point($pad, $y)
    $script:btnExtra.Location = New-Object System.Drawing.Point(($script:btnBack.Right + (S 10)), $y)
    $script:btnPrimary.Location = New-Object System.Drawing.Point(($w - $pad - $script:btnPrimary.Width), $y)
}
function Set-Footer([string]$backText, [scriptblock]$back, [string]$primaryText, [scriptblock]$primary, [string]$extraText = '', [scriptblock]$extra = $null, [string]$primaryIcon = '') {
    foreach ($pair in @(@($script:btnBack, $backText, 'secondary'), @($script:btnExtra, $extraText, 'ghost'), @($script:btnPrimary, $primaryText, 'primary'))) {
        $b = $pair[0]; $b.Text = $pair[1]; $b.Font = $script:F.bold; $b.Dpi = [single]$script:Scale; $b.BackColor = $script:Col.surface; $b.Kind = $pair[2]
        $b.Visible = [bool]$pair[1]
        if ($pair[1]) { $m = $b.Measure(); $b.Size = New-Object System.Drawing.Size([Math]::Max($m.Width, (S 120)), [Math]::Max($m.Height, (S 40))) }
    }
    $script:btnPrimary.IconKind = $primaryIcon; if ($primaryIcon) { $m = $script:btnPrimary.Measure(); $script:btnPrimary.Width = [Math]::Max($m.Width, (S 140)) }
    $script:btnPrimary.Enabled = $true
    $script:BackAction = $back; $script:PrimaryAction = $primary; $script:ExtraAction = $extra
    Position-Footer
}

# ── Layout-Engine: senkrechte Reihe (DPI-sicher, mit Scroll bei kleinem Fenster) ──
function Add-Item([hashtable]$it) { $script:L += $it; if ($it.ContainsKey('c')) { $script:pContent.Controls.Add($it.c) } }
function Add-Label([string]$text, $font = $null, $color = $null, [int]$gap = 8) {
    $l = New-Lbl $text $font $color; Add-Item @{ k = 'label'; c = $l; gap = (S $gap) }; return $l
}
function Add-Fill($ctl, [int]$min = 120) { Add-Item @{ k = 'fill'; c = $ctl; min = (S $min); gap = (S 12) } }
function Add-Fixed($ctl, [int]$h, [int]$gap = 12) { Add-Item @{ k = 'ctl'; c = $ctl; h = (S $h); gap = (S $gap) } }
function Add-Row([int]$h, [scriptblock]$fn, [int]$gap = 12) { Add-Item @{ k = 'row'; h = (S $h); fn = $fn; gap = (S $gap) } }
function Do-Layout {
    if ($script:inLayout -or -not $script:pContent) { return }
    $script:inLayout = $true
    try {
        $pad = (S 28); $top = (S 20)
        $w = [Math]::Max((S 300), $script:pContent.ClientSize.Width - 2 * $pad)
        $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
        $fixed = 0; $fillMin = 0; $fillItem = $null
        foreach ($it in $script:L) {
            switch ($it.k) {
                'label' { $sz = [System.Windows.Forms.TextRenderer]::MeasureText($it.c.Text, $it.c.Font, (New-Object System.Drawing.Size($w, 0)), $flags); $it.h = $sz.Height + (S 4) }
            }
            if ($it.k -eq 'fill') { $fillItem = $it; $fillMin += $it.min + $it.gap } else { $fixed += $it.h + $it.gap }
        }
        $avail = $script:pContent.ClientSize.Height - $top - (S 16)
        $fillH = [Math]::Max($(if ($fillItem) { $fillItem.min } else { 0 }), $avail - $fixed - $(if ($fillItem) { $fillItem.gap } else { 0 }))
        $y = $top
        foreach ($it in $script:L) {
            $h = if ($it.k -eq 'fill') { $fillH } else { $it.h }
            if ($it.k -eq 'fill' -and $it.c -is [Rf4Ui.UCardList] -and $it.c.Cards.Count -gt 0) { $h = [Math]::Min($h, $it.c.ContentHeight + (S 4)) }
            switch ($it.k) {
                'row' { & $it.fn $pad $y $w }
                default { $it.c.SetBounds($pad, $y, $w, $h) }
            }
            $y += $h + $it.gap
        }
        $script:pContent.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($y + (S 8)))
        foreach ($it in $script:L) { if ($it.k -eq 'fill' -and $it.c -is [Rf4Ui.UCardList]) { $it.c.LayoutCards() } }
    } finally { $script:inLayout = $false }
}

function Show-Panel([scriptblock]$render) {
    $script:state.Render = $render
    $script:pContent.SuspendLayout()
    while ($script:pContent.Controls.Count -gt 0) { $c = $script:pContent.Controls[0]; $script:pContent.Controls.RemoveAt(0); $c.Dispose() }
    $script:L = @(); $script:pContent.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    & $render
    $script:pContent.ResumeLayout($false)
    Do-Layout
    $script:stepper.Current = $script:state.Step; $script:stepper.Invalidate()
}
function Set-Step([int]$s) { $script:state.Step = $s; $script:stepper.Current = $s }

# ── Sprache / Design / DPI umschalten ──────────────────────────────────────────
function Rebuild-All {
    Update-Fonts; Apply-Theme; Build-Header
    $script:cmbDirty = $false
    if ($script:state.Render -and -not $script:state.Busy) { Show-Panel $script:state.Render }
    Position-Footer
}
function Set-Language([string]$code) {
    [void](Set-Lang $code); try { Save-Lang $script:Lang } catch { }
    Rebuild-All
}
function Set-ThemeChoice([string]$choice) {
    try { Save-ThemeChoice $choice } catch { }
    Rebuild-All
}
$script:pContent.Add_ClientSizeChanged({ Do-Layout })
$script:pHeader.Add_Resize({ if ($script:headLang) { Position-Header } })
$script:pFooter.Add_Resize({ Position-Footer })
$form.Add_DpiChanged({ param($s, $e) $script:Scale = $e.DeviceDpiNew / 96.0; Rebuild-All })
$form.Add_HandleCreated({ try { [Rf4Ui.Native]::TitleBar($form.Handle, [Rf4Ui.UiTheme]::Dark, $script:Col.surface, $script:Col.text) } catch { } })
# Windows-Design live verfolgen (nur bei "Automatisch")
$script:themeTimer = New-Object System.Windows.Forms.Timer; $script:themeTimer.Interval = 2000
$script:themeTimer.Add_Tick({
    if ($script:state.Busy) { return }
    $cfg = Get-Config; $choice = if ($cfg.theme) { $cfg.theme } else { 'auto' }
    if ($choice -eq 'auto' -and (Resolve-ThemeCode 'auto') -ne $script:ThemeCode) { Rebuild-All }
})

# ── Log-Senke ──────────────────────────────────────────────────────────────────
$script:LogSink = {
    param($lvl, $msg)
    $prefix = switch ($lvl) { 'ok' { '[OK] ' } 'warn' { '[!]  ' } 'err' { '[X]  ' } default { '     ' } }
    [void]$script:RunLog.AppendLine("$prefix$msg")
    if ($script:lblCur) { $script:lblCur.Text = $msg; $script:lblCur.Refresh() }
    [System.Windows.Forms.Application]::DoEvents()
}

function Ensure-Installs { if ($null -eq $script:state.Installs) { $script:state.Installs = @(Find-Installations) } }
function Get-ExistingInstalls { Ensure-Installs; @($script:state.Installs | Where-Object { $_.Exists }) }
function Confirm-GameClosedGui {
    $run = Test-Rf4Running
    if (-not $run) { return $true }
    return ((Show-Msg ((T 'running_warn' @($run)) + "`n`n" + (T 'running_ask')) 'Warning' 'YesNo') -eq 'Yes')
}
$script:ConfirmOverwrite = { param($name) ((Show-Msg (T 'overwrite_q' @($name, "`n")) 'Warning' 'YesNo') -eq 'Yes') }
function Pick-Folder([string]$start, [string]$desc = '') {
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($desc) { $fb.Description = $desc }
    if ($start -and (Test-Path -LiteralPath $start)) { $fb.SelectedPath = $start }
    if ($fb.ShowDialog($form) -eq 'OK') { return $fb.SelectedPath }
    return $null
}
function Inst-Card($list, $inst, [string]$icon = 'disk') {
    $sub = ''
    if ($inst.Exists) { $info = Get-InstInfo $inst.Path; $sub = (T 'scan_stats' @($info.Mailboxes.Count, $info.Convs)) + $(if ($info.Ids) { '   ·   ' + (T 'scan_accounts' @($info.Ids)) } else { '' }) + "`n" + $inst.Path }
    else { $sub = $inst.Path }
    $badge = if ($inst.Exists) { T 'chip_found' } else { T 'chip_missing' }
    $c = $list.Add((Get-InstLabel $inst), $sub, $badge, $(if ($inst.Exists) { 'ok' } else { 'muted' }), $icon, $inst)
    $c.Dim = (-not $inst.Exists)
    return $c
}

# ── Panel 1: Scan ──────────────────────────────────────────────────────────────
function Render-Scan {
    Set-Step 0
    [void](Add-Label (T 'hdr_scan_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'scan_hint') $script:F.small $script:Col.muted 12)
    $lst = New-Cards 'none' (S 92); Add-Fill $lst 160
    $status = Add-Label (T 'scanning') $script:F.body $script:Col.accent 4
    [void](Add-Label (T 'scan_readonly') $script:F.small $script:Col.success 4)
    Set-Footer (T 'rescan') { $script:state.Installs = $null; Show-Panel { Render-Scan } } (T 'next') { Show-Panel { Render-Action } }
    $script:btnPrimary.Enabled = $false
    Do-Layout; $form.Refresh()
    if ($null -eq $script:state.Installs) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; [System.Windows.Forms.Application]::DoEvents()
        $script:state.Installs = @(Find-Installations)
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    $found = 0
    foreach ($i in ($script:state.Installs | Sort-Object { -not $_.Exists })) { [void](Inst-Card $lst $i); if ($i.Exists) { $found++ } }
    $status.Text = if ($found -gt 0) { T 'found_n' @($found) } else { T 'none_found' }
    $status.ForeColor = if ($found -gt 0) { $script:Col.success } else { $script:Col.warn }
    $script:btnPrimary.Enabled = ($found -gt 0)
    Do-Layout
}

# ── Panel 2: Aktion ────────────────────────────────────────────────────────────
function Render-Action {
    Set-Step 1
    [void](Add-Label (T 'hdr_action_t') $script:F.h2 $script:Col.text 12)
    $acts = @(@('backup', 'act_backup', 'act_backup_d'), @('restore', 'act_restore', 'act_restore_d'), @('merge', 'act_merge', 'act_merge_d'), @('sync', 'act_sync', 'act_sync_d'))
    $script:actCards = @{}
    foreach ($a in $acts) {
        $c = New-Object Rf4Ui.UCard
        $c.Dpi = [single]$script:Scale; $c.Title = T $a[1]; $c.Sub = T $a[2]; $c.IconKind = $a[0]
        $c.TitleFont = $script:F.card; $c.SubFont = $script:F.body; $c.Font = $script:F.body; $c.BadgeFont = $script:F.smallb; $c.BackColor = $script:Col.bg
        $c.Selected = ($script:state.Action -eq $a[0]); $c.Tag = $a[0]; $c.IconTop = $true
        $c.Add_Click({ param($s, $e)
            $script:state.Action = [string]$s.Tag
            foreach ($k in $script:actCards.Keys) { $script:actCards[$k].Selected = ($k -eq $script:state.Action); $script:actCards[$k].Invalidate() }
        })
        $script:pContent.Controls.Add($c); $script:actCards[$a[0]] = $c
    }
    Add-Row 270 {
        param($x, $y, $w)
        $gap = (S 16); $cw = [int](($w - $gap) / 2); $ch = [int]((S 270 - $gap) / 2)
        $keys = @('backup', 'restore', 'merge', 'sync')
        for ($i = 0; $i -lt 4; $i++) { $script:actCards[$keys[$i]].SetBounds($x + ($i % 2) * ($cw + $gap), $y + [int][Math]::Floor($i / 2) * ($ch + $gap), $cw, $ch) }
    }
    Set-Footer (T 'back') { Show-Panel { Render-Scan } } (T 'next') {
        switch ($script:state.Action) {
            'backup'  { Show-Panel { Render-Backup } }
            'restore' { Show-Panel { Render-Restore } }
            'merge'   { Show-Panel { Render-Merge } }
            'sync'    { Show-Panel { Render-Sync } }
            default   { [void](Show-Msg (T 'pick_action')) }
        }
    }
}

# Reihe aus Checkboxen mit Umbruch
function Add-CheckRow($checks) {
    foreach ($c in $checks) { $script:pContent.Controls.Add($c) }
    $script:chkRowChecks = $checks
    $rows = 1
    Add-Row 34 {
        param($x, $y, $w)
        $cx = $x; $cy = $y; $gap = (S 26); $rowH = (S 32)
        foreach ($c in $script:chkRowChecks) {
            if ($cx + $c.Width -gt $x + $w -and $cx -gt $x) { $cx = $x; $cy += $rowH }
            $c.Location = New-Object System.Drawing.Point($cx, $cy); $cx += $c.Width + $gap
        }
    }
    # Höhe der Reihe an die tatsächliche Zeilenzahl anpassen
    $total = 0; foreach ($c in $checks) { $total += $c.Width + (S 26) }
    $it = $script:L[-1]; $avail = [Math]::Max((S 300), $script:pContent.ClientSize.Width - 2 * (S 28))
    $lines = [Math]::Max(1, [int][Math]::Ceiling($total / $avail)); $it.h = (S 32) * $lines + (S 2)
}

function Update-AcctText { $t = ($script:bkAcctItems | Where-Object { $_.value -eq $script:bkAcctValue } | Select-Object -First 1).text; $script:bkAcct.Text = (T 'sel_account') + ' ' + $t; $m = $script:bkAcct.Measure(); $script:bkAcct.Width = $m.Width; $script:bkAcct.Invalidate() }

# ── Panel 3a: Backup ───────────────────────────────────────────────────────────
function Render-Backup {
    Set-Step 2
    [void](Add-Label (T 'hdr_backup_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'pick_source') $script:F.small $script:Col.muted 8)
    $script:exSrc = Get-ExistingInstalls
    $lst = New-Cards 'one' (S 92); $script:lstSrc = $lst
    foreach ($i in $script:exSrc) { [void](Inst-Card $lst $i) }
    if ($lst.Cards.Count -gt 0) { $lst.SelectedIndex = 0 }
    Add-Fill $lst 150
    [void](Add-Label (T 'what_backup') $script:F.bold $script:Col.text 6)
    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $script:bkKeys = $keys; $script:bkChecks = @()
    foreach ($k in $keys) { $script:bkChecks += (New-Check (T "item_$k") ($k -in @('mail', 'Settings.dat', 'Preferences.dat'))) }
    Add-CheckRow $script:bkChecks
    # Account-Auswahl (Dropdown), nur bei > 1 Mailbox
    $script:bkAcctHost = New-Object System.Windows.Forms.Panel; $script:bkAcctHost.BackColor = $script:Col.bg
    $script:pContent.Controls.Add($script:bkAcctHost); $script:bkAcct = $null; $script:bkAcctValue = ''
    Add-Item @{ k = 'ctl'; c = $script:bkAcctHost; h = (S 44); gap = (S 6) }
    $script:refreshAcct = {
        $script:bkAcctHost.Controls.Clear(); $script:bkAcctValue = ''
        if ($script:lstSrc.SelectedIndex -lt 0) { return }
        $boxes = @(Get-Mailboxes $script:exSrc[$script:lstSrc.SelectedIndex].Path)
        if ($boxes.Count -le 1) { return }
        $items = @(@{ text = (T 'all_accts' @($boxes.Count)); value = '' }) + @($boxes | ForEach-Object { @{ text = (T 'acct_line' @($_.Id, $_.Convs)); value = $_.Name } })
        $b = New-Dropdown ((T 'sel_account') + ' ' + (T 'all_accts' @($boxes.Count))) '' $items '' { param($v) $script:bkAcctValue = $v; Update-AcctText }
        $script:bkAcct = $b; $script:bkAcctItems = $items; $script:bkAcctHost.Controls.Add($b); $b.Location = New-Object System.Drawing.Point(0, 0)
    }

    $lst.add_SelectionChanged({ & $script:refreshAcct })
    & $script:refreshAcct
    [void](Add-Label (T 'backup_to') $script:F.bold $script:Col.text 6)
    $script:inDir = New-Input (Get-DefaultBackupDir); $script:pContent.Controls.Add($script:inDir)
    $script:btnBrowseBk = New-Btn (T 'btn_browse') 'secondary' 'folder'; $script:pContent.Controls.Add($script:btnBrowseBk)
    $script:btnBrowseBk.Add_Click({ $p = Pick-Folder $script:inDir.Text; if ($p) { $script:inDir.Text = $p } })
    Add-Row 42 { param($x, $y, $w) $bw = $script:btnBrowseBk.Width; $script:inDir.SetBounds($x, $y, $w - $bw - (S 10), (S 40)); $script:btnBrowseBk.SetBounds($x + $w - $bw, $y, $bw, (S 40)) } 4
    $script:lblBkHint = Add-Label '' $script:F.small $script:Col.muted 4
    $script:updateBkHint = { $d = $script:inDir.Text.Trim(); $i = if ($d) { Read-BackupInfo $d } else { $null }; $script:lblBkHint.Text = if ($i) { T 'bk_existing_here' @((Get-BackupSourceLabel $i) + '  ' + (Format-BackupDates ([pscustomobject]@{ Created = $i.Created; Updated = $i.Updated; Time = (Get-Date) }))) } else { '' }; Do-Layout }
    $script:inDir.Box.Add_TextChanged({ & $script:updateBkHint }); & $script:updateBkHint
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'run_backup') {
        if ($script:lstSrc.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        $items = @(); for ($i = 0; $i -lt $script:bkKeys.Count; $i++) { if ($script:bkChecks[$i].Checked) { $items += $script:bkKeys[$i] } }
        if ($items.Count -eq 0) { [void](Show-Msg (T 'pick_item')); return }
        $src = $script:exSrc[$script:lstSrc.SelectedIndex]
        $dest = $script:inDir.Text.Trim(); if (-not $dest) { $dest = Get-DefaultBackupDir }
        $acc = if ($script:bkAcctValue) { @($script:bkAcctValue) } else { $null }
        Start-Operation 'hdr_backup_t' $dest {
            Copy-Rf4Data -SrcDir $src.Path -DstDir $dest -Items $items -Accounts $acc -ShotsSrc (Get-ScreenshotDir $src.Path) -ShotsDst (Join-Path $dest 'Screenshots') -Confirm $script:ConfirmOverwrite
            Write-BackupInfo $dest $src $items
            Add-BackupDir $dest
            Write-Log 'ok' 'backup_done' @($dest)
        }
    } '' $null 'backup'
}

# ── Panel 3b: Restore ──────────────────────────────────────────────────────────
function Render-Restore {
    Set-Step 2
    [void](Add-Label (T 'hdr_restore_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'existing_backups') $script:F.bold $script:Col.text 6)
    $script:rsBackups = @(Find-Backups); $script:rsExtra = $null
    $lb = New-Cards 'one' (S 136); $script:lstBk = $lb
    foreach ($b in $script:rsBackups) { [void]$lb.Add($b.Name, (Format-BackupCard $b), $(if ($b.IsSync) { T 'bk_badge_sync' } else { '' }), 'accent', 'disk', $b) }
    if ($script:rsBackups.Count -eq 0) { $lb.Visible = $true }
    Add-Fixed $lb ([Math]::Min(2, [Math]::Max(1, $script:rsBackups.Count)) * 144 + 4) 8
    $script:lblNoBk = Add-Label $(if ($script:rsBackups.Count -eq 0) { T 'no_existing_backups' } else { '' }) $script:F.small $script:Col.muted 8
    $script:btnOtherBk = New-Btn (T 'other_folder') 'secondary' 'folder'; $script:pContent.Controls.Add($script:btnOtherBk)
    Add-Row 40 { param($x, $y, $w) $script:btnOtherBk.SetBounds($x, $y, $script:btnOtherBk.Width, (S 40)) }
    [void](Add-Label (T 'pick_target') $script:F.bold $script:Col.text 6)
    Ensure-Installs; $script:rsIns = @($script:state.Installs)
    $ld = New-Cards 'one' (S 92); $script:lstDst = $ld
    foreach ($i in ($script:rsIns | Sort-Object { -not $_.Exists })) { [void](Inst-Card $ld $i) }
    Add-Fill $ld 120
    [void](Add-Label (T 'what_restore') $script:F.bold $script:Col.text 6)
    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $script:rsKeys = $keys; $script:rsChecks = @()
    foreach ($k in $keys) { $script:rsChecks += (New-Check (T "item_$k") $false) }
    Add-CheckRow $script:rsChecks
    $script:rsCurrent = $null
    $script:applyBackup = {
        param($bk)
        $script:rsCurrent = $bk
        $has = @{ 'mail' = ($bk.Mailboxes -gt 0); 'shots' = ($bk.Shots -gt 0) }; foreach ($f in $script:DatFiles) { $has[$f] = ($bk.Files -contains $f) }
        for ($i = 0; $i -lt $script:rsKeys.Count; $i++) { $c = $script:rsChecks[$i]; $c.Enabled = [bool]$has[$script:rsKeys[$i]]; $c.Checked = [bool]$has[$script:rsKeys[$i]]; $c.Invalidate() }
    }
    $lb.add_SelectionChanged({ $ix = $script:lstBk.SelectedIndex; if ($ix -ge 0) { & $script:applyBackup $script:rsBackups[$ix] } })
    $script:btnOtherBk.Add_Click({
        $start = if (Get-SyncPath) { Get-SyncPath } else { Get-DefaultBackupDir }
        $p = Pick-Folder $start (T 'pick_backup_d'); if (-not $p) { return }
        $rp = Resolve-BackupPath $p     # nimmt auch den übergeordneten Ordner eines RF4_Sync-Ordners (Netzwerk/NAS)
        if (-not $rp) { [void](Show-Msg ((T 'restore_path_bad') + "`n`n" + $p)); return }
        $dupe = [Array]::FindIndex($script:lstBk.Cards.ToArray(), [Predicate[object]] { param($c) $c.Tag2.Path -eq $rp })
        if ($dupe -ge 0) { $script:lstBk.SelectedIndex = $dupe; return }
        $bk = Get-BackupEntry $rp
        [void]$script:lstBk.Add($bk.Name, (Format-BackupCard $bk), $(if ($bk.IsSync) { T 'bk_badge_sync' } else { '' }), 'accent', 'disk', $bk)
        $script:lstBk.SelectedIndex = $script:lstBk.Cards.Count - 1
        $script:rsBackups = @($script:lstBk.Cards | ForEach-Object { $_.Tag2 })
        $script:lblNoBk.Text = ''; Do-Layout
    })
    if ($lb.Cards.Count -gt 0) { $lb.SelectedIndex = 0 }
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'run_restore') {
        if (-not $script:rsCurrent) { [void](Show-Msg (T 'select_backup_first')); return }
        if ($script:lstDst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        $items = @(); for ($i = 0; $i -lt $script:rsKeys.Count; $i++) { if ($script:rsChecks[$i].Checked -and $script:rsChecks[$i].Enabled) { $items += $script:rsKeys[$i] } }
        if ($items.Count -eq 0) { [void](Show-Msg (T 'pick_item')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dst = $script:lstDst.Cards[$script:lstDst.SelectedIndex].Tag2.Path; $src = $script:rsCurrent.Path
        Start-Operation 'hdr_restore_t' $dst {
            Write-Log 'info' 'importing_to' @($dst)
            Copy-Rf4Data -SrcDir $src -DstDir $dst -Items $items -ShotsSrc (Join-Path $src 'Screenshots') -ShotsDst (Get-ScreenshotDir $dst -Create) -Confirm $script:ConfirmOverwrite -UndoRoot (New-UndoRoot $dst)
            Add-BackupDir (Split-Path $src -Parent)
            Write-Log 'ok' 'restore_done'
        }
    } '' $null 'restore'
}

# ── Panel 3c: Merge ────────────────────────────────────────────────────────────
function Render-Merge {
    Set-Step 2
    [void](Add-Label (T 'hdr_merge_t') $script:F.h2 $script:Col.text 4)
    $ex = Get-ExistingInstalls; $script:mgEx = $ex
    if ($ex.Count -lt 2) {
        [void](Add-Label (T 'merge_need2') $script:F.body $script:Col.warn 8)
        Set-Footer (T 'back') { Show-Panel { Render-Action } } '' $null; return
    }
    [void](Add-Label (T 'merge_note') $script:F.small $script:Col.warn 4)
    [void](Add-Label (T 'merge_safe') $script:F.small $script:Col.success 4)
    [void](Add-Label (T 'undo_hint') $script:F.small $script:Col.muted 10)
    [void](Add-Label (T 'merge_dst') $script:F.bold $script:Col.text 6)
    $script:lstMgDst = New-Cards 'one' (S 92); foreach ($i in $ex) { [void](Inst-Card $script:lstMgDst $i) }
    Add-Fill $script:lstMgDst 120
    [void](Add-Label (T 'merge_src') $script:F.bold $script:Col.text 6)
    $script:lstMgSrc = New-Cards 'multi' (S 92); foreach ($i in $ex) { [void](Inst-Card $script:lstMgSrc $i) }
    Add-Fill $script:lstMgSrc 120
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'run_merge') {
        $d = $script:lstMgDst.SelectedIndex; $s = @($script:lstMgSrc.SelectedIndices)
        if ($d -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        if ($s.Count -eq 0) { [void](Show-Msg (T 'pick_one_src')); return }
        if ($s -contains $d) { [void](Show-Msg (T 'merge_same')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dstPath = $script:mgEx[$d].Path; $srcs = @($s | ForEach-Object { $script:mgEx[$_] }); $undo = New-UndoRoot $dstPath
        Start-Operation 'hdr_merge_t' $dstPath {
            foreach ($si in $srcs) {
                Write-Log 'info' 'merge_src_hdr' @((Get-InstLabel $si))
                Copy-Rf4Data -SrcDir $si.Path -DstDir $dstPath -Items @('mail') -UndoRoot $undo
            }
            Write-Log 'ok' 'merge_done'
        }
    } '' $null 'merge'
}

# ── Panel 3d: Sync ─────────────────────────────────────────────────────────────
function Render-Sync {
    Set-Step 2
    [void](Add-Label (T 'hdr_sync_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'sync_intro') $script:F.small $script:Col.muted 10)
    [void](Add-Label (T 'sync_dir_lbl') $script:F.bold $script:Col.text 6)
    $script:inSync = New-Input (Get-SyncPath); $script:pContent.Controls.Add($script:inSync)
    $script:btnBrowseSy = New-Btn (T 'btn_browse') 'secondary' 'folder'; $script:pContent.Controls.Add($script:btnBrowseSy)
    $script:btnBrowseSy.Add_Click({ $p = Pick-Folder $script:inSync.Text (T 'sync_pick_dir'); if ($p) { $script:inSync.Text = $p; Set-SyncPath $p } })
    Add-Row 42 { param($x, $y, $w) $bw = $script:btnBrowseSy.Width; $script:inSync.SetBounds($x, $y, $w - $bw - (S 10), (S 40)); $script:btnBrowseSy.SetBounds($x + $w - $bw, $y, $bw, (S 40)) } 4
    [void](Add-Label (T 'sync_hint') $script:F.small $script:Col.muted 12)
    [void](Add-Label (T 'sync_inst_lbl') $script:F.bold $script:Col.text 6)
    $script:syEx = Get-ExistingInstalls
    $script:lstSyInst = New-Cards 'one' (S 92); foreach ($i in $script:syEx) { [void](Inst-Card $script:lstSyInst $i) }
    if ($script:lstSyInst.Cards.Count -gt 0) { $script:lstSyInst.SelectedIndex = 0 }
    Add-Fill $script:lstSyInst 110
    $script:lblSyState = Add-Label '' $script:F.small $script:Col.muted 4
    $script:lstSySt = New-Cards 'none' (S 40); Add-Fill $script:lstSySt 80
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'sync_run_btn') {
        $sp = $script:inSync.Text.Trim()
        if (-not $sp) { [void](Show-Msg (T 'sync_first')); return }
        if (-not (Test-Path -LiteralPath $sp)) { [void](Show-Msg ((T 'sync_unreach' @($sp)) + "`n" + (T 'sync_unreach_h'))); return }
        if ($script:lstSyInst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        Set-SyncPath $sp; $inst = $script:syEx[$script:lstSyInst.SelectedIndex]
        Start-Operation 'hdr_sync_t' $inst.Path { Invoke-SyncRun -InstPath $inst.Path -SyncBase $sp }
    } (T 'sync_status_btn') {
        $script:lstSySt.ClearItems(); $sp = $script:inSync.Text.Trim()
        if (-not $sp) { $script:lblSyState.Text = T 'sync_none'; return }
        if (-not (Test-Path -LiteralPath $sp)) { $script:lblSyState.Text = T 'sync_unreach' @($sp); return }
        Set-SyncPath $sp; $script:lblSyState.Text = T 'sync_ok' @($sp)
        $st = Get-SyncStatus $sp
        if (-not $st.Exists) { [void]$script:lstSySt.Add((T 'sync_st_nodir'), '', '', 'muted', '', $null); return }
        if ($st.Mailboxes.Count -eq 0) { [void]$script:lstSySt.Add((T 'sync_st_none'), '', '', 'muted', '', $null) }
        foreach ($m in $st.Mailboxes) { [void]$script:lstSySt.Add((T 'sync_st_boxes' @($m.Name, $m.Convs)), '', '', 'muted', '', $null) }
        foreach ($f in $st.Files) { [void]$script:lstSySt.Add("$($f.Name)  ·  $($f.Time)", '', '', 'muted', '', $null) }
        foreach ($l in $st.Log) { [void]$script:lstSySt.Add($l, '', '', 'muted', '', $null) }
    } 'sync'
}

# ── Ausführen + Ergebnis ───────────────────────────────────────────────────────
function Start-Operation([string]$titleKey, [string]$openPath, [scriptblock]$work) {
    if ($script:state.Busy) { return }
    $script:state.Busy = $true; $script:state.LastOpen = $openPath; $script:state.ResultKey = $titleKey
    $script:RunLog.Clear() | Out-Null; Reset-Stats
    Show-Panel {
        Set-Step 3
        [void](Add-Label (T $script:state.ResultKey) $script:F.h2 $script:Col.text 8)
        [void](Add-Label (T 'working_title') $script:F.body $script:Col.muted 18)
        $pg = New-Object Rf4Ui.UProgress; $pg.Dpi = [single]$script:Scale; $pg.BackColor = $script:Col.bg; Add-Fixed $pg 12 14
        $script:lblCur = Add-Label (T 'working') $script:F.small $script:Col.accent 4
        Set-Footer '' $null '' $null
    }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    try { & $work } catch { Add-Stat Failed; Write-Log 'err' 'f_failed' @($titleKey, $_.Exception.Message) }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $script:lblCur = $null; $script:state.Busy = $false
    Show-Panel { Render-Result }
}
function Render-Result {
    Set-Step 4
    $st = Get-Stats
    [void](Add-Label ((T $script:state.ResultKey) + '  ·  ' + (T 'result_title')) $script:F.h2 $script:Col.text 10)
    # Status-Karte
    $card = New-Object Rf4Ui.UCard; $card.Dpi = [single]$script:Scale; $card.Clickable = $false; $card.Cursor = [System.Windows.Forms.Cursors]::Default
    $card.IconKind = 'check'; $card.TitleFont = $script:F.card; $card.SubFont = $script:F.small; $card.Font = $script:F.small; $card.BadgeFont = $script:F.smallb; $card.BackColor = $script:Col.bg
    if ($st.Failed -gt 0) { $card.Title = T 'res_err' @($st.Failed); $card.Badge = ''; $card.IconKind = 'folder' } else { $card.Title = T 'res_ok' }
    $card.Sub = $script:state.LastOpen
    Add-Fixed $card 74 14
    # Kennzahlen
    $stats = @()
    $stats += , @($st.MsgAdded, (T 'sum_msgs'), 'accent')
    $stats += , @(($st.ConvNew + $st.ConvMerged), (T 'sum_convs'), 'ok')
    $stats += , @(($st.FilesNew + $st.FilesReplaced), (T 'sum_files'), 'ok')
    if ($st.Shots -gt 0) { $stats += , @($st.Shots, (T 'sum_shots'), 'ok') }
    if ($st.FilesSkipped -gt 0) { $stats += , @($st.FilesSkipped, (T 'sum_skipped'), 'warn') }
    if ($st.Failed -gt 0) { $stats += , @($st.Failed, (T 'sum_failed'), 'danger') }
    $script:statCtls = @()
    foreach ($s in $stats) {
        $u = New-Object Rf4Ui.UStat; $u.Dpi = [single]$script:Scale; $u.Value = [string]$s[0]; $u.Caption = [string]$s[1]; $u.Kind = [string]$s[2]; $u.ValueFont = $script:F.big; $u.Font = $script:F.small; $u.BackColor = $script:Col.bg
        $script:pContent.Controls.Add($u); $script:statCtls += $u
    }
    Add-Row 84 {
        param($x, $y, $w)
        $n = $script:statCtls.Count; if ($n -eq 0) { return }
        $gap = (S 12); $cw = [int](($w - $gap * ($n - 1)) / $n)
        for ($i = 0; $i -lt $n; $i++) { $script:statCtls[$i].SetBounds($x + $i * ($cw + $gap), $y, $cw, (S 84)) }
    } 14
    # Details
    $script:btnDetails = New-Btn (T 'show_details') 'ghost'; $script:pContent.Controls.Add($script:btnDetails)
    Add-Row 40 { param($x, $y, $w) $script:btnDetails.SetBounds($x, $y, $script:btnDetails.Width, (S 38)) } 4
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.BorderStyle = 'None'; $tb.Font = New-Object System.Drawing.Font('Consolas', [single](9.5 * $script:Scale * 96 / 72), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $tb.Add_HandleCreated({ param($s, $e) try { [Rf4Ui.Native]::DarkScroll($s.Handle, [Rf4Ui.UiTheme]::Dark) } catch { } }); $tb.BackColor = $script:Col.surface; $tb.ForeColor = $script:Col.text; $tb.Text = ($script:RunLog.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")); $tb.Visible = $false
    $script:tbDetails = $tb; Add-Fill $tb 140
    $script:btnDetails.Add_Click({
        $script:tbDetails.Visible = -not $script:tbDetails.Visible
        $script:btnDetails.Text = if ($script:tbDetails.Visible) { T 'hide_details' } else { T 'show_details' }
        $m = $script:btnDetails.Measure(); $script:btnDetails.Width = $m.Width; $script:pContent.ScrollControlIntoView($script:tbDetails)
    })
    Set-Footer (T 'btn_open') { if ($script:state.LastOpen -and (Test-Path -LiteralPath $script:state.LastOpen)) { Start-Process explorer.exe -ArgumentList ('"' + $script:state.LastOpen + '"') } } (T 'btn_start_over') { $script:state.Installs = $null; Show-Panel { Render-Scan } } '' $null 'sync'
    $script:btnPrimary.IconKind = ''
}

# ── Start ──────────────────────────────────────────────────────────────────────
Build-Header
if ($env:RF4_GUI_NOSHOW -ne '1') {
    $form.Add_Shown({ Show-Panel { Render-Scan }; $script:themeTimer.Start() })
    [void]$form.ShowDialog()
}
