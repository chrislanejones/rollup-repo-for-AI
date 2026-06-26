#!/usr/bin/env bash
# roll_repo_for_ai.sh — The Ultimate AI Context Bundler
set -uo pipefail

export TERM="${TERM:-xterm}"

safe_clear() { clear 2>/dev/null || true; }
safe_tput()   { tput "$@" 2>/dev/null || true; }

REPO_DIR="${1:-.}"
MAX_SIZE_KB="${2:-}"      # empty → prompt interactively; or pass KB as the 2nd arg
MAX_SIZE_BYTES=0          # computed after the chunk size is chosen
OUT_DIR="rolled_repo"
SEARCH_QUERY=""

# Colors and Styling
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'
DIM='\033[2m'; NC='\033[0m'; BOLD='\033[1m'

declare -A SELECTED
declare -a TREE_ITEMS TREE_PATHS TREE_DEPTHS TREE_TYPES
CURSOR=0

# Keep your repo clean by ignoring the output and the script itself
ensure_gitignore_entries() {
    local gitignore=".gitignore"
    [[ -f "$gitignore" ]] || return 0
    local entries=("roll_repo_for_ai.sh" "$OUT_DIR/")
    for entry in "${entries[@]}"; do
        if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
            {
                echo ""
                echo "# Added by roll_repo_for_ai.sh"
                echo "$entry"
            } >> "$gitignore"
        fi
    done
}

cd "$REPO_DIR"
mkdir -p "$OUT_DIR"
ensure_gitignore_entries

get_files() {
    # Respects .gitignore and avoids binary/lockfile bloat
    git ls-files --cached --others --exclude-standard | \
        grep -vE '(\.lock$|bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)' | \
        grep -vE '(^\.env$|\.env\..*)' | \
        grep -vE '(^\.git/|\.next/|\.cache/)' | \
        grep -vE '(node_modules/|dist/|build/|out/|coverage/|public/)' | \
        grep -vE '(^|/)(target|vendor|zig-(cache|out))(/|$)' | \
        grep -viE '\.(exe|dll|so|dylib|a|o|obj|lib|pdb|ilk|exp|wasm|elf|ttf|otf|woff2?|eot|png|jpe?g|gif|bmp|ico|webp|avif|mp4|webm|mov|avi|mp3|wav|ogg|flac|pdf|zip|gz|tar|7z|rar)(\..+)?$' | \
        grep -vE '\.(svelte\.(js|ts|jsx|tsx)|d\.ts)$' | \
        grep -i "$SEARCH_QUERY" | \
        sort
}

