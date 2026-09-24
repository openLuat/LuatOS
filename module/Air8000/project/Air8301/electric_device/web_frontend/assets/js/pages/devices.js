/* assets/js/pages/devices.js —— 由 index.html 内联脚本拆出（原行区间 4023-4494 / 7262-8466），内容未改动 */
/* =========================================================
   6.2 设备列表
   ========================================================= */
/* =========================================================
   6.3 列表按可用高度自适应（不出现滚动条）
   ========================================================= */
/* probeRowHeight() 已移到公共层（多页面下别的页面也要用） */

/* 行模板，供探针测量每页条数使用（状态文案取最长的一档：在线 · 严重告警） */
const DEV_ROW_PROBE =
  '<span class="dot ok"></span>' +
  '<div class="dev-info"><div class="dev-name">W</div><div class="dev-meta">W</div></div>' +
  '<div class="dev-val ok">在线 · 严重告警</div>';

/* ALERT_ROW_PROBE 已移到 pages/alerts.js */

function deviceRow(d, clickable){
  const row = document.createElement('div');
  row.className = 'dev-row' + (clickable ? '' : ' is-static');
  /* 一个标签同时说清两条轴：在线 · 无告警 / 在线 · 告警 / 离线 · 失联 */
  row.innerHTML =
    '<span class="dot ' + devTone(d) + '"></span>' +
    '<div class="dev-info">' +
      '<div class="dev-name">' + d.id + '</div>' +
      '<div class="dev-meta">' + d.zone + ' · ' + d.area + ' · ' + netTagText(d.netType) + '</div>' +
    '</div>' +
    '<div class="dev-val ' + devTone(d) + '">' + devStateText(d) + '</div>';
  /* 行会被复用（见 renderDevices 的增量更新）：点击时按 id 取当前最新数据，
     避免复用行里闭包捕获的还是上一轮刷新的旧对象 */
  if (clickable) row.addEventListener('click', () => openDeviceView(freshDev(d), 'basic'));
  return row;
}

/* 按 id 取当前最新的设备对象（增量渲染后行对象可能复用，数据对象却已换代） */
function freshDev(d){
  const list = (typeof curData === 'function' ? curData().devices : null) || [];
  return list.find(x => x.id === d.id) || d;
}

/* qualityOf() 已移到公共层 api.js（地图页也要用） */

/* 设备列表表格：表头 / 行模板 */
const DEV_SORT_ICON =
  '<svg class="th-ico" viewBox="0 0 10 14" aria-hidden="true">' +
    '<path class="up" d="M5 1 8.4 5.4H1.6z"/>' +
    '<path class="down" d="M5 13 1.6 8.6h6.8z"/>' +
  '</svg>';

/* 可排序列：顺序须与表格第 1~5 列一一对应（末列「操作」不参与排序） */
const DEV_SORT_COLS = [
  { key:'id',        label:'设备号' },
  { key:'area',      label:'位置' },
  { key:'status',    label:'状态' },
  { key:'quality',   label:'通信质量' },
  { key:'heartbeat', label:'最近上报' }
];

function devSortTh(col){
  const dir = state.devSort === col.key ? state.devSortDir : '';
  return '<button class="th-sort" data-sort="' + col.key + '"' +
         (dir ? ' data-dir="' + dir + '"' : '') +
         ' title="按「' + col.label + '」排序">' +
         '<span>' + col.label + '</span>' + DEV_SORT_ICON +
         '</button>';
}

function devTableHead(){
  return DEV_SORT_COLS.map(devSortTh).join('') + '<span>操作</span>';
}

/* 状态排序权重：离线·失联 → 在线·告警 → 在线·无告警（由异常到正常） */
const TONE_RANK = { off: 0, alarm: 1, ok: 2 };
const toneRank = d => (TONE_RANK[devTone(d)] != null ? TONE_RANK[devTone(d)] : 9);

/* 按表头排序取排序副本（sort 是稳定的，同值时保持原有设备顺序） */
function sortDevices(rows){
  const key = state.devSort;
  if (!key) return rows;
  const dir = state.devSortDir === 'desc' ? -1 : 1;

  return rows.slice().sort((a, b) => {
    /* 字符串列：设备 ID 按数字段自然排序，位置按中文拼音 */
    if (key === 'id') return dir * a.id.localeCompare(b.id, 'en', { numeric: true });
    if (key === 'area'){
      return dir * (a.zone + a.area).localeCompare(b.zone + b.area, 'zh-Hans-CN');
    }
    let va, vb;
    if (key === 'status'){ va = toneRank(a); vb = toneRank(b); }
    /* 信号排序：先按分级（4 档），再按原值 —— 避免 4G 的 99（无信号）被排到最前 */
    else if (key === 'quality'){ va = qualityOf(a).lv * 100 + a.snr; vb = qualityOf(b).lv * 100 + b.snr; }
    else { va = a.hbOffset || 0; vb = b.hbOffset || 0; }
    return (va - vb) * dir;
  });
}

/* 点击表头：首次按升序，再次点击同一列切换为降序 */
function toggleDevSort(key){
  if (state.devSort === key){
    state.devSortDir = state.devSortDir === 'asc' ? 'desc' : 'asc';
  } else {
    state.devSort = key;
    state.devSortDir = 'asc';
  }
  state.devPage = 1;
  renderDevices(curData());
}

const DEV_TABLE_PROBE =
  '<span class="dt-id">W</span>' +
  '<span class="dt-cell">W</span>' +
  '<span class="dt-cell dt-flex"><span class="dev-val ok">在线 · 严重告警</span></span>' +
  '<span class="dt-cell dt-flex"><span class="q-bar" data-lv="4"><i></i><i></i><i></i><i></i></span><span class="q-text">优秀</span></span>' +
  '<span class="dt-cell">W</span>' +
  '<span class="dt-ops"><button class="mini-btn">详情</button><button class="mini-btn">指令</button></span>';

function deviceTableRow(d, clickable){
  const q = qualityOf(d);
  const row = document.createElement('div');
  row.className = 'dev-row-t' + (clickable ? '' : ' is-static');
  row.innerHTML =
    '<span class="dt-id">' + d.id + '</span>' +
    '<span class="dt-cell">' + d.zone + ' · ' + d.area + '</span>' +
    '<span class="dt-cell dt-flex"><span class="dev-val ' + devTone(d) + '">' + devStateText(d) + '</span></span>' +
    '<span class="dt-cell dt-flex">' +
      /* 联网方式（Tag 781）短标签：4G / WiFi / 以太网 / 未上报 */
      '<span class="net-tag" data-net="' + (d.netType || 0) + '">' + netTagText(d.netType) + '</span>' +
      '<span class="q-bar" data-lv="' + q.lv + '" style="--qc:' + q.color + '"><i></i><i></i><i></i><i></i></span>' +
      '<span class="q-text">' + q.text + '</span>' +
    '</span>' +
    '<span class="dt-cell">' + hbRelText(d) + '</span>' +
    (clickable
      ? '<span class="dt-ops">' +
          '<button class="mini-btn" data-op="detail">详情</button>' +
          '<button class="mini-btn" data-op="cmd">指令</button>' +
        '</span>'
      : '<span class="dt-ops"><span class="dt-static" title="在「设备管理」中查看详情与下发指令">—</span></span>');

  if (!clickable) return row;

  row.addEventListener('click', () => openDeviceView(freshDev(d), 'basic'));
  row.querySelector('[data-op="detail"]').addEventListener('click', e => {
    e.stopPropagation();
    openDeviceView(freshDev(d), 'basic');
  });
  row.querySelector('[data-op="cmd"]').addEventListener('click', e => {
    e.stopPropagation();
    openDeviceView(freshDev(d), 'control');
  });
  return row;
}

/* 面板宽度够宽时用表格（带表头与多列），窄面板沿用紧凑行 */
const TABLE_MIN_WIDTH = 720;

/* =========================================================
   列宽自适应
   表头与每个数据行都是各自独立的 grid 容器，只有写入同一份列宽模板
   才能保证纵向对齐。做法：先按 max-content 量出各列内容的自然宽度，
   再用「水位线」把剩余空间补给内容较窄的列——低于水位的列补到水位，
   高于水位的列保持自身宽度，从而让各列宽度尽量接近且都不窄于内容。
   ========================================================= */
const DEV_TABLE_COLS = 6;
const DEV_TABLE_SEAM = 2;   /* 行左右各 1px 边框，留出余量避免横向溢出 */

function balanceDeviceColumns(list){
  const grids = Array.from(list.children).filter(
    el => el.classList.contains('dev-thead') || el.classList.contains('dev-row-t')
  );
  if (!grids.length) return;

  const cs = getComputedStyle(grids[0]);
  const gap = parseFloat(cs.columnGap) || 0;
  const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);

  /* 面板不在当前视图时宽度为 0，此时沿用 CSS 里的兜底列宽 */
  const avail = list.clientWidth - padX - DEV_TABLE_SEAM - gap * (DEV_TABLE_COLS - 1);
  if (avail <= 0) return;

  /* 先把所有容器切成 max-content，再统一读取宽度：写读分离，期间不会触发绘制 */
  const probeTpl = 'repeat(' + DEV_TABLE_COLS + ', max-content)';
  grids.forEach(g => { g.style.gridTemplateColumns = probeTpl; });

  const need = new Array(DEV_TABLE_COLS).fill(0);
  grids.forEach(g => {
    Array.from(g.children).forEach((cell, i) => {
      if (i >= DEV_TABLE_COLS) return;
      const w = cell.getBoundingClientRect().width;
      if (w > need[i]) need[i] = w;
    });
  });

  /* 二分求水位线 L：sum(max(内容宽, L)) 恰好不超过可用宽度 */
  let lo = 0, hi = avail;
  for (let i = 0; i < 32; i++){
    const mid = (lo + hi) / 2;
    const total = need.reduce((a, w) => a + (w > mid ? w : mid), 0);
    if (total > avail) hi = mid; else lo = mid;
  }
  let widths = need.map(w => (w > lo ? w : lo));

  /* 面板过窄、内容总和超宽时整体等比收缩，宁可省略号也不出现横向溢出 */
  const total = widths.reduce((a, w) => a + w, 0);
  if (total > avail) widths = widths.map(w => w * avail / total);

  const tpl = widths.map(w => Math.floor(w) + 'px').join(' ');
  grids.forEach(g => { g.style.gridTemplateColumns = tpl; });
}

