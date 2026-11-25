// Sorting and filtering for every table on every page, done in the browser.
//
// - Click a column header to sort (again: reverse, third time: original order).
// - Under each header there is a filter. Number and money columns take ">10", "<=5", "=3",
//   "10-20" or "10..20"; money also in coins: ">1g 50s". Text columns take a word to search
//   for ("!" in front excludes it); columns with only a few different values get a dropdown.
// - Above the table: a search across all columns, the number of rows shown and a reset button.
// Money cells carry their copper value in data-c (see money() in layout.ts); a cell can give its
// own sort value in data-sort. Tables inside a table cell (detail lists) are left alone.
// The filters and the sort of each table are remembered for the browser tab.

export const TABLE_CSS = `
.tk-bar{display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin:0 0 8px}
.tk-bar input{width:220px;padding:5px 8px;font-size:14px}
.tk-bar .tk-count{color:var(--muted);font-size:13px}
.tk-bar button{padding:5px 10px;font-size:11px}
th.tk-sort{cursor:pointer;user-select:none}
th.tk-sort:hover{color:var(--gold-hi)}
th.tk-sort .tk-arrow{display:inline-block;width:10px;margin-left:4px;color:var(--gold-hi)}
tr.tk-filters th{padding:2px 4px 6px;border-bottom:1px solid var(--edge)}
tr.tk-filters input,tr.tk-filters select{width:100%;min-width:0;max-width:160px;padding:3px 5px;font:13px var(--body);color:var(--text);
  background:#0c0a07;border:1px solid var(--hair)}
tr.tk-filters input:focus,tr.tk-filters select:focus{border-color:var(--gold)}
tr.tk-filters .tk-on{border-color:var(--gold-hi)}
`;

