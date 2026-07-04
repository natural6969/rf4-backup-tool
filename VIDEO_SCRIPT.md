# RF4 Backup Tool v1.3.0 – Video Walkthrough Script
## Produktion: 4K · Deutsch · ~6 Min · Untertitel/Overlays

**Account für Aufnahme:** Br_ina / RF4 Standalone  
**Tool:** rf4sa-backup-gui.ps1 (GUI-Version)  
**Auflösung:** 3840×2160 · 60fps empfohlen  
**Software:** OBS + DaVinci Resolve (Captions) oder OBS Text-Overlay direkt

---

## SZENE 1 — Intro / Titelkarte (0:00–0:18)

**Screen:** Schwarzer Hintergrund → Fade-in  
**Musik:** Leise ambient / lofi (kein Copyright)

### Text-Overlay (zentriert):
```
RF4 Backup Tool
Mailboxen · Einstellungen · Screenshots sichern

Version 1.3.0 · Kostenlos · Open Source
natural.yt
```

**Action:** Nichts — reine Titelkarte  
**Caption:** —  
**Dauer:** 18 Sekunden

---

## SZENE 2 — Download & SHA256 Prüfung (0:18–0:55)

**Screen:** Browser auf natural.yt/... (Artikel-Seite)

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 0:18 | **„Erstes Mal? Hier herunterladen."** |
| 0:22 | Download-Bereich scrollen – grüner Button sichtbar |
| 0:28 | Klick auf „⬇ Download (.exe)" ODER .ps1 |
| 0:33 | **„Vor dem Start: SHA256 prüfen."** |
| 0:38 | PowerShell öffnen |

### Action:
```
1. Browser → Artikel Download-Sektion
2. rf4sa-backup-gui-setup-v1.2.0.exe herunterladen (sichtbar im Browser)
3. PowerShell öffnen (Win+X → Terminal)
4. Eingeben:
   Get-FileHash "$env:USERPROFILE\Downloads\rf4sa-backup-gui-setup-v1.2.0.exe" -Algorithm SHA256
5. Hash wird angezeigt
6. Vergleich mit Artikel → Overlay zeigt beide Zeilen nebeneinander
```

### Overlay bei Hash-Anzeige:
```
Erwartet: c4175e31fd82b041e2f2...
Angezeigt: c4175e31fd82b041e2f2...   ✓ IDENTISCH
```

**Caption:** „Stimmt der Hash überein – wurde die Datei nicht verändert."

---

## SZENE 3 — Tool starten (0:55–1:25)

**Screen:** Desktop / Downloads-Ordner

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 0:55 | **„Installer starten – einmalig."** |
| 1:02 | Doppelklick auf .exe → Windows SmartScreen-Dialog |
| 1:06 | **„SmartScreen-Warnung: normal bei neuen Tools."** |
| 1:09 | „Weitere Informationen" → „Trotzdem ausführen" |
| 1:14 | Installer läuft durch |
| 1:18 | **„Gestartet. Das ist die Hauptansicht."** |

### Action:
```
1. Doppelklick rf4sa-backup-gui-setup-v1.2.0.exe
2. SmartScreen: "Weitere Informationen" klicken → "Trotzdem ausführen"
3. Installer: Weiter → Installieren → Fertigstellen
4. Tool öffnet sich automatisch
5. Kurze Pause auf Hauptfenster – alle 5 Buttons sichtbar:
   [Scan] [Backup] [Restore] [Merge] [Sync]
```

### Overlay auf Hauptfenster:
```
┌─────────────────────────────────────┐
│  RF4 SA Backup & Migration Tool     │
│  Backup · Restore · Merge · Sync    │
│                                     │
│  [1] Scan    [2] Backup             │
│  [3] Restore [4] Merge   [5] Sync   │
└─────────────────────────────────────┘
  ↑ Die 5 Funktionen – heute alle gezeigt
```

---

