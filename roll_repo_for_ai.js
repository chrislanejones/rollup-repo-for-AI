#!/usr/bin/env node
// roll_repo_for_ai.js - Node.js version of "roll repo for AI"
import fs from "fs";
import path from "path";
import os from "os";
import readline from "readline";
import { execSync } from "child_process";

const repoDir = process.argv[2] || ".";
const sizeArg = parseInt(process.argv[3], 10);   // KB; NaN if not passed
const sizeArgGiven = !Number.isNaN(sizeArg);
let maxKB = sizeArgGiven ? sizeArg : 250;        // default; may be set by the picker
let maxBytes = maxKB * 1024;
const outDir = path.join(repoDir, "rolled_repo");
fs.mkdirSync(outDir, { recursive: true });

const files = execSync(`git ls-files --cached --others --exclude-standard`, {
  cwd: repoDir,
})
  .toString()
  .split("\n")
  .filter(
    (f) =>
      f &&
      !f.match(
        /(\.lock$|bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)/
      ) &&
      !f.match(/(^\.env$|\.env\..*)/) &&
      !f.match(/(^\.git\/|\.next\/|\.cache\/)/) &&
      !f.match(/(node_modules\/|dist\/|build\/|out\/|coverage\/|public\/)/) &&
      !f.match(/(^|\/)(target|vendor|zig-(cache|out))(\/|$)/) &&
      !f.match(/\.(exe|dll|so|dylib|a|o|obj|lib|pdb|ilk|exp|wasm|elf)(\..+)?$/i) &&
      !f.match(/\.(ttf|otf|woff2?|eot)$/i) &&
      !f.match(/\.(mp4|webm|mov|avi|mp3|wav|ogg|flac|pdf|zip|gz|tar|7z|rar)$/i) &&
      !f.match(/\.(svelte\.(js|ts|jsx|tsx)|d\.ts|test)$/) &&
      !f.match(/\.(png|jpe?g|gif|bmp|webp|ico|tiff?|raw|cr2|nef|arw|psd|heic|avif)$/i)
  );

const isImage = (file) =>
  /\.(png|jpe?g|gif|bmp|webp|ico|tiff?|raw|cr2|nef|arw|psd|heic|avif)$/i.test(file);

// Content-based binary check: any file containing a NUL byte is binary,
// regardless of extension. Catches fonts/images/binaries that slip past
// the extension filters above (and unknown extensions entirely).
const isBinary = (filePath) => {
  try {
    const buf = fs.readFileSync(filePath);
    const n = Math.min(buf.length, 8192);
    for (let i = 0; i < n; i++) if (buf[i] === 0) return true;
    return false;
  } catch {
    return true; // unreadable → treat as binary and skip
  }
};

