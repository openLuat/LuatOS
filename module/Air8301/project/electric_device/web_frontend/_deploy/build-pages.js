/* 阶段 2/3：把单页 index.html 拆成多页面结构。
   —— 页面 HTML 由当前 index.html 的 body 机械切片生成，不改动面板内部结构
   —— CSS 链接顺序统一取自 CANON（= 拆分前规则顺序），每页只取自己需要的子集，
      因此任意页面的层叠顺序都与拆分前一致
   —— 同时把 pages/devices.css 里的「列表搜索 / 分页（设备列表与告警中心共用）」段落
      切到 components-list.css（供两个页面共用，且顺序不变）
   用法：node _deploy/build-pages.js
*/
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
/* body 切片源：优先用生成前的单页壳备份（避免重跑时读到已被改写成运营总览的 index.html） */
const INDEX = fs.existsSync(path.join(ROOT, '_deploy', 'index.single-page-shell.bak'))
  ? path.join(ROOT, '_deploy', 'index.single-page-shell.bak')
  : path.join(ROOT, 'index.html');
const raw = fs.readFileSync(INDEX, 'utf8');
const EOL = raw.includes('\r\n') ? '\r\n' : '\n';
const L = raw.split(/\r?\n/);
const seg = (a, b) => L.slice(a - 1, b);            // 1-based 闭区间

/* ---------- 1. 先把共用列表样式切出来（保持内容与顺序） ---------- */
(() => {
  const devCssPath = path.join(ROOT, 'assets/css/pages/devices.css');
  const listCssPath = path.join(ROOT, 'assets/css/components-list.css');
  if (fs.existsSync(listCssPath)) { console.log('components-list.css 已存在，跳过切分'); return; }
  const txt = fs.readFileSync(devCssPath, 'utf8');
  const lines = txt.split(/\r?\n/);
  const cut = lines.findIndex(l => l.includes('列表搜索 / 分页'));
  if (cut <= 0) throw new Error('pages/devices.css 里找不到「列表搜索 / 分页」分段');
  const headPart = lines.slice(0, cut);
  const tailPart = lines.slice(cut);
  fs.writeFileSync(devCssPath, headPart.join(EOL).replace(/\s+$/, '') + EOL, 'utf8');
  fs.writeFileSync(listCssPath, '/* assets/css/components-list.css —— 设备列表与告警中心共用的列表搜索 / 分页样式（由 pages/devices.css 切出，顺序不变） */' + EOL + tailPart.join(EOL), 'utf8');
  console.log('已切出 components-list.css（devices.css ' + headPart.length + ' 行 / list.css ' + (tailPart.length - 1) + ' 行）');
})();

/* ---------- 2. body 切片定义（基于当前 index.html 行号） ---------- */
const H = {
  headBefore: [1, 6],   /* 只到 <title>，腾讯地图 SDK 由 page.tmap 决定是否加 */          // doctype…腾讯地图 SDK
  sidebar:    [34, 77],        // 侧边栏（含导航）
  topbar:     [81, 119],
  gridOpen:   121,
  gridClose:  [695, 697],      // </div>(grid) </div>(main) </div>(app)
  toast:      [699, 699],
  ruleMask:   [701, 712],
  logoutMask: [714, 724],
  /* 面板块（每块的第一行是面板开始标签，会被重写 class / 去掉 display:none） */
  panels: {
    onlinePie:    [123, 130],
    alarmPie:     [131, 138],
    devices:      [139, 411],   // 含设备全屏页 #deviceView
    alertKpi:     [412, 434],
    alerts:       [435, 473],
    alertSide:    [474, 515],
    topo:         [516, 527],
    location:     [528, 589],
    settings:     [590, 694]
  }
};

/* ---------- 3. 页面定义 ---------- */
const CANON = ['variables', 'reset', 'layout', 'pages/settings', 'components',
  'pages/overview', 'pages/devices', 'components-list', 'pages/alerts', 'pages/topo',
  'pages/map', 'pages/device-detail', 'components-shell', 'components-user',
  'components-dialog', 'responsive'];
const BASE_CSS = ['variables', 'reset', 'layout', 'components', 'components-shell',
  'components-user', 'components-dialog', 'responsive'];
const SHARED_JS = ['luat-sdk', 'config', 'storage', 'utils', 'http', 'auth', 'guards', 'components', 'api', 'shell'];

