#Requires -Version 5.1
<#
.SYNOPSIS
    RF4 Backup & Migration Tool – GUI
.DESCRIPTION
    Findet RF4-Installationen (Standalone + Steam) und sichert, stellt wieder her, führt zusammen
    und synchronisiert Mailboxen, Einstellungen und Screenshots. Es wird nichts gelöscht; ersetzte
    Dateien landen in <Installation>\_rf4tool_undo\<Zeitstempel>.
    Sprachen: Deutsch, English, 中文, Русский (im Programm umschaltbar, oder -Lang de|en|zh|ru,
    oder Umgebungsvariable RF4_LANG).
.NOTES
    Start: Rechtsklick -> "Mit PowerShell ausführen"  oder  powershell -ExecutionPolicy Bypass -File <Datei>
    Blog: https://nga.li/rf4b | Quellcode: https://nga.li/rf4git | Download: https://nga.li/rf4dl
    Spenden/Donate: https://paypal.me/bjoernoppermann
.LINK
    https://nga.li/rf4b
#>
# Version 1.4.0 – 2026-10-09
param([string]$Lang = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# ══════════════════════════════════════════════════════════════════════════════
#  RF4 Backup Tool – gemeinsamer Kern (Logik + Übersetzungen), keine UI
#  Wird von build.ps1 in rf4sa-backup.ps1 (CLI) und rf4sa-backup-gui.ps1 (GUI) eingebettet.
# ══════════════════════════════════════════════════════════════════════════════
$script:ToolVersion = '1.4.0'
$script:ToolDate    = '2026-10-09'
$script:Langs       = @('de', 'en', 'zh', 'ru')
$script:LangNames   = [ordered]@{ de = 'Deutsch'; en = 'English'; zh = '中文'; ru = 'Русский' }
$script:DatFiles    = @('Settings.dat', 'Preferences.dat', 'Crafting.dat')
$script:LogSink     = $null

# ── Übersetzungen ──────────────────────────────────────────────────────────────
$script:TX = @{}
function X([string]$k, [string]$de, [string]$en, [string]$zh, [string]$ru) {
    $script:TX[$k] = @{ de = $de; en = $en; zh = $zh; ru = $ru }
}

# Allgemein
X 'app_title'     'RF4 Backup & Migration'  'RF4 Backup & Migration'  'RF4 备份与迁移'  'RF4 Резервное копирование и перенос'
X 'donate'        'Spenden: paypal.me/bjoernoppermann' 'Donate: paypal.me/bjoernoppermann' '捐赠: paypal.me/bjoernoppermann' 'Поддержать: paypal.me/bjoernoppermann'
X 'back'          'Zurück'   'Back'    '返回'   'Назад'
X 'next'          'Weiter'   'Next'    '下一步' 'Далее'
X 'exit'          'Beenden'  'Exit'    '退出'   'Выход'
X 'choose'        'Auswahl'  'Choice'  '选择'   'Выбор'
X 'continue'      '[Enter] zum Fortfahren' '[Enter] to continue' '按 [Enter] 继续' '[Enter] — продолжить'
X 'invalid'       'Ungültige Eingabe' 'Invalid input' '输入无效' 'Неверный ввод'
X 'toggle_hint'   '(Nummer = ein/aus, a = alle, n = keine, Enter = OK, 0 = Zurück)' '(number = toggle, a = all, n = none, Enter = OK, 0 = back)' '(数字 = 切换, a = 全选, n = 全不选, Enter = 确定, 0 = 返回)' '(номер = вкл/выкл, a = все, n = ничего, Enter = ОК, 0 = назад)'
X 'yes_char'       'j' 'y' 'y' 'д'
X 'yn_overwrite'   '{0} existiert bereits. Überschreiben? [j/N]' '{0} already exists. Overwrite? [y/N]' '{0} 已存在。是否覆盖？[y/N]' '{0} уже существует. Перезаписать? [д/Н]'
X 'language'      'Sprache' 'Language' '语言' 'Язык'
X 'lang_prompt'   'Sprache wählen' 'Choose language' '选择语言' 'Выберите язык'
X 'lang_changed'  'Sprache geändert.' 'Language changed.' '语言已更改。' 'Язык изменён.'
X 'running_warn'  'RF4 scheint zu laufen ({0}). Bitte das Spiel VOR Restore/Merge/Sync beenden, sonst werden Änderungen überschrieben.' 'RF4 seems to be running ({0}). Please close the game BEFORE restore/merge/sync, otherwise changes get overwritten.' '检测到 RF4 正在运行 ({0})。请在恢复/合并/同步之前关闭游戏，否则更改会被覆盖。' 'RF4, похоже, запущена ({0}). Закройте игру ПЕРЕД восстановлением/объединением/синхронизацией, иначе изменения будут перезаписаны.'
X 'running_ask'   'Trotzdem fortfahren?' 'Continue anyway?' '仍要继续吗？' 'Всё равно продолжить?'
X 'cancelled'     'Abgebrochen.' 'Cancelled.' '已取消。' 'Отменено.'

# Menü / Aktionen
X 'menu_scan'     'Scan – Alle Installationen anzeigen' 'Scan – Show all installations' '扫描 – 显示所有安装' 'Сканировать – показать все установки'
X 'menu_backup'   'Backup – Daten sichern' 'Backup – Save data to a folder' '备份 – 将数据保存到文件夹' 'Резервная копия – сохранить данные в папку'
X 'menu_restore'  'Restore – Aus Backup importieren' 'Restore – Import from a backup' '恢复 – 从备份导入' 'Восстановить – импорт из резервной копии'
X 'menu_merge'    'Merge – Installationen zusammenführen' 'Merge – Combine installations' '合并 – 合并多个安装' 'Объединить – слить установки'
X 'menu_sync'     'Sync – Mit Cloud/NAS abgleichen' 'Sync – Synchronize with cloud/NAS' '同步 – 与云/NAS同步' 'Синхронизация – облако/NAS'
X 'menu_lang'     'Sprache wechseln' 'Change language' '切换语言' 'Сменить язык'
X 'act_backup'    'Backup erstellen' 'Create backup' '创建备份' 'Создать резервную копию'
X 'act_backup_d'  'RF4-Daten (Chats, Einstellungen, Screenshots) in einen Ordner sichern.' 'Save RF4 data (chats, settings, screenshots) to a folder.' '将 RF4 数据（聊天、设置、截图）保存到文件夹。' 'Сохранить данные RF4 (чаты, настройки, скриншоты) в папку.'
X 'act_restore'    'Backup wiederherstellen' 'Restore backup' '恢复备份' 'Восстановить из копии'
X 'act_restore_d' 'Gesicherte Daten in eine RF4-Installation importieren. Nachrichten werden zusammengeführt.' 'Import saved data into an RF4 installation. Messages are merged.' '将已保存的数据导入 RF4 安装。消息会被合并。' 'Импортировать сохранённые данные в установку RF4. Сообщения объединяются.'
X 'act_merge'     'Installationen zusammenführen' 'Merge installations' '合并安装' 'Объединить установки'
X 'act_merge_d'   'Nachrichten aus anderen Installationen ergänzen – nichts wird überschrieben.' 'Add messages from other installations – nothing is overwritten.' '从其他安装补充消息——不会覆盖任何内容。' 'Добавить сообщения из других установок — ничего не перезаписывается.'
X 'act_sync'      'Cloud / NAS Sync' 'Cloud / NAS sync' '云 / NAS 同步' 'Синхронизация облако / NAS'
X 'act_sync_d'    'Mailboxen zwischen PC, Laptop und NAS abgleichen (Nextcloud, Syncthing, Netzlaufwerk, USB).' 'Sync mailboxes between PC, laptop and NAS (Nextcloud, Syncthing, network drive, USB).' '在电脑、笔记本和 NAS 之间同步邮箱（Nextcloud、Syncthing、网络驱动器、USB）。' 'Синхронизация почты между ПК, ноутбуком и NAS (Nextcloud, Syncthing, сетевой диск, USB).'

# Scan
X 'hdr_scan'      'INSTALLATIONEN SCANNEN' 'SCAN INSTALLATIONS' '扫描安装' 'ПОИСК УСТАНОВОК'
X 'scanning'      'Suche auf allen Laufwerken…' 'Searching all drives…' '正在搜索所有驱动器…' 'Поиск на всех дисках…'
X 'none_found'    'Keine Installationen gefunden.' 'No installations found.' '未找到安装。' 'Установки не найдены.'
X 'found_n'       'Gefunden: {0} Installation(en)' 'Found: {0} installation(s)' '已找到：{0} 个安装' 'Найдено установок: {0}'
X 'scan_path'     'Pfad: {0}' 'Path: {0}' '路径: {0}' 'Путь: {0}'
X 'scan_stats'    'Mailboxen: {0}  Konversationen: {1}' 'Mailboxes: {0}  Conversations: {1}' '邮箱: {0}  对话: {1}' 'Ящиков: {0}  Диалогов: {1}'
X 'scan_accounts' 'Account-IDs: {0}' 'Account IDs: {0}' '账号 ID: {0}' 'ID аккаунтов: {0}'
X 'scan_empty'    '(noch nicht vorhanden)' '(not present yet)' '(尚不存在)' '(пока отсутствует)'
X 'scan_total'    'Gesamt: {0} Pfade geprüft' 'Total: {0} paths checked' '共检查 {0} 个路径' 'Всего проверено путей: {0}'
X 'scan_readonly' 'Sicher: Das Tool liest nur – Originaldaten werden nicht verändert.' 'Safe: the tool only reads – original data is not modified.' '安全：本工具只读取，不会修改原始数据。' 'Безопасно: программа только читает — исходные данные не меняются.'

# Varianten / Orte
X 'v_DE'      'RF4 Standalone Deutsch' 'RF4 Standalone German' 'RF4 独立版（德语）' 'RF4 Standalone (немецкая)'
X 'v_DE_new'  'RF4 Standalone Deutsch (neu)' 'RF4 Standalone German (new)' 'RF4 独立版（德语，新）' 'RF4 Standalone (немецкая, новая)'
X 'v_EN'      'RF4 Standalone Englisch' 'RF4 Standalone English' 'RF4 独立版（英语）' 'RF4 Standalone (английская)'
X 'v_Steam'   'RF4 Steam' 'RF4 Steam' 'RF4 Steam 版' 'RF4 Steam'
X 'v_Other'   'RF4 ({0})' 'RF4 ({0})' 'RF4 ({0})' 'RF4 ({0})'
X 'w_user'    'Benutzer: {0}' 'User: {0}' '用户: {0}' 'Пользователь: {0}'
X 'w_drive'   'Laufwerk: {0} / {1}' 'Drive: {0} / {1}' '驱动器: {0} / {1}' 'Диск: {0} / {1}'
X 'w_extra'   'Pfad: {0}' 'Path: {0}' '路径: {0}' 'Путь: {0}'
X 'w_win'     'Windows: {0} / {1}' 'Windows: {0} / {1}' 'Windows: {0} / {1}' 'Windows: {0} / {1}'
X 'w_wine'    'Wine: {0}' 'Wine: {0}' 'Wine: {0}' 'Wine: {0}'
X 'w_proton'  'Proton: AppID {0}' 'Proton: AppID {0}' 'Proton: AppID {0}' 'Proton: AppID {0}'
X 'need_python' 'python3 wird für das Zusammenführen der Nachrichten benötigt (Debian/Ubuntu: sudo apt install python3).' 'python3 is required to merge messages (Debian/Ubuntu: sudo apt install python3).' '合并消息需要 python3（Debian/Ubuntu: sudo apt install python3）。' 'Для объединения сообщений нужен python3 (Debian/Ubuntu: sudo apt install python3).'
X 'usage'      'Aufruf: rf4sa-backup.sh [-l de|en|zh|ru]' 'Usage: rf4sa-backup.sh [-l de|en|zh|ru]' '用法: rf4sa-backup.sh [-l de|en|zh|ru]' 'Использование: rf4sa-backup.sh [-l de|en|zh|ru]'

# Backup
X 'hdr_backup'    'BACKUP' 'BACKUP' '备份' 'РЕЗЕРВНАЯ КОПИЯ'
X 'pick_source'   'Quelle wählen – von welcher Installation sichern?' 'Choose source – back up which installation?' '选择来源——备份哪个安装？' 'Выберите источник — какую установку копировать?'
X 'what_backup'   'Was soll gesichert werden?' 'What should be backed up?' '要备份什么？' 'Что копировать?'
X 'what_restore'  'Was soll importiert werden?' 'What should be imported?' '要导入什么？' 'Что импортировать?'
X 'item_mail'     'Mailboxen (private Nachrichten)' 'Mailboxes (private messages)' '邮箱（私人消息）' 'Почтовые ящики (личные сообщения)'
X 'item_Settings.dat'    'Settings.dat (Grafik/Audio/Tasten)' 'Settings.dat (graphics/audio/keys)' 'Settings.dat（画面/音频/按键）' 'Settings.dat (графика/звук/клавиши)'
X 'item_Preferences.dat' 'Preferences.dat' 'Preferences.dat' 'Preferences.dat' 'Preferences.dat'
X 'item_Crafting.dat'    'Crafting.dat' 'Crafting.dat' 'Crafting.dat' 'Crafting.dat'
X 'item_shots'    'Screenshots' 'Screenshots' '截图' 'Скриншоты'
X 'nothing_sel'   'Nichts ausgewählt.' 'Nothing selected.' '未选择任何内容。' 'Ничего не выбрано.'
X 'backup_dir'    'Backup-Ordner' 'Backup folder' '备份文件夹' 'Папка резервной копии'
X 'backup_dir_p'  'Backup-Ordner [{0}] (Enter = Standard)' 'Backup folder [{0}] (Enter = default)' '备份文件夹 [{0}]（Enter = 默认）' 'Папка копии [{0}] (Enter = по умолчанию)'
X 'from'          'Von: {0}' 'From: {0}' '来源: {0}' 'Откуда: {0}'
X 'to'            'Nach: {0}' 'To: {0}' '目标: {0}' 'Куда: {0}'
X 'backup_done'   'Backup fertig: {0}' 'Backup finished: {0}' '备份完成: {0}' 'Резервная копия готова: {0}'
X 'run_backup'    'Backup starten' 'Start backup' '开始备份' 'Начать копирование'
X 'no_inst'       'Keine Installationen gefunden.' 'No installations found.' '未找到安装。' 'Установки не найдены.'
X 'which_acct_b'  'Welchen Account sichern?' 'Which account to back up?' '备份哪个账号？' 'Какой аккаунт копировать?'
X 'which_acct_r'  'Welchen Account importieren?' 'Which account to import?' '导入哪个账号？' 'Какой аккаунт импортировать?'
X 'which_acct_m'  'Welche Accounts aus dieser Quelle mergen?' 'Which accounts to merge from this source?' '从该来源合并哪些账号？' 'Какие аккаунты объединить из этого источника?'
X 'all_accts'     'Alle Accounts ({0})' 'All accounts ({0})' '所有账号 ({0})' 'Все аккаунты ({0})'
X 'acct_line'     'Account {0}  ({1} Konversationen)' 'Account {0}  ({1} conversations)' '账号 {0}  ({1} 个对话)' 'Аккаунт {0}  (диалогов: {1})'

# Restore
X 'hdr_restore'   'RESTORE / IMPORT' 'RESTORE / IMPORT' '恢复 / 导入' 'ВОССТАНОВЛЕНИЕ / ИМПОРТ'
X 'pick_backup'   'Backup-Ordner wählen' 'Choose backup folder' '选择备份文件夹' 'Выберите папку резервной копии'
X 'pick_backup_d' 'Wähle den Ordner, der dein RF4-Backup enthält.' 'Choose the folder that contains your RF4 backup.' '请选择包含 RF4 备份的文件夹。' 'Выберите папку с вашей резервной копией RF4.'
X 'folder_missing' 'Ordner nicht gefunden: {0}' 'Folder not found: {0}' '未找到文件夹: {0}' 'Папка не найдена: {0}'
X 'no_backup_here' 'Kein RF4-Backup in diesem Ordner gefunden.' 'No RF4 backup found in this folder.' '该文件夹中没有 RF4 备份。' 'В этой папке нет резервной копии RF4.'
X 'contents'       'Inhalt:' 'Contents:' '内容:' 'Содержимое:'
X 'bk_mailbox'    '{0}: {1} Konversationen' '{0}: {1} conversations' '{0}: {1} 个对话' '{0}: диалогов {1}'
X 'bk_shots'      'Screenshots: {0} Dateien' 'Screenshots: {0} files' '截图: {0} 个文件' 'Скриншоты: файлов {0}'
X 'pick_target'   'Ziel-Installation' 'Target installation' '目标安装' 'Целевая установка'
X 'manual_path'   '→ Pfad manuell eingeben' '→ Enter path manually' '→ 手动输入路径' '→ Ввести путь вручную'
X 'enter_path'    'Pfad eingeben' 'Enter path' '输入路径' 'Введите путь'
X 'no_path'       'Kein Pfad angegeben.' 'No path given.' '未提供路径。' 'Путь не указан.'
X 'importing_to'  'Importiere nach: {0}' 'Importing to: {0}' '正在导入到: {0}' 'Импорт в: {0}'
X 'restore_done'  'Import abgeschlossen.' 'Import finished.' '导入完成。' 'Импорт завершён.'
X 'run_restore'   'Restore starten' 'Start restore' '开始恢复' 'Начать восстановление'

# Merge
X 'hdr_merge'     'INSTALLATIONEN MERGEN' 'MERGE INSTALLATIONS' '合并安装' 'ОБЪЕДИНЕНИЕ УСТАНОВОК'
X 'merge_need2'   'Mindestens 2 vorhandene Installationen nötig.' 'At least 2 existing installations are required.' '至少需要 2 个现有安装。' 'Нужно минимум 2 существующие установки.'
X 'merge_note'    'RF4 erlaubt nur den Wechsel Steam → Standalone, nicht umgekehrt. Details: https://nga.li/rf4transfer' 'RF4 only allows switching Steam → Standalone, not the other way round. Details: https://nga.li/rf4transfer' 'RF4 只允许从 Steam 切换到独立版，反之不行。详情: https://nga.li/rf4transfer' 'RF4 позволяет переходить только Steam → Standalone, но не наоборот. Подробнее: https://nga.li/rf4transfer'
X 'merge_safe'    'Nur fehlende Nachrichten werden ergänzt. Vorhandene Daten werden nicht überschrieben.' 'Only missing messages are added. Existing data is not overwritten.' '仅补充缺失的消息，不会覆盖现有数据。' 'Добавляются только недостающие сообщения. Существующие данные не перезаписываются.'
X 'merge_dst'      'Ziel (Hauptinstallation, bleibt erhalten)' 'Target (main installation, is kept)' '目标（主安装，将保留）' 'Цель (основная установка, сохраняется)'
X 'merge_src'     'Quellen (mehrere möglich)' 'Sources (multiple allowed)' '来源（可多选）' 'Источники (можно несколько)'
X 'merge_src_ctrl' 'Quellen (Strg+Klick = Mehrfachauswahl)' 'Sources (Ctrl+click = multi-select)' '来源（Ctrl+点击 = 多选）' 'Источники (Ctrl+клик = несколько)'
X 'merge_nosrc'    'Keine weiteren Installationen als Quellen verfügbar.' 'No other installations available as sources.' '没有其他可用作来源的安装。' 'Нет других установок в качестве источников.'
X 'merge_src_hdr' 'Quelle: {0}' 'Source: {0}' '来源: {0}' 'Источник: {0}'
X 'merge_same'    'Quelle und Ziel dürfen nicht identisch sein.' 'Source and target must not be the same.' '来源和目标不能相同。' 'Источник и цель не должны совпадать.'
X 'merge_done'    'Merge abgeschlossen.' 'Merge finished.' '合并完成。' 'Объединение завершено.'
X 'run_merge'     'Merge starten' 'Start merge' '开始合并' 'Начать объединение'
X 'pick_one_src'  'Bitte mindestens eine Quelle wählen.' 'Please select at least one source.' '请至少选择一个来源。' 'Выберите хотя бы один источник.'
X 'pick_dst'      'Bitte Ziel-Installation wählen.' 'Please select a target installation.' '请选择目标安装。' 'Выберите целевую установку.'
X 'pick_src'      'Bitte eine Quelle wählen.' 'Please select a source.' '请选择来源。' 'Выберите источник.'
X 'pick_item'     'Bitte mindestens eine Option wählen.' 'Please select at least one option.' '请至少选择一项。' 'Выберите хотя бы один пункт.'
X 'pick_action'   'Bitte eine Aktion wählen.' 'Please select an action.' '请选择一个操作。' 'Выберите действие.'
X 'what_todo'     'Was möchtest du tun?' 'What would you like to do?' '您想做什么？' 'Что вы хотите сделать?'

# Sync
X 'hdr_sync'      'CLOUD / NAS SYNC' 'CLOUD / NAS SYNC' '云 / NAS 同步' 'СИНХРОНИЗАЦИЯ ОБЛАКО / NAS'
X 'sync_intro'    'Ordnerbasierter Sync – Nextcloud, NAS-Laufwerk, Syncthing, USB, OneDrive.' 'Folder-based sync – Nextcloud, NAS drive, Syncthing, USB, OneDrive.' '基于文件夹的同步——Nextcloud、NAS 驱动器、Syncthing、USB、OneDrive。' 'Синхронизация через папку — Nextcloud, NAS, Syncthing, USB, OneDrive.'
X 'sync_none'     'Kein Sync-Ordner konfiguriert.' 'No sync folder configured.' '尚未配置同步文件夹。' 'Папка синхронизации не настроена.'
X 'sync_ok'       'Sync-Ordner: {0}' 'Sync folder: {0}' '同步文件夹: {0}' 'Папка синхронизации: {0}'
X 'sync_unreach'  'Sync-Ordner nicht erreichbar: {0}' 'Sync folder not reachable: {0}' '无法访问同步文件夹: {0}' 'Папка синхронизации недоступна: {0}'
X 'sync_unreach_h' 'NAS eingebunden? Cloud-Sync aktiv? USB angesteckt?' 'NAS mounted? Cloud sync running? USB plugged in?' 'NAS 已挂载？云同步已启动？U 盘已插入？' 'NAS подключён? Облачная синхронизация активна? USB вставлен?'
X 'sync_run'      'Sync jetzt ausführen (bidirektional)' 'Run sync now (bidirectional)' '立即同步（双向）' 'Синхронизировать сейчас (двусторонне)'
X 'sync_cfg'      'Sync-Ordner konfigurieren' 'Configure sync folder' '配置同步文件夹' 'Настроить папку синхронизации'
X 'sync_status'   'Sync-Status anzeigen' 'Show sync status' '显示同步状态' 'Показать состояние синхронизации'
X 'sync_enter'    'Sync-Ordner eingeben (z.B. N:\RF4-Sync, D:\RF4-Sync):' 'Enter sync folder (e.g. N:\RF4-Sync, D:\RF4-Sync):' '输入同步文件夹（例如 N:\RF4-Sync, D:\RF4-Sync）:' 'Введите папку синхронизации (напр. N:\RF4-Sync, D:\RF4-Sync):'
X 'sync_saved'    'Gespeichert: {0}' 'Saved: {0}' '已保存: {0}' 'Сохранено: {0}'
X 'sync_mkfail'   'Ordner konnte nicht erstellt werden: {0}' 'Folder could not be created: {0}' '无法创建文件夹: {0}' 'Не удалось создать папку: {0}'
X 'sync_first'    'Bitte zuerst den Sync-Ordner konfigurieren.' 'Please configure the sync folder first.' '请先配置同步文件夹。' 'Сначала настройте папку синхронизации.'
X 'sync_which'    'Welche Installation synchronisieren?' 'Which installation to sync?' '同步哪个安装？' 'Какую установку синхронизировать?'
X 'sync_local'    'Lokal:  {0}' 'Local:  {0}' '本地:  {0}' 'Локально:  {0}'
X 'sync_remote'   'Sync:   {0}' 'Sync:   {0}' '同步:   {0}' 'Синхр.:   {0}'
X 'sync_p1'       'Phase 1: Lokal → Sync (neue Nachrichten hochladen)' 'Phase 1: local → sync (upload new messages)' '阶段 1：本地 → 同步（上传新消息）' 'Этап 1: локально → синхр. (загрузка новых сообщений)'
X 'sync_p2'       'Phase 2: Sync → Lokal (neue Nachrichten herunterladen)' 'Phase 2: sync → local (download new messages)' '阶段 2：同步 → 本地（下载新消息）' 'Этап 2: синхр. → локально (скачивание новых сообщений)'
X 'sync_p3'       'Einstellungen (neuere Version gewinnt)' 'Settings (newer version wins)' '设置（以较新版本为准）' 'Настройки (побеждает более новая версия)'
X 'sync_nolocal'  'Keine lokalen Mailboxen – nur Download wird ausgeführt.' 'No local mailboxes – download only.' '没有本地邮箱——仅执行下载。' 'Локальных ящиков нет — только загрузка.'
X 'sync_noremote' 'Der Sync-Ordner enthält noch keine Mailboxen anderer Geräte.' 'The sync folder has no mailboxes from other devices yet.' '同步文件夹中还没有来自其他设备的邮箱。' 'В папке синхронизации ещё нет ящиков с других устройств.'
X 'sync_done'     'Sync abgeschlossen!' 'Sync finished!' '同步完成！' 'Синхронизация завершена!'
X 'sync_up'       '{0} → Sync (hochgeladen)' '{0} → sync (uploaded)' '{0} → 同步（已上传）' '{0} → синхр. (загружено)'
X 'sync_down'     '{0} ← Sync (heruntergeladen)' '{0} ← sync (downloaded)' '{0} ← 同步（已下载）' '{0} ← синхр. (скачано)'
X 'sync_up_new'   '{0} → Sync (lokal neuer)' '{0} → sync (local is newer)' '{0} → 同步（本地较新）' '{0} → синхр. (локальный новее)'
X 'sync_down_new' '{0} ← Sync (Sync neuer)' '{0} ← sync (sync is newer)' '{0} ← 同步（同步版较新）' '{0} ← синхр. (в синхр. новее)'
X 'sync_same'     '{0}: identisch, übersprungen' '{0}: identical, skipped' '{0}: 相同，已跳过' '{0}: одинаковы, пропущено'
X 'sync_st_boxes' '{0}: {1} Konversationen' '{0}: {1} conversations' '{0}: {1} 个对话' '{0}: диалогов {1}'
X 'sync_st_none'  'Noch keine Mailboxen im Sync-Ordner.' 'No mailboxes in the sync folder yet.' '同步文件夹中还没有邮箱。' 'В папке синхронизации ещё нет ящиков.'
X 'sync_st_nodir' 'Noch kein RF4_Sync-Unterordner. Bitte zuerst einen Sync ausführen.' 'No RF4_Sync subfolder yet. Please run a sync first.' '还没有 RF4_Sync 子文件夹。请先执行一次同步。' 'Подпапки RF4_Sync ещё нет. Сначала выполните синхронизацию.'
X 'sync_st_log'   'Letzte Sync-Einträge:' 'Recent sync entries:' '最近的同步记录:' 'Последние записи синхронизации:'
X 'sync_hint'     'Nextcloud-Ordner · NAS-Netzlaufwerk (N:\) · Syncthing-Ordner · USB-Stick' 'Nextcloud folder · NAS network drive (N:\) · Syncthing folder · USB stick' 'Nextcloud 文件夹 · NAS 网络驱动器 (N:\) · Syncthing 文件夹 · U 盘' 'Папка Nextcloud · сетевой диск NAS (N:\) · папка Syncthing · USB-накопитель'
X 'sync_dir_lbl'  'Sync-Ordner:' 'Sync folder:' '同步文件夹:' 'Папка синхронизации:'
X 'sync_inst_lbl' 'Installation:' 'Installation:' '安装:' 'Установка:'
X 'sync_pick_dir' 'Sync-Ordner wählen (z.B. Nextcloud-Ordner oder NAS-Laufwerk)' 'Choose sync folder (e.g. Nextcloud folder or NAS drive)' '选择同步文件夹（例如 Nextcloud 文件夹或 NAS 驱动器）' 'Выберите папку синхронизации (напр. Nextcloud или диск NAS)'

# Operationen (Log)
X 'mb_header'     'Mailbox {0}…' 'Mailbox {0}…' '邮箱 {0}…' 'Ящик {0}…'
X 'mb_merge_file' 'Merge {0}: +{1} Nachrichten' 'Merge {0}: +{1} messages' '合并 {0}: +{1} 条消息' 'Слияние {0}: +{1} сообщ.'
X 'mb_merge_fail' 'Merge fehlgeschlagen: {0} – {1}' 'Merge failed: {0} – {1}' '合并失败: {0} – {1}' 'Ошибка слияния: {0} – {1}'
X 'mb_summary'    'Mailbox: {0} gemergt, {1} neu kopiert, {2} unverändert' 'Mailbox: {0} merged, {1} newly copied, {2} unchanged' '邮箱: {0} 个已合并, {1} 个新复制, {2} 个未变化' 'Ящик: слито {0}, скопировано новых {1}, без изменений {2}'
X 'no_mailboxes'  'Keine Mailboxen gefunden.' 'No mailboxes found.' '未找到邮箱。' 'Почтовые ящики не найдены.'
X 'f_copied'      '{0} kopiert' '{0} copied' '{0} 已复制' '{0} скопирован'
X 'f_overwritten' '{0} überschrieben' '{0} overwritten' '{0} 已覆盖' '{0} перезаписан'
X 'f_skipped'     '{0} übersprungen' '{0} skipped' '{0} 已跳过' '{0} пропущен'
X 'f_identical'   '{0} identisch, nichts zu tun' '{0} identical, nothing to do' '{0} 相同，无需处理' '{0} идентичен, ничего не делаем'
X 'f_missing'     '{0} nicht gefunden' '{0} not found' '未找到 {0}' '{0} не найден'
X 'f_failed'      '{0} fehlgeschlagen: {1}' '{0} failed: {1}' '{0} 失败: {1}' '{0}: ошибка: {1}'
X 'shots_done'    'Screenshots: {0} Bilder → {1}' 'Screenshots: {0} images → {1}' '截图: {0} 张 → {1}' 'Скриншоты: {0} изобр. → {1}'
X 'shots_none'    'Screenshot-Ordner nicht gefunden' 'Screenshot folder not found' '未找到截图文件夹' 'Папка скриншотов не найдена'
X 'undo_saved'    'Ersetzte Dateien gesichert in: {0}' 'Replaced files saved in: {0}' '被替换的文件已保存到: {0}' 'Заменённые файлы сохранены в: {0}'
X 'result_title'  'Fertig' 'Done' '完成' 'Готово'
X 'btn_open'      'Ordner öffnen' 'Open folder' '打开文件夹' 'Открыть папку'
X 'btn_home'      'Zum Start' 'Back to start' '返回开始' 'В начало'
X 'btn_close'     'Schließen' 'Close' '关闭' 'Закрыть'
X 'btn_browse'    'Durchsuchen…' 'Browse…' '浏览…' 'Обзор…'
X 'working'       'Bitte warten…' 'Please wait…' '请稍候…' 'Пожалуйста, подождите…'
X 'step1'         '1. Scan' '1. Scan' '1. 扫描' '1. Поиск'
X 'step2'         '2. Aktion' '2. Action' '2. 操作' '2. Действие'
X 'step3'         '3. Quelle' '3. Source' '3. 来源' '3. Источник'
X 'step4'         '4. Optionen' '4. Options' '4. 选项' '4. Параметры'
X 'step5'         '5. Fertig' '5. Done' '5. 完成' '5. Готово'
X 'hash_label'    'SHA256: {0}…' 'SHA256: {0}…' 'SHA256: {0}…' 'SHA256: {0}…'
X 'hash_click'    '(Klicken zum Kopieren)' '(click to copy)' '（点击复制）' '(нажмите, чтобы скопировать)'
X 'hash_copied'   'SHA256-Prüfsumme kopiert:' 'SHA256 checksum copied:' 'SHA256 校验和已复制:' 'Контрольная сумма SHA256 скопирована:'
X 'hash_unknown'  'SHA256: (Pfad unbekannt)' 'SHA256: (path unknown)' 'SHA256: （路径未知）' 'SHA256: (путь неизвестен)'

function Resolve-Lang([string]$code) {
    if ([string]::IsNullOrWhiteSpace($code)) { return $null }
    $c = $code.Trim().ToLowerInvariant()
    if ($c.Length -ge 2) { $c = $c.Substring(0, 2) }
    if ($script:Langs -contains $c) { return $c }
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
    if ($a -and $a.Count -gt 0) { return [string]::Format($s, $a) }
    return $s
}

# ── Konfiguration (Sprache + Sync-Ordner) ──────────────────────────────────────
function Get-ConfigDir  { Join-Path $env:APPDATA 'rf4-backup' }
function Get-ConfigFile { Join-Path (Get-ConfigDir) 'settings.json' }
function Get-Config {
    $cfg = @{ lang = ''; syncPath = '' }
    $f = Get-ConfigFile
    if (Test-Path -LiteralPath $f) {
        try {
            $j = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            foreach ($k in @('lang', 'syncPath')) {
                $p = $j.PSObject.Properties[$k]
                if ($p -and $p.Value) { $cfg[$k] = [string]$p.Value }
            }
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
    $json = [pscustomobject]@{ lang = [string]$cfg.lang; syncPath = [string]$cfg.syncPath } | ConvertTo-Json
    [IO.File]::WriteAllText((Get-ConfigFile), $json, (New-Object Text.UTF8Encoding($true)))
}
function Get-SyncPath { [string](Get-Config).syncPath }
function Set-SyncPath([string]$p) { $c = Get-Config; $c.syncPath = $p; Save-Config $c }
function Save-Lang([string]$l)    { $c = Get-Config; $c.lang = $l;     Save-Config $c }

function Initialize-Lang([string]$Override) {
    $l = Resolve-Lang $Override
    if (-not $l) { $l = Resolve-Lang $env:RF4_LANG }
    if (-not $l) { $l = Resolve-Lang (Get-Config).lang }
    if (-not $l) { $l = Resolve-Lang (Get-Culture).TwoLetterISOLanguageName }
    if (-not $l) { $l = 'en' }
    [void](Set-Lang $l)
}

# ── Logging an die UI ──────────────────────────────────────────────────────────
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
    $p = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(rf4|RussianFishing)' })
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
            if (-not $yes) { Write-Log 'warn' 'f_skipped' @($name); return 'skipped' }
            Save-Undo $Dst $UndoRoot
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
            Write-Log 'ok' 'f_overwritten' @($name); return 'overwritten'
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
        Copy-Item -LiteralPath $Src -Destination $Dst
        Write-Log 'ok' 'f_copied' @($name); return 'copied'
    } catch {
        Write-Log 'err' 'f_failed' @($name, $_.Exception.Message); return 'failed'
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
#  Grafische Oberfläche (Windows Forms, nutzt core.ps1)
# ══════════════════════════════════════════════════════════════════════════════
# WinForms braucht einen STA-Thread (Windows PowerShell 5.1 ist es, PowerShell 7 standardmäßig nicht) -> neu starten
if ($env:RF4_GUI_NOSHOW -ne '1' -and $PSCommandPath -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process $exe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Lang', $Lang)
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }

Initialize-Lang $Lang

# GUI-eigene Texte
X 'overwrite_q'  '{0} existiert bereits.{1}Überschreiben?' '{0} already exists.{1}Overwrite?' '{0} 已存在。{1}是否覆盖？' '{0} уже существует.{1}Перезаписать?'
X 'sel_account'  'Account:' 'Account:' '账号:' 'Аккаунт:'
X 'scan_hint'    'Das Tool sucht automatisch auf allen Laufwerken nach RF4-Installationen.' 'The tool automatically searches all drives for RF4 installations.' '本工具会自动在所有驱动器上搜索 RF4 安装。' 'Программа автоматически ищет установки RF4 на всех дисках.'
X 'rescan'       'Neu suchen' 'Rescan' '重新扫描' 'Искать заново'
X 'target_none'  'Keine passende Ziel-Installation vorhanden.' 'No suitable target installation available.' '没有合适的目标安装。' 'Подходящая целевая установка отсутствует.'
X 'backup_to'    'Backup-Zielordner:' 'Backup target folder:' '备份目标文件夹:' 'Папка для копии:'
X 'preview'      'Inhalt des Backups:' 'Backup contents:' '备份内容:' 'Содержимое копии:'
X 'undo_hint'    'Ersetzte Dateien werden vorher nach _rf4tool_undo kopiert.' 'Files that get replaced are copied to _rf4tool_undo first.' '被替换的文件会先复制到 _rf4tool_undo。' 'Заменяемые файлы сначала копируются в _rf4tool_undo.'

# ── Schriften / Farben ─────────────────────────────────────────────────────────
$COL_BG     = [System.Drawing.Color]::FromArgb(15, 23, 42)
$COL_CARD   = [System.Drawing.Color]::FromArgb(30, 41, 59)
$COL_SEL    = [System.Drawing.Color]::FromArgb(15, 60, 90)
$COL_BORDER = [System.Drawing.Color]::FromArgb(51, 65, 85)
$COL_ACCENT = [System.Drawing.Color]::FromArgb(6, 182, 212)
$COL_GREEN  = [System.Drawing.Color]::FromArgb(34, 197, 94)
$COL_WARN   = [System.Drawing.Color]::FromArgb(251, 191, 36)
$COL_RED    = [System.Drawing.Color]::FromArgb(239, 68, 68)
$COL_TEXT   = [System.Drawing.Color]::FromArgb(241, 245, 249)
$COL_MUTED  = [System.Drawing.Color]::FromArgb(148, 163, 184)

function Update-Fonts {
    $fam = if ($script:Lang -eq 'zh') { 'Microsoft YaHei UI' } else { 'Segoe UI' }
    $script:FONT_MAIN  = New-Object System.Drawing.Font($fam, 9)
    $script:FONT_BOLD  = New-Object System.Drawing.Font($fam, 9, [System.Drawing.FontStyle]::Bold)
    $script:FONT_TITLE = New-Object System.Drawing.Font($fam, 13, [System.Drawing.FontStyle]::Bold)
    $script:FONT_SMALL = New-Object System.Drawing.Font($fam, 8)
    $script:FONT_MONO  = New-Object System.Drawing.Font($(if ($script:Lang -eq 'zh') { 'Microsoft YaHei UI' } else { 'Consolas' }), 8.5)
}
Update-Fonts

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$W = 140, [int]$H = 34, $BG = $COL_ACCENT, $FG = $COL_BG) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = New-Object System.Drawing.Point($X, $Y); $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.BackColor = $BG; $b.ForeColor = $FG; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.Font = $script:FONT_BOLD; $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}
function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W = 400, [int]$H = 22, $Font = $null, $FG = $COL_TEXT) {
    $l = New-Object System.Windows.Forms.Label
    if (-not $Font) { $Font = $script:FONT_MAIN }
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.Font = $Font; $l.ForeColor = $FG; $l.BackColor = [System.Drawing.Color]::Transparent
    $l.UseMnemonic = $false   # '&' in 'Backup & Migration' nicht verschlucken
    return $l
}
function New-List([int]$X, [int]$Y, [int]$W, [int]$H, $Font = $null) {
    $l = New-Object System.Windows.Forms.ListBox
    if (-not $Font) { $Font = $script:FONT_MAIN }
    $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.BackColor = $COL_CARD; $l.ForeColor = $COL_TEXT; $l.Font = $Font; $l.BorderStyle = 'None'
    return $l
}
function New-Text([int]$X, [int]$Y, [int]$W, [string]$Value) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y); $t.Size = New-Object System.Drawing.Size($W, 24)
    $t.BackColor = $COL_CARD; $t.ForeColor = $COL_TEXT; $t.BorderStyle = 'FixedSingle'; $t.Font = $script:FONT_MAIN; $t.Text = $Value
    return $t
}
function New-Check([string]$Text, [int]$X, [int]$Y, [int]$W, [bool]$Checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Location = New-Object System.Drawing.Point($X, $Y); $c.Size = New-Object System.Drawing.Size($W, 22)
    $c.ForeColor = $COL_TEXT; $c.BackColor = [System.Drawing.Color]::Transparent; $c.Font = $script:FONT_MAIN; $c.Checked = $Checked
    return $c
}
function Show-Msg([string]$Text, [string]$Kind = 'Warning', [string]$Buttons = 'OK') {
    return [System.Windows.Forms.MessageBox]::Show($Text, (T 'app_title'),
        [System.Windows.Forms.MessageBoxButtons]::$Buttons, [System.Windows.Forms.MessageBoxIcon]::$Kind)
}

