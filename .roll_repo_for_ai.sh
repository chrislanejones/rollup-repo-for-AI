#!/usr/bin/env bash
# roll_repo.sh
# Dual-mode repository roller for AI contexts.

set -euo pipefail

# --- Configuration ---
REPO_DIR="${1:-.}"
MAX_SIZE_KB="${2:-40}"  # default 40 KB
MAX_SIZE_BYTES=$((MAX_SIZE_KB * 1024))
OUT_DIR="rolled_repo"
mkdir -p "$OUT_DIR"

# --- User Input ---
echo "=============================================="
echo "      🤖 AI Repository Roller Tool 🤖"
echo "=============================================="
echo "Target: $REPO_DIR"
echo "Chunk Size: ${MAX_SIZE_KB}KB"
echo ""
echo "Select Mode:"
echo "1) Text Mode (.txt)"
echo "   - Best for copy-pasting into LLMs."
echo "   - Clear headers, comments stripped, whitespace optimized."
echo "   - Not directly executable."
echo ""
echo "2) Executable Mode (.sh)"
echo "   - Uses 'cat << EOF' syntax."
echo "   - AI can read it easily."
echo "   - You can execute the output file to Restore/Unroll the files."
echo ""
read -p "Enter choice [1 or 2]: " MODE

if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then
    echo "Invalid choice. Exiting."
    exit 1
fi

cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $REPO_DIR is not a git repository."
  exit 1
fi

# --- File Gathering ---
echo "→ Finding files..."
# Exclude lockfiles, node_modules, build folders, but keep package.json
FILES=$(git ls-files --cached --others --exclude-standard | \
  grep -vE '(\.lock$|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb)' | \
  grep -vE '(node_modules/|\.next/|dist/|build/|out/|\_generated/|coverage/|public/|\.git/)' || true)

if [[ -z "$FILES" ]]; then
  echo "No files found to include."
  exit 0
fi

# --- Helper Functions ---

get_size() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1"
}

get_clean_cmd() {
  local f="$1"
  # Define cleanup command based on file type
  case "$f" in
    *.py|*.sh|*.zsh|*.bash|*.rb|*.pl|*.yaml|*.yml|*.dockerfile) 
      echo "grep -vE '^\s*#' '$f'" ;;
    *.js|*.ts|*.jsx|*.tsx|*.java|*.c|*.cpp|*.h|*.css|*.scss|*.go|*.rs|*.php) 
      echo "grep -vE '^\s*(//|/\*|\*|\*/)' '$f'" ;;
    *) 
      echo "cat '$f'" ;;
  esac
}

generate_tree() {
  echo "# Project Structure:"
  if command -v tree &> /dev/null; then
    tree -L 3 -I 'node_modules|.git|.next|dist|build|coverage|public' --noreport
  else
    find . -maxdepth 3 -not -path '*/.*' | sed 's|/[^/]*|  |g'
  fi
}

