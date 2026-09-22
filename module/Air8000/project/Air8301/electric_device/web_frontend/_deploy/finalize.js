/* 阶段 2 收尾：统一 logo 引用（根目录真实 64×64 logo.png）+ 生成 404.html。
   用法：先跑 PowerShell 生成 logo.png，再执行 node _deploy/finalize.js
*/
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const PAGES = [
  ['index.html', ''],
  ['login.html', ''],
  ['pages/devices.html', '../'],
  ['pages/alerts.html', '../'],
  ['pages/map.html', '../'],
  ['pages/topo.html', '../'],
  ['pages/settings.html', '../']
];

let changed = 0;
PAGES.forEach(function (pair) {
  const file = path.join(ROOT, pair[0]), rel = pair[1];
  if (!fs.existsSync(file)) { console.log('跳过（不存在） ' + pair[0]); return; }
  let t = fs.readFileSync(file, 'utf8');
  const before = t;
  /* 1) 统一引用根目录 logo.png（相对当前页层级） */
  t = t.replace(/src="(?:\.\.\/)?luat-logo\.png"/g, 'src="' + rel + 'logo.png"');
  /* 2) favicon 也指向同一份（规范要求统一 Logo） */
  if (t.indexOf('rel="icon"') === -1) {
    t = t.replace('</head>', '<link rel="icon" type="image/png" href="' + rel + 'logo.png">\n</head>');
  }
  if (t !== before) { fs.writeFileSync(file, t, 'utf8'); changed++; console.log('已更新 ' + pair[0]); }
  else console.log('无需改动 ' + pair[0]);
});

/* 3) 404.html：与全站同一套主题变量，给出来路与两个出口 */
const p404 = `<!DOCTYPE html>
<html lang="zh-CN" data-theme="nebula">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>页面不存在 · 上海合宙</title>
<link rel="icon" type="image/png" href="logo.png">
<link rel="stylesheet" href="assets/css/variables.css">
<link rel="stylesheet" href="assets/css/reset.css">
<link rel="stylesheet" href="assets/css/layout.css">
<link rel="stylesheet" href="assets/css/components.css">
<link rel="stylesheet" href="assets/css/components-dialog.css">
<link rel="stylesheet" href="assets/css/responsive.css">
</head>
<body data-page="404">
<canvas id="bg"></canvas>
<div class="app" style="display:block">
  <div class="main" style="height:100vh">
    <div class="grid" id="grid" style="grid-template-rows:minmax(0,1fr);place-items:center">
      <div class="panel span12" style="max-width:520px;text-align:center">
        <div class="panel-body" style="padding:34px 22px">
          <img src="logo.png" alt="LuatOS" width="64" height="64" style="border-radius:16px">
          <h3 style="margin:16px 0 6px;font-size:19px">404 · 页面不存在</h3>
          <p style="color:var(--dim);font-size:12.5px;line-height:1.9;margin:0 0 20px">
            你访问的地址没有对应页面，可能是链接过期或文件名拼写有误。<br>
            可以从下面两个入口继续。
          </p>
          <div style="display:flex;gap:10px;justify-content:center;flex-wrap:wrap">
            <a class="set-btn primary" href="index.html" style="text-decoration:none">回到控制台</a>
            <a class="set-btn" href="login.html" style="text-decoration:none">重新登录</a>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
</body>
</html>
`;
fs.writeFileSync(path.join(ROOT, '404.html'), p404, 'utf8');
console.log('已生成 404.html');
console.log('共更新 ' + changed + ' 个页面');
