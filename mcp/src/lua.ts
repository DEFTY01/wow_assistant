// SavedVariables reading reuses the repository's parser; writing produces plain Lua literals only.
import { parseSavedVariables as parse } from "../../scripts/lua-table.mjs";
import { readFileSync } from "node:fs";

export type LuaValue = null | boolean | number | string | LuaValue[] | { [k: string]: LuaValue };

export function parseSavedVariables(src: string): Record<string, LuaValue> {
  return parse(src) as Record<string, LuaValue>;
}

/** Parses a SavedVariables file; retries briefly because the game may be writing it. */
export function readSavedVariables(file: string, attempts = 3): Record<string, LuaValue> {
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return parseSavedVariables(readFileSync(file, "utf8"));
    } catch (e) {
      last = e;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1000); // synchronous 1 s pause
    }
  }
  throw last;
}

const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;

function str(s: string): string {
  let out = '"';
  for (const ch of s) {
    const c = ch.codePointAt(0)!;
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (c < 32 || c === 127) out += `\\${c}`;
    else out += ch; // UTF-8 text is written as-is; the game reads the file as UTF-8
  }
  return out + '"';
}

/** Serializes a JSON-like value as a Lua literal (no code, no functions). */
export function toLua(v: unknown, indent = ""): string {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error("Non-finite number cannot be written to Lua");
    return String(v);
  }
  if (typeof v === "string") return str(v);
  const inner = indent + "\t";
  if (Array.isArray(v)) {
    if (!v.length) return "{}";
    return "{\n" + v.map((x) => `${inner}${toLua(x, inner)},`).join("\n") + `\n${indent}}`;
  }
  if (typeof v === "object") {
    const entries = Object.entries(v as Record<string, unknown>).filter(([, x]) => x !== undefined);
    if (!entries.length) return "{}";
    return (
      "{\n" +
      entries.map(([k, x]) => `${inner}${IDENT.test(k) ? `["${k}"]` : `[${str(k)}]`} = ${toLua(x, inner)},`).join("\n") +
      `\n${indent}}`
    );
  }
  throw new Error(`Cannot serialize ${typeof v} to Lua`);
}
