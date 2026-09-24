/* assets/js/pages/overview.js —— 由 index.html 内联脚本拆出（原行区间 3840-4022），内容未改动 */
/* =========================================================
   6.1 KPI / 文案渲染
   ========================================================= */
function renderKpi(data){
  const prj = data.project;
  /* 面板可能正处于其他视图（已从 #grid 摘除），因此逐项判空 */
  const q = id => document.getElementById(id);
  const text = (id, val) => { const el = q(id); if (el) el.textContent = val; };

  /* 概览不再用两张 KPI 卡，改由两张饼图分别表达连接口径与告警口径 */
  renderOverviewPies(data);

  /* 设备面板副标题由 renderDevices 维护（需反映搜索结果） */
  /* 告警面板副标题由 renderAlerts 维护（需反映搜索结果） */
}

/* =========================================================
   6.1b 运营总览：概览饼图（连接口径 · 告警口径）
   ========================================================= */
/* 扇形路径：从 12 点方向起顺时针铺开。整圆无法用单段圆弧表达（起终点重合会退化成空），
   这种情况返回 null，由调用方改画 circle */
function pieSlicePath(cx, cy, r, from, to){
  if (to - from >= 1) return null;
  const a0 = from * Math.PI * 2 - Math.PI / 2;
  const a1 = to   * Math.PI * 2 - Math.PI / 2;
  const x0 = cx + r * Math.cos(a0), y0 = cy + r * Math.sin(a0);
  const x1 = cx + r * Math.cos(a1), y1 = cy + r * Math.sin(a1);
  return 'M' + cx + ' ' + cy +
         'L' + x0.toFixed(2) + ' ' + y0.toFixed(2) +
         'A' + r + ' ' + r + ' 0 ' + (to - from > .5 ? 1 : 0) + ' 1 ' +
         x1.toFixed(2) + ' ' + y1.toFixed(2) + 'Z';
}

/* 引线标签占位：饼图半径同时受画布高度与「留给标签的横向空间」约束 */
const PIE_EDGE  = 18;          /* 饼图外缘到标签锚点的水平距离（引线长度） */
const PIE_PAD   = 16;          /* 标签距画布上下边缘的最小距离 */
const PIE_MAX_R = 200;         /* 饼图半径上限（超大屏兜底） */

/* 饼图本体 + 引线标签：items = [{ name, value, color }]，按 total 归一。
   画布尺寸由面板实际像素给定（viewBox 与像素 1:1），文字不会被等比缩放拉糊。
   标签按扇区中线角度的余弦分左右两侧，同侧再纵向错开，避免互相压住 */
