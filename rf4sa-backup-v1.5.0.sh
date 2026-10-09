#!/usr/bin/env bash
# rf4sa-backup.sh — RF4 Backup & Migration (Linux / macOS / Git-Bash), interaktiv
# Findet Installationen auf Windows-Partitionen, in Wine-Prefixes und in Steam-Proton.
# Sichert, stellt wieder her, führt zusammen und synchronisiert Mailboxen, Einstellungen, Screenshots.
# Es wird nichts gelöscht; ersetzte Dateien landen in <Installation>/_rf4tool_undo/<Zeitstempel>.
#
# Sprachen: Deutsch, English, 中文, Русский  (im Programm umschaltbar [L], oder: -l de|en|zh|ru, oder RF4_LANG=xx)
# Benötigt: bash >= 4, python3 (nur zum Zusammenführen der Nachrichten-Dateien)
#
# Infos & Blog:  https://nga.li/rf4b
# Quellcode:     https://nga.li/rf4git  (Codeberg)
# Download:      https://nga.li/rf4dl
# Spenden/Donate: https://paypal.me/bjoernoppermann
#
# Version 1.5.0 – 2026-10-09

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # '&' in Ersetzungstexten nicht speziell behandeln (bash 5.2+)

TOOL_VERSION="1.5.0"
# UTF-8 sicherstellen (Rahmen, 中文, Русский): bei LANG=C auf C.UTF-8 ausweichen
if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then export LC_ALL=C.UTF-8 2>/dev/null; fi
LANGS=()
declare -A LANG_NAMES=()
DAT_FILES=(Settings.dat Preferences.dat Crafting.dat)

