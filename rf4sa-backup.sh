#!/usr/bin/env bash
# rf4sa-backup.sh — RF4 Standalone Backup & Migration (interaktiv)
# Findet automatisch alle Installationen auf Windows-Partitionen, Wine & Proton.
#
# Infos & Blog:  https://nga.li/rf4b
# Quellcode:     https://nga.li/rf4git  (Codeberg)
# RF4 Offiziell: https://nga.li/rf4de  (DE)  |  https://nga.li/rf4en  (EN)
# Steam:         https://nga.li/rf4steam
# Download:      https://nga.li/rf4dl
# Transfer-Info: https://nga.li/rf4transfer  (nur Steam → Standalone)
#
# Version 1.2.0 – 2026-07-04
# Changelog:
#   1.2.0  Cloud/NAS-Sync (bidirektional, ordnerbasiert: Nextcloud/NAS/USB/Syncthing)
#   1.1.1  Header-Links aktualisiert (nga.li/rf4b + Codeberg)
#   1.1.0  Standalone-Labels, Account-IDs im Scan, Per-Account Backup/Restore,
#          Multi-Quellen Merge, nga.li-Links, Linux→Linux Unterstützung
#   1.0.0  Erstveröffentlichung

set -uo pipefail

# ── Farben ─────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[1;34m' C='\033[0;36m'
W='\033[1;37m' D='\033[2m' NC='\033[0m'

# ── Konfiguration ──────────────────────────────────────────────────────────────
SYNC_CONFIG_DIR="$HOME/.config/rf4-backup"
SYNC_CONFIG="$SYNC_CONFIG_DIR/sync.conf"

# SA + Steam als Varianten (Steam separat markiert)
RF4_VARIANTS=(RussianFishing4DE RussianFishing4DE_new RussianFishing4EN RussianFishing4Steam)
declare -A VARIANT_LABELS=(
    [RussianFishing4DE]="RF4 Standalone Deutsch"
    [RussianFishing4DE_new]="RF4 Standalone Deutsch (neu)"
    [RussianFishing4EN]="RF4 Standalone Englisch"
    [RussianFishing4Steam]="RF4 Steam"
)
# Steam-Varianten (werden im Backup-Menü gesondert gekennzeichnet)
RF4_STEAM_VARIANTS=(RussianFishing4Steam)
RF4_BASE="AppData/Roaming/RussianFishingLLC"
SCREENSHOT_SUBPATH="Documents/Russian Fishing 4/Screenshots"
DEFAULT_BACKUP_DIR="$HOME/RF4_Backup"

# ── Links ──────────────────────────────────────────────────────────────────────
RF4_BLOG="https://nga.li/rf4b"
RF4_LINK_DE="https://nga.li/rf4de"
RF4_LINK_EN="https://nga.li/rf4en"
RF4_LINK_STEAM="https://nga.li/rf4steam"
RF4_LINK_DL="https://nga.li/rf4dl"
RF4_LINK_FORUM="https://nga.li/rf4forum"
RF4_LINK_TRANSFER="https://nga.li/rf4transfer"

# ── Hilfsfunktionen ────────────────────────────────────────────────────────────
sep()  { echo -e "${D}────────────────────────────────────────────────────────${NC}"; }
hdr()  { echo; echo -e "${B}╔══ ${W}$* ${B}══╗${NC}"; sep; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}⚠${NC} $*"; }
err()  { echo -e "  ${R}✗${NC} $*" >&2; }
info() { echo -e "  ${C}→${NC} $*"; }

pause() { echo; read -r -p "  [Enter] zum Fortfahren..."; }

# Numerisches Menü: menu "Titel" "opt1" "opt2" ... → gibt 1-basierte Auswahl zurück
menu() {
    local title="$1"; shift
    local opts=("$@")
    echo
    echo -e "  ${W}$title${NC}"
    sep
    local i=1
    for o in "${opts[@]}"; do
        echo -e "  ${Y}[$i]${NC} $o"
        ((i++))
    done
    echo -e "  ${Y}[0]${NC} Zurück"
    echo
    local choice
    while true; do
        read -r -p "  Wähle: " choice
        [[ "$choice" == "0" ]] && return 0
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )) && { MENU_CHOICE=$choice; return "$choice"; }
        echo -e "  ${R}Ungültige Eingabe.${NC}"
    done
}