/* 设备筛选：连接轴（全部/在线/离线）+ 告警轴（是否只看告警）+ 设备 ID 模糊匹配 */
function matchDevices(data){
  const q = state.devQuery.trim().toUpperCase();
  const f = state.devFilter;                    /* all / online / offline */
  const alarmOnly = state.devAlarmOnly;         /* 只看有告警（含离线失联） */
  if (!q && f === 'all' && !alarmOnly) return data.devices;
  return data.devices.filter(d =>
    (f === 'all' || (f === 'online') === devOnline(d)) &&
    (!alarmOnly || devAlarmed(d)) &&
    (!q || d.id.toUpperCase().indexOf(q) > -1)
  );
}

/* 行的增量更新池：id → { el, sig }
   —— 定时刷新时通常只有少数几行真的变了，按签名复用 DOM，只重建变化的行 */
let devRowPool = new Map();
let devHead = null;          /* 表格模式的表头：只在「宽窄 / 排序」变化时重建 */
let devHeadSum = '';
let devEmpty = null;         /* 「无匹配设备」提示：复用同一个节点 */

/* 「最近上报」的相对文案。
   —— 注意 hbOffset 为 0 有两种含义：① 刚刚上报过（lastCt 有值）② 云端从未有过记录。
      必须用 lastCt 区分，否则"从未上报"的设备会被当成"刚刚"
      （原实现写的是 `d.hbOffset || 30`：0 被兜底成 30 秒 → timeText 算出"刚刚"）。 */
function hbRelText(d){
  if (!d) return '--';
  const hasLastCt = (typeof d.lastCt === 'number' && d.lastCt > 0);
  const hasOffset = (typeof d.hbOffset === 'number' && d.hbOffset > 0);
  if (!hasLastCt && !hasOffset) return '从未上报';
  const ts = hasLastCt ? d.lastCt : (Date.now() - d.hbOffset * 1000);
  return timeText(ts);
}

/* 行内容签名：这几项决定了一个行长什么样（表格模式还要含"最近上报"的相对时间文案） */
function devRowSig(d, wide, clickable){
  const base = [d.id, d.zone, d.area, devTone(d), devStateText(d), wide ? 1 : 0, clickable ? 1 : 0].join('|');
  if (!wide) return base;
  const q = qualityOf(d);
  return base + '|' + q.lv + '|' + q.text + '|' + hbRelText(d);
}

function renderDevices(data){
  const list = document.getElementById('deviceList');
  if (!list) return;

  const matched = sortDevices(matchDevices(data));
  const wide = list.clientWidth >= TABLE_MIN_WIDTH;

  /* ---------- 表头：只在宽窄模式或排序变化时重建 ---------- */
  const headSig = wide + '|' + (wide ? (state.devSort || '') + state.devSortDir : '');
  if (headSig !== devHeadSum){
    devHeadSum = headSig;
    if (devHead && devHead.parentNode) devHead.remove();
    devHead = null;
    if (wide){
      const thead = document.createElement('div');
      thead.className = 'dev-thead';
      thead.innerHTML = devTableHead();
      /* 表头重建时在此绑定排序点击 */
      thead.querySelectorAll('.th-sort').forEach(btn => {
        btn.addEventListener('click', () => toggleDevSort(btn.dataset.sort));
      });
      devHead = thead;
    }
  }
  if (devHead && devHead.parentNode !== list) list.insertBefore(devHead, list.firstChild);

  /* 表格模式的表头高度要从可用高度里扣掉 */
  const headH = devHead ? devHead.getBoundingClientRect().height : 0;

  /* 每页条数由面板可用高度决定：行高固定，量一次即可（面板被摘除时用兜底值） */
  const avail = list.clientHeight - headH;
  const rowH = avail > 0
    ? probeRowHeight(list, wide ? 'dev-row-t' : 'dev-row', wide ? DEV_TABLE_PROBE : DEV_ROW_PROBE)
    : 0;
  const size = rowH > 0
    ? Math.max(1, Math.floor((avail - 2) / rowH))
    : DEVICE_SPEC.pageSize;

  const pages = Math.max(1, Math.ceil(matched.length / size));
  if (state.devPage > pages) state.devPage = pages;
  if (state.devPage < 1) state.devPage = 1;

  const start = (state.devPage - 1) * size;
  const rows = matched.slice(start, start + size);
  /* 概览视图里的设备列表仅作展示，不提供进入详情的交互 */
  const clickable = detailAllowed();

  /* ---------- 行：按 id 复用，签名变了才重建（appendChild 顺带把复用的行摆到正确位置） ---------- */
  const keep = new Set();
  rows.forEach(d => {
    const sig = devRowSig(d, wide, clickable);
    let row = devRowPool.get(d.id);
    if (!row || row.sig !== sig){
      const el = wide ? deviceTableRow(d, clickable) : deviceRow(d, clickable);
      if (row && row.el && row.el.parentNode) row.el.parentNode.replaceChild(el, row.el);
      row = { el: el, sig: sig };
      devRowPool.set(d.id, row);
    }
    keep.add(d.id);
    list.appendChild(row.el);
  });
  /* 回收不在本页的行（翻页 / 筛选 / 项目切换后不留残行） */
  devRowPool.forEach((row, id) => {
    if (keep.has(id)) return;
    if (row.el && row.el.parentNode) row.el.remove();
    devRowPool.delete(id);
  });

  /* 当前页设备 → 实时拉取最新 Tag（切页 / 搜索 / 筛选后由本函数重新触发） */
  queueTags(rows.map(d => d.id));

  if (!rows.length){
    const tip = state.devQuery
      ? '未找到匹配「' + state.devQuery + '」的设备'
      : (state.devFilter !== 'all' || state.devAlarmOnly ? '当前筛选条件下没有设备' : '该项目下暂无设备');
    if (!devEmpty){
      devEmpty = document.createElement('div');
      devEmpty.className = 'act-empty';
      devEmpty.style.cssText = 'text-align:center;padding:26px 0';
    }
    devEmpty.textContent = tip;
    if (devEmpty.parentNode !== list) list.appendChild(devEmpty);
  } else if (devEmpty && devEmpty.parentNode){
    devEmpty.remove();
  }
  if (rows.length && wide){
    /* 行都挂载完成后按内容重新分配列宽（表头与各行同步写入） */
    balanceDeviceColumns(list);
  }

  /* 副标题：总数 / 筛选命中数 */

  /* 连接轴计数：在线 = 所有在线设备（含在线告警），离线同理 */
  const dc = { all: data.devices.length, online: 0, offline: 0 };
  let alarmed = 0;
  data.devices.forEach(d => {
    dc[d.online ? 'online' : 'offline']++;
    if (devAlarmed(d)) alarmed++;
  });
  Array.prototype.forEach.call(document.querySelectorAll('#panel-devices .tab'), t => {
    const b = t.querySelector('b');
    if (b) b.textContent = dc[t.dataset.dev];
  });
  /* 告警轴计数：在线告警 + 离线失联 */
  const alarmBtn = document.getElementById('devAlarmOnly');
  if (alarmBtn){
    alarmBtn.setAttribute('aria-pressed', state.devAlarmOnly ? 'true' : 'false');
    const b = alarmBtn.querySelector('b');
    if (b) b.textContent = alarmed;
  }

  const info = document.getElementById('devPageInfo');
  if (info) info.textContent = '第 ' + state.devPage + ' / ' + pages + ' 页';
  const prev = document.getElementById('devPrev');
  const next = document.getElementById('devNext');
  if (prev) prev.disabled = state.devPage <= 1;
  if (next) next.disabled = state.devPage >= pages;
}

/* 通用搜索框绑定：输入即筛选，带清空按钮 */
/* bindSearch() 已移到公共层（多页面下别的页面也要用） */

/* 设备列表：模糊搜索 */
bindSearch('devSearch', 'devClear', value => {
  state.devQuery = value;
  state.devPage = 1;
  renderDevices(curData());
});

/* 告警中心搜索绑定 已移到 pages/alerts.js（属于该页的交互） */

/* 告警历史翻页绑定 已移到 pages/alerts.js（属于该页的交互） */

/* 设备列表翻页 */
(function(){
  const prev = document.getElementById('devPrev');
  const next = document.getElementById('devNext');
  if (!prev || !next) return;
  prev.addEventListener('click', () => {
    if (state.devPage <= 1) return;
    state.devPage--;
    renderDevices(curData());
  });
  next.addEventListener('click', () => {
    state.devPage++;
    renderDevices(curData());
  });
})();

/* 面板高度变化（窗口缩放 / 视图切换 / 布局回流）时重算可见条数。
   窗口拖拽会连续触发 resize，绝大多数帧的尺寸其实没变——尺寸没变就不重排，
   只重算需要跟着尺寸走的那一项（本页就是设备列表的可见条数）。 */
let listResizeTimer = null;
let lastListBox = '';
window.addEventListener('resize', () => {
  if (listResizeTimer) clearTimeout(listResizeTimer);
  listResizeTimer = setTimeout(() => {
    const list = document.getElementById('deviceList');
    if (!list) return;
    const box = Math.round(list.clientWidth) + 'x' + Math.round(list.clientHeight);
    if (box === lastListBox) return;
    lastListBox = box;
    renderDevices(curData());
  }, 160);
});

