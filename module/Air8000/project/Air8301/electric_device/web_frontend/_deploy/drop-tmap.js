/* 非地图页不该加载腾讯地图 SDK（它只服务「位置地图」页与「运营总览」的地图）。
   本脚本：
     1) 从 devices/alerts/topo/settings 四个页面里删掉 SDK 的 <script> 与其注释；
     2) 同步修正生成器 build-pages.js，让以后重新生成页面时也遵守 page.tmap 开关。
   用法：node _deploy/drop-tmap.js
*/
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const TARGETS = ['pages/devices.html', 'pages/alerts.html', 'pages/topo.html', 'pages/settings.html'];
const RE = /<!-- 腾讯位置服务[\s\S]*?-->\n?<script src="https:\/\/map\.qq\.com\/api\/gljs[^"]*"><\/script>\n?/;

let n = 0;
TARGETS.forEach(f => {
  const p = path.join(ROOT, f);
  let t = fs.readFileSync(p, 'utf8');
  if (RE.test(t)) { t = t.replace(RE, ''); fs.writeFileSync(p, t, 'utf8'); n++; console.log('  已移除 SDK: ' + f); }
  else console.log('  无需改动（没有 SDK 引用）: ' + f);
});

/* 同步生成器：head 只取到 <title> 后面的注释前，不再把 SDK 一起切过去 */
const g = path.join(ROOT, '_deploy', 'build-pages.js');
let gt = fs.readFileSync(g, 'utf8');
if (gt.indexOf('headBefore: [1, 6]') === -1) {
  gt = gt.replace('headBefore: [1, 9],', 'headBefore: [1, 6],   /* 只到 <title>，腾讯地图 SDK 由 page.tmap 决定是否加 */');
  gt = gt.replace(
    "  const head = seg(H.headBefore[0], H.headBefore[1]);",
    "  const head = seg(H.headBefore[0], H.headBefore[1]);\n  if (page.tmap){\n    head.push('<!-- 腾讯位置服务 JavaScript API GL：按 AirCloud 资源包《腾讯地图.md》要求，Key 为项目内置常量，只出现在本加载地址中 -->');\n    head.push('<script src=\"https://map.qq.com/api/gljs?v=1.exp&key=EZNBZ-VA6KW-ASMRR-3UE4S-M3QCO-EYBC6\"></script>');\n  }"
  );
  fs.writeFileSync(g, gt, 'utf8');
  console.log('  生成器已改为按 page.tmap 决定是否引入 SDK');
} else console.log('  生成器已是按 page.tmap 引入');
console.log('共处理 ' + n + ' 个页面');
