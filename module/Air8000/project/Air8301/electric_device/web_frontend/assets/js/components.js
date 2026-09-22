/* assets/js/components.js —— 由 index.html 内联脚本拆出（原行区间 3369-3427 / 3428-3527 / 8467-8483），内容未改动 */

/* =========================================================
   工具
   ========================================================= */
function cssVar(name){
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}
function numOf(el){
  return parseFloat(String(el.textContent).replace(/[^\d.-]/g, '')) || 0;
}
/* KPI 数字滚动（系统设置里可关闭，关闭后直接落值） */
function rollNumber(el, to){
  if (!el) return;
  const from = numOf(el);
  if (from === to){ el.textContent = to.toLocaleString('en-US'); return; }
  if (window.nexusNoRoll){ el.textContent = to.toLocaleString('en-US'); return; }
  const dur = 700, t0 = performance.now();
  function step(t){
    const p = Math.min((t - t0) / dur, 1);
    const e = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(from + (to - from) * e).toLocaleString('en-US');
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

/* =========================================================
   1. 背景粒子星链（颜色随主题）
   —— 偏好存在 localStorage（与系统设置同一个键），并且本模块在**所有页面**都会读它，
      所以「关」现在是全站生效；出厂默认也是关（与 UI_DEF.bg 一致）。
   —— 开启时：限帧 30fps；去掉每颗粒子的发光模糊（shadowBlur 是这堆绘制里最贵的一项）；
      标签页切到后台立即停帧，切回来自动续上。
   ========================================================= */
(function(){
  const cvs = document.getElementById('bg');
  if (!cvs) return;
  const ctx = cvs.getContext('2d');
  const UI_KEY = 'nexus-ui';
  const FPS = 30;
  let W, H, dpr, parts = [], rafId = 0, lastT = 0, running = false;
  let palette = ['#22e1ff','#8b5cf6','#2bffb0','#4f8cff'];
  let linkRGB = '80,160,255';

  /* 读/写与系统设置同一份偏好（不依赖设置页是否加载过） */
  function prefOn(){
    try {
      const raw = localStorage.getItem(UI_KEY);
      if (raw) return !!JSON.parse(raw).bg;
    } catch (e){}
    return false;                    /* 出厂默认：关 */
  }
  function prefSave(on){
    try {
      const raw = localStorage.getItem(UI_KEY);
      const o = raw ? JSON.parse(raw) : {};
      o.bg = !!on;
      localStorage.setItem(UI_KEY, JSON.stringify(o));
    } catch (e){}
  }

  function readPalette(){
    palette = [cssVar('--particle-1'), cssVar('--particle-2'), cssVar('--particle-3'), cssVar('--particle-4')];
    linkRGB = cssVar('--particle-link') || '80,160,255';
    parts.forEach(p => { p.c = palette[p.ci]; });
  }

  function init(){
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = cvs.width = innerWidth * dpr;
    H = cvs.height = innerHeight * dpr;
    cvs.style.width = innerWidth + 'px';
    cvs.style.height = innerHeight + 'px';
    const count = Math.min(Math.floor(innerWidth / 26), 68);
    parts = [];
    for (let i = 0; i < count; i++){
      const ci = (Math.random() * palette.length) | 0;
      parts.push({
        x: Math.random() * W,
        y: Math.random() * H,
        vx: (Math.random() - .5) * .28 * dpr,
        vy: (Math.random() - .5) * .28 * dpr,
        r: (Math.random() * 1.5 + .6) * dpr,
        ci: ci,
        c: palette[ci],
        a: Math.random() * .5 + .25
      });
    }
  }

  function step(){
    ctx.clearRect(0, 0, W, H);
    const linkDist = 135 * dpr;

    for (let i = 0; i < parts.length; i++){
      const p = parts[i];
      p.x += p.vx; p.y += p.vy;
      if (p.x < 0 || p.x > W) p.vx *= -1;
      if (p.y < 0 || p.y > H) p.vy *= -1;
    }

    for (let i = 0; i < parts.length; i++){
      for (let j = i + 1; j < parts.length; j++){
        const a = parts[i], b = parts[j];
        const dx = a.x - b.x, dy = a.y - b.y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < linkDist){
          const alpha = (1 - d / linkDist) * .16;
          ctx.strokeStyle = 'rgba(' + linkRGB + ',' + alpha + ')';
          ctx.lineWidth = .7 * dpr;
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.stroke();
        }
      }
    }

    for (const p of parts){
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = p.c;
      ctx.globalAlpha = p.a;
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }

  /* 限帧：30fps 足够表现，绘制量减半。用时间戳判断，不依赖帧回调频率 */
  function frame(t){
    rafId = 0;
    if (!running) return;
    if (lastT && t - lastT < 1000 / FPS - 1){ rafId = requestAnimationFrame(frame); return; }
    lastT = t;
    step();
    rafId = requestAnimationFrame(frame);
  }
  function start(){
    if (running) return;
    running = true;
    window.nexusBgOff = false;      /* nexusBgOff 保留：老代码/开关用它判断当前是否关闭 */
    lastT = 0;
    if (!rafId) rafId = requestAnimationFrame(frame);
  }
  function stop(){
    running = false;
    window.nexusBgOff = true;
    if (rafId){ cancelAnimationFrame(rafId); rafId = 0; }
    ctx.clearRect(0, 0, W, H);
  }

  readPalette();
  init();
  window.nexusBgOff = !prefOn();
  if (prefOn()) start();

  addEventListener('resize', () => { init(); if (running) step(); });
  window.addEventListener('themechange', readPalette);

  /* 切到后台立即停帧，回到前台（且偏好为开）再续上 */
  document.addEventListener('visibilitychange', function(){
    if (document.hidden){
      if (running){ running = false; if (rafId){ cancelAnimationFrame(rafId); rafId = 0; } }
    } else if (prefOn() && !running){
      start();
    }
  });

  /* 供系统设置里的开关调用：写偏好 + 当前页立即生效（其它页下次加载生效） */
  window.nexusBgSet = function(on){
    prefSave(on);
    if (on) start(); else stop();
  };
})();

/* 数字滚动已并入 KPI 渲染（renderKpi），见第 6.2 节 */

/* =========================================================
   10. Toast
   ========================================================= */
const toastWrap = document.getElementById('toastWrap');
function toast(msg, isErr){
  const el = document.createElement('div');
  el.className = 'toast' + (isErr ? ' err' : '');
  el.textContent = msg;
  toastWrap.appendChild(el);
  setTimeout(() => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 420);
  }, isErr ? 3200 : 2200);
}
/* 仅用于失败提示：操作成功不弹任何提示 */
function toastErr(msg){ toast(msg, true); }