# --- MODE 1: TEXT MODE (.txt) ---
run_text_mode() {
  echo "→ Running Text Mode..."
  OUT_BASENAME="ai_context_text"
  PART_NUM=1
  OUT_FILE="${OUT_DIR}/${OUT_BASENAME}_${PART_NUM}.txt"

  # Init File 1
  {
    echo "AI REPO CONTEXT: Part $PART_NUM"
    echo "Repo: $REPO_DIR"
    echo ""
    generate_tree
    echo ""
  } > "$OUT_FILE"
  CUR_SIZE=$(get_size "$OUT_FILE")

  for f in $FILES; do
    [[ -f "$f" ]] || continue
    if file "$f" | grep -qi 'binary'; then continue; fi

    echo "  Processing: $f"
    CLEAN_CMD=$(get_clean_cmd "$f")

    HEADER="===== FILE START: $f ====="
    
    # Check if header fits
    if (( CUR_SIZE + ${#HEADER} + 100 > MAX_SIZE_BYTES )); then
        PART_NUM=$((PART_NUM + 1))
        OUT_FILE="${OUT_DIR}/${OUT_BASENAME}_${PART_NUM}.txt"
        echo "AI REPO CONTEXT: Part $PART_NUM" > "$OUT_FILE"
        CUR_SIZE=$(get_size "$OUT_FILE")
    fi
    echo "$HEADER" >> "$OUT_FILE"

    # Stream content with whitespace trimming (tr -s ' ') to save tokens
    eval "$CLEAN_CMD" | head -n 3000 | while IFS= read -r line; do
        # Trim multiple spaces to one, useful for AI token saving
        clean_line=$(echo "$line" | tr -s ' ')
        line_len=${#clean_line}

        if (( CUR_SIZE + line_len + 1 > MAX_SIZE_BYTES )); then
             echo "    -> Splitting $f into Part $((PART_NUM + 1))"
             echo "[File continues in next part...]" >> "$OUT_FILE"
             PART_NUM=$((PART_NUM + 1))
             OUT_FILE="${OUT_DIR}/${OUT_BASENAME}_${PART_NUM}.txt"
             echo "AI REPO CONTEXT: Part $PART_NUM" > "$OUT_FILE"
             echo "[Continuing file: $f]" >> "$OUT_FILE"
             CUR_SIZE=$(get_size "$OUT_FILE")
        fi
        echo "$clean_line" >> "$OUT_FILE"
        CUR_SIZE=$(get_size "$OUT_FILE")
    done

    echo "===== FILE END: $f =====" >> "$OUT_FILE"
    echo "" >> "$OUT_FILE"
  done
}

# --- MODE 2: EXECUTABLE MODE (.sh) ---
run_exec_mode() {
  echo "→ Running Executable Mode..."
  OUT_BASENAME="ai_restore_script"
  PART_NUM=1
  OUT_FILE="${OUT_DIR}/${OUT_BASENAME}_${PART_NUM}.sh"

  init_sh_file() {
    local fname="$1"
    {
        echo "#!/bin/bash"
        echo "# REPO RESTORE SCRIPT - PART $PART_NUM"
        echo "# Run this file to recreate the codebase."
        echo ""
        if [ "$PART_NUM" -eq 1 ]; then
            echo "# File Tree Reference:"
            generate_tree | sed 's/^/# /'
            echo ""
        fi
    } > "$fname"
    chmod +x "$fname"
  }

  init_sh_file "$OUT_FILE"
  CUR_SIZE=$(get_size "$OUT_FILE")

  for f in $FILES; do
    [[ -f "$f" ]] || continue
    if file "$f" | grep -qi 'binary'; then continue; fi
    
    echo "  Processing: $f"
    CLEAN_CMD=$(get_clean_cmd "$f")
    
    # Generate unique EOF marker
    DELIMITER="EOF_$(echo "$f" | md5sum | cut -c1-6 | tr '[:lower:]' '[:upper:]')"
    
    # Header command
    HEADER_CMD="mkdir -p \"\$(dirname \"$f\")\" && cat << '$DELIMITER' > \"$f\""
    
    # Check size for header
    if (( CUR_SIZE + ${#HEADER_CMD} + 100 > MAX_SIZE_BYTES )); then
        PART_NUM=$((PART_NUM + 1))
        OUT_FILE="${OUT_DIR}/${OUT_BASENAME}_${PART_NUM}.sh"
        init_sh_file "$OUT_FILE"
        CUR_SIZE=$(get_size "$OUT_FILE")
    fi

    echo "$HEADER_CMD" >> "$OUT_FILE"

    eval "$CLEAN_CMD" | head -n 3000 | while IFS= read -r line; do
        line_len=${#line}
        
        # Check size (reserve space for delimiter closure)
        if (( CUR_SIZE + line_len + 50 > MAX_SIZE_BYTES )); then
             echo "    -> Splitting $f into Part $((PART_NUM + 1))"
             # Close current heredoc
             echo "$DELIMITER" >> "$OUT_FILE"
             
             PART_NUM=$((PART_NUM + 1))
             OUT_FILE="${OUT_DIR}/${OUT_BASENAME}_${PART_NUM}.sh"
             init_sh_file "$OUT_FILE"
             
             # Re-open in append mode
             echo "cat << '$DELIMITER' >> \"$f\"" >> "$OUT_FILE"
             CUR_SIZE=$(get_size "$OUT_FILE")
        fi
        echo "$line" >> "$OUT_FILE"
        CUR_SIZE=$(get_size "$OUT_FILE")
    done

    echo "$DELIMITER" >> "$OUT_FILE"
    echo "" >> "$OUT_FILE"
    CUR_SIZE=$(get_size "$OUT_FILE")
  done
}

# --- Main Execution ---

if [ "$MODE" == "1" ]; then
    run_text_mode
else
    run_exec_mode
fi

echo ""
echo "✅ Finished!"
echo "Files located in: $OUT_DIR"
ls -lh "$OUT_DIR"
