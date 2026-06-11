![Rollup Repo For AI](Rollup-Repo-for-AI.jpg)

# Rollup Repo for AI

Merge your entire codebase into AI-ready text files. Perfect for uploading project context to Claude, ChatGPT, or any LLM.

## Why?

AI assistants work best with full project context, but uploading dozens of files is tedious. This tool:

- Concatenates your repo into chunked `.txt` files sized for AI uploads
- Strips comments, whitespace, and base64 blobs to maximize signal
- Respects `.gitignore` and excludes lock files, `node_modules`, build artifacts
- Optionally generates restore scripts to recreate the file structure
- **Interactive tree selection** for cherry-picking specific files/folders
- **Auto-purges `rolled_repo/`** before every roll — output is always the latest, never stale

## Install to PATH (Recommended)

Copy the script to `~/.local/bin` so you can run it from any directory without a path prefix:

```bash
cp roll_repo ~/.local/bin/roll_repo
chmod +x ~/.local/bin/roll_repo
```

`~/.local/bin` is a standard user-level bin directory that most distros already include in `$PATH`. No `sudo` needed — your tools, your permissions.

Then add a short alias to `~/.zshrc` (or `~/.bashrc`):

```bash
roll() {
  local target_dir="${1:-.}"
  bash ~/.local/bin/roll_repo "$target_dir"
}
```

Reload your shell:

```bash
source ~/.zshrc
```

Now from any repo on your system you just type:

```bash
roll           # rolls current directory
roll ../other  # rolls a different path
```

No `./`, no full paths, no remembering where you cloned it. One word from anywhere.

### Why ~/.local/bin?

| Approach | What you type |
| -------- | ------------- |
| Run from clone dir | `bash /home/you/tools/rollup-repo-for-AI/roll_repo_for_ai.sh` |
| Add to PATH | `roll_repo` |
| With alias | `roll` |

The alias also lets you default the target to `.` so calling it bare always operates on the current repo — no arguments needed for the common case.

## Quick Start

```bash
# Clone
git clone https://github.com/yourusername/rollup-repo-for-ai.git

# Install to PATH
cp rollup-repo-for-ai/roll_repo ~/.local/bin/roll_repo
chmod +x ~/.local/bin/roll_repo

# Add alias to ~/.zshrc
echo 'roll() { bash ~/.local/bin/roll_repo "${1:-.}"; }' >> ~/.zshrc
source ~/.zshrc

# Run from any repo
cd ~/your-project
roll
```

Output lands in `./rolled_repo/`

## Usage

### Node.js Version

```bash
node roll_repo_for_ai.js [repo_path] [max_kb] [--mode text|sh]
```

| Argument    | Default | Description                                     |
| ----------- | ------- | ----------------------------------------------- |
| `repo_path` | `.`     | Path to your git repository                     |
| `max_kb`    | `40`    | Max size per output file (KB)                   |
| `--mode`    | `text`  | `text` for AI context, `sh` for restore scripts |

**Examples:**

```bash
# Roll current repo into 40KB chunks
node roll_repo_for_ai.js

# Roll a different repo with 100KB chunks
node roll_repo_for_ai.js ../my-project 100

# Generate restore scripts instead of text
node roll_repo_for_ai.js . 40 --mode sh
```

### Bash Version

```bash
roll [repo_path]          # via alias (recommended)
roll_repo [repo_path]     # direct after installing to ~/.local/bin
./roll_repo [repo_path]   # or run directly
```

Presents an interactive menu:

```
           🤖 Roll Repo For AI 🤖
==============================================

  1) Roll AI Version (.txt minimal - most common)

  2) Pick files from tree view (interactive select)

  3) Roll Restorable Version (.sh heredoc - large)

  4) Roll AI Version (no git) (.txt minimal - directory scan)

==============================================

Select mode [1, 2, 3, or 4]:
```

> **Note:** Every roll first purges `rolled_repo/` so you always get the latest files — no dated leftovers.

## Output Modes

### 1. Text Mode (default)

Generates `ai_context_1.txt`, `ai_context_2.txt`, etc.

```
===== FILE: src/components/Button.tsx =====
import React from "react"
export function Button({ children }) { return <button>{children}</button> }

===== FILE: src/utils/helpers.ts =====
export const formatDate = (d) => d.toLocaleDateString()
```

