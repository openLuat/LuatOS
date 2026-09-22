/* 阶段 2：把「被其他页面用到的函数」从页面脚本挪到公共层。
   已知：地图页（pages/map.js）要画点位浮卡，直接调用 qualityOf() 与 hbText()，
        而它们原来定义在 pages/devices.js —— 多页面下设备页不加载就会 ReferenceError。
   幂等：带标记则跳过。用法：node _deploy/fix-crosspage.js
*/
const fs = require('fs');
const API = require('path').join(__dirname, '..', 'assets', 'js', 'api.js');
const DEV = require('path').join(__dirname, '..', 'assets', 'js', 'pages', 'devices.js');
const MARK = '/* ==== 跨页共用：由 _deploy/fix-crosspage.js 从 pages/devices.js 移入 ==== */';

const QUALITY = `/* 通信质量：按 4G 信号强度分级（离线无读数，直接判失联） */
function qualityOf(d){
  if (!d.online) return { lv: 0, text: '失联', color: cssVar('--muted') };
  /* 4G CSQ 原始值 0~31（来自 latest_location.signal），非模板的 dB 信噪比 */
  /* 设备不上报信号时（latest_location 无 signal 字段）如实显示“未上报”，不伪装成 0 */
  if (!d.hasSignal) return { lv: 0, text: '设备未上报信号', color: cssVar('--muted') };
  if (d.snr >= 20) return { lv: 4, text: 'CSQ ' + d.snr + ' · 优秀', color: cssVar('--green') };
  if (d.snr >= 15) return { lv: 3, text: 'CSQ ' + d.snr + ' · 良好', color: cssVar('--cyan') };
  if (d.snr >= 10) return { lv: 2, text: 'CSQ ' + d.snr + ' · 一般', color: cssVar('--amber') };
  return { lv: 1, text: 'CSQ ' + d.snr + ' · 较差', color: cssVar('--red') };
}`;

const HB = `/* 上报间隔文案（秒 → 可读文本） */
function hbText(sec){
  if (sec < 60) return sec + ' 秒前';
  if (sec < 3600) return Math.round(sec / 60) + ' 分钟前';
  return (sec / 3600).toFixed(1) + ' 小时前';
}`;

let api = fs.readFileSync(API, 'utf8');
if (api.indexOf(MARK) === -1) {
  if (!api.endsWith('\n')) api += '\n';
  api += '\n' + MARK + '\n' + QUALITY + '\n\n' + HB + '\n';
  fs.writeFileSync(API, api, 'utf8');
  console.log('api.js: 已移入 qualityOf / hbText');
} else console.log('api.js: 已存在，跳过');

let dev = fs.readFileSync(DEV, 'utf8');
[['qualityOf', QUALITY], ['hbText', HB]].forEach(function (pair) {
  if (dev.indexOf(pair[1]) > -1) {
    dev = dev.replace(pair[1], '/* ' + pair[0] + '() 已移到公共层 api.js（地图页也要用） */');
    console.log('devices.js: 已移除 ' + pair[0]);
  } else console.log('devices.js: 未找到 ' + pair[0] + ' 原文（可能已处理）');
});
fs.writeFileSync(DEV, dev, 'utf8');