## SZENE 4 — Scan (1:25–1:55)

**Screen:** Tool Hauptfenster

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 1:25 | **„Schritt 1: Scan – Was ist installiert?"** |
| 1:28 | Klick auf [Scan] |
| 1:32 | Scan läuft – Ladebalken sichtbar |
| 1:38 | Ergebnis: RF4 Standalone Deutsch gefunden |
| 1:42 | **„Gefunden: RF4 SA · Account Br_ina · 3 Mailboxen"** |
| 1:48 | **„Das Tool kennt jetzt alle Installationen auf diesem PC."** |

### Action:
```
1. Klick [Scan]
2. Warten bis Ergebnis erscheint
3. Kamera/Screen hält auf:
   [OK] RF4 Standalone Deutsch [C: / Br_ina]
        Mailboxen: 3 · Konversationen: XX · Accounts: XXXXX
4. Kurze Pause (2 Sek)
```

### Overlay:
```
[OK] RF4 Standalone Deutsch
     Pfad: C:\Users\Br_ina\AppData\Roaming\...
     Mailboxen: 3 · Nachrichten: XX
     ← Alles automatisch erkannt
```

---

## SZENE 5 — Backup (1:55–3:00)

**Screen:** Tool – Backup-Funktion

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 1:55 | **„Schritt 2: Backup – Daten sichern."** |
| 1:58 | Klick auf [Backup] |
| 2:03 | Installation aus Liste wählen |
| 2:08 | **„Was soll gesichert werden? Auswahl treffen."** |
| 2:12 | Mailboxen + Settings ✓, Rest nach Wahl |
| 2:18 | **„Zielordner: Standard oder eigener Pfad."** |
| 2:24 | Zielordner bestätigen |
| 2:28 | Backup läuft |
| 2:38 | **„Fertig. Backup liegt in:"** |
| 2:42 | Pfad einblenden: C:\Users\Br_ina\RF4_Backup\ |
| 2:48 | Explorer öffnen – Backup-Ordner zeigen |
| 2:54 | **„Originaldateien unberührt. Nur Kopien."** |

### Action:
```
1. Klick [Backup]
2. Installation wählen (RF4 SA Deutsch)
3. Auswahl:
   [X] Mailboxen
   [X] Settings.dat
   [ ] Preferences.dat   (abwählen für Demo)
   [ ] Crafting.dat
   [ ] Screenshots
4. Zielordner: Standard (C:\Users\Br_ina\RF4_Backup\)
5. Backup starten
6. Ergebnis-Log zeigen:
   [OK] Mailbox_XXXXX: X Dateien gesichert
   [OK] Settings.dat kopiert
7. Explorer öffnen → RF4_Backup-Ordner zeigen (Ordnerstruktur sichtbar)
```

### Overlay nach Backup:
```
RF4_Backup\
 └─ RussianFishing4DE\
     ├─ Mailbox_XXXXX\
     │   └─ *.json (Nachrichten)
     └─ Settings.dat
  ✓ Backup vollständig
```

---

## SZENE 6 — Restore (3:00–3:45)

**Screen:** Tool – Restore-Funktion

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 3:00 | **„Schritt 3: Restore – Backup zurückspielen."** |
| 3:04 | Klick auf [Restore] |
| 3:08 | Backup-Ordner angeben (vorhin erstellter) |
| 3:14 | **„Ziel-Installation wählen."** |
| 3:18 | RF4 SA Deutsch als Ziel |
| 3:24 | Restore startet |
| 3:32 | **„Mailboxen werden gemergt – nichts überschrieben."** |
| 3:38 | **„Ideal für: Neuinstallation, PC-Wechsel."** |

### Action:
```
1. Klick [Restore]
2. Backup-Ordner angeben: C:\Users\Br_ina\RF4_Backup\
3. Ziel-Installation wählen
4. Restore starten
5. Log zeigen:
   [OK] Mailbox_XXXXX: X bestehend, X neue Nachrichten hinzugefügt
   [OK] Settings.dat: identisch, übersprungen
```