function pieSVG(uid, items, total, W, H){
  const cx = W / 2, cy = H / 2;
  /* 半径先顶到高度上限（把面板高度用满），字号按半径等比给；
     若横向留给标签的空间不够，则把半径收回一点，字号随之缩小，避免长标签被裁 */
  let r = Math.max(26, Math.min(H / 2 - 10, PIE_MAX_R));
  let fs = Math.max(12, Math.min(17, r / 11));
  /* 标签分两行（名称+台数 / 占比），横向只占「名称+台数」的宽度，
     所以窄面板也能放下，饼图不必被压小 */
  const room = 26 + fs * 7.2;
  if (W / 2 - room < r){
    r = Math.max(26, W / 2 - room);
    fs = Math.max(12, Math.min(17, r / 11));
  }
  const open = '<svg class="pie-svg" viewBox="0 0 ' + W + ' ' + H +
               '" style="font-size:' + fs.toFixed(1) + 'px" role="img">';

  /* 1. 逐块算角度与标签的落点（先按自然位置摆，再统一收进可视区） */
  const arcs = [];
  let acc = 0;
  items.forEach(it => {
    const v = Math.max(0, it.value || 0);
    if (!v || !total) return;
    const from = acc / total;
    acc += v;
    const to = acc / total;
    const ang = (from + to) * Math.PI - Math.PI / 2;      /* 中线角度：(from+to)/2*2π - π/2 */
    const cos = Math.cos(ang), sin = Math.sin(ang);
    arcs.push({
      name: it.name, value: v, color: it.color,
      from: from, to: to, cos: cos, sin: sin,
      side: cos >= 0 ? 'right' : 'left',
      y: cy + (r + 18) * sin
    });
  });

  /* 全为 0（例如项目下暂无设备）时画一个空环，避免出现空白画布 */
  if (!arcs.length){
    return open + '<circle cx="' + cx + '" cy="' + cy + '" r="' + r +
           '" fill="none" stroke="var(--track-bg)" stroke-width="2"/></svg>';
  }

  ['left', 'right'].forEach(side => {
    const list = arcs.filter(a => a.side === side).sort((p, q) => p.y - q.y);
    /* 单侧无扇区时必须跳过（例如全部在线 / 只有一台设备）：
       否则 list[list.length-1] 为 undefined，读 .y 抛 TypeError，
       会中断整个 renderAllViews，导致后续真实数据拉取被吞掉 */
    if (!list.length) return;
    for (let i = 1; i < list.length; i++){
      if (list[i].y - list[i - 1].y < fs * 2.4) list[i].y = list[i - 1].y + fs * 2.4;
    }
    const over = list[list.length - 1].y - (H - PIE_PAD);
    if (over > 0) list.forEach(a => { a.y -= over; });
    const under = PIE_PAD - list[0].y;
    if (under > 0) list.forEach(a => { a.y += under; });
  });

  /* 2. 每块一层「亮→暗」线性渐变，饼面有体积感；扇区之间留一道底色缝隙 */
  let defs = '<defs>';
  arcs.forEach((a, i) => {
    defs += '<linearGradient id="' + uid + 'Slice' + i + '" x1="0" y1="0" x2="0.55" y2="1">' +
        '<stop offset="0" style="stop-color:' + a.color + '"/>' +
        '<stop offset="1" style="stop-color:' + a.color + ';stop-opacity:.6"/>' +
      '</linearGradient>';
  });
  defs += '</defs>';

  const slices = [];
  arcs.forEach((a, i) => {
    const fill = 'fill="url(#' + uid + 'Slice' + i + ')"';
    const edge = 'stroke="var(--bg)" stroke-width="1" stroke-linejoin="round"';
    const d = pieSlicePath(cx, cy, r, a.from, a.to);
    slices.push(d
      ? '<path class="pie-slice" d="' + d + '" ' + fill + ' ' + edge + '/>'
      : '<circle class="pie-slice" cx="' + cx + '" cy="' + cy + '" r="' + r + '" ' +
        fill + ' ' + edge + '/>');
  });

  /* 3. 引线：扇区边缘 -> 折点 -> 标签；文字按台数滚动，占比直接落值 */
  const leads = [];
  arcs.forEach(a => {
    const x0 = cx + (r + 1) * a.cos, y0 = cy + (r + 1) * a.sin;
    const x1 = cx + (r + 18) * a.cos;
    const xEnd = a.side === 'right' ? cx + r + PIE_EDGE : cx - r - PIE_EDGE;
    const anchor = a.side === 'right' ? 'start' : 'end';
    const tx = a.side === 'right' ? xEnd + 6 : xEnd - 6;
    const dy = fs * 0.62;            /* 两行标签各偏移半行 */
    const pct = (a.value / total * 100).toFixed(1);
    leads.push(
      '<polyline class="pie-lead" style="stroke:' + a.color + '" points="' +
        x0.toFixed(1) + ',' + y0.toFixed(1) + ' ' +
        x1.toFixed(1) + ',' + a.y.toFixed(1) + ' ' +
        xEnd + ',' + a.y.toFixed(1) + '"/>' +
      '<circle class="pie-lead-dot" cx="' + x0.toFixed(1) + '" cy="' + y0.toFixed(1) +
        '" r="1.9" style="fill:' + a.color + '"/>' +
      '<text x="' + tx + '" y="' + (a.y - dy).toFixed(1) +
        '" text-anchor="' + anchor + '">' +
        '<tspan class="pie-lb-name">' + a.name + ' </tspan>' +
        '<tspan class="pie-lb-val" data-pie-count="' + a.value + '">0</tspan>' +
      '</text>' +
      '<text x="' + tx + '" y="' + (a.y + dy).toFixed(1) +
        '" text-anchor="' + anchor + '">' +
        '<tspan class="pie-lb-pct">' + pct + '%</tspan>' +
      '</text>'
    );
  });

  return open + defs +
    '<g class="pie-wrap">' + slices.join('') + '</g>' +
    leads.join('') + '</svg>';
}

function renderOverviewPies(data){
  const total = data.project.total;
  const online = Math.max(0, Math.min(total, data.kpi.online));
  const alarmed = Math.max(0, Math.min(total, data.kpi.alert));

  const charts = [
    {
      uid:'pieA', box:'pieOnline',
      items:[{ name:'在线', value: online,           color:'var(--green)' },
             { name:'离线', value: total - online,   color:'var(--amber)' }]
    },
    {
      uid:'pieB', box:'pieAlarm', legend:'pieAlarmLegend',
      items:[{ name:'有告警', value: alarmed,          color:'var(--red)' },
             { name:'无告警', value: total - alarmed,  color:'var(--green)' }]
    }
  ];

  charts.forEach(c => {
    const box = document.getElementById(c.box);
    if (box){
      /* 面板处于其他视图时量不到尺寸，用兜底画布；重新挂载后的 resize 会重画 */
      const w = Math.round(box.clientWidth) || 400;
      const h = Math.round(box.clientHeight) || 132;
      box.innerHTML = pieSVG(c.uid, c.items, total, w, h);
      /* 台数滚动，与「系统设置」里的动效开关保持一致 */
      box.querySelectorAll('[data-pie-count]').forEach(el => rollNumber(el, +el.dataset.pieCount));
    }
  });
}


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
/* 运营总览页：KPI 卡 + 两张概览饼图 */
registerPageRenderer(function(data){ renderKpi(data); renderOverviewPies(data); });