# ── Übersetzungen (generiert aus src/core.ps1 – eine Quelle für Windows und Linux) ──
declare -A TX
LANGS+=('de')
LANG_NAMES[de]='Deutsch'
TX[de:acct_line]='Account {0}  ({1} Konversationen)'
TX[de:act_backup]='Backup erstellen'
TX[de:act_backup_d]='RF4-Daten (Chats, Einstellungen, Screenshots) in einen Ordner sichern.'
TX[de:act_merge]='Installationen zusammenführen'
TX[de:act_merge_d]='Nachrichten aus anderen Installationen ergänzen – nichts wird überschrieben.'
TX[de:act_restore]='Backup wiederherstellen'
TX[de:act_restore_d]='Gesicherte Daten in eine RF4-Installation importieren. Nachrichten werden zusammengeführt.'
TX[de:act_sync]='Cloud / NAS Sync'
TX[de:act_sync_d]='Mailboxen zwischen PC, Laptop und NAS abgleichen (Nextcloud, Syncthing, Netzlaufwerk, USB).'
TX[de:all_accts]='Alle Accounts ({0})'
TX[de:app_title]='RF4 Backup & Migration'
TX[de:back]='Zurück'
TX[de:backup_dir]='Backup-Ordner'
TX[de:backup_dir_p]='Backup-Ordner [{0}] (Enter = Standard)'
TX[de:backup_done]='Backup fertig: {0}'
TX[de:bk_mailbox]='{0}: {1} Konversationen'
TX[de:bk_shots]='Screenshots: {0} Dateien'
TX[de:btn_browse]='Durchsuchen…'
TX[de:btn_close]='Schließen'
TX[de:btn_home]='Zum Start'
TX[de:btn_open]='Ordner öffnen'
TX[de:cancelled]='Abgebrochen.'
TX[de:choose]='Auswahl'
TX[de:contents]='Inhalt:'
TX[de:continue]='[Enter] zum Fortfahren'
TX[de:donate]='Spenden: paypal.me/bjoernoppermann'
TX[de:enter_path]='Pfad eingeben'
TX[de:exit]='Beenden'
TX[de:f_copied]='{0} kopiert'
TX[de:f_failed]='{0} fehlgeschlagen: {1}'
TX[de:f_identical]='{0} identisch, nichts zu tun'
TX[de:f_missing]='{0} nicht gefunden'
TX[de:f_overwritten]='{0} überschrieben'
TX[de:f_skipped]='{0} übersprungen'
TX[de:folder_missing]='Ordner nicht gefunden: {0}'
TX[de:found_n]='Gefunden: {0} Installation(en)'
TX[de:from]='Von: {0}'
TX[de:hash_click]='(Klicken zum Kopieren)'
TX[de:hash_copied]='SHA256-Prüfsumme kopiert:'
TX[de:hash_label]='SHA256: {0}…'
TX[de:hash_unknown]='SHA256: (Pfad unbekannt)'
TX[de:hdr_backup]='BACKUP'
TX[de:hdr_merge]='INSTALLATIONEN MERGEN'
TX[de:hdr_restore]='RESTORE / IMPORT'
TX[de:hdr_scan]='INSTALLATIONEN SCANNEN'
TX[de:hdr_sync]='CLOUD / NAS SYNC'
TX[de:importing_to]='Importiere nach: {0}'
TX[de:invalid]='Ungültige Eingabe'
TX[de:item_Crafting.dat]='Crafting.dat'
TX[de:item_mail]='Mailboxen (private Nachrichten)'
TX[de:item_Preferences.dat]='Preferences.dat'
TX[de:item_Settings.dat]='Settings.dat (Grafik/Audio/Tasten)'
TX[de:item_shots]='Screenshots'
TX[de:lang_changed]='Sprache geändert.'
TX[de:lang_prompt]='Sprache wählen'
TX[de:language]='Sprache'
TX[de:manual_path]='→ Pfad manuell eingeben'
TX[de:mb_header]='Mailbox {0}…'
TX[de:mb_merge_fail]='Merge fehlgeschlagen: {0} – {1}'
TX[de:mb_merge_file]='Merge {0}: +{1} Nachrichten'
TX[de:mb_summary]='Mailbox: {0} gemergt, {1} neu kopiert, {2} unverändert'
TX[de:menu_backup]='Backup – Daten sichern'
TX[de:menu_lang]='Sprache wechseln'
TX[de:menu_merge]='Merge – Installationen zusammenführen'
TX[de:menu_restore]='Restore – Aus Backup importieren'
TX[de:menu_scan]='Scan – Alle Installationen anzeigen'
TX[de:menu_sync]='Sync – Mit Cloud/NAS abgleichen'
TX[de:merge_done]='Merge abgeschlossen.'
TX[de:merge_dst]='Ziel (Hauptinstallation, bleibt erhalten)'
TX[de:merge_need2]='Mindestens 2 vorhandene Installationen nötig.'
TX[de:merge_nosrc]='Keine weiteren Installationen als Quellen verfügbar.'
TX[de:merge_note]='RF4 erlaubt nur den Wechsel Steam → Standalone, nicht umgekehrt. Details: https://nga.li/rf4transfer'
TX[de:merge_safe]='Nur fehlende Nachrichten werden ergänzt. Vorhandene Daten werden nicht überschrieben.'
TX[de:merge_same]='Quelle und Ziel dürfen nicht identisch sein.'
TX[de:merge_src]='Quellen (mehrere möglich)'
TX[de:merge_src_ctrl]='Quellen (Strg+Klick = Mehrfachauswahl)'
TX[de:merge_src_hdr]='Quelle: {0}'
TX[de:need_python]='python3 wird für das Zusammenführen der Nachrichten benötigt (Debian/Ubuntu: sudo apt install python3).'
TX[de:next]='Weiter'
TX[de:no_backup_here]='Kein RF4-Backup in diesem Ordner gefunden.'
TX[de:no_inst]='Keine Installationen gefunden.'
TX[de:no_mailboxes]='Keine Mailboxen gefunden.'
TX[de:no_path]='Kein Pfad angegeben.'
TX[de:none_found]='Keine Installationen gefunden.'
TX[de:nothing_sel]='Nichts ausgewählt.'
TX[de:pick_action]='Bitte eine Aktion wählen.'
TX[de:pick_backup]='Backup-Ordner wählen'
TX[de:pick_backup_d]='Wähle den Ordner, der dein RF4-Backup enthält.'
TX[de:pick_dst]='Bitte Ziel-Installation wählen.'
TX[de:pick_item]='Bitte mindestens eine Option wählen.'
TX[de:pick_one_src]='Bitte mindestens eine Quelle wählen.'
TX[de:pick_source]='Quelle wählen – von welcher Installation sichern?'
TX[de:pick_src]='Bitte eine Quelle wählen.'
TX[de:pick_target]='Ziel-Installation'
TX[de:restore_done]='Import abgeschlossen.'
TX[de:result_title]='Fertig'
TX[de:run_backup]='Backup starten'
TX[de:run_merge]='Merge starten'
TX[de:run_restore]='Restore starten'
TX[de:running_ask]='Trotzdem fortfahren?'
TX[de:running_warn]='RF4 scheint zu laufen ({0}). Bitte das Spiel VOR Restore/Merge/Sync beenden, sonst werden Änderungen überschrieben.'
TX[de:scan_accounts]='Account-IDs: {0}'
TX[de:scan_empty]='(noch nicht vorhanden)'
TX[de:scan_path]='Pfad: {0}'
TX[de:scan_readonly]='Sicher: Das Tool liest nur – Originaldaten werden nicht verändert.'
TX[de:scan_stats]='Mailboxen: {0}  Konversationen: {1}'
TX[de:scan_total]='Gesamt: {0} Pfade geprüft'
TX[de:scanning]='Suche auf allen Laufwerken…'
TX[de:shots_done]='Screenshots: {0} Bilder → {1}'
TX[de:shots_none]='Screenshot-Ordner nicht gefunden'
TX[de:step1]='Scan'
TX[de:step2]='Aktion'
TX[de:step3]='Auswahl'
TX[de:step4]='Ausführen'
TX[de:step5]='Ergebnis'
TX[de:sync_cfg]='Sync-Ordner konfigurieren'
TX[de:sync_dir_lbl]='Sync-Ordner:'
TX[de:sync_done]='Sync abgeschlossen!'
TX[de:sync_down]='{0} ← Sync (heruntergeladen)'
TX[de:sync_down_new]='{0} ← Sync (Sync neuer)'
TX[de:sync_enter]='Sync-Ordner eingeben (z.B. N:\RF4-Sync, D:\RF4-Sync):'
TX[de:sync_first]='Bitte zuerst den Sync-Ordner konfigurieren.'
TX[de:sync_hint]='Nextcloud-Ordner · NAS-Netzlaufwerk (N:\) · Syncthing-Ordner · USB-Stick'
TX[de:sync_inst_lbl]='Installation:'
TX[de:sync_intro]='Ordnerbasierter Sync – Nextcloud, NAS-Laufwerk, Syncthing, USB, OneDrive.'
TX[de:sync_local]='Lokal:  {0}'
TX[de:sync_mkfail]='Ordner konnte nicht erstellt werden: {0}'
TX[de:sync_nolocal]='Keine lokalen Mailboxen – nur Download wird ausgeführt.'
TX[de:sync_none]='Kein Sync-Ordner konfiguriert.'
TX[de:sync_noremote]='Der Sync-Ordner enthält noch keine Mailboxen anderer Geräte.'
TX[de:sync_ok]='Sync-Ordner: {0}'
TX[de:sync_p1]='Phase 1: Lokal → Sync (neue Nachrichten hochladen)'
TX[de:sync_p2]='Phase 2: Sync → Lokal (neue Nachrichten herunterladen)'
TX[de:sync_p3]='Einstellungen (neuere Version gewinnt)'
TX[de:sync_pick_dir]='Sync-Ordner wählen (z.B. Nextcloud-Ordner oder NAS-Laufwerk)'
TX[de:sync_remote]='Sync:   {0}'
TX[de:sync_run]='Sync jetzt ausführen (bidirektional)'
TX[de:sync_same]='{0}: identisch, übersprungen'
TX[de:sync_saved]='Gespeichert: {0}'
TX[de:sync_st_boxes]='{0}: {1} Konversationen'
TX[de:sync_st_log]='Letzte Sync-Einträge:'
TX[de:sync_st_nodir]='Noch kein RF4_Sync-Unterordner. Bitte zuerst einen Sync ausführen.'
TX[de:sync_st_none]='Noch keine Mailboxen im Sync-Ordner.'
TX[de:sync_status]='Sync-Status anzeigen'
TX[de:sync_unreach]='Sync-Ordner nicht erreichbar: {0}'
TX[de:sync_unreach_h]='NAS eingebunden? Cloud-Sync aktiv? USB angesteckt?'
TX[de:sync_up]='{0} → Sync (hochgeladen)'
TX[de:sync_up_new]='{0} → Sync (lokal neuer)'
TX[de:sync_which]='Welche Installation synchronisieren?'
TX[de:to]='Nach: {0}'
TX[de:toggle_hint]='(Nummer = ein/aus, a = alle, n = keine, Enter = OK, 0 = Zurück)'
TX[de:undo_saved]='Ersetzte Dateien gesichert in: {0}'
TX[de:usage]='Aufruf: rf4sa-backup.sh [-l de|en|zh|ru]'
TX[de:v_DE]='RF4 Standalone Deutsch'
TX[de:v_DE_new]='RF4 Standalone Deutsch (neu)'
TX[de:v_EN]='RF4 Standalone Englisch'
TX[de:v_Other]='RF4 ({0})'
TX[de:v_Steam]='RF4 Steam'
TX[de:w_drive]='Laufwerk: {0} / {1}'
TX[de:w_extra]='Pfad: {0}'
TX[de:w_proton]='Proton: AppID {0}'
TX[de:w_user]='Benutzer: {0}'
TX[de:w_win]='Windows: {0} / {1}'
TX[de:w_wine]='Wine: {0}'
TX[de:what_backup]='Was soll gesichert werden?'
TX[de:what_restore]='Was soll importiert werden?'
TX[de:what_todo]='Was möchtest du tun?'
TX[de:which_acct_b]='Welchen Account sichern?'
TX[de:which_acct_m]='Welche Accounts aus dieser Quelle mergen?'
TX[de:which_acct_r]='Welchen Account importieren?'
TX[de:working]='Bitte warten…'
TX[de:yes_char]='j'
TX[de:yn_overwrite]='{0} existiert bereits. Überschreiben? [j/N]'
TX[de:overwrite_q]='{0} existiert bereits.{1}Überschreiben?'
TX[de:sel_account]='Account:'
TX[de:scan_hint]='Das Tool sucht automatisch auf allen Laufwerken nach RF4-Installationen.'
TX[de:rescan]='Neu suchen'
TX[de:target_none]='Keine passende Ziel-Installation vorhanden.'
TX[de:backup_to]='Backup-Zielordner'
TX[de:preview]='Inhalt des Backups:'
TX[de:undo_hint]='Ersetzte Dateien werden vorher nach _rf4tool_undo kopiert.'
TX[de:theme_label]='Design'
TX[de:theme_auto]='Automatisch (wie Windows)'
TX[de:tip_lang]='Sprache ändern'
TX[de:tip_theme]='Design ändern'
TX[de:bk_mailbox_n]='{0} Mailboxen · {1} Konversationen'
TX[de:bk_files_n]='Einstellungsdateien: {0}'
TX[de:bk_shots_n]='Screenshots: {0}'
TX[de:existing_backups]='Vorhandene Backups'
TX[de:no_existing_backups]='Noch keine Backups gefunden – wähle einen Ordner.'
TX[de:other_folder]='Anderen Ordner wählen…'
TX[de:last_change]='Zuletzt geändert: {0}'
TX[de:chip_found]='vorhanden'
TX[de:chip_missing]='nicht vorhanden'
TX[de:convs_short]='Konversationen'
TX[de:sum_msgs]='Nachrichten übertragen'
TX[de:sum_convs]='Konversationen'
TX[de:sum_files]='Dateien kopiert'
TX[de:sum_shots]='Screenshots'
TX[de:sum_skipped]='übersprungen'
TX[de:sum_failed]='Fehler'
TX[de:show_details]='Details anzeigen'
TX[de:hide_details]='Details ausblenden'
TX[de:res_ok]='Fertig – ohne Fehler.'
TX[de:res_err]='Abgeschlossen, aber mit {0} Fehler(n). Details ansehen.'
TX[de:working_title]='Bitte nicht schließen – das kann einen Moment dauern.'
TX[de:btn_done]='Fertig'
TX[de:btn_start_over]='Neue Aktion'
TX[de:hdr_scan_t]='Installationen'
TX[de:hdr_action_t]='Was möchtest du tun?'
TX[de:hdr_backup_t]='Backup erstellen'
TX[de:hdr_restore_t]='Backup wiederherstellen'
TX[de:hdr_merge_t]='Installationen zusammenführen'
TX[de:hdr_sync_t]='Cloud / NAS Sync'
TX[de:to_target]='Ziel'
TX[de:no_backup_found_cli]='Keine Backups in den üblichen Ordnern – Pfad eingeben.'
TX[de:pick_backup_list]='Backup wählen'
TX[de:theme_name_dark]='Dunkel (Marine)'
TX[de:theme_name_light]='Hell'
TX[de:open_folder_tip]='Öffnet den Ordner im Explorer'
TX[de:accounts_all]='Alle Accounts'
TX[de:tip_card_select]='Zum Auswählen anklicken'
TX[de:select_backup_first]='Bitte zuerst ein Backup wählen.'
TX[de:sync_run_btn]='Sync starten'
TX[de:sync_status_btn]='Status anzeigen'
TX[de:dialog_yes]='Ja'
TX[de:dialog_no]='Nein'
TX[de:dialog_ok]='OK'
TX[de:err_unexpected]='Ein unerwarteter Fehler ist aufgetreten. Das Programm läuft weiter, es wurde nichts gelöscht.'
TX[de:err_logged]='Details: {0}'
TX[de:bk_source]='Quelle: {0}'
TX[de:bk_source_unknown]='Quelle: unbekannt (Backup ohne Info-Datei)'
TX[de:bk_from_pc]='(PC {0})'
TX[de:bk_dates]='Erstellt: {0}   ·   Aktualisiert: {1}'
TX[de:bk_existing_here]='Hier liegt schon ein Backup. {0}'
TX[de:bk_source_sync]='Quelle: gemeinsamer Sync-Ordner – zuletzt abgeglichen von PC {0} am {1}'
TX[de:bk_source_sync_unknown]='Quelle: gemeinsamer Sync-Ordner (noch keine Sync-Einträge)'
TX[de:bk_sync_hint]='Gemeinsamer Ordner aller Geräte – Restore holt den abgeglichenen Stand von dort.'
TX[de:bk_badge_sync]='Sync'
TX[de:menu_help]='Hilfe / Anleitung'
TX[de:help_btn]='Hilfe'
TX[de:tip_help]='Anleitung mit Screenshots in deiner Sprache öffnen'
TX[de:restore_path_bad]='Dort wurde kein Backup gefunden (auch nicht im Unterordner RF4_Sync). Ordner nicht erreichbar?'
LANGS+=('en')
LANG_NAMES[en]='English'
TX[en:acct_line]='Account {0}  ({1} conversations)'
TX[en:act_backup]='Create backup'
TX[en:act_backup_d]='Save RF4 data (chats, settings, screenshots) to a folder.'
TX[en:act_merge]='Merge installations'
TX[en:act_merge_d]='Add messages from other installations – nothing is overwritten.'
TX[en:act_restore]='Restore backup'
TX[en:act_restore_d]='Import saved data into an RF4 installation. Messages are merged.'
TX[en:act_sync]='Cloud / NAS sync'
TX[en:act_sync_d]='Sync mailboxes between PC, laptop and NAS (Nextcloud, Syncthing, network drive, USB).'
TX[en:all_accts]='All accounts ({0})'
TX[en:app_title]='RF4 Backup & Migration'
TX[en:back]='Back'
TX[en:backup_dir]='Backup folder'
TX[en:backup_dir_p]='Backup folder [{0}] (Enter = default)'
TX[en:backup_done]='Backup finished: {0}'
TX[en:bk_mailbox]='{0}: {1} conversations'
TX[en:bk_shots]='Screenshots: {0} files'
TX[en:btn_browse]='Browse…'
TX[en:btn_close]='Close'
TX[en:btn_home]='Back to start'
TX[en:btn_open]='Open folder'
TX[en:cancelled]='Cancelled.'
TX[en:choose]='Choice'
TX[en:contents]='Contents:'
TX[en:continue]='[Enter] to continue'
TX[en:donate]='Donate: paypal.me/bjoernoppermann'
TX[en:enter_path]='Enter path'
TX[en:exit]='Exit'
TX[en:f_copied]='{0} copied'
TX[en:f_failed]='{0} failed: {1}'
TX[en:f_identical]='{0} identical, nothing to do'
TX[en:f_missing]='{0} not found'
TX[en:f_overwritten]='{0} overwritten'
TX[en:f_skipped]='{0} skipped'
TX[en:folder_missing]='Folder not found: {0}'
TX[en:found_n]='Found: {0} installation(s)'
TX[en:from]='From: {0}'
TX[en:hash_click]='(click to copy)'
TX[en:hash_copied]='SHA256 checksum copied:'
TX[en:hash_label]='SHA256: {0}…'
TX[en:hash_unknown]='SHA256: (path unknown)'
TX[en:hdr_backup]='BACKUP'
TX[en:hdr_merge]='MERGE INSTALLATIONS'
TX[en:hdr_restore]='RESTORE / IMPORT'
TX[en:hdr_scan]='SCAN INSTALLATIONS'
TX[en:hdr_sync]='CLOUD / NAS SYNC'
TX[en:importing_to]='Importing to: {0}'
TX[en:invalid]='Invalid input'
TX[en:item_Crafting.dat]='Crafting.dat'
TX[en:item_mail]='Mailboxes (private messages)'
TX[en:item_Preferences.dat]='Preferences.dat'
TX[en:item_Settings.dat]='Settings.dat (graphics/audio/keys)'
TX[en:item_shots]='Screenshots'
TX[en:lang_changed]='Language changed.'
TX[en:lang_prompt]='Choose language'
TX[en:language]='Language'
TX[en:manual_path]='→ Enter path manually'
TX[en:mb_header]='Mailbox {0}…'
TX[en:mb_merge_fail]='Merge failed: {0} – {1}'
TX[en:mb_merge_file]='Merge {0}: +{1} messages'
TX[en:mb_summary]='Mailbox: {0} merged, {1} newly copied, {2} unchanged'
TX[en:menu_backup]='Backup – Save data to a folder'
TX[en:menu_lang]='Change language'
TX[en:menu_merge]='Merge – Combine installations'
TX[en:menu_restore]='Restore – Import from a backup'
TX[en:menu_scan]='Scan – Show all installations'
TX[en:menu_sync]='Sync – Synchronize with cloud/NAS'
TX[en:merge_done]='Merge finished.'
TX[en:merge_dst]='Target (main installation, is kept)'
TX[en:merge_need2]='At least 2 existing installations are required.'
TX[en:merge_nosrc]='No other installations available as sources.'
TX[en:merge_note]='RF4 only allows switching Steam → Standalone, not the other way round. Details: https://nga.li/rf4transfer'
TX[en:merge_safe]='Only missing messages are added. Existing data is not overwritten.'
TX[en:merge_same]='Source and target must not be the same.'
TX[en:merge_src]='Sources (multiple allowed)'
TX[en:merge_src_ctrl]='Sources (Ctrl+click = multi-select)'
TX[en:merge_src_hdr]='Source: {0}'
TX[en:need_python]='python3 is required to merge messages (Debian/Ubuntu: sudo apt install python3).'
TX[en:next]='Next'
TX[en:no_backup_here]='No RF4 backup found in this folder.'
TX[en:no_inst]='No installations found.'
TX[en:no_mailboxes]='No mailboxes found.'
TX[en:no_path]='No path given.'
TX[en:none_found]='No installations found.'
TX[en:nothing_sel]='Nothing selected.'
TX[en:pick_action]='Please select an action.'
TX[en:pick_backup]='Choose backup folder'
TX[en:pick_backup_d]='Choose the folder that contains your RF4 backup.'
TX[en:pick_dst]='Please select a target installation.'
TX[en:pick_item]='Please select at least one option.'
TX[en:pick_one_src]='Please select at least one source.'
TX[en:pick_source]='Choose source – back up which installation?'
TX[en:pick_src]='Please select a source.'
TX[en:pick_target]='Target installation'
TX[en:restore_done]='Import finished.'
TX[en:result_title]='Done'
TX[en:run_backup]='Start backup'
TX[en:run_merge]='Start merge'
TX[en:run_restore]='Start restore'
TX[en:running_ask]='Continue anyway?'
TX[en:running_warn]='RF4 seems to be running ({0}). Please close the game BEFORE restore/merge/sync, otherwise changes get overwritten.'
TX[en:scan_accounts]='Account IDs: {0}'
TX[en:scan_empty]='(not present yet)'
TX[en:scan_path]='Path: {0}'
TX[en:scan_readonly]='Safe: the tool only reads – original data is not modified.'
TX[en:scan_stats]='Mailboxes: {0}  Conversations: {1}'
TX[en:scan_total]='Total: {0} paths checked'
TX[en:scanning]='Searching all drives…'
TX[en:shots_done]='Screenshots: {0} images → {1}'
TX[en:shots_none]='Screenshot folder not found'
TX[en:step1]='Scan'
TX[en:step2]='Action'
TX[en:step3]='Selection'
TX[en:step4]='Run'
TX[en:step5]='Result'
TX[en:sync_cfg]='Configure sync folder'
TX[en:sync_dir_lbl]='Sync folder:'
TX[en:sync_done]='Sync finished!'
TX[en:sync_down]='{0} ← sync (downloaded)'
TX[en:sync_down_new]='{0} ← sync (sync is newer)'
TX[en:sync_enter]='Enter sync folder (e.g. N:\RF4-Sync, D:\RF4-Sync):'
TX[en:sync_first]='Please configure the sync folder first.'
TX[en:sync_hint]='Nextcloud folder · NAS network drive (N:\) · Syncthing folder · USB stick'
TX[en:sync_inst_lbl]='Installation:'
TX[en:sync_intro]='Folder-based sync – Nextcloud, NAS drive, Syncthing, USB, OneDrive.'
TX[en:sync_local]='Local:  {0}'
TX[en:sync_mkfail]='Folder could not be created: {0}'
TX[en:sync_nolocal]='No local mailboxes – download only.'
TX[en:sync_none]='No sync folder configured.'
TX[en:sync_noremote]='The sync folder has no mailboxes from other devices yet.'
TX[en:sync_ok]='Sync folder: {0}'
TX[en:sync_p1]='Phase 1: local → sync (upload new messages)'
TX[en:sync_p2]='Phase 2: sync → local (download new messages)'
TX[en:sync_p3]='Settings (newer version wins)'
TX[en:sync_pick_dir]='Choose sync folder (e.g. Nextcloud folder or NAS drive)'
TX[en:sync_remote]='Sync:   {0}'
TX[en:sync_run]='Run sync now (bidirectional)'
TX[en:sync_same]='{0}: identical, skipped'
TX[en:sync_saved]='Saved: {0}'
TX[en:sync_st_boxes]='{0}: {1} conversations'
TX[en:sync_st_log]='Recent sync entries:'
TX[en:sync_st_nodir]='No RF4_Sync subfolder yet. Please run a sync first.'
TX[en:sync_st_none]='No mailboxes in the sync folder yet.'
TX[en:sync_status]='Show sync status'
TX[en:sync_unreach]='Sync folder not reachable: {0}'
TX[en:sync_unreach_h]='NAS mounted? Cloud sync running? USB plugged in?'
TX[en:sync_up]='{0} → sync (uploaded)'
TX[en:sync_up_new]='{0} → sync (local is newer)'
TX[en:sync_which]='Which installation to sync?'
TX[en:to]='To: {0}'
TX[en:toggle_hint]='(number = toggle, a = all, n = none, Enter = OK, 0 = back)'
TX[en:undo_saved]='Replaced files saved in: {0}'
TX[en:usage]='Usage: rf4sa-backup.sh [-l de|en|zh|ru]'
TX[en:v_DE]='RF4 Standalone German'
TX[en:v_DE_new]='RF4 Standalone German (new)'
TX[en:v_EN]='RF4 Standalone English'
TX[en:v_Other]='RF4 ({0})'
TX[en:v_Steam]='RF4 Steam'
TX[en:w_drive]='Drive: {0} / {1}'
TX[en:w_extra]='Path: {0}'
TX[en:w_proton]='Proton: AppID {0}'
TX[en:w_user]='User: {0}'
TX[en:w_win]='Windows: {0} / {1}'
TX[en:w_wine]='Wine: {0}'
TX[en:what_backup]='What should be backed up?'
TX[en:what_restore]='What should be imported?'
TX[en:what_todo]='What would you like to do?'
TX[en:which_acct_b]='Which account to back up?'
TX[en:which_acct_m]='Which accounts to merge from this source?'
TX[en:which_acct_r]='Which account to import?'
TX[en:working]='Please wait…'
TX[en:yes_char]='y'
TX[en:yn_overwrite]='{0} already exists. Overwrite? [y/N]'
TX[en:overwrite_q]='{0} already exists.{1}Overwrite?'
TX[en:sel_account]='Account:'
TX[en:scan_hint]='The tool automatically searches all drives for RF4 installations.'
TX[en:rescan]='Rescan'
TX[en:target_none]='No suitable target installation available.'
TX[en:backup_to]='Backup target folder'
TX[en:preview]='Backup contents:'
TX[en:undo_hint]='Files that get replaced are copied to _rf4tool_undo first.'
TX[en:theme_label]='Theme'
TX[en:theme_auto]='Automatic (like Windows)'
TX[en:tip_lang]='Change language'
TX[en:tip_theme]='Change theme'
TX[en:bk_mailbox_n]='{0} mailboxes · {1} conversations'
TX[en:bk_files_n]='settings files: {0}'
TX[en:bk_shots_n]='screenshots: {0}'
TX[en:existing_backups]='Existing backups'
TX[en:no_existing_backups]='No backups found yet – choose a folder.'
TX[en:other_folder]='Choose another folder…'
TX[en:last_change]='Last changed: {0}'
TX[en:chip_found]='found'
TX[en:chip_missing]='not present'
TX[en:convs_short]='conversations'
TX[en:sum_msgs]='messages transferred'
TX[en:sum_convs]='conversations'
TX[en:sum_files]='files copied'
TX[en:sum_shots]='screenshots'
TX[en:sum_skipped]='skipped'
TX[en:sum_failed]='errors'
TX[en:show_details]='Show details'
TX[en:hide_details]='Hide details'
TX[en:res_ok]='Done – no errors.'
TX[en:res_err]='Finished, but with {0} error(s). See details.'
TX[en:working_title]='Please do not close – this may take a moment.'
TX[en:btn_done]='Done'
TX[en:btn_start_over]='New action'
TX[en:hdr_scan_t]='Installations'
TX[en:hdr_action_t]='What would you like to do?'
TX[en:hdr_backup_t]='Create backup'
TX[en:hdr_restore_t]='Restore backup'
TX[en:hdr_merge_t]='Merge installations'
TX[en:hdr_sync_t]='Cloud / NAS sync'
TX[en:to_target]='Target'
TX[en:no_backup_found_cli]='No backups in the usual folders – enter a path.'
TX[en:pick_backup_list]='Choose a backup'
TX[en:theme_name_dark]='Dark (navy)'
TX[en:theme_name_light]='Light'
TX[en:open_folder_tip]='Opens the folder in Explorer'
TX[en:accounts_all]='All accounts'
TX[en:tip_card_select]='Click to select'
TX[en:select_backup_first]='Please choose a backup first.'
TX[en:sync_run_btn]='Start sync'
TX[en:sync_status_btn]='Show status'
TX[en:dialog_yes]='Yes'
TX[en:dialog_no]='No'
TX[en:dialog_ok]='OK'
TX[en:err_unexpected]='An unexpected error occurred. The program keeps running; nothing was deleted.'
TX[en:err_logged]='Details: {0}'
TX[en:bk_source]='Source: {0}'
TX[en:bk_source_unknown]='Source: unknown (backup without info file)'
TX[en:bk_from_pc]='(PC {0})'
TX[en:bk_dates]='Created: {0}   ·   Updated: {1}'
TX[en:bk_existing_here]='There is already a backup here. {0}'
TX[en:bk_source_sync]='Source: shared sync folder – last synced by PC {0} on {1}'
TX[en:bk_source_sync_unknown]='Source: shared sync folder (no sync entries yet)'
TX[en:bk_sync_hint]='Shared folder of all devices – restore pulls the synced state from here.'
TX[en:bk_badge_sync]='Sync'
TX[en:menu_help]='Help / guide'
TX[en:help_btn]='Help'
TX[en:tip_help]='Open the guide with screenshots in your language'
TX[en:restore_path_bad]='No backup found there (not in a RF4_Sync subfolder either). Folder not reachable?'
LANGS+=('zh')
LANG_NAMES[zh]='中文'
TX[zh:acct_line]='账号 {0}  ({1} 个对话)'
TX[zh:act_backup]='创建备份'
TX[zh:act_backup_d]='将 RF4 数据（聊天、设置、截图）保存到文件夹。'
TX[zh:act_merge]='合并安装'
TX[zh:act_merge_d]='从其他安装补充消息——不会覆盖任何内容。'
TX[zh:act_restore]='恢复备份'
TX[zh:act_restore_d]='将已保存的数据导入 RF4 安装。消息会被合并。'
TX[zh:act_sync]='云 / NAS 同步'
TX[zh:act_sync_d]='在电脑、笔记本和 NAS 之间同步邮箱（Nextcloud、Syncthing、网络驱动器、USB）。'
TX[zh:all_accts]='所有账号 ({0})'
TX[zh:app_title]='RF4 备份与迁移'
TX[zh:back]='返回'
TX[zh:backup_dir]='备份文件夹'
TX[zh:backup_dir_p]='备份文件夹 [{0}]（Enter = 默认）'
TX[zh:backup_done]='备份完成: {0}'
TX[zh:bk_mailbox]='{0}: {1} 个对话'
TX[zh:bk_shots]='截图: {0} 个文件'
TX[zh:btn_browse]='浏览…'
TX[zh:btn_close]='关闭'
TX[zh:btn_home]='返回开始'
TX[zh:btn_open]='打开文件夹'
TX[zh:cancelled]='已取消。'
TX[zh:choose]='选择'
TX[zh:contents]='内容:'
TX[zh:continue]='按 [Enter] 继续'
TX[zh:donate]='捐赠: paypal.me/bjoernoppermann'
TX[zh:enter_path]='输入路径'
TX[zh:exit]='退出'
TX[zh:f_copied]='{0} 已复制'
TX[zh:f_failed]='{0} 失败: {1}'
TX[zh:f_identical]='{0} 相同，无需处理'
TX[zh:f_missing]='未找到 {0}'
TX[zh:f_overwritten]='{0} 已覆盖'
TX[zh:f_skipped]='{0} 已跳过'
TX[zh:folder_missing]='未找到文件夹: {0}'
TX[zh:found_n]='已找到：{0} 个安装'
TX[zh:from]='来源: {0}'
TX[zh:hash_click]='（点击复制）'
TX[zh:hash_copied]='SHA256 校验和已复制:'
TX[zh:hash_label]='SHA256: {0}…'
TX[zh:hash_unknown]='SHA256: （路径未知）'
TX[zh:hdr_backup]='备份'
TX[zh:hdr_merge]='合并安装'
TX[zh:hdr_restore]='恢复 / 导入'
TX[zh:hdr_scan]='扫描安装'
TX[zh:hdr_sync]='云 / NAS 同步'
TX[zh:importing_to]='正在导入到: {0}'
TX[zh:invalid]='输入无效'
TX[zh:item_Crafting.dat]='Crafting.dat'
TX[zh:item_mail]='邮箱（私人消息）'
TX[zh:item_Preferences.dat]='Preferences.dat'
TX[zh:item_Settings.dat]='Settings.dat（画面/音频/按键）'
TX[zh:item_shots]='截图'
TX[zh:lang_changed]='语言已更改。'
TX[zh:lang_prompt]='选择语言'
TX[zh:language]='语言'
TX[zh:manual_path]='→ 手动输入路径'
TX[zh:mb_header]='邮箱 {0}…'
TX[zh:mb_merge_fail]='合并失败: {0} – {1}'
TX[zh:mb_merge_file]='合并 {0}: +{1} 条消息'
TX[zh:mb_summary]='邮箱: {0} 个已合并, {1} 个新复制, {2} 个未变化'
TX[zh:menu_backup]='备份 – 将数据保存到文件夹'
TX[zh:menu_lang]='切换语言'
TX[zh:menu_merge]='合并 – 合并多个安装'
TX[zh:menu_restore]='恢复 – 从备份导入'
TX[zh:menu_scan]='扫描 – 显示所有安装'
TX[zh:menu_sync]='同步 – 与云/NAS同步'
TX[zh:merge_done]='合并完成。'
TX[zh:merge_dst]='目标（主安装，将保留）'
TX[zh:merge_need2]='至少需要 2 个现有安装。'
TX[zh:merge_nosrc]='没有其他可用作来源的安装。'
TX[zh:merge_note]='RF4 只允许从 Steam 切换到独立版，反之不行。详情: https://nga.li/rf4transfer'
TX[zh:merge_safe]='仅补充缺失的消息，不会覆盖现有数据。'
TX[zh:merge_same]='来源和目标不能相同。'
TX[zh:merge_src]='来源（可多选）'
TX[zh:merge_src_ctrl]='来源（Ctrl+点击 = 多选）'
TX[zh:merge_src_hdr]='来源: {0}'
TX[zh:need_python]='合并消息需要 python3（Debian/Ubuntu: sudo apt install python3）。'
TX[zh:next]='下一步'
TX[zh:no_backup_here]='该文件夹中没有 RF4 备份。'
TX[zh:no_inst]='未找到安装。'
TX[zh:no_mailboxes]='未找到邮箱。'
TX[zh:no_path]='未提供路径。'
TX[zh:none_found]='未找到安装。'
TX[zh:nothing_sel]='未选择任何内容。'
TX[zh:pick_action]='请选择一个操作。'
TX[zh:pick_backup]='选择备份文件夹'
TX[zh:pick_backup_d]='请选择包含 RF4 备份的文件夹。'
TX[zh:pick_dst]='请选择目标安装。'
TX[zh:pick_item]='请至少选择一项。'
TX[zh:pick_one_src]='请至少选择一个来源。'
TX[zh:pick_source]='选择来源——备份哪个安装？'
TX[zh:pick_src]='请选择来源。'
TX[zh:pick_target]='目标安装'
TX[zh:restore_done]='导入完成。'
TX[zh:result_title]='完成'
TX[zh:run_backup]='开始备份'
TX[zh:run_merge]='开始合并'
TX[zh:run_restore]='开始恢复'
TX[zh:running_ask]='仍要继续吗？'
TX[zh:running_warn]='检测到 RF4 正在运行 ({0})。请在恢复/合并/同步之前关闭游戏，否则更改会被覆盖。'
TX[zh:scan_accounts]='账号 ID: {0}'
TX[zh:scan_empty]='(尚不存在)'
TX[zh:scan_path]='路径: {0}'
TX[zh:scan_readonly]='安全：本工具只读取，不会修改原始数据。'
TX[zh:scan_stats]='邮箱: {0}  对话: {1}'
TX[zh:scan_total]='共检查 {0} 个路径'
TX[zh:scanning]='正在搜索所有驱动器…'
TX[zh:shots_done]='截图: {0} 张 → {1}'
TX[zh:shots_none]='未找到截图文件夹'
TX[zh:step1]='扫描'
TX[zh:step2]='操作'
TX[zh:step3]='选择'
TX[zh:step4]='执行'
TX[zh:step5]='结果'
TX[zh:sync_cfg]='配置同步文件夹'
TX[zh:sync_dir_lbl]='同步文件夹:'
TX[zh:sync_done]='同步完成！'
TX[zh:sync_down]='{0} ← 同步（已下载）'
TX[zh:sync_down_new]='{0} ← 同步（同步版较新）'
TX[zh:sync_enter]='输入同步文件夹（例如 N:\RF4-Sync, D:\RF4-Sync）:'
TX[zh:sync_first]='请先配置同步文件夹。'
TX[zh:sync_hint]='Nextcloud 文件夹 · NAS 网络驱动器 (N:\) · Syncthing 文件夹 · U 盘'
TX[zh:sync_inst_lbl]='安装:'
TX[zh:sync_intro]='基于文件夹的同步——Nextcloud、NAS 驱动器、Syncthing、USB、OneDrive。'
TX[zh:sync_local]='本地:  {0}'
TX[zh:sync_mkfail]='无法创建文件夹: {0}'
TX[zh:sync_nolocal]='没有本地邮箱——仅执行下载。'
TX[zh:sync_none]='尚未配置同步文件夹。'
TX[zh:sync_noremote]='同步文件夹中还没有来自其他设备的邮箱。'
TX[zh:sync_ok]='同步文件夹: {0}'
TX[zh:sync_p1]='阶段 1：本地 → 同步（上传新消息）'
TX[zh:sync_p2]='阶段 2：同步 → 本地（下载新消息）'
TX[zh:sync_p3]='设置（以较新版本为准）'
TX[zh:sync_pick_dir]='选择同步文件夹（例如 Nextcloud 文件夹或 NAS 驱动器）'
TX[zh:sync_remote]='同步:   {0}'
TX[zh:sync_run]='立即同步（双向）'
TX[zh:sync_same]='{0}: 相同，已跳过'
TX[zh:sync_saved]='已保存: {0}'
TX[zh:sync_st_boxes]='{0}: {1} 个对话'
TX[zh:sync_st_log]='最近的同步记录:'
TX[zh:sync_st_nodir]='还没有 RF4_Sync 子文件夹。请先执行一次同步。'
TX[zh:sync_st_none]='同步文件夹中还没有邮箱。'
TX[zh:sync_status]='显示同步状态'
TX[zh:sync_unreach]='无法访问同步文件夹: {0}'
TX[zh:sync_unreach_h]='NAS 已挂载？云同步已启动？U 盘已插入？'
TX[zh:sync_up]='{0} → 同步（已上传）'
TX[zh:sync_up_new]='{0} → 同步（本地较新）'
TX[zh:sync_which]='同步哪个安装？'
TX[zh:to]='目标: {0}'
TX[zh:toggle_hint]='(数字 = 切换, a = 全选, n = 全不选, Enter = 确定, 0 = 返回)'
TX[zh:undo_saved]='被替换的文件已保存到: {0}'
TX[zh:usage]='用法: rf4sa-backup.sh [-l de|en|zh|ru]'
TX[zh:v_DE]='RF4 独立版（德语）'
TX[zh:v_DE_new]='RF4 独立版（德语，新）'
TX[zh:v_EN]='RF4 独立版（英语）'
TX[zh:v_Other]='RF4 ({0})'
TX[zh:v_Steam]='RF4 Steam 版'
TX[zh:w_drive]='驱动器: {0} / {1}'
TX[zh:w_extra]='路径: {0}'
TX[zh:w_proton]='Proton: AppID {0}'
TX[zh:w_user]='用户: {0}'
TX[zh:w_win]='Windows: {0} / {1}'
TX[zh:w_wine]='Wine: {0}'
TX[zh:what_backup]='要备份什么？'
TX[zh:what_restore]='要导入什么？'
TX[zh:what_todo]='您想做什么？'
TX[zh:which_acct_b]='备份哪个账号？'
TX[zh:which_acct_m]='从该来源合并哪些账号？'
TX[zh:which_acct_r]='导入哪个账号？'
TX[zh:working]='请稍候…'
TX[zh:yes_char]='y'
TX[zh:yn_overwrite]='{0} 已存在。是否覆盖？[y/N]'
TX[zh:overwrite_q]='{0} 已存在。{1}是否覆盖？'
TX[zh:sel_account]='账号:'
TX[zh:scan_hint]='本工具会自动在所有驱动器上搜索 RF4 安装。'
TX[zh:rescan]='重新扫描'
TX[zh:target_none]='没有合适的目标安装。'
TX[zh:backup_to]='备份目标文件夹'
TX[zh:preview]='备份内容:'
TX[zh:undo_hint]='被替换的文件会先复制到 _rf4tool_undo。'
TX[zh:theme_label]='外观'
TX[zh:theme_auto]='自动（跟随 Windows）'
TX[zh:tip_lang]='切换语言'
TX[zh:tip_theme]='切换外观'
TX[zh:bk_mailbox_n]='{0} 个邮箱 · {1} 个对话'
TX[zh:bk_files_n]='设置文件: {0}'
TX[zh:bk_shots_n]='截图: {0}'
TX[zh:existing_backups]='现有备份'
TX[zh:no_existing_backups]='尚未找到备份——请选择一个文件夹。'
TX[zh:other_folder]='选择其他文件夹…'
TX[zh:last_change]='最后修改: {0}'
TX[zh:chip_found]='已找到'
TX[zh:chip_missing]='不存在'
TX[zh:convs_short]='对话'
TX[zh:sum_msgs]='条消息已传输'
TX[zh:sum_convs]='个对话'
TX[zh:sum_files]='个文件已复制'
TX[zh:sum_shots]='张截图'
TX[zh:sum_skipped]='已跳过'
TX[zh:sum_failed]='个错误'
TX[zh:show_details]='显示详情'
TX[zh:hide_details]='隐藏详情'
TX[zh:res_ok]='完成——没有错误。'
TX[zh:res_err]='已完成，但有 {0} 个错误。请查看详情。'
TX[zh:working_title]='请勿关闭——这可能需要一点时间。'
TX[zh:btn_done]='完成'
TX[zh:btn_start_over]='新操作'
TX[zh:hdr_scan_t]='安装'
TX[zh:hdr_action_t]='您想做什么？'
TX[zh:hdr_backup_t]='创建备份'
TX[zh:hdr_restore_t]='恢复备份'
TX[zh:hdr_merge_t]='合并安装'
TX[zh:hdr_sync_t]='云 / NAS 同步'
TX[zh:to_target]='目标'
TX[zh:no_backup_found_cli]='常用文件夹中没有备份——请输入路径。'
TX[zh:pick_backup_list]='选择备份'
TX[zh:theme_name_dark]='深色（海军蓝）'
TX[zh:theme_name_light]='浅色'
TX[zh:open_folder_tip]='在资源管理器中打开文件夹'
TX[zh:accounts_all]='所有账号'
TX[zh:tip_card_select]='点击选择'
TX[zh:select_backup_first]='请先选择一个备份。'
TX[zh:sync_run_btn]='开始同步'
TX[zh:sync_status_btn]='显示状态'
TX[zh:dialog_yes]='是'
TX[zh:dialog_no]='否'
TX[zh:dialog_ok]='确定'
TX[zh:err_unexpected]='发生意外错误。程序继续运行，没有删除任何内容。'
TX[zh:err_logged]='详情: {0}'
TX[zh:bk_source]='来源: {0}'
TX[zh:bk_source_unknown]='来源: 未知（备份没有信息文件）'
TX[zh:bk_from_pc]='（电脑 {0}）'
TX[zh:bk_dates]='创建: {0}   ·   更新: {1}'
TX[zh:bk_existing_here]='此处已有备份。{0}'
TX[zh:bk_source_sync]='来源: 共享同步文件夹 – 最后由电脑 {0} 于 {1} 同步'
TX[zh:bk_source_sync_unknown]='来源: 共享同步文件夹（尚无同步记录）'
TX[zh:bk_sync_hint]='所有设备共用的文件夹——恢复会从这里取回已同步的内容。'
TX[zh:bk_badge_sync]='同步'
TX[zh:menu_help]='帮助 / 指南'
TX[zh:help_btn]='帮助'
TX[zh:tip_help]='用您的语言打开带截图的指南'
TX[zh:restore_path_bad]='在那里没有找到备份（RF4_Sync 子文件夹中也没有）。文件夹无法访问？'
LANGS+=('ru')
LANG_NAMES[ru]='Русский'
TX[ru:acct_line]='Аккаунт {0}  (диалогов: {1})'
TX[ru:act_backup]='Создать резервную копию'
TX[ru:act_backup_d]='Сохранить данные RF4 (чаты, настройки, скриншоты) в папку.'
TX[ru:act_merge]='Объединить установки'
TX[ru:act_merge_d]='Добавить сообщения из других установок — ничего не перезаписывается.'
TX[ru:act_restore]='Восстановить из копии'
TX[ru:act_restore_d]='Импортировать сохранённые данные в установку RF4. Сообщения объединяются.'
TX[ru:act_sync]='Синхронизация облако / NAS'
TX[ru:act_sync_d]='Синхронизация почты между ПК, ноутбуком и NAS (Nextcloud, Syncthing, сетевой диск, USB).'
TX[ru:all_accts]='Все аккаунты ({0})'
TX[ru:app_title]='RF4 Резервное копирование и перенос'
TX[ru:back]='Назад'
TX[ru:backup_dir]='Папка резервной копии'
TX[ru:backup_dir_p]='Папка копии [{0}] (Enter = по умолчанию)'
TX[ru:backup_done]='Резервная копия готова: {0}'
TX[ru:bk_mailbox]='{0}: диалогов {1}'
TX[ru:bk_shots]='Скриншоты: файлов {0}'
TX[ru:btn_browse]='Обзор…'
TX[ru:btn_close]='Закрыть'
TX[ru:btn_home]='В начало'
TX[ru:btn_open]='Открыть папку'
TX[ru:cancelled]='Отменено.'
TX[ru:choose]='Выбор'
TX[ru:contents]='Содержимое:'
TX[ru:continue]='[Enter] — продолжить'
TX[ru:donate]='Поддержать: paypal.me/bjoernoppermann'
TX[ru:enter_path]='Введите путь'
TX[ru:exit]='Выход'
TX[ru:f_copied]='{0} скопирован'
TX[ru:f_failed]='{0}: ошибка: {1}'
TX[ru:f_identical]='{0} идентичен, ничего не делаем'
TX[ru:f_missing]='{0} не найден'
TX[ru:f_overwritten]='{0} перезаписан'
TX[ru:f_skipped]='{0} пропущен'
TX[ru:folder_missing]='Папка не найдена: {0}'
TX[ru:found_n]='Найдено установок: {0}'
TX[ru:from]='Откуда: {0}'
TX[ru:hash_click]='(нажмите, чтобы скопировать)'
TX[ru:hash_copied]='Контрольная сумма SHA256 скопирована:'
TX[ru:hash_label]='SHA256: {0}…'
TX[ru:hash_unknown]='SHA256: (путь неизвестен)'
TX[ru:hdr_backup]='РЕЗЕРВНАЯ КОПИЯ'
TX[ru:hdr_merge]='ОБЪЕДИНЕНИЕ УСТАНОВОК'
TX[ru:hdr_restore]='ВОССТАНОВЛЕНИЕ / ИМПОРТ'
TX[ru:hdr_scan]='ПОИСК УСТАНОВОК'
TX[ru:hdr_sync]='СИНХРОНИЗАЦИЯ ОБЛАКО / NAS'
TX[ru:importing_to]='Импорт в: {0}'
TX[ru:invalid]='Неверный ввод'
TX[ru:item_Crafting.dat]='Crafting.dat'
TX[ru:item_mail]='Почтовые ящики (личные сообщения)'
TX[ru:item_Preferences.dat]='Preferences.dat'
TX[ru:item_Settings.dat]='Settings.dat (графика/звук/клавиши)'
TX[ru:item_shots]='Скриншоты'
TX[ru:lang_changed]='Язык изменён.'
TX[ru:lang_prompt]='Выберите язык'
TX[ru:language]='Язык'
TX[ru:manual_path]='→ Ввести путь вручную'
TX[ru:mb_header]='Ящик {0}…'
TX[ru:mb_merge_fail]='Ошибка слияния: {0} – {1}'
TX[ru:mb_merge_file]='Слияние {0}: +{1} сообщ.'
TX[ru:mb_summary]='Ящик: слито {0}, скопировано новых {1}, без изменений {2}'
TX[ru:menu_backup]='Резервная копия – сохранить данные в папку'
TX[ru:menu_lang]='Сменить язык'
TX[ru:menu_merge]='Объединить – слить установки'
TX[ru:menu_restore]='Восстановить – импорт из резервной копии'
TX[ru:menu_scan]='Сканировать – показать все установки'
TX[ru:menu_sync]='Синхронизация – облако/NAS'
TX[ru:merge_done]='Объединение завершено.'
TX[ru:merge_dst]='Цель (основная установка, сохраняется)'
TX[ru:merge_need2]='Нужно минимум 2 существующие установки.'
TX[ru:merge_nosrc]='Нет других установок в качестве источников.'
TX[ru:merge_note]='RF4 позволяет переходить только Steam → Standalone, но не наоборот. Подробнее: https://nga.li/rf4transfer'
TX[ru:merge_safe]='Добавляются только недостающие сообщения. Существующие данные не перезаписываются.'
TX[ru:merge_same]='Источник и цель не должны совпадать.'
TX[ru:merge_src]='Источники (можно несколько)'
TX[ru:merge_src_ctrl]='Источники (Ctrl+клик = несколько)'
TX[ru:merge_src_hdr]='Источник: {0}'
TX[ru:need_python]='Для объединения сообщений нужен python3 (Debian/Ubuntu: sudo apt install python3).'
TX[ru:next]='Далее'
TX[ru:no_backup_here]='В этой папке нет резервной копии RF4.'
TX[ru:no_inst]='Установки не найдены.'
TX[ru:no_mailboxes]='Почтовые ящики не найдены.'
TX[ru:no_path]='Путь не указан.'
TX[ru:none_found]='Установки не найдены.'
TX[ru:nothing_sel]='Ничего не выбрано.'
TX[ru:pick_action]='Выберите действие.'
TX[ru:pick_backup]='Выберите папку резервной копии'
TX[ru:pick_backup_d]='Выберите папку с вашей резервной копией RF4.'
TX[ru:pick_dst]='Выберите целевую установку.'
TX[ru:pick_item]='Выберите хотя бы один пункт.'
TX[ru:pick_one_src]='Выберите хотя бы один источник.'
TX[ru:pick_source]='Выберите источник — какую установку копировать?'
TX[ru:pick_src]='Выберите источник.'
TX[ru:pick_target]='Целевая установка'
TX[ru:restore_done]='Импорт завершён.'
TX[ru:result_title]='Готово'
TX[ru:run_backup]='Начать копирование'
TX[ru:run_merge]='Начать объединение'
TX[ru:run_restore]='Начать восстановление'
TX[ru:running_ask]='Всё равно продолжить?'
TX[ru:running_warn]='RF4, похоже, запущена ({0}). Закройте игру ПЕРЕД восстановлением/объединением/синхронизацией, иначе изменения будут перезаписаны.'
TX[ru:scan_accounts]='ID аккаунтов: {0}'
TX[ru:scan_empty]='(пока отсутствует)'
TX[ru:scan_path]='Путь: {0}'
TX[ru:scan_readonly]='Безопасно: программа только читает — исходные данные не меняются.'
TX[ru:scan_stats]='Ящиков: {0}  Диалогов: {1}'
TX[ru:scan_total]='Всего проверено путей: {0}'
TX[ru:scanning]='Поиск на всех дисках…'
TX[ru:shots_done]='Скриншоты: {0} изобр. → {1}'
TX[ru:shots_none]='Папка скриншотов не найдена'
TX[ru:step1]='Поиск'
TX[ru:step2]='Действие'
TX[ru:step3]='Выбор'
TX[ru:step4]='Запуск'
TX[ru:step5]='Итог'
TX[ru:sync_cfg]='Настроить папку синхронизации'
TX[ru:sync_dir_lbl]='Папка синхронизации:'
TX[ru:sync_done]='Синхронизация завершена!'
TX[ru:sync_down]='{0} ← синхр. (скачано)'
TX[ru:sync_down_new]='{0} ← синхр. (в синхр. новее)'
TX[ru:sync_enter]='Введите папку синхронизации (напр. N:\RF4-Sync, D:\RF4-Sync):'
TX[ru:sync_first]='Сначала настройте папку синхронизации.'
TX[ru:sync_hint]='Папка Nextcloud · сетевой диск NAS (N:\) · папка Syncthing · USB-накопитель'
TX[ru:sync_inst_lbl]='Установка:'
TX[ru:sync_intro]='Синхронизация через папку — Nextcloud, NAS, Syncthing, USB, OneDrive.'
TX[ru:sync_local]='Локально:  {0}'
TX[ru:sync_mkfail]='Не удалось создать папку: {0}'
TX[ru:sync_nolocal]='Локальных ящиков нет — только загрузка.'
TX[ru:sync_none]='Папка синхронизации не настроена.'
TX[ru:sync_noremote]='В папке синхронизации ещё нет ящиков с других устройств.'
TX[ru:sync_ok]='Папка синхронизации: {0}'
TX[ru:sync_p1]='Этап 1: локально → синхр. (загрузка новых сообщений)'
TX[ru:sync_p2]='Этап 2: синхр. → локально (скачивание новых сообщений)'
TX[ru:sync_p3]='Настройки (побеждает более новая версия)'
TX[ru:sync_pick_dir]='Выберите папку синхронизации (напр. Nextcloud или диск NAS)'
TX[ru:sync_remote]='Синхр.:   {0}'
TX[ru:sync_run]='Синхронизировать сейчас (двусторонне)'
TX[ru:sync_same]='{0}: одинаковы, пропущено'
TX[ru:sync_saved]='Сохранено: {0}'
TX[ru:sync_st_boxes]='{0}: диалогов {1}'
TX[ru:sync_st_log]='Последние записи синхронизации:'
TX[ru:sync_st_nodir]='Подпапки RF4_Sync ещё нет. Сначала выполните синхронизацию.'
TX[ru:sync_st_none]='В папке синхронизации ещё нет ящиков.'
TX[ru:sync_status]='Показать состояние синхронизации'
TX[ru:sync_unreach]='Папка синхронизации недоступна: {0}'
TX[ru:sync_unreach_h]='NAS подключён? Облачная синхронизация активна? USB вставлен?'
TX[ru:sync_up]='{0} → синхр. (загружено)'
TX[ru:sync_up_new]='{0} → синхр. (локальный новее)'
TX[ru:sync_which]='Какую установку синхронизировать?'
TX[ru:to]='Куда: {0}'
TX[ru:toggle_hint]='(номер = вкл/выкл, a = все, n = ничего, Enter = ОК, 0 = назад)'
TX[ru:undo_saved]='Заменённые файлы сохранены в: {0}'
TX[ru:usage]='Использование: rf4sa-backup.sh [-l de|en|zh|ru]'
TX[ru:v_DE]='RF4 Standalone (немецкая)'
TX[ru:v_DE_new]='RF4 Standalone (немецкая, новая)'
TX[ru:v_EN]='RF4 Standalone (английская)'
TX[ru:v_Other]='RF4 ({0})'
TX[ru:v_Steam]='RF4 Steam'
TX[ru:w_drive]='Диск: {0} / {1}'
TX[ru:w_extra]='Путь: {0}'
TX[ru:w_proton]='Proton: AppID {0}'
TX[ru:w_user]='Пользователь: {0}'
TX[ru:w_win]='Windows: {0} / {1}'
TX[ru:w_wine]='Wine: {0}'
TX[ru:what_backup]='Что копировать?'
TX[ru:what_restore]='Что импортировать?'
TX[ru:what_todo]='Что вы хотите сделать?'
TX[ru:which_acct_b]='Какой аккаунт копировать?'
TX[ru:which_acct_m]='Какие аккаунты объединить из этого источника?'
TX[ru:which_acct_r]='Какой аккаунт импортировать?'
TX[ru:working]='Пожалуйста, подождите…'
TX[ru:yes_char]='д'
TX[ru:yn_overwrite]='{0} уже существует. Перезаписать? [д/Н]'
TX[ru:overwrite_q]='{0} уже существует.{1}Перезаписать?'
TX[ru:sel_account]='Аккаунт:'
TX[ru:scan_hint]='Программа автоматически ищет установки RF4 на всех дисках.'
TX[ru:rescan]='Искать заново'
TX[ru:target_none]='Подходящая целевая установка отсутствует.'
TX[ru:backup_to]='Папка для копии'
TX[ru:preview]='Содержимое копии:'
TX[ru:undo_hint]='Заменяемые файлы сначала копируются в _rf4tool_undo.'
TX[ru:theme_label]='Тема'
TX[ru:theme_auto]='Автоматически (как в Windows)'
TX[ru:tip_lang]='Сменить язык'
TX[ru:tip_theme]='Сменить тему'
TX[ru:bk_mailbox_n]='Ящиков: {0} · диалогов: {1}'
TX[ru:bk_files_n]='файлов настроек: {0}'
TX[ru:bk_shots_n]='скриншотов: {0}'
TX[ru:existing_backups]='Найденные резервные копии'
TX[ru:no_existing_backups]='Резервные копии не найдены — выберите папку.'
TX[ru:other_folder]='Выбрать другую папку…'
TX[ru:last_change]='Изменено: {0}'
TX[ru:chip_found]='найдено'
TX[ru:chip_missing]='нет'
TX[ru:convs_short]='диалогов'
TX[ru:sum_msgs]='сообщений перенесено'
TX[ru:sum_convs]='диалогов'
TX[ru:sum_files]='файлов скопировано'
TX[ru:sum_shots]='скриншотов'
TX[ru:sum_skipped]='пропущено'
TX[ru:sum_failed]='ошибок'
TX[ru:show_details]='Показать подробности'
TX[ru:hide_details]='Скрыть подробности'
TX[ru:res_ok]='Готово — без ошибок.'
TX[ru:res_err]='Завершено, но с ошибками: {0}. Смотрите подробности.'
TX[ru:working_title]='Не закрывайте — это может занять некоторое время.'
TX[ru:btn_done]='Готово'
TX[ru:btn_start_over]='Новое действие'
TX[ru:hdr_scan_t]='Установки'
TX[ru:hdr_action_t]='Что вы хотите сделать?'
TX[ru:hdr_backup_t]='Создать резервную копию'
TX[ru:hdr_restore_t]='Восстановить из копии'
TX[ru:hdr_merge_t]='Объединить установки'
TX[ru:hdr_sync_t]='Синхронизация облако / NAS'
TX[ru:to_target]='Цель'
TX[ru:no_backup_found_cli]='В обычных папках копий нет — введите путь.'
TX[ru:pick_backup_list]='Выберите резервную копию'
TX[ru:theme_name_dark]='Тёмная (морская)'
TX[ru:theme_name_light]='Светлая'
TX[ru:open_folder_tip]='Открывает папку в проводнике'
TX[ru:accounts_all]='Все аккаунты'
TX[ru:tip_card_select]='Нажмите, чтобы выбрать'
TX[ru:select_backup_first]='Сначала выберите резервную копию.'
TX[ru:sync_run_btn]='Начать синхронизацию'
TX[ru:sync_status_btn]='Показать состояние'
TX[ru:dialog_yes]='Да'
TX[ru:dialog_no]='Нет'
TX[ru:dialog_ok]='ОК'
TX[ru:err_unexpected]='Произошла непредвиденная ошибка. Программа продолжает работу, ничего не удалено.'
TX[ru:err_logged]='Подробности: {0}'
TX[ru:bk_source]='Источник: {0}'
TX[ru:bk_source_unknown]='Источник: неизвестен (копия без информационного файла)'
TX[ru:bk_from_pc]='(ПК {0})'
TX[ru:bk_dates]='Создана: {0}   ·   Обновлена: {1}'
TX[ru:bk_existing_here]='Здесь уже есть копия. {0}'
TX[ru:bk_source_sync]='Источник: общая папка синхронизации – последний раз синхронизировал ПК {0}, {1}'
TX[ru:bk_source_sync_unknown]='Источник: общая папка синхронизации (записей синхронизации пока нет)'
TX[ru:bk_sync_hint]='Общая папка всех устройств — восстановление берёт отсюда синхронизированное состояние.'
TX[ru:bk_badge_sync]='Sync'
TX[ru:menu_help]='Справка / руководство'
TX[ru:help_btn]='Справка'
TX[ru:tip_help]='Открыть руководство со скриншотами на вашем языке'
TX[ru:restore_path_bad]='Там не найдена резервная копия (в подпапке RF4_Sync тоже). Папка недоступна?'