const PAGES = [
  {
    key: 'overview', nav: '运营总览', out: 'index.html', depth: 0, title: '上海合宙 · 电力控制平台',
    rows: 'minmax(0,1fr) minmax(0,1fr)', tmap: true,
    css: ['pages/overview', 'pages/map'],
    js: ['pages/overview'],
    /* 地图引擎/覆盖层（pages/map.js）只服务地图面板，是首屏最大的一块非关键脚本：
       单列成「首屏之后再加载」的分包（lazyJs），让 KPI/饼图先上屏、地图稍后出现 */
    lazyJs: ['pages/map'],
    panels: [
      { seg: 'onlinePie', id: 'panel-online-pie', cls: 'panel ov-pie-a' },
      { seg: 'alarmPie', id: 'panel-alarm-pie', cls: 'panel ov-pie-b' },
      { seg: 'location', id: 'panel-location', cls: 'panel lm2-mini ov-map' }
    ]
  },
  {
    key: 'devices', nav: '设备管理', out: 'pages/devices.html', depth: 1, title: '设备管理 · 上海合宙',
    rows: 'minmax(0,1fr)', tmap: false,
    css: ['pages/devices', 'components-list', 'pages/device-detail'],
    js: ['pages/devices'],
    panels: [{ seg: 'devices', id: 'panel-devices', cls: 'panel span12' }]
  },
  {
    key: 'alerts', nav: '告警中心', out: 'pages/alerts.html', depth: 1, title: '告警中心 · 上海合宙',
    rows: 'auto minmax(0,1fr)', tmap: false,
    css: ['components-list', 'pages/alerts', 'pages/settings'],
    js: ['pages/alerts'],
    ruleMask: true,
    panels: [
      { seg: 'alertKpi', id: 'panel-alert-kpi', cls: 'panel span12' },
      { seg: 'alerts', id: 'panel-alerts', cls: 'panel span6' },
      { seg: 'alertSide', id: 'panel-alert-side', cls: 'panel span6' }
    ]
  },
  {
    key: 'topo', nav: '网络拓扑', out: 'pages/topo.html', depth: 1, title: '网络拓扑 · 上海合宙',
    rows: 'minmax(0,1fr)', tmap: false,
    css: ['pages/topo'], js: ['pages/topo'],
    panels: [{ seg: 'topo', id: 'panel-topo', cls: 'panel span12' }]
  },
  {
    key: 'map', nav: '位置地图', out: 'pages/map.html', depth: 1, title: '位置地图 · 上海合宙',
    rows: 'minmax(0,1fr)', tmap: true,
    css: ['pages/map'], js: ['pages/map'],
    panels: [{ seg: 'location', id: 'panel-location', cls: 'panel span12' }]
  },
  {
    key: 'settings', nav: '系统设置', out: 'pages/settings.html', depth: 1, title: '系统设置 · 上海合宙',
    rows: 'minmax(0,1fr)', tmap: false,
    css: ['pages/settings'], js: ['pages/settings'],
    panels: [{ seg: 'settings', id: 'panel-settings', cls: 'panel span12' }]
  }
];

/* ---------- 4. 工具 ---------- */
const NAV_URL = {           // 由 depth=1（pages/ 下）出发的相对地址
  '运营总览': '../index.html',
  '设备管理': 'devices.html',
  '告警中心': 'alerts.html',
  '位置地图': 'map.html',
  '网络拓扑': 'topo.html',
  '系统设置': 'settings.html'
};
const NAV_URL_ROOT = {      // 由 depth=0（根目录）出发
  '运营总览': 'index.html',
  '设备管理': 'pages/devices.html',
  '告警中心': 'pages/alerts.html',
  '位置地图': 'pages/map.html',
  '网络拓扑': 'pages/topo.html',
  '系统设置': 'pages/settings.html'
};

function buildNav(page) {
  const map = page.depth === 0 ? NAV_URL_ROOT : NAV_URL;
  return seg(H.sidebar[0], H.sidebar[1]).join(EOL).replace(
    /<button class="nav-item([^"]*)" data-tip="([^"]+)">([\s\S]*?)<\/button>/g,
    (m, cls, tip, inner) => {
      const active = tip === page.nav ? ' active' : '';
      return '<a class="nav-item' + active + '" href="' + map[tip] + '" data-tip="' + tip + '">' + inner + '</a>';
    });
}

/* 重写面板开始标签：class 固定 + 去掉 display:none */
function buildPanel(page, p) {
  const lines = seg(H.panels[p.seg][0], H.panels[p.seg][1]);
  lines[0] = lines[0]
    .replace(/class="[^"]*"/, 'class="' + p.cls + '"')
    .replace(/\s*style="display:none"/, '');
  if (lines[0].indexOf('class="') === -1) throw new Error('面板标签未找到 class: ' + lines[0]);
  // 面板内嵌套同名 id 检查
  const html = lines.join(EOL);
  if (html.indexOf('id="' + p.id + '"') === -1) throw new Error('面板 id 缺失: ' + p.id);
  return html;
}

