/* 修 TDZ：api.js 里 notifyCfg 的初始化要用 NOTIFY_DEF，
   但搬迁时 NOTIFY_DEF 被追加在其后 → “Cannot access before initialization”。
   把 NOTIFY_DEF 整块挪到 notifyCfg 之前。用法：node _deploy/fix-shared6.js
*/
const fs = require('fs');
const API = require('path').join(__dirname, '..', 'assets', 'js', 'api.js');
let t = fs.readFileSync(API, 'utf8');
if (t.indexOf('NOTIFY_DEF') === -1) { console.log('api.js 里没有 NOTIFY_DEF，跳过'); process.exit(0); }

const lines = t.split('\n');
const s = lines.findIndex(l => /^const\s+NOTIFY_DEF\b/.test(l));
if (s === -1) { console.log('未找到 NOTIFY_DEF 声明行，跳过'); process.exit(0); }
let e = s;
if (!/;\s*$/.test(lines[s])) for (let i = s + 1; i < lines.length; i++) if (/^[\]};]/.test(lines[i])) { e = i; break; }
const block = lines.splice(s, e - s + 1);
const target = lines.findIndex(l => /^const\s+notifyCfg\b/.test(l));
if (target === -1) { console.log('未找到 notifyCfg 声明行，回滚不改'); process.exit(0); }
lines.splice(target, 0, ...block, '');
fs.writeFileSync(API, lines.join('\n'), 'utf8');
console.log('已把 NOTIFY_DEF（' + block.length + ' 行）移到 notifyCfg 之前（第 ' + (target + 1) + ' 行前）');
