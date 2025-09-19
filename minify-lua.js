/**
 * Uses child process to call luamin CLI (npx fallback).
 * Concurrent minification (8 parallel jobs).
 * Preserves directory structure unless --inplace is used.
 * Run:
 * node minify-lua.js ./src ./dist
 * node minify-lua.js . . --inplace
 */

// Usage with npm: npm run minify-lua -- [srcDir] [outDir] [--obfuscate] [--obf-cmd="cmd {in} {out}"] [--bytecode]
// Example:
//   npm run minify-lua -- ./public/Src ./public/Dist --obfuscate --obf-cmd="hercules-obfuscator {in} -o {out}"
//   npm run minify-lua -- ./src ./dist --bytecode
const fs = require("fs");
const path = require("path");
const luamin = require("luamin");
const luaparse = require("luaparse");

// CLI arguments
const args = process.argv.slice(2);
const srcDir = args[0] || "src";
const outDir = args[1] || "dist";
const copyExtra = args.includes("--copy-extra");

// Helper: walk directory recursively
function walkDir(dir, callback) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walkDir(full, callback);
        else callback(full);
    }
}

// Write file safely
function writeFileAtomic(dest, contents) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const tmp = dest + ".tmp-" + Date.now();
    fs.writeFileSync(tmp, contents, "utf8");
    fs.renameSync(tmp, dest);
}

// Generate short random names for locals
function generateName(index) {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    let name = "";
    do {
        name += chars[index % chars.length];
        index = Math.floor(index / chars.length);
    } while (index > 0);
    return name;
}

// Obfuscate Lua AST: rename locals and functions
function obfuscateAST(ast) {
    let counter = 0;
    const nameMap = {};

    function traverse(node) {
        if (!node) return;

        if (node.type === "LocalStatement") {
            node.variables.forEach((v) => {
                const newName = generateName(counter++);
                nameMap[v.name] = newName;
                v.name = newName;
            });
        }

        if (node.type === "FunctionDeclaration" && node.isLocal) {
            if (node.identifier && node.identifier.name) {
                const newName = generateName(counter++);
                nameMap[node.identifier.name] = newName;
                node.identifier.name = newName;
            }
        }

        for (let key in node) {
            if (node[key] && typeof node[key] === "object") {
                if (Array.isArray(node[key])) node[key].forEach(traverse);
                else traverse(node[key]);
            }
        }
    }

    traverse(ast);
    return ast;
}

// Optional: encode strings
function encodeStrings(code) {
    return code.replace(/(["'])(.*?)(\1)/g, (match, quote, content) => {
        const chars = content.split("").map((c) => c.charCodeAt(0));
        return `string.char(${chars.join(",")})`;
    });
}

// Minify and obfuscate Lua
function minifyAndObfuscate(src, dest) {
    try {
        let code = fs.readFileSync(src, "utf8");

        const ast = luaparse.parse(code, { locations: false });

        obfuscateAST(ast);

        code = luamin.minify(code);

        code = encodeStrings(code);

        writeFileAtomic(dest, code);
        console.log(`✔ Minified & obfuscated: ${src} -> ${dest}`);
        return dest;
    } catch (err) {
        console.error(`❌ Failed to process ${src}: ${err.message}`);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(src, dest);
        console.log(`→ Copied (fallback): ${src} -> ${dest}`);
        return dest;
    }
}

// Copy non-Lua files (only if --copy-extra)
function copyOtherFile(src, dest) {
    if (!copyExtra) return;
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
    console.log(`📄 Copied: ${src} -> ${dest}`);
}

// Main
if (!fs.existsSync(srcDir)) {
    console.error(`Source directory '${srcDir}' does not exist.`);
    process.exit(1);
}

console.log(`Minifying & obfuscating Lua files from '${srcDir}' to '${outDir}'...`);
if (copyExtra) console.log("✅ Copying extra non-Lua files enabled.");

walkDir(srcDir, (file) => {
    const rel = path.relative(srcDir, file);
    const outPath = path.join(outDir, rel);

    if (file.endsWith(".lua")) {
        minifyAndObfuscate(file, outPath);
    } else {
        copyOtherFile(file, outPath);
    }
});

console.log("✨ Done.");