/* 连接轴筛选标签（沿用告警中心类型标签的样式） */
document.querySelectorAll('#panel-devices .tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('#panel-devices .tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    state.devFilter = tab.dataset.dev;
    state.devPage = 1;
    renderDevices(curData());
  });
});

/* 告警轴开关：只筛「有告警（含离线失联）/ 无告警」，与连接轴叠加生效 */
(function bindDeviceAlarmToggle(){
  const btn = document.getElementById('devAlarmOnly');
  if (!btn) return;
  btn.addEventListener('click', () => {
    state.devAlarmOnly = !state.devAlarmOnly;
    btn.setAttribute('aria-pressed', state.devAlarmOnly ? 'true' : 'false');
    state.devPage = 1;
    renderDevices(curData());
  });
})();

/* =========================================================
   9. 设备全屏页（完全覆盖设备列表区域 · 详情 / 指令 两个页签）
   ========================================================= */
const deviceView = document.getElementById('deviceView');
let activeDevice = null;      /* 当前查看的设备（操作记录按设备过滤） */
let dvTab = 'basic';          /* 当前页签：basic 基本信息 / report 数据报表 / control 指令控制 */

/* 设备列表（以及覆盖其上的设备详情页）只挂在「设备管理」视图里；
   运营总览中的列表是概览卡片，仅作展示 */
const DV_DETAIL_VIEWS = ['设备管理'];
/* DV_ALERT_VIEWS() 已移到公共层（多页面下别的页面也要用） */

/* activeViewName() 已移到公共层（多页面下别的页面也要用） */

function detailAllowed(){
  return DV_DETAIL_VIEWS.indexOf(activeViewName()) > -1;
}

/* alertClickable() 已移到公共层（多页面下别的页面也要用） */

/* 状态文案与取色统一走 6.0 的 devStateText / devToneColor：
   连接与告警是两条独立的轴，不再有「第三种状态」需要判断 */

/* 主题变量取到的可能是 #hex 或 rgb()，统一转成带透明度的 rgba */
function toRgba(c, a){
  const v = String(c || '').trim();
  if (v.charAt(0) === '#'){
    let h = v.slice(1);
    if (h.length === 3) h = h.split('').map(x => x + x).join('');
    const n = parseInt(h, 16);
    return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')';
  }
  const m = v.match(/[\d.]+/g);
  return m ? 'rgba(' + m[0] + ',' + m[1] + ',' + m[2] + ',' + a + ')' : v;
}

/* 卡头状态胶囊：文字 + 同色系半透明底 */
function setDvState(id, text, colorVar){
  const el = document.getElementById(id);
  if (!el) return;
  const c = cssVar(colorVar);
  el.textContent = text;
  el.style.color = c;
  el.style.background = 'color-mix(in srgb, ' + c + ' 15%, transparent)';
  el.style.borderColor = 'color-mix(in srgb, ' + c + ' 38%, transparent)';
}

/* hbText() 已移到公共层 api.js（地图页也要用） */

/* =========================================================
   9.1b 详情页的数据保鲜（实时值 + 定期刷新）
   —— 现状问题：详情页的数值只来自「打开那一刻」的内存快照，
      之后无论列表怎么刷新，详情页都不会变（数据看似"卡住了"）：
        · 点开时没有任何请求；
        · 列表那套 60s 项目刷新只重绘列表（renderAllViews → renderDevices），
          没有详情页的重绘钩子；
        · 而且每次项目刷新会用**新对象**重建 data.devices（字段是拷过去的），
          activeDevice 会因此"脱钩"，就算数据更新了也落不到详情页上。
      这里补齐三件事：
        ① 打开即拉一次该设备的实时 Tag（force 忽略列表那套 65s 新鲜度节流）；
        ② 停留在详情页期间每 60 秒续拉一次（设备周期上报 60s，1 次/分钟在平台限额内；
           周期 Tag 一个报文就带回 799/265/800/781/782 + 设备上报的经纬度 512/513）；
        ③ 实时队列把数据落地后回调 refreshOpenDetail() 自动重绘，画面跟着变。
   ========================================================= */
let dvLiveTimer = null;
const DV_LIVE_MS = 60000;

/* 列表刷新会重建设备对象：按 id 把 activeDevice 重新指回当前那份 */
function syncActiveDevice(){
  if (!activeDevice) return null;
  const list = (typeof curData === 'function' ? curData().devices : null) || [];
  const cur = list.find(x => x.id === activeDevice.id);
  if (cur && cur !== activeDevice) activeDevice = cur;
  return activeDevice;
}

/* 拉一次当前设备的实时值（force=true 时忽略 65s 新鲜度） */
function refreshOpenDevice(force){
  const d = syncActiveDevice();
  if (!d) return;
  if (typeof queueTags === 'function') queueTags([d.id], force !== false);
}

/* 供 api.js 的实时 Tag 队列在数据落地后回调：详情正开着这台设备就重绘 */
function refreshOpenDetail(id){
  if (!activeDevice || !deviceView || !deviceView.classList.contains('show')) return;
  if (id && activeDevice.id !== id) return;
  if (dvTab === 'report') return;      /* 报表页签重绘会重跑历史查询，不在这里自动打 */
  syncActiveDevice();
  renderDeviceView(dvTab);
}

function startDvLive(){
  stopDvLive();
  dvLiveTimer = setInterval(function(){
    if (document.hidden) return;                                    /* 后台不请求 */
    if (!deviceView || !deviceView.classList.contains('show')) return;
    refreshOpenDevice(true);
  }, DV_LIVE_MS);
}
function stopDvLive(){
  if (dvLiveTimer){ clearInterval(dvLiveTimer); dvLiveTimer = null; }
}

/* ---------- 打开 / 关闭 ---------- */
function openDeviceView(d, tab){
  if (!d || !deviceView){
    toastErr('打开设备详情失败：设备数据缺失');
    return;
  }
  activeDevice = d;
  renderDeviceView(tab || 'basic');
  deviceView.classList.add('show');
  /* 打开即现拉一次该设备的实时值，并开启停留期间的定期刷新（见 9.1b） */
  refreshOpenDevice(true);
  startDvLive();
}

function closeDeviceView(){
  if (!deviceView || !deviceView.classList.contains('show')) return;
  deviceView.classList.remove('show');
  stopDvLive();                       /* 详情关闭即停止定期刷新 */
}

/* ---------- 页签切换 ---------- */
const DV_PAGES = { basic:'dvPageBasic', report:'dvPageReport', control:'dvPageControl' };

function setDvTab(name){
  dvTab = DV_PAGES[name] ? name : 'basic';
  document.querySelectorAll('.dv-tab').forEach(t => {
    t.classList.toggle('active', t.dataset.dv === dvTab);
  });
  Object.keys(DV_PAGES).forEach(k => {
    const el = document.getElementById(DV_PAGES[k]);
    if (el) el.classList.toggle('hide', k !== dvTab);
  });
  const sc = deviceView && deviceView.querySelector('.dv-scroll');
  if (sc) sc.scrollTop = 0;
  /* 报表画布在隐藏容器里量不到尺寸，切到该页签时按当前条件重绘 */
  if (dvTab === 'report' && activeDevice) renderDvReport(activeDevice);
}

document.querySelectorAll('.dv-tab').forEach(t => {
  t.addEventListener('click', () => setDvTab(t.dataset.dv));
});
document.getElementById('dvBack').addEventListener('click', closeDeviceView);
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeDeviceView();
});

/* ---------- 整页渲染 ---------- */
function renderDeviceView(tab){
  const d = activeDevice;
  if (!d) return;
  setDvTab(tab || dvTab);

  document.getElementById('dvCrumb').textContent = d.id;
  document.getElementById('dvId').textContent = d.id;

  /* 胶囊同时表达两条轴：在线 · 无告警 / 在线 · 告警 / 离线 · 失联 */
  const badge = document.getElementById('dvStatus');
  const c = devToneColor(d);
  badge.textContent = devStateText(d);
  badge.style.color = c;
  badge.style.background = 'color-mix(in srgb, ' + c + ' 16%, transparent)';
  badge.style.borderColor = 'color-mix(in srgb, ' + c + ' 40%, transparent)';

  renderDvMetrics(d);
  renderDvKv(d);
  renderDvEvents(d);
  renderDvPower(d);
  renderDvPeriod(d);
  renderLog();
}

/* ---------- 指标卡 ----------
   四张卡按「数据性质」配不同控件，不再一律用进度条（进度条对枚举量/时间量没有意义）：
     · 实际电压 / 设定电压 —— 连续量：量程条（0 ~ VOLTAGE_MAX），
       并在条上标出另一路电压的位置，一眼看出"实际 vs 设定"的差
     · 工作状态 —— 枚举量：状态徽标（运行中 / 已关机 / 未同步），不用进度条
     · 最近上报 —— 时间量：完整「年月日时分秒」+ 新鲜度（距今多久 / 已失联） */
