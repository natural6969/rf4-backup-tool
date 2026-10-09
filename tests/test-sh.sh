#!/usr/bin/env bash
# Tests für rf4sa-backup.sh – laufen komplett in einem Temp-Verzeichnis mit eigenem $HOME.
# Aufruf: bash tests/test-sh.sh        (benötigt bash >= 4 und python3)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../rf4sa-backup.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export XDG_CONFIG_HOME="$HOME/.config"
export PYTHONIOENCODING=utf-8
unset RF4_LANG LC_ALL; export LANG=C
PASS=0; FAIL=0
tpass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
tfail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m  %s  %s\n' "$1" "${2:-}"; }
check() { if eval "$2"; then tpass "$1"; else tfail "$1" "${3:-}"; fi; }

RF4_NO_MAIN=1 source "$SCRIPT"
init_lang ""

msg()  { printf '{"meta":{"id":"%s","created":%s,"sender":1,"type":0,"text":"%s","items":[]},"status":1281}' "$1" "$2" "${3:-x}"; }
mkdat() {   # mkdat file conv msgs…
    local f="$1"; shift; local conv="$1"; shift; local body="" m
    for m in "$@"; do body+="${body:+,}$m"; done
    mkdir -p "$(dirname "$f")"; printf '\xEF\xBB\xBF{"id":%s,"items":[%s]}' "$conv" "$body" > "$f"
}
ids() { "$PYTHON" -c "import json,sys;print(','.join(str(i['meta']['id']) for i in json.load(open(sys.argv[1],encoding='utf-8-sig'))['items']))" "$1" | tr -d '\r'; }
find_python || { echo "python3 fehlt"; exit 2; }

echo; echo "[1] Sprachen / Übersetzungen"
check "resolve_lang zh-CN"  '[[ "$(resolve_lang zh-CN)" == zh ]]'
check "resolve_lang DE_de"  '[[ "$(resolve_lang DE_de.UTF-8)" == de ]]'
check "resolve_lang unbekannt leer" '[[ -z "$(resolve_lang xx)" ]]'
check "resolve_lang leer"   '[[ -z "$(resolve_lang "")" ]]'
for l in de en zh ru; do
    LANG_CODE=$l
    s=$(t mb_merge_file "a.dat" 5)
    check "t() mit Argumenten ($l)" '[[ "$s" == *a.dat* && "$s" == *5* && "$s" != *"{0}"* ]]' "$s"
    s=$(t sync_up 'A&B')
    check "t() '&' im Argument unverändert ($l)" '[[ "$s" == *"A&B"* ]]' "$s"
done
keys=$(for k in "${!TX[@]}"; do [[ $k == en:* ]] && echo "${k#en:}"; done)
miss=0; for l in de en zh ru; do for k in $keys; do [[ -n "${TX[$l:$k]:-}" ]] || { miss=$((miss + 1)); echo "    fehlt: $l:$k"; }; done; done
check "Alle $(echo "$keys" | wc -l) Schlüssel in 4 Sprachen vorhanden" '(( miss == 0 ))'
LANG_CODE=zh; check "zh enthält chinesische Zeichen" '[[ "$(t menu_backup)" =~ [一-龥] ]]'
LANG_CODE=ru; check "ru enthält kyrillische Zeichen" '[[ "$(t menu_backup)" =~ [А-Яа-я] ]]'
LANG_CODE=de
RF4_LANG=ru init_lang ""; check "RF4_LANG wird gelesen" '[[ $LANG_CODE == ru ]]'
cfg_set lang zh; RF4_LANG="" init_lang ""; check "Config-Sprache wird gelesen" '[[ $LANG_CODE == zh ]]'
RF4_LANG=en init_lang ""; check "RF4_LANG schlägt Config" '[[ $LANG_CODE == en ]]'
RF4_LANG=en init_lang de; check "Parameter schlägt Env" '[[ $LANG_CODE == de ]]'
unset RF4_LANG
sync_set "/tmp/Sync Ordner/ü ß 中"; check "Sync-Pfad mit Sonderzeichen roundtrip" '[[ "$(sync_get)" == "/tmp/Sync Ordner/ü ß 中" ]]'
check "Sprache bleibt nach sync_set" '[[ "$(cfg_get lang)" == zh ]]'
rm -f "$CONFIG_FILE"; printf '/alt/pfad\n' > "$CONFIG_DIR/sync.conf"; check "Altes sync.conf wird gelesen" '[[ "$(sync_get)" == /alt/pfad ]]'
rm -f "$CONFIG_DIR/sync.conf"; init_lang de

