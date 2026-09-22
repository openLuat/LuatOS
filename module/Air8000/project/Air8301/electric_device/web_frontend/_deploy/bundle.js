/* 把每个页面的 CSS / JS 按原有顺序合并成单文件（每页 1 个 CSS + 1 个 JS），
   页面只引用合并产物 —— 请求数从 33 降到 ~5，切页时间主要就省在这里。
   模块文件（assets/css/**、assets/js/**）仍然是唯一源码，本脚本只是「打包产物」生成器：
   先备份拆包前的 HTML 到 _deploy/html-modules/，需要还原时执行 node _deploy/bundle.js --revert
   用法：node _deploy/bundle.js
*/
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/* 全站唯一的构建号（同一次打包的所有页面完全一致）：
   —— 页面上注入并在控制台打印的就是它，用来一眼判断"跑的是哪一版"；
   —— 产物引用的 ?v= 仍用每页内容哈希（内容没变就不重复下载）。 */
const BUILD_TIME = (function(){
  const d = new Date(Date.now() + 8 * 3600 * 1000);   /* 北京时间 */
  const p = n => String(n).padStart(2, '0');
  return d.getUTCFullYear() + '年' + p(d.getUTCMonth() + 1) + '月' + p(d.getUTCDate()) + '日 ' +
         p(d.getUTCHours()) + ':' + p(d.getUTCMinutes()) + ':' + p(d.getUTCSeconds());
})();
const BUILD_ID = (function(){
  const d = new Date(Date.now() + 8 * 3600 * 1000);   /* 按北京时间显示 */
  const p = n => String(n).padStart(2, '0');
  return 'build ' + p(d.getUTCMonth() + 1) + '-' + p(d.getUTCDate()) + ' ' + p(d.getUTCHours()) + ':' + p(d.getUTCMinutes());
})();
const ROOT = path.resolve(__dirname, '..');
const PAGES = ['index.html', 'pages/devices.html', 'pages/alerts.html', 'pages/map.html', 'pages/topo.html', 'pages/settings.html'];
const BK = path.join(ROOT, '_deploy', 'html-modules');

if (process.argv.includes('--revert')) {
  PAGES.forEach(p => {
    const b = path.join(BK, p.replace('/', '__'));
    if (fs.existsSync(b)) { fs.copyFileSync(b, path.join(ROOT, p)); console.log('已还原 ' + p); }
  });
  process.exit(0);
}

fs.mkdirSync(BK, { recursive: true });
let total = 0;
/* 全站唯一的时间源（页脚读它，见 shell.js renderPublishFoot）：
   —— 页面 HTML 里注入的 __buildTime 是「这份 HTML 打包那一刻」的时间，一旦浏览器/网关
      缓存住旧 HTML，页脚就会停在旧值（实际出现过「运营总览和其他菜单时间不一致」）；
   —— 这里额外产出一个小文件，页脚按时间戳绕开缓存去读，因此无论页面本身缓存成什么版本，
      只要服务器上是新版，全站页脚就显示同一份「最新发布时间」。 */
const bundleDirEarly = path.join(ROOT, 'assets', 'bundle');
fs.mkdirSync(bundleDirEarly, { recursive: true });
fs.writeFileSync(path.join(bundleDirEarly, 'version.json'),
  JSON.stringify({ build: BUILD_ID, buildTime: BUILD_TIME }), 'utf8');