function renderDvMetrics(d){
  const box = document.getElementById('dvMetrics');
  if (!box) return;
  const off = !d.online;
  const MAX = App.config.BIZ.VOLTAGE_MAX || 6000;
  const pos = v => Math.max(0, Math.min(100, (Number(v) || 0) / MAX * 100));
  const loadV = Number(d.load) || 0, setV = Number(d.temp) || 0;
  const over = setV > 0 && loadV > setV;                   /* 实际高于设定：值得提醒 */
  const ws = d.workStatus;
  const stTone = ws === 1 ? 'ok' : (ws === 0 ? 'off' : (ws === 255 ? 'warn' : 'muted'));
  const stText = off ? '离线' : (App.utils.workStatusText(ws) || '--');
  const age = (typeof d.hbOffset === 'number') ? d.hbOffset : null;
  const freshTone = off ? 'off' : (age === null ? 'muted' : (age < 120 ? 'ok' : 'warn'));
  const freshText = off ? '已失联'
                  : (age === null ? '无上报记录'
                  : (age < 60 ? '刚刚上报（' + age + ' 秒前）' : hbText(age)));
  const icon = p => '<svg viewBox="0 0 24 24"><path d="' + p + '"/></svg>';

  /* 量程条：底轨铺满量程 + 当前值填充 + 另一路电压的刻度标记 */
  function gauge(value, other, tone, otherName){
    const mk = (!off && other > 0 && other <= MAX)
      ? '<u class="dv-gauge-mark" style="left:' + pos(other).toFixed(2) + '%" title="' +
          otherName + ' ' + Math.round(other) + ' V"></u>'
      : '';
    return '<div class="dv-gauge ' + (off ? 'is-off' : tone) + '">' +
             '<i class="dv-gauge-fill" style="width:' + (off ? 0 : pos(value)).toFixed(2) + '%"></i>' +
             mk +
           '</div>';
  }

  box.innerHTML = [
    /* ① 实际电压 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>实际电压</span>' + icon('M4 19h16M7 19V9M12 19V5M17 19v-6') + '</div>' +
      '<div class="dv-metric-value' + (over ? ' is-warn' : '') + '"><b>' + (off ? '--' : Math.round(loadV)) + '</b><em>V</em></div>' +
      gauge(loadV, setV, over ? 'warn' : 'ok', '设定') +
      '<div class="dv-metric-foot"><span>量程 0–' + MAX + ' V</span><span>' +
        (off ? 'Tag 799' : '设定 ' + Math.round(setV) + ' V') + '</span></div>' +
    '</div>',
    /* ② 设定电压 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>设定电压</span>' + icon('M12 3v10.6a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2z') + '</div>' +
      '<div class="dv-metric-value"><b>' + Math.round(setV) + '</b><em>V</em></div>' +
      gauge(setV, loadV, 'violet', '实际') +
      '<div class="dv-metric-foot"><span>量程 0–' + MAX + ' V</span><span>Tag 800</span></div>' +
    '</div>',
    /* ③ 工作状态 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>工作状态</span>' + icon('M12 2v3.5M12 18.5V22M4.2 4.2l2.5 2.5M17.3 17.3l2.5 2.5M2 12h3.5M18.5 12H22M4.2 19.8l2.5-2.5M17.3 6.7l2.5-2.5') + '</div>' +
      '<div class="dv-state ' + stTone + '"><i></i>' + stText + '</div>' +
      '<div class="dv-metric-foot"><span>Tag 265</span><span>1=开机 · 0=关机 · 255=未同步</span></div>' +
    '</div>',
    /* ④ 最近上报 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>最近上报</span>' + icon('M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 7.6V12l3 2') + '</div>' +
      '<div class="dv-metric-value is-time"><b>' + hbTimeText(d) + '</b></div>' +
      '<div class="dv-fresh ' + freshTone + '"><i></i>' + freshText + '</div>' +
      '<div class="dv-metric-foot"><span>Tag 799</span><span>周期 60s · 变化即时上报</span></div>' +
    '</div>'
  ].join('');
}

/* ---------- 设备参数 ---------- */
function renderDvKv(d){
  const box = document.getElementById('dvKv');
  if (!box) return;
  const prj = curProject();

  const rows = [
    ['所属项目', prj.name],
    ['项目编号', prj.code],
    ['设备型号', d.model],
    ['设备号 IMEI', d.id],
    ['ICCID', d.iccid !== undefined ? String(d.iccid) : '--'],
    ['安装位置', d.zone + ' · ' + d.area],
    ['接入协议', 'AirCloud · TCP 长连接'],
    /* Tag 781/782：设备端新增的联网方式与信号强度（统一 0~31 刻度） */
    ['联网方式', netTagText(d.netType)],
    ['信号强度', d.hasSignal ? (d.snr + '/31 · ' + qualityOf(d).text) : '未上报'],
    ['固件版本', d.version !== undefined ? String(d.version) : '--'],
    ['上报周期', d.period + ' s'],
    ['工作状态（265）', App.utils.workStatusText(d.workStatus)],
    ['连接状态', devConnText(d)],
    ['告警状态', devAlarmText(d)],
    ['开关机状态', d.power === 'off' ? '已关机（265=0）' : '已开机（265=1）'],
    /* 同上：给出实际上报时间；离线时补一句状态（失联设备更需要知道是什么时候断的） */
    ['最近上报', hbTimeText(d) + (d.online ? '' : ' · 已失联')]
  ];

  box.innerHTML = rows.map(r => '<div><span>' + r[0] + '</span><b>' + r[1] + '</b></div>').join('');
}

/* ---------- 相关事件 ---------- */
function renderDvEvents(d){
  const box = document.getElementById('dvEvents');
  if (!box) return;

  const evts = curData().alerts.filter(a => a.deviceId === d.id).slice(0, 10);
  const cnt = document.getElementById('dvEventCount');
  if (cnt) cnt.textContent = evts.length + ' 条';

  if (!evts.length){
    box.innerHTML = '<div class="act-empty">该设备近期无异常事件</div>';
    return;
  }
  box.innerHTML = evts.map(a =>
    '<div class="dv-event ' + a.level + '">' +
      '<div class="dv-event-main">' +
        '<div class="dv-event-title">' + a.title + '</div>' +
        '<div class="dv-event-meta">' + a.meta + '</div>' +
      '</div>' +
      '<span class="dv-event-time">' + timeText(a.ts) + '</span>' +
    '</div>'
  ).join('');
}

/* =========================================================
   9.1 功能块一：开关机控制
   —— 显示当前开关机状态，并提供开机 / 关机 / 重启三个动作
   ========================================================= */
/* 动作元信息：tone 决定按钮悬停配色，state 为执行后设备所处状态 */
const DV_ACTION_META = {
  '开机': { state:'on',  tone:'ok',     desc:'协议 265=1：启动电场发生器输出' },
  '关机': { state:'off', tone:'danger', desc:'协议 265=0：停止输出，云端链路保持' }
};

/* 开关机状态是独立的第三条维度：关机必然离线，但离线不等于关机
   （链路故障时设备仍在运行，所以不能拿连接状态反推电源状态） */
function powerStateOf(d){
  return d.power === 'off' ? 'off' : 'on';
}

function renderDvPower(d){
  const box = document.getElementById('dvPowerBtns');
  if (!box) return;

  const state = powerStateOf(d);
  const on = state === 'on';

  /* 卡头状态胶囊 */
  setDvState('dvPowerState', d.busy ? '指令执行中' : (on ? '已开机' : '已关机'),
             d.busy ? '--cyan' : (on ? '--green' : '--red'));

  const val = (id, text) => { const el = document.getElementById(id); if (el) el.textContent = text; };
  val('dvPowerLoad', on ? d.load + ' V' : '--');
  val('dvPowerTemp', (d.temp || 0) + ' V');
  val('dvPowerSnr', d.online ? (d.power === 'off' ? '已关机' : '运行中') : '未同步');
  val('dvPowerHb', d.online ? hbText(d.hbOffset) : '已失联');

  box.innerHTML = '';
  (d.actions || []).forEach(name => {
    const meta = DV_ACTION_META[name];
    if (!meta) return;
    const btn = document.createElement('button');
    btn.className = 'dv-act' + (meta.state === state ? ' current' : '');
    btn.dataset.tone = meta.tone;
    btn.dataset.action = name;
    btn.title = meta.desc;
    btn.textContent = name;
    btn.disabled = !!d.busy;
    btn.addEventListener('click', () => runPowerAction(d, name, btn));
    box.appendChild(btn);
  });
}

function runPowerAction(dev, action, btn){
  const data = curData();
  const d = data.devices.find(x => x.id === dev.id) || dev;

  if (d.busy){
    toastErr('操作失败：' + d.id + ' 正在执行其他指令，请稍后重试');
    return;
  }
  /* 关机需要链路在线（离线不一定是关机，提示要分清） */
  if (action !== '开机' && !d.online){
    const why = d.power === 'off' ? '设备已关机' : '设备离线（AirCloud 无最近上报）';
    logAction(d, action, false, why + '，指令未送达');
    renderLog();
    setDvExec('失败', why + '，指令未能送达', -1);
    toastErr('操作失败：' + d.id + ' ' + why + (d.power === 'off' ? '，请先开机' : '，请检查链路'));
    return;
  }

  setDvPowerBusy(true);
  if (btn) btn.classList.add('running');
  /* 真实下发：send_cmd tag=19（嵌套 265 工作状态） */
  sendControl(d, action, buildControlValue(action === '开机' ? 1 : 0, undefined), function(){
    applyPowerEffect(d, action);
  });
  setTimeout(function(){
    setDvPowerBusy(false);
    if (btn) btn.classList.remove('running');
    renderDevices(data);
    if (activeDevice && activeDevice.id === d.id) renderDeviceView(dvTab);
  }, 1800);
}

function setDvPowerBusy(busy){
  const box = document.getElementById('dvPowerBtns');
  if (box) box.querySelectorAll('.dv-act').forEach(b => { b.disabled = busy; });
}

function applyPowerEffect(d, action){
  if (action === '关机'){
    /* 关机（265=0）：停止电场输出，实际电压归零；云端链路保持在线 */
    d.power = 'off';
    d.alarm = 'none';
    d.load = 0;
    d.hbOffset = 5;
  } else {
    /* 开机（265=1）：启动输出，实际电压向设定值靠拢，告警解除 */
    d.power = 'on';
    d.online = true;
    d.alarm = 'none';
    d.load = d.temp || 0;
    d.hbOffset = 5;
  }
}

/* =========================================================
   9.2 功能块二：设定电压下发（Tag 800）
   —— 显示当前设定电压，可从预设中选择或直接输入，再下发
      （经 send_cmd tag=19 的嵌套子 TLV 下发到设备）
   ========================================================= */
const DV_PERIOD_PRESETS = [1000, 2000, 3500, 5000, 6000];

function renderDvPeriod(d){
  /* 卡头状态胶囊显示当前设定电压 */
  setDvState('dvPeriodState',
             d.busy ? '下发中…' : '当前 ' + (d.temp || 0) + ' V',
             d.busy ? '--cyan' : '--violet');

  /* 输入框与预设 chip 同步（正在输入时不覆盖用户输入） */
  const input = document.getElementById('dvPeriodInput');
  if (input && document.activeElement !== input) input.value = (d.temp || App.config.BIZ.DEFAULT_SET_VOLTAGE);
  syncPeriodChips();
}

function syncPeriodChips(){
  const input = document.getElementById('dvPeriodInput');
  const val = input ? Math.round(+input.value) : NaN;
  document.querySelectorAll('#dvPeriodChips .dv-chip').forEach(c => {
    c.classList.toggle('active', Math.round(+c.dataset.sec) === val);
  });
}

function setDvPeriodBusy(busy){
  const chips = document.getElementById('dvPeriodChips');
  const input = document.getElementById('dvPeriodInput');
  const apply = document.getElementById('dvPeriodApply');
  if (chips) chips.querySelectorAll('.dv-chip').forEach(c => { c.disabled = busy; });
  if (input) input.disabled = busy;
  if (apply) apply.disabled = busy;
}

/* 构造 tag=19「控制命令」的 value（协议 8.3.2 控制命令 / 10.2 下行 TLV 选用规则）
   —— 约定：value 是**顶层裸数组的 JSON 字符串**，数组元素形如
        [{"field_meaning":265,"data_type":0,"value":1}]
      · field_meaning：TLV 字段含义（265 工作状态 / 800 设定电压，均为「自主补充」字段）
      · data_type    ：0 = 整数
      · value        ：字段值（265：1=开机 / 0=关机；800：0~6000 V）
      设备端 protocol_app.handle_aircloud_msg 收到 Type=19 后，从 value 里取出
      field=265/800 的子项，发布 CTRL_CMD_RECV 交给 business_app 执行（再经 UART 下发给高压板）。
   —— 原来的写法是 { "265": 1 } 这种「以 tag 为键的对象」：平台按 Type=19 封装后，
      设备端拿到的 value 不是可解析的子 TLV（excloud 解不出 265/800），
      ctrl_fields 为空 → 设备收到但不执行（这正是"报文已下发但设备没动作"的原因）。
   —— 与合宙 excloud 扩展库 demo 约定一致（Air8782 泵控项目同写法，已实测可用）。 */
function buildControlValue(workStatus, setVoltage){
  const items = [];
  if (workStatus !== undefined && workStatus !== null){
    items.push({ field_meaning: App.config.TAGS.WORK_STATUS, data_type: 0, value: workStatus });
  }
  if (setVoltage !== undefined && setVoltage !== null){
    items.push({ field_meaning: App.config.TAGS.SET_VOLTAGE, data_type: 0, value: setVoltage });
  }
  return JSON.stringify(items);
}

/* 真实下发控制命令（send_cmd），统一走执行监控与操作记录 */
function sendControl(d, label, value, onOk, tag){
  const data = curData();
  if (!d.online){
    const why = '设备离线（AirCloud 无最近上报）';
    logAction(d, label, false, why + '，指令未送达');
    renderLog();
    setDvExec('失败', why, -1);
    toastErr('下发失败：' + d.id + ' ' + why);
    return Promise.resolve();
  }
  setDvExec('执行中', '正在下发「' + label + '」…', 0);
  return App.http.post(App.config.API.SEND_CMD, {
    client_id: d.id,
    tag: (tag === undefined ? App.config.BIZ.CONTROL_TAG : tag),
    value: value,
    protocol: 0
  }).then(function(res){
    if (onOk) onOk();
    const r = (res && typeof res.value === 'string') ? res.value : '操作成功';
    logAction(d, label, true, r);
    setDvExec('已完成', '「' + label + '」已下发（平台已受理）', 100);
    toast(label + '：' + r);
    renderDevices(data);
  }).catch(function(e){
    logAction(d, label, false, e.message);
    setDvExec('失败', e.message, -1);
    toastErr('下发失败：' + e.message);
  }).then(function(){
    if (activeDevice && activeDevice.id === d.id) renderDeviceView(dvTab);
  });
}

function runPeriodApply(value){
  const dev = activeDevice;
  if (!dev){ toastErr('下发失败：未选择设备'); return; }

  const data = curData();
  const d = data.devices.find(x => x.id === dev.id) || dev;

  if (d.busy){
    toastErr('操作失败：' + d.id + ' 正在执行其他指令，请稍后重试');
    return;
  }
  if (value < App.config.BIZ.VOLTAGE_MIN || value > App.config.BIZ.VOLTAGE_MAX){
    toastErr('下发失败：设定电压需在 0 ~ 6000 V 之间');
    return;
  }
  if (value === d.temp){
    toastErr('下发失败：' + value + ' V 与当前设定电压相同');
    return;
  }

  d.busy = true;
  setDvPeriodBusy(true);
  sendControl(d, '设定电压 ' + value + 'V', buildControlValue(undefined, value), function(){
    d.temp = value;
    if (d.power === 'on') d.load = value;
  });
  setTimeout(function(){
    d.busy = false;
    setDvPeriodBusy(false);
    renderDevices(data);
    if (activeDevice && activeDevice.id === d.id) renderDeviceView(dvTab);
  }, 1800);
}

/* =========================================================
   9.3 / 9.4 已按需求删除
   —— 原「设备信息」块（IMEI / ICCID / 版本 / 云端连接 展示）与
      「运维日志上报」块（send_cmd tag=25 通知设备上传日志）一并移除。
   —— 说明两点，避免以后重复踩：
      · 设备身份信息仍可在「基本信息」页签的详细信息里看到（ICCID/版本/IMEI 都在）；
      · 平台的「通知设备上传日志」信令是 tag=22，不是 25（见接口文档 send_cmd 支持的
        Tag：19 控制命令 / 21 iRTU / 1281 自定义 / 22 通知上传日志），原实现用错了。
   ========================================================= */

/* =========================================================
   9.5 执行监控（仅「指令下发」「回执确认」两个阶段）
   ========================================================= */
const DV_STEP_COUNT = 2;

function setDvExec(state, sub, pct){
  setDvState('dvExecState', state,
             pct < 0 ? '--red' : pct >= 100 ? '--green' : pct > 0 ? '--cyan' : '--muted');
  const sub2 = document.getElementById('dvExecSub');
  if (sub2) sub2.textContent = sub;

  const failed = pct < 0;
  const prog = document.getElementById('dvProgress');
  const bar = document.getElementById('dvBar');
  const pctEl = document.getElementById('dvBarPct');
  if (prog) prog.classList.toggle('fail', failed);
  if (bar) bar.style.width = (failed ? 100 : pct) + '%';
  if (pctEl) pctEl.textContent = failed ? '失败' : pct + '%';

  /* 两个阶段：已过阶段点亮、当前阶段高亮 */
  const steps = document.getElementById('dvSteps');
  if (!steps) return;
  const idx = failed ? -1 : Math.min(DV_STEP_COUNT - 1, Math.floor(pct / (100 / DV_STEP_COUNT)));
  Array.from(steps.children).forEach((el, k) => {
    el.classList.toggle('done', !failed && (pct >= 100 || k < idx));
    el.classList.toggle('active', !failed && pct < 100 && k === idx);
  });
}

function runDvProgress(label, onDone){
  const total = 1300, t0 = performance.now();
  function tick(t){
    const p = Math.min((t - t0) / total, 1);
    setDvExec('执行中', '正在下发「' + label + '」…', Math.round(p * 100));
    if (p < 1) requestAnimationFrame(tick);
    else onDone();
  }
  requestAnimationFrame(tick);
}

/* =========================================================
   9.6 操作记录
   ========================================================= */
function nowText(){
  const d = new Date(), p = n => String(n).padStart(2, '0');
  return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

function logAction(d, action, ok, note){
  actionLog.unshift({ deviceId: d.id, name: d.name, action: action, ok: ok, note: note, time: nowText() });
  if (actionLog.length > 40) actionLog.pop();
}

function renderLog(){
  const box = document.getElementById('dvLog');
  if (!box) return;
  const rows = actionLog.filter(r => activeDevice && r.deviceId === activeDevice.id);
  const cnt = document.getElementById('dvLogCount');
  if (cnt) cnt.textContent = rows.length + ' 条';

  box.innerHTML = '';
  if (!rows.length){
    box.innerHTML = '<div class="act-empty">暂无操作记录，在上方功能块中下发指令后会记录在此</div>';
    return;
  }
  rows.slice(0, 20).forEach(r => {
    const el = document.createElement('div');
    el.className = 'act-line' + (r.ok ? '' : ' fail');
    el.innerHTML =
      '<span>' + r.time + '</span>' +
      '<b>' + r.action + '</b>' +
      '<span class="act-note">' + r.note + '</span>';
    box.appendChild(el);
  });
}

/* =========================================================
   9.7 实时趋势曲线
   ========================================================= */
/* =========================================================
   9.7 折线图鼠标读数（十字线 + 数值气泡）
   —— 数据报表四张历史曲线用：鼠标移到图上 → 竖向虚线 + 采样点圆点 + 读数气泡
   —— 气泡用 DOM 而不是 canvas 文字：排版交给浏览器，样式好统一
   —— 画布 X 轴是「等距采样点」，鼠标 x 反解成最近下标即可
   —— 画布每次查询都会重建，所以监听器用事件委托挂在容器上
   ========================================================= */
/* 惰性创建气泡元素（挂在绘图区外层，外层需 position:relative） */
/* 画布内边距：绘图（drawDvChart）与鼠标读数的坐标反解共用这一处定义。
   —— 它原先定义在已删除的「实际电压趋势」代码块里，删掉后本文件就只剩引用、
      没有定义 → drawDvChart 一进函数就抛 ReferenceError，四张图全空白；
      而表格是在 requestAnimationFrame(绘图) 之前渲染的，所以表格照常有数据。 */
const RP_PAD = { l: 38, r: 12, t: 12, b: 22 };

function dvTipEl(box){
  if (!box) return null;
  for (const c of box.children) if (c.classList && c.classList.contains('dv-tip')) return c;
  const el = document.createElement('div');
  el.className = 'dv-tip';
  box.appendChild(el);
  return el;
}
/* 显示气泡：默认在光标右上，贴边自动翻转/收边，保证不出框 */
function dvTipShow(box, tip, x, y, html){
  if (!box || !tip) return;
  tip.innerHTML = html;
  tip.style.display = 'block';
  const bw = tip.offsetWidth, bh = tip.offsetHeight;
  const W = box.clientWidth, H = box.clientHeight;
  let left = x + 14, top = y - bh - 12;
  if (left + bw > W - 4) left = x - bw - 14;
  if (left < 4) left = 4;
  if (top < 4) top = y + 16;
  if (top + bh > H - 4) top = Math.max(4, H - bh - 4);
  tip.style.left = Math.round(left) + 'px';
  tip.style.top = Math.round(top) + 'px';
}
function dvTipHide(tip){ if (tip) tip.style.display = 'none'; }

/* 数据报表四张曲线：画布每次查询都会重建，所以用事件委托挂在容器上
   （mouseout 会冒泡，mouseleave 不会，故用 mouseout + relatedTarget 判断） */
(function bindRpChartHover(){
  const box = document.getElementById('rpCharts');
  if (!box) return;
  const canvasOf = e => (e.target && e.target.tagName === 'CANVAS' && e.target.dataset.chart !== undefined) ? e.target : null;
  const repaint = cvs => {
    const card = DV_REPORT_CARDS[+cvs.dataset.chart];
    if (card) drawDvChart(cvs, card);
  };
  box.addEventListener('mousemove', function(e){
    const cvs = canvasOf(e);
    if (!cvs || !dvReport) return;
    const n = dvReport.times.length;
    const r = cvs.getBoundingClientRect();
    const plotW = r.width - RP_PAD.l - RP_PAD.r;
    if (n < 2 || plotW <= 0) return;
    /* 与 drawDvChart 里的 X(i) = padL + i/(n-1)*plotW 互为反解 */
    const i = Math.round((e.clientX - r.left - RP_PAD.l) / plotW * (n - 1));
    const idx = Math.max(0, Math.min(n - 1, i));
    const y = e.clientY - r.top;
    if (idx !== cvs.__hover || Math.abs((cvs.__hoverY || 0) - y) > 2){
      cvs.__hover = idx; cvs.__hoverY = y;
      repaint(cvs);
    }
  });
  box.addEventListener('mouseout', function(e){
    const cvs = canvasOf(e);
    if (!cvs) return;
    const to = e.relatedTarget;
    if (to && cvs.contains(to)) return;          /* 仍在画布内（子节点间移动）不算离开 */
    if (typeof cvs.__hover !== 'number' || cvs.__hover < 0) return;
    cvs.__hover = -1;
    repaint(cvs);
  });
})();


/* =========================================================
   9.8 上报周期的选择与输入控件
   ========================================================= */
(function bindDvPeriod(){
  const chips = document.getElementById('dvPeriodChips');
  const input = document.getElementById('dvPeriodInput');
  const apply = document.getElementById('dvPeriodApply');
  if (!chips || !input || !apply) return;

  /* 预设值 chip：选中即填入输入框 */
  chips.innerHTML = DV_PERIOD_PRESETS.map(s =>
    '<button class="dv-chip" data-sec="' + s + '">' + s + ' V</button>').join('');

  chips.addEventListener('click', e => {
    const chip = e.target.closest('.dv-chip');
    if (!chip) return;
    input.value = chip.dataset.sec;
    syncPeriodChips();
  });

  input.addEventListener('input', syncPeriodChips);

  apply.addEventListener('click', () => {
    const v = Math.round(+input.value);
    if (isNaN(v) || v < App.config.BIZ.VOLTAGE_MIN || v > App.config.BIZ.VOLTAGE_MAX){
      toastErr('下发失败：设定电压需在 0 ~ 6000 V 之间');
      return;
    }
    runPeriodApply(v);
  });
})();

/* =========================================================
   9.5 数据报表（时间段查询 · 折线趋势 · 明细表）
   —— 全部为 list_by_tags 的真实历史记录：一条上报纸文 = 一个点，
      不做采样降频、不补点、不插值/合成；某条记录缺某个 Tag 时该点为空，
      曲线在这一段断开（如实呈现），明细表也只列真实上报过的时刻
   ========================================================= */
const DV_RANGES = {
  '1h':  { span: 3600000,   label: '近 1 小时' },
  '6h':  { span: 21600000,  label: '近 6 小时' },
  '24h': { span: 86400000,  label: '近 24 小时' },
  '7d':  { span: 604800000, label: '近 7 天' }
};

/* 报表卡片：一张图可叠多条同量纲曲线（与参考图一致） */
/* 报表卡片：全部由 list_by_tags 的真实历史记录绘制（无合成曲线）
   —— 信号强度（Tag 782）是统一 0~31 刻度，按当条记录的联网方式（Tag 781）拆成两张图：
      4G 期间的上报进「4G 信号强度」，WiFi 期间的上报进「WiFi 信号强度」，
      另一条链路就是断点（不插值、不混画）
   —— 上报间隔不再单独出图（数值仍在下方明细表与 CSV 里） */
const DV_REPORT_CARDS = [
  { title:'电压', sub:'实际电压(799) / 设定电压(800) · 单位 V', floor:0, series:[
      { label:'实际电压', color:'--cyan',   key:'load', unit:' V' },
      { label:'设定电压', color:'--violet', key:'temp', unit:' V' } ] },
  { title:'工作状态', sub:'Tag 265 · 1=开机 / 0=关机 / 255=未同步', floor:0, series:[
      { label:'工作状态', color:'--green',  key:'work', fmt:function(v){ return workLabel(v); } } ] },
  { title:'4G 信号强度', sub:'Tag 782 · 统一 0~31 刻度（4G=CSQ 原值）· 仅统计 4G 期间的上报', floor:0, emptyText:'4G 信号', series:[
      { key:'sig4', label:'4G 信号（CSQ）', color:'--cyan' } ] },
  { title:'WiFi 信号强度', sub:'Tag 782 · 统一 0~31 刻度（WiFi=RSSI 折算）· 仅统计 WiFi 期间的上报', floor:0, emptyText:'WiFi 信号', series:[
      { key:'sigwifi', label:'WiFi 信号', color:'--violet' } ] }
];

let dvRange = '6h';         /* 当前区间：预设键，或 custom（自定义） */
let dvFrom = 0, dvTo = 0;   /* 自定义区间起止时间戳 */
let dvReport = null;        /* 当前查询结果：表格与导出共用 */

/* ---------- 确定性噪声 ---------- */
function dvHashAt(seed, i){
  let h = (seed ^ 0x9e3779b9) >>> 0;
  h = Math.imul(h ^ (i | 0), 0x85ebca6b) >>> 0;
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h ^= h >>> 16;
  return (h >>> 8) / 8388608 - 1;      /* -1 ~ 1 */
}
function dvOctave(seed, x){
  const i = Math.floor(x), f = x - i;
  const a = dvHashAt(seed, i), b = dvHashAt(seed, i + 1);
  const u = f * f * (3 - 2 * f);       /* 平滑插值，避免折线出现锯齿拐点 */
  return a + (b - a) * u;
}
function dvNoise(seed, x){
  return dvOctave(seed, x) * .68 + dvOctave(seed + 977, x * 3.1) * .32;
}
const dvClamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

/* ---------- 真实历史数据（list_by_tags） ---------- */
function dvFetchHistory(d, from, to, tags, size){
  const filter = {
    aks: ['ct', 'ct'], acs: ['ge', 'le'],
    avs: [App.utils.formatLocalParam(from), App.utils.formatLocalParam(to)]
  };
  /* 走全局限频闸门：报表查询与 App 自身的 Tag 查询共用一条队列，
     平台规则是"查询频率 ≈ 上报频率"，两条查询挨着发必然被拒（实测报"请求过于频繁"）。
     闸门内自带同设备 15s 间隔与"频繁"自动退避重试，因此这里只会慢一点、不会失败 */
  return scheduleTagQuery(d.id, function(){
    return apiTags(d.id, tags, 1, size || 100, filter);
  }).then(function(res){
    const v = res.value || {};
    return {
      total: Number(v.total || 0),
      records: Array.isArray(v.records) ? v.records : []      /* 接口按 ct 降序返回 */
    };
  });
}

/* 直接用查询回来的真实记录出点：一条上报纸文 = 一个点。
   —— 不按采样间隔落桶、不补点、不做插值/合成：查询条件给多宽就覆盖多宽，
      "有多少是多少"；某条记录缺某个 Tag 时该点为空，曲线在此断开。
   —— 因为点与记录一一对应，明细表自然只会出现真实上报过的时刻（不再有空行）。 */
function dvBuildReportFromRecords(records, from, to){
  const sorted = records.slice().sort(function(a, b){
    return (App.utils.parseLocal(a.ct) || 0) - (App.utils.parseLocal(b.ct) || 0);
  });

  const times = [], load = [], temp = [], work = [], hb = [],
        net = [], sig = [], sig4 = [], sigwifi = [];

  let prevTs = null;
  sorted.forEach(function(rec){
    const ts = App.utils.parseLocal(rec.ct);
    if (!ts || ts < from || ts > to) return;

    const v7 = Number(rec['val_' + App.config.TAGS.VOLTAGE]);
    const v8 = Number(rec['val_' + App.config.TAGS.SET_VOLTAGE]);
    const v2 = Number(rec['val_' + App.config.TAGS.WORK_STATUS]);
    const vNet = Number(rec['val_' + App.config.TAGS.NETWORK_TYPE]);
    const vSig = Number(rec['val_' + App.config.TAGS.SIGNAL]);

    times.push(ts);
    load.push(isFinite(v7) ? v7 : null);
    temp.push(isFinite(v8) ? v8 : null);
    work.push(isFinite(v2) ? v2 : null);
    net.push(isFinite(vNet) ? vNet : null);
    sig.push(isFinite(vSig) ? vSig : null);
    /* 信号强度(782) 是统一 0~31 刻度，按该条记录实际走的链路（781）归到对应曲线：
       4G(1) 进「4G 信号强度」，WiFi(2) 进「WiFi 信号强度」，其它链路/未上报留空；
       4G 的 99（无信号/不可测）不进曲线，避免把纵轴拉到 99 */
    sig4.push((vNet === 1 && vSig >= 0 && vSig < 99) ? vSig : null);
    sigwifi.push((vNet === 2 && vSig >= 0 && vSig <= 31) ? vSig : null);
    /* 上报间隔 = 相邻两条真实记录的时间差 */
    hb.push(prevTs ? Math.round((ts - prevTs) / 1000) : null);
    prevTs = ts;
  });

  return {
    times: times,
    count: times.length,
    /* 最后一条真实记录时刻（明细表/CSV 的状态列用） */
    failAt: times.length ? times[times.length - 1] : 0,
    series: { load: load, temp: temp, work: work, hb: hb, net: net, sig: sig, sig4: sig4, sigwifi: sigwifi }
  };
}

/* dv2() 已移到公共层（多页面下别的页面也要用） */
/* dvDT() 在公共层 utils.js（系统设置页也要用） */

function dvFull(ts){
  const d = new Date(ts);
  return d.getFullYear() + '-' + dvDT(ts) + ':' + dv2(d.getSeconds());
}
function dvLocalInput(ts){
  const d = new Date(ts);
  return d.getFullYear() + '-' + dv2(d.getMonth() + 1) + '-' + dv2(d.getDate()) +
         'T' + dv2(d.getHours()) + ':' + dv2(d.getMinutes());
}

/* ---------- 报表渲染 ---------- */
function renderDvReport(d){
  const charts = document.getElementById('rpCharts');
  if (!charts || !d) return;

  const now = Date.now();
  let from, to, label;
  if (dvRange === 'custom'){
    from = dvFrom; to = dvTo; label = '自定义区间';
  } else {
    const cfg = DV_RANGES[dvRange] || DV_RANGES['6h'];
    to = now; from = now - cfg.span; label = cfg.label;
  }

  dvReport = null;

  /* 先建骨架：画布尺寸依赖布局，等下一帧再绘制 */
  charts.innerHTML = DV_REPORT_CARDS.map((c, i) =>
    '<div class="rp-card">' +
      '<div class="rp-card-head"><h4>' + c.title + '</h4><span>' + c.sub + '</span></div>' +
      '<div class="rp-legend">' + c.series.map(s =>
        '<span><i style="--c:' + cssVar(s.color) + '"></i>' + s.label + '</span>').join('') + '</div>' +
      '<div class="rp-plot"><canvas data-chart="' + i + '"></canvas></div>' +
    '</div>').join('');

  const meta = document.getElementById('rpMeta');
  if (meta){
    meta.textContent = d.id + ' · ' + dvDT(from) + ' ~ ' + dvDT(to);
  }

  const body = document.getElementById('rpBody');
  if (body) body.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:18px 0">正在查询真实历史数据…</td></tr>';
  const cnt = document.getElementById('rpCount');
  if (cnt) cnt.textContent = '查询中…';
  const tsub = document.getElementById('rpTableSub');
  if (tsub) tsub.textContent = label + ' · 正在查询 AirCloud 历史记录…';

  /* 真实查询：区间内取最近 100 条原始记录
     —— 100 就是平台限额（接口文档：size 建议在 [0,100] 内），有多少取多少，
        区间记录数超过限额时按限额取最近 100 条展示，不再为了"凑点数"做采样降频。
     —— 一并取联网方式(781)与信号强度(782)：它们是同一条上报纸文里的字段，
        并进这次查询不会增加请求次数（平台限频要求查询频率≈上报频率） */
  dvFetchHistory(d, from, to, [App.config.TAGS.VOLTAGE, App.config.TAGS.SET_VOLTAGE, App.config.TAGS.WORK_STATUS,
    App.config.TAGS.NETWORK_TYPE, App.config.TAGS.SIGNAL], 100)
    .then(function(h){
      dvReport = dvBuildReportFromRecords(h.records, from, to);
      dvReport.total = h.total;
      if (cnt) cnt.textContent = h.records.length + ' 条实际上报（区间共 ' + h.total + ' 条）';
      if (tsub){
        tsub.textContent = label + ' · 最新在上 · 区间共 ' + h.total + ' 条，本次取回最近 ' + h.records.length + ' 条' +
          (h.total > h.records.length ? '（接口单页上限 100 条）' : '');
      }
      renderDvTable();
      requestAnimationFrame(drawDvCharts);
    })
    .catch(function(e){
      const msg = (e && e.message) ? e.message : '未知错误';
      toastErr('历史数据查询失败：' + msg);
      if (cnt) cnt.textContent = '查询失败';
      if (tsub) tsub.textContent = label + ' · 查询失败：' + msg;
      if (body) body.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:18px 0">查询失败：' + msg + '</td></tr>';
    });
}

/* ---------- 明细表（全部为真实记录落桶结果） ---------- */
function workLabel(v){
  if (v === 1 || v === '1') return '开机';
  if (v === 0 || v === '0') return '关机';
  if (v === 255 || v === '255') return '未同步';
  return String(v);
}
function renderDvTable(){
  const body = document.getElementById('rpBody');
  if (!body || !dvReport) return;
  const { times, series } = dvReport;

  /* 一行 = 一条真实上报纸文：不再有「无上报」的空行占位（表里出现的就是上报过的时刻） */
  if (!times.length){
    body.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:18px 0">该查询区间内没有任何上报记录</td></tr>';
    return;
  }

  const rows = [];
  for (let i = times.length - 1; i >= 0; i--){      /* 最新在上 */
    const t = times[i];
    const voltage = series.load[i], setV = series.temp[i], work = series.work[i], hb = series.hb[i];
    const netV = series.net[i], sigV = series.sig[i];
    const warn = (voltage != null && voltage > 5500) || (setV != null && setV > 5000);
    rows.push('<tr>' +
      '<td>' + dvDT(t) + '</td>' +
      '<td>' + (voltage == null ? '--' : Math.round(voltage) + ' V') + '</td>' +
      '<td>' + (setV == null ? '--' : Math.round(setV) + ' V') + '</td>' +
      '<td>' + (work == null ? '--' : workLabel(work)) + '</td>' +
      /* 联网方式 + 信号强度：同一条记录里的 Tag 781/782（信号带档位词） */
      '<td>' + (netV == null ? '--' : netTagText(netV)) + '</td>' +
      '<td>' + (sigV == null ? '--' : (sigV + '/31 · ' + signalLevelText(netV, sigV))) + '</td>' +
      '<td>' + (hb == null ? '--' : hb + ' s') + '</td>' +
      '<td><span class="rp-st ' + (warn ? 'alarm' : 'ok') + '">' +
        (warn ? '已上报 · 告警' : '已上报 · 正常') + '</span></td>' +
    '</tr>');
  }
  body.innerHTML = rows.join('');
}

/* ---------- 趋势图 ---------- */
function drawDvCharts(){
  if (!dvReport) return;
  document.querySelectorAll('#rpCharts canvas').forEach(cvs => {
    const card = DV_REPORT_CARDS[+cvs.dataset.chart];
    if (card) drawDvChart(cvs, card);
  });
}

function drawDvChart(cvs, card){
  const r = cvs.getBoundingClientRect();
  if (!r.width || !r.height) return;          /* 页签隐藏时量不到尺寸，等可见后再画 */
  const ctx = cvs.getContext('2d');
  const dpr = Math.min(devicePixelRatio || 1, 2);
  cvs.width = Math.round(r.width * dpr);
  cvs.height = Math.round(r.height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  const W = r.width, H = r.height;
  /* 内边距与鼠标读数的坐标反解共用一套（见 RP_PAD），避免两处各写一份 */
  const padL = RP_PAD.l, padR = RP_PAD.r, padT = RP_PAD.t, padB = RP_PAD.b;
  const plotW = W - padL - padR, plotH = H - padT - padB;
  const times = dvReport.times, series = dvReport.series;

  /* 同一张图共用一套刻度：取所有曲线的取值范围 */
  let lo = Infinity, hi = -Infinity;
  card.series.forEach(s => {
    series[s.key].forEach(v => {
      if (v == null) return;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    });
  });
  if (!isFinite(lo)){
    /* 该区间没有任何可用样本（例如设备全程走 WiFi，4G 信号图就一个点都没有）：
       明确写出来，而不是画一张空网格让人以为图坏了 */
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = cssVar('--muted');
    ctx.font = '12px -apple-system,system-ui,sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('该区间内没有' + (card.emptyText || '') + '上报记录', W / 2, H / 2);
    dvTipHide(dvTipEl(cvs.parentElement));      /* 数据变空时别留着上一次的读数 */
    return;
  }
  const pad = (hi - lo) * .15 || 1;
  lo = lo - pad;
  hi = hi + pad;
  if (card.floor != null) lo = Math.max(card.floor, lo);
  if (hi - lo < 1e-6) hi = lo + 1;

  const X = i => padL + (times.length <= 1 ? plotW / 2 : (i / (times.length - 1)) * plotW);
  const Y = v => padT + plotH - ((v - lo) / (hi - lo)) * plotH;

  ctx.clearRect(0, 0, W, H);
  ctx.font = '10px ui-monospace,Consolas,monospace';

  /* 横向网格 + Y 轴刻度 */
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';
  ctx.strokeStyle = cssVar('--chart-grid');
  ctx.fillStyle = cssVar('--muted');
  ctx.lineWidth = 1;
  for (let k = 0; k <= 4; k++){
    const v = lo + (hi - lo) * k / 4;
    const y = Math.round(Y(v)) + .5;
    ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(W - padR, y); ctx.stroke();
    ctx.fillText(dvTick(v), padL - 7, y);
  }

  /* X 轴时间刻度 */
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  const stride = Math.max(1, Math.round((times.length - 1) / 5));
  for (let i = 0; i < times.length; i += stride){
    ctx.fillText(dvDT(times[i]), X(i), padT + plotH + 7);
  }
  ctx.textAlign = 'right';
  ctx.fillText(dvDT(times[times.length - 1]), W - padR, padT + plotH + 7);

  /* 每条曲线：渐变面积 + 发光折线；null 处断开 */
  card.series.forEach(s => {
    const color = cssVar(s.color);
    const vals = series[s.key];

    const segs = [];
    let cur = null;
    vals.forEach((v, i) => {
      if (v == null){ cur = null; return; }
      if (!cur){ cur = []; segs.push(cur); }
      cur.push([X(i), Y(v)]);
    });

    segs.forEach(pts => {
      const base = padT + plotH;

      if (pts.length > 1){
        const g = ctx.createLinearGradient(0, padT, 0, base);
        g.addColorStop(0, toRgba(color, .28));
        g.addColorStop(1, toRgba(color, 0));
        ctx.beginPath();
        pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]));
        ctx.lineTo(pts[pts.length - 1][0], base);
        ctx.lineTo(pts[0][0], base);
        ctx.closePath();
        ctx.fillStyle = g;
        ctx.fill();
      }

      ctx.beginPath();
      pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]));
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.7;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.shadowBlur = 8;
      ctx.shadowColor = toRgba(color, .7);
      ctx.stroke();
      ctx.shadowBlur = 0;

      /* 末端光点：单点段也画，避免曲线在末端突然消失 */
      const lastP = pts[pts.length - 1];
      ctx.beginPath();
      ctx.arc(lastP[0], lastP[1], 2.6, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
    });
  });

  /* ---- 鼠标读数：竖向虚线 + 各曲线在该时刻的采样点 + 读数气泡 ---- */
  const tip = dvTipEl(cvs.parentElement);
  const hvI = (typeof cvs.__hover === 'number') ? cvs.__hover : -1;
  if (hvI < 0 || hvI >= times.length){
    dvTipHide(tip);
    return;
  }
  const hx = X(hvI);
  ctx.strokeStyle = cssVar('--line-strong');
  ctx.lineWidth = 1;
  ctx.setLineDash([4, 4]);
  ctx.beginPath(); ctx.moveTo(hx, padT); ctx.lineTo(hx, padT + plotH); ctx.stroke();
  ctx.setLineDash([]);

  let html = '<div class="t-time">' + dvFull(times[hvI]) + '</div>';
  card.series.forEach(s => {
    const v = series[s.key][hvI];
    const color = cssVar(s.color);
    if (v == null){
      html += '<div><i style="background:' + color + ';opacity:.35"></i><em>' + s.label + ' 该时刻无上报</em></div>';
      return;
    }
    const txt = s.fmt ? s.fmt(v) : (Math.round(v * 100) / 100) + (s.unit || '');
    html += '<div><i style="background:' + color + '"></i>' + s.label + ' <b>' + txt + '</b></div>';
    const py = Y(v);
    ctx.beginPath(); ctx.arc(hx, py, 6, 0, Math.PI * 2);
    ctx.fillStyle = toRgba(color, .25); ctx.fill();
    ctx.beginPath(); ctx.arc(hx, py, 3, 0, Math.PI * 2);
    ctx.fillStyle = color; ctx.fill();
  });
  dvTipShow(cvs.parentElement, tip, cvs.offsetLeft + hx, cvs.offsetTop + (cvs.__hoverY || (padT + plotH / 2)), html);
}