# ── Konfiguration / Sprache ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rf4-backup"
CONFIG_FILE="$CONFIG_DIR/settings.conf"

cfg_get() {   # cfg_get key
    local line
    [[ -f "$CONFIG_FILE" ]] || return 0
    line=$(grep -m1 "^$1=" "$CONFIG_FILE" 2>/dev/null) || return 0
    printf '%s' "${line#*=}"
}
cfg_set() {   # cfg_set key value
    mkdir -p "$CONFIG_DIR"
    local tmp="$CONFIG_FILE.tmp"
    { [[ -f "$CONFIG_FILE" ]] && grep -v "^$1=" "$CONFIG_FILE" 2>/dev/null; printf '%s=%s\n' "$1" "$2"; } > "$tmp" || true
    mv "$tmp" "$CONFIG_FILE"
}
resolve_lang() {   # exakt (pt-br), sonst die ersten 2 Zeichen – nur geladene Sprachen
    local c="${1:-}"; c="${c,,}"; c="${c//_/-}"; c="${c%%.*}"
    local l
    for l in "${LANGS[@]}"; do [[ "$l" == "$c" ]] && { printf '%s' "$l"; return; }; done
    c="${c:0:2}"
    for l in "${LANGS[@]}"; do [[ "$l" == "$c" ]] && { printf '%s' "$l"; return; }; done
}
# Weitere Sprachen: Dateien lang/*.lang neben dem Skript oder in ~/.config/rf4-backup/lang/ (Format key=Text, @code=, @name=)
load_lang_file() {
    local f="$1" code="" line k v l known
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"; line="${line#$'\xEF\xBB\xBF'}"
        [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *=* ]] && continue
        k="${line%%=*}"; v="${line#*=}"
        if [[ "${k:0:1}" == "@" ]]; then
            case "${k:1}" in
                code) code="${v,,}"; known=0; for l in "${LANGS[@]}"; do [[ "$l" == "$code" ]] && known=1; done; (( known )) || LANGS+=("$code") ;;
                name) [[ -n "$code" ]] && LANG_NAMES[$code]="$v" ;;
            esac
        elif [[ -n "$code" ]]; then TX[$code:$k]="$v"; fi
    done < "$f"
}
load_external_langs() {
    local d f
    for d in "$SCRIPT_DIR/lang" "$CONFIG_DIR/lang"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*.lang; do [[ -f "$f" ]] && load_lang_file "$f"; done
    done
}
init_lang() {
    local l
    l=$(resolve_lang "${1:-}")
    [[ -z "$l" ]] && l=$(resolve_lang "${RF4_LANG:-}")
    [[ -z "$l" ]] && l=$(resolve_lang "$(cfg_get lang)")
    [[ -z "$l" ]] && l=$(resolve_lang "${LC_ALL:-${LANG:-}}")
    [[ -z "$l" ]] && l=en
    LANG_CODE="$l"
}
t() {   # t key [args…]   – {0} {1} … werden ersetzt
    local key="$1"; shift
    local s="${TX[$LANG_CODE:$key]:-${TX[en:$key]:-$key}}"
    local i=0 a
    for a in "$@"; do s="${s//\{$i\}/$a}"; i=$((i + 1)); done
    printf '%s' "$s"
}

