/* 阶段 1「抽公共壳」一次性拆分脚本：
   把 index.html 里内联的 <style> 与 <script> 按原有分区标记切成
   assets/css/*、assets/js/*，并把 index.html 改成引用这些文件。

   原则：只搬位置、不改代码内容，且保持「各区块的先后顺序」与拆分前一致，
   因此拆分后行为应与拆分前完全等价（样式规则顺序、脚本执行顺序都不变）。

   用法：node _deploy/split-index.js          （原地改写 index.html）
*/
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
/* 拆分源：默认用拆分前的单文件备份（重跑时不会被已拆分的 index.html 干扰）
   注意：读源与写出目标是两个路径 —— 曾经把两者写成同一个变量，
        导致重跑时把新壳写回了备份文件、index.html 没更新（线上样式全丢） */
const SRC = process.argv[2] || path.join(ROOT, '_deploy', 'index.single-file.bak');
const OUT = path.join(ROOT, 'index.html');
const raw = fs.readFileSync(SRC, 'utf8');
const EOL = raw.includes('\r\n') ? '\r\n' : '\n';
const lines = raw.split(/\r?\n/);

/* 1-based 闭区间取行；写文件时用该文件的 EOL */
const slice = (a, b) => lines.slice(a - 1, b);
const findLine = (text, from) => {
  for (let i = from || 0; i < lines.length; i++) if (lines[i].trim() === text) return i + 1;
  return -1;
};
const findLastLine = (text) => {
  let at = -1;
  lines.forEach((l, i) => { if (l.trim() === text) at = i + 1; });
  return at;
};

const styleStart = findLine('<style>');
const styleEnd = findLine('</style>', styleStart);
const scriptStart = findLastLine('<script>');          // 应用脚本（无 src 属性那个）
const scriptEnd = findLine('</script>', scriptStart);

if (styleStart < 0 || styleEnd < 0 || scriptStart < 0 || scriptEnd < 0) {
  throw new Error('未找到 style/script 边界: ' + JSON.stringify({ styleStart, styleEnd, scriptStart, scriptEnd }));
}

/* ---------------- 拆分表：文件 → 该文件包含的原始行区间（保持原文顺序） ---------------- */
const CSS_FILES = [
  ['variables.css',        [[13, 150]]],                               // 主题变量（三套主题）
  ['reset.css',            [[11, 12], [151, 185]]],                    // 全局复位 + 基础样式
  ['layout.css',           [[186, 314]]],                              // 骨架：布局 / 侧边栏 / 顶栏
  ['pages/settings.css',   [[315, 569]]],                              // 系统设置（主题风格 / 通知）
  ['components.css',       [[570, 656]]],                              // 栅格 / 面板 / KPI 卡
  ['pages/overview.css',   [[657, 678]]],                              // 运营总览：概览饼图
  ['pages/devices.css',    [[679, 831]]],                              // 设备列表 + 共用列表搜索 / 分页
  ['pages/alerts.css',     [[832, 1084]]],                             // 告警中心 + 规则弹窗
  ['pages/topo.css',       [[1085, 1100]]],                            // 网络拓扑
  ['pages/map.css',        [[1101, 1511]]],                            // 位置地图
  ['pages/device-detail.css', [[1512, 1990]]],                         // 设备全屏页（详情 / 指令）
  ['components-shell.css', [[1991, 2069]]],                            // Toast + 项目切换器
  ['components-user.css',  [[2070, 2118]]],                            // 操作记录 + 用户菜单
  ['components-dialog.css',[[2119, 2200]]],                            // 退出确认 + 登录页
  ['responsive.css',       [[2201, 2233]]]                             // 响应式断点（必须最后，与原来一致）
];

const JS_FILES = [
  ['luat-sdk.js',          [[2934, 3026]]],
  ['config.js',            [[3027, 3094]]],
  ['storage.js',           [[3095, 3162]]],
  ['utils.js',             [[3163, 3202]]],
  ['http.js',              [[3203, 3234]]],
  ['auth.js',              [[3235, 3357]]],
  ['guards.js',            [[3358, 3368]]],
  ['components.js',        [[3369, 3427], [3428, 3527], [8467, 8483]]],
  ['api.js',               [[3528, 3839], [8484, 8495], [9319, 9443]]],
  ['shell.js',             [[8496, 8660], [8984, 9318]]],
  ['pages/overview.js',    [[3840, 4022]]],
  ['pages/devices.js',     [[4023, 4494], [7262, 8466]]],
  ['pages/alerts.js',      [[4495, 5096]]],
  ['pages/topo.js',        [[5097, 5219]]],
  ['pages/map.js',         [[5220, 7261]]],
  ['pages/settings.js',    [[8661, 8983], [9444, 9684]]],
  ['boot.js',              [[9685, 9700]]]
];