/* Y 轴刻度文案：大数少留小数，小数保留一位 */
function dvTick(v){
  const a = Math.abs(v);
  if (a >= 1000) return (v / 1000).toFixed(1) + 'k';
  if (a >= 100) return Math.round(v) + '';
  return v.toFixed(1);
}

/* ---------- 导出 ---------- */
function exportDvCsv(){
  if (!dvReport || !activeDevice) return;
  const { times, series, failAt } = dvReport;

  /* 列与明细表保持一致；数值一律走空值安全输出
     （原实现误用 series.snr[i].toFixed()，而 series 里从来没有 snr → 导出会抛错） */
  const num = v => (v == null ? '' : v.toFixed(0));
  const lines = times.map((t, i) => {
    const off = t > failAt;
    const warn = !off && ((series.load[i] || 0) > 5500 || (series.temp[i] || 0) > 5000);
    const netV = series.net[i], sigV = series.sig[i];
    return [dvFull(t),
      num(series.load[i]), num(series.temp[i]),
      series.work[i] == null ? '' : workLabel(series.work[i]),
      netV == null ? '' : netTagText(netV),
      sigV == null ? '' : sigV,
      num(series.hb[i]),
      off ? '离线·失联' : warn ? '在线·告警' : '在线·正常'].join(',');
  });

  const csv = '时间,实际电压(V),设定电压(V),工作状态,联网方式,信号强度(0~31),上报间隔(s),状态\n' + lines.join('\n');
  try {
    const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = activeDevice.id + '_' + dvDT(Date.now()).replace(/[ :]/g, '') + '.csv';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  } catch (e){
    toastErr('导出失败：当前环境不支持文件下载');
  }
}