sync_get() {
    local p; p=$(cfg_get sync)
    if [[ -z "$p" && -f "$CONFIG_DIR/sync.conf" ]]; then p=$(<"$CONFIG_DIR/sync.conf"); fi   # Altformat v1.2/1.3
    printf '%s' "$p"
}
sync_set() { cfg_set sync "$1"; }

# ── Ausgabe ────────────────────────────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    R=$'\033[0;31m' G=$'\033[0;32m' Y=$'\033[1;33m' B=$'\033[1;34m' C=$'\033[0;36m' W=$'\033[1;37m' D=$'\033[2m' NC=$'\033[0m'
else
    R='' G='' Y='' B='' C='' W='' D='' NC=''
fi
# Unicode-Rahmen/Symbole, wenn das Terminal UTF-8 kann (RF4_ASCII=1 erzwingt ASCII)
UNI=1
[[ "${RF4_ASCII:-}" == "1" ]] && UNI=0
[[ "$(locale charmap 2>/dev/null)" == "UTF-8" ]] || UNI=0
if (( UNI )); then
    G_TL='╔' G_TR='╗' G_BL='╚' G_BR='╝' G_H='═' G_V='║' G_LINE='─' G_OK='✔' G_WARN='!' G_ERR='✘' G_INFO='›' G_DOT='·' G_BAR='━' G_ON='■'
