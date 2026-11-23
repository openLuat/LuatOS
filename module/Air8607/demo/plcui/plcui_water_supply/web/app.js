/* plcui_water_supply · 渲染/交互/模拟 —— 配合 spec.js 使用 */
const L = SPEC.layout;
const el = (tag, cls, css, txt) => { const e = document.createElement(tag);
  if (cls) e.className = cls; if (css) e.setAttribute("style", css); if (txt != null) e.textContent = txt; return e; };
const $ = (id) => document.getElementById(id);

/* ---------- 参数页渲染 ---------- */
function cellGeom(page, idx, nCells, merged) {
  const wide = nCells === 1 || merged;
  const bandW = L.formW;
  if (merged) return { x: 330, w: bandW - 340 };
  if (nCells === 1) return { x: 8, w: bandW - 16 };
  const w = Math.floor((bandW - 8) / nCells);
  return { x: 4 + idx * w, w: w - 8 };
}
function renderCell(band, cell, geom, page) {
  const { x, w } = geom;
  const y = L.rowTop;
  const cols3 = w < 300;
  const valX = cols3 ? L.cellVal3 : L.cellVal2, unitX = cols3 ? L.cellUnit3 : L.cellUnit2;
  const helpX = cols3 ? x + 4 : x + L.cellHelp2;
  const mk = (cls, css, txt) => { const e = el("div", cls, `left:${x}px;${css}`, txt); band.appendChild(e); return e; };
  if (cell.dt) {
    mk("flab", `top:${y + 6}px;max-width:${w - 320}px`, cell.l + ":");
    for (let i = 0; i < 4; i++) {
      const bx = x + Math.min(200, w - 320) + 30 + i * 62;
      const inp = el("input", "fval dyn", `left:${bx}px;top:${y + 10}px;width:48px`);
      inp.value = ["0", "0", "0", "0"][i]; inp.dataset.k = "num";
      inp.onclick = () => openKeypad(inp, cell.l);
      band.appendChild(inp);
      band.appendChild(el("div", "funit", `left:${bx + 50}px;top:${y + 14}px`, ["年", "月", "日", "时"][i]));
    }
    return;
  }
  if (cell.t === "toggle") {
    const b = el("div", "ftog dyn" + (cell.red ? " red" : cell.on ? " on" : ""),
      `left:${x + 6}px;top:${y + 14}px;width:${w - 14}px`, cell.l);
    b.onclick = () => { b.classList.toggle("on"); };
    band.appendChild(b);
    if (cell.h) band.appendChild(el("div", "fhelp", `left:${x + 6}px;top:${y + 48}px;width:${w - 14}px`, cell.h));
    return;
  }
  if (cell.t === "sel") {
    mk("flab", `top:${y + 8}px;max-width:${w - 140}px`, cell.l + ":");
    const s = el("div", "fsel dyn", `left:${x + w - 132}px;top:${y + 12}px;width:124px`, cell.v);
    s.onclick = () => { const o = cell.opts; s.textContent = cell.v = o[(o.indexOf(cell.v) + 1) % o.length]; };
    band.appendChild(s);
    return;
  }
  if (cell.t === "btn") {
    const b = el("div", "fbtn dyn", `left:${x + w / 2 - 60}px;top:${y + 14}px;width:120px`, cell.v);
    b.onclick = () => H.action(cell.v);
    band.appendChild(b);
    return;
  }
  /* 数值框 num */
  if (!cell.l && !cell.v) return;
  mk("flab", `top:${y + 6}px;max-width:${cols3 ? 104 : (cell.wide ? 260 : 140)}px`, cell.l);
  const inp = el("input", "fval dyn",
    `left:${cell.wide ? x + 300 : x + valX}px;top:${y + 12}px;width:${cell.wide ? 72 : 72}px`);
  inp.value = cell.v; inp.dataset.k = "num";
  inp.onclick = () => openKeypad(inp, cell.l);
  band.appendChild(inp);
  if (cell.u) band.appendChild(el("div", "funit",
    `left:${(cell.wide ? x + 300 : x + valX) + 78}px;top:${y + 16}px`, cell.u));
  if (cell.h) band.appendChild(el("div", "fhelp",
    `left:${cell.wide ? x + 430 : helpX}px;top:${y + 2}px;width:${cell.wide ? w - 440 : 122}px`, cell.h));
}
function renderForm(page) {
  const P = el("div", "page", "", null); P.id = page.id;
  const F = el("div", "form", "", null);
  const T = el("div", "f-title", "", page.title);
  if (page.sub) { const s = el("div", "sub", "", null);
    s.innerHTML = `${page.sub} <input value="${page.subv}"> ${page.subu}`; T.appendChild(s); }
  if (page.ver) T.appendChild(el("div", "ver", "", page.ver));
  F.appendChild(T);
  const nbands = 7;
  for (let r = 0; r < nbands; r++) {
    const band = el("div", "frow", "", null); F.appendChild(band);
    const cells = r < page.rows.length ? page.rows[r] : [];
    const merged = (r === 6 && page.strip && page.rows.length >= 7);
    if (r === 6 && page.strip && !merged) {
      /* 操作条独占第 7 行 */
      page.strip.forEach((c, i) => {
        if (c.t === "btn") {
          const b = el("div", "fbtn dyn", `left:${20 + i * 170}px;top:20px;width:150px;height:36px`, c.v);
          b.onclick = () => UI.show(c.go); band.appendChild(b);
        } else {
          band.appendChild(el("div", "flab", `left:${20 + i * 170}px;top:18px`, c.l));
          const inp = el("input", "fval dyn", `left:${20 + i * 170 + 110}px;top:20px;width:72px`);
          inp.value = c.v; inp.onclick = () => openKeypad(inp, c.l); band.appendChild(inp);
          if (c.u) band.appendChild(el("div", "funit", `left:${20 + i * 170 + 188}px;top:24px`, c.u));
        }
      });
    } else {
      cells.forEach((c, i) => renderCell(band, c, cellGeom(page, i, merged ? 1 : cells.length, merged), page));
      if (merged) page.strip.forEach((c, i) => {
        const b = el("div", "fbtn dyn", `left:${14 + i * 156}px;top:20px;width:140px;height:36px`, c.v);
        b.onclick = () => UI.show(c.go); band.appendChild(b);
      });
    }
  }
  P.appendChild(F);
  /* 右侧导航 + 日期 */
  const nav = el("div", "nav", "", null);
  SPEC.nav.forEach((n) => {
    const [t, id] = n.split("|");
    const b = el("div", "nb dyn", "", t); b.dataset.nav = id;
    b.onclick = () => UI.show(id); nav.appendChild(b);
  });
  const d = el("div", "date dyn", "", "2026/04/02\n16:34:46"); d.id = page.id + "-date";
  nav.appendChild(d);
  P.appendChild(nav);
  return P;
}
/* ---------- 时段供水（表格型） ---------- */
function renderSched(page) {
  const P = el("div", "page", "", null); P.id = page.id;
  const F = el("div", "form", "", null);
  F.appendChild(el("div", "f-title", "", page.title));
  const S = L.sched;
  const head = el("div", "frow", "height:44px;background:#2468B0", null);
  [["时段", S.idxX], ["开关", S.swX], ["启用时间", S.shX], ["至", S.ehX - 40], ["结束时间", S.ehX + 10], ["定时压力", S.pX]]
    .forEach(([t, x]) => head.appendChild(el("div", "flab", `left:${x}px;top:8px;background:#62C8F0;border-color:#1B5CA8`, t)));
  F.appendChild(head);
  page.rows.forEach((row, ri) => {
    const band = el("div", "frow", "", null);
    band.appendChild(el("div", "", `position:absolute;left:${S.idxX}px;top:22px;font-size:19px;font-weight:700`, String(ri + 1)));
    const sw = el("div", "ftog dyn", `left:${S.swX}px;top:20px;min-width:44px;width:44px;height:34px;border-radius:17px`,
      row.sw ? "开" : "关");
    sw.onclick = () => { row.sw = !row.sw; sw.textContent = row.sw ? "开" : "关"; sw.classList.toggle("on", row.sw); };
    if (row.sw) sw.classList.add("on");
    band.appendChild(sw);
    const mkv = (v, x) => { const i = el("input", "fval dyn", `left:${x}px;top:20px;width:52px`); i.value = v;
      i.onclick = () => openKeypad(i, "时间"); band.appendChild(i); };
    mkv(row.sh, S.shX); band.appendChild(el("div", "funit", `left:${S.shX + 54}px;top:24px`, ":"));
    mkv(row.sm, S.smX);
    band.appendChild(el("div", "funit", `left:${S.smX + 62}px;top:24px`, "至"));
    mkv(row.eh, S.ehX); band.appendChild(el("div", "funit", `left:${S.ehX + 54}px;top:24px`, ":"));
    mkv(row.em, S.emX);
    mkv(row.p, S.pX); band.appendChild(el("div", "funit", `left:${S.pX + 58}px;top:24px`, "Mpa"));
    F.appendChild(band);
  });
  /* 第 7 行：操作条 + 目标压力 */
  const band = el("div", "frow", "", null);
  page.strip.forEach((c, i) => {
    if (c.t === "btn") {
      const b = el("div", "fbtn dyn", `left:${20 + i * 170}px;top:20px;width:150px;height:36px`, c.v);
      b.onclick = () => UI.show(c.go); band.appendChild(b);
    } else {
      band.appendChild(el("div", "flab", `left:380px;top:18px`, c.l));
      const inp = el("input", "fval dyn", `left:500px;top:20px;width:72px`); inp.value = c.v;
      inp.onclick = () => openKeypad(inp, c.l); band.appendChild(inp);
      band.appendChild(el("div", "funit", `left:578px;top:24px`, c.u));
    }
  });
  F.appendChild(band);
  P.appendChild(F);
  const nav = el("div", "nav", "", null);
  SPEC.nav.forEach((n) => {
    const [t, id] = n.split("|");
    const b = el("div", "nb dyn", "", t); b.dataset.nav = id;
    b.onclick = () => UI.show(id); nav.appendChild(b);
  });
  const d = el("div", "date dyn", "", ""); d.id = page.id + "-date";
  nav.appendChild(d);
  P.appendChild(nav);
  return P;
}
/* ---------- 页面导航 ---------- */
const UI = {
  show(id) {
    document.querySelectorAll(".page").forEach((p) => p.classList.toggle("on", p.id === id));
    document.querySelectorAll(".nav .nb").forEach((b) => b.classList.toggle("sel", b.dataset.nav === id));
    window.scrollTo(0, 0);
  }
};
/* ---------- 时钟 ---------- */
function tickClock() {
  const d = new Date(), p = (n) => String(n).padStart(2, "0");
  const ds = `${d.getFullYear()}/${p(d.getMonth() + 1)}/${p(d.getDate())}`;
  const ts = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  const set = (id, v) => { const e = $(id); if (e) e.textContent = v; };
  set("run-date", ds); set("run-time", ts);
  document.querySelectorAll(".nav .date").forEach((e) => e.innerHTML = ds + "<br>" + ts);
  $("fault-date").innerHTML = ds + "<br>" + ts;
}
/* ---------- 数值键盘弹层 ---------- */
let kpTarget = null;
function openKeypad(inp, title) {
  kpTarget = inp;
  $("kp-title").textContent = (title || "数值") + "  输入";
  $("kp-val").value = inp.value;
  $("keypad").classList.add("on");
}
function kpKey(k) {
  const v = $("kp-val");
  if (k === "OK") { if (kpTarget) kpTarget.value = v.value; $("keypad").classList.remove("on"); simApply(kpTarget); }
  else if (k === "CLR") v.value = "";
  else if (k === "DEL") v.value = v.value.slice(0, -1);
  else v.value += k;
}
/* ---------- 运行画面：泵组渲染 ---------- */
const SIM = { run:false, mode:"auto", curp:0, level:0, freq:50,
  pumps:[{s:"run",m:"变频"},{s:"freq",m:"工频"},{s:"freq",m:"工频"},{s:"stand",m:"待机"},{s:"stand",m:"待机"}],
  faults:[{t:"出水超压", a:"2026/04/02 15:20:11", c:"2026/04/02 15:20:30"},
          {t:"变频器故障", a:"2026/04/02 15:18:02", c:"2026/04/02 15:18:40"}] };
