RF4 Backup Tool v1.5.0
======================
Backup- und Migrationstool fuer Russian Fishing 4 (Standalone + Steam)
Backup & migration tool for Russian Fishing 4 (Standalone + Steam)
RF4 备份与迁移工具 / Инструмент резервного копирования и переноса RF4

SPRACHEN / LANGUAGES / 语言 / ЯЗЫКИ:
  Deutsch, English, 中文, Русский - umschaltbar im Programm (Sprachwahl oben rechts bzw. Menue [L]).
  Switchable inside the program (language box top right / menu [L]).

DESIGN / THEME:
  Dunkel und Hell automatisch nach Windows (oder manuell) / dark and light, automatic (or manual).
  Eigene Sprachen und Designs: Vorlagen im Ordner examples\ / custom languages and themes: templates in examples\

FUNKTIONEN / FEATURES:
  - Vorhandene Backups werden aufgelistet / existing backups are listed
  - Scan: findet alle RF4-Installationen / finds all RF4 installations
  - Backup & Restore: Mailboxen, Settings.dat, Preferences.dat, Crafting.dat, Screenshots
  - Merge: Nachrichten mehrerer Installationen zusammenfuehren (nur fehlende werden ergaenzt)
  - Restore auch aus Sync-Ordner / NAS; Backups zeigen Quelle + Datum / restore from sync folder or NAS; backups show source + date
  - Hilfe-Button (GUI) / [H] (Terminal): Anleitung mit Screenshots in der Programmsprache / help opens the guide in the program language (docs\)
  - Cloud / NAS Sync (Nextcloud, Syncthing, Netzlaufwerk, USB ...)
  - Es wird nichts geloescht (Deinstallation: Startmenue-Eintrag, Spieldaten und Backups bleiben). Ersetzte Dateien werden vorher nach
    <Installation>\_rf4tool_undo\<Zeitstempel> kopiert.
    Nothing is deleted. Files that get replaced are copied to _rf4tool_undo first.

VARIANTEN / VARIANTS:
  - GUI Version:      rf4sa-backup-gui-v1.5.0.ps1
  - Terminal Version: rf4sa-backup-v1.5.0.ps1
  - Linux/Mac Shell:  rf4sa-backup-v1.5.0.sh

AUSFUEHREN / HOW TO RUN:
  Per Startmenue-Verknuepfung, oder Rechtsklick auf die .ps1 Datei -> "Mit PowerShell ausfuehren"
  Via Start Menu shortcut, or right-click the .ps1 file -> "Run with PowerShell"
  Bitte RF4 vor Restore/Merge/Sync beenden. / Please close RF4 before restore/merge/sync.

QUELLE / SOURCE:
  https://codeberg.org/Natural78/rf4-backup-tool
  https://nga.li/rf4git

SPENDEN / DONATE:
  Wenn dir das Tool gefaellt, freue ich mich ueber eine Spende!
  If you like this tool, donations are welcome!
  https://paypal.me/bjoernoppermann

LIZENZ / LICENSE: MIT