else
    G_TL='+' G_TR='+' G_BL='+' G_BR='+' G_H='=' G_V='|' G_LINE='-' G_OK='OK' G_WARN='!' G_ERR='X' G_INFO='>' G_DOT='-' G_BAR='=' G_ON='[X]'
fi
WIDTH=64
rep() { local n="$1" s="$2" out="" i; for ((i = 0; i < n; i++)); do out+="$s"; done; printf '%s' "$out"; }
disp_width() {   # Anzeigebreite: CJK/Fullwidth zählt doppelt
    local s="$1" w=0 i ch cp
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"; printf -v cp '%d' "'$ch" 2>/dev/null || cp=0
        if (( (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0xA4CF) || (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE30 && cp <= 0xFE6F) || (cp >= 0xFF00 && cp <= 0xFF60) )); then w=$((w + 2)); else w=$((w + 1)); fi
    done
    printf '%d' "$w"
}
sep()  { printf '%s\n' "  ${C}$(rep $((WIDTH - 4)) "$G_LINE")${NC}"; }
hdr()  { local t=" $* " fill; fill=$(( WIDTH - 6 - $(disp_width "$t") )); (( fill < 2 )) && fill=2; printf '\n%s\n' "  ${C}$(rep 2 "$G_BAR")${t}$(rep "$fill" "$G_BAR")${NC}"; }
ok()   { printf '%s\n' "  ${G}${G_OK}${NC} $*"; }
warn() { printf '%s\n' "  ${Y}${G_WARN}${NC} ${Y}$*${NC}"; }
err()  { printf '%s\n' "  ${R}${G_ERR}${NC} ${R}$*${NC}" >&2; }
info() { printf '%s\n' "  ${C}${G_INFO}${NC} $*"; }
log()  { case "$1" in ok) ok "$2" ;; warn) warn "$2" ;; err) err "$2" ;; *) info "$2" ;; esac; }
box()  {   # box zeile1 zeile2 …
    local inner=$((WIDTH - 4)) l pad
    printf '%s\n' "  ${C}${G_TL}$(rep "$inner" "$G_H")${G_TR}${NC}"
    for l in "$@"; do pad=$(( inner - 1 - $(disp_width "$l") )); (( pad < 0 )) && pad=0; printf '%s\n' "  ${C}${G_V}${NC} ${l}$(rep "$pad" ' ')${C}${G_V}${NC}"; done
    printf '%s\n' "  ${C}${G_BL}$(rep "$inner" "$G_H")${G_BR}${NC}"
}
# Statistik der letzten Operation
STAT_MSG=0 STAT_CONV=0 STAT_FILES=0 STAT_SHOTS=0 STAT_SKIP=0 STAT_FAIL=0
reset_stats() { STAT_MSG=0 STAT_CONV=0 STAT_FILES=0 STAT_SHOTS=0 STAT_SKIP=0 STAT_FAIL=0; }
print_summary() {
    echo
    printf '  %s' "${C}${G_ON} ${STAT_MSG}${NC} $(t sum_msgs)   ${G}${G_ON} ${STAT_CONV}${NC} $(t sum_convs)   ${G}${G_ON} ${STAT_FILES}${NC} $(t sum_files)   "
    (( STAT_SHOTS > 0 )) && printf '%s' "${G}${G_ON} ${STAT_SHOTS}${NC} $(t sum_shots)   "
    (( STAT_SKIP > 0 )) && printf '%s' "${Y}${G_ON} ${STAT_SKIP}${NC} $(t sum_skipped)   "
    (( STAT_FAIL > 0 )) && printf '%s' "${R}${G_ON} ${STAT_FAIL}${NC} $(t sum_failed)   "
    echo
    if (( STAT_FAIL > 0 )); then err "$(t res_err "$STAT_FAIL")"; else ok "$(t res_ok)"; fi
}

pause() { echo; local _x; read -r -p "  $(t continue) " _x || true; }

