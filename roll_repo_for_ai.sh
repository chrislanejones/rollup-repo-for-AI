#!/usr/bin/env bash
# roll_repo_for_ai.sh — SAFE CLEAN + selective dotfile exclusion + base64 stripping (non-CSS)
set -euo pipefail

REPO_DIR="${1:-.}"
MAX_SIZE_KB="${2:-40}"
MAX_SIZE_BYTES=$((MAX_SIZE_KB * 1024))
OUT_DIR="rolled_repo"
mkdir -p "$OUT_DIR"

cd "$REPO_DIR"

clear
echo "1) AI Clean (.txt)"
echo "2) SH Restore (.sh)"
read -p "Select mode [1 or 2]: " MODE

[[ "$MODE" == "1" || "$MODE" == "2" ]] || { echo "Invalid"; exit 1; }

FILES=$(git ls-files --cached --others --exclude-standard | \
  grep -vE '(\.lock$|bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)' | \
  grep -vE '(^\.env$|\.env\..*)' | \
  grep -vE '(^\.git/|\.next/|\.cache/)' | \
  grep -vE '(node_modules/|dist/|build/|out/|coverage/|public/)')

TOTAL=$(echo "$FILES" | wc -l)
COUNT=0

progress() {
  COUNT=$((COUNT+1))
  PCT=$((COUNT * 100 / TOTAL))
  printf "\rProcessing %-40s [%3d%%]" "$1" "$PCT"
}

clean_file_for_ai() {
  local f="$1"
  local ext="${f##*.}"

  content="$(sed \
    -e 's/\/\/.*$//' \
    -e 's/#.*$//' \
    -e '/\/\*/,/\*\//d' \
    -e 's/[[:space:]]\+/ /g' \
    -e 's/^[ \t]*//' \
    -e 's/[ \t]*$//' "$f" | sed '/^$/d')"

  if [[ "$ext" != "css" ]]; then
    content="$(echo "$content" | sed 's/data:[a-zA-Z0-9\/+;=,.%-]*base64,[a-zA-Z0-9\/+=]*//g')"
  fi

  echo "$content" | fold -s -w 200
}

run_text() {
  local part=1
  local out="$OUT_DIR/ai_context_${part}.txt"
  echo "AI CONTEXT PART $part" > "$out"

  for f in $FILES; do
    progress "$f"
    [[ -f "$f" ]] || continue
    file "$f" | grep -qi binary && continue

    header="===== FILE: $f ====="
    content="$(clean_file_for_ai "$f")"

    if (( $(stat -c%s "$out") + ${#header} > MAX_SIZE_BYTES )); then
      part=$((part+1))
      out="$OUT_DIR/ai_context_${part}.txt"
      echo "AI CONTEXT PART $part" > "$out"
    fi

    echo "$header" >> "$out"
    echo "$content" >> "$out"
    echo "" >> "$out"
  done
}

run_sh() {
  local part=1
  local out="$OUT_DIR/ai_restore_${part}.sh"

  init() {
    echo "#!/bin/bash" > "$out"
    echo "# RESTORE SCRIPT PART $part" >> "$out"
    echo "" >> "$out"
    chmod +x "$out"
  }

  init

  for f in $FILES; do
    progress "$f"
    [[ -f "$f" ]] || continue
    file "$f" | grep -qi binary && continue

    d="EOF_$(echo "$f" | md5sum | cut -c1-6)"
    header="mkdir -p \"$(dirname "$f")\" && cat << '$d' > \"$f\""

    if (( $(stat -c%s "$out") + ${#header} > MAX_SIZE_BYTES )); then
      part=$((part+1))
      out="$OUT_DIR/ai_restore_${part}.sh"
      init
    fi

    echo "$header" >> "$out"
    cat "$f" >> "$out"
    echo "$d" >> "$out"
    echo "" >> "$out"
  done
}

[[ "$MODE" == "1" ]] && run_text
[[ "$MODE" == "2" ]] && run_sh
printf "\nDone!\n"
