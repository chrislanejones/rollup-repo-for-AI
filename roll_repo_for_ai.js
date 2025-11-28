#!/usr/bin/env node
// roll_repo_for_ai.js — SAFE CLEAN + selective dotfile exclusion + base64 stripping (non-CSS)

import fs from "fs";
import path from "path";
import { execSync } from "child_process";

const repo = process.argv[2] || ".";
const maxKB = parseInt(process.argv[3] || "40");
const maxBytes = maxKB * 1024;

const mode = process.argv.includes("--mode")
  ? process.argv[process.argv.indexOf("--mode") + 1]
  : "text";

const outDir = "rolled_repo";
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);

const files = execSync("git ls-files", { cwd: repo })
  .toString()
  .split("\n")
  .filter(Boolean)
  .filter(f => !/\.lock$|bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml/.test(f))
  .filter(f => !/^\.env$/.test(f) && !/^\.env\..*/.test(f))
  .filter(f => !/^\.git\//.test(f))
  .filter(f => !/^\.next\//.test(f))
  .filter(f => !/^\.cache\//.test(f))
  .filter(f => !/(node_modules\/|dist\/|build\/|out\/|coverage\/|public\/)/.test(f));

const total = files.length;
let count = 0;

function progress(file) {
  count++;
  const pct = Math.floor((count / total) * 100);
  process.stdout.write(`Processing: ${file} [${pct}%]\r`);
}

function cleanForAI(file, content) {
  const ext = file.split(".").pop();

  let cleaned = content
    .replace(/\/\/.*$/gm, "")
    .replace(/#.*$/gm, "")
    .replace(/\/\*[\s\S]*?\*\//gm, "")
    .replace(/[ \t]+/g, " ")
    .split("\n")
    .map(l => l.trim())
    .filter(Boolean)
    .join("\n");

  if (ext !== "css") {
    cleaned = cleaned.replace(/data:[a-zA-Z0-9\/+;=,.%-]*base64,[a-zA-Z0-9\/+=]*/g, "");
  }

  return cleaned
    .split("\n")
    .map(l => l.match(/.{1,200}/g) || [])
    .flat()
    .join("\n");
}

let textPart = 1;
let textBuf = "";

function flushText() {
  fs.writeFileSync(`${outDir}/ai_context_${textPart}.txt`, textBuf);
  textPart++;
  textBuf = "";
}

let shPart = 1;
let shBuf = "";

function initSh() {
  shBuf += `#!/bin/bash\n# RESTORE SCRIPT PART ${shPart}\n\n`;
}

initSh();

function flushSh() {
  fs.writeFileSync(`${outDir}/ai_restore_${shPart}.sh`, shBuf);
  shPart++;
  shBuf = "";
  initSh();
}

for (const file of files) {
  progress(file);

  const full = path.join(repo, file);
  if (!fs.existsSync(full)) continue;

  const raw = fs.readFileSync(full, "utf8");

  if (mode === "text") {
    const cleaned = cleanForAI(file, raw);
    const header = `===== FILE: ${file} =====\n`;

    if (
      Buffer.byteLength(textBuf) +
      Buffer.byteLength(header) +
      Buffer.byteLength(cleaned) >
      maxBytes
    ) {
      flushText();
    }

    textBuf += header + cleaned + "\n\n";
    continue;
  }

  const delimiter =
    "EOF_" + Buffer.from(file).toString("hex").slice(0, 6).toUpperCase();

  const header = `mkdir -p "${path.dirname(
    file
  )}" && cat << '${delimiter}' > "${file}"`;

  if (Buffer.byteLength(shBuf) + Buffer.byteLength(header) > maxBytes) {
    flushSh();
  }

  shBuf += header + "\n" + raw + "\n" + delimiter + "\n\n";
}

mode === "text" ? flushText() : flushSh();

console.log(`\nDone. Files written to ${outDir}/`);
