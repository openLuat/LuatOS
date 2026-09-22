/* 修复 fix-shared.js 的括号配对事故 + 完成剩余跨页搬迁（全部用显式字符串，不用正则配对大括号）
   事故：抽取 dvDT 时把 devices.js 从文件开头到 dvDT 的整段（约 1400 行）误搬进了 utils.js。
   做法：把 utils.js 里以「assets/js/pages/devices.js 拆出」开头到文件末尾的整块搬回 devices.js 头部。
   用法：node _deploy/fix-shared2.js
*/
const fs = require('fs');
const path = require('path');
const JS = path.join(__dirname, '..', 'assets', 'js');
const p = f => path.join(JS, f);
const read = f => fs.readFileSync(p(f), 'utf8');
const write = (f, t) => fs.writeFileSync(p(f), t, 'utf8');

/* ---------- 1. 把误搬的整块搬回 devices.js ---------- */
(function () {
  const MARK = 'assets/js/pages/devices.js —— 由 index.html 内联脚本拆出';
  let u = read('utils.js');
  const lines = u.split('\n');
  const start = lines.findIndex(l => l.indexOf(MARK) > -1);
  if (start === -1) { console.log('utils.js 里没有误搬块，跳过恢复'); return; }
  let chunkLines = lines.slice(start);
  while (chunkLines.length && chunkLines[chunkLines.length - 1].trim() === '') chunkLines.pop();
  const chunk = chunkLines.join('\n');
  let head = lines.slice(0, start);
  while (head.length && head[head.length - 1].trim() === '') head.pop();
  write('utils.js', head.join('\n') + '\n');

  let dev = read('pages/devices.js');
  dev = dev.replace(/^\/\* dvDT\(\) 已移到公共层（多页面下别的页面也要用） \*\/\n?/, '');
  write('pages/devices.js', chunk + '\n' + dev);
  console.log('已把 ' + chunkLines.length + ' 行搬回 pages/devices.js（utils.js 余 ' + head.length + ' 行）');
})();

/* ---------- 2. 剩余跨页搬迁（显式字符串） ---------- */
function moveLiteral(from, to, snippet, label, comment) {
  let src = read(from), dst = read(to);
  if (src.indexOf(snippet) === -1) { console.log('  跳过（源里没有） ' + label); return; }
  src = src.replace(snippet, comment || ('/* ' + label + '() 已移到公共层（多页面下别的页面也要用） */'));
  if (dst.indexOf(snippet) === -1) {
    if (dst.indexOf('跨页共用（由 _deploy/fix-shared') === -1) {
      if (!dst.endsWith('\n')) dst += '\n';
      dst += '\n/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */\n';
    }
    dst = dst.replace(/\s*$/, '\n') + '\n' + snippet.replace(/\s*$/, '') + '\n';
  }
  write(from, src); write(to, dst);
  console.log('  ' + label + ': ' + from + ' → ' + to);
}

const DV2 = `/* ---------- 时间文案 ---------- */
const dv2 = n => String(n).padStart(2, '0');`;

const PROBE = `/* 量出单行高度（含下外边距）：行样式固定，探针量一次即可推算每页条数
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
}`;

const ALERTPICK = `function alertClickable(){
  return DV_ALERT_VIEWS.indexOf(activeViewName()) > -1;
}`;

const DVAV = `/* 告警条目可点击的视图：告警中心里点告警会跳到设备管理查看该设备 */
const DV_ALERT_VIEWS = ['告警中心'];`;

console.log('剩余跨页搬迁：');
moveLiteral('pages/devices.js', 'utils.js', DV2, 'dv2');
moveLiteral('pages/devices.js', 'components.js', PROBE, 'probeRowHeight');
moveLiteral('pages/devices.js', 'pages/alerts.js', DVAV, 'DV_ALERT_VIEWS');
moveLiteral('pages/devices.js', 'pages/alerts.js', ALERTPICK, 'alertClickable');

/* ---------- 3. devices.js：尺寸变化时只重绘本页登记过的渲染器 ---------- */
(function () {
  let t = read('pages/devices.js');
  const old = `    renderKpi(data);
    renderDevices(data);
    renderAlerts(data);`;
  if (t.indexOf(old) > -1) {
    t = t.replace(old, `    /* 多页面：只重绘本页登记过的面板（别的页面的渲染函数本页没有） */
    if (typeof runPageRenderers === 'function') runPageRenderers();`);
    write('pages/devices.js', t);
    console.log('  devices.js: 尺寸变化重绘改为只跑本页渲染器');
  } else console.log('  devices.js: 未找到尺寸变化重绘块');
})();

/* ---------- 4. 校验搬迁结果 ---------- */
['utils.js', 'components.js', 'pages/devices.js', 'pages/alerts.js'].forEach(f => {
  const t = read(f);
  console.log('  ' + f + ': ' + t.split('\n').length + ' 行');
});
