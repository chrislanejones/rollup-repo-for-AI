#!/usr/bin/env node
// roll_repo_for_ai.js - Node.js version of "roll repo for AI"
import fs from "fs";
import path from "path";
import os from "os";
import { execSync } from "child_process";

const repoDir = process.argv[2] || ".";
const maxKB = parseInt(process.argv[3] || "40", 10);
const maxBytes = maxKB * 1024;
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
      !f.match(/\.(exe|dll|so|dylib|a|o|obj|lib|pdb|ilk|exp|wasm|elf)(\..+)?$/) &&
      !f.match(/\.(svelte\.(js|ts|jsx|tsx)|d\.ts|test)$/) &&
      !f.match(/\.(png|jpe?g|gif|bmp|webp|ico|tiff?|raw|cr2|nef|arw|psd|heic|avif)$/i)
  );

const isImage = (file) =>
  /\.(png|jpe?g|gif|bmp|webp|ico|tiff?|raw|cr2|nef|arw|psd|heic|avif)$/i.test(file);

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

const runText = () => {
  let part = 1;
  let outPath = path.join(outDir, `ai_context_${part}.txt`);
  fs.writeFileSync(outPath, `AI CONTEXT PART ${part}\n`);

  for (const f of files) {
    const full = path.join(repoDir, f);
    if (!fs.existsSync(full) || fs.statSync(full).isDirectory()) continue;
    if (isImage(f)) continue;

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
    if (isImage(f)) continue;

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

console.clear();
console.log("==============================================");
console.log("          🤖 Roll Repo For AI (Node) 🤖");
console.log("==============================================");
console.log("1) Roll AI Version (.txt minimal - most common use case)");
console.log("2) Roll Restorable Version (.sh full heredoc)");
const input = fs.readFileSync(0, "utf8").trim();
const mode = input.endsWith("2") ? "2" : "1";
if (mode === "1") runText();
else runRestore();

console.log(`\nDone! Output saved in ${outDir}\n`);