# ── Eingaben ───────────────────────────────────────────────────────────────────
# menu "Titel" opt1 opt2 …  → setzt MENU_CHOICE (0 = zurück)
menu() {
    local title="$1"; shift
    local -a opts=("$@")
    echo; printf '%s\n' "  ${W}${title}${NC}"; sep
    local i
    for i in "${!opts[@]}"; do printf '%s\n' "  ${Y}[$((i + 1))]${NC} ${opts[$i]}"; done
    printf '%s\n\n' "  ${Y}[0]${NC} $(t back)"
    local raw
    while true; do
        read -r -p "  $(t choose): " raw || { MENU_CHOICE=0; return; }
        raw="${raw//[[:space:]]/}"
        if [[ "$raw" == "0" ]]; then MENU_CHOICE=0; return; fi
        if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw >= 1 && raw <= ${#opts[@]} )); then MENU_CHOICE=$raw; return; fi
        warn "$(t invalid)"
    done
}
# multiselect "Titel" opt1 …  → MULTI_SEL (Array 0-basierter Indizes), MULTI_CANCEL=1 bei 0/EOF
multiselect() {
    local title="$1"; shift
    local -a opts=("$@") chosen=()
    local i n=${#opts[@]} raw tok
    for ((i = 0; i < n; i++)); do chosen[i]=0; done
    MULTI_SEL=(); MULTI_CANCEL=0
    while true; do
        echo; printf '%s\n' "  ${W}${title}${NC}"; printf '%s\n' "  ${D}$(t toggle_hint)${NC}"; sep
        for ((i = 0; i < n; i++)); do
            if (( chosen[i] )); then printf '%s\n' "  ${G}[X] $((i + 1))) ${opts[$i]}${NC}"; else printf '%s\n' "  ${D}[ ] $((i + 1))) ${opts[$i]}${NC}"; fi
        done
        echo
        read -r -p "  $(t choose): " raw || { MULTI_CANCEL=1; return; }
        raw="${raw,,}"; raw="${raw#"${raw%%[![:space:]]*}"}"; raw="${raw%"${raw##*[![:space:]]}"}"
        if [[ -z "$raw" ]]; then for ((i = 0; i < n; i++)); do (( chosen[i] )) && MULTI_SEL+=("$i"); done; return; fi
        if [[ "$raw" == "0" ]]; then MULTI_CANCEL=1; return; fi
        if [[ "$raw" == "a" ]]; then for ((i = 0; i < n; i++)); do chosen[i]=1; done; continue; fi
        if [[ "$raw" == "n" ]]; then for ((i = 0; i < n; i++)); do chosen[i]=0; done; continue; fi
        for tok in ${raw//,/ }; do
            if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= n )); then chosen[tok - 1]=$(( 1 - chosen[tok - 1] )); fi
        done
    done
}
ask_overwrite() {   # ask_overwrite name → 0 = ja
    local a
    read -r -p "  $(t yn_overwrite "$1") " a || return 1
    a="${a,,}"
    [[ "$a" == "j" || "$a" == "y" || "$a" == "ja" || "$a" == "yes" || "$a" == "д" || "$a" == "да" ]]
}
rf4_running() {   # gibt einen Hinweis aus, wenn das Spiel läuft (nur rf4_x64/rf4_x32, nicht Launcher/Installer)
    [[ -n "${RF4_FAKE_RUNNING:-}" ]] && { printf '%s' "$RF4_FAKE_RUNNING"; return 0; }
    command -v pgrep >/dev/null 2>&1 || return 1
    pgrep -if 'rf4_x64|rf4_x32' 2>/dev/null | head -1 | grep -q . && printf 'rf4'
}
confirm_game_closed() {
    local run; run=$(rf4_running) || true
    [[ -z "$run" ]] && return 0
    warn "$(t running_warn "$run")"
    local a; read -r -p "  $(t running_ask) [$(t yes_char)/N] " a || return 1
    a="${a,,}"; [[ "$a" == "j" || "$a" == "y" || "$a" == "д" ]]
}

# ── Installationen finden ──────────────────────────────────────────────────────
KNOWN_FOLDERS=(RussianFishing4DE RussianFishing4DE_new RussianFishing4EN RussianFishing4Steam)
declare -A KNOWN_VARIANT=([RussianFishing4DE]=DE [RussianFishing4DE_new]=DE_new [RussianFishing4EN]=EN [RussianFishing4Steam]=Steam)
RF4_BASE="AppData/Roaming/RussianFishingLLC"
declare -a INST_VARIANT=() INST_FOLDER=() INST_PATH=() INST_WTYPE=() INST_W1=() INST_W2=() INST_EXISTS=()
declare -A _SEEN=()

add_user() {   # add_user userdir wtype w1 w2 create_known(0/1)
    local udir="${1%/}" wtype="$2" w1="$3" w2="$4" create="$5"
    local base="$udir/$RF4_BASE" f d
    local -a folders=()
    (( create )) && folders=("${KNOWN_FOLDERS[@]}")
    if [[ -d "$base" ]]; then
        for d in "$base"/*/; do
            [[ -d "$d" ]] || continue
            f=$(basename "$d")
            local dup=0 x; for x in "${folders[@]:-}"; do [[ "$x" == "$f" ]] && dup=1; done
            (( dup )) || folders+=("$f")
        done
    fi
    for f in "${folders[@]:-}"; do
        [[ -n "$f" ]] || continue
        local p="$base/$f" ex=0
        [[ -n "${_SEEN[${p,,}]:-}" ]] && continue
        _SEEN[${p,,}]=1
        [[ -d "$p" ]] && ex=1
        (( ex || create )) || continue
        INST_VARIANT+=("${KNOWN_VARIANT[$f]:-Other}"); INST_FOLDER+=("$f"); INST_PATH+=("$p")
        INST_WTYPE+=("$wtype"); INST_W1+=("$w1"); INST_W2+=("$w2"); INST_EXISTS+=("$ex")
    done
}

find_installations() {
    INST_VARIANT=(); INST_FOLDER=(); INST_PATH=(); INST_WTYPE=(); INST_W1=(); INST_W2=(); INST_EXISTS=(); _SEEN=()
    local mp u udir prefix compat appid x
    # 1) Windows-Partitionen
    for mp in /mnt/* /media/*/* /run/media/*/*; do
        [[ -d "$mp/Users" ]] || continue
        for udir in "$mp"/Users/*/; do
            [[ -d "$udir" ]] || continue
            u=$(basename "$udir"); [[ "$u" == "Public" || "$u" == "Default" || "$u" == "All Users" || "$u" == "Default User" ]] && continue
            add_user "$udir" win "$(basename "$mp")" "$u" 0
        done
    done
    # 2) Wine-Prefixes
    for prefix in "$HOME/.wine" "$HOME/.local/share/wineprefixes"/* "$HOME/.local/share/lutris/runners/wine"/* "$HOME/Games"/*/drive_c/..; do
        [[ -d "$prefix/drive_c/users" ]] || continue
        for udir in "$prefix"/drive_c/users/*/; do
            [[ -d "$udir" ]] || continue
            u=$(basename "$udir"); [[ "$u" == "Public" || "$u" == "All Users" ]] && continue
            add_user "$udir" wine "$prefix" "$u" 1
        done
    done
    # 3) Steam Proton
    for compat in "$HOME/.local/share/Steam/steamapps/compatdata" "$HOME/.steam/steam/steamapps/compatdata" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata"; do
        [[ -d "$compat" ]] || continue
        for prefix in "$compat"/*/; do
            appid=$(basename "$prefix")
            [[ -d "$prefix/pfx/drive_c/users" ]] || continue
            for udir in "$prefix"/pfx/drive_c/users/*/; do
                [[ -d "$udir" ]] || continue
                u=$(basename "$udir"); [[ "$u" == "Public" || "$u" == "All Users" ]] && continue
                add_user "$udir" proton "$appid" "$u" 0
            done
        done
    done
    # 4) Zusätzliche "Users"-Ordner (RF4_SCAN_USERS, ':'-getrennt)
    local IFS=':'
    for x in ${RF4_SCAN_USERS:-}; do
        [[ -d "$x" ]] || continue
        for udir in "$x"/*/; do
            [[ -d "$udir" ]] || continue
            add_user "$udir" extra "$(basename "$udir")" "" 0
        done
    done
}

label_for() {   # label_for variant folder wtype w1 w2   (versteht auch von Windows geschriebene Orte)
    local variant="$1" folder="$2" wtype="$3" w1="$4" w2="$5" name where
    if [[ "$variant" == "Other" || -z "$variant" ]]; then name=$(t v_Other "$folder"); else name=$(t "v_$variant"); fi
    case "$wtype" in
        win)    where=$(t w_win "$w1" "$w2") ;;
        wine)   where=$(t w_wine "$w2") ;;
        proton) where=$(t w_proton "$w1") ;;
        local)  where="$w1 / $w2" ;;
        user)   where=$(t w_user "$w1") ;;
        drive)  where=$(t w_drive "$w1" "$w2") ;;
        *)      where=$(t w_extra "$w1") ;;
    esac
    printf '%s [%s]' "$name" "$where"
}
inst_label() { label_for "${INST_VARIANT[$1]}" "${INST_FOLDER[$1]}" "${INST_WTYPE[$1]}" "${INST_W1[$1]}" "${INST_W2[$1]}"; }
# ── Mailboxen ──────────────────────────────────────────────────────────────────
declare -a MB_NAME=() MB_ID=() MB_PATH=() MB_CONVS=()
count_dats() { local n=0 f; for f in "$1"/*.dat; do [[ -f "$f" ]] && n=$((n + 1)); done; echo "$n"; }
load_mailboxes() {   # load_mailboxes pfad
    MB_NAME=(); MB_ID=(); MB_PATH=(); MB_CONVS=()
    local d
    [[ -d "$1" ]] || return 0
    for d in "$1"/Mailbox_*/; do
        [[ -d "$d" ]] || continue
        d="${d%/}"
        MB_NAME+=("$(basename "$d")"); MB_ID+=("$(basename "$d" | sed 's/^Mailbox_//')"); MB_PATH+=("$d"); MB_CONVS+=("$(count_dats "$d")")
    done
}

PYTHON=""
find_python() {
    [[ -n "$PYTHON" ]] && return 0
    local c
    for c in python3 python; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' 2>/dev/null; then PYTHON="$c"; return 0; fi
    done
    return 1
}
read -r -d '' PY_MERGE <<'PYEOF' || true
import json, os, shutil, sys
src, dst, undo = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(dst, exist_ok=True)
def load(p):
    with open(p, encoding='utf-8-sig') as f:
        return json.load(f)
def mid(i):
    try:
        return str(i['meta']['id'])
    except Exception:
        return None
def created(i):
    try:
        return int(i['meta']['created'])
    except Exception:
        return 0
for name in sorted(os.listdir(src)):
    if not name.lower().endswith('.dat'):
        continue
    sp = os.path.join(src, name)
    if not os.path.isfile(sp):
        continue
    dp = os.path.join(dst, name)
    if not os.path.exists(dp):
        shutil.copy2(sp, dp)
        try:
            n = len(load(sp).get('items') or [])
        except Exception:
            n = 0
        print('COPIED\t%s\t%d' % (name, n))
        continue
    try:
        s = load(sp)
        d = load(dp)
        ditems = list(d.get('items') or [])
        sitems = list(s.get('items') or [])
        seen = set(m for m in (mid(i) for i in ditems) if m)
        extra = []
        for i in sitems:
            m = mid(i)
            if m and m not in seen:
                seen.add(m)
                extra.append(i)
        if not extra:
            print('UNCHANGED\t' + name)
            continue
        if undo:
            ud = os.path.join(undo, os.path.basename(os.path.normpath(dst)))
            os.makedirs(ud, exist_ok=True)
            shutil.copy2(dp, os.path.join(ud, name))
        d['items'] = sorted(ditems + extra, key=created)
        tmp = dp + '.rf4tmp'
        with open(tmp, 'w', encoding='utf-8-sig') as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        load(tmp)
        os.replace(tmp, dp)
        print('MERGED\t%s\t%d' % (name, len(extra)))
    except Exception as e:
        print('FAILED\t%s\t%s' % (name, str(e).replace('\n', ' ')))
PYEOF

merge_mailbox() {   # merge_mailbox srcdir dstdir [undoroot]
    local src="$1" dst="$2" undo="${3:-}"
    local merged=0 copied=0 unchanged=0 failed=0 kind name extra
    if ! find_python; then err "$(t need_python)"; return 1; fi
    mkdir -p "$dst"
    while IFS=$'\t' read -r kind name extra; do
        extra="${extra%$'\r'}"; name="${name%$'\r'}"; kind="${kind%$'\r'}"
        case "$kind" in
            COPIED)    copied=$((copied + 1)); STAT_CONV=$((STAT_CONV + 1)); STAT_MSG=$((STAT_MSG + ${extra:-0})) ;;
            UNCHANGED) unchanged=$((unchanged + 1)) ;;
            MERGED)    merged=$((merged + 1)); STAT_CONV=$((STAT_CONV + 1)); STAT_MSG=$((STAT_MSG + extra)); info "$(t mb_merge_file "$name" "$extra")" ;;
            FAILED)    failed=$((failed + 1)); STAT_FAIL=$((STAT_FAIL + 1)); warn "$(t mb_merge_fail "$name" "$extra")" ;;
        esac
    done < <(PYTHONIOENCODING=utf-8 "$PYTHON" -c "$PY_MERGE" "$src" "$dst" "$undo" 2>&1)
    ok "$(t mb_summary "$merged" "$copied" "$unchanged")"
}

# ── Dateien / Screenshots ──────────────────────────────────────────────────────
save_undo() {   # save_undo datei undoroot
    local f="$1" u="${2:-}"
    [[ -n "$u" && -f "$f" ]] || return 0
    local d; d="$u/$(basename "$(dirname "$f")")"
    mkdir -p "$d" && cp -p "$f" "$d/"
}
new_undo_root() { printf '%s/_rf4tool_undo/%s' "$1" "$(date +%Y%m%d_%H%M%S)"; }
files_identical() { cmp -s "$1" "$2"; }

copy_datfile() {   # copy_datfile src dst [undoroot]
    local src="$1" dst="$2" undo="${3:-}" name; name=$(basename "$src")
    [[ -f "$src" ]] || { warn "$(t f_missing "$name")"; return; }
    if [[ -f "$dst" ]]; then
        if files_identical "$src" "$dst"; then info "$(t f_identical "$name")"; return; fi
        if ask_overwrite "$name"; then
            save_undo "$dst" "$undo"; cp -f "$src" "$dst" && { STAT_FILES=$((STAT_FILES + 1)); ok "$(t f_overwritten "$name")"; } || { STAT_FAIL=$((STAT_FAIL + 1)); err "$(t f_failed "$name" cp)"; }
        else STAT_SKIP=$((STAT_SKIP + 1)); warn "$(t f_skipped "$name")"; fi
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst" && { STAT_FILES=$((STAT_FILES + 1)); ok "$(t f_copied "$name")"; } || { STAT_FAIL=$((STAT_FAIL + 1)); err "$(t f_failed "$name" cp)"; }
}

screenshot_dir() {   # screenshot_dir instpath [create]
    local u="${1%/}" i c
    for i in 1 2 3 4; do u=$(dirname "$u"); done
    for c in "$u/Documents/Russian Fishing 4/Screenshots" "$u/My Documents/Russian Fishing 4/Screenshots" "$u/OneDrive/Documents/Russian Fishing 4/Screenshots"; do
        [[ -d "$c" ]] && { printf '%s' "$c"; return; }
    done
    [[ "${2:-}" == "create" ]] && printf '%s' "$u/Documents/Russian Fishing 4/Screenshots"
}
copy_screenshots() {   # copy_screenshots srcdir dstdir
    local src="$1" dst="$2" n=0 f t
    if [[ -z "$src" || ! -d "$src" ]]; then warn "$(t shots_none)"; return; fi
    mkdir -p "$dst"
    while IFS= read -r -d '' f; do
        t="$dst/$(basename "$f")"
        [[ -e "$t" ]] || { cp "$f" "$t" && n=$((n + 1)); }
    done < <(find "$src" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 2>/dev/null)
    STAT_SHOTS=$((STAT_SHOTS + n)); ok "$(t shots_done "$n" "$dst")"
}

# Gemeinsam für Backup UND Restore:  copy_rf4data src dst "items" "accounts" shots_src shots_dst undo
#   items: mail Settings.dat Preferences.dat Crafting.dat shots  (leerzeichengetrennt)
#   accounts: leer = alle, sonst Ordnernamen (Mailbox_123 …) leerzeichengetrennt
copy_rf4data() {
    local src="$1" dst="$2" items="$3" accounts="$4" shots_src="$5" shots_dst="$6" undo="${7:-}" it i a want
    mkdir -p "$dst"
    for it in $items; do
        case "$it" in
            mail)
                load_mailboxes "$src"
                if (( ${#MB_NAME[@]} == 0 )); then warn "$(t no_mailboxes)"; continue; fi
                local -a names=("${MB_NAME[@]}") paths=("${MB_PATH[@]}")
                for i in "${!names[@]}"; do
                    want=1
                    if [[ -n "$accounts" ]]; then want=0; for a in $accounts; do [[ "$a" == "${names[$i]}" ]] && want=1; done; fi
                    (( want )) || continue
                    info "$(t mb_header "${names[$i]}")"
                    merge_mailbox "${paths[$i]}" "$dst/${names[$i]}" "$undo"
                done ;;
            shots) copy_screenshots "$shots_src" "$shots_dst" ;;
            Settings.dat|Preferences.dat|Crafting.dat) copy_datfile "$src/$it" "$dst/$it" "$undo" ;;
        esac
    done
    if [[ -n "$undo" && -d "$undo" ]]; then info "$(t undo_saved "$undo")"; fi
}

