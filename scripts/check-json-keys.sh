#!/usr/bin/env bash
#
# Reject duplicate keys in this repository's JSON and JSONC files.
#
# Nothing else catches them. A duplicate key is legal JSON: the last one wins, silently.
# Prettier reformats the file happily, the devcontainer CLI parses it happily, and
# `jq .` prints only the survivor — so the file reads as correct while doing something
# else. `.devcontainer/local/devcontainer.json` shipped a second "initializeCommand"
# that way, which discarded a build-time guard and looked right in every tool above.
#
# JSONC-aware, because devcontainer.json takes comments and the comments here are load
# bearing: `//` inside a string is not a comment, so the scanner tracks string state
# instead of stripping with a regex. Comment bodies are blanked rather than removed so
# reported line numbers still match the file on disk.

set -euo pipefail

# Explicit paths win, so the checker is runnable against a fixture and against one file
# while editing. Without them, git ls-files from the repository root — the set follows the
# repository rather than a hand-maintained list, and node_modules and the gitignored
# working-tree copy are excluded for free.
if [ "$#" -gt 0 ]; then
    files=("$@")
else
    cd "$(dirname "$0")/.."
    mapfile -t files < <(git ls-files '*.json')
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "No JSON files tracked — nothing to check."
    exit 0
fi

node - "${files[@]}" <<'JS'
const fs = require("fs");

// Blank out comment bodies, preserving length and newlines so offsets stay usable.
function blankComments(src) {
    let out = "";
    let i = 0;
    while (i < src.length) {
        const c = src[i];
        if (c === '"') {
            out += c;
            i++;
            while (i < src.length) {
                if (src[i] === "\\") {
                    out += src.slice(i, i + 2);
                    i += 2;
                    continue;
                }
                out += src[i];
                i++;
                if (src[i - 1] === '"') break;
            }
            continue;
        }
        if (c === "/" && (src[i + 1] === "/" || src[i + 1] === "*")) {
            const block = src[i + 1] === "*";
            const end = block ? src.indexOf("*/", i + 2) + 2 || src.length : src.indexOf("\n", i);
            const stop = end === -1 ? src.length : end;
            for (let j = i; j < stop; j++) out += src[j] === "\n" ? "\n" : " ";
            i = stop;
            continue;
        }
        out += c;
        i++;
    }
    return out;
}

function lineOf(src, index) {
    let line = 1;
    for (let i = 0; i < index; i++) if (src[i] === "\n") line++;
    return line;
}

// Walk the blanked text tracking a stack of object/array frames. A string read while the
// innermost frame is an object, and followed by ':', is a key.
function duplicateKeys(src) {
    const dups = [];
    const stack = [];
    let i = 0;
    let pendingKey = null;

    while (i < src.length) {
        const c = src[i];
        if (c === "{" || c === "[") {
            stack.push({ object: c === "{", keys: new Map(), name: pendingKey });
            pendingKey = null;
            i++;
            continue;
        }
        if (c === "}" || c === "]") {
            stack.pop();
            i++;
            continue;
        }
        if (c === '"') {
            const start = i;
            let text = "";
            i++;
            while (i < src.length) {
                if (src[i] === "\\") {
                    text += src.slice(i, i + 2);
                    i += 2;
                    continue;
                }
                if (src[i] === '"') {
                    i++;
                    break;
                }
                text += src[i];
                i++;
            }
            let j = i;
            while (j < src.length && /\s/.test(src[j])) j++;
            const frame = stack[stack.length - 1];
            if (src[j] === ":" && frame && frame.object) {
                const path = stack
                    .map((f) => f.name)
                    .filter(Boolean)
                    .concat(text)
                    .join(".");
                if (frame.keys.has(text)) {
                    dups.push({ key: text, path, first: frame.keys.get(text), second: lineOf(src, start) });
                } else {
                    frame.keys.set(text, lineOf(src, start));
                }
                pendingKey = text;
            }
            continue;
        }
        i++;
    }
    return dups;
}

let failed = false;
for (const file of process.argv.slice(2)) {
    const raw = fs.readFileSync(file, "utf8");
    const dups = duplicateKeys(blankComments(raw));
    for (const d of dups) {
        failed = true;
        console.error(`${file}:${d.second}: duplicate key "${d.key}" (first set at line ${d.first})`);
        console.error(`    path: ${d.path} — the later value silently wins`);
    }
}

if (failed) {
    console.error("\nDuplicate JSON keys found. Merge them into one key.");
    process.exit(1);
}
console.log(`No duplicate JSON keys in ${process.argv.length - 2} files.`);
JS