/* ---------------- 覆盖完整性自检：每个区间必须落在 style/script 范围内且首尾相接 ---------------- */
function check(name, spec, lo, hi) {
  const all = spec.flatMap(s => s[1]).slice().sort((a, b) => a[0] - b[0]);
  let cur = lo;
  all.forEach(r => {
    if (r[0] !== cur) throw new Error(name + ' 覆盖断档: 期望起点 ' + cur + '，实际 ' + r[0]);
    cur = r[1] + 1;
  });
  if (cur !== hi + 1) throw new Error(name + ' 覆盖不足: 结束于 ' + (cur - 1) + '，应为 ' + hi);
}

/* style 范围内：11..2233（10 是 <style>，2234 是 </style>） */
(() => {
  const all = CSS_FILES.flatMap(s => s[1]).slice().sort((a, b) => a[0] - b[0]);
  let cur = styleStart + 1;
  all.forEach(r => {
    if (r[0] !== cur) throw new Error('CSS 覆盖断档: 期望 ' + cur + '，实际 ' + r[0]);
    cur = r[1] + 1;
  });
  if (cur !== styleEnd) throw new Error('CSS 覆盖不足，结束于 ' + (cur - 1) + '，应为 ' + (styleEnd - 1));
})();
(() => {
  const all = JS_FILES.flatMap(s => s[1]).slice().sort((a, b) => a[0] - b[0]);
  let cur = scriptStart + 1;
  all.forEach(r => {
    if (r[0] !== cur) throw new Error('JS 覆盖断档: 期望 ' + cur + '，实际 ' + r[0]);
    cur = r[1] + 1;
  });
  if (cur !== scriptEnd) throw new Error('JS 覆盖不足，结束于 ' + (cur - 1) + '，应为 ' + (scriptEnd - 1));
})();

/* ---------------- 写文件 ---------------- */
function emit(rel, spec, banner) {
  const parts = [];
  spec.forEach(r => parts.push(slice(r[0], r[1]).join(EOL)));
  const dir = path.join(ROOT, path.dirname(rel));
  fs.mkdirSync(dir, { recursive: true });
  const text = banner + EOL + parts.join(EOL) + EOL;
  fs.writeFileSync(path.join(ROOT, rel), text, 'utf8');
  return { rel, bytes: Buffer.byteLength(text, 'utf8'), from: spec.map(r => r[0] + '-' + r[1]).join(', ') };
}

const report = [];
CSS_FILES.forEach(([f, spec]) => report.push(emit('assets/css/' + f, spec, '/* assets/css/' + f + ' —— 由 index.html 内联样式拆出（原行区间 ' + spec.map(r => r[0] + '-' + r[1]).join(' / ') + '），内容未改动 */')));
JS_FILES.forEach(([f, spec]) => report.push(emit('assets/js/' + f, spec, '/* assets/js/' + f + ' —— 由 index.html 内联脚本拆出（原行区间 ' + spec.map(r => r[0] + '-' + r[1]).join(' / ') + '），内容未改动 */')));

/* ---------------- 改写 index.html ---------------- */
const head = slice(1, styleStart - 1);
const between = slice(styleEnd + 1, scriptStart - 1);
const tail = slice(scriptEnd + 1, lines.length);

const linkTags = ['<!-- 公共样式（阶段 1 抽公共壳：从内联 <style> 拆出，加载顺序与拆分前的规则顺序一致） -->']
  .concat(CSS_FILES.map(([f]) => '<link rel="stylesheet" href="assets/css/' + f + '">'));
const scriptTags = ['<!-- 公共能力与页面脚本（加载顺序 = LuatSDK → config → storage → utils → http → auth → guards → components → api → shell → 页面 → boot） -->']
  .concat(JS_FILES.map(([f]) => '<script src="assets/js/' + f + '"></script>'));

const out = []
  .concat(head)
  .concat(linkTags)
  .concat(between)
  .concat(scriptTags)
  .concat(tail)
  .join(EOL);
fs.writeFileSync(OUT, out, 'utf8');

console.log('原文件行数: ' + lines.length + '，EOL=' + (EOL === '\r\n' ? 'CRLF' : 'LF'));
console.log('style 区间: ' + styleStart + '..' + styleEnd + '（内容 ' + (styleStart + 1) + '-' + (styleEnd - 1) + '）');
console.log('script 区间: ' + scriptStart + '..' + scriptEnd + '（内容 ' + (scriptStart + 1) + '-' + (scriptEnd - 1) + '）');
console.log('');
report.forEach(r => console.log('  ' + (r.rel + '                              ').slice(0, 34) + String(r.bytes).padStart(8) + ' bytes   ← 原行 ' + r.from));
console.log('');
console.log('新 index.html: ' + Buffer.byteLength(out, 'utf8') + ' bytes, ' + out.split(EOL).length + ' 行');