# Mehrfachauswahl: multiselect "Titel" "opt1" ... → SELECTED=() Array
multiselect() {
    local title="$1"; shift
    local opts=("$@")
    SELECTED=()
    local chosen=()
    for _ in "${opts[@]}"; do chosen+=(0); done

    while true; do
        echo
        echo -e "  ${W}$title${NC} ${D}(Leertaste = an/aus, Enter = bestätigen)${NC}"
        sep
        local i=0
        for o in "${opts[@]}"; do
            if [[ "${chosen[$i]}" == "1" ]]; then
                echo -e "  ${G}[✓]${NC} $((i+1))) $o"
            else
                echo -e "  ${D}[ ]${NC} $((i+1))) $o"
            fi
            ((i++))
        done
        echo -e "  ${Y}[a]${NC} Alle  ${Y}[n]${NC} Keine  ${Y}[Enter]${NC} OK  ${Y}[0]${NC} Zurück"
        echo
        read -r -p "  Wähle (Nr. oder a/n/Enter): " choice

        if [[ -z "$choice" ]]; then
            for i in "${!chosen[@]}"; do
                [[ "${chosen[$i]}" == "1" ]] && SELECTED+=("${opts[$i]}")
            done
            return 0
        elif [[ "$choice" == "0" ]]; then
            return 1
        elif [[ "$choice" == "a" ]]; then
            for i in "${!chosen[@]}"; do chosen[$i]=1; done
        elif [[ "$choice" == "n" ]]; then
            for i in "${!chosen[@]}"; do chosen[$i]=0; done
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
            local idx=$((choice-1))
            chosen[$idx]=$(( 1 - chosen[$idx] ))
        fi
    done
}

# ── Installation finden ────────────────────────────────────────────────────────
# Gibt Zeilen aus: "LABEL|PFAD|TYP"
find_installations() {
    local -A seen

    _emit() {
        local label="$1" path="$2" type="$3"
        [[ -d "$path" ]] || return
        [[ -n "${seen[$path]:-}" ]] && return
        seen[$path]=1
        echo "${label}|${path}|${type}"
    }

    # 1) Windows-Partitionen
    for mp in /mnt/* /run/media/*/*; do
        [[ -d "$mp/Users" ]] || continue
        local vol
        vol=$(basename "$mp")
        for user_dir in "$mp"/Users/*/; do
            [[ -d "$user_dir" ]] || continue
            local user
            user=$(basename "$user_dir")
            for variant in "${RF4_VARIANTS[@]}"; do
                local p="$user_dir$RF4_BASE/$variant"
                local label="${VARIANT_LABELS[$variant]:-$variant} [Win: $vol/$user]"
                _emit "$label" "$p" "windows"
            done
        done
    done

    # 2) Plain Wine (~/.wine oder benutzerdefiniert)
    for wine_root in "$HOME/.wine" "$HOME/.local/share/wineprefixes"/*; do
        [[ -d "$wine_root/drive_c/users" ]] || continue
        for user_dir in "$wine_root"/drive_c/users/*/; do
            [[ -d "$user_dir" ]] || continue
            local user
            user=$(basename "$user_dir")
            [[ "$user" == "Public" || "$user" == "All Users" ]] && continue
            for variant in "${RF4_VARIANTS[@]}"; do
                local p="$user_dir$RF4_BASE/$variant"
                local label="${VARIANT_LABELS[$variant]:-$variant} [Wine: $user_dir]"
                _emit "$label" "$p" "wine"
            done
        done
    done

    # 3) Steam Proton compatdata
    for compat in \
        "$HOME/.local/share/Steam/steamapps/compatdata" \
        "$HOME/.steam/steam/steamapps/compatdata"
    do
        [[ -d "$compat" ]] || continue
        for prefix in "$compat"/*/; do
            local appid
            appid=$(basename "$prefix")
            local users_dir="$prefix/pfx/drive_c/users"
            [[ -d "$users_dir" ]] || continue
            for user_dir in "$users_dir"/*/; do
                [[ -d "$user_dir" ]] || continue
                local user
                user=$(basename "$user_dir")
                [[ "$user" == "Public" || "$user" == "All Users" ]] && continue
                for variant in "${RF4_VARIANTS[@]}"; do
                    local p="$user_dir$RF4_BASE/$variant"
                    local label="${VARIANT_LABELS[$variant]:-$variant} [Proton: AppID $appid]"
                    _emit "$label" "$p" "proton"
                done
            done
        done
    done
}

# Alle gefundenen Installationen (auch leere/neue)
declare -a INST_LABELS=()
declare -a INST_PATHS=()
declare -a INST_TYPES=()

load_installations() {
    INST_LABELS=()
    INST_PATHS=()
    INST_TYPES=()
    while IFS='|' read -r label path type; do
        INST_LABELS+=("$label")
        INST_PATHS+=("$path")
        INST_TYPES+=("$type")
    done < <(find_installations)
}

