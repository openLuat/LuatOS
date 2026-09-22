/* 阶段 2：把「被其他页面调用、但定义在本页脚本里」的函数挪到公共层。
   检查依据：_deploy/check-crosspage.js 的输出。
   做法：按大括号配对精确抽取函数原文，再从原文件删除、追加到目标文件（幂等）。
   用法：node _deploy/fix-shared.js
*/
const fs = require('fs');
const path = require('path');
const JS = path.join(__dirname, '..', 'assets', 'js');
const p = f => path.join(JS, f);

/* 抽取一个顶层 function 的完整原文（含其上方紧邻的注释行） */
function cutFunction(text, name) {
  const re = new RegExp('(?:^|\\n)((?:[^\\n]*\\n)*?)(function\\s+' + name + '\\s*\\([^)]*\\)\\s*\\{)');
  const m = re.exec(text);
  if (!m) return null;
  const startIdx = m.index + (m[0][0] === '\n' ? 1 : 0);
  const bodyStart = text.indexOf(m[2], startIdx);
  let i = bodyStart + m[2].length, depth = 1;
  while (i < text.length && depth > 0) {
    const c = text[i];
    if (c === '{') depth++;
    else if (c === '}') depth--;
    i++;
  }
  /* 注释头只保留紧邻的连续注释行 */
  let headStart = startIdx;
  const before = text.slice(0, startIdx).split('\n');
  let k = before.length - 1;
  while (k >= 0 && /^\s*(\/\*|\*|\/\/|$)/.test(before[k])) k--;
  headStart = before.slice(0, k + 1).join('\n').length + (k + 1 > 0 ? 1 : 0);
  const full = text.slice(headStart, i).replace(/^\s+/, '');
  return { full: full, from: headStart, to: i };
}

function cutLine(text, needle) {
  const idx = text.indexOf(needle);
  if (idx === -1) return null;
  const s = text.lastIndexOf('\n', idx) + 1;
  const e = text.indexOf('\n', idx);
  return { full: text.slice(s, e + 1), from: s, to: e + 1 };
}

function move(fromFile, toFile, kind, name, extraNeedle) {
  let src = fs.readFileSync(p(fromFile), 'utf8');
  let dst = fs.readFileSync(p(toFile), 'utf8');
  const MARK = '/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */';
  if (dst.indexOf(name) > -1 && dst.indexOf(MARK) > -1 && new RegExp('function\\s+' + name + '\\s*\\(').test(dst)) {
    console.log('  跳过（目标已存在） ' + name); return;
  }
  const got = kind === 'fn' ? cutFunction(src, name) : cutLine(src, extraNeedle || name);
  if (!got) { console.log('  !! 源里找不到 ' + name + '（' + fromFile + '）'); return; }
  src = src.slice(0, got.from) + '/* ' + name + '() 已移到公共层（多页面下别的页面也要用） */\n' + src.slice(got.to);
  if (dst.indexOf(MARK) === -1) { if (!dst.endsWith('\n')) dst += '\n'; dst += '\n' + MARK + '\n'; }
  dst += '\n' + got.full.replace(/\s+$/, '') + '\n';
  fs.writeFileSync(p(fromFile), src, 'utf8');
  fs.writeFileSync(p(toFile), dst, 'utf8');
  console.log('  ' + name + ': ' + fromFile + ' → ' + toFile);
}

console.log('移动跨页共用函数：');
move('pages/alerts.js', 'utils.js', 'fn', 'timeText');
move('pages/map.js', 'utils.js', 'fn', 'locHash');
move('pages/devices.js', 'utils.js', 'fn', 'dvDT');
move('pages/devices.js', 'utils.js', 'line', 'dv2', 'const dv2 = n =>');
move('pages/devices.js', 'components.js', 'fn', 'probeRowHeight');
move('pages/devices.js', 'pages/alerts.js', 'fn', 'alertClickable');
move('pages/devices.js', 'pages/alerts.js', 'line', 'DV_ALERT_VIEWS', "const DV_ALERT_VIEWS = ['告警中心'];");

/* shell.js：alertWeekCache 只存在于告警页，其他页面不能直接引用 */
(function () {
  const f = p('shell.js');
  let t = fs.readFileSync(f, 'utf8');
  const old = `    /* 设备集合已变化：先作废该项目的 7 天态势缓存，再渲染（渲染时会按新设备集合重新拉取） */
    delete alertWeekCache[prj.id];`;
  if (t.indexOf(old) > -1) {
    t = t.replace(old, `    /* 设备集合已变化：7 天态势缓存是「告警中心」页自己的内存态，
       多页面下其它页面没有这个变量，因此这里不再跨页清理（重新加载那一页时自然重建） */`);
    fs.writeFileSync(f, t, 'utf8');
    console.log('  shell.js: 去掉跨页引用 alertWeekCache');
  } else console.log('  shell.js: 未找到 alertWeekCache 引用（可能已处理）');
})();

/* devices.js：窗口尺寸变化的重绘只跑「本页」登记过的渲染函数 */
(function () {
  const f = p('pages/devices.js');
  let t = fs.readFileSync(f, 'utf8');
  const old = `    renderKpi(data);
    renderDevices(data);
    renderAlerts(data);`;
  if (t.indexOf(old) > -1) {
    t = t.replace(old, `    /* 多页面：只重绘本页登记过的面板，别的页面的渲染函数本页没有 */
    if (typeof runPageRenderers === 'function') runPageRenderers();`);
    fs.writeFileSync(f, t, 'utf8');
    console.log('  devices.js: 尺寸变化重绘改为只跑本页渲染器');
  } else console.log('  devices.js: 未找到尺寸变化重绘块（可能已处理）');
})();
