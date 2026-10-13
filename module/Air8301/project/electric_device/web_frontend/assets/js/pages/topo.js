/* assets/js/pages/topo.js —— 由 index.html 内联脚本拆出（原行区间 5097-5219），内容未改动 */
/* =========================================================
   8. 网络拓扑（可重建，随主题更新）
   ========================================================= */
/* 拓扑节点数：设备可达上千台，只等间隔抽样展示核心设备，
   否则 SVG 里会塞进上千个节点和常驻动画，浏览器会被拖死 */
const TOPO_SAMPLE = 6;

function topoSample(data, n){
  const all = data.devices;
  if (all.length <= n) return all.slice();
  const step = (all.length - 1) / (n - 1);
  const out = [];
  for (let i = 0; i < n; i++) out.push(all[Math.round(i * step)]);
  return out;
}

function buildTopo(data){
  data = data || curData();
  const svg = document.getElementById('topo');
  if (!svg) return;
  const NS = 'http://www.w3.org/2000/svg';
  svg.innerHTML = '';

  const cx = 200, cy = 150, R = 100;
  /* 节点 = 抽样设备，标签直接用设备名，颜色按该设备自身状态 */
  const nodes = topoSample(data, TOPO_SAMPLE).map(d => ({
    label: d.name,
    c: d.online ? (d.alarm !== 'none' ? cssVar('--amber') : cssVar('--cyan')) : cssVar('--red')
  }));

  // 渐变
  const defs = document.createElementNS(NS, 'defs');
  const lg = document.createElementNS(NS, 'linearGradient');
  lg.setAttribute('id', 'coreGrad');
  lg.setAttribute('x1', '0%'); lg.setAttribute('y1', '0%');
  lg.setAttribute('x2', '100%'); lg.setAttribute('y2', '100%');
  const s1 = document.createElementNS(NS, 'stop');
  s1.setAttribute('offset', '0%');
  s1.setAttribute('stop-color', cssVar('--cyan'));
  const s2 = document.createElementNS(NS, 'stop');
  s2.setAttribute('offset', '100%');
  s2.setAttribute('stop-color', cssVar('--violet'));
  lg.appendChild(s1); lg.appendChild(s2);
  defs.appendChild(lg);
  svg.appendChild(defs);

  // 外圈
  const halo = document.createElementNS(NS, 'circle');
  halo.setAttribute('cx', cx); halo.setAttribute('cy', cy); halo.setAttribute('r', R + 22);
  halo.setAttribute('fill', 'none');
  halo.setAttribute('stroke', cssVar('--line-strong'));
  halo.setAttribute('stroke-width', '1');
  halo.setAttribute('stroke-dasharray', '4 8');
  svg.appendChild(halo);

  nodes.forEach((n, i) => {
    const ang = (Math.PI * 2 * i) / nodes.length - Math.PI / 2;
    const x = cx + Math.cos(ang) * R;
    const y = cy + Math.sin(ang) * R;

    const line = document.createElementNS(NS, 'line');
    line.setAttribute('x1', cx); line.setAttribute('y1', cy);
    line.setAttribute('x2', x);  line.setAttribute('y2', y);
    line.setAttribute('class', 'topo-link');
    svg.appendChild(line);

    const g = document.createElementNS(NS, 'g');

    const ping = document.createElementNS(NS, 'circle');
    ping.setAttribute('cx', x); ping.setAttribute('cy', y); ping.setAttribute('r', 8);
    ping.setAttribute('fill', 'none');
    ping.setAttribute('stroke', n.c);
    ping.setAttribute('stroke-width', '1.2');
    ping.setAttribute('class', 'topo-ping');
    ping.style.animationDelay = (i * .38) + 's';
    g.appendChild(ping);

    const c = document.createElementNS(NS, 'circle');
    c.setAttribute('cx', x); c.setAttribute('cy', y); c.setAttribute('r', 6);
    c.setAttribute('fill', n.c);
    c.style.filter = 'drop-shadow(0 0 6px ' + n.c + ')';
    g.appendChild(c);

    const t = document.createElementNS(NS, 'text');
    t.setAttribute('x', x);
    t.setAttribute('y', y + (Math.sin(ang) > 0 ? 22 : -14));
    t.setAttribute('class', 'topo-label');
    t.textContent = n.label;
    g.appendChild(t);

    svg.appendChild(g);
  });

  // 中心服务器
  const coreG = document.createElementNS(NS, 'g');

  const coreRing = document.createElementNS(NS, 'circle');
  coreRing.setAttribute('cx', cx); coreRing.setAttribute('cy', cy); coreRing.setAttribute('r', 37);
  coreRing.setAttribute('fill', 'none');
  coreRing.setAttribute('stroke', cssVar('--line-strong'));
  coreRing.setAttribute('stroke-width', '1');
  coreG.appendChild(coreRing);

  const core = document.createElementNS(NS, 'circle');
  core.setAttribute('cx', cx); core.setAttribute('cy', cy); core.setAttribute('r', 27);
  core.setAttribute('fill', 'url(#coreGrad)');
  core.setAttribute('class', 'core');
  core.style.filter = 'drop-shadow(0 0 16px ' + cssVar('--cyan') + ')';
  coreG.appendChild(core);

  const coreLabel = document.createElementNS(NS, 'text');
  coreLabel.setAttribute('x', cx);
  coreLabel.setAttribute('text-anchor', 'middle');
  coreLabel.setAttribute('font-size', '9');
  coreLabel.setAttribute('font-weight', '700');
  coreLabel.setAttribute('class', 'core-label');
  /* 字号与换行：单行「AirCloud 平台」实测约 65px 宽，而实心圆（r=27）在文字基线附近的可用弦长只有
     约 48px —— 一行放不下；要一行塞下得压到约 7px，小到看不清。所以拆成两行：
     最宽一行「AirCloud」约 40px，刚好落在实心圆内，字号也只从 10 收到 9。
     颜色交给 CSS 的 .core-label 规则（圆是亮色渐变，文字固定用深色 —— 见 topo.css 注释）。 */
  [['AirCloud', -2], ['平台', 8]].forEach(function(pair){
    const t = document.createElementNS(NS, 'tspan');
    t.setAttribute('x', cx);
    t.setAttribute('y', cy + pair[1]);
    t.textContent = pair[0];
    coreLabel.appendChild(t);
  });
  coreG.appendChild(coreLabel);

  svg.appendChild(coreG);
}
window.addEventListener('themechange', () => buildTopo());


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
/* 网络拓扑页 */
registerPageRenderer(function(data){ buildTopo(data); });