print_installations() {
    if [[ ${#INST_PATHS[@]} -eq 0 ]]; then
        warn "Keine Installationen gefunden."
        return
    fi
    local i=0
    for path in "${INST_PATHS[@]}"; do
        local label="${INST_LABELS[$i]}"
        local type="${INST_TYPES[$i]}"
        if [[ -d "$path" ]]; then
            local mboxes
            mboxes=$(find "$path" -maxdepth 1 -name "Mailbox_*" -type d 2>/dev/null | wc -l)
            local convs
            convs=$(find "$path" -maxdepth 2 -name "*.dat" -path "*/Mailbox_*" 2>/dev/null | wc -l)
            local acc_ids
            acc_ids=$(find "$path" -maxdepth 1 -name "Mailbox_*" -type d 2>/dev/null | \
                      sed 's|.*/Mailbox_||' | sort | tr '\n' ' ' | sed 's/ $//')
            ok "$label"
            info "  Pfad: ${D}$path${NC}"
            info "  Mailboxen: $mboxes  Konversationen: $convs"
            [[ -n "$acc_ids" ]] && info "  Account-IDs: $acc_ids"
        else
            echo -e "  ${D}[leer]${NC} $label"
            info "  Pfad: ${D}$path${NC} ${R}(nicht vorhanden)${NC}"
        fi
        echo
        ((i++))
    done
}

# ── Mailboxen mergen ───────────────────────────────────────────────────────────
merge_mailboxes() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || { warn "Quelle nicht gefunden: $src"; return; }
    mkdir -p "$dst"

    local merged=0 copied=0
    for src_file in "$src"/*.dat; do
        [[ -f "$src_file" ]] || continue
        local fname
        fname=$(basename "$src_file")
        local dst_file="$dst/$fname"

        if [[ ! -f "$dst_file" ]]; then
            cp "$src_file" "$dst_file"
            ((copied++))
        else
            # Merge per UUID-Dedup
            python3 - "$src_file" "$dst_file" "$dst_file.tmp" << 'PY'
import json, sys
def load(p):
    with open(p, encoding='utf-8-sig') as f: return json.load(f)
s, d, out = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
seen = {i['meta']['id'] for i in d.get('items', [])}
extra = [i for i in s.get('items', []) if i['meta']['id'] not in seen]
merged = dict(d)
merged['items'] = sorted(d.get('items', []) + extra, key=lambda i: i['meta']['created'])
with open(out, 'w', encoding='utf-8') as f:
    json.dump(merged, f, ensure_ascii=False, indent=2)
print(len(extra))
PY
            local added
            added=$(cat "$dst_file.tmp.count" 2>/dev/null || python3 -c "
import json
s=json.load(open('$src_file',encoding='utf-8-sig'))
d=json.load(open('$dst_file',encoding='utf-8-sig'))
seen={i['meta']['id'] for i in d.get('items',[])}
print(len([i for i in s.get('items',[]) if i['meta']['id'] not in seen]))
" 2>/dev/null || echo "?")
            mv "$dst_file.tmp" "$dst_file"
            info "  Merge $fname: +$added Nachrichten"
            ((merged++))
        fi
    done
    ok "Mailbox: $merged Dateien gemergt, $copied neu kopiert"
}

# ── Backup durchführen ─────────────────────────────────────────────────────────
do_backup() {
    hdr "BACKUP"

    # Quelle wählen
    load_installations
    if [[ ${#INST_PATHS[@]} -eq 0 ]]; then
        err "Keine Installationen gefunden."; pause; return; fi

    local opts=()
    for i in "${!INST_LABELS[@]}"; do
        [[ -d "${INST_PATHS[$i]}" ]] && opts+=("${INST_LABELS[$i]}") || opts+=("${INST_LABELS[$i]} ${R}[leer]${NC}")
    done
    menu "Quelle wählen" "${opts[@]}" || return
    local src_idx=$((MENU_CHOICE-1))
    local src_path="${INST_PATHS[$src_idx]}"

    if [[ ! -d "$src_path" ]]; then
        err "Quellpfad nicht gefunden: $src_path"; pause; return; fi

    # Was sichern?
    local items=("Mailboxen (private Nachrichten)" "Settings.dat (Grafik/Audio/Tasten)"
                 "Preferences.dat" "Crafting.dat" "Screenshots")
    multiselect "Was soll gesichert werden?" "${items[@]}" || return
    [[ ${#SELECTED[@]} -eq 0 ]] && { warn "Nichts ausgewählt."; pause; return; }

    # Ziel
    echo
    echo -e "  Backup-Ordner [${D}$DEFAULT_BACKUP_DIR${NC}]: "
    read -r -p "  (Enter = Standard): " dest
    dest="${dest:-$DEFAULT_BACKUP_DIR}"
    mkdir -p "$dest"

    echo
    info "Sichere von: $src_path"
    info "Nach:        $dest"
    sep

    for sel in "${SELECTED[@]}"; do
        case "$sel" in
            Mailboxen*)
                local mbox_dirs=()
                for mbox in "$src_path"/Mailbox_*/; do
                    [[ -d "$mbox" ]] && mbox_dirs+=("$mbox")
                done
                if [[ ${#mbox_dirs[@]} -eq 0 ]]; then warn "Keine Mailboxen gefunden."; continue; fi
                local sel_mboxes=("${mbox_dirs[@]}")
                if [[ ${#mbox_dirs[@]} -gt 1 ]]; then
                    local mb_opts=("Alle Accounts (${#mbox_dirs[@]})")
                    for mbox in "${mbox_dirs[@]}"; do
                        local mname acc_id cnt
                        mname=$(basename "$mbox")
                        acc_id="${mname#Mailbox_}"
                        cnt=$(ls "$mbox"*.dat 2>/dev/null | wc -l)
                        mb_opts+=("Account $acc_id  ($cnt Konversationen)")
                    done
                    menu "Welchen Account sichern?" "${mb_opts[@]}" || continue
                    if [[ $MENU_CHOICE -gt 1 ]]; then
                        sel_mboxes=("${mbox_dirs[$((MENU_CHOICE-2))]}")
                    fi
                fi
                for mbox in "${sel_mboxes[@]}"; do
                    [[ -d "$mbox" ]] || continue
                    local mname cnt
                    mname=$(basename "$mbox")
                    cnt=$(ls "$mbox"*.dat 2>/dev/null | wc -l)
                    info "Mailbox $mname ($cnt Konversationen) …"
                    merge_mailboxes "$mbox" "$dest/$mname"
                done
                ;;
            Settings*)
                if [[ ! -f "$src_path/Settings.dat" ]]; then warn "Settings.dat nicht gefunden"
                elif [[ -f "$dest/Settings.dat" ]]; then
                    read -r -p "  Settings.dat existiert im Backup. Überschreiben? [j/N]: " ow
                    [[ "$ow" =~ ^[jJ]$ ]] && { cp "$src_path/Settings.dat" "$dest/"; ok "Settings.dat überschrieben"; } \
                        || warn "Settings.dat übersprungen"
                else cp "$src_path/Settings.dat" "$dest/"; ok "Settings.dat"; fi
                ;;
            Preferences*)
                if [[ ! -f "$src_path/Preferences.dat" ]]; then warn "Preferences.dat nicht gefunden"
                elif [[ -f "$dest/Preferences.dat" ]]; then
                    read -r -p "  Preferences.dat existiert im Backup. Überschreiben? [j/N]: " ow
                    [[ "$ow" =~ ^[jJ]$ ]] && { cp "$src_path/Preferences.dat" "$dest/"; ok "Preferences.dat überschrieben"; } \
                        || warn "Preferences.dat übersprungen"
                else cp "$src_path/Preferences.dat" "$dest/"; ok "Preferences.dat"; fi
                ;;
            Crafting*)
                if [[ ! -f "$src_path/Crafting.dat" ]]; then warn "Crafting.dat nicht gefunden"
                elif [[ -f "$dest/Crafting.dat" ]]; then
                    read -r -p "  Crafting.dat existiert im Backup. Überschreiben? [j/N]: " ow
                    [[ "$ow" =~ ^[jJ]$ ]] && { cp "$src_path/Crafting.dat" "$dest/"; ok "Crafting.dat überschrieben"; } \
                        || warn "Crafting.dat übersprungen"
                else cp "$src_path/Crafting.dat" "$dest/"; ok "Crafting.dat"; fi
                ;;
            Screenshots*)
                # Screenshots: im Installationsverzeichnis oder Windows Documents
                local shot_dir
                shot_dir=$(dirname "$(dirname "$(dirname "$(dirname "$src_path")")")")
                local shot_path="$shot_dir/$SCREENSHOT_SUBPATH"
                if [[ -d "$shot_path" ]]; then
                    mkdir -p "$dest/Screenshots"
                    local count=0
                    for img in "$shot_path"/*.png "$shot_path"/*.jpg; do
                        [[ -f "$img" ]] || continue
                        local tgt="$dest/Screenshots/$(basename "$img")"
                        [[ -f "$tgt" ]] || { cp "$img" "$tgt"; ((count++)); }
                    done
                    ok "Screenshots: $count Bilder"
                else
                    warn "Screenshot-Ordner nicht gefunden: $shot_path"
                fi
                ;;
        esac
    done

    echo
    ok "Backup fertig: $dest"
    echo -e "  Inhalt:"
    ls -lh "$dest" 2>/dev/null | grep -v "^total" | sed 's/^/    /'
    pause
}

# ── Restore / Import ───────────────────────────────────────────────────────────
do_restore() {
    hdr "RESTORE / IMPORT"

    # Backup-Ordner
    echo
    echo -e "  Backup-Ordner [${D}$DEFAULT_BACKUP_DIR${NC}]: "
    read -r -p "  (Enter = Standard): " src
    src="${src:-$DEFAULT_BACKUP_DIR}"
    if [[ ! -d "$src" ]]; then
        err "Backup-Ordner nicht gefunden: $src"; pause; return; fi

    # Backup-Inhalt zeigen
    info "Backup-Inhalt:"
    local mboxes=()
    for d in "$src"/Mailbox_*/; do
        [[ -d "$d" ]] || continue
        mboxes+=("$d")
        local convs
        convs=$(ls "$d"*.dat 2>/dev/null | wc -l)
        info "  $(basename $d): $convs Gespräche"
    done
    for f in Settings.dat Preferences.dat Crafting.dat; do
        [[ -f "$src/$f" ]] && info "  $f"
    done
    local shots
    shots=$(find "$src/Screenshots" -type f 2>/dev/null | wc -l)
    [[ $shots -gt 0 ]] && info "  Screenshots: $shots Dateien"

    # Ziel wählen
    load_installations
    local opts=()
    for i in "${!INST_LABELS[@]}"; do opts+=("${INST_LABELS[$i]}"); done
    opts+=("→ Neuen Pfad manuell eingeben")
    menu "Ziel-Installation wählen" "${opts[@]}" || return

    local dst_path
    if [[ $MENU_CHOICE -le ${#INST_PATHS[@]} ]]; then
        local dst_idx=$((MENU_CHOICE-1))
        dst_path="${INST_PATHS[$dst_idx]}"
    else
        read -r -p "  Pfad eingeben: " dst_path
    fi

    if [[ -z "$dst_path" ]]; then err "Kein Pfad."; pause; return; fi
    mkdir -p "$dst_path"

    # Was importieren?
    local avail=()
    [[ ${#mboxes[@]} -gt 0 ]] && avail+=("Mailboxen (${#mboxes[@]} Ordner)")
    [[ -f "$src/Settings.dat" ]]    && avail+=("Settings.dat")
    [[ -f "$src/Preferences.dat" ]] && avail+=("Preferences.dat")
    [[ -f "$src/Crafting.dat" ]]    && avail+=("Crafting.dat")
    [[ $shots -gt 0 ]]             && avail+=("Screenshots ($shots Dateien)")

    multiselect "Was importieren?" "${avail[@]}" || return
    [[ ${#SELECTED[@]} -eq 0 ]] && { warn "Nichts ausgewählt."; pause; return; }

    info "Importiere nach: $dst_path"
    sep

    # Überschreib-Strategie bei Settings
    local overwrite_settings=0
    for sel in "${SELECTED[@]}"; do
        case "$sel" in
            Settings*|Preferences*|Crafting*)
                local fname="${sel%%.*}.dat"
                [[ "$sel" == Settings* ]] && fname="Settings.dat"
                [[ "$sel" == Preferences* ]] && fname="Preferences.dat"
                [[ "$sel" == Crafting* ]] && fname="Crafting.dat"
                if [[ -f "$dst_path/$fname" ]]; then
                    echo -e "  ${Y}$fname${NC} existiert bereits."
                    read -r -p "  Überschreiben? [j/N]: " ow
                    [[ "$ow" =~ ^[jJ]$ ]] && { cp "$src/$fname" "$dst_path/"; ok "$fname überschrieben"; } \
                        || warn "$fname übersprungen"
                else
                    cp "$src/$fname" "$dst_path/"; ok "$fname kopiert"
                fi
                ;;
            Mailboxen*)
                local src_mboxes=()
                for mbox in "$src"/Mailbox_*/; do
                    [[ -d "$mbox" ]] && src_mboxes+=("$mbox")
                done
                local sel_mboxes=("${src_mboxes[@]}")
                if [[ ${#src_mboxes[@]} -gt 1 ]]; then
                    local mb_opts=("Alle Accounts (${#src_mboxes[@]})")
                    for mbox in "${src_mboxes[@]}"; do
                        local mname acc_id cnt
                        mname=$(basename "$mbox")
                        acc_id="${mname#Mailbox_}"
                        cnt=$(ls "$mbox"*.dat 2>/dev/null | wc -l)
                        mb_opts+=("Account $acc_id  ($cnt Konversationen)")
                    done
                    menu "Welchen Account importieren?" "${mb_opts[@]}" || continue
                    if [[ $MENU_CHOICE -gt 1 ]]; then
                        sel_mboxes=("${src_mboxes[$((MENU_CHOICE-2))]}")
                    fi
                fi
                for mbox in "${sel_mboxes[@]}"; do
                    [[ -d "$mbox" ]] || continue
                    local mname
                    mname=$(basename "$mbox")
                    info "Mailbox $mname …"
                    merge_mailboxes "$mbox" "$dst_path/$mname"
                done
                ;;
            Screenshots*)
                local shot_dst
                # Für Wine/Windows: in Documents-Pfad schreiben
                shot_dst=$(dirname "$(dirname "$(dirname "$(dirname "$dst_path")")")")
                shot_dst="$shot_dst/$SCREENSHOT_SUBPATH"
                mkdir -p "$shot_dst"
                local count=0
                for img in "$src/Screenshots"/*; do
                    [[ -f "$img" ]] || continue
                    local tgt="$shot_dst/$(basename "$img")"
                    [[ -f "$tgt" ]] || { cp "$img" "$tgt"; ((count++)); }
                done
                ok "Screenshots: $count Bilder → $shot_dst"
                ;;
        esac
    done

    ok "Import abgeschlossen."
    pause
}

# ── Alle Installationen scannen ────────────────────────────────────────────────
do_scan() {
    hdr "INSTALLATIONEN SCANNEN"
    info "Suche auf allen Laufwerken…"
    echo
    load_installations
    print_installations
    echo -e "  ${D}Gesamt: ${#INST_PATHS[@]} gefundene Pfade${NC}"
    pause
}

# ── Installationen zusammenführen ──────────────────────────────────────────────
do_merge() {
    hdr "INSTALLATIONEN MERGEN"
    load_installations

    echo
    echo -e "  ${Y}WICHTIG:${NC} RF4 erlaubt nur den Wechsel ${W}Steam → Standalone${NC},"
    echo -e "           nicht umgekehrt. Standalone → Steam ist ${R}NICHT möglich${NC}."
    info "  Details: $RF4_LINK_TRANSFER"
    echo
    info "  Unterstützte Szenarien:"
    info "   · Steam → Standalone          (Versionswechsel)"
    info "   · Steam → Steam               (PC-Wechsel, neue Installation)"
    info "   · Standalone → Standalone     (PC-Wechsel, neue Installation)"
    info "   · Linux Wine/Proton → Linux   (Migration zwischen Systemen)"
    info "   · Mehrere alte → eine neue    (alle Quellen auswählen)"
    echo

    local existing=()
    local existing_paths=()
    local i=0
    for path in "${INST_PATHS[@]}"; do
        if [[ -d "$path" ]]; then
            existing+=("${INST_LABELS[$i]}")
            existing_paths+=("$path")
        fi
        ((i++))
    done

    if [[ ${#existing[@]} -lt 2 ]]; then
        warn "Mindestens 2 vorhandene Installationen nötig."; pause; return; fi

    # Ziel zuerst wählen
    menu "Ziel-Installation (Hauptinstallation)" "${existing[@]}" || return
    local dst_idx=$((MENU_CHOICE-1))
    local dst_path="${existing_paths[$dst_idx]}"

    # Quellen: alle außer Ziel zur Auswahl anbieten
    local src_opts=()
    local src_paths=()
    for i in "${!existing[@]}"; do
        if [[ "${existing_paths[$i]}" != "$dst_path" ]]; then
            src_opts+=("${existing[$i]}")
            src_paths+=("${existing_paths[$i]}")
        fi
    done

    if [[ ${#src_opts[@]} -eq 0 ]]; then
        err "Keine weiteren Installationen als Quellen verfügbar."; pause; return; fi

    multiselect "Quellen wählen (mehrere möglich)" "${src_opts[@]}" || return
    [[ ${#SELECTED[@]} -eq 0 ]] && { warn "Keine Quelle gewählt."; pause; return; }

    info "Ziel: $dst_path"
    sep

    for sel_label in "${SELECTED[@]}"; do
        # Quellpfad aus Label suchen
        local src_path=""
        for i in "${!src_opts[@]}"; do
            [[ "${src_opts[$i]}" == "$sel_label" ]] && src_path="${src_paths[$i]}" && break
        done
        [[ -z "$src_path" ]] && continue

        info "=== Quelle: $sel_label"

        local mbox_dirs=()
        for mbox in "$src_path"/Mailbox_*/; do
            [[ -d "$mbox" ]] && mbox_dirs+=("$mbox")
        done
        if [[ ${#mbox_dirs[@]} -eq 0 ]]; then
            warn "  Keine Mailboxen gefunden."; continue; fi

        local sel_mboxes=("${mbox_dirs[@]}")
        if [[ ${#mbox_dirs[@]} -gt 1 ]]; then
            local mb_opts=("Alle Accounts (${#mbox_dirs[@]})")
            for mbox in "${mbox_dirs[@]}"; do
                local mname acc_id cnt
                mname=$(basename "$mbox")
                acc_id="${mname#Mailbox_}"
                cnt=$(ls "$mbox"*.dat 2>/dev/null | wc -l)
                mb_opts+=("Account $acc_id  ($cnt Konversationen)")
            done
            menu "Welche Accounts aus dieser Quelle mergen?" "${mb_opts[@]}" || continue
            if [[ $MENU_CHOICE -gt 1 ]]; then
                sel_mboxes=("${mbox_dirs[$((MENU_CHOICE-2))]}")
            fi
        fi

        for mbox in "${sel_mboxes[@]}"; do
            [[ -d "$mbox" ]] || continue
            local mname
            mname=$(basename "$mbox")
            info "Mailbox $mname …"
            merge_mailboxes "$mbox" "$dst_path/$mname"
        done
    done

    ok "Merge abgeschlossen."
    pause
}

# ── Cloud/NAS-Sync ─────────────────────────────────────────────────────────────
sync_get_path() { [[ -f "$SYNC_CONFIG" ]] && cat "$SYNC_CONFIG" || echo ""; }
sync_set_path() { mkdir -p "$SYNC_CONFIG_DIR" && printf '%s' "$1" > "$SYNC_CONFIG"; }
file_mtime()    { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

do_sync_run() {
    local inst_path="$1" sync_base="$2"
    local sync_dir="$sync_base/RF4_Sync"
    mkdir -p "$sync_dir"

    echo
    info "Lokal:  $inst_path"
    info "Sync:   $sync_dir"
    sep

    # Phase 1: Lokal → Sync
    echo -e "\n  ${W}↑ Phase 1: Lokal → Sync${NC} ${D}(neue Nachrichten hochladen)${NC}"
    local any_local=0
    for mbox in "$inst_path"/Mailbox_*/; do
        [[ -d "$mbox" ]] || continue
        any_local=1
        local mname; mname=$(basename "$mbox")
        info "  ↑ $mname"
        merge_mailboxes "$mbox" "$sync_dir/$mname"
    done
    [[ $any_local -eq 0 ]] && warn "Keine lokalen Mailboxen – nur Pull wird ausgeführt."

    # Phase 2: Sync → Lokal
    echo -e "\n  ${W}↓ Phase 2: Sync → Lokal${NC} ${D}(neue Nachrichten herunterladen)${NC}"
    local any_sync=0
    for mbox in "$sync_dir"/Mailbox_*/; do
        [[ -d "$mbox" ]] || continue
        any_sync=1
        local mname; mname=$(basename "$mbox")
        info "  ↓ $mname"
        merge_mailboxes "$mbox" "$inst_path/$mname"
    done
    [[ $any_sync -eq 0 ]] && warn "Sync-Ordner enthält noch keine Mailboxen von anderen Geräten."

    # Settings/Preferences/Crafting: neuere Version gewinnt
    echo -e "\n  ${W}⇄ Einstellungen${NC} ${D}(neuere Version gewinnt automatisch)${NC}"
    for dat in Settings.dat Preferences.dat Crafting.dat; do
        local lf="$inst_path/$dat" sf="$sync_dir/$dat"
        if [[ -f "$lf" && ! -f "$sf" ]]; then
            cp "$lf" "$sf" && ok "$dat → Sync (neu hochgeladen)"
        elif [[ ! -f "$lf" && -f "$sf" ]]; then
            cp "$sf" "$lf" && ok "$dat ← Sync (neu heruntergeladen)"
        elif [[ -f "$lf" && -f "$sf" ]]; then
            local lt st; lt=$(file_mtime "$lf"); st=$(file_mtime "$sf")
            if   [[ $lt -gt $st ]]; then cp "$lf" "$sf" && ok "$dat → Sync (lokal neuer)"
            elif [[ $st -gt $lt ]]; then cp "$sf" "$lf" && ok "$dat ← Sync (Sync neuer)"
            else info "$dat: identisch, übersprungen"; fi
        fi
    done

    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" >> "$sync_dir/.sync_log"
    echo
    ok "Sync abgeschlossen!"
}

do_sync() {
    hdr "CLOUD / NAS SYNC"
    echo -e "  ${D}Ordnerbasierter Sync – funktioniert mit:${NC}"
    echo -e "  ${D}Nextcloud · Syncthing · NAS-Laufwerk · USB · OneDrive · jeder geteilter Ordner${NC}"

    while true; do
        local sync_path; sync_path=$(sync_get_path)
        echo
        if [[ -z "$sync_path" ]]; then
            echo -e "  ${Y}Kein Sync-Ordner konfiguriert.${NC}"
        elif [[ -d "$sync_path" ]]; then
            ok "Sync-Ordner: $sync_path"
        else
            warn "Sync-Ordner nicht erreichbar: $sync_path"
            echo -e "  ${D}(NAS/Laufwerk eingebunden? Cloud-Sync aktiv?)${NC}"
        fi
        echo
        echo -e "  ${Y}[1]${NC} ${W}Sync jetzt ausführen${NC} (bidirektional)"
        echo -e "  ${Y}[2]${NC} Sync-Ordner konfigurieren"
        echo -e "  ${Y}[3]${NC} Sync-Status anzeigen"
        echo -e "  ${Y}[0]${NC} Zurück"
        echo
        read -r -p "  Wähle: " choice

        case "$choice" in
            0) return ;;
            2)
                echo
                echo -e "  ${W}Sync-Ordner eingeben${NC}"
                echo -e "  ${D}Beispiele:${NC}"
                echo -e "  ${D}  ~/Nextcloud/RF4-Sync${NC}"
                echo -e "  ${D}  /mnt/nas/RF4-Sync${NC}"
                echo -e "  ${D}  /run/media/$USER/USB-Stick/RF4-Sync${NC}"
                echo
                read -r -p "  Pfad: " new_path
                new_path="${new_path/#\~/$HOME}"
                if [[ -n "$new_path" ]]; then
                    if mkdir -p "$new_path" 2>/dev/null; then
                        sync_set_path "$new_path"
                        ok "Gespeichert: $new_path"
                    else
                        err "Ordner konnte nicht erstellt werden: $new_path"
                    fi
                fi
                pause
                ;;
            3)
                sync_path=$(sync_get_path)
                echo
                if [[ -z "$sync_path" ]]; then warn "Kein Sync-Ordner konfiguriert."; pause; continue; fi
                if [[ ! -d "$sync_path" ]]; then err "Nicht erreichbar: $sync_path"; pause; continue; fi
                local sync_dir="$sync_path/RF4_Sync"
                info "Sync-Ordner: $sync_path"
                if [[ -d "$sync_dir" ]]; then
                    local total_mbox=0
                    for mbox in "$sync_dir"/Mailbox_*/; do
                        [[ -d "$mbox" ]] || continue
                        local mname cnt; mname=$(basename "$mbox")
                        cnt=$(ls "$mbox"*.dat 2>/dev/null | wc -l)
                        info "  $mname: $cnt Konversationen"
                        total_mbox=$((total_mbox+1))
                    done
                    [[ $total_mbox -eq 0 ]] && warn "  Noch keine Mailboxen im Sync-Ordner."
                    for dat in Settings.dat Preferences.dat Crafting.dat; do
                        [[ -f "$sync_dir/$dat" ]] && info "  $dat vorhanden"
                    done
                    if [[ -f "$sync_dir/.sync_log" ]]; then
                        echo; info "Letzte Sync-Einträge:"
                        tail -5 "$sync_dir/.sync_log" | while IFS= read -r line; do info "  $line"; done
                    fi
                else
                    warn "Noch kein RF4_Sync-Unterordner. Ersten Sync ausführen, um ihn anzulegen."
                fi
                pause
                ;;
            1)
                sync_path=$(sync_get_path)
                if [[ -z "$sync_path" ]]; then warn "Bitte zuerst Sync-Ordner konfigurieren (Option 2)."; pause; continue; fi
                if [[ ! -d "$sync_path" ]]; then
                    err "Sync-Ordner nicht erreichbar: $sync_path"
                    info "NAS eingebunden? Cloud-Sync aktiv? USB angesteckt?"
                    pause; continue
                fi
                load_installations
                local existing=() existing_paths=() i=0
                for path in "${INST_PATHS[@]}"; do
                    if [[ -d "$path" ]]; then
                        existing+=("${INST_LABELS[$i]}")
                        existing_paths+=("$path")
                    fi
                    i=$((i+1))
                done
                if [[ ${#existing[@]} -eq 0 ]]; then err "Keine RF4-Installationen gefunden."; pause; continue; fi
                local inst_path
                if [[ ${#existing[@]} -eq 1 ]]; then
                    inst_path="${existing_paths[0]}"
                    info "Installation: ${existing[0]}"
                else
                    menu "Welche Installation synchronisieren?" "${existing[@]}" || continue
                    inst_path="${existing_paths[$((MENU_CHOICE-1))]}"
                fi
                do_sync_run "$inst_path" "$sync_path"
                pause
                ;;
        esac
    done
}

# ── Hauptmenü ──────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        clear
        echo -e "${B}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${B}║${W}   RF4 SA  Backup & Migration Tool           ${B}║${NC}"
        echo -e "${B}╚══════════════════════════════════════════════╝${NC}"
        echo -e "  ${D}RF4: nga.li/rf4de | Steam: nga.li/rf4steam | Blog: nga.li/rf4b${NC}"
        echo
        echo -e "  ${Y}[1]${NC} ${W}Scan${NC}     – Alle Installationen anzeigen"
        echo -e "  ${Y}[2]${NC} ${W}Backup${NC}   – Daten sichern"
        echo -e "  ${Y}[3]${NC} ${W}Restore${NC}  – In Installation importieren"
        echo -e "  ${Y}[4]${NC} ${W}Merge${NC}    – Installationen zusammenführen"
        echo -e "  ${Y}[5]${NC} ${W}Sync${NC}     – Mit Cloud/NAS synchronisieren"
        echo -e "  ${Y}[0]${NC} Beenden"
        echo
        read -r -p "  Wähle: " choice
        case "$choice" in
            1) do_scan ;;
            2) do_backup ;;
            3) do_restore ;;
            4) do_merge ;;
            5) do_sync ;;
            0) echo; exit 0 ;;
            *) ;;
        esac
    done
}

# ── Direktaufruf ohne Menü (für Cron/Scripts) ─────────────────────────────────
case "${1:-}" in
    backup)  DEFAULT_BACKUP_DIR="${2:-$DEFAULT_BACKUP_DIR}"; do_backup ;;
    restore) do_restore ;;
    scan)    do_scan ;;
    merge)   do_merge ;;
    sync)    do_sync ;;
    *)       main_menu ;;
esac