build_tree() {
    local files="$1"
    declare -A dirs_added
    TREE_ITEMS=(); TREE_PATHS=(); TREE_DEPTHS=(); TREE_TYPES=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local dir_path=""
        IFS='/' read -ra parts <<< "$file"
        local depth=0
        for ((i=0; i<${#parts[@]}-1; i++)); do
            dir_path="${dir_path:+$dir_path/}${parts[i]}"
            if [[ -z "${dirs_added[$dir_path]:-}" ]]; then
                dirs_added[$dir_path]=1
                TREE_ITEMS+=("${parts[i]}")
                TREE_PATHS+=("$dir_path")
                TREE_DEPTHS+=($depth)
                TREE_TYPES+=("dir")
                [[ -z "${SELECTED[$dir_path]:-}" ]] && SELECTED["$dir_path"]=1
            fi
            ((depth++))
        done
        TREE_ITEMS+=("${parts[-1]}")
        TREE_PATHS+=("$file")
        TREE_DEPTHS+=($depth)
        TREE_TYPES+=("file")
        [[ -z "${SELECTED[$file]:-}" ]] && SELECTED["$file"]=1
    done <<< "$files"
}

toggle_selection() {
    local idx=$1
    local path="${TREE_PATHS[$idx]}"
    local type="${TREE_TYPES[$idx]}"
    local state="${SELECTED[$path]:-0}"
    local new_state=$((1 - state))

    SELECTED["$path"]=$new_state
    if [[ "$type" == "dir" ]]; then
        for ((i=0; i<${#TREE_PATHS[@]}; i++)); do
            [[ "${TREE_PATHS[$i]}" == "$path/"* ]] && \
              SELECTED["${TREE_PATHS[$i]}"]=$new_state
        done
    fi
    # If enabling a file, ensure parents are enabled
    if [[ "$new_state" == "1" ]]; then
        local parent="$path"
        while [[ "$parent" == */* ]]; do
            parent="${parent%/*}"
            SELECTED["$parent"]=1
        done
    fi
}

draw_tree() {
    local term_height=$(tput lines || echo 24)
    local visible_height=$((term_height - 12))
    local total=${#TREE_ITEMS[@]}
    local scroll_offset=0
    ((CURSOR >= visible_height)) && scroll_offset=$((CURSOR - visible_height + 1))

    safe_clear
    echo -e "${BOLD}${CYAN}           🤖 Roll Repo For AI 🤖${NC}"
    echo -e "${DIM}=============================================${NC}"
    [[ -n "$SEARCH_QUERY" ]] && echo -e "${YELLOW}Filter: $SEARCH_QUERY${NC}"
    echo -e "${WHITE}Navigate: ↑/↓ | Space: Toggle | Enter: Confirm${NC}"
    echo -e "${DIM}a: All | n: None | d: Dirs Only | f: Files Only | /: Search${NC}"
    echo -e "${DIM}=============================================${NC}"

    local count=0
    for ((i=scroll_offset; i<total && count<visible_height; i++)); do
        local indent=""
        for ((d=0; d<TREE_DEPTHS[i]; d++)); do indent+="  "; done
        local checkbox="${DIM}[ ]${NC}"; [[ "${SELECTED[${TREE_PATHS[$i]}]:-0}" == "1" ]] && checkbox="${GREEN}[X]${NC}"
        local icon="${BLUE}📄${NC}"; [[ "${TREE_TYPES[$i]}" == "dir" ]] && icon="${YELLOW}📁${NC}"
        local line="  ${checkbox} ${indent}${icon} ${TREE_ITEMS[$i]}"
        ((i == CURSOR)) && echo -ne "${WHITE}▶${NC}" || echo -ne " "
        echo -e "$line"
        ((count++))
    done
}

tree_select() {
    while true; do
        build_tree "$(get_files)"
        ((CURSOR >= ${#TREE_ITEMS[@]})) && CURSOR=0
        draw_tree
        read -rsn1 key
        case "$key" in
            $'\x1b') read -rsn2 -t 0.1 k2; [[ "$k2" == "[A" ]] && ((CURSOR>0)) && ((CURSOR--)); [[ "$k2" == "[B" ]] && ((CURSOR<${#TREE_ITEMS[@]}-1)) && ((CURSOR++)) ;;
            ' ') toggle_selection $CURSOR ;;
            'a') for p in "${TREE_PATHS[@]}"; do SELECTED["$p"]=1; done ;;
            'n') for p in "${TREE_PATHS[@]}"; do SELECTED["$p"]=0; done ;;
            'd') for i in "${!TREE_TYPES[@]}"; do [[ "${TREE_TYPES[$i]}" == "dir" ]] && SELECTED["${TREE_PATHS[$i]}"]=1 || SELECTED["${TREE_PATHS[$i]}"]=0; done ;;
            'f') for i in "${!TREE_TYPES[@]}"; do [[ "${TREE_TYPES[$i]}" == "file" ]] && SELECTED["${TREE_PATHS[$i]}"]=1 || SELECTED["${TREE_PATHS[$i]}"]=0; done ;;
            '/') safe_tput cup $(($(tput lines)-1)) 0; read -p "Search: " SEARCH_QUERY; CURSOR=0 ;;
            ''|$'\n') break ;;
            'q') exit 0 ;;
        esac
    done

    SELECTED_FILES=""
    for ((i=0; i<${#TREE_PATHS[@]}; i++)); do
        [[ "${TREE_TYPES[$i]}" == "file" && "${SELECTED[${TREE_PATHS[$i]}]:-0}" == "1" ]] && SELECTED_FILES+="${TREE_PATHS[$i]}"$'\n'
    done
}

purge_out_dir() {
    # Wipe any output from a previous run so nobody mistakes stale parts
    # (e.g. an old ai_context_5.txt) for current output if they run twice.
    local existing
    existing=$(find "$OUT_DIR" -type f 2>/dev/null | wc -l)
    if (( existing > 0 )); then
        echo -e "${YELLOW}⚠  $OUT_DIR/ has ${existing} file(s) from a previous run — purging so the old roll is gone...${NC}"
        find "$OUT_DIR" -type f -delete 2>/dev/null
        echo -e "${GREEN}✓  $OUT_DIR/ is clean — rolling fresh files now.${NC}\n"
    fi
}

is_binary() {
    local f="$1"
    # grep -I treats files with NUL bytes as non-matching, so any binary,
    # font (.ttf) or image fails this and is flagged regardless of extension.
    # (Empty files also fail here and get skipped, which is harmless.)
    grep -qI . "$f" 2>/dev/null || return 0
    # Backstop: `file --mime-encoding` reports "binary" for fonts/images.
    # The old check grepped `file` for the word "binary", but it calls them
    # "TrueType Font data"/"JPEG image data" — so they leaked in as garbage.
    file --mime-encoding "$f" 2>/dev/null | grep -qi 'binary' && return 0
    return 1
}

clean_file_for_ai() {
    local f="$1"
    local content
    content="$(sed -e 's/\/\/.*$//' -e 's/#.*$//' -e '/\/\*/,/\*\//d' -e 's/[[:space:]]\+/ /g' -e 's/^[ \t]*//' -e 's/[ \t]*$//' "$f" 2>/dev/null | sed '/^$/d')"
    [[ "${f##*.}" != "css" ]] && content="$(echo "$content" | sed 's/data:[a-zA-Z0-9\/+;=,.%-]*base64,[a-zA-Z0-9\/+=]*//g')"
    # Wrap long lines at 200 chars. NOTE: `fold` counts BYTES, so it splits
    # multibyte UTF-8 (box-drawing art, em-dashes, emoji) mid-character and
    # produces invalid bytes — the output then gets rejected by AI uploaders
    # as an "unsupported text file". Use perl with -CSD so length/substr count
    # CHARACTERS, not bytes. Fall back to no-wrap (still valid) if perl is absent.
    if command -v perl >/dev/null 2>&1; then
        echo "$content" | perl -CSD -ne 'chomp; while (length > 200) { print substr($_,0,200), "\n"; $_ = substr($_,200) } print "$_\n"'
    else
        echo "$content"
    fi
}

open_output() {
    if command -v open >/dev/null; then open "$OUT_DIR"; 
    elif command -v xdg-open >/dev/null; then xdg-open "$OUT_DIR"; fi
}

run_text() {
    local files="$1" part=1
    local out="$OUT_DIR/ai_context_${part}.txt"
    purge_out_dir
    echo "" > "$out"
    local total=$(echo "$files" | grep -c . || echo 0)
    local count=0
    while IFS= read -r f; do
        [[ -z "$f" || ! -f "$f" ]] && continue
        # 200KB Guard
        [[ $(stat -c%s "$f" 2>/dev/null || stat -f%z "$f") -gt 200000 ]] && continue
        is_binary "$f" && continue

        ((count++)); printf "\rProcessing %d/%d..." "$count" "$total"
        header="===== FILE: $f ====="
        content="$(clean_file_for_ai "$f")"

        # Start a new chunk once this one would exceed the chosen size
        local current_size
        current_size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)
        if (( current_size + ${#header} > MAX_SIZE_BYTES )); then
            ((part++))
            out="$OUT_DIR/ai_context_${part}.txt"
            echo "" > "$out"
        fi
        echo -e "$header\n$content\n" >> "$out"
    done <<< "$files"

    local final_size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)
    echo -e "\n${GREEN}✓ Created ${part} file(s) in ${OUT_DIR}/ — Approx tokens (last part): $((final_size / 4))${NC}"
    open_output
}

run_sh() {
    local files="$1" part=1
    local out="$OUT_DIR/ai_restore_${part}.sh"
    purge_out_dir
    echo "#!/bin/bash" > "$out"; chmod +x "$out"
    while IFS= read -r f; do
        [[ -z "$f" || ! -f "$f" ]] && continue
        [[ $(stat -c%s "$f" 2>/dev/null || stat -f%z "$f") -gt 200000 ]] && continue
        is_binary "$f" && continue
        d="EOF_$(echo "$f" | md5sum | cut -c1-6)"
        header="mkdir -p \"$(dirname "$f")\" && cat << '$d' > \"$f\""

        # Start a new chunk once this one would exceed the chosen size
        local current_size
        current_size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)
        if (( current_size + ${#header} > MAX_SIZE_BYTES )); then
            ((part++))
            out="$OUT_DIR/ai_restore_${part}.sh"
            echo "#!/bin/bash" > "$out"; chmod +x "$out"
        fi
        echo "$header" >> "$out"
        cat "$f" >> "$out"
        echo "$d" >> "$out"
    done <<< "$files"
    echo -e "\n${GREEN}✓ Created ${part} restore script(s) in ${OUT_DIR}/${NC}"
    open_output
}

select_chunk_size() {
    # Arrow-key picker for the max size of each output file (the "chunk" you
    # paste / upload into a non-terminal AI). ←/→ (or ↑/↓) to move, Enter to pick.
    local sizes_kb=(50 250 1024)
    local sizes_label=("50 KB" "250 KB" "1 MB")
    local sel=1   # default highlight → 250 KB

    safe_tput civis
    trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null' EXIT

    while true; do
        safe_clear
        echo -e "${BOLD}${CYAN}           🤖 Roll Repo For AI 🤖${NC}"
        echo -e "${DIM}=============================================${NC}"
        echo -e "${WHITE}Chunk size${NC} ${DIM}— max size of each output file you paste/upload into the AI${NC}"
        echo -e "${DIM}←/→: Change  |  Enter: Confirm  |  q: Quit${NC}"
        echo -e "${DIM}=============================================${NC}"
        echo ""

        local line="     "
        for ((i=0; i<${#sizes_label[@]}; i++)); do
            if ((i == sel)); then
                line+="${GREEN}${BOLD}▶ ${sizes_label[$i]} ◀${NC}"
            else
                line+="${DIM}  ${sizes_label[$i]}  ${NC}"
            fi
            ((i < ${#sizes_label[@]}-1)) && line+="      "
        done
        echo -e "$line"
        echo ""

        read -rsn1 key
        case "$key" in
            $'\x1b') read -rsn2 -t 0.1 k2
                     case "$k2" in
                         '[C'|'[B') ((sel < ${#sizes_kb[@]}-1)) && ((sel++)) ;;
                         '[D'|'[A') ((sel > 0)) && ((sel--)) ;;
                     esac ;;
            ''|$'\n') break ;;
            'q'|'Q') safe_tput cnorm; echo; echo "Cancelled."; exit 0 ;;
        esac
    done

    safe_tput cnorm
    MAX_SIZE_KB="${sizes_kb[$sel]}"
}

# Entry Point
safe_clear
echo -e "1) Roll AI (.txt)\n2) Interactive Select\n3) Roll Restore (.sh)"
read -p "Selection: " MODE

# Ask for the chunk size before rolling (unless one was passed as the 2nd arg).
if [[ "$MODE" =~ ^[1-3]$ ]]; then
    [[ -z "$MAX_SIZE_KB" ]] && select_chunk_size
    MAX_SIZE_BYTES=$((MAX_SIZE_KB * 1024))
fi

case "$MODE" in
    1) run_text "$(get_files)" ;;
    2) tree_select; [[ -n "$SELECTED_FILES" ]] && run_text "$SELECTED_FILES" ;;
    3) run_sh "$(get_files)" ;;
esac