# ── SHA256 der eigenen Datei ───────────────────────────────────────────────────
function Get-SelfHash {
    try {
        $path = $PSCommandPath
        if ($path -and (Test-Path -LiteralPath $path)) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    } catch { }
    return $null
}

# ── Zustand ────────────────────────────────────────────────────────────────────
$script:state = @{ Installs = $null; Action = ''; Render = $null; Step = 0; LastOpen = ''; Busy = $false }
$script:RunLog = New-Object System.Text.StringBuilder

$script:LogSink = {
    param($lvl, $msg)
    $prefix = switch ($lvl) { 'ok' { '[OK] ' } 'warn' { '[!]  ' } 'err' { '[X]  ' } default { '     ' } }
    [void]$script:RunLog.AppendLine("$prefix$msg")
    if ($script:txtLog) {
        $script:txtLog.AppendText("$prefix$msg`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ── Hauptfenster ───────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(820, 680)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $COL_BG; $form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false; $form.Font = $script:FONT_MAIN

$pHeader = New-Object System.Windows.Forms.Panel
$pHeader.Location = New-Object System.Drawing.Point(0, 0); $pHeader.Size = New-Object System.Drawing.Size(820, 76); $pHeader.BackColor = $COL_CARD
$form.Controls.Add($pHeader)
$lblTitle = New-Label '' 18 10 460 30 $script:FONT_TITLE $COL_ACCENT
$lblSub   = New-Label '' 18 46 480 20 $script:FONT_SMALL $COL_MUTED
$lblHash  = New-Label '' 470 42 330 30 $script:FONT_SMALL $COL_MUTED; $lblHash.TextAlign = 'MiddleRight'; $lblHash.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblLang  = New-Label '' 520 12 90 22 $script:FONT_MAIN $COL_MUTED; $lblLang.TextAlign = 'MiddleRight'
$cmbLang  = New-Object System.Windows.Forms.ComboBox
$cmbLang.DropDownStyle = 'DropDownList'; $cmbLang.Location = New-Object System.Drawing.Point(620, 10); $cmbLang.Size = New-Object System.Drawing.Size(180, 26)
$cmbLang.BackColor = $COL_BG; $cmbLang.ForeColor = $COL_TEXT; $cmbLang.FlatStyle = 'Flat'
foreach ($l in $script:Langs) { [void]$cmbLang.Items.Add($script:LangNames[$l]) }
$pHeader.Controls.AddRange(@($lblTitle, $lblSub, $lblHash, $lblLang, $cmbLang))

$pStepper = New-Object System.Windows.Forms.Panel
$pStepper.Location = New-Object System.Drawing.Point(0, 76); $pStepper.Size = New-Object System.Drawing.Size(820, 36); $pStepper.BackColor = $COL_BG
$form.Controls.Add($pStepper)
$script:stepLabels = @()
for ($i = 0; $i -lt 5; $i++) {
    $sl = New-Label '' (20 + $i * 156) 8 150 22 $script:FONT_SMALL $COL_MUTED; $sl.TextAlign = 'MiddleCenter'
    $pStepper.Controls.Add($sl); $script:stepLabels += $sl
}

$pContent = New-Object System.Windows.Forms.Panel
$pContent.Location = New-Object System.Drawing.Point(0, 112); $pContent.Size = New-Object System.Drawing.Size(820, 460); $pContent.BackColor = $COL_BG
$form.Controls.Add($pContent)

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Location = New-Object System.Drawing.Point(12, 576); $script:txtLog.Size = New-Object System.Drawing.Size(790, 66)
$script:txtLog.Multiline = $true; $script:txtLog.ReadOnly = $true; $script:txtLog.BackColor = $COL_CARD; $script:txtLog.ForeColor = $COL_MUTED
$script:txtLog.Font = $script:FONT_MONO; $script:txtLog.BorderStyle = 'None'; $script:txtLog.ScrollBars = 'Vertical'
$form.Controls.Add($script:txtLog)

$script:selfHash = Get-SelfHash

function Set-Step([int]$step) {
    $script:state.Step = $step
    for ($i = 0; $i -lt 5; $i++) {
        $sl = $script:stepLabels[$i]; $sl.Text = T ('step' + ($i + 1))
        if ($i -eq $step) { $sl.ForeColor = $COL_ACCENT; $sl.Font = $script:FONT_BOLD }
        elseif ($i -lt $step) { $sl.ForeColor = $COL_GREEN; $sl.Font = $script:FONT_SMALL }
        else { $sl.ForeColor = $COL_MUTED; $sl.Font = $script:FONT_SMALL }
    }
}

function Apply-Header {
    $form.Text = (T 'app_title') + ' v' + $script:ToolVersion
    $form.Font = $script:FONT_MAIN
    $lblTitle.Text = T 'app_title'; $lblTitle.Font = $script:FONT_TITLE
    $lblSub.Text = T 'donate'; $lblSub.Font = $script:FONT_SMALL
    $lblLang.Text = T 'language'; $lblLang.Font = $script:FONT_MAIN
    $cmbLang.Font = $script:FONT_MAIN
    if ($script:selfHash) { $lblHash.Text = (T 'hash_label' @($script:selfHash.Substring(0, 16))) + ' ' + (T 'hash_click') }
    else { $lblHash.Text = T 'hash_unknown' }
    $lblHash.Font = $script:FONT_SMALL
    $script:txtLog.Font = $script:FONT_MONO
    Set-Step $script:state.Step
}
$lblHash.Add_Click({
    if ($script:selfHash) {
        [System.Windows.Forms.Clipboard]::SetText($script:selfHash)
        [void](Show-Msg ((T 'hash_copied') + "`n" + $script:selfHash) 'Information')
    }
})

function Show-Panel([scriptblock]$render) {
    $script:state.Render = $render
    $pContent.SuspendLayout()
    while ($pContent.Controls.Count -gt 0) { $c = $pContent.Controls[0]; $pContent.Controls.RemoveAt(0); $c.Dispose() }
    & $render
    $pContent.ResumeLayout()
}

function Set-Language([string]$code) {
    [void](Set-Lang $code)
    try { Save-Lang $script:Lang } catch { }
    Update-Fonts
    $script:suppressLang = $true; $cmbLang.SelectedIndex = [Array]::IndexOf($script:Langs, $script:Lang); $script:suppressLang = $false
    Apply-Header
    if ($script:state.Render) { Show-Panel $script:state.Render }
}
$cmbLang.Add_SelectedIndexChanged({
    if ($script:suppressLang) { return }
    $ix = $cmbLang.SelectedIndex
    if ($ix -ge 0 -and $script:Langs[$ix] -ne $script:Lang) { Set-Language $script:Langs[$ix] }
})

function Get-ExistingInstalls { @($script:state.Installs | Where-Object { $_.Exists }) }

function Confirm-GameClosedGui {
    $run = Test-Rf4Running
    if (-not $run) { return $true }
    return ((Show-Msg ((T 'running_warn' @($run)) + "`n`n" + (T 'running_ask')) 'Warning' 'YesNo') -eq 'Yes')
}
$script:ConfirmOverwrite = { param($name) ((Show-Msg (T 'overwrite_q' @($name, "`n")) 'Warning' 'YesNo') -eq 'Yes') }

function Add-BackBtn([scriptblock]$target) {
    $b = New-Button (T 'back') 18 400 120 34 $COL_BORDER $COL_TEXT
    $script:backTarget = $target
    $b.Add_Click({ Show-Panel $script:backTarget })
    $pContent.Controls.Add($b)
}

# ── Panel 1: Scan ──────────────────────────────────────────────────────────────
function Render-Scan {
    Set-Step 0
    $pContent.Controls.Add((New-Label (T 'hdr_scan') 18 12 600 24 $script:FONT_BOLD $COL_TEXT))
    $pContent.Controls.Add((New-Label (T 'scan_hint') 18 38 780 20 $script:FONT_SMALL $COL_MUTED))
    $lst = New-List 18 64 780 270 $script:FONT_MONO; $lst.SelectionMode = 'None'
    $pContent.Controls.Add($lst)
    $lblP = New-Label (T 'scanning') 18 342 600 20 $script:FONT_SMALL $COL_ACCENT
    $pContent.Controls.Add($lblP)
    $pContent.Controls.Add((New-Label (T 'scan_readonly') 18 366 780 20 $script:FONT_SMALL $COL_GREEN))
    $script:btnScanNext = New-Button (T 'next') 658 400 140 34
    $script:btnScanNext.Enabled = $false
    $script:btnScanNext.Add_Click({ Show-Panel { Render-Action } })
    $pContent.Controls.Add($script:btnScanNext)
    $btnRe = New-Button (T 'rescan') 18 400 150 34 $COL_BORDER $COL_TEXT
    $btnRe.Add_Click({ $script:state.Installs = $null; Show-Panel { Render-Scan } })
    $pContent.Controls.Add($btnRe)
    $form.Update()

    if ($null -eq $script:state.Installs) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $script:state.Installs = @(Find-Installations)
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    $found = 0
    foreach ($i in $script:state.Installs) {
        if ($i.Exists) {
            $info = Get-InstInfo $i.Path
            [void]$lst.Items.Add('[OK]  ' + (Get-InstLabel $i))
            [void]$lst.Items.Add('      ' + (T 'scan_stats' @($info.Mailboxes.Count, $info.Convs)) + $(if ($info.Ids) { '  |  ' + (T 'scan_accounts' @($info.Ids)) } else { '' }))
            [void]$lst.Items.Add('')
            $found++
        } else {
            [void]$lst.Items.Add('[--]  ' + (Get-InstLabel $i) + '  ' + (T 'scan_empty'))
        }
    }
    $lblP.Text = if ($found -gt 0) { T 'found_n' @($found) } else { T 'none_found' }
    $lblP.ForeColor = if ($found -gt 0) { $COL_GREEN } else { $COL_WARN }
    $script:btnScanNext.Enabled = ($found -gt 0)
}

# ── Panel 2: Aktion ────────────────────────────────────────────────────────────
function Render-Action {
    Set-Step 1
    $pContent.Controls.Add((New-Label (T 'what_todo') 18 12 600 24 $script:FONT_BOLD $COL_TEXT))
    $acts = @(@('backup', 'act_backup', 'act_backup_d'), @('restore', 'act_restore', 'act_restore_d'), @('merge', 'act_merge', 'act_merge_d'), @('sync', 'act_sync', 'act_sync_d'))
    $script:cards = @{}
    $y = 46
    foreach ($a in $acts) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(18, $y); $card.Size = New-Object System.Drawing.Size(780, 76)
        $card.BackColor = $(if ($script:state.Action -eq $a[0]) { $COL_SEL } else { $COL_CARD }); $card.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Tag = $a[0]
        $t1 = New-Label (T $a[1]) 14 8 740 22 $script:FONT_BOLD $COL_TEXT; $t1.Tag = $a[0]
        $t2 = New-Label (T $a[2]) 14 32 750 44 $script:FONT_SMALL $COL_MUTED; $t2.Tag = $a[0]
        $card.Controls.AddRange(@($t1, $t2))
        $handler = {
            param($s, $e)
            $script:state.Action = [string]$s.Tag
            foreach ($k in $script:cards.Keys) { $script:cards[$k].BackColor = $(if ($k -eq $script:state.Action) { $COL_SEL } else { $COL_CARD }) }
        }
        $card.Add_Click($handler); $t1.Add_Click($handler); $t2.Add_Click($handler)
        $pContent.Controls.Add($card); $script:cards[$a[0]] = $card
        $y += 84
    }
    Add-BackBtn { Render-Scan }
    $n = New-Button (T 'next') 658 400 140 34
    $n.Add_Click({
        switch ($script:state.Action) {
            'backup'  { Show-Panel { Render-Backup } }
            'restore' { Show-Panel { Render-Restore } }
            'merge'   { Show-Panel { Render-Merge } }
            'sync'    { Show-Panel { Render-Sync } }
            default   { [void](Show-Msg (T 'pick_action')) }
        }
    })
    $pContent.Controls.Add($n)
}

function Add-AccountCombo($boxes, [int]$x, [int]$y) {
    $script:cmbAcct = $null
    $boxes = @($boxes)
    if ($boxes.Count -le 1) { return }
    $pContent.Controls.Add((New-Label (T 'sel_account') $x $y 80 22 $script:FONT_MAIN $COL_MUTED))
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.Location = New-Object System.Drawing.Point(($x + 84), ($y - 2)); $c.Size = New-Object System.Drawing.Size(380, 24)
    $c.BackColor = $COL_CARD; $c.ForeColor = $COL_TEXT; $c.FlatStyle = 'Flat'; $c.Font = $script:FONT_MAIN
    [void]$c.Items.Add((T 'all_accts' @($boxes.Count)))
    foreach ($b in $boxes) { [void]$c.Items.Add((T 'acct_line' @($b.Id, $b.Convs))) }
    $c.SelectedIndex = 0
    $pContent.Controls.Add($c); $script:cmbAcct = $c
    $script:acctBoxes = $boxes
}
function Get-SelectedAccounts {
    if ($script:cmbAcct -and $script:cmbAcct.SelectedIndex -gt 0) { return @($script:acctBoxes[$script:cmbAcct.SelectedIndex - 1].Name) }
    return $null
}

# ── Panel 3a: Backup ───────────────────────────────────────────────────────────
function Render-Backup {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'pick_source') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $script:exSrc = Get-ExistingInstalls
    $lst = New-List 18 34 780 112; foreach ($i in $script:exSrc) { [void]$lst.Items.Add((Get-InstLabel $i)) }
    if ($lst.Items.Count -gt 0) { $lst.SelectedIndex = 0 }
    $pContent.Controls.Add($lst); $script:lstSrc = $lst
    $pContent.Controls.Add((New-Label (T 'what_backup') 18 156 780 22 $script:FONT_BOLD $COL_TEXT))
    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $script:bkKeys = $keys; $script:bkChecks = @()
    $y = 180
    foreach ($k in $keys) {
        $c = New-Check (T ('item_' + $k)) 18 $y 600 ($k -in @('mail', 'Settings.dat', 'Preferences.dat'))
        $pContent.Controls.Add($c); $script:bkChecks += $c; $y += 24
    }
    $script:acctY = $y + 2
    $lst.Add_SelectedIndexChanged({
        if ($script:cmbAcct) { $pContent.Controls.Remove($script:cmbAcct); $script:cmbAcct = $null }
        # Account-Auswahl neu aufbauen
        foreach ($ctl in @($pContent.Controls | Where-Object { $_.Tag -eq 'acctlbl' })) { $pContent.Controls.Remove($ctl) }
        if ($script:lstSrc.SelectedIndex -ge 0) {
            Add-AccountCombo (Get-Mailboxes $script:exSrc[$script:lstSrc.SelectedIndex].Path) 18 $script:acctY
            foreach ($ctl in @($pContent.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq (T 'sel_account') })) { $ctl.Tag = 'acctlbl' }
        }
    })
    if ($lst.SelectedIndex -ge 0) {
        Add-AccountCombo (Get-Mailboxes $script:exSrc[$lst.SelectedIndex].Path) 18 $script:acctY
        foreach ($ctl in @($pContent.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq (T 'sel_account') })) { $ctl.Tag = 'acctlbl' }
    }
    $pContent.Controls.Add((New-Label (T 'backup_to') 18 ($y + 34) 170 22 $script:FONT_MAIN $COL_MUTED))
    $script:txtDir = New-Text 190 ($y + 32) 480 (Get-DefaultBackupDir); $pContent.Controls.Add($script:txtDir)
    $bb = New-Button (T 'btn_browse') 680 ($y + 30) 118 28 $COL_BORDER $COL_TEXT
    $bb.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.SelectedPath = $script:txtDir.Text; if ($fb.ShowDialog() -eq 'OK') { $script:txtDir.Text = $fb.SelectedPath } })
    $pContent.Controls.Add($bb)
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'run_backup') 598 400 200 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        if ($script:lstSrc.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        $items = @(); for ($i = 0; $i -lt $script:bkKeys.Count; $i++) { if ($script:bkChecks[$i].Checked) { $items += $script:bkKeys[$i] } }
        if ($items.Count -eq 0) { [void](Show-Msg (T 'pick_item')); return }
        $src = $script:exSrc[$script:lstSrc.SelectedIndex]
        $dest = $script:txtDir.Text.Trim(); if (-not $dest) { $dest = Get-DefaultBackupDir }
        $acc = Get-SelectedAccounts
        Start-Operation 'hdr_backup' $dest {
            Copy-Rf4Data -SrcDir $src.Path -DstDir $dest -Items $items -Accounts $acc `
                -ShotsSrc (Get-ScreenshotDir $src.Path) -ShotsDst (Join-Path $dest 'Screenshots') -Confirm $script:ConfirmOverwrite
            Write-Log 'ok' 'backup_done' @($dest)
        }
    })
    $pContent.Controls.Add($go)
}

# ── Panel 3b: Restore ──────────────────────────────────────────────────────────
function Update-RestorePreview {
    $script:lstPrev.Items.Clear()
    $dir = $script:txtDir.Text
    if (-not (Test-Path -LiteralPath $dir)) { [void]$script:lstPrev.Items.Add((T 'folder_missing' @($dir))); $script:rsBC = $null; return }
    $bc = Get-BackupContents $dir; $script:rsBC = $bc
    foreach ($m in $bc.Mailboxes) { [void]$script:lstPrev.Items.Add('[OK] ' + (T 'bk_mailbox' @($m.Name, $m.Convs))) }
    foreach ($f in $bc.Files) { [void]$script:lstPrev.Items.Add("[OK] $f") }
    if ($bc.Shots -gt 0) { [void]$script:lstPrev.Items.Add('[OK] ' + (T 'bk_shots' @($bc.Shots))) }
    if ($bc.Empty) { [void]$script:lstPrev.Items.Add('[!]  ' + (T 'no_backup_here')) }
}
function Render-Restore {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'pick_backup') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $pContent.Controls.Add((New-Label (T 'pick_backup_d') 18 32 780 18 $script:FONT_SMALL $COL_MUTED))
    $script:txtDir = New-Text 18 56 650 (Get-DefaultBackupDir); $pContent.Controls.Add($script:txtDir)
    $bb = New-Button (T 'btn_browse') 680 54 118 28 $COL_BORDER $COL_TEXT
    $bb.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.SelectedPath = $script:txtDir.Text; if ($fb.ShowDialog() -eq 'OK') { $script:txtDir.Text = $fb.SelectedPath } })
    $pContent.Controls.Add($bb)
    $pContent.Controls.Add((New-Label (T 'preview') 18 90 500 18 $script:FONT_SMALL $COL_MUTED))
    $script:lstPrev = New-List 18 110 780 110 $script:FONT_MONO; $script:lstPrev.SelectionMode = 'None'; $pContent.Controls.Add($script:lstPrev)
    $pContent.Controls.Add((New-Label (T 'pick_target') 18 228 780 22 $script:FONT_BOLD $COL_TEXT))
    $script:rsIns = @($script:state.Installs)
    $script:lstDst = New-List 18 252 780 100
    foreach ($i in $script:rsIns) { [void]$script:lstDst.Items.Add((Get-InstLabel $i) + $(if (-not $i.Exists) { '  ' + (T 'scan_empty') } else { '' })) }
    $pContent.Controls.Add($script:lstDst)
    $pContent.Controls.Add((New-Label (T 'undo_hint') 18 360 780 18 $script:FONT_SMALL $COL_MUTED))
    $script:txtDir.Add_TextChanged({ Update-RestorePreview })
    Update-RestorePreview
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'run_restore') 598 400 200 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        if (-not $script:rsBC -or $script:rsBC.Empty) { [void](Show-Msg (T 'no_backup_here')); return }
        if ($script:lstDst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dst = $script:rsIns[$script:lstDst.SelectedIndex].Path; $src = $script:txtDir.Text; $bc = $script:rsBC
        $items = @(); if ($bc.Mailboxes.Count -gt 0) { $items += 'mail' }; $items += @($bc.Files); if ($bc.Shots -gt 0) { $items += 'shots' }
        Start-Operation 'hdr_restore' $dst {
            Write-Log 'info' 'importing_to' @($dst)
            Copy-Rf4Data -SrcDir $src -DstDir $dst -Items $items -ShotsSrc (Join-Path $src 'Screenshots') -ShotsDst (Get-ScreenshotDir $dst -Create) `
                -Confirm $script:ConfirmOverwrite -UndoRoot (New-UndoRoot $dst)
            Write-Log 'ok' 'restore_done'
        }
    })
    $pContent.Controls.Add($go)
}

