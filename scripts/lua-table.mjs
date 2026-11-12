// Minimal parser for WoW SavedVariables files: `Name = { ... }` assignments with
// tables, strings, numbers, booleans and nil. Returns { Name: value, ... }.
export function parseSavedVariables(src) {
  let i = 0;
  const out = {};

  const skip = () => {
    for (;;) {
      while (i < src.length && /\s/.test(src[i])) i++;
      if (src.startsWith("--", i)) {
        while (i < src.length && src[i] !== "\n") i++;
      } else return;
    }
  };
  const fail = (msg) => {
    throw new Error(`${msg} at offset ${i}: ${JSON.stringify(src.slice(i, i + 30))}`);
  };

  function string() {
    const quote = src[i++];
    let s = "";
    let byteEscapes = false;
    while (i < src.length && src[i] !== quote) {
      if (src[i] === "\\") {
        const c = src[++i];
        if (c === "n") s += "\n";
        else if (c === "t") s += "\t";
        else if (c === "r") s += "\r";
        else if (/\d/.test(c)) {
          let d = "";
          while (d.length < 3 && /\d/.test(src[i])) d += src[i++];
          s += String.fromCharCode(Number(d));
          byteEscapes = true;
          continue;
        } else s += c;
        i++;
      } else s += src[i++];
    }
    i++;
    // \ddd escapes are raw UTF-8 bytes; turn them back into text. Strings without
    // escapes were already decoded when the file was read.
    return byteEscapes && !/[^\x00-\xff]/.test(s) ? Buffer.from(s, "latin1").toString("utf8") : s;
  }

  function value() {
    skip();
    const c = src[i];
    if (c === "{") return table();
    if (c === '"' || c === "'") return string();
    const m = /^(?:-?(?:0x[\da-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)|true|false|nil|-?inf|-?nan)/.exec(src.slice(i, i + 40));
    if (!m) fail("Unexpected token");
    i += m[0].length;
    if (m[0] === "true") return true;
    if (m[0] === "false") return false;
    if (m[0] === "nil") return null;
    return Number(m[0]);
  }

  function table() {
    i++; // {
    const obj = {};
    let n = 1;
    let isArray = true;
    for (;;) {
      skip();
      if (src[i] === "}") {
        i++;
        break;
      }
      let key;
      if (src[i] === "[") {
        i++;
        key = value();
        skip();
        if (src[i++] !== "]") fail("Expected ]");
        skip();
        if (src[i++] !== "=") fail("Expected =");
        if (key !== n) isArray = false;
        else n++;
      } else {
        const m = /^[A-Za-z_]\w*\s*=/.exec(src.slice(i, i + 80));
        if (m) {
          key = m[0].replace(/\s*=$/, "");
          i += m[0].length;
          isArray = false;
        } else key = n++;
      }
      obj[key] = value();
      skip();
      if (src[i] === "," || src[i] === ";") i++;
    }
    const keys = Object.keys(obj);
    return isArray && keys.length ? keys.map((k) => obj[k]) : obj;
  }

  for (;;) {
    skip();
    if (i >= src.length) break;
    const m = /^([A-Za-z_]\w*)\s*=/.exec(src.slice(i, i + 120));
    if (!m) fail("Expected assignment");
    i += m[0].length;
    out[m[1]] = value();
  }
  return out;
}
