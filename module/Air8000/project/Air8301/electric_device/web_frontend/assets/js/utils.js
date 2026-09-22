/* assets/js/utils.js —— 由 index.html 内联脚本拆出（原行区间 3163-3202），内容未改动 */
/* =========================================================
   App.utils
   ========================================================= */
App.utils = {
  maskMobile: function(v){ var s = String(v || ''); return s.length < 7 ? s : s.slice(0, 3) + '****' + s.slice(-4); },
  pad2: function(n){ return (n < 10 ? '0' : '') + n; },
  formatTime: function(ts){
    var d = new Date(ts);
    return d.getFullYear() + '-' + this.pad2(d.getMonth() + 1) + '-' + this.pad2(d.getDate()) +
      ' ' + this.pad2(d.getHours()) + ':' + this.pad2(d.getMinutes()) + ':' + this.pad2(d.getSeconds());
  },
  parseLocal: function(s){
    if (!s || typeof s !== 'string') return NaN;
    var m = s.match(/(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
    if (!m) return Date.parse(s);
    return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime();
  },
  formatLocalParam: function(ts){
    var d = new Date(ts);
    return d.getFullYear() + '-' + this.pad2(d.getMonth() + 1) + '-' + this.pad2(d.getDate()) +
      ' ' + this.pad2(d.getHours()) + ':' + this.pad2(d.getMinutes()) + ':' + this.pad2(d.getSeconds());
  },
  fromNow: function(ts){
    if (!ts || isNaN(ts)) return '--';
    var sec = Math.max(0, Math.round((Date.now() - ts) / 1000));
    if (sec < 60) return sec + ' 秒前';
    if (sec < 3600) return Math.round(sec / 60) + ' 分钟前';
    if (sec < 86400) return Math.round(sec / 3600) + ' 小时前';
    return Math.round(sec / 86400) + ' 天前';
  },
  str: function(v){ return (v === undefined || v === null || v === '') ? '--' : String(v); },
  num: function(v){ var n = Number(v); return isFinite(n) ? n : NaN; },
  workStatusText: function(v){
    if (v === 1 || v === '1') return '运行中';
    if (v === 0 || v === '0') return '已关机';
    if (v === 255 || v === '255') return '未同步';
    return '--';
  }
};


/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */

/* assets/js/pages/alerts.js —— 由 index.html 内联脚本拆出（原行区间 4495-5096），内容未改动 */
/* =========================================================
   7. 告警中心
   ========================================================= */
/* 相对时间（每次渲染刷新）与绝对时间（悬停查看） */
function timeText(ts){
  if (!ts) return '--';
  const sec = Math.max(0, Math.round((Date.now() - ts) / 1000));
  if (sec < 60) return '刚刚';
  if (sec < 3600) return Math.round(sec / 60) + ' 分钟前';
  if (sec < 86400) return Math.round(sec / 3600) + ' 小时前';
  return Math.round(sec / 86400) + ' 天前';
}

/* ---------- 字符串哈希（数据报表的确定性取值也用它） ---------- */
function locHash(s){
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h % 100003;
}

/* ---------- 时间文案 ---------- */
const dv2 = n => String(n).padStart(2, '0');

/* 短时间戳：MM-DD HH:mm
   —— 设备管理（数据报表/CSV/曲线坐标）与系统设置（推送记录/测试消息）共用，
      拆模块时这个函数漏搬了一次，导致点「数据报表」抛 ReferenceError: dvDT is not defined */
function dvDT(ts){
  const d = new Date(ts);
  return dv2(d.getMonth() + 1) + '-' + dv2(d.getDate()) + ' ' + dv2(d.getHours()) + ':' + dv2(d.getMinutes());
}

function activeViewName(){
  return window.nexusCurrentView || '运营总览';
}