# ── Panel 3c: Merge ────────────────────────────────────────────────────────────
function Render-Merge {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'hdr_merge') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $ex = Get-ExistingInstalls; $script:mgEx = $ex
    if ($ex.Count -lt 2) {
        $pContent.Controls.Add((New-Label (T 'merge_need2') 18 40 780 22 $script:FONT_MAIN $COL_WARN))
        Add-BackBtn { Render-Action }; return
    }
    $pContent.Controls.Add((New-Label (T 'merge_note') 18 32 780 32 $script:FONT_SMALL $COL_WARN))
    $pContent.Controls.Add((New-Label (T 'merge_safe') 18 66 780 18 $script:FONT_SMALL $COL_GREEN))
    $pContent.Controls.Add((New-Label (T 'merge_dst') 18 92 780 20 $script:FONT_BOLD $COL_TEXT))
    $script:lstMgDst = New-List 18 114 780 84; foreach ($i in $ex) { [void]$script:lstMgDst.Items.Add((Get-InstLabel $i)) }
    $pContent.Controls.Add($script:lstMgDst)
    $pContent.Controls.Add((New-Label (T 'merge_src_ctrl') 18 206 780 20 $script:FONT_BOLD $COL_TEXT))
    $script:lstMgSrc = New-List 18 228 780 120; $script:lstMgSrc.SelectionMode = 'MultiExtended'
    foreach ($i in $ex) { [void]$script:lstMgSrc.Items.Add((Get-InstLabel $i)) }
    $pContent.Controls.Add($script:lstMgSrc)
    $pContent.Controls.Add((New-Label (T 'undo_hint') 18 356 780 18 $script:FONT_SMALL $COL_MUTED))
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'run_merge') 598 400 200 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        $d = $script:lstMgDst.SelectedIndex; $s = @($script:lstMgSrc.SelectedIndices)
        if ($d -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        if ($s.Count -eq 0) { [void](Show-Msg (T 'pick_one_src')); return }
        if ($s -contains $d) { [void](Show-Msg (T 'merge_same')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dstPath = $script:mgEx[$d].Path; $srcs = @($s | ForEach-Object { $script:mgEx[$_] }); $undo = New-UndoRoot $dstPath
        Start-Operation 'hdr_merge' $dstPath {
            foreach ($si in $srcs) {
                Write-Log 'info' 'merge_src_hdr' @((Get-InstLabel $si))
                Copy-Rf4Data -SrcDir $si.Path -DstDir $dstPath -Items @('mail') -UndoRoot $undo
            }
            Write-Log 'ok' 'merge_done'
        }
    })
    $pContent.Controls.Add($go)
}

