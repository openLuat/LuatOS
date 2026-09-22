/* 收尾：把最后几处「被别的页面用到、却定义在设备页脚本里」的东西挪到公共层。
   注意：本脚本只从「行首 function 名」开始做括号配对，不再向前吞注释（上次的坑就在这里）。
   用法：node _deploy/fix-shared3.js
*/
const fs = require('fs');
const path = require('path');
const JS = path.join(__dirname, '..', 'assets', 'js');
const p = f => path.join(JS, f);
const read = f => fs.readFileSync(p(f), 'utf8');
const write = (f, t) => fs.writeFileSync(p(f), t, 'utf8');
const MARK = '/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */';

/* 从「行首 function name(」开始精确取到配对的大括号 */
function cutFnSafe(text, name) {
  const re = new RegExp('(^|\\n)(function\\s+' + name + '\\s*\\([^)]*\\)\\s*\\{)');
  const m = re.exec(text);
  if (!m) return null;
  const start = m.index + m[1].length;
  const braceIdx = text.indexOf('{', start + ('function ' + name).length);
  let i = braceIdx, depth = 0;
  for (; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') { depth--; if (depth === 0) { i++; break; } }
  }
  return { from: start, to: i, text: text.slice(start, i) };
}
function moveFn(from, to, name) {
  let src = read(from), dst = read(to);
  const got = cutFnSafe(src, name);
  if (!got) { console.log('  跳过（源里没有） ' + name); return; }
  src = src.slice(0, got.from) + '/* ' + name + '() 已移到公共层（多页面下别的页面也要用） */' + src.slice(got.to);
  if (dst.indexOf(MARK) === -1) { if (!dst.endsWith('\n')) dst += '\n'; dst += '\n' + MARK + '\n'; }
  if (dst.indexOf('function ' + name + '(') === -1) dst = dst.replace(/\s*$/, '\n') + '\n' + got.text + '\n';
  write(from, src); write(to, dst);
  console.log('  ' + name + ': ' + from + ' → ' + to);
}
function moveLiteral(from, to, snippet, label) {
  let src = read(from), dst = read(to);
  if (src.indexOf(snippet) === -1) { console.log('  跳过（源里没有） ' + label); return; }
  src = src.replace(snippet, '/* ' + label + ' 已移到 ' + to + '（属于该页的交互） */');
  if (dst.indexOf(MARK) === -1) { if (!dst.endsWith('\n')) dst += '\n'; dst += '\n' + MARK + '\n'; }
  if (dst.indexOf(snippet) === -1) dst = dst.replace(/\s*$/, '\n') + '\n' + snippet + '\n';
  write(from, src); write(to, dst);
  console.log('  ' + label + ': ' + from + ' → ' + to);
}

console.log('最后一批跨页搬迁：');
moveFn('pages/devices.js', 'components.js', 'bindSearch');            /* 设备列表与告警中心共用的搜索框逻辑 */
moveFn('pages/devices.js', 'utils.js', 'activeViewName');             /* 当前页名（告警页也要判断） */
moveLiteral('pages/devices.js', 'pages/alerts.js', `/* 告警中心：模糊搜索 */
bindSearch('alertSearch', 'alertClear', value => {
  state.alertQuery = value;
  state.alertPage = 1;
  renderAlerts(curData());
});`, '告警中心搜索绑定');
moveLiteral('pages/devices.js', 'pages/alerts.js', `/* 告警历史翻页 */
(function(){
  const prev = document.getElementById('alertPrev');
  const next = document.getElementById('alertNext');
  if (!prev || !next) return;
  prev.addEventListener('click', () => {
    if (state.alertPage <= 1) return;
    state.alertPage--;
    renderAlerts(curData());
  });
  next.addEventListener('click', () => {
    state.alertPage++;
    renderAlerts(curData());
  });
})();`, '告警历史翻页绑定');

/* 去掉 devices.js 里重复的 dvDT（公共层已有一份，设置页也要用） */
(function () {
  let t = read('pages/devices.js');
  const got = cutFnSafe(t, 'dvDT');
  if (got) {
    t = t.slice(0, got.from) + '/* dvDT() 在公共层 utils.js（系统设置页也要用） */' + t.slice(got.to);
    write('pages/devices.js', t);
    console.log('  去掉 pages/devices.js 里重复的 dvDT');
  } else console.log('  pages/devices.js 里没有重复的 dvDT');
})();
