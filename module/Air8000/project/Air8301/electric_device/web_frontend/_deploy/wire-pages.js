/* 阶段 2：把各页自己的「重绘登记」与「页面参数处理」追加到对应页面 JS 末尾。
   幂等：已追加过（含标记）则跳过。
   用法：node _deploy/wire-pages.js
*/
const fs = require('fs');
const path = require('path');
const JS = path.join(__dirname, '..', 'assets', 'js', 'pages');
const MARK = '/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */';

const BLOCKS = {
  'overview.js': `
${MARK}
/* 运营总览页：KPI 卡 + 两张概览饼图 */
registerPageRenderer(function(data){ renderKpi(data); renderOverviewPies(data); });
`,
  'devices.js': `
${MARK}
/* 设备管理页：设备列表（含表格模式） */
registerPageRenderer(function(data){ renderDevices(data); });

/* 支持从地图/告警页跳过来直接打开某台设备：pages/devices.html?dev=<IMEI> */
onPageQuery(function(q){
  if (!q.dev) return;
  const id = String(q.dev);
  const d = (curData().devices || []).find(function(x){ return x.id === id; });
  if (!d){ toastErr('未找到设备 ' + id); return; }
  if (typeof openDeviceView === 'function') openDeviceView(d, 'basic');
});
`,
  'alerts.js': `
${MARK}
/* 告警中心页：三张指标 + 富列表 + 右侧态势 */
registerPageRenderer(function(data){ renderAlerts(data); renderAlertKpi(data); renderAlertSide(data); });
`,
  'topo.js': `
${MARK}
/* 网络拓扑页 */
registerPageRenderer(function(data){ buildTopo(data); });
`,
  'map.js': `
${MARK}
/* 位置地图页 */
registerPageRenderer(function(data){ buildLocationMap(data); });
`,
  'settings.js': `
${MARK}
/* 系统设置页 */
registerPageRenderer(function(){ renderSettings(); });

/* 支持从告警中心跳过来直接落在「通知设置」页签：pages/settings.html?tab=notify */
onPageQuery(function(q){
  if (q.tab === 'notify'){
    if (typeof setSetTab === 'function') setSetTab('notify');
    if (typeof renderSettings === 'function') renderSettings();
  }
});
`
};

let n = 0;
Object.keys(BLOCKS).forEach(function (f) {
  const p = path.join(JS, f);
  let txt = fs.readFileSync(p, 'utf8');
  if (txt.indexOf(MARK) > -1) { console.log('  跳过（已接线） ' + f); return; }
  if (!txt.endsWith('\n')) txt += '\n';
  fs.writeFileSync(p, txt + BLOCKS[f], 'utf8');
  n++;
  console.log('  已接线 ' + f);
});
console.log('完成，共修改 ' + n + ' 个页面脚本');