# ── Panel 3d: Sync ─────────────────────────────────────────────────────────────
function Render-Sync {
    Set-Step 2
    $pContent.Controls.Add((New-Label (T 'hdr_sync') 18 8 780 22 $script:FONT_BOLD $COL_TEXT))
    $pContent.Controls.Add((New-Label (T 'sync_intro') 18 32 780 18 $script:FONT_SMALL $COL_MUTED))
    $pContent.Controls.Add((New-Label (T 'sync_dir_lbl') 18 66 150 22 $script:FONT_MAIN $COL_MUTED))
    $script:txtSync = New-Text 170 64 500 (Get-SyncPath); $pContent.Controls.Add($script:txtSync)
    $bb = New-Button (T 'btn_browse') 680 62 118 28 $COL_BORDER $COL_TEXT
    $bb.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.Description = T 'sync_pick_dir'
        if ($script:txtSync.Text -and (Test-Path -LiteralPath $script:txtSync.Text)) { $fb.SelectedPath = $script:txtSync.Text }
        if ($fb.ShowDialog() -eq 'OK') { $script:txtSync.Text = $fb.SelectedPath; Set-SyncPath $fb.SelectedPath }
    })
    $pContent.Controls.Add($bb)
    $pContent.Controls.Add((New-Label (T 'sync_hint') 170 92 628 18 $script:FONT_SMALL $COL_MUTED))
    $pContent.Controls.Add((New-Label (T 'sync_inst_lbl') 18 124 150 22 $script:FONT_MAIN $COL_MUTED))
    $script:syEx = Get-ExistingInstalls
    $script:lstSyInst = New-List 170 122 628 90; foreach ($i in $script:syEx) { [void]$script:lstSyInst.Items.Add((Get-InstLabel $i)) }
    if ($script:lstSyInst.Items.Count -gt 0) { $script:lstSyInst.SelectedIndex = 0 }
    $pContent.Controls.Add($script:lstSyInst)
    $script:lblSyState = New-Label '' 18 222 780 20 $script:FONT_SMALL $COL_MUTED; $pContent.Controls.Add($script:lblSyState)
    $script:lstSySt = New-List 18 246 780 140 $script:FONT_MONO; $script:lstSySt.SelectionMode = 'None'; $pContent.Controls.Add($script:lstSySt)
    $btnSt = New-Button (T 'sync_status') 146 400 250 34 $COL_BORDER $COL_TEXT
    $btnSt.Add_Click({
        $script:lstSySt.Items.Clear(); $sp = $script:txtSync.Text.Trim()
        if (-not $sp) { $script:lblSyState.Text = T 'sync_none'; return }
        if (-not (Test-Path -LiteralPath $sp)) { $script:lblSyState.Text = T 'sync_unreach' @($sp); return }
        Set-SyncPath $sp; $script:lblSyState.Text = T 'sync_ok' @($sp)
        $st = Get-SyncStatus $sp
        if (-not $st.Exists) { [void]$script:lstSySt.Items.Add((T 'sync_st_nodir')); return }
        if ($st.Mailboxes.Count -eq 0) { [void]$script:lstSySt.Items.Add((T 'sync_st_none')) }
        foreach ($m in $st.Mailboxes) { [void]$script:lstSySt.Items.Add((T 'sync_st_boxes' @($m.Name, $m.Convs))) }
        foreach ($f in $st.Files) { [void]$script:lstSySt.Items.Add("$($f.Name): $($f.Time)") }
        foreach ($l in $st.Log) { [void]$script:lstSySt.Items.Add($l) }
    })
    $pContent.Controls.Add($btnSt)
    Add-BackBtn { Render-Action }
    $go = New-Button (T 'sync_run') 528 400 270 34 $COL_GREEN $COL_BG
    $go.Add_Click({
        $sp = $script:txtSync.Text.Trim()
        if (-not $sp) { [void](Show-Msg (T 'sync_first')); return }
        if (-not (Test-Path -LiteralPath $sp)) { [void](Show-Msg ((T 'sync_unreach' @($sp)) + "`n" + (T 'sync_unreach_h'))); return }
        if ($script:lstSyInst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        Set-SyncPath $sp; $inst = $script:syEx[$script:lstSyInst.SelectedIndex]
        Start-Operation 'hdr_sync' $inst.Path { Invoke-SyncRun -InstPath $inst.Path -SyncBase $sp }
    })
    $pContent.Controls.Add($go)
}

