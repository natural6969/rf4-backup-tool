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
# Version @@VERSION@@ – @@DATE@@

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # '&' in Ersetzungstexten nicht speziell behandeln (bash 5.2+)

TOOL_VERSION="@@VERSION@@"
LANGS=(de en zh ru)
declare -A LANG_NAMES=([de]="Deutsch" [en]="English" [zh]="中文" [ru]="Русский")
DAT_FILES=(Settings.dat Preferences.dat Crafting.dat)

# ── Übersetzungen (generiert aus src/core.ps1 – eine Quelle für Windows und Linux) ──
declare -A TX
# @@STRINGS@@

# ── Konfiguration / Sprache ────────────────────────────────────────────────────
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
resolve_lang() {
    local c="${1:-}"; c="${c,,}"; c="${c:0:2}"
    case "$c" in de|en|zh|ru) printf '%s' "$c" ;; esac
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
sep()  { printf '%s\n' "${D}------------------------------------------------------------${NC}"; }
hdr()  { printf '\n%s\n' "${B}== ${W}$*${B} ==${NC}"; sep; }
ok()   { printf '%s\n' "  ${G}[OK]${NC} $*"; }
warn() { printf '%s\n' "  ${Y}[!]${NC} $*"; }
err()  { printf '%s\n' "  ${R}[X]${NC} $*" >&2; }
info() { printf '%s\n' "  ${C}-->${NC} $*"; }
log()  { case "$1" in ok) ok "$2" ;; warn) warn "$2" ;; err) err "$2" ;; *) info "$2" ;; esac; }
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
rf4_running() {   # gibt Prozessnamen aus, wenn RF4 läuft
    command -v pgrep >/dev/null 2>&1 || return 1
    pgrep -if 'rf4_x64|rf4_x32|RussianFishing4\.exe|RussianFishing.*\.exe' 2>/dev/null | head -1 | grep -q . && echo "rf4"
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

inst_label() {   # inst_label index
    local i="$1" name where
    if [[ "${INST_VARIANT[$i]}" == "Other" ]]; then name=$(t v_Other "${INST_FOLDER[$i]}"); else name=$(t "v_${INST_VARIANT[$i]}"); fi
    case "${INST_WTYPE[$i]}" in
        win)    where=$(t w_win "${INST_W1[$i]}" "${INST_W2[$i]}") ;;
        wine)   where=$(t w_wine "${INST_W2[$i]}") ;;
        proton) where=$(t w_proton "${INST_W1[$i]}") ;;
        *)      where=$(t w_extra "${INST_W1[$i]}") ;;
    esac
    printf '%s [%s]' "$name" "$where"
}

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
        print('COPIED\t' + name)
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
            COPIED)    copied=$((copied + 1)) ;;
            UNCHANGED) unchanged=$((unchanged + 1)) ;;
            MERGED)    merged=$((merged + 1)); info "$(t mb_merge_file "$name" "$extra")" ;;
            FAILED)    failed=$((failed + 1)); warn "$(t mb_merge_fail "$name" "$extra")" ;;
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
            save_undo "$dst" "$undo"; cp -f "$src" "$dst" && ok "$(t f_overwritten "$name")" || err "$(t f_failed "$name" cp)"
        else warn "$(t f_skipped "$name")"; fi
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst" && ok "$(t f_copied "$name")" || err "$(t f_failed "$name" cp)"
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
    ok "$(t shots_done "$n" "$dst")"
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
    copy_rf4data "$src" "$dest" "$items" "$ACCOUNTS" "$(screenshot_dir "$src")" "$dest/Screenshots" ""
    echo; ok "$(t backup_done "$dest")"
    pause
}

# ── RESTORE ────────────────────────────────────────────────────────────────────
do_restore() {
    hdr "$(t hdr_restore)"
    local def="$HOME/RF4_Backup" src
    read -r -p "  $(t backup_dir_p "$def") " src || src=""
    [[ -z "$src" ]] && src="$def"
    [[ -d "$src" ]] || { err "$(t folder_missing "$src")"; pause; return; }
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
    copy_rf4data "$src" "$dst" "$items" "$ACCOUNTS" "$src/Screenshots" "$(screenshot_dir "$dst" create)" "$(new_undo_root "$dst")"
    ok "$(t restore_done)"
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
    local k si
    for k in "${MULTI_SEL[@]}"; do
        si="${src_idx[$k]}"
        info "$(t merge_src_hdr "$(inst_label "$si")")"
        load_mailboxes "${INST_PATH[$si]}"; select_accounts "${INST_PATH[$si]}" which_acct_m
        (( ACC_BACK )) && continue
        copy_rf4data "${INST_PATH[$si]}" "$dpath" "mail" "$ACCOUNTS" "" "" "$undo"
    done
    ok "$(t merge_done)"
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
               do_sync_run "${INST_PATH[$ci]}" "$sp"
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
        printf '%s\n' "${B}============================================================${NC}"
        printf '%s\n' "${B}  $(t app_title)   v${TOOL_VERSION}${NC}"
        printf '%s\n' "${B}============================================================${NC}"
        printf '%s\n' "  ${D}RF4: nga.li/rf4de | Blog: nga.li/rf4b${NC}" "  ${D}$(t donate)${NC}" ""
        printf '%s\n' "  ${Y}[1]${NC} $(t menu_scan)" "  ${Y}[2]${NC} $(t menu_backup)" "  ${Y}[3]${NC} $(t menu_restore)" \
                      "  ${Y}[4]${NC} $(t menu_merge)" "  ${Y}[5]${NC} $(t menu_sync)" \
                      "  ${Y}[L]${NC} $(t menu_lang) (${LANG_NAMES[$LANG_CODE]})" "  ${Y}[0]${NC} $(t exit)" ""
        read -r -p "  $(t choose): " raw || return 0
        raw="${raw,,}"; raw="${raw//[[:space:]]/}"
        case "$raw" in
            1) do_scan ;; 2) do_backup ;; 3) do_restore ;; 4) do_merge ;; 5) do_sync ;;
            l) do_language ;; 0) return 0 ;;
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
init_lang "$ARG_LANG"
if (( SHOW_HELP )); then echo "$(t usage)"; exit 0; fi
if [[ "${RF4_NO_MAIN:-0}" != "1" ]]; then main_menu; fi