echo; echo "[2] Installationen finden"
W="$HOME/.wine/drive_c/users/tester/AppData/Roaming/RussianFishingLLC"
STEAM="$W/RussianFishing4Steam"; DE="$W/RussianFishing4DE"
mkdat "$STEAM/Mailbox_309850/100.dat" 100 "$(msg a 1)" "$(msg b 2)" "$(msg c 3)"
mkdat "$STEAM/Mailbox_309850/200.dat" 200 "$(msg z 9)"
mkdir -p "$STEAM/Mailbox_555"
echo steam-settings > "$STEAM/Settings.dat"; echo steam-prefs > "$STEAM/Preferences.dat"
mkdat "$DE/Mailbox_309850/100.dat" 100 "$(msg a 1)" "$(msg d 4)"; echo de-settings > "$DE/Settings.dat"
mkdir -p "$W/RussianFishing4Foo"
mkdir -p "$TMP/usb/Users/alt/AppData/Roaming/RussianFishingLLC/RussianFishing4DE"
mkdat "$TMP/usb/Users/alt/AppData/Roaming/RussianFishingLLC/RussianFishing4DE/Mailbox_1/1.dat" 1 "$(msg u 1)"
PROTON="$HOME/.local/share/Steam/steamapps/compatdata/309850/pfx/drive_c/users/steamuser/AppData/Roaming/RussianFishingLLC/RussianFishing4Steam"
mkdat "$PROTON/Mailbox_777/1.dat" 1 "$(msg q 1)"
RF4_SCAN_USERS="$TMP/usb/Users" find_installations
check "Installationen gefunden (>= 5)" '(( ${#INST_PATH[@]} >= 5 ))' "${#INST_PATH[@]}"
n_exist=0; for e in "${INST_EXISTS[@]}"; do (( e )) && n_exist=$((n_exist + 1)); done
check "Existierende: Steam, DE, Foo, Proton, USB = 5" '(( n_exist == 5 ))' "$n_exist"
types=" ${INST_WTYPE[*]} "; check "Wine, Proton, extra erkannt" '[[ "$types" == *" wine "* && "$types" == *" proton "* && "$types" == *" extra "* ]]' "$types"
check "Bekannte, noch fehlende Varianten (EN, DE_new) im Wine-Prefix als Ziel angeboten" '[[ " ${INST_FOLDER[*]} " == *RussianFishing4EN* ]]'
for l in de en zh ru; do LANG_CODE=$l; lab=$(inst_label 0); check "Label ($l): $lab" '[[ ${#lab} -gt 5 && "$lab" != *"{0}"* ]]'; done; LANG_CODE=de
load_mailboxes "$STEAM"; check "load_mailboxes: 2 Mailboxen" '(( ${#MB_NAME[@]} == 2 ))'
check "Konversationen gezählt (2 / 0)" '[[ "${MB_CONVS[0]}" == 0 || "${MB_CONVS[1]}" == 0 ]] && [[ "${MB_CONVS[0]}${MB_CONVS[1]}" == 20 || "${MB_CONVS[0]}${MB_CONVS[1]}" == 02 ]]' "${MB_CONVS[*]}"
load_mailboxes "$W/RussianFishing4Foo"; check "Leere Installation crasht nicht" '(( ${#MB_NAME[@]} == 0 ))'
load_mailboxes "$TMP/gibtsnicht"; check "Nicht vorhandener Pfad crasht nicht" '(( ${#MB_NAME[@]} == 0 ))'