### Overlay:
```
Restore:
 Neue Nachrichten: +X
 Bereits vorhanden: X (übersprungen)
 Settings: unverändert
 ← Nichts geht verloren
```

---

## SZENE 7 — Sync (3:45–5:10)

**Screen:** Tool – Sync-Funktion  
**Dies ist die Hauptszene – mehr Zeit**

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 3:45 | **„Schritt 4: Sync – Der Highlight dieser Version."** |
| 3:50 | **„Ziel: Mailboxen auf PC und Laptop immer gleich."** |
| 3:55 | Klick auf [Sync] |
| 4:00 | **„Sync-Ordner angeben – z.B. Nextcloud, NAS oder USB."** |
| 4:05 | Ordner-Browser öffnet sich |
| 4:10 | Demo-Ordner wählen (z.B. Desktop/RF4-Sync-Demo) |
| 4:16 | **„Phase 1: Lokale Daten hochladen."** |
| 4:22 | Sync startet – Phase 1 im Log sichtbar |
| 4:30 | **„Phase 2: Daten von anderen Geräten herunterladen."** |
| 4:36 | Phase 2 im Log sichtbar |
| 4:44 | **„Settings: neuere Version gewinnt automatisch."** |
| 4:50 | Sync abgeschlossen |
| 4:55 | Explorer: RF4_Sync-Ordner zeigen |
| 5:02 | **„Diesen Ordner auf Nextcloud/Syncthing legen"** |
| 5:06 | **„→ alle Geräte automatisch synchron."** |

### Action:
```
1. Klick [Sync]
2. Sync-Ordner wählen:
   Option A: Einen Desktop-Ordner "RF4-Sync-Demo" vorab anlegen
   Option B: Echten Nextcloud-Ordner verwenden falls vorhanden
3. Sync starten
4. Log zeigen:
   === Phase 1: Lokal -> Sync (hochladen) ===
   Up Mailbox_XXXXX...
     + chat_guild.dat: X neue Nachrichten
   [OK] Settings.dat -> Sync (neu hochgeladen)

   === Phase 2: Sync -> Lokal (herunterladen) ===
   [!] Noch keine Mailboxen von anderen Geräten
       (erstes Mal – normal)

   === Einstellungen ===
   Settings.dat: identisch, übersprungen
5. Explorer: RF4_Sync/ Ordner öffnen → Struktur zeigen
6. Overlay: Schema PC ↔ Sync-Ordner ↔ Laptop
```

### Overlay – Sync-Schema (wichtig, gut lesbar):
```
     GAMING-PC                    LAPTOP
  RF4 Mailboxen              RF4 Mailboxen
       │                          │
       ▼                          ▼
  ┌────────────────────────────────────┐
  │     Nextcloud / Syncthing / NAS    │
  │          RF4_Sync/                 │
  │    Mailbox_XXXXX/  Settings.dat    │
  └────────────────────────────────────┘
       ↑ Sync starten = beide Seiten aktuell
```

### Erklärungs-Overlay Services:
```
Funktioniert mit:
✓ Nextcloud  (selbst gehostet)
✓ Syncthing  (lokal, kein Server nötig)
✓ NAS        (Netzlaufwerk N:\)
✓ USB-Stick  (manuell)
✓ OneDrive / Dropbox / Google Drive
```

---

## SZENE 8 — Merge (5:10–5:45)

**Screen:** Tool – Merge-Funktion  
**Kürzer halten – Konzept reicht**