# ── Ausführen + Ergebnis ───────────────────────────────────────────────────────
function Start-Operation([string]$titleKey, [string]$openPath, [scriptblock]$work) {
    if ($script:state.Busy) { return }
    $script:state.Busy = $true
    $script:state.LastOpen = $openPath
    $script:RunLog.Clear() | Out-Null; $script:txtLog.Clear()
    Set-Step 3
    Show-Panel { Set-Step 3; $pContent.Controls.Add((New-Label (T 'working') 18 12 780 24 $script:FONT_BOLD $COL_ACCENT)) }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    try { & $work } catch { Write-Log 'err' 'f_failed' @($titleKey, $_.Exception.Message) }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $script:state.Busy = $false
    $script:state.ResultKey = $titleKey
    Show-Panel { Render-Result }
}
function Render-Result {
    Set-Step 4
    $pContent.Controls.Add((New-Label ((T $script:state.ResultKey) + ' – ' + (T 'result_title')) 18 8 780 24 $script:FONT_BOLD $COL_GREEN))
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(18, 40); $tb.Size = New-Object System.Drawing.Size(780, 340)
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.BackColor = $COL_CARD; $tb.ForeColor = $COL_TEXT
    $tb.Font = $script:FONT_MONO; $tb.BorderStyle = 'None'; $tb.Text = $script:RunLog.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")
    $pContent.Controls.Add($tb)
    $bo = New-Button (T 'btn_open') 18 400 170 34 $COL_BORDER $COL_TEXT
    $bo.Add_Click({ if ($script:state.LastOpen -and (Test-Path -LiteralPath $script:state.LastOpen)) { Start-Process explorer.exe -ArgumentList ('"' + $script:state.LastOpen + '"') } })
    $pContent.Controls.Add($bo)
    $bh = New-Button (T 'btn_home') 598 400 200 34
    $bh.Add_Click({ $script:state.Installs = $null; Show-Panel { Render-Scan } })
    $pContent.Controls.Add($bh)
}

# ── Start ──────────────────────────────────────────────────────────────────────
$script:suppressLang = $true
$cmbLang.SelectedIndex = [Array]::IndexOf($script:Langs, $script:Lang)
$script:suppressLang = $false
Apply-Header
if ($env:RF4_GUI_NOSHOW -ne '1') {
    $form.Add_Shown({ Show-Panel { Render-Scan } })
    [void]$form.ShowDialog()
}