echo; echo "[3] Merge"
DST="$TMP/merge/Mailbox_309850"; UND="$TMP/undo1"
mkdat "$DST/100.dat" 100 "$(msg a 1)" "$(msg d 4)"
out=$(merge_mailbox "$STEAM/Mailbox_309850" "$DST" "$UND")
check "Merge: 1 gemergt, 1 neu kopiert" '[[ "$out" == *"1 "*"1 "* ]]' "$out"
check "Reihenfolge nach created, keine Duplikate" '[[ "$(ids "$DST/100.dat")" == a,b,c,d ]]' "$(ids "$DST/100.dat")"
check "Undo-Kopie angelegt" '[[ -f "$UND/Mailbox_309850/100.dat" ]]'
check "UTF-8 BOM bleibt erhalten" '[[ "$(head -c3 "$DST/100.dat" | od -An -tx1 | tr -d " ")" == efbbbf ]]'
h1=$(md5sum "$DST/100.dat" | cut -d' ' -f1); out=$(merge_mailbox "$STEAM/Mailbox_309850" "$DST" "")
check "Zweiter Lauf idempotent (Datei unverändert)" '[[ "$h1" == "$(md5sum "$DST/100.dat" | cut -d" " -f1)" ]]'
check "Zweiter Lauf: 0 gemergt" '[[ "$out" == *" 0 gemergt"* || "$out" == *" 0 merged"* || "$out" == *"0"* ]]' "$out"
# kaputte Datei
mkdat "$TMP/bad/src/1.dat" 1 "$(msg k 1)"; mkdat "$TMP/bad/src/2.dat" 2 "$(msg m 2)"
mkdat "$TMP/bad/dst/1.dat" 1 "$(msg x 1)"; echo '{kaputt' > "$TMP/bad/dst/2.dat"
out=$(merge_mailbox "$TMP/bad/src" "$TMP/bad/dst" "")
check "Kaputte JSON: Warnung, andere Datei läuft weiter" '[[ "$(ids "$TMP/bad/dst/1.dat")" == x,k && "$(cat "$TMP/bad/dst/2.dat")" == "{kaputt" ]]' "$out"
check "Keine .rf4tmp-Reste" '[[ -z "$(ls "$TMP/bad/dst" | grep rf4tmp)" ]]'
# Ziel leer / ohne items
mkdat "$TMP/e1/1.dat" 1; mkdat "$TMP/es/1.dat" 1 "$(msg n1 5)" "$(msg n2 6)"
merge_mailbox "$TMP/es" "$TMP/e1" "" >/dev/null; check "Leeres Ziel (items=[]) wird gefüllt" '[[ "$(ids "$TMP/e1/1.dat")" == n1,n2 ]]'
mkdir -p "$TMP/e2"; printf '\xEF\xBB\xBF{"id":1}' > "$TMP/e2/1.dat"
merge_mailbox "$TMP/es" "$TMP/e2" "" >/dev/null; check "Ziel ohne items-Eigenschaft" '[[ "$(ids "$TMP/e2/1.dat")" == n1,n2 ]]'
# Unicode + große Zahlen
mkdat "$TMP/u1/1.dat" 1 "$(msg u1 1 'Привет 你好 ä ö ü ß')"; mkdat "$TMP/u2/1.dat" 1 "$(msg u2 2 ok)"
merge_mailbox "$TMP/u1" "$TMP/u2" "" >/dev/null
check "Unicode überlebt Merge" 'grep -q "Привет 你好 ä ö ü ß" "$TMP/u2/1.dat"'
mkdat "$TMP/b1/1.dat" 1 "$(msg g1 133292355165425967)"; mkdat "$TMP/b2/1.dat" 1 "$(msg g2 133292355165425000)"
merge_mailbox "$TMP/b1" "$TMP/b2" "" >/dev/null
check "FILETIME-Zahlen (18 Stellen) verlustfrei + sortiert" '[[ "$(ids "$TMP/b2/1.dat")" == g2,g1 ]] && grep -q 133292355165425967 "$TMP/b2/1.dat"'

