# RF4 — Backup & Migration Tool

Kostenloses Tool zum Sichern und Übertragen von Russian Fishing 4 Spielerdaten:
Mailboxen (In-Game-Chats), Einstellungen, Screenshots.
Für **Windows** (GUI + Terminal, PowerShell) und **Linux/macOS** (Bash).

**Sprachen / Languages / 语言 / Языки:** Deutsch · English · 中文 · Русский — komplett umschaltbar im Programm
(GUI: Auswahlfeld oben rechts · Terminal: Menüpunkt **[L]** · Start-Parameter `-Lang de|en|zh|ru` bzw. `-l xx` · Umgebungsvariable `RF4_LANG`).
Die Wahl wird gespeichert.

📄 **Anleitung:** [nga.li/rf4b](https://nga.li/rf4b) · 📥 **Download:** [nga.li/rf4dl](https://nga.li/rf4dl)

---

## Dateien

| Datei | Plattform | Beschreibung |
|---|---|---|
| `rf4sa-backup-gui.ps1` | Windows 7/10/11 | Grafische Oberfläche (Schritt-für-Schritt) |
| `rf4sa-backup.ps1` | Windows 7/10/11 | Terminal-Version (Textmenü) |
| `rf4sa-backup.sh` | Linux, macOS, Git-Bash | Bash-Version — Windows-Partitionen, Wine und Steam-Proton werden erkannt |
| `installer/*.iss` | Windows | InnoSetup-Skripte für die Installer (`.exe`) |

Kein Installer nötig: Rechtsklick auf `rf4sa-backup-gui.ps1` → „Mit PowerShell ausführen“.

## Funktionen

- **Scan** — findet alle RF4-Installationen (DE / EN / Steam / weitere Ordner unter `RussianFishingLLC`, alle Benutzer und Laufwerke)
- **Backup** — Mailboxen (alle oder ein Account), Settings.dat, Preferences.dat, Crafting.dat, Screenshots
- **Restore** — Backup in eine Installation importieren (Nachrichten werden zusammengeführt)
- **Merge** — Installationen zusammenführen: nur fehlende Nachrichten werden ergänzt (Dedup über Nachrichten-ID, sortiert nach Zeit)
- **Cloud / NAS Sync** — bidirektional über jeden gemeinsamen Ordner (Nextcloud, Syncthing, NAS, USB); Einstellungsdateien: neuere gewinnt

## Sicherheit

- **Es wird nichts gelöscht.** Backup und Scan lesen nur.
- Bei Restore / Merge / Sync wird jede **zu ersetzende Datei vorher** nach `<Installation>\_rf4tool_undo\<Zeitstempel>\` kopiert.
- Nachrichten-Dateien werden nur geschrieben, wenn tatsächlich neue Nachrichten dazukommen; geschrieben wird über eine Temp-Datei und erst nach erfolgreicher Gegenprobe ersetzt.
- RF4 wird vor Restore/Merge/Sync als laufender Prozess erkannt (Warnung) — bitte das Spiel vorher beenden.

SHA256-Prüfsummen: siehe [CHECKSUMS.txt](CHECKSUMS.txt) (`Get-FileHash <datei>` bzw. `sha256sum <datei>`).
Die GUI zeigt oben rechts den eigenen SHA256-Hash (Klick = kopieren).

## Ablageorte der Daten

```
%APPDATA%\RussianFishingLLC\<Variante>\Mailbox_<AccountID>\*.dat    (JSON, UTF-8 mit BOM)
%APPDATA%\RussianFishingLLC\<Variante>\Settings.dat / Preferences.dat / Crafting.dat
Dokumente\Russian Fishing 4\Screenshots
```

Varianten: `RussianFishing4DE`, `RussianFishing4DE_new`, `RussianFishing4EN`, `RussianFishing4Steam` (weitere Ordner werden automatisch erkannt).

## Typische Anwendungsfälle

**PC-Wechsel:** Auf dem alten PC *Backup* → RF4 auf dem neuen PC einmal starten → *Restore*.
**Steam → Standalone:** *Merge* mit Steam als Quelle und Standalone als Ziel. RF4 erlaubt offiziell nur Steam → Standalone, nicht umgekehrt ([nga.li/rf4transfer](https://nga.li/rf4transfer)).
**Mehrere Geräte:** *Sync* mit einem gemeinsamen Ordner auf jedem Gerät.

## Voraussetzungen

- **Windows:** Windows PowerShell 5.1 (ab Windows 10 vorinstalliert; Windows 7 mit WMF 5.1). Python wird **nicht** benötigt.
- **Linux/macOS:** bash ≥ 4 (macOS: `brew install bash`) und `python3` (nur zum Zusammenführen der Nachrichten-Dateien).

## Entwicklung

Der Quellcode liegt in `src/` (`core.ps1` = gemeinsame Logik + alle Übersetzungen, `cli.ps1`, `gui.ps1`, `cli.sh`).
`build.ps1` erzeugt daraus die ausgelieferten Einzeldateien (auch die Übersetzungstabelle des Bash-Skripts wird aus `core.ps1` erzeugt — eine Quelle für alle Plattformen).

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
powershell -ExecutionPolicy Bypass -File tests\Test-Core.ps1 [-RealDataDir <Mailbox-Ordner>]   # Logik, Übersetzungen, Merge, Sync
powershell -STA -ExecutionPolicy Bypass -File tests\Test-Gui.ps1                               # GUI: alle Panels × 4 Sprachen, Textüberlauf, Button-Läufe
bash tests/test-sh.sh                                                                          # Linux-Skript
```

Neue Sprache oder neuer Text: Eintrag in `src/core.ps1` (`X 'schluessel' 'de' 'en' 'zh' 'ru'`), `build.ps1` ausführen — die Tests prüfen, dass jeder Schlüssel in allen Sprachen vorhanden ist und die Platzhalter `{0}`, `{1}` übereinstimmen.

## Änderungen

**1.4.0**
- Komplett überarbeitet auf gemeinsamem Kern: Terminal, GUI und Bash nutzen dieselbe Logik und dieselbe Übersetzungstabelle.
- **Alles** ist übersetzt (DE/EN/ZH/RU), nicht nur die Menüs; Sprache jederzeit umschaltbar und gespeichert.
- Fix: Die **eigene Installation wurde nie gefunden** (Benutzerordner wurde eine Ebene zu niedrig aus `%APPDATA%` abgeleitet).
- Fix: Abstürze bei genau einer Mailbox/Datei oder leerer Installation (`StrictMode` + `.Count` in PowerShell 5.1).
- Fix: Screenshots wurden beim Restore nicht kopiert (`-Include` ohne `-Recurse`).
- Merge schreibt nur noch bei neuen Nachrichten, atomar mit Gegenprobe; Undo-Ordner für ersetzte Dateien.
- Warnung, wenn RF4 läuft; GUI: Sprachwahl, Account-Auswahl, Fortschritts-/Ergebnisansicht, korrekte Anzeige von „&“.
- Automatische Tests (228 Prüfungen) und `build.ps1`.

**1.3.0** i18n (nur Menüs), InnoSetup-Installer · **1.2.0** Cloud/NAS-Sync · **1.1.x** Account-IDs, Multi-Quellen-Merge · **1.0.0** Erstveröffentlichung

---

## English summary

Free backup & migration tool for **Russian Fishing 4** player data (in-game mailboxes, settings, screenshots) for Windows (GUI + terminal, PowerShell 5.1) and Linux/macOS (bash + python3).
The whole interface is available in **German, English, Chinese and Russian** and can be switched at any time (GUI language box, terminal menu **[L]**, `-Lang xx`, or `RF4_LANG=xx`).
Nothing is ever deleted; files that get replaced are first copied to `<installation>\_rf4tool_undo\<timestamp>`. Close RF4 before restore/merge/sync.

## 中文简介

用于 **Russian Fishing 4** 玩家数据（游戏内邮箱、设置、截图）的免费备份与迁移工具，支持 Windows（图形界面 + 终端）和 Linux/macOS。
界面完整支持 **德语、英语、中文、俄语**，可随时切换。工具不会删除任何文件；被替换的文件会先保存到 `_rf4tool_undo` 文件夹。恢复/合并/同步前请先关闭游戏。

## Кратко по-русски

Бесплатный инструмент резервного копирования и переноса данных игрока **Russian Fishing 4** (игровая почта, настройки, скриншоты) для Windows (GUI + терминал) и Linux/macOS.
Интерфейс полностью доступен на **немецком, английском, китайском и русском** языках и переключается в любой момент. Ничего не удаляется; заменяемые файлы сначала копируются в `_rf4tool_undo`. Перед восстановлением/объединением/синхронизацией закройте игру.

---

MIT License · Spenden / Donate: [paypal.me/bjoernoppermann](https://paypal.me/bjoernoppermann) · [Codeberg](https://codeberg.org/Natural78/rf4-backup-tool)