**Optimizations applied:**

- Removes single-line comments (`//`, `#`)
- Removes block comments (`/* */`)
- Collapses whitespace
- Strips base64 data URIs (except in CSS)
- Wraps long lines at 200 characters

### 2. Interactive Tree Selection

Cherry-pick exactly which files and folders to include. Perfect for creating smaller, focused context packages.

```
           🤖 Roll Repo For AI 🤖
=============================================
Select files/folders to include:
↑/↓: Navigate | Space: Toggle | a: All | n: None | Enter: Confirm
=============================================

▶ [X]    📁 src
   [X]    📁 app
     [ ]    📁 about
     [X]    📁 admin
       [X]    📄 AdminDashboard.tsx
       [X]    📄 Settings.tsx
   [X]    📁 components
     [X]    📄 Button.tsx
     [ ]    📄 Card.tsx
  [ ]    📁 convex
  [ ]    📁 public

─────────────────────────────────────────────
Selected: 4/12 files  |  Item 1/15
```

**Keyboard Controls:**

| Key     | Action                                         |
| ------- | ---------------------------------------------- |
| `↑`/`↓` | Navigate up/down through the tree              |
| `Space` | Toggle selection (folders select all children) |
| `a`     | Select all files                               |
| `n`     | Deselect all files                             |
| `Enter` | Confirm selection and generate output          |
| `q`     | Quit without generating                        |

**Use cases:**

- Include only `src/` but skip `tests/`
- Grab specific components without the whole app
- Create minimal context for focused AI questions

### 3. Shell Restore Mode

Generates `ai_restore_1.sh`, `ai_restore_2.sh`, etc.

Executable scripts that recreate your file structure:

```bash
#!/bin/bash
mkdir -p "src/components" && cat << 'EOF_A1B2C3' > "src/components/Button.tsx"
import React from "react";
// Full original content preserved
EOF_A1B2C3
```

Run them to restore: `bash ai_restore_1.sh`

## What Gets Excluded

| Pattern                                                                   | Reason                            |
| ------------------------------------------------------------------------- | --------------------------------- |
| `*.lock`, `bun.lockb`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` | Lock files are noise              |
| `.env`, `.env.*`                                                          | Security - never share secrets    |
| `.git/`, `.next/`, `.cache/`                                              | Build/system directories          |
| `node_modules/`, `dist/`, `build/`, `out/`, `coverage/`, `public/`        | Dependencies and outputs          |
| `target/`, `vendor/`, `zig-cache/`, `zig-out/`                            | Go, Rust, Zig build directories   |
| `.exe`, `.dll`, `.so`, `.dylib`, `.a`, `.o`, `.obj`, `.lib`, `.pdb`, `.ilk`, `.exp`, `.wasm`, `.elf` | Compiled binaries and object files |

Only git-tracked files are processed (`git ls-files`).

## Recommended Workflow

1. **Roll your repo:**

   ```bash
   node roll_repo_for_ai.js ./my-project 50
   ```

2. **Upload to your AI assistant:**

   - Drag and drop `ai_context_1.txt` (and subsequent parts) into Claude/ChatGPT
   - Or paste contents directly

3. **Prompt with context:**

   > "I've uploaded my project files. Help me refactor the Button component to use Tailwind."

4. **For selective context**, use tree selection:

   ```bash
   ./roll_repo_for_ai.sh
   # Select option 2, pick only relevant files
   ```

5. **For code generation**, use restore mode:
   ```bash
   node roll_repo_for_ai.js . 40 --mode sh
   ```
   Share the restore script with AI to get back executable file creation commands.

## Requirements

- **Node.js version:** Node 18+ (uses ES modules)
- **Bash version:** Bash 4+, standard Unix tools (`git`, `sed`, `fold`)
- Must be run inside a git repository

## Tips

- **Chunk size:** 40KB works well for most AI interfaces. Increase to 100KB+ if your AI supports larger contexts.
- **Multiple parts:** Upload all parts for full context, or just the relevant ones.
- **Sensitive data:** The tool excludes `.env` files, but review output before sharing.
- **Binary files:** Automatically skipped.
- **Tree selection:** Great for large repos—only include what's relevant to your question.

## License

MIT License - see [LICENSE](LICENSE)

---

Built for developers who talk to AI about code.