echo; echo "[4] Backup / Restore (copy_rf4data)"
SH="$HOME/.wine/drive_c/users/tester/Documents/Russian Fishing 4/Screenshots"; mkdir -p "$SH/sub"
for i in 1 2 3; do echo p$i > "$SH/s$i.png"; done; echo j > "$SH/sub/deep.jpg"; echo x > "$SH/note.txt"
check "Screenshot-Ordner gefunden" '[[ "$(screenshot_dir "$STEAM")" == "$SH" ]]' "$(screenshot_dir "$STEAM")"
BK="$TMP/backup"
copy_rf4data "$STEAM" "$BK" "mail Settings.dat Preferences.dat Crafting.dat shots" "" "$(screenshot_dir "$STEAM")" "$BK/Screenshots" "" </dev/null >/dev/null
load_mailboxes "$BK"; check "Backup: beide Mailboxen" '(( ${#MB_NAME[@]} == 2 ))'
check "Backup: Settings+Preferences, Crafting fehlt" '[[ -f "$BK/Settings.dat" && -f "$BK/Preferences.dat" && ! -f "$BK/Crafting.dat" ]]'
check "Backup: 4 Bilder (rekursiv), txt ignoriert" '[[ "$(ls "$BK/Screenshots" | wc -l | tr -d " ")" == 4 ]]' "$(ls "$BK/Screenshots")"
BK2="$TMP/backup2"; copy_rf4data "$STEAM" "$BK2" "mail" "Mailbox_555" "" "" "" </dev/null >/dev/null
load_mailboxes "$BK2"; check "Account-Filter: nur Mailbox_555" '(( ${#MB_NAME[@]} == 1 )) && [[ "${MB_NAME[0]}" == Mailbox_555 ]]'
NEW="$HOME/.wine/drive_c/users/neu/AppData/Roaming/RussianFishingLLC/RussianFishing4DE"
check "Screenshot-Ziel (create) für neuen User" '[[ "$(screenshot_dir "$NEW" create)" == "$HOME/.wine/drive_c/users/neu/Documents/Russian Fishing 4/Screenshots" ]]' "$(screenshot_dir "$NEW" create)"
NSH="$(screenshot_dir "$NEW" create)"; U3="$TMP/undo3"
copy_rf4data "$BK" "$NEW" "mail Settings.dat shots" "" "$BK/Screenshots" "$NSH" "$U3" </dev/null >/dev/null
load_mailboxes "$NEW"; check "Restore: Mailboxen vorhanden" '(( ${#MB_NAME[@]} == 2 ))'
check "Restore: 4 Screenshots (früher 0)" '[[ "$(ls "$NSH" | wc -l | tr -d " ")" == 4 ]]' "$(ls "$NSH" 2>&1)"
echo lokal-anders > "$NEW/Settings.dat"
copy_rf4data "$BK" "$NEW" "Settings.dat" "" "" "" "$U3" <<< "n" >/dev/null
check "Überschreiben abgelehnt → Datei bleibt" '[[ "$(cat "$NEW/Settings.dat")" == lokal-anders ]]'
copy_rf4data "$BK" "$NEW" "Settings.dat" "" "" "" "$U3" <<< "j" >/dev/null
check "Überschreiben bestätigt → ersetzt" '[[ "$(cat "$NEW/Settings.dat")" == steam-settings ]]'
check "Undo enthält ersetzte Datei" '[[ "$(cat "$U3/RussianFishing4DE/Settings.dat")" == lokal-anders ]]'
out=$(copy_rf4data "$BK" "$NEW" "Settings.dat" "" "" "" "" </dev/null)
check "Identische Datei: keine Rückfrage" '[[ "$out" == *identisch* ]]' "$out"

echo; echo "[5] Sync"
NAS="$TMP/nas"; mkdir -p "$NAS"
A="$HOME/.wine/drive_c/users/pcA/AppData/Roaming/RussianFishingLLC/RussianFishing4DE"
Bp="$HOME/.wine/drive_c/users/pcB/AppData/Roaming/RussianFishingLLC/RussianFishing4DE"
mkdat "$A/Mailbox_1/1.dat" 1 "$(msg a1 1)" "$(msg a2 2)"; echo A-alt > "$A/Settings.dat"
mkdat "$Bp/Mailbox_1/1.dat" 1 "$(msg a1 1)" "$(msg b1 3)"; echo B-neu > "$Bp/Settings.dat"
touch -d '2 hours ago' "$A/Settings.dat" 2>/dev/null || touch -t 202001010000 "$A/Settings.dat"
do_sync_run "$A" "$NAS" >/dev/null; do_sync_run "$Bp" "$NAS" >/dev/null; do_sync_run "$A" "$NAS" >/dev/null
check "Sync: PC A hat a1,a2,b1" '[[ "$(ids "$A/Mailbox_1/1.dat")" == a1,a2,b1 ]]' "$(ids "$A/Mailbox_1/1.dat")"
check "Sync: PC B hat a1,a2,b1" '[[ "$(ids "$Bp/Mailbox_1/1.dat")" == a1,a2,b1 ]]' "$(ids "$Bp/Mailbox_1/1.dat")"
check "Sync: neuere Settings gewinnen" '[[ "$(cat "$A/Settings.dat")" == B-neu ]]'
check "Sync: .sync_log mit 3 Zeilen" '[[ "$(wc -l < "$NAS/RF4_Sync/.sync_log" | tr -d " ")" == 3 ]]'

