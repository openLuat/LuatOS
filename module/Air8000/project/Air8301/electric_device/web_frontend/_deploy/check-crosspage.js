/* 跨页引用静态检查（顶层声明，含函数调用与变量引用）
   某页用到的 函数/变量 若只定义在「本页不加载」的脚本里，多页面下就会 ReferenceError。
   用法：node _deploy/check-crosspage.js
*/
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'assets', 'js');

const SHARED = ['luat-sdk', 'config', 'storage', 'utils', 'http', 'auth', 'guards', 'components', 'api', 'shell', 'boot'];
const PAGE_FILES = ['pages/overview', 'pages/devices', 'pages/alerts', 'pages/topo', 'pages/map', 'pages/settings'];
const LOADED = {
  overview: ['pages/overview'], devices: ['pages/devices'], alerts: ['pages/alerts'],
  topo: ['pages/topo'], map: ['pages/map'], settings: ['pages/settings']
};

const strip = t => t.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1 ');
/* 顶层声明：行首（≤2 空格缩进）的 function / const / let / var */
function topDecls(text) {
  const out = new Set();
  strip(text).split(/\n/).forEach(line => {
    let m = line.match(/^\s{0,2}function\s+([A-Za-z_$][\w$]*)/);
    if (m) { out.add(m[1]); return; }
    m = line.match(/^\s{0,2}(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/);
    if (m) out.add(m[1]);
  });
  return out;
}

const files = SHARED.concat(PAGE_FILES).map(f => f + '.js');
const decl = {}, body = {};
files.forEach(f => { const t = fs.readFileSync(path.join(ROOT, f), 'utf8'); decl[f] = topDecls(t); body[f] = strip(t); });

const IGNORE = new Set(['state', 'DATA', 'PROJECTS', 'STORE_KEY', 'App', 'SDK', 'window', 'document', 'location', 'localStorage', 'sessionStorage', 'console', 'setTimeout', 'setInterval', 'clearTimeout', 'clearInterval', 'requestAnimationFrame', 'Object', 'Array', 'Math', 'JSON', 'Date', 'Number', 'String', 'Boolean', 'Set', 'Map', 'Promise', 'URLSearchParams', 'isFinite', 'parseInt', 'parseFloat', 'encodeURIComponent', 'decodeURIComponent', 'navigator', 'performance', 'Event', 'URL', 'TMap', 'Chart', 'undefined', 'Infinity', 'NaN']);

let total = 0;
Object.keys(LOADED).forEach(page => {
  const loaded = SHARED.concat(LOADED[page]).map(f => f + '.js');
  const notLoaded = files.filter(f => loaded.indexOf(f) === -1);
  const own = new Set();
  loaded.forEach(f => decl[f].forEach(n => own.add(n)));
  const found = {};
  loaded.forEach(f => {
    notLoaded.forEach(g => {
      decl[g].forEach(n => {
        if (own.has(n) || IGNORE.has(n) || n.length < 6) return;   /* 短名多为局部变量，跳过 */
        if (new RegExp('(^|[^\\w$.])' + n + '\\b').test(body[f])) (found[n] = found[n] || []).push(f + ' ← 定义在 ' + g);
      });
    });
  });
  const keys = Object.keys(found);
  total += keys.length;
  console.log('[' + page + '] ' + (keys.length ? keys.length + ' 处需要确认：' : '无跨页缺失'));
  keys.forEach(k => console.log('   ' + k + '   ' + found[k][0]));
});
console.log(total ? ('=== 共 ' + total + ' 处 ===') : '=== 全部通过 ===');