# ── Backup-Info (von wann, von welcher Installation) – gleiche Datei wie unter Windows ──
write_backup_info() {   # write_backup_info dest inst_index "items"
    local dest="$1" i="$2" items="$3" f="$1/rf4-backup.info" now created="" l n=0
    local -a hist=()
    now="$(date '+%Y-%m-%d %H:%M')"
    if [[ -f "$f" ]]; then
        created="$(grep -m1 '^created=' "$f" | cut -d= -f2-)"
        while IFS= read -r l; do hist+=("${l#history=}"); done < <(grep '^history=' "$f")
    fi
    [[ -z "$created" ]] && created="$now"
    mkdir -p "$dest"
    {
        echo '# RF4 Backup Tool - Informationen zu diesem Backup (von wann, von welcher Installation)'
        echo "created=$created"; echo "updated=$now"; echo "tool=$TOOL_VERSION"; echo "host=$(hostname 2>/dev/null || echo host)"; echo "user=${USER:-}"
        echo "variant=${INST_VARIANT[$i]}"; echo "folder=${INST_FOLDER[$i]}"; echo "wtype=${INST_WTYPE[$i]}"; echo "w1=${INST_W1[$i]}"; echo "w2=${INST_W2[$i]}"; echo "srcpath=${INST_PATH[$i]}"
        echo "items=${items// /,}"
        echo "history=$now|${INST_VARIANT[$i]}|${INST_FOLDER[$i]}|$(hostname 2>/dev/null || echo host)"
        for l in "${hist[@]:-}"; do if [[ -n "$l" && n -lt 9 ]]; then echo "history=$l"; n=$((n + 1)); fi; done
    } > "$f.tmp" && mv "$f.tmp" "$f"
}
# liest rf4-backup.info → setzt BI_* (BI_OK=1 wenn vorhanden)
read_backup_info() {
    BI_OK=0; BI_CREATED=""; BI_UPDATED=""; BI_HOST=""; BI_VARIANT=""; BI_FOLDER=""; BI_WTYPE=""; BI_W1=""; BI_W2=""
    local f="$1/rf4-backup.info" line k v
    [[ -f "$f" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"; line="${line#$'\xEF\xBB\xBF'}"
        [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *=* ]] && continue
        k="${line%%=*}"; v="${line#*=}"
        case "$k" in created) BI_CREATED="$v" ;; updated) BI_UPDATED="$v" ;; host) BI_HOST="$v" ;; variant) BI_VARIANT="$v" ;; folder) BI_FOLDER="$v" ;; wtype) BI_WTYPE="$v" ;; w1) BI_W1="$v" ;; w2) BI_W2="$v" ;; esac
    done < "$f"
    BI_OK=1
}
bk_source_text() {   # nach read_backup_info
    if (( BI_OK )) && [[ -n "$BI_VARIANT" ]]; then
        local s; s="$(label_for "$BI_VARIANT" "$BI_FOLDER" "$BI_WTYPE" "$BI_W1" "$BI_W2")"
        [[ -n "$BI_HOST" ]] && s+="  $(t bk_from_pc "$BI_HOST")"
        t bk_source "$s"
    else t bk_source_unknown; fi
}
# ── Vorhandene Backups ─────────────────────────────────────────────────────────
cfg_backup_dirs() { [[ -f "$CONFIG_FILE" ]] && grep '^backup=' "$CONFIG_FILE" | cut -d= -f2-; return 0; }
add_backup_dir() {
    local d="$1" l n=1
    d="$(cd "$d" 2>/dev/null && pwd -P)" || d="$1"
    local -a keep=("$d")
    while IFS= read -r l; do [[ -n "$l" && "$l" != "$d" && n -lt 8 ]] && { keep+=("$l"); n=$((n + 1)); }; done < <(cfg_backup_dirs)
    mkdir -p "$CONFIG_DIR"
    { [[ -f "$CONFIG_FILE" ]] && grep -v '^backup=' "$CONFIG_FILE"; for l in "${keep[@]}"; do printf 'backup=%s\n' "$l"; done; } > "$CONFIG_FILE.tmp" || true
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}
looks_like_backup() {
    local d="$1" f
    [[ -d "$d" ]] || return 1
    compgen -G "$d/Mailbox_*" >/dev/null 2>&1 && return 0
    for f in "${DAT_FILES[@]}"; do [[ -f "$d/$f" ]] && return 0; done
    [[ -d "$d/Screenshots" ]]
}
fmt_size() {
    local b="$1"
    if (( b >= 1073741824 )); then printf '%d.%d GB' $((b / 1073741824)) $((b % 1073741824 * 10 / 1073741824))
    elif (( b >= 1048576 )); then printf '%d.%d MB' $((b / 1048576)) $((b % 1048576 * 10 / 1048576))
    elif (( b >= 1024 )); then printf '%d KB' $((b / 1024))
    else printf '%d B' "$b"; fi
}
fmt_time() { date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$1"; }
# Pfad, aus dem wiederhergestellt werden kann: der Ordner selbst oder dessen Unterordner RF4_Sync (leer = nichts gefunden)
resolve_backup_path() {
    local p="${1%/}"
    [[ -z "$p" ]] && return 0
    if looks_like_backup "$p"; then printf '%s' "$p"; elif looks_like_backup "$p/RF4_Sync"; then printf '%s' "$p/RF4_Sync"; fi
}
# Quelle eines Backups; Sync-Ordner (RF4_Sync) ohne Info-Datei: letzte Zeile von .sync_log
bk_source_for() {
    read_backup_info "$1"
    if (( BI_OK == 0 )) && [[ "$(basename "$1")" == "RF4_Sync" ]]; then
        local last host ts tsl
        last="$(grep -v '^[[:space:]]*$' "$1/.sync_log" 2>/dev/null | tail -1)"
        if [[ -n "$last" ]]; then
            ts="${last%% *}"; host="${last#* }"
            tsl="$(date -d "$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ts")"
            t bk_source_sync "$host" "$tsl"
        else t bk_source_sync_unknown; fi
    else bk_source_text; fi
}
# Anleitung in der Sprache des Programms öffnen
open_guide() {
    local code="$LANG_CODE" f="" url suffix=""
    case "$code" in de|en|zh|ru) ;; *) code=en ;; esac
    for f in "$SCRIPT_DIR/docs/guide.$code.html" "$SCRIPT_DIR/../docs/guide.$code.html"; do [[ -f "$f" ]] && break; f=""; done
    [[ "$code" != "de" ]] && suffix=".$code"
    url="https://codeberg.org/Natural78/rf4-backup-tool/src/branch/main/README$suffix.md"
    local target="${f:-$url}"
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "$target" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then open "$target" >/dev/null 2>&1 &
    elif command -v cmd.exe >/dev/null 2>&1; then cmd.exe /c start "" "$target" >/dev/null 2>&1 &
    else info "$target"; fi
}
declare -a BK_PATH=() BK_NAME=() BK_TIME=() BK_SIZE=() BK_MBOX=() BK_CONV=() BK_FILES=() BK_SHOTS=() BK_SRC=() BK_DATES=()
find_backups() {
    BK_PATH=(); BK_NAME=(); BK_TIME=(); BK_SIZE=(); BK_MBOX=(); BK_CONV=(); BK_FILES=(); BK_SHOTS=(); BK_SRC=(); BK_DATES=()
    local -a bases=("$HOME/RF4_Backup") cand=() order=()
    local -A seen=()
    local l b c base f m latest size convs files shots i
    while IFS= read -r l; do [[ -n "$l" ]] && bases+=("$l"); done < <(cfg_backup_dirs)
    l="$(sync_get)"; [[ -n "$l" && -d "$l" ]] && bases+=("$l")
    if [[ -n "${RF4_BACKUP_DIRS:-}" ]]; then IFS=':' read -ra cand <<< "$RF4_BACKUP_DIRS"; for l in "${cand[@]}"; do bases+=("$l"); done; fi
    for b in "${bases[@]}"; do
        [[ -d "$b" ]] || continue
        b="${b%/}"
        for c in "$b" "$b"/*/; do
            c="${c%/}"; [[ -d "$c" ]] || continue
            base="$(basename "$c")"
            [[ "$c" != "$b" && ( "$base" == Mailbox_* || "$base" == "Screenshots" ) ]] && continue
            [[ -n "${seen[$c]:-}" ]] && continue
            looks_like_backup "$c" || continue
            seen[$c]=1
            load_mailboxes "$c"; convs=0; for m in "${MB_CONVS[@]:-0}"; do convs=$((convs + m)); done
            files=0; for f in "${DAT_FILES[@]}"; do [[ -f "$c/$f" ]] && files=$((files + 1)); done
            shots=0; [[ -d "$c/Screenshots" ]] && shots=$(find "$c/Screenshots" -type f 2>/dev/null | wc -l | tr -d ' ')
            size=0; latest=0
            while IFS= read -r -d '' f; do size=$((size + $(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0))); m=$(file_mtime "$f"); (( m > latest )) && latest=$m; done < <(find "$c" -type f -print0 2>/dev/null)
            read_backup_info "$c"
            BK_PATH+=("$c"); BK_NAME+=("$base"); BK_TIME+=("$latest"); BK_SIZE+=("$size"); BK_MBOX+=("${#MB_NAME[@]}"); BK_CONV+=("$convs"); BK_FILES+=("$files"); BK_SHOTS+=("$shots")
            BK_SRC+=("$(bk_source_for "$c")")
            if [[ "$base" == "RF4_Sync" && $BI_OK -eq 0 ]]; then BK_DATES+=("$(t bk_sync_hint)"); else BK_DATES+=("$(t bk_dates "${BI_CREATED:-?}" "${BI_UPDATED:-$(fmt_time "$latest")}")"); fi
        done
    done
    # neueste zuerst
    local -a sp=() sn=() st=() ss=() sm=() sc=() sf=() sh=() sr=() sd=()
    while IFS=$'\t' read -r _ i; do sp+=("${BK_PATH[$i]}"); sn+=("${BK_NAME[$i]}"); st+=("${BK_TIME[$i]}"); ss+=("${BK_SIZE[$i]}"); sm+=("${BK_MBOX[$i]}"); sc+=("${BK_CONV[$i]}"); sf+=("${BK_FILES[$i]}"); sh+=("${BK_SHOTS[$i]}"); sr+=("${BK_SRC[$i]}"); sd+=("${BK_DATES[$i]}"); done < <(for i in "${!BK_PATH[@]}"; do printf '%s\t%s\n' "${BK_TIME[$i]}" "$i"; done | sort -rn)
    BK_PATH=("${sp[@]:-}"); BK_NAME=("${sn[@]:-}"); BK_TIME=("${st[@]:-}"); BK_SIZE=("${ss[@]:-}"); BK_MBOX=("${sm[@]:-}"); BK_CONV=("${sc[@]:-}"); BK_FILES=("${sf[@]:-}"); BK_SHOTS=("${sh[@]:-}"); BK_SRC=("${sr[@]:-}"); BK_DATES=("${sd[@]:-}")
    [[ -z "${BK_PATH[0]:-}" ]] && { BK_PATH=(); BK_NAME=(); BK_TIME=(); BK_SIZE=(); BK_MBOX=(); BK_CONV=(); BK_FILES=(); BK_SHOTS=(); BK_SRC=(); BK_DATES=(); }
    return 0
}
bk_info() {   # bk_info index
    local i="$1" s
    s="$(t bk_mailbox_n "${BK_MBOX[$i]}" "${BK_CONV[$i]}")"
    (( BK_FILES[i] > 0 )) && s+="  $G_DOT  $(t bk_files_n "${BK_FILES[$i]}")"
    (( BK_SHOTS[i] > 0 )) && s+="  $G_DOT  $(t bk_shots_n "${BK_SHOTS[$i]}")"
    printf '%s' "$s  $G_DOT  $(fmt_size "${BK_SIZE[$i]}")"
}
# ── Auswahl-Helfer ─────────────────────────────────────────────────────────────
# select_accounts nameprefix titlekey → ACCOUNTS (leer = alle), ACC_BACK=1 bei Zurück
select_accounts() {   # nutzt MB_* (vorher load_mailboxes)
    ACCOUNTS=""; ACC_BACK=0
    (( ${#MB_NAME[@]} <= 1 )) && return
    local -a opts=("$(t all_accts "${#MB_NAME[@]}")"); local i
    for i in "${!MB_NAME[@]}"; do opts+=("$(t acct_line "${MB_ID[$i]}" "${MB_CONVS[$i]}")"); done
    menu "$(t "$1")" "${opts[@]}"
    if (( MENU_CHOICE == 0 )); then ACC_BACK=1; return; fi
    (( MENU_CHOICE == 1 )) && return
    ACCOUNTS="${MB_NAME[$((MENU_CHOICE - 2))]}"
}
existing_indices() { local i; EXIST_IDX=(); for i in "${!INST_PATH[@]}"; do (( INST_EXISTS[i] )) && EXIST_IDX+=("$i"); done; }
item_label() { t "item_$1"; }

# ── SCAN ───────────────────────────────────────────────────────────────────────
do_scan() {
    hdr "$(t hdr_scan)"; info "$(t scanning)"
    find_installations
    if (( ${#INST_PATH[@]} == 0 )); then warn "$(t none_found)"; pause; return; fi
    local i ids
    for i in "${!INST_PATH[@]}"; do
        if (( INST_EXISTS[i] )); then
            load_mailboxes "${INST_PATH[$i]}"
            local convs=0 c; for c in "${MB_CONVS[@]:-0}"; do convs=$((convs + c)); done
            ids=""; for c in "${MB_ID[@]:-}"; do [[ -n "$c" ]] && ids+="${ids:+, }$c"; done
            ok "$(inst_label "$i")"
            info "  $(t scan_path "${INST_PATH[$i]}")"
            info "  $(t scan_stats "${#MB_NAME[@]}" "$convs")"
            [[ -n "$ids" ]] && info "  $(t scan_accounts "$ids")"
        else
            printf '%s\n' "  ${D}[--] $(inst_label "$i")  $(t scan_empty)${NC}"
        fi
        echo
    done
    printf '%s\n' "  ${D}$(t scan_total "${#INST_PATH[@]}")${NC}"
    pause
}

# ── BACKUP ─────────────────────────────────────────────────────────────────────
do_backup() {
    hdr "$(t hdr_backup)"
    find_installations; existing_indices
    if (( ${#EXIST_IDX[@]} == 0 )); then err "$(t no_inst)"; pause; return; fi
    local -a labels=(); local i
    for i in "${EXIST_IDX[@]}"; do labels+=("$(inst_label "$i")"); done
    menu "$(t pick_source)" "${labels[@]}"; (( MENU_CHOICE == 0 )) && return
    local si="${EXIST_IDX[$((MENU_CHOICE - 1))]}" src="${INST_PATH[$((EXIST_IDX[MENU_CHOICE - 1]))]}"
    local -a keys=(mail Settings.dat Preferences.dat Crafting.dat shots); local -a kl=()
    for i in "${keys[@]}"; do kl+=("$(item_label "$i")"); done
    multiselect "$(t what_backup)" "${kl[@]}"
    if (( MULTI_CANCEL )) || (( ${#MULTI_SEL[@]} == 0 )); then warn "$(t nothing_sel)"; pause; return; fi
    local items=""; for i in "${MULTI_SEL[@]}"; do items+="${keys[$i]} "; done
    ACCOUNTS=""; ACC_BACK=0
    if [[ " $items " == *" mail "* ]]; then
        load_mailboxes "$src"; select_accounts "$src" which_acct_b
        (( ACC_BACK )) && return
    fi
    local def="$HOME/RF4_Backup" dest
    read -r -p "  $(t backup_dir_p "$def") " dest || dest=""
    [[ -z "$dest" ]] && dest="$def"
    info "$(t from "$src")"; info "$(t to "$dest")"; sep
    reset_stats
    copy_rf4data "$src" "$dest" "$items" "$ACCOUNTS" "$(screenshot_dir "$src")" "$dest/Screenshots" ""
    write_backup_info "$dest" "$si" "$items"
    add_backup_dir "$dest"
    echo; ok "$(t backup_done "$dest")"; print_summary
    pause
}

# ── RESTORE ────────────────────────────────────────────────────────────────────
do_restore() {
    hdr "$(t hdr_restore)"
    local def="$HOME/RF4_Backup" src="" bi
    find_backups
    if (( ${#BK_PATH[@]} > 0 )); then
        local -a bopts=()
        for bi in "${!BK_PATH[@]}"; do bopts+=("${BK_NAME[$bi]}$([[ "${BK_NAME[$bi]}" == RF4_Sync ]] && printf "  [%s]" "$(t bk_badge_sync)")"$'\n'"        ${BK_PATH[$bi]}"$'\n'"        ${BK_SRC[$bi]}"$'\n'"        $(bk_info "$bi")"$'\n'"        ${BK_DATES[$bi]}"); done
        bopts+=("$(t manual_path)")
        menu "$(t pick_backup_list)" "${bopts[@]}"; (( MENU_CHOICE == 0 )) && return
        (( MENU_CHOICE <= ${#BK_PATH[@]} )) && src="${BK_PATH[$((MENU_CHOICE - 1))]}"
    else warn "$(t no_backup_found_cli)"; fi
    if [[ -z "$src" ]]; then
        read -r -p "  $(t backup_dir_p "$def") " src || src=""
        [[ -z "$src" ]] && src="$def"
    fi
    [[ -d "$src" ]] || { err "$(t folder_missing "$src")"; pause; return; }
    local rp; rp="$(resolve_backup_path "$src")"
    [[ -z "$rp" ]] && { err "$(t restore_path_bad)"; pause; return; }
    src="$rp"
    load_mailboxes "$src"
    local -a bk_names=("${MB_NAME[@]}") bk_ids=("${MB_ID[@]}") bk_convs=("${MB_CONVS[@]}") bk_files=()
    local f i shots=0
    for f in "${DAT_FILES[@]}"; do [[ -f "$src/$f" ]] && bk_files+=("$f"); done
    [[ -d "$src/Screenshots" ]] && shots=$(find "$src/Screenshots" -type f 2>/dev/null | wc -l | tr -d ' ')
    if (( ${#bk_names[@]} + ${#bk_files[@]} + shots == 0 )); then warn "$(t no_backup_here)"; pause; return; fi
    info "$(t contents)"
    for i in "${!bk_names[@]}"; do info "  $(t bk_mailbox "${bk_names[$i]}" "${bk_convs[$i]}")"; done
    for f in "${bk_files[@]:-}"; do [[ -n "$f" ]] && info "  $f"; done
    (( shots > 0 )) && info "  $(t bk_shots "$shots")"

    find_installations
    local -a opts=()
    for i in "${!INST_PATH[@]}"; do opts+=("$(inst_label "$i")$( (( INST_EXISTS[i] )) || printf '  %s' "$(t scan_empty)")"); done
    opts+=("$(t manual_path)")
    menu "$(t pick_target)" "${opts[@]}"; (( MENU_CHOICE == 0 )) && return
    local dst
    if (( MENU_CHOICE <= ${#INST_PATH[@]} )); then dst="${INST_PATH[$((MENU_CHOICE - 1))]}"; else read -r -p "  $(t enter_path): " dst || dst=""; fi
    [[ -z "$dst" ]] && { err "$(t no_path)"; pause; return; }

    local -a avail=() labels=()
    (( ${#bk_names[@]} > 0 )) && { avail+=(mail); labels+=("$(item_label mail) (${#bk_names[@]})"); }
    for f in "${bk_files[@]:-}"; do [[ -n "$f" ]] && { avail+=("$f"); labels+=("$(item_label "$f")"); }; done
    (( shots > 0 )) && { avail+=(shots); labels+=("$(item_label shots) ($shots)"); }
    multiselect "$(t what_restore)" "${labels[@]}"
    if (( MULTI_CANCEL )) || (( ${#MULTI_SEL[@]} == 0 )); then warn "$(t nothing_sel)"; pause; return; fi
    local items=""; for i in "${MULTI_SEL[@]}"; do items+="${avail[$i]} "; done
    ACCOUNTS=""; ACC_BACK=0
    if [[ " $items " == *" mail "* ]]; then
        load_mailboxes "$src"; select_accounts "$src" which_acct_r
        (( ACC_BACK )) && return
    fi
    confirm_game_closed || { warn "$(t cancelled)"; pause; return; }
    info "$(t importing_to "$dst")"; sep
    reset_stats
    copy_rf4data "$src" "$dst" "$items" "$ACCOUNTS" "$src/Screenshots" "$(screenshot_dir "$dst" create)" "$(new_undo_root "$dst")"
    add_backup_dir "$(dirname "$src")"
    ok "$(t restore_done)"; print_summary
    pause
}

# ── MERGE ──────────────────────────────────────────────────────────────────────
do_merge() {
    hdr "$(t hdr_merge)"
    find_installations; existing_indices
    if (( ${#EXIST_IDX[@]} < 2 )); then warn "$(t merge_need2)"; pause; return; fi
    echo; warn "$(t merge_note)"; info "$(t merge_safe)"
    local -a labels=(); local i
    for i in "${EXIST_IDX[@]}"; do labels+=("$(inst_label "$i")"); done
    menu "$(t merge_dst)" "${labels[@]}"; (( MENU_CHOICE == 0 )) && return
    local di="${EXIST_IDX[$((MENU_CHOICE - 1))]}"
    local -a src_idx=() src_labels=()
    for i in "${EXIST_IDX[@]}"; do [[ "$i" != "$di" ]] && { src_idx+=("$i"); src_labels+=("$(inst_label "$i")"); }; done
    if (( ${#src_idx[@]} == 0 )); then err "$(t merge_nosrc)"; pause; return; fi
    multiselect "$(t merge_src)" "${src_labels[@]}"
    if (( MULTI_CANCEL )) || (( ${#MULTI_SEL[@]} == 0 )); then warn "$(t pick_one_src)"; pause; return; fi
    confirm_game_closed || { warn "$(t cancelled)"; pause; return; }
    local dpath="${INST_PATH[$di]}" undo; undo=$(new_undo_root "$dpath")
    info "$(t to "$dpath")"; sep
    reset_stats
    local k si
    for k in "${MULTI_SEL[@]}"; do
        si="${src_idx[$k]}"
        info "$(t merge_src_hdr "$(inst_label "$si")")"
        load_mailboxes "${INST_PATH[$si]}"; select_accounts "${INST_PATH[$si]}" which_acct_m
        (( ACC_BACK )) && continue
        copy_rf4data "${INST_PATH[$si]}" "$dpath" "mail" "$ACCOUNTS" "" "" "$undo"
    done
    ok "$(t merge_done)"; print_summary
    pause
}

# ── SYNC ───────────────────────────────────────────────────────────────────────
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

do_sync_run() {   # do_sync_run instpath syncbase
    local inst="$1" sd="$2/RF4_Sync" undo dat lf sf lt st i
    mkdir -p "$sd"; undo=$(new_undo_root "$inst")
    info "$(t sync_local "$inst")"; info "$(t sync_remote "$sd")"
    info "$(t sync_p1)"
    load_mailboxes "$inst"
    (( ${#MB_NAME[@]} == 0 )) && warn "$(t sync_nolocal)"
    local -a n=("${MB_NAME[@]:-}") p=("${MB_PATH[@]:-}")
    for i in "${!n[@]}"; do [[ -n "${n[$i]}" ]] || continue; info "$(t mb_header "${n[$i]}")"; merge_mailbox "${p[$i]}" "$sd/${n[$i]}" ""; done
    info "$(t sync_p2)"
    load_mailboxes "$sd"
    (( ${#MB_NAME[@]} == 0 )) && warn "$(t sync_noremote)"
    n=("${MB_NAME[@]:-}"); p=("${MB_PATH[@]:-}")
    for i in "${!n[@]}"; do [[ -n "${n[$i]}" ]] || continue; info "$(t mb_header "${n[$i]}")"; merge_mailbox "${p[$i]}" "$inst/${n[$i]}" "$undo"; done
    info "$(t sync_p3)"
    for dat in "${DAT_FILES[@]}"; do
        lf="$inst/$dat"; sf="$sd/$dat"
        if [[ -f "$lf" && ! -f "$sf" ]]; then cp -p "$lf" "$sf"; ok "$(t sync_up "$dat")"
        elif [[ ! -f "$lf" && -f "$sf" ]]; then cp -p "$sf" "$lf"; ok "$(t sync_down "$dat")"
        elif [[ -f "$lf" && -f "$sf" ]]; then
            if files_identical "$lf" "$sf"; then info "$(t sync_same "$dat")"
            else
                lt=$(file_mtime "$lf"); st=$(file_mtime "$sf")
                if (( lt > st )); then cp -pf "$lf" "$sf"; ok "$(t sync_up_new "$dat")"
                elif (( st > lt )); then save_undo "$lf" "$undo"; cp -pf "$sf" "$lf"; ok "$(t sync_down_new "$dat")"
                else info "$(t sync_same "$dat")"; fi
            fi
        fi
    done
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname 2>/dev/null || echo host)" >> "$sd/.sync_log"
    [[ -d "$undo" ]] && info "$(t undo_saved "$undo")"
    ok "$(t sync_done)"
}

do_sync() {
    hdr "$(t hdr_sync)"; printf '%s\n' "  ${D}$(t sync_intro)${NC}"
    local sp raw np i
    while true; do
        sp=$(sync_get); echo
        if [[ -z "$sp" ]]; then printf '%s\n' "  ${Y}$(t sync_none)${NC}"
        elif [[ -d "$sp" ]]; then ok "$(t sync_ok "$sp")"
        else warn "$(t sync_unreach "$sp")"; printf '%s\n' "  ${D}$(t sync_unreach_h)${NC}"; fi
        echo
        printf '%s\n' "  ${Y}[1]${NC} $(t sync_run)" "  ${Y}[2]${NC} $(t sync_cfg)" "  ${Y}[3]${NC} $(t sync_status)" "  ${Y}[0]${NC} $(t back)"
        echo
        read -r -p "  $(t choose): " raw || return
        case "${raw//[[:space:]]/}" in
            0) return ;;
            2) echo; printf '%s\n' "  ${W}$(t sync_enter)${NC}"
               read -r -p "  > " np || np=""
               if [[ -n "$np" ]]; then
                   if mkdir -p "$np" 2>/dev/null; then sync_set "$np"; ok "$(t sync_saved "$np")"; else err "$(t sync_mkfail "$np")"; fi
               fi
               pause ;;
            3) if [[ -z "$sp" ]]; then warn "$(t sync_none)"
               elif [[ ! -d "$sp" ]]; then err "$(t sync_unreach "$sp")"
               else
                   info "$(t sync_ok "$sp")"
                   if [[ ! -d "$sp/RF4_Sync" ]]; then warn "$(t sync_st_nodir)"
                   else
                       load_mailboxes "$sp/RF4_Sync"
                       (( ${#MB_NAME[@]} == 0 )) && warn "$(t sync_st_none)"
                       for i in "${!MB_NAME[@]}"; do info "  $(t sync_st_boxes "${MB_NAME[$i]}" "${MB_CONVS[$i]}")"; done
                       local d; for d in "${DAT_FILES[@]}"; do [[ -f "$sp/RF4_Sync/$d" ]] && info "  $d: $(date -r "$sp/RF4_Sync/$d" '+%Y-%m-%d %H:%M' 2>/dev/null)"; done
                       if [[ -f "$sp/RF4_Sync/.sync_log" ]]; then echo; info "$(t sync_st_log)"; tail -n 5 "$sp/RF4_Sync/.sync_log" | while IFS= read -r l; do info "  $l"; done; fi
                   fi
               fi
               pause ;;
            1) if [[ -z "$sp" ]]; then warn "$(t sync_first)"; pause; continue; fi
               if [[ ! -d "$sp" ]]; then err "$(t sync_unreach "$sp")"; info "$(t sync_unreach_h)"; pause; continue; fi
               find_installations; existing_indices
               if (( ${#EXIST_IDX[@]} == 0 )); then err "$(t no_inst)"; pause; continue; fi
               local ci
               if (( ${#EXIST_IDX[@]} == 1 )); then ci="${EXIST_IDX[0]}"; info "$(inst_label "$ci")"
               else
                   local -a lb=(); for i in "${EXIST_IDX[@]}"; do lb+=("$(inst_label "$i")"); done
                   menu "$(t sync_which)" "${lb[@]}"; (( MENU_CHOICE == 0 )) && continue
                   ci="${EXIST_IDX[$((MENU_CHOICE - 1))]}"
               fi
               confirm_game_closed || { warn "$(t cancelled)"; pause; continue; }
               reset_stats; do_sync_run "${INST_PATH[$ci]}" "$sp"; print_summary
               pause ;;
            *) warn "$(t invalid)" ;;
        esac
    done
}

# ── Sprache ────────────────────────────────────────────────────────────────────
do_language() {
    local -a names=() l
    for l in "${LANGS[@]}"; do names+=("${LANG_NAMES[$l]}"); done
    menu "$(t lang_prompt)" "${names[@]}"; (( MENU_CHOICE == 0 )) && return
    LANG_CODE="${LANGS[$((MENU_CHOICE - 1))]}"; cfg_set lang "$LANG_CODE"
    ok "$(t lang_changed)"
}

# ── Hauptmenü ──────────────────────────────────────────────────────────────────
main_menu() {
    local raw
    while true; do
        [[ -t 1 ]] && clear 2>/dev/null
        box "$(t app_title)   v${TOOL_VERSION}" "RF4: nga.li/rf4de  $G_DOT  Blog: nga.li/rf4b" "$(t donate)"
        echo
        printf '%s\n' "  ${Y}[1]${NC} $(t menu_scan)" "  ${Y}[2]${NC} $(t menu_backup)" "  ${Y}[3]${NC} $(t menu_restore)" \
                      "  ${Y}[4]${NC} $(t menu_merge)" "  ${Y}[5]${NC} $(t menu_sync)" \
                      "  ${Y}[H]${NC} $(t menu_help)" "  ${Y}[L]${NC} $(t menu_lang) (${LANG_NAMES[$LANG_CODE]})" "  ${Y}[0]${NC} $(t exit)" ""
        read -r -p "  $(t choose): " raw || return 0
        raw="${raw,,}"; raw="${raw//[[:space:]]/}"
        case "$raw" in
            1) do_scan ;; 2) do_backup ;; 3) do_restore ;; 4) do_merge ;; 5) do_sync ;;
            l) do_language ;; h) open_guide ;; 0) return 0 ;;
        esac
    done
}

# ── Start ──────────────────────────────────────────────────────────────────────
ARG_LANG=""; SHOW_HELP=0
while (( $# > 0 )); do
    case "$1" in
        -l|--lang) ARG_LANG="${2:-}"; shift 2 || shift ;;
        -h|--help) SHOW_HELP=1; shift ;;
        *) shift ;;
    esac
done
load_external_langs
init_lang "$ARG_LANG"
if (( SHOW_HELP )); then echo "$(t usage)"; exit 0; fi
if [[ "${RF4_NO_MAIN:-0}" != "1" ]]; then main_menu; fi