function cleanForAI(filePath) {
  let content = fs.readFileSync(filePath, "utf8");
  // strip common comment forms
  content = content
    .replace(/\/\/.*$/gm, "")
    .replace(/#.*$/gm, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/^\s+|\s+$/gm, "")
    .replace(/\n{2,}/g, "\n");

  const ext = path.extname(filePath).toLowerCase();
  if (ext !== ".css" && ext !== ".scss") {
    content = content.replace(/data:[^ ]*base64,[a-zA-Z0-9/+=]+/g, "");
  }

  return content;
}

// Wipe output from a previous run so nobody mistakes stale parts
// (e.g. an old ai_context_5.txt) for current output if they run twice.
const purgeOutDir = () => {
  let existing = [];
  try {
    existing = fs.readdirSync(outDir);
  } catch {}
  if (existing.length) {
    console.log(
      `⚠  ${outDir}/ has ${existing.length} file(s) from a previous run — purging so the old roll is gone...`
    );
    for (const name of existing) {
      try {
        fs.rmSync(path.join(outDir, name), { recursive: true, force: true });
      } catch {}
    }
    console.log(`✓  ${outDir}/ is clean — rolling fresh files now.\n`);
  }
};

const runText = () => {
  purgeOutDir();
  let part = 1;
  let outPath = path.join(outDir, `ai_context_${part}.txt`);
  fs.writeFileSync(outPath, `AI CONTEXT PART ${part}\n`);

  for (const f of files) {
    const full = path.join(repoDir, f);
    if (!fs.existsSync(full) || fs.statSync(full).isDirectory()) continue;
    if (isImage(f) || isBinary(full)) continue;

    const content = cleanForAI(full);
    const header = `===== FILE: ${f} =====\n`;
    const curSize = fs.statSync(outPath).size;
    if (curSize + Buffer.byteLength(header) > maxBytes) {
      part++;
      outPath = path.join(outDir, `ai_context_${part}.txt`);
      fs.writeFileSync(outPath, `AI CONTEXT PART ${part}\n`);
    }
    fs.appendFileSync(outPath, header + content + "\n\n");
    process.stdout.write(`\rProcessed ${f}`);
  }
};

const runRestore = () => {
  purgeOutDir();
  let part = 1;
  let outPath = path.join(outDir, `ai_restore_${part}.sh`);

  const init = () => {
    fs.writeFileSync(
      outPath,
      "#!/bin/bash\n# RESTORE SCRIPT PART " + part + "\n\n"
    );
    fs.chmodSync(outPath, 0o755);
  };
  init();

  for (const f of files) {
    const full = path.join(repoDir, f);
    if (!fs.existsSync(full) || fs.statSync(full).isDirectory()) continue;
    if (isImage(f) || isBinary(full)) continue;

    const header = `mkdir -p "${path.dirname(f)}" && cat << 'EOF' > "${f}"\n`;
    const curSize = fs.statSync(outPath).size;
    if (curSize + Buffer.byteLength(header) > maxBytes) {
      part++;
      outPath = path.join(outDir, `ai_restore_${part}.sh`);
      init();
    }
    fs.appendFileSync(outPath, header);
    fs.appendFileSync(outPath, fs.readFileSync(full, "utf8") + "\nEOF\n\n");
    process.stdout.write(`\rProcessed ${f}`);
  }
};

// Arrow-key picker (←/→ or ↑/↓, Enter to confirm). Only usable on a real
// terminal; when stdin is piped it resolves to the default option instead.
const pickOption = (title, subtitle, options, defaultIdx = 0) =>
  new Promise((resolve) => {
    if (!process.stdin.isTTY) {
      resolve(options[defaultIdx].value);
      return;
    }
    let sel = defaultIdx;
    readline.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();

    const render = () => {
      console.clear();
      console.log("==============================================");
      console.log("          🤖 Roll Repo For AI (Node) 🤖");
      console.log("==============================================");
      console.log(title);
      if (subtitle) console.log(subtitle);
      console.log("←/→: Change  |  Enter: Confirm  |  q: Quit\n");
      const line = options
        .map((o, i) => (i === sel ? `▶ ${o.label} ◀` : `  ${o.label}  `))
        .join("      ");
      console.log("     " + line + "\n");
    };
    render();

    const cleanup = () => {
      process.stdin.removeListener("keypress", onKey);
      process.stdin.setRawMode(false);
      process.stdin.pause();
    };
    const onKey = (_str, key) => {
      if (!key) return;
      if (key.name === "right" || key.name === "down") {
        if (sel < options.length - 1) sel++;
        render();
      } else if (key.name === "left" || key.name === "up") {
        if (sel > 0) sel--;
        render();
      } else if (key.name === "return") {
        cleanup();
        resolve(options[sel].value);
      } else if (key.name === "q" || (key.ctrl && key.name === "c")) {
        cleanup();
        console.log("\nCancelled.");
        process.exit(0);
      }
    };
    process.stdin.on("keypress", onKey);
  });

// Mode can be passed non-interactively via --mode text|sh (matches the
// documented CLI). If omitted, fall back to the interactive prompt.
const modeFlagIdx = process.argv.indexOf("--mode");
const modeArg = modeFlagIdx !== -1 ? process.argv[modeFlagIdx + 1] : null;

async function main() {
  let mode;
  if (modeArg) {
    mode = /^(sh|restore|2)$/i.test(modeArg) ? "2" : "1";
  } else if (process.stdin.isTTY) {
    mode = await pickOption(
      "Mode",
      null,
      [
        { label: "AI text (.txt)", value: "1" },
        { label: "Restore (.sh)", value: "2" },
      ],
      0
    );
  } else {
    // Back-compat: read a piped "1"/"2" selection.
    const input = fs.readFileSync(0, "utf8").trim();
    mode = input.endsWith("2") ? "2" : "1";
  }

  // Chunk size: an explicit 2nd arg wins; otherwise prompt (or default 250).
  if (!sizeArgGiven) {
    maxKB = await pickOption(
      "Chunk size — max size of each output file you paste/upload into the AI",
      null,
      [
        { label: "50 KB", value: 50 },
        { label: "250 KB", value: 250 },
        { label: "1 MB", value: 1024 },
      ],
      1
    );
    maxBytes = maxKB * 1024;
  }

  if (mode === "1") runText();
  else runRestore();

  console.log(`\nDone! Output saved in ${outDir}\n`);
}

main();
