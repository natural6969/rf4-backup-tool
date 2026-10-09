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