echo; echo "[6] Menü per Eingabe (alle Sprachen, Sprachwechsel)"
export RF4_SCAN_USERS=""
for l in de en zh ru; do
    out=$(printf '1\n\n0\n' | bash "$SCRIPT" -l "$l" 2>&1)
    check "Scan-Menü ($l) zeigt Steam-Installation und Titel" '[[ "$out" == *"RussianFishing4Steam"* && "$out" == *"v1.5.0"* ]]' "$(echo "$out" | head -5)"
done
out=$(printf 'l\n3\n0\n' | bash "$SCRIPT" -l de 2>&1)
check "Sprachwechsel im Menü (L → 中文) gespeichert" '[[ "$(cfg_get lang)" == zh ]]' "$(cfg_get lang)"
out=$(printf '0\n' | RF4_LANG="" bash "$SCRIPT" 2>&1)
check "Neustart nutzt gespeicherte Sprache (zh)" '[[ "$out" == *"扫描"* ]]' "$(echo "$out" | head -8)"
out=$(printf '9\n0\n' | bash "$SCRIPT" 2>&1); check "Ungültige Hauptmenü-Eingabe crasht nicht" '[[ "$out" == *"v1.5.0"* ]]'
out=$(bash "$SCRIPT" -h -l en 2>&1); check "--help" '[[ "$out" == *Usage* ]]' "$out"
out=$(printf '' | bash "$SCRIPT" -l en 2>&1; echo "rc=$?"); check "EOF auf stdin beendet sauber" '[[ "$out" == *rc=0* ]]' "$out"


