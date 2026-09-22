/* 收尾 2：NOTIFY_DEF（api.js 里的 notifyCfg 初始化要用）与告警行探针常量（告警页要用）
   仍留在设置页 / 设备页，搬到公共层或本页。仍用「行首终止符」方式，不做大括号配对。
   用法：node _deploy/fix-shared5.js
*/
const fs = require('fs');
const path = require('path');
const JS = path.join(__dirname, '..', 'assets', 'js');
const p = f => path.join(JS, f);
const read = f => fs.readFileSync(p(f), 'utf8');
const write = (f, t) => fs.writeFileSync(p(f), t, 'utf8');
const MARK = '/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */';

function cutConst(text, name) {
  const lines = text.split('\n');
  const start = lines.findIndex(l => new RegExp('^(const|let|var)\\s+' + name + '\\b').test(l));
  if (start === -1) return null;
  let end = start;
  if (!/;\s*$/.test(lines[start])) {
    for (let i = start + 1; i < lines.length; i++) if (/^[\]};]/.test(lines[i])) { end = i; break; }
  }
  return { text: lines.slice(start, end + 1).join('\n') };
}
function moveConst(from, to, name) {
  let src = read(from), dst = read(to);
  const got = cutConst(src, name);
  if (!got) { console.log('  跳过（源里没有） ' + name); return; }
  src = src.replace(got.text, '/* ' + name + ' 已移到 ' + to + ' */');
  if (dst.indexOf(MARK) === -1) { if (!dst.endsWith('\n')) dst += '\n'; dst += '\n' + MARK + '\n'; }
  if (new RegExp('^(const|let|var)\\s+' + name + '\\b', 'm').test(dst)) console.log('  目标已有 ' + name + '，仅从源删除');
  else dst = dst.replace(/\s*$/, '\n') + '\n' + got.text + '\n';
  write(from, src); write(to, dst);
  console.log('  ' + name + ': ' + from + ' → ' + to);
}

console.log('收尾搬迁：');
moveConst('pages/settings.js', 'api.js', 'NOTIFY_DEF');
moveConst('pages/devices.js', 'pages/alerts.js', 'ALERT_ROW_PROBE');
moveConst('pages/devices.js', 'pages/alerts.js', 'ALERT_PROBE_RICH');