### Caption-Sequenz:
| Zeit | Text |
|------|------|
| 5:10 | **„Bonus: Merge – Zwei Installationen zusammenführen."** |
| 5:15 | **„Z.B. Steam-Version → Standalone wechseln."** |
| 5:20 | Klick [Merge] |
| 5:24 | Ziel wählen: RF4 SA |
| 5:28 | Quelle wählen (zweite Installation oder Backup-Ordner) |
| 5:32 | **„Nur neue Nachrichten werden ergänzt. Nie doppelt."** |
| 5:38 | Ergebnis zeigen |

### Action:
```
1. Klick [Merge]
2. Ziel: RF4 SA Deutsch
3. Quelle: RF4_Backup-Ordner von Szene 5 (simuliert zweite Installation)
4. Merge starten
5. Log: "+X neue Nachrichten hinzugefügt"
```

---

## SZENE 9 — Outro (5:45–6:05)

**Screen:** Fade to black + Text-Overlay

### Overlay:
```
RF4 Backup Tool v1.3.0

⬇  Download:    nga.li/rf4dl
📄  Artikel:     nga.li/rf4b
💻  Quellcode:   Codeberg · GitHub
☕  Unterstützen: paypal.me/bjoernoppermann

Kostenlos · Open Source · Windows + Linux
```

**Caption:** „Fragen und Feedback gerne im Kommentar."  
**Musik:** Fade out

---

## SCHNITT-HINWEISE für DaVinci Resolve

```
- Übergänge: Cross Dissolve 8 Frames
- Overlays: Fusion Text Node, Hintergrund #0f172a, Text #f1f5f9
- Schrift: Segoe UI / Inter, Bold für Titel, Regular für Captions
- Caption-Position: unteres Drittel, ca. 80px vom unteren Rand
- Log-Fenster-Ausschnitte: ggf. zoomen auf 150% für 4K-Lesbarkeit
- SHA256-Szene: Split-Screen links Terminal / rechts Artikel
```

---

## YOUTUBE-BESCHREIBUNG

```
RF4 Backup Tool v1.3.0 – Vollständiger Walkthrough (DE)

Kostenloses Tool zum Sichern und Synchronisieren von Russian Fishing 4 Spielerdaten:
Mailboxen, Einstellungen, Screenshots.

Gezeigt in diesem Video:
00:00 Intro
00:18 Download & SHA256-Prüfung
00:55 Installation & erster Start
01:25 Scan – Installationen automatisch finden
01:55 Backup erstellen
03:00 Restore – Backup zurückspielen
03:45 Cloud/NAS Sync – PC und Laptop synchron halten
05:10 Merge – zwei Installationen zusammenführen
05:45 Links & Outro

Unterstützte Sync-Dienste: Nextcloud · Syncthing · NAS · USB · OneDrive/Dropbox/GDrive
Sprachen: Deutsch · English · Русский · 中文

⬇ Download:   https://nga.li/rf4dl
📄 Artikel:    https://nga.li/rf4b
💻 Codeberg:   https://nga.li/rf4git
💻 GitHub:     https://github.com/natural6969/rf4-backup-tool
☕ Spenden:    https://paypal.me/bjoernoppermann

#RussianFishing4 #RF4 #Backup #Tool #Sync #Nextcloud #Gaming
```

---

## AUFNAHME-CHECKLISTE

- [ ] RF4 Standalone installiert, Account Br_ina eingeloggt, Spiel einmal gestartet
- [ ] rf4sa-backup-gui-setup-v1.2.0.exe heruntergeladen (von nga.li/rf4dl)
- [ ] Demo-Ordner `C:\RF4-Sync-Demo\` auf Desktop angelegt
- [ ] OBS auf 3840×2160@60fps eingestellt, Bitrate ≥ 40.000 kbps
- [ ] Cursor-Highlighting in OBS aktivieren (gut sichtbar für Zuschauer)
- [ ] Alle nicht relevanten Fenster/Tabs geschlossen
- [ ] Mikrofon-Stille OK (rein Captions) ODER Mikrofon bereit für Kommentar
- [ ] Zweite Aufnahme-Runde für saubere Takes einplanen