echo; echo "[7] Backups finden, Statistik, Module, Banner"
export RF4_SCAN_USERS=""
find_backups; check "Find-Backups: ohne Backups leer" '(( ${#BK_PATH[@]} == 0 ))'
reset_stats
copy_rf4data "$STEAM" "$HOME/RF4_Backup" "mail Settings.dat" "" "" "" "" </dev/null >/dev/null
check "Statistik nach Backup: 2 Konversationen, 1 Datei, 4 Nachrichten" '(( STAT_CONV == 2 && STAT_FILES == 1 && STAT_MSG == 4 ))' "conv=$STAT_CONV files=$STAT_FILES msg=$STAT_MSG"
reset_stats; copy_rf4data "$STEAM" "$HOME/RF4_Backup" "mail Settings.dat" "" "" "" "" </dev/null >/dev/null
check "Statistik zweiter Lauf: nichts Neues" '(( STAT_CONV == 0 && STAT_FILES == 0 && STAT_MSG == 0 ))'
find_backups
check "Find-Backups: Standardordner erkannt (2 Mailboxen, 2 Konv.)" '(( ${#BK_PATH[@]} >= 1 )) && [[ "${BK_PATH[0]}" == "$HOME/RF4_Backup" ]] && (( BK_MBOX[0] == 2 && BK_CONV[0] == 2 ))' "${BK_PATH[*]} ${BK_MBOX[*]} ${BK_CONV[*]}"
MULTI="$TMP/mybackups"
copy_rf4data "$STEAM" "$MULTI/Steam_alt" "mail" "" "" "" "" </dev/null >/dev/null
copy_rf4data "$DE" "$MULTI/DE_neu" "mail Settings.dat" "" "" "" "" </dev/null >/dev/null
touch -d 'tomorrow' "$MULTI/DE_neu/Settings.dat" 2>/dev/null || touch -t 203001010000 "$MULTI/DE_neu/Settings.dat"
RF4_BACKUP_DIRS="$MULTI" find_backups
names=" ${BK_NAME[*]} "
check "Find-Backups: Unterordner eines Zusatzordners" '[[ "$names" == *" Steam_alt "* && "$names" == *" DE_neu "* ]]' "$names"
check "Find-Backups: neueste zuerst" '[[ "${BK_NAME[0]}" == DE_neu ]]' "${BK_NAME[*]}"
check "bk_info: Inhalt + Größe" '[[ "$(bk_info 0)" == *"·"* || "$(bk_info 0)" == *" - "* ]] && [[ "$(bk_info 0)" != *"{0}"* ]]' "$(bk_info 0)"
add_backup_dir "$TMP/a"; add_backup_dir "$TMP/b"; add_backup_dir "$TMP/a"
check "add_backup_dir: ohne Duplikate, neueste zuerst" '[[ "$(cfg_backup_dirs | wc -l | tr -d " ")" == 2 && "$(cfg_backup_dirs | head -1)" == *"/a" ]]' "$(cfg_backup_dirs)"
for i in 1 2 3 4 5 6 7 8 9 10; do add_backup_dir "$TMP/x$i"; done
check "add_backup_dir: maximal 8" '[[ "$(cfg_backup_dirs | wc -l | tr -d " ")" == 8 ]]'
check "Sprachreihenfolge de en zh ru" '[[ "${LANGS[*]:0:4}" == "de en zh ru" ]]' "${LANGS[*]}"
# externe Sprache
mkdir -p "$CONFIG_DIR/lang"
printf '# Test\n@code=pt\n@name=Português\napp_title=RF4 Cópia e Migração\nmenu_scan=Procurar = tudo\n' > "$CONFIG_DIR/lang/pt.lang"
load_external_langs
check "Externe Sprache pt geladen (LANGS + Name)" '[[ " ${LANGS[*]} " == *" pt "* && "${LANG_NAMES[pt]}" == "Português" ]]' "${LANGS[*]}"
LANG_CODE=pt
check "pt: eigener Text mit = korrekt, fehlender Schlüssel → Englisch" '[[ "$(t app_title)" == "RF4 Cópia e Migração" && "$(t menu_scan)" == "Procurar = tudo" && "$(t exit)" == "Exit" ]]' "$(t menu_scan) / $(t exit)"
check "resolve_lang pt-BR → pt" '[[ "$(resolve_lang pt_BR.UTF-8)" == pt ]]'
LANG_CODE=de; rm -rf "$CONFIG_DIR/lang"
# Banner
out=$(LANG_CODE=de box "RF4 Backup" "zeile 2")
w1=$(echo "$out" | sed -n 1p | wc -m); w2=$(echo "$out" | sed -n 2p | wc -m)
check "Banner-Rahmen: Zeilen gleich lang (Zeichen)" '[[ "$w1" == "$w2" ]]' "$w1 vs $w2"
LANG_CODE=zh; out=$(box "$(t app_title)" "$(t donate)")
w=$(disp_width "$(echo "$out" | sed -n 2p | sed 's/^  //')"); w3=$(disp_width "$(echo "$out" | sed -n 1p | sed 's/^  //')")
check "Banner (zh): Anzeigebreite aller Zeilen gleich ($w3)" '[[ "$w" == "$w3" ]]' "$w vs $w3"
LANG_CODE=de
check "disp_width: ASCII=1, CJK=2" '[[ "$(disp_width abc)" == 3 && "$(disp_width 备份)" == 4 ]]' "$(disp_width 备份)"
out=$(RF4_ASCII=1 bash "$SCRIPT" -l en </dev/null 2>&1); check "ASCII-Modus: keine Rahmenzeichen" '[[ "$out" != *"╔"* && "$out" == *"+====="* ]]' "$(echo "$out" | head -3)"
out=$(printf '3\n1\n0\n0\n' | bash "$SCRIPT" -l en 2>&1)
check "Restore-Menü listet Backups (Name, Pfad, Inhalt)" '[[ "$out" == *"Choose a backup"* && "$out" == *"RF4_Backup"* && "$out" == *"conversations"* ]]' "$(echo "$out" | head -12)"


