# RF4 Standalone — Backup & Migration Tool

Kostenloses Tool zum Sichern und Übertragen von Russian Fishing 4 Spielerdaten:
Mailboxen (In-Game-Chats), Einstellungen, Screenshots.

Für Windows (PowerShell, mit GUI) und Linux (Bash).

📄 **Vollständige Anleitung:** [nga.li/rf4b](https://nga.li/rf4b)
📥 **Direkter Download:** [nga.li/rf4dl](https://nga.li/rf4dl)

---

## Installer (Windows)

| Datei | Beschreibung |
|---|---|
| `rf4sa-backup-gui-setup-v1.2.0.exe` | GUI-Version — empfohlen für Einsteiger |
| `rf4sa-backup-cli-setup-v1.2.0.exe` | CLI-Version (Terminal) |
| `rf4sa-backup-full-setup-v1.2.0.exe` | GUI + CLI zusammen |

→ Download unter [Releases](../../releases)

---

## Dateien (ohne Installer)

| Datei | Plattform | Beschreibung |
|---|---|---|
| `rf4sa-backup-gui.ps1` | Windows 10/11 | Grafische Oberfläche — direkt ausführbar, kein Installer nötig |
| `rf4sa-backup.ps1` | Windows 7/10/11 | Terminal-Version (Textmenü) |
| `rf4sa-backup.sh` | Linux, macOS | Bash-Script — Wine & Proton automatisch erkannt |

---

## Was wird gesichert?

- **Mailboxen** — In-Game-Chats zwischen Spielern (lokal gespeichert, nicht auf RF4-Servern)
- **Settings.dat** — Grafik, Audio, Tastenbelegung
- **Preferences.dat** — weitere Spieleinstellungen
- **Crafting.dat** — Craftingdaten
- **Screenshots**

Spielstand, Inventar und Angelausrüstung liegen auf den RF4-Servern und sind beim PC-Wechsel automatisch da.

---

## Funktionen

- **Scan** — findet alle RF4-Installationen automatisch (Windows, Wine, Steam/Proton)
- **Backup** — sichert Daten in einen Ordner deiner Wahl
- **Restore** — importiert ein Backup in eine Installation
- **Merge** — führt zwei Installationen zusammen (nur fehlende Nachrichten werden ergänzt, nichts überschrieben)
- **Cloud / NAS Sync** — bidirektionaler Sync zwischen mehreren Geräten über Nextcloud, Syncthing, NAS-Netzlaufwerk, USB-Stick oder jeden gemeinsamen Ordner

---

## Benutzung

### Windows — Cloud / NAS Sync

Menüpunkt **[5] Sync** → Sync-Ordner angeben (Nextcloud, Syncthing, NAS `N:\`, USB-Stick oder jeder gemeinsame Ordner) → Sync starten.

Der Sync läuft bidirektional:
- **Phase 1** – Lokale Mailboxen werden in den Sync-Ordner gemergt (Push)
- **Phase 2** – Neue Nachrichten aus dem Sync-Ordner werden lokal übernommen (Pull)
- Settings.dat / Preferences.dat / Crafting.dat: neuere Datei gewinnt (Zeitstempel-Vergleich)

---

### Windows — Installer (empfohlen)

`rf4sa-backup-gui-setup-v1.2.0.exe` herunterladen und ausführen. Installiert das Tool systemweit.

### Windows — GUI (ohne Installer)

```
Rechtsklick auf rf4sa-backup-gui.ps1 → "Mit PowerShell ausführen"
```

Das Fenster öffnet sich direkt.

### Windows — Terminal

```powershell
powershell -ExecutionPolicy Bypass -File rf4sa-backup.ps1
```

### Linux

```bash
chmod +x rf4sa-backup.sh
bash rf4sa-backup.sh
```

---

## Sicherheit & Verifikation

Das Tool **verändert keine Originaldaten** — es erstellt ausschließlich Kopien.

Der Quellcode ist vollständig in diesen Dateien einsehbar.

SHA256-Prüfsummen verifizieren:

```powershell
# Windows
Get-FileHash rf4sa-backup-gui.ps1 -Algorithm SHA256
Get-FileHash rf4sa-backup.ps1     -Algorithm SHA256
Get-FileHash rf4sa-backup.sh      -Algorithm SHA256
```

```bash
# Linux
sha256sum rf4sa-backup-gui.ps1 rf4sa-backup.ps1 rf4sa-backup.sh
```

Erwartete Hashes → siehe [CHECKSUMS.txt](CHECKSUMS.txt)

---

## Unterstützte RF4-Varianten

| Ordnername | Bezeichnung |
|---|---|
| `RussianFishing4DE` | RF4 Standalone Deutsch |
| `RussianFishing4DE_new` | RF4 Standalone Deutsch (neu) |
| `RussianFishing4EN` | RF4 Standalone Englisch |
| `RussianFishing4Steam` | RF4 Steam (via Proton/Wine) |

---

## Typische Anwendungsfälle

**PC-Wechsel / Neuinstallation:**
1. Auf altem PC: Backup erstellen
2. RF4 auf neuem PC installieren und einmal starten
3. Backup → Restore auf neuen PC

**Steam → Standalone wechseln:**
1. Steam-Installation scannen
2. Merge: Steam als Quelle, Standalone als Ziel

**Wichtig:** RF4 erlaubt offiziell nur Steam → Standalone, nicht umgekehrt.
Details: [nga.li/rf4transfer](https://nga.li/rf4transfer)

---

## Voraussetzungen

**Windows:**
- PowerShell 5.1 (ab Windows 7 vorinstalliert)
- Python 3 (nur für Mailbox-Merge, optional — wird automatisch erkannt)

**Linux:**
- bash, python3, jq (meist vorinstalliert)
- `sshpass` oder `jq` nur wenn explizit benötigt

---

## Lizenz

MIT License — frei verwendbar, veränderbar und weitergabe-erlaubt.

---

## Links

| | |
|---|---|
| RF4 Offiziell (DE) | [nga.li/rf4de](https://nga.li/rf4de) |
| RF4 Offiziell (EN) | [nga.li/rf4en](https://nga.li/rf4en) |
| RF4 auf Steam | [nga.li/rf4steam](https://nga.li/rf4steam) |
| Steam → Standalone Transfer | [nga.li/rf4transfer](https://nga.li/rf4transfer) |
| Forum | [nga.li/rf4forum](https://nga.li/rf4forum) |
| Artikel & Anleitung | [nga.li/rf4b](https://nga.li/rf4b) |
