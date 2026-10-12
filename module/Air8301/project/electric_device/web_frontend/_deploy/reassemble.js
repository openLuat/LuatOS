/* 反向操作：把 assets/css/* + assets/js/* 与 index.html 的壳重新合成单文件版本，
   产出 _deploy/index.single-file.bak 作为「一键回滚包」（遇到子目录部署异常时可直接替换 index.html）。
   顺带做完整性自检：CSS/JS 内容行数必须与拆分前一致（CSS 11-2233 = 2223 行，JS 2934-9700 = 6767 行）。
   用法：node _deploy/reassemble.js
*/
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const INDEX = path.join(ROOT, 'index.html');
const OUT = path.join(ROOT, '_deploy', 'index.single-file.bak');

const src = fs.readFileSync(INDEX, 'utf8');
const EOL = src.includes('\r\n') ? '\r\n' : '\n';
const lines = src.split(/\r?\n/);
const cssFiles = [...src.matchAll(/<link rel="stylesheet" href="assets\/css\/([^"]+)">/g)].map(m => m[1]);
const jsFiles = [...src.matchAll(/<script src="assets\/js\/([^"]+)"><\/script>/g)].map(m => m[1]);

const iStyleComment = lines.findIndex(l => l.includes('<!-- 公共样式'));
const iScriptComment = lines.findIndex(l => l.includes('<!-- 公共能力与页面脚本'));
const lastLink = lines.reduce((a, l, i) => (l.includes('rel="stylesheet"') ? i : a), -1);
const lastScript = lines.reduce((a, l, i) => (l.includes('<script src="assets/js/') ? i : a), -1);

const head = lines.slice(0, iStyleComment === -1 ? lastLink : iStyleComment);
const body = lines.slice(lastLink + 1, iScriptComment === -1 ? lastScript : iScriptComment);
const tail = lines.slice(lastScript + 1);

/* 读取拆出的文件并去掉首行「来源说明」注释 */
function readStripped(rel, dir) {
  const text = fs.readFileSync(path.join(ROOT, dir, rel), 'utf8');
  const ls = text.split(/\r?\n/);
  if (ls.length && ls[0].startsWith('/*')) ls.shift();
  /* 只去掉写文件时补的那个结尾换行，不裁剪内容里的空行（否则行数对不上） */
  if (ls.length && ls[ls.length - 1] === '') ls.pop();
  return ls;
}
const cssLines = cssFiles.flatMap(f => readStripped(f, 'assets/css'));
const jsLines = jsFiles.flatMap(f => readStripped(f, 'assets/js'));

const out = []
  .concat(head)
  .concat(['<style>'])
  .concat(cssLines)
  .concat(['</style>'])
  .concat(body)
  .concat(['<script>'])
  .concat(jsLines)
  .concat(['</script>'])
  .concat(tail)
  .join(EOL);
fs.writeFileSync(OUT, out, 'utf8');

console.log('CSS 文件 ' + cssFiles.length + ' 个 → 合并 ' + cssLines.length + ' 行（拆分前应为 2223 行）');
console.log('JS  文件 ' + jsFiles.length + ' 个 → 合并 ' + jsLines.length + ' 行（拆分前应为 6767 行）');
console.log('回滚包: ' + OUT + '  ' + Buffer.byteLength(out, 'utf8') + ' bytes（拆分前 424732 bytes，差值为新增/去掉的注释与标签）');
console.log('完整性: CSS ' + (cssLines.length === 2223 ? 'OK' : '不一致!') + '，JS ' + (jsLines.length === 6767 ? 'OK' : '不一致!'));
