![Rollup Repo For AI](Rollup-Repo-for-AI.jpg)

# Rollup Repo for AI

A bash tool that rolls up your entire repository into AI-friendly chunks, perfect for feeding codebases into LLMs like ChatGPT, Claude, or other AI assistants.

## Features

- **Two Output Modes:**

  - **Text Mode (.txt)** - Optimized for copy-pasting into LLM chat interfaces
  - **Executable Mode (.sh)** - Creates scripts that can recreate your codebase when run

- **Smart File Handling:**

  - Automatically strips comments to reduce token usage
  - Skips binary files and lockfiles
  - Excludes common build directories (node_modules, dist, .next, etc.)
  - Uses git to find tracked files

- **Chunking Support:**
  - Splits output into configurable chunk sizes (default 40KB)
  - Seamlessly continues files across chunks
  - Includes project tree structure in output

## Usage

```bash
./roll_repo_for_ai.sh [repo_path] [chunk_size_kb]
```

### Arguments

| Argument        | Default                 | Description                         |
| --------------- | ----------------------- | ----------------------------------- |
| `repo_path`     | `.` (current directory) | Path to the git repository          |
| `chunk_size_kb` | `40`                    | Maximum size per output chunk in KB |

### Examples

```bash
# Roll current directory with defaults
./roll_repo_for_ai.sh

# Roll a specific repo
./roll_repo_for_ai.sh /path/to/my/project

# Roll with 100KB chunks
./roll_repo_for_ai.sh . 100
```

## Output Modes

### Mode 1: Text Mode (.txt)

Best for manually pasting into AI chat interfaces.

- Clear file headers and footers
- Comments stripped from code
- Whitespace optimized to save tokens
- Output: `rolled_repo/ai_context_text_N.txt`

### Mode 2: Executable Mode (.sh)

Creates shell scripts using heredoc syntax that can recreate your files.

- AI can read and understand the code
- Run the script to restore/unroll all files
- Output: `rolled_repo/ai_restore_script_N.sh`

To restore files from executable mode:

```bash
./rolled_repo/ai_restore_script_1.sh
```

## Requirements

- Bash
- Git (repository must be a git repo)
- Standard Unix utilities (stat, file, grep, etc.)
- Optional: `tree` command for better project structure display

## How It Works

1. Scans git-tracked files in the repository
2. Filters out lockfiles, binaries, and build artifacts
3. Strips comments based on file type
4. Chunks content into manageable pieces
5. Outputs files ready for AI consumption

## License

MIT
