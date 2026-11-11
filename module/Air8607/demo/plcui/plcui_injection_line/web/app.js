/* 注塑产线 HMI 前端原型引擎 - 数据模拟/导航/交互
 * 页面: index.html mc.html ctl.html pr.html rc.html  */
(function () {
  "use strict";
  var KEY = "inj_line_state_v1";
  var NAV = [["ov", "总览", "index.html"], ["mc", "注塑机", "mc.html"], ["ctl", "控制台", "ctl.html"],
             ["pr", "参数", "pr.html"], ["rc", "记录", "rc.html"]];

  function defState() {
    return {
      running: true, mode: "auto",
      shift: { out: 3842, plan: 4200, good: 3812, bad: 30 },
      machines: [
        { id: 1, run: true, shot: 12450, cyc: 32.5, t: [210.2, 215.1, 220.3, 218.2, 225.0, 45.2], p: [125.2, 85.1, 12.5] },
        { id: 2, run: true, shot: 11982, cyc: 31.8, t: [211.0, 214.6, 219.4, 216.8, 224.2, 46.1], p: [122.8, 84.6, 12.2] },
        { id: 3, run: true, shot: 12211, cyc: 33.1, t: [209.8, 215.4, 220.8, 214.9, 225.6, 44.8], p: [126.4, 86.2, 12.8] }
      ],
      aux: { dryer: 1, chiller: 1, moldtemp: 1, packer: 1, gran: 0, belt: 1, rob: 1 },
      sel: 1,
      al: { text: "2# 料温偏高 2℃", level: 2, cnt: 2 },
      pars: { t1: 210, t2: 215, t3: 220, t4: 215, t5: 225, t6: 45, p1: 125, p2: 85, p3: 60, p4: 12.5 }
    };
  }
  var S;
  try { S = JSON.parse(localStorage.getItem(KEY)) || defState(); } catch (e) { S = defState(); }
  function save() { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) {} }
  function $(id) { return document.getElementById(id); }
  function txt(id, s) { var el = $(id); if (el) el.textContent = s; }
  function fx(v, n) { return (Math.round(v * Math.pow(10, n)) / Math.pow(10, n)).toFixed(n); }
  function rnd(a) { return (Math.random() - 0.5) * 2 * a; }
  function nowStr() {
    var d = new Date(), p = function (n) { return (n < 10 ? "0" : "") + n; };
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " +
           p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds());
  }

  function injectNav(active) {
    var d = document.createElement("div");
    d.className = "nav"; d.style.left = "252px"; d.style.top = "566px";
    NAV.forEach(function (n) {
      var b = document.createElement("div");
      b.className = "nb" + (n[0] === active ? " on" : "");
      b.textContent = n[1];
      b.onclick = function () { location.href = n[2]; };
      d.appendChild(b);
    });
    var st = document.querySelector(".stage");
    if (st) st.appendChild(d);
  }

  function startClock() {
    var upd = function () {
      var s = nowStr();
      document.querySelectorAll('[data-id="clock"]').forEach(function (el) { el.textContent = s; });
    };
    upd(); setInterval(upd, 1000);
  }
  var phase = 0, phaseT = 0;
  var PHASE_DUR = [3.5, 2.0, 3.5, 8.5, 4.0, 3.0];

  function tick() {
    if (S.running) {
      S.machines.forEach(function (m) {
        if (!m.run) return;
        for (var i = 0; i < 6; i++) m.t[i] += rnd(0.35);
        m.p[0] += rnd(1.2); m.p[1] += rnd(0.8); m.p[2] += rnd(0.15);
      });
    }
    save(); render();
  }

  function render() {
    var m = S.machines[S.sel - 1];
    txt("clock", nowStr());
    txt("kpi_out", S.shift.out);
    txt("kpi_rate", fx(S.shift.out / S.shift.plan * 100, 1) + "%");
    txt("kpi_yield", fx(S.shift.good / S.shift.out * 100, 1));
    txt("kpi_oee", fx(87 + rnd(0.4), 1));
    txt("kpi_cyc", fx(32.5 + rnd(0.3), 1));
    S.machines.forEach(function (mm, i) {
      txt("m" + (i + 1) + "st", mm.run ? "运行" : "停止");
      txt("m" + (i + 1) + "shot", "模次 " + mm.shot);
      txt("st_m" + (i + 1), (i + 1) + "# " + (mm.run ? "运行" : "停机") + " · " +
          Math.round(mm.t[0]) + "℃ · " + (S.mode === "auto" ? "自动" : S.mode === "semi" ? "半自动" : "手动"));
    });
    txt("belt_spd", "输送带 12.5 m/min · " + (S.aux.belt ? "运行" : "停止"));
    txt("belt_cnt", "本班入仓 " + S.shift.out + " 模");
    txt("dry_st", "120℃ " + (S.aux.dryer ? "运行" : "停止"));
    txt("cool_st", "冷却水 24." + (6 + Math.floor(Math.random() * 3)) + "℃ · 模温 45." +
        (1 + Math.floor(Math.random() * 4)) + "℃ · 流量 86 L/min");
    txt("pack_st", "包装 25 kg/袋 · 今日 " + Math.floor(S.shift.out / 25) + " 袋");
    txt("al_txt", S.al.text);
    txt("al_cnt", S.al.cnt);
    if (m) {
      txt("mc_shot", "累计模次：" + m.shot);
      txt("mc_cyc", "当前周期：" + fx(m.cyc + rnd(0.2), 1) + " s");
      txt("mc_good", "班次良品：" + S.shift.good + " 模");
      txt("mc_clamp", "锁模力 " + Math.round(1286 + rnd(8)) + " kN");
      txt("mc_pos", "开模位置 " + Math.round(312 + rnd(3)) + " mm");
      txt("mc_vel", "注射速度 " + Math.round(86 + rnd(2)) + " mm/s");
      txt("mc_screw", "螺杆转速 " + Math.round(125 + rnd(3)) + " rpm");
      txt("mc_st", m.run ? "● 自动运行中" : "● 已停机");
      var names = ["tv_t1", "tv_t2", "tv_t3", "tv_t4", "tv_t5", "tv_t6"];
      var sps = [S.pars.t1, S.pars.t2, S.pars.t3, S.pars.t4, S.pars.t5, S.pars.t6];
      for (var i = 0; i < 6; i++) {
        txt(names[i], fx(m.t[i], 1) + " / " + sps[i]);
        var bar = $("bar-t" + (i + 1));
        if (bar) bar.style.width = Math.max(4, Math.min(98, m.t[i] / 300 * 100)) + "%";
      }
      txt("pv_p1", fx(m.p[0], 1)); txt("pv_p2", fx(m.p[1], 1)); txt("pv_p3", fx(m.p[2], 1));
      txt("pv_p4", Math.round(1286 + rnd(8)) + " kN");
      var bp = [$("bar-p1"), $("bar-p2"), $("bar-p3")];
      if (bp[0]) bp[0].style.width = Math.min(98, m.p[0] / 200 * 100) + "%";
      if (bp[1]) bp[1].style.width = Math.min(98, m.p[1] / 200 * 100) + "%";
      if (bp[2]) bp[2].style.width = Math.min(98, m.p[2] / 100 * 100) + "%";
      txt("mc_upd", nowStr().slice(11));
      drawCharts(m);
    }
    var ao = [["ao1", "bar-ao1", 125 + rnd(2), 200], ["ao2", "bar-ao2", S.pars.p4 + rnd(0.3), 50],
              ["ao3", "bar-ao3", 70 + rnd(1), 100], ["ao4", "bar-ao4", 55 + rnd(1), 100]];
    ao.forEach(function (a) {
      txt(a[0], fx(a[2], a[0] === "ao2" ? 1 : 0));
      var b = $(a[1]); if (b) b.style.width = Math.min(98, a[2] / a[3] * 100) + "%";
    });
    txt("st_lube", "润滑油压：" + fx(0.32 + rnd(0.01), 2) + " MPa");
    txt("st_today", S.shift.out);
    txt("st_hours", fx(3.2 + rnd(0.05), 1));
    updatePhaseUI();
  }

  function updatePhaseUI() {
    var bar = $("phase-bar");
    if (!bar) return;
    phaseT += 1;
    if (phaseT > PHASE_DUR[phase]) {
      phaseT = 0; phase = (phase + 1) % 6;
      if (phase === 0) {
        S.shift.out++; S.shift.good++;
        S.machines.forEach(function (m) { if (m.run) m.shot++; });
        save();
      }
    }
    var phs = bar.children, prog = 0;
    for (var i = 0; i < 6; i++) {
      phs[i].className = "ph" + (i < phase ? " done" : i === phase ? " act" : "");
      if (i < phase) prog += PHASE_DUR[i];
    }
    prog += phaseT;
    txt("ph_prog", Math.round(prog / 24.5 * 100) + "%");
    txt("ph_time", fx(phaseT, 1) + " s");
  }
  var histT = [], histP = [];
  function drawCharts(m) {
    histT.push([m.t[0], m.t[1], m.t[4]]); histP.push([m.p[0], m.p[1]]);
    if (histT.length > 60) histT.shift();
    if (histP.length > 60) histP.shift();
    line($("chart-t"), histT, ["#29d8f0", "#2ee6a0", "#ffa62b"], 180, 240);
    line($("chart-p"), histP, ["#ffa62b", "#ff6b81"], 0, 200);
  }
  function line(cv, data, colors, lo, hi) {
    if (!cv || !cv.getContext || !data.length) return;
    var g = cv.getContext("2d"), w = cv.width, h = cv.height;
    g.clearRect(0, 0, w, h);
    g.strokeStyle = "rgba(41,216,240,.15)"; g.lineWidth = 1;
    for (var y = 0; y <= h; y += h / 4) { g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke(); }
    for (var c = 0; c < data[0].length; c++) {
      g.strokeStyle = colors[c]; g.lineWidth = 1.6; g.beginPath();
      for (var i = 0; i < data.length; i++) {
        var x = i / (data.length - 1) * w, yy = h - (data[i][c] - lo) / (hi - lo) * h;
        i ? g.lineTo(x, yy) : g.moveTo(x, yy);
      }
      g.stroke();
    }
  }

  function bind() {
    [1, 2, 3].forEach(function (n) {
      var b = $("sel-m" + n);
      if (b) b.onclick = function () {
        S.sel = n; save();
        [1, 2, 3].forEach(function (k) { $("sel-m" + k).className = "btn" + (k === n ? " on" : ""); });
        histT = []; histP = []; render();
      };
    });
    var flash = function (b) {
      b.style.filter = "brightness(1.6)";
      setTimeout(function () { b.style.filter = ""; }, 300);
    };
    var acts = {
      run_start: function () { S.running = true; S.machines.forEach(function (m) { m.run = true; }); },
      run_stop: function () { S.running = false; S.machines.forEach(function (m) { m.run = false; }); },
      run_pause: function () { S.running = !S.running; },
      run_reset: function () { S.al = { text: "系统复位完成", level: 3, cnt: 0 }; },
      alarm_ack: function () { S.al.cnt = 0; S.al.text = "无未确认报警"; },
      shift_clear: function () { S.shift.out = 0; S.shift.good = 0; S.shift.bad = 0; },
      shift_change: function () { S.shift.out = 0; S.shift.good = 0; S.shift.bad = 0; S.shift.plan = 4200; },
      his_save: function () { S.al.text = "记录已保存"; },
      go_rc: function () { location.href = "rc.html"; },
      par_apply: function () { S.al.text = "参数已应用"; },
      par_def: function () { S.pars = defState().pars; S.al.text = "参数已恢复默认"; },
      par_upld: function () { S.al.text = "参数上载完成"; },
      par_dnld: function () { S.al.text = "参数下载完成"; },
      jog_open: function () {}, jog_close: function () {}, jog_eject: function () {},
      jog_inj: function () {}, jog_feed: function () {}, jog_rob: function () {},
      page_prev: function () {}, page_next: function () {},
      rc_sel1: function () {}, rc_sel2: function () {}, rc_sel3: function () {}, rc_sel4: function () {}
    };
    document.querySelectorAll("[data-handler]").forEach(function (b) {
      var fn = acts[b.getAttribute("data-handler")];
      if (!fn) return;
      b.onclick = function () {
        fn(); save(); render(); flash(b);
        var st = b.getAttribute("data-states");
        if (st && st.indexOf("checked") >= 0) {
          b.parentNode.querySelectorAll('[data-states*="checked"]').forEach(function (o) {
            o.classList.toggle("on", o === b);
          });
        }
      };
    });
    document.querySelectorAll("[data-sw]").forEach(function (td) {
      td.onclick = function () {
        var k = td.getAttribute("data-sw");
        var on = td.textContent === "停止";
        td.textContent = on ? "启动" : "停止";
        td.className = on ? "st-g" : "st-y";
        var row = td.parentNode.children;
        row[1].textContent = on ? "待机" : "运行";
        row[1].className = on ? "st-r" : "st-g";
        if (k === "belt") S.aux.belt = on ? 0 : 1;
        if (k === "dryer") S.aux.dryer = on ? 0 : 1;
        if (k.indexOf("im") === 0) { var idx = +k.slice(2) - 1; S.machines[idx].run = !on; }
        save();
      };
    });
  }

  window.PLC = {
    page: function (name) {
      injectNav(name); startClock(); bind();
      setInterval(tick, 1000);
      tick();
    }
  };
})();
