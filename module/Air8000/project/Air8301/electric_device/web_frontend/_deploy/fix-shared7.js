/* 最后一处错位：设备筛选 matchDevices() 被切在告警页脚本里，而调用方是设备页。
   挪回 pages/devices.js（同样只从行首 function 处做括号配对）。
   用法：node _deploy/fix-shared7.js
*/
const fs = require('fs');
const path = require('path');
const JS = path.join(__dirname, '..', 'assets', 'js');
const p = f => path.join(JS, f);
const read = f => fs.readFileSync(p(f), 'utf8');
const write = (f, t) => fs.writeFileSync(p(f), t, 'utf8');

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
  /* 连同紧邻的上一行注释一起搬走 */
  let from = start;
  const before = text.slice(0, start).split('\n');
  if (before.length >= 2 && /^\s*\/\*/.test(before[before.length - 2])) {
    from = text.lastIndexOf('\n', text.slice(0, start).lastIndexOf('\n') - 1) + 1;
  }
  return { from: from, to: i, text: text.slice(from, i) };
}

let src = read('pages/alerts.js'), dst = read('pages/devices.js');
const got = cutFnSafe(src, 'matchDevices');
if (!got) console.log('alerts.js 里没有 matchDevices，跳过');
else {
  src = src.slice(0, got.from) + '/* matchDevices() 属于设备管理页逻辑，已移回 pages/devices.js */\n' + src.slice(got.to);
  const anchor = '\nfunction renderDevices(data){';
  const at = dst.indexOf(anchor);
  const block = '\n' + got.text.replace(/\s*$/, '') + '\n';
  if (at > -1) dst = dst.slice(0, at) + block + dst.slice(at);
  else dst = dst.replace(/\s*$/, '\n') + block;
  write('pages/alerts.js', src);
  write('pages/devices.js', dst);
  console.log('matchDevices: pages/alerts.js → pages/devices.js（' + got.text.split('\n').length + ' 行）');
}
console.log('  alerts.js ' + read('pages/alerts.js').split('\n').length + ' 行 / devices.js ' + read('pages/devices.js').split('\n').length + ' 行');