PAGES.forEach(p => {
  const file = path.join(ROOT, p);
  if (!fs.existsSync(file)) return;
  let html = fs.readFileSync(file, 'utf8');
  const rel = p.includes('/') ? '../' : '';
  const EOL = html.includes('\r\n') ? '\r\n' : '\n';
  /* 备份「引用模块文件」的版本，便于一键还原 */
  const bak = path.join(BK, p.replace('/', '__'));
  if (!fs.existsSync(bak)) fs.writeFileSync(bak, html, 'utf8');

  const css = [...html.matchAll(/<link rel="stylesheet" href="(?:\.\.\/)?assets\/css\/([^"]+)">/g)].map(m => m[1]);
  const js = [...html.matchAll(/<script (?:defer )?src="(?:\.\.\/)?assets\/js\/([^"]+)"><\/script>/g)].map(m => m[1]);
  /* data-lazy 的模块单独打成「延迟分包」：首屏不加载，由 boot.js 在首屏渲染后注入 */
  const lazy = [...html.matchAll(/<script src="(?:\.\.\/)?assets\/js\/([^"]+)" data-lazy><\/script>/g)].map(m => m[1]);
  if (!css.length || !js.length) { console.log('跳过（没有模块引用，可能已打包） ' + p); return; }

  const name = p.replace('pages/', '').replace('.html', '');
  const bundleDir = path.join(ROOT, 'assets', 'bundle');
  fs.mkdirSync(bundleDir, { recursive: true });
  const header = '/* 打包产物（合并顺序 = 模块加载顺序，勿手改）：';
  const cssOut = header + css.map(c => c).join(' + ') + ' */\n' +
    css.map(f => fs.readFileSync(path.join(ROOT, 'assets/css', f), 'utf8')).join('\n');
  const jsOut = header + js.join(' + ') + ' */\n' +
    js.map(f => fs.readFileSync(path.join(ROOT, 'assets/js', f), 'utf8')).join('\n');
  fs.writeFileSync(path.join(bundleDir, name + '.css'), cssOut, 'utf8');
  fs.writeFileSync(path.join(bundleDir, name + '.js'), jsOut, 'utf8');
  let lazyKb = 0, lazyOutText = '';
  if (lazy.length){
    const lazyOut = header + lazy.join(' + ') + ' */\n' +
      lazy.map(f => fs.readFileSync(path.join(ROOT, 'assets/js', f), 'utf8')).join('\n');
    fs.writeFileSync(path.join(bundleDir, name + '-lazy.js'), lazyOut, 'utf8');
    lazyKb = Buffer.byteLength(lazyOut);
    lazyOutText = lazyOut;
  }
  /* 内容哈希：只有内容真的变了版本号才变（避免每次都让用户重下） */
  const stamp = crypto.createHash('sha1').update(cssOut).update(jsOut).update(lazyOutText).digest('hex').slice(0, 8);

  /* 用打包产物替换模块引用（保留注释说明来源） */
  html = html.replace(/<!-- 公共样式[\s\S]*?-->\n/, '');
  html = html.replace(/<!-- 本页专属样式[^\n]*-->\n/, '');
  html = html.replace(/(<link rel="stylesheet" href="(?:\.\.\/)?assets\/css\/[^"]+">\n?)+/,
    '<link rel="stylesheet" href="' + rel + 'assets/bundle/' + name + '.css?v=' + stamp + '">\n');
  html = html.replace(/<!-- 公共能力与页面脚本[^\n]*-->\n/, '');
  if (lazy.length){
    /* 延迟分包不进 HTML：只在 body 上留地址，由 boot.js 首屏之后注入 */
    html = html.replace(/(<script src="(?:\.\.\/)?assets\/js\/[^"]+" data-lazy><\/script>\n?)+/, '');
    html = html.replace(/<body ([^>]*)>/,
      '<body $1 data-lazy-bundle="' + rel + 'assets/bundle/' + name + '-lazy.js?v=' + stamp + '">');
  }
  html = html.replace(/(<script (?:defer )?src="(?:\.\.\/)?assets\/js\/[^"]+"><\/script>\n?)+/,
    '<script defer src="' + rel + 'assets/bundle/' + name + '.js?v=' + stamp + '"></script>\n');
  /* 构建号写进页面：出问题时一眼看出用户页面跑的是哪一版。
     同时在这里「提前定主题」—— 页面默认是 :root（星云蓝），而主题一直是由 shell.js 里
     applyTheme() 应用的，那段代码在**延迟加载的 bundle** 里，要等首屏画完才执行，
     于是切换菜单（整页加载）时会先闪一下星云蓝再变成所选主题（用户实测反馈）。
     这段内联脚本紧跟 <body> 之后同步执行，早于 bundle、也早于首屏渲染，所以不会闪。
     存储键与取值必须与 shell.js 的 applyTheme() 保持一致（'nexus-theme'，三个主题名）。 */
  html = html.replace(/<body ([^>]*)>/,
    '<body $1><script>window.__build="' + BUILD_ID + '";window.__buildTime="' + BUILD_TIME + '";' +
    '(function(){try{var t=localStorage.getItem("nexus-theme");' +
    'if(t==="aurora"||t==="dawn"||t==="mist")document.documentElement.setAttribute("data-theme",t);' +
    'window.__themeEarlyAt=document.readyState;}catch(e){}})();' +
    'console.log("[build] " + window.__build + " / " + window.__buildTime);</script>');
  fs.writeFileSync(file, html, 'utf8');

  const kb = n => (n / 1024).toFixed(1) + ' KB';
  total += css.length + js.length + lazy.length;
  console.log('  ' + p.padEnd(22) + ' ' + BUILD_ID + ' (v=' + stamp + ')  CSS ' + css.length + '→1 (' + kb(Buffer.byteLength(cssOut)) + ')   JS ' + js.length + '→1 (' + kb(Buffer.byteLength(jsOut)) + ')' +
    (lazy.length ? '   延迟分包 ' + lazy.join(' + ') + ' (' + kb(lazyKb) + ')' : ''));
});
console.log('原模块引用合计 ' + total + ' 个 → 现每页 1 CSS + 1 JS');

/* ---- 收官自检：六个页面必须都处于「已打包」状态 ----
   历史事故：还原（--revert）会把页面写回「逐个引用模块」的形态，如果之后没有重新打包，
   这些页面就没有 assets/bundle 引用、也没有 window.__buildTime 注入 —— 表现是侧栏页脚
   只能显示「发布于：--」（网络拓扑 / 系统设置两页曾长期如此）。
   这里在打包结束时强制校验，缺失即报错退出（非 0），让漏打包无法悄悄上线。 */
const unpacked = [];
PAGES.forEach(p => {
  const f = path.join(ROOT, p);
  if (!fs.existsSync(f)) return;
  const h = fs.readFileSync(f, 'utf8');
  const name = p.replace('pages/', '').replace('.html', '');
  if (!new RegExp('assets/bundle/' + name + '\\.(js|css)').test(h)) unpacked.push(p + '（缺 bundle 引用，仍是模块引用形态）');
  else if (!/window\.__buildTime=/.test(h)) unpacked.push(p + '（缺构建时间注入）');
});
if (unpacked.length){
  console.error('✗ 打包自检失败，以下页面未正确打包：\n  ' + unpacked.join('\n  ') +
    '\n  处理：先 node _deploy/bundle.js --revert（还原为模块引用），再 node _deploy/bundle.js 重新打包');
  process.exit(1);
}
console.log('✓ 打包自检通过：' + PAGES.length + ' 个页面均已引用 bundle 且已注入构建号');
