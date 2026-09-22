/* 把「通知渠道配置」这类跨页共享的顶层常量从设置页搬到公共层 api.js。
   做法：从行首 const NAME 开始，扫到第一行以 ] 或 } 或 ; 结尾且顶格的行（不用大括号配对，避免上次的事故）。
   用法：node _deploy/fix-shared4.js
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
    for (let i = start + 1; i < lines.length; i++) {
      if (/^[\]};]/.test(lines[i])) { end = i; break; }
    }
  }
  return { start: start, end: end, text: lines.slice(start, end + 1).join('\n') };
}

function moveConst(from, to, name) {
  let src = read(from), dst = read(to);
  if (dst.indexOf('function ntMeta') === -1 && new RegExp('^(const|let|var)\\s+' + name + '\\b', 'm').test(dst)) {
    console.log('  跳过（目标已存在） ' + name); return;
  }
  const got = cutConst(src, name);
  if (!got) { console.log('  跳过（源里没有） ' + name); return; }
  src = src.replace(got.text, '/* ' + name + ' 已移到公共层 api.js（告警中心的通知通道展示也要用） */');
  if (dst.indexOf(MARK) === -1) { if (!dst.endsWith('\n')) dst += '\n'; dst += '\n' + MARK + '\n'; }
  dst = dst.replace(/\s*$/, '\n') + '\n' + got.text + '\n';
  write(from, src); write(to, dst);
  console.log('  ' + name + ': ' + from + ' → ' + to);
}

console.log('搬迁通知渠道共享常量：');
moveConst('pages/settings.js', 'api.js', 'NOTIFY_KEY');
moveConst('pages/settings.js', 'api.js', 'NOTIFY_META');
moveConst('pages/settings.js', 'api.js', 'NOTIFY_GROUP');
moveConst('pages/settings.js', 'api.js', 'notifyCfg');
['utils.js', 'api.js', 'pages/settings.js', 'pages/alerts.js'].forEach(f => console.log('  ' + f + ': ' + read(f).split('\n').length + ' 行'));