export const TABLE_JS = `
(function () {
  var MONEY_RE = /(-?\\d+(?:[.,]\\d+)?)\\s*([gsc])/gi;
  function store(key, val) { try { if (val == null) sessionStorage.removeItem(key); else sessionStorage.setItem(key, JSON.stringify(val)); } catch (e) {} }
  function load(key) { try { var v = sessionStorage.getItem(key); return v ? JSON.parse(v) : null; } catch (e) { return null; } }
  function firstLine(el) { return (el.innerText || "").trim().split("\\n")[0].trim(); }
  function parseNumber(s) {
    var m = String(s).replace(/[\\s\\u00a0\\u202f]/g, "").match(/^([+\\u2212-])?(\\d+(?:[.,]\\d+)?)/);
    if (!m) return null;
    var n = parseFloat(m[2].replace(",", "."));
    return m[1] === "-" || m[1] === "\\u2212" ? -n : n;
  }
  // A cell reads as a number only when little follows it ("155×", "8%", "12 db", "35 perc").
  function cellNumber(line) {
    var m = String(line).match(/^[+\\u2212-]?\\s*\\d[\\d\\s\\u00a0\\u202f]*(?:[.,]\\d+)?/);
    if (!m) return null;
    var rest = line.slice(m[0].length).trim();
    if (rest.length > 14 || /[a-z\\u00e1-\\u0171]{5,}/i.test(rest)) return null;
    return parseNumber(line);
  }
  // Copper from "1g 50s 3c", or a plain number.
  function parseAmount(s, money) {
    s = String(s).trim();
    if (money && /[gsc]/i.test(s)) {
      var total = 0, m, any = false;
      MONEY_RE.lastIndex = 0;
      while ((m = MONEY_RE.exec(s))) { any = true; total += parseFloat(m[1].replace(",", ".")) * ({ g: 10000, s: 100, c: 1 })[m[2].toLowerCase()]; }
      if (any) return total;
    }
    return parseNumber(s);
  }
  function cellValue(td) {
    if (!td) return { num: null, text: "" };
    var text = (td.innerText || "").toLowerCase();
    if (td.dataset.sort != null && td.dataset.sort !== "") {
      var n = Number(td.dataset.sort);
      return isNaN(n) ? { num: null, text: text, key: td.dataset.sort.toLowerCase() } : { num: n, text: text };
    }
    var line = firstLine(td);
    // Money shown in the cell itself, not in a detail list folded inside it.
    var coin = null;
    var coins = td.querySelectorAll("[data-c]");
    for (var i = 0; i < coins.length; i++) if (!coins[i].closest("details") && coins[i].closest("td") === td) { coin = coins[i]; break; }
    // Only when the cell starts with the amount, not a name with a price tag next to it.
    if (coin && /^[+\\u2212-]?\\s*\\d/.test(line)) {
      var c = Number(coin.dataset.c);
      return { num: /^[\\u2212-]/.test(line) ? -c : c, text: text, money: true };
    }
    return { num: cellNumber(line), text: text, key: line.toLowerCase() };
  }
  function matches(v, f, kind) {
    if (!f) return true;
    if (kind === "select") return (v.key || "") === f;
    if (kind === "num") {
      var r = f.match(/^\\s*(.+?)\\s*(?:\\.\\.|\\s-\\s|(?<=\\d)-(?=\\s*\\d))\\s*(.+)$/);
      if (r) {
        var lo = parseAmount(r[1], v.money !== false), hi = parseAmount(r[2], true);
        if (lo != null && hi != null) return v.num != null && v.num >= lo && v.num <= hi;
      }
      var m = f.match(/^\\s*(>=|<=|>|<|=|!=)?\\s*(.+)$/);
      var x = m && parseAmount(m[2], true);
      if (x == null) return v.text.indexOf(f.toLowerCase()) >= 0;
      if (v.num == null) return false;
      switch (m[1] || "=") {
        case ">": return v.num > x; case "<": return v.num < x;
        case ">=": return v.num >= x; case "<=": return v.num <= x;
        case "!=": return v.num !== x; default: return v.num === x;
      }
    }
    var neg = f.charAt(0) === "!";
    var q = (neg ? f.slice(1) : f).toLowerCase().trim();
    if (!q) return true;
    var hit = v.text.indexOf(q) >= 0;
    return neg ? !hit : hit;
  }

  function enhance(table, index) {
    var head = table.tHead;
    var body = table.tBodies[0];
    if (!head || !body || table.dataset.tk) return;
    if (table.parentElement && table.parentElement.closest("td")) return; // detail list inside a cell
    var headRow = head.rows[head.rows.length - 1];
    var rows = Array.prototype.slice.call(body.rows);
    if (rows.length < 2) return;
    for (var i = 0; i < rows.length; i++) {
      for (var j = 0; j < rows[i].cells.length; j++) if (rows[i].cells[j].colSpan > 1 || rows[i].cells[j].rowSpan > 1) return;
    }
    table.dataset.tk = "1";
    var cols = headRow.cells.length;
    var key = "tk:" + location.pathname + location.search + ":" + index;
    var state = load(key) || { sort: null, dir: 1, f: {}, q: "" };
    var values = rows.map(function (tr, i) {
      var vals = [];
      for (var c = 0; c < cols; c++) vals.push(cellValue(tr.cells[c]));
      return { tr: tr, i: i, vals: vals, all: (tr.innerText || "").toLowerCase() };
    });

    // Column kinds: numbers, a short list of values, or free text.
    var kinds = [];
    for (var c = 0; c < cols; c++) {
      var filled = 0, nums = 0, distinct = {};
      values.forEach(function (r) {
        var v = r.vals[c];
        if (!v.text.trim()) return;
        filled++;
        if (v.num != null) nums++;
        distinct[v.key || v.text] = 1;
      });
      var nDistinct = Object.keys(distinct).length;
      kinds.push(filled && nums / filled >= 0.6 ? "num" : nDistinct > 1 && nDistinct <= 15 && rows.length >= 6 ? "select" : "text");
    }

    var bar = document.createElement("div");
    bar.className = "tk-bar";
    var search = document.createElement("input");
    search.type = "search";
    search.placeholder = "Keresés a táblázatban…";
    search.value = state.q || "";
    var count = document.createElement("span");
    count.className = "tk-count";
    var reset = document.createElement("button");
    reset.type = "button";
    reset.textContent = "Szűrők törlése";
    bar.appendChild(search); bar.appendChild(count); bar.appendChild(reset);
    table.parentNode.insertBefore(bar, table);

    var filterRow = document.createElement("tr");
    filterRow.className = "tk-filters";
    var inputs = [];
    for (var c2 = 0; c2 < cols; c2++) {
      var th = document.createElement("th");
      var el;
      if (kinds[c2] === "select") {
        el = document.createElement("select");
        var opts = {};
        values.forEach(function (r) { var v = r.vals[c2]; if (v.key) opts[v.key] = firstLine(r.tr.cells[c2]); });
        el.appendChild(new Option("mind", ""));
        Object.keys(opts).sort().forEach(function (k) { el.appendChild(new Option(opts[k], k)); });
      } else {
        el = document.createElement("input");
        el.type = "text";
        el.placeholder = kinds[c2] === "num" ? ">10" : "szűrő";
        el.title = kinds[c2] === "num"
          ? "Szám vagy összeg: >10, <=5, =3, 10-20, 10..20; pénznél: >1g 50s"
          : "Szövegrész; ! elé írva kizárja";
      }
      el.value = (state.f && state.f[c2]) || "";
      el.dataset.col = String(c2);
      inputs.push(el);
      th.appendChild(el);
      filterRow.appendChild(th);
    }
    head.appendChild(filterRow);

    var heads = Array.prototype.slice.call(headRow.cells);
    heads.forEach(function (th, c) {
      th.classList.add("tk-sort");
      th.title = "Rendezés";
      var a = document.createElement("span");
      a.className = "tk-arrow";
      th.appendChild(a);
      th.addEventListener("click", function () {
        if (state.sort !== c) { state.sort = c; state.dir = kinds[c] === "num" ? -1 : 1; }
        else if (state.dir === (kinds[c] === "num" ? -1 : 1)) state.dir = -state.dir;
        else state.sort = null;
        apply();
      });
    });

    function apply() {
      var shown = 0;
      var q = (search.value || "").toLowerCase().trim();
      var order = values.slice();
      if (state.sort != null) {
        var c = state.sort, dir = state.dir, num = kinds[c] === "num";
        order.sort(function (a, b) {
          var x = a.vals[c], y = b.vals[c];
          var r;
          if (num) {
            if (x.num == null && y.num == null) r = 0;
            else if (x.num == null) return 1;
            else if (y.num == null) return -1;
            else r = x.num - y.num;
          } else r = (x.key || x.text).localeCompare(y.key || y.text, "hu");
          return r * dir || a.i - b.i;
        });
      }
      state.f = {};
      inputs.forEach(function (el) {
        if (el.value) state.f[el.dataset.col] = el.value;
        el.classList.toggle("tk-on", !!el.value);
      });
      order.forEach(function (r) {
        var ok = !q || r.all.indexOf(q) >= 0;
        for (var c = 0; ok && c < cols; c++) ok = matches(r.vals[c], state.f[c], kinds[c]);
        r.tr.style.display = ok ? "" : "none";
        if (ok) shown++;
        body.appendChild(r.tr);
      });
      heads.forEach(function (th, c) {
        th.querySelector(".tk-arrow").textContent = state.sort === c ? (state.dir > 0 ? "\\u25B2" : "\\u25BC") : "";
      });
      state.q = search.value;
      count.textContent = shown === values.length ? values.length + " sor" : shown + " / " + values.length + " sor";
      store(key, state);
    }
    inputs.forEach(function (el) { el.addEventListener(el.tagName === "SELECT" ? "change" : "input", apply); });
    search.addEventListener("input", apply);
    reset.addEventListener("click", function () {
      inputs.forEach(function (el) { el.value = ""; });
      search.value = "";
      state = { sort: null, dir: 1, f: {}, q: "" };
      apply();
    });
    apply();
  }

  function run() { Array.prototype.forEach.call(document.querySelectorAll("main table"), enhance); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run); else run();
})();
`;