function renderPumps() {
  const host = $("pumps"); if (!host || host.childElementCount) return;
  for (let i = 0; i < 5; i++) {
    const x = 216 + i * 104;
    host.appendChild(Object.assign(document.createElement("img"), { className:"pv", src:"assets/pipe_v.svg" }))
      .setAttribute("style", `left:${x + 36}px;top:266px;height:42px`);
    host.appendChild(Object.assign(document.createElement("img"), { className:"pv", src:"assets/pipe_v.svg" }))
      .setAttribute("style", `left:${x + 36}px;top:398px;height:70px`);
    const img = document.createElement("img");
    img.className = "pump dyn"; img.src = "assets/pump.svg"; img.id = "pump" + i;
    img.setAttribute("style", `left:${x}px;top:300px`);
    host.appendChild(img);
    const no = el("div", "pump-no dyn", `left:${x}px;top:336px`, String(i + 1)); no.id = "pno" + i;
    host.appendChild(no);
    const ch = el("div", "chip dyn", `left:${x}px;top:524px;width:86px`, SIM.pumps[i].m); ch.id = "chip" + i;
    host.appendChild(ch);
  }
}
function refreshPumps() {
  for (let i = 0; i < 5; i++) {
    const img = $("pump" + i), ch = $("chip" + i);
    if (!img) continue;
    img.className = "pump dyn " + ({ run:"st-run", freq:"st-freq", stand:"st-stand" }[SIM.pumps[i].s] || "st-stand");
    ch.textContent = SIM.pumps[i].m;
    const hide = ($("v_level") && SIM.pumps.length < 5);
  }
}
/* ---------- 操作与模拟 ---------- */
function simApply(inp) {
  if (!inp) return;
  if (inp.id === "v_tgtp") { /* 目标压力 */ }
}
function fmt(v, n) { return Number(v).toFixed(n); }
const H = {
  start() { SIM.run = true; },
  stop()  { SIM.run = false; SIM.pumps.forEach((p, i) => { p.s = "stand"; p.m = "待机"; }); refreshPumps(); },
  setMode(m) { SIM.mode = m;
    document.querySelector('[data-id=btn_auto]').className = "btn dyn " + (m === "auto" ? "gpill" : "blue");
    document.querySelector('[data-id=btn_manual]').className = "btn dyn " + (m === "manual" ? "gpill" : "blue"); },
  clearFaults() { SIM.faults = []; renderFaults(); },
  action(name) {
    if (name === "恢复默认") { /* 保持演示数据 */ }
    if (name === "触摸校准") alert("请在 3 秒内点击屏幕四角完成触摸校准");
    if (name === "压力校准") alert("压力校准已启动");
    if (name === "确定") alert("时间校准完成");
    if (name === "停用") alert("工程时间已停用");
  }
};
function renderFaults() {
  const t = $("fault-tbl");
  while (t.rows.length > 1) t.deleteRow(1);
  SIM.faults.forEach((f, i) => {
    const r = t.insertRow();
    [i + 1, f.t, f.a, f.c].forEach((v) => { const c = r.insertCell(); c.textContent = v; });
  });
}
function simTick() {
  if (SIM.run) {
    const tgt = parseFloat(($("v_tgtp") || {}).value || "2.00");
    const act = SIM.pumps.filter((p) => p.s !== "stand").length;
    if (SIM.mode === "auto") {
      if (SIM.curp < tgt - 0.15 && act < 5) SIM.pumps[act] = { s: act === 0 ? "run" : "freq", m: act === 0 ? "变频" : "工频" };
      else if (SIM.curp > tgt + 0.15 && act > 1) SIM.pumps[act - 1] = { s:"stand", m:"待机" };
      refreshPumps();
    }
    const cap = SIM.pumps.filter((p) => p.s !== "stand").length;
    SIM.curp += (cap * 0.75 - SIM.curp) * 0.12;
    SIM.freq = 28 + Math.min(22, Math.abs(tgt - SIM.curp) * 26);
    SIM.level = Math.max(0, Math.min(2.6, SIM.level + (cap ? -0.002 : 0.001)));
    const set = (id, v) => { const e = $(id); if (e) e.value = v; };
    set("v_curp", fmt(SIM.curp, 2)); set("v_freq", fmt(SIM.freq, 2)); set("v_level", fmt(SIM.level, 2));
  }
  tickClock();
}
/* ---------- 启动 ---------- */
(function init() {
  const q = new URLSearchParams(location.search);
  SPEC.pages.forEach((p) => {
    const node = p.type === "sched" ? renderSched(p) : renderForm(p);
    $("form-host").appendChild(node);
  });
  renderPumps(); refreshPumps(); renderFaults(); tickClock();
  setInterval(simTick, 1000);
  /* bake 模式：仅显示指定页，清空动态值供背景烘焙 */
  if (q.get("bake")) {
    document.body.classList.add("bake");
    document.querySelectorAll(".page").forEach((p) => p.classList.toggle("on", p.id === q.get("page")));
    document.querySelectorAll("input").forEach((i) => i.value = "");
  }
  /* chrome 模式：表单族共享背景——只留渐变/面板/行分隔，去掉文字与控件 */
  if (q.get("chrome")) {
    document.body.classList.add("bake", "chrome");
    const pid = q.get("page") || "p_out";
    document.querySelectorAll(".page").forEach((p) => p.classList.toggle("on", p.id === pid));
    document.querySelectorAll("input").forEach((i) => i.value = "");
    document.querySelectorAll(".f-title").forEach((t) => {
      [...t.childNodes].forEach((n) => { if (n.nodeType === 3) n.remove(); });
    });
  }
  if (q.get("page")) UI.show(q.get("page"));
})();