(function bindDvReport(){
  const seg = document.getElementById('rpSeg');
  const fromEl = document.getElementById('rpFrom');
  const toEl = document.getElementById('rpTo');
  const query = document.getElementById('rpQuery');
  const exp = document.getElementById('rpExport');
  if (!seg || !fromEl || !toEl || !query || !exp) return;

  /* 自定义区间默认给「近 6 小时」，与默认预设一致 */
  dvTo = Date.now();
  dvFrom = dvTo - DV_RANGES['6h'].span;
  fromEl.value = dvLocalInput(dvFrom);
  toEl.value = dvLocalInput(dvTo);

  const setActive = key => {
    seg.querySelectorAll('button[data-range]').forEach(b => b.classList.toggle('active', b.dataset.range === key));
  };

  seg.addEventListener('click', e => {
    const b = e.target.closest('button[data-range]');
    if (!b) return;
    dvRange = b.dataset.range;
    setActive(dvRange);
    if (activeDevice) renderDvReport(activeDevice);
  });

  query.addEventListener('click', () => {
    const f = Date.parse(fromEl.value);
    const t = Date.parse(toEl.value);
    if (!f || !t){ toastErr('查询失败：请选择完整的起止时间'); return; }
    if (f >= t){ toastErr('查询失败：开始时间必须早于结束时间'); return; }
    if (t - f < 600000){ toastErr('查询失败：时间跨度至少 10 分钟'); return; }
    if (f > Date.now()){ toastErr('查询失败：开始时间不能晚于当前时间'); return; }
    if (t - f > 90 * 86400000){ toastErr('查询失败：时间跨度不能超过 90 天'); return; }
    dvRange = 'custom';
    dvFrom = f;
    dvTo = t;
    setActive('');
    if (activeDevice) renderDvReport(activeDevice);
  });

  exp.addEventListener('click', exportDvCsv);

  /* 窗口尺寸变化后画布要按新宽度重绘（防抖，且只在报表页签可见时执行） */
  let rzTimer = null;
  window.addEventListener('resize', () => {
    if (rzTimer) clearTimeout(rzTimer);
    rzTimer = setTimeout(() => { if (dvTab === 'report') drawDvCharts(); }, 180);
  });
})();

/* 主题切换后重绘（健康环渐变、指标卡取色都依赖于主题变量） */
window.addEventListener('themechange', () => {
  if (activeDevice && deviceView && deviceView.classList.contains('show')) renderDeviceView(dvTab);
});


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
/* 设备管理页：设备列表（含表格模式） */
registerPageRenderer(function(data){ renderDevices(data); });

/* 支持从地图/告警页跳过来直接打开某台设备：pages/devices.html?dev=<IMEI> */
onPageQuery(function(q){
  if (!q.dev) return;
  const id = String(q.dev);
  const d = (curData().devices || []).find(function(x){ return x.id === id; });
  if (!d){ toastErr('未找到设备 ' + id); return; }
  if (typeof openDeviceView === 'function') openDeviceView(d, 'basic');
});