function buildPage(page) {
  const rel = page.depth === 0 ? '' : '../';
  const out = [];
  /* head */
  const head = seg(H.headBefore[0], H.headBefore[1]);
  if (page.tmap){
    head.push('<!-- 腾讯位置服务 JavaScript API GL：按 AirCloud 资源包《腾讯地图.md》要求，Key 为项目内置常量，只出现在本加载地址中 -->');
    head.push('<!-- defer：SDK 不再阻塞 HTML 解析与首屏渲染（实测阻塞时首屏数据上屏会被拖后约 0.5s）；');
    head.push('     preconnect/dns-prefetch：提前与地图域名建连，缩短 SDK 与瓦片的握手耗时 -->');
    head.push('<link rel="preconnect" href="https://map.qq.com">');
    head.push('<link rel="dns-prefetch" href="https://map.qq.com">');
    /* SDK 起来后还要拉样式/图标（vectorsdk）与上报信标（pr），提前解析这两个子域，
       实测它们的请求能占到 600ms 左右（见加载性能实测） */
    head.push('<link rel="dns-prefetch" href="https://vectorsdk.map.qq.com">');
    head.push('<link rel="dns-prefetch" href="https://pr.map.qq.com">');
    head.push('<script defer src="https://map.qq.com/api/gljs?v=1.exp&key=EZNBZ-VA6KW-ASMRR-3UE4S-M3QCO-EYBC6"></script>');
  }
  head[5] = '<title>' + page.title + '</title>';       // 第 6 行是原 title
  out.push(head.join(EOL));
  out.push('<!-- 公共样式（顺序 = 拆分前规则的原始顺序，勿调整） -->');
  const cssList = CANON.filter(f => BASE_CSS.indexOf(f) > -1 || page.css.indexOf(f) > -1);
  cssList.forEach(f => out.push('<link rel="stylesheet" href="' + rel + 'assets/css/' + f + '.css">'));
  if (page.css.some(f => !BASE_CSS.includes(f))) {
    out.push('<!-- 本页专属样式：' + page.css.filter(f => !BASE_CSS.includes(f)).map(f => f + '.css').join(' / ') + ' -->');
  }
  out.push('</head>');
  out.push('<body data-page="' + page.key + '" data-page-name="' + page.nav + '">');
  out.push(seg(30, 32).join(EOL));                     // canvas#bg + <div class="app">
  out.push(buildNav(page));
  out.push(seg(H.topbar[0] - 1, H.topbar[0] - 1).join(EOL));  // 主区域注释
  out.push(seg(H.topbar[0], H.topbar[1]).join(EOL));
  out.push('    <!-- 栅格：本页只放自己用到的面板（行高与原视图定义一致） -->');
  out.push('    <div class="grid" id="grid" style="grid-template-rows:' + page.rows + '">');
  page.panels.forEach(p => out.push(buildPanel(page, p)));
  out.push(seg(H.gridClose[0], H.gridClose[1]).join(EOL));
  out.push(seg(H.toast[0], H.toast[1]).join(EOL));
  if (page.ruleMask) out.push(seg(H.ruleMask[0], H.ruleMask[1]).join(EOL));
  out.push(seg(H.logoutMask[0], H.logoutMask[1]).join(EOL));
  out.push('<!-- 公共能力 → 本页逻辑 → 页面启动（顺序不可调整） -->');
  SHARED_JS.forEach(f => out.push('<script src="' + rel + 'assets/js/' + f + '.js"></script>'));
  page.js.forEach(f => out.push('<script src="' + rel + 'assets/js/' + f + '.js"></script>'));
  /* 延迟分包：data-lazy 标记的模块首屏不加载，打包时抽成 <页名>-lazy.js 由 boot.js 注入 */
  (page.lazyJs || []).forEach(f => out.push('<script src="' + rel + 'assets/js/' + f + '.js" data-lazy></script>'));
  out.push('<script src="' + rel + 'assets/js/boot.js"></script>');
  out.push('</body>');
  out.push('</html>');
  const file = path.join(ROOT, page.out);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, out.join(EOL), 'utf8');
  return { out: page.out, bytes: Buffer.byteLength(out.join(EOL), 'utf8'), css: cssList.length, js: SHARED_JS.length + page.js.length + (page.lazyJs ? page.lazyJs.length : 0) + 1 };
}

const report = PAGES.map(buildPage);
report.forEach(r => console.log(('  ' + r.out).padEnd(28) + String(r.bytes).padStart(7) + ' bytes   CSS ' + r.css + ' 个 / JS ' + r.js + ' 个'));

/* ---------- 5. 校验：每页引用的文件都存在 ---------- */
let bad = 0;
PAGES.forEach(page => {
  const rel = page.depth === 0 ? '' : '../';
  const cssList = CANON.filter(f => BASE_CSS.indexOf(f) > -1 || page.css.indexOf(f) > -1);
  cssList.forEach(f => { if (!fs.existsSync(path.join(ROOT, 'assets/css', f + '.css'))) { console.log('缺少 CSS: ' + f); bad++; } });
  SHARED_JS.concat(page.js).concat(['boot']).forEach(f => { if (!fs.existsSync(path.join(ROOT, 'assets/js', f + '.js'))) { console.log('缺少 JS: ' + f); bad++; } });
});
console.log(bad ? ('!!! 缺失 ' + bad + ' 个引用') : '全部引用文件存在');