echo; echo "[8] Backup-Info (von wann, von welcher Installation)"
INFO="$TMP/infotest"; mkdir -p "$INFO"
read_backup_info "$INFO"; check "Ohne Info-Datei: BI_OK=0, Quelle unbekannt" '(( BI_OK == 0 )) && [[ "$(LANG_CODE=de bk_source_text)" == *unbekannt* ]]'
si=-1; for i in "${!INST_FOLDER[@]}"; do [[ "${INST_FOLDER[$i]}" == RussianFishing4Steam && "${INST_WTYPE[$i]}" == wine ]] && si=$i; done
check "Steam-Installation (Wine) im Fixture gefunden" '(( si >= 0 ))' "${INST_FOLDER[*]}"
write_backup_info "$INFO" "$si" "mail Settings.dat"; read_backup_info "$INFO"
check "Info schreiben/lesen: Variante, Ordner, Host, Datum" '(( BI_OK == 1 )) && [[ "$BI_VARIANT" == Steam && "$BI_FOLDER" == RussianFishing4Steam && -n "$BI_HOST" && "$BI_CREATED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ && "$BI_UPDATED" == "$BI_CREATED" ]]' "$BI_VARIANT $BI_CREATED"
for l in de en zh ru; do LANG_CODE=$l; s="$(bk_source_text)"; check "Quelle in $l: $s" '[[ "$s" != *"{0}"* && ${#s} -gt 10 ]]'; done; LANG_CODE=de
c1="$BI_CREATED"
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do write_backup_info "$INFO" "$si" "mail"; done
read_backup_info "$INFO"; hl=$(grep -c '^history=' "$INFO/rf4-backup.info")
check "Mehrfach-Backup: Erstelldatum bleibt, Historie auf 10 begrenzt" '[[ "$BI_CREATED" == "$c1" ]] && (( hl == 10 ))' "$BI_CREATED vs $c1, history=$hl"
# von Windows geschriebene Info (wtype=local/user/drive)
for wt in local user drive extra; do printf 'created=2026-01-01 10:00\nupdated=2026-01-02 11:00\nhost=winpc\nvariant=EN\nfolder=RussianFishing4EN\nwtype=%s\nw1=C:\nw2=reinh\n' "$wt" > "$INFO/rf4-backup.info"; read_backup_info "$INFO"; s="$(bk_source_text)"; check "Info von Windows ($wt): $s" '[[ "$s" == *winpc* && "$s" == *Englisch* && "$s" != *"{0}"* ]]'; done
printf 'kaputt ohne gleichheitszeichen\n\n====\n' > "$INFO/rf4-backup.info"; read_backup_info "$INFO"; check "Kaputte Info-Datei crasht nicht" '[[ "$(bk_source_text)" == *unbekannt* ]]'
copy_rf4data "$STEAM" "$MULTI/mit_info" "mail" "" "" "" "" </dev/null >/dev/null; write_backup_info "$MULTI/mit_info" "$si" "mail"
RF4_BACKUP_DIRS="$MULTI" find_backups
for i in "${!BK_NAME[@]}"; do [[ "${BK_NAME[$i]}" == mit_info ]] && wi=$i; [[ "${BK_NAME[$i]}" == Steam_alt ]] && oi=$i; done
check "find_backups: Quelle aus Info-Datei (mit_info)" '[[ "${BK_SRC[$wi]}" == *Steam* && "${BK_DATES[$wi]}" == *Erstellt* ]]' "${BK_SRC[$wi]} / ${BK_DATES[$wi]}"
check "find_backups: altes Backup ohne Info → Quelle unbekannt" '[[ "${BK_SRC[$oi]}" == *unbekannt* ]]' "${BK_SRC[$oi]}"
out=$(RF4_FAKE_RUNNING=rf4_x64 rf4_running); check "RF4_FAKE_RUNNING-Hook" '[[ "$out" == rf4_x64 ]]'
out=$(printf '3\n1\n1\na\n\n1\nn\n\n0\n' | RF4_FAKE_RUNNING=rf4_x64 bash "$SCRIPT" -l en 2>&1); check "RF4 läuft + n: Abbruch ohne Import" '[[ "$out" == *"seems to be running"* && "$out" == *Cancelled* && "$out" != *"Import finished"* ]]' "$(echo "$out" | tail -8)"
out=$(printf '3\n1\n1\na\n\n1\ny\n\n0\n' | RF4_FAKE_RUNNING=rf4_x64 bash "$SCRIPT" -l en 2>&1); check "RF4 läuft + y: Import läuft durch" '[[ "$out" == *"seems to be running"* && "$out" == *"Import finished"* ]]' "$(echo "$out" | tail -8)"
check "label_for: Windows-Ort 'local' und Linux-Orte" '[[ "$(label_for Steam RussianFishing4Steam local C: reinh)" == *"C: / reinh"* && "$(label_for Other Foo wine /p natural)" == *"Wine: natural"* && "$(label_for DE x proton 309850 u)" == *"309850"* ]]'

echo
printf 'Ergebnis: %d bestanden, %d fehlgeschlagen\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