/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */

/* 量出单行高度（含下外边距）：行样式固定，探针量一次即可推算每页条数
   html 可以是字符串，也可以直接给一个已构建好的行元素（比如带 rich 样式的告警行），
   给元素时沿用它自己的类名，避免把行套进行里导致量出的高度翻倍 */
function probeRowHeight(box, className, html){
  const isEl = html && html.nodeType === 1;
  const probe = isEl ? html : document.createElement('div');
  if (!isEl){
    probe.className = className;
    probe.innerHTML = html;
  }
  probe.style.cssText = 'position:absolute;left:-9999px;top:0;width:100%;visibility:hidden;pointer-events:none';
  box.appendChild(probe);
  const h = probe.getBoundingClientRect().height +
            (parseFloat(getComputedStyle(probe).marginBottom) || 0);
  box.removeChild(probe);
  return h;
}

function bindSearch(inputId, clearId, onInput){
  const input = document.getElementById(inputId);
  if (!input) return;
  const box = input.closest('.list-search');
  const sync = () => box.classList.toggle('has-text', input.value.length > 0);

  input.addEventListener('input', () => {
    onInput(input.value);
    sync();
  });
  const clear = document.getElementById(clearId);
  if (clear) clear.addEventListener('click', () => {
    onInput('');
    input.value = '';
    sync();
    input.focus();
  });
}
