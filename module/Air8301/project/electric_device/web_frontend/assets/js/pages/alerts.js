/* timeText() 已移到公共层（多页面下别的页面也要用） */


function fullTime(ts){
  const d = new Date(ts || Date.now()), p = n => String(n).padStart(2, '0');
  return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' +
         p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

/* ---------- 处置状态：只保留两种 —— 待处理 / 已处理 ---------- */
const ALERT_STATUS_TEXT = { pending:'待处理', done:'已处理' };
const ALERT_OWNERS = ['韩振飞','LZY','赵工','运维一班','电气组','王涛'];
const alertStatus = new Map();      /* 人工处置过的：项目|告警 → 状态 */
const alertDefaults = new Map();    /* 默认铺底状态：保证既有积压也有已处理 */
let alertDefaultsPrj = '';
/* 这里原有一个写死的渠道群名表（园区运维群 / 项目指挥群…），那是编造的信息，已删除：
   渠道状态一律以 notifyCfg（系统设置里的真实配置）为准，界面只展示真实存在的字段 */

function alertKey(a){ return a.deviceId + '|' + a.ts + '|' + a.title; }
function alertStatusOf(a){
  const k = curProject().id + '|' + alertKey(a);
  if (alertStatus.has(k)) return alertStatus.get(k);
  if (alertDefaults.has(k)) return alertDefaults.get(k);
  return a.level === 'info' ? 'done' : 'pending';
}
function setAlertStatus(a, st){ alertStatus.set(curProject().id + '|' + alertKey(a), st); }
function alertOwnerOf(a){ return ALERT_OWNERS[locHash(alertKey(a)) % ALERT_OWNERS.length]; }
/* 持续时长 / 分类都由告警自身派生，同一条每次渲染结果一致 */
function alertDurOf(a){ return 3 + locHash(alertKey(a)) % 57; }
const ALERT_CATS = [
  { name:'工作状态未同步', re:/未同步/ },
  { name:'数据上报中断',   re:/中断|失联|无数据/ },
  { name:'输出电压异常',   re:/输出异常|电压/ },
  { name:'通信与升级',     re:/校验|串口|升级|固件|FOTA|重连/ },
  { name:'设备接入',       re:/接入|注册|上线/ }
];
function alertCatOf(a){
  const t = a.title;
  for (let i = 0; i < ALERT_CATS.length; i++) if (ALERT_CATS[i].re.test(t)) return ALERT_CATS[i].name;
  return '其他事件';
}

/* 每个项目铺一次默认状态：最新 4 条待处理，其余（含提示级）都算已处理 */
function syncAlertDefaults(data){
  if (alertDefaultsPrj === data.project.id) return;
  alertDefaultsPrj = data.project.id;
  alertDefaults.clear();
  let pending = 0;
  data.alerts.forEach(a => {
    const k = data.project.id + '|' + alertKey(a);
    if (a.level === 'info'){ alertDefaults.set(k, 'done'); return; }
    if (pending < 4){ alertDefaults.set(k, 'pending'); pending++; }
    else alertDefaults.set(k, 'done');
  });
}

/* =========================================================
   近 7 天态势（真实数据）
   —— 数据来源：对项目内每台设备调用
      POST /open_api/aircloud/list_by_tags（tags = 799/800/265，
      filter.ct ∈ [7 天前 00:00, 现在]），把返回的历史记录按「天」分桶：
        · 严重 crit：实际电压(799) > 5500 V 的记录数
        · 警告 warn：设定电压(800) > 5000 V 且未越限的记录数
        · 提示 info：该设备「当天首次上报」计 1 条（上线/恢复）
   —— 设备之间串行 + 间隔 100ms（平台限频建议）；结果缓存 5 分钟；
      设备较多时逐台补齐，期间界面先渲染缓存/空值，不阻塞。
   ========================================================= */
const alertWeekCache = {};
const ALERT_WEEK_TTL = 5 * 60 * 1000;

function p2(n){ return (n < 10 ? '0' : '') + n; }
function dayKeyOf(ts){
  const d = new Date(ts);
  return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate());
}

function emptyAlertWeek(){
  const days = [];
  const now = new Date();
  for (let i = 6; i >= 0; i--){
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    days.push({
      key: dayKeyOf(d.getTime()),
      label: (d.getMonth() + 1) + '/' + d.getDate(),
      crit: 0, warn: 0, info: 0, total: 0
    });
  }
  return { days: days, cats: {}, total: 0, covered: 0,
           loaded: false, loading: false, at: 0, nextTryAt: 0 };
}

function alertWeek(prj){
  if (!prj) return emptyAlertWeek();
  let c = alertWeekCache[prj.id];
  if (!c){
    c = emptyAlertWeek();
    /* 切页回来时先用未过期的缓存：7 天态势要对每台设备逐台查历史，重算代价最高，
       命中缓存可直接显示，不必再等一轮串行查询 */
    const saved = (typeof cacheGet === 'function') ? cacheGet('week', prj) : null;
    if (saved && Array.isArray(saved.days) && (Date.now() - saved.at) < ALERT_WEEK_TTL){
      c.days = saved.days;
      c.cats = saved.cats || {};
      c.total = saved.total || 0;
      c.covered = saved.covered || 0;
      c.loaded = true;
      c.loading = false;
      c.at = saved.at;
    }
    alertWeekCache[prj.id] = c;
  }
  /* nextTryAt：上一轮查询失败（多为限频）后的退避时刻，避免失败即无限重试 */
  if (!c.loading && Date.now() >= (c.nextTryAt || 0) &&
      (Date.now() - c.at) > ALERT_WEEK_TTL){
    loadAlertWeek(prj);
  }
  return c;
}

function loadAlertWeek(prj){
  const c = alertWeekCache[prj.id];
  if (!c || c.loading) return;
  const data = projectData(prj);
  const devices = (data && data.devices) || [];
  if (!devices.length){ c.loaded = true; c.at = Date.now(); return; }

  c.loading = true;
  const now = new Date();
  const from = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6, 0, 0, 0);
  const filter = {
    aks: ['ct', 'ct'], acs: ['ge', 'le'],
    avs: [App.utils.formatLocalParam(from.getTime()), App.utils.formatLocalParam(now.getTime())]
  };
  const tags = [App.config.TAGS.VOLTAGE, App.config.TAGS.SET_VOLTAGE, App.config.TAGS.WORK_STATUS];

  const bucket = {}, catCount = {}, firstSeen = {};
  c.days.forEach(function(d){ bucket[d.key] = { crit: 0, warn: 0, info: 0 }; });
  ALERT_CATS.forEach(function(x){ catCount[x.name] = 0; });
  catCount['其他事件'] = 0;

  let idx = 0, covered = 0, failed = 0;

  function bumpCat(name){
    catCount[name] = (catCount[name] || 0) + 1;
  }
  function finish(){
    if (failed && !covered){
      /* 全部设备查询失败（通常是被限频）：本轮结果作废，60s 后自动重试，
         而不是把"查询失败"当成"近 7 天没有告警" */
      c.loaded = false; c.loading = false; c.at = 0;
      c.nextTryAt = Date.now() + 60000;
      scheduleRender();
      return;
    }
    c.days.forEach(function(d){
      const b = bucket[d.key];
      d.crit = b.crit; d.warn = b.warn; d.info = b.info;
      d.total = b.crit + b.warn + b.info;
    });
    c.total = c.days.reduce(function(a, d){ return a + d.total; }, 0);
    c.cats = catCount;
    c.covered = covered;
    c.loaded = true; c.loading = false; c.at = Date.now(); c.nextTryAt = 0;
    if (typeof cacheSet === 'function'){                /* 落缓存：切页回来直接显示，不再逐台查询 */
      cacheSet('week', prj, { days: c.days, cats: c.cats, total: c.total, covered: c.covered });
    }
    scheduleRender();
  }
  function next(){
    if (idx >= devices.length){ finish(); return; }
    const dev = devices[idx++];
    /* 统一走限频闸门（同设备查询间隔由闸门保证） */
    apiTagsGated(dev.id, tags, 1, 100, filter).then(function(res){
      const v = res.value || {};
      const recs = Array.isArray(v.records) ? v.records : [];
      covered++;
      const dayHas = {};
      let firstDay = null;
      recs.forEach(function(rec){
        const ts = App.utils.parseLocal(rec.ct);
        if (!ts) return;
        const k = dayKeyOf(ts);
        const b = bucket[k];
        if (!b) return;
        dayHas[k] = 1;
        if (!firstDay || k < firstDay) firstDay = k;
        const volt = Number(rec['val_' + App.config.TAGS.VOLTAGE]);
        const setv = Number(rec['val_' + App.config.TAGS.SET_VOLTAGE]);
        const ws   = Number(rec['val_' + App.config.TAGS.WORK_STATUS]);
        const fk = k + '|' + dev.id;
        if (!firstSeen[fk]){ firstSeen[fk] = 1; b.info++; bumpCat('设备接入'); }
        /* 告警口径与设备端协议语义一致（无臆造阈值） */
        if (ws === 255){ b.warn++; bumpCat('工作状态未同步'); }
        else if (ws === 1 && setv > 0 && volt < setv * 0.5){ b.warn++; bumpCat('输出电压异常'); }
      });
      /* 只对「设备已开始上报之后」的无记录日判失联：
         设备首次上报之前的日子不计为中断（否则会凭空造出不存在的故障历史） */
      if (firstDay){
        const todayKey = dayKeyOf(Date.now());
        c.days.forEach(function(d){
          if (d.key >= firstDay && d.key <= todayKey && !dayHas[d.key]){
            bucket[d.key].crit++; bumpCat('数据上报中断');
          }
        });
      }
    }, function(){ failed++; }).then(function(){
      setTimeout(next, 60);
    });
  }
  next();
}
/* 迷你折线 sparkSvg() 已删除：KPI 卡右上角那三张小趋势图按需求整块移除 */

/* ---------- 概览指标 ---------- */
function renderAlertKpi(data){
  const grid = document.getElementById('akGrid');
  if (!grid) return;
  syncAlertDefaults(data);

  const prj = data.project;
  const week = alertWeek(prj);
  const today = week.days[6].total;
  const live = data.alerts;
  const pending = live.filter(a => alertStatusOf(a) === 'pending').length;
  const done = live.filter(a => alertStatusOf(a) === 'done').length;

  /* 三张卡只保留「图标 + 名称 + 数值」：
     按需求删掉了两处附属内容 —— ① 数字下面那行小字（紧急条数 / 数据覆盖 / 较昨日），
     ② 右上角的迷你趋势图（.ak-spark）。对应的模板节点与 CSS、只服务它们的
     sparkSvg() 与 urgent / yest / dt 计算都一并移除，不留死代码。 */
  const cards = [
    { label:'待处理告警', val:pending, unit:'条', color:'--red',
      icon:'M12 3 2 20h20L12 3zM12 10v5M12 17.6v.2' },
    { label:'已处理', val:done, unit:'条', color:'--green',
      icon:'m4.5 12.5 4.5 4.5L19.5 6.5' },
    { label:'今日新增', val:today, unit:'条', color:'--cyan',
      icon:'M12 5v14M5 12h14' }
  ];

  grid.innerHTML = cards.map(c => {
    const col = cssVar(c.color);
    return '<div class="ak-card" style="--c:' + col + '">' +
      '<div class="ak-top">' +
        '<span class="ak-ic"><svg viewBox="0 0 24 24"><path d="' + c.icon + '"/></svg></span>' +
        '<span class="ak-label">' + c.label + '</span>' +
      '</div>' +
      '<div class="ak-num">' + c.val + '<em>' + c.unit + '</em></div>' +
    '</div>';
  }).join('');

  const sub = document.getElementById('akSub');
  if (sub){
    sub.textContent = week.loaded
      ? ('近 7 天共 ' + week.total + ' 条 · 覆盖 ' + (week.covered || 0) +
         ' 台设备 · 口径：每台每日最近 100 条记录 + 无记录判失联')
      : '近 7 天态势加载中…';
  }
}

/* ---------- 右侧：趋势 / 分布 / 通知通道 ---------- */
function renderAlertSide(data){
  const week = alertWeek(data.project);

  /* 堆叠柱：按等级 */
  const cols = document.getElementById('asTrend');
  if (cols){
    const max = Math.max.apply(null, week.days.map(d => d.total).concat([1]));
    const step = Math.max(5, Math.ceil(max / 3 / 5) * 5);
    const top = step * 3;

    cols.innerHTML = week.days.map(d => {
      const seg = (v, cls) => v > 0
        ? '<i class="' + cls + '" style="height:' + (v / d.total * 100).toFixed(1) + '%"></i>' : '';
      return '<div class="as-col-wrap"><div class="as-col" style="height:' +
        Math.min(100, d.total / top * 100).toFixed(1) + '%">' +
        seg(d.crit, 'crt') + seg(d.warn, 'wrn') + seg(d.info, 'inf') + '</div></div>';
    }).join('');

    const axis = document.getElementById('asAxis');
    if (axis){
      axis.innerHTML = '<span>' + top + '</span><span>' + (top / 3 * 2) + '</span>' +
                       '<span>' + (top / 3) + '</span><span>0</span>';
    }
    const xax = document.getElementById('asX');
    if (xax) xax.innerHTML = week.days.map(d => '<span>' + d.label + '</span>').join('');
    const tsub = document.getElementById('asTrendSub');
    if (tsub) tsub.textContent = week.loaded ? ('近 7 天 · 共 ' + week.total + ' 条') : '近 7 天 · 加载中…';
  }

  /* 类型分布：近 7 天真实历史构成（loadAlertWeek 按天分桶时同步累计） */
  const cats = document.getElementById('asCats');
  if (cats){
    const counts = week.cats || {};
    const total = Math.max(1, week.total);
    const names = ALERT_CATS.map(c => c.name).concat(['其他事件']);
    cats.innerHTML = names.map(n => {
      const pct = Math.round((counts[n] || 0) / total * 100);
      return '<div class="as-bar"><span>' + n + '</span>' +
        '<span class="tr"><i style="width:' + pct + '%"></i></span><b>' + pct + '%</b></div>';
    }).join('');
  }

  /* 通知通道：与系统设置里启用的渠道保持一致 */
  const chans = document.getElementById('asChans');
  if (chans){
    chans.innerHTML = NOTIFY_META.map(m => {
      const c = notifyCfg[m.id] || { on:false, fmt:'md' };
      const fmt = c.fmt === 'card' ? '卡片' : c.fmt === 'text' ? '纯文本' : 'Markdown';
      /* 只显示配置里真实存在的信息：渠道名 + Webhook 是否填好 + 消息格式。
         以前这里写死「园区运维群 / 项目指挥群」这类群名，是编造的，已去掉。 */
      const ready = c.on && String(c.webhook || '').trim();
      const desc = ready ? ('Webhook 已配置 · ' + fmt) : (c.on ? '已启用但未填写 Webhook' : '未启用');
      return '<div class="as-chan">' +
        '<span class="nt-ic" style="--brand:' + m.brand + '"><svg viewBox="0 0 24 24"><path d="' + m.icon + '"/></svg></span>' +
        '<div class="as-chan-txt"><b>' + m.name + '</b><span>' + desc + '</span></div>' +
        '<span class="as-pill ' + (ready ? 'on' : 'off') + '">' + (ready ? '已启用' : (c.on ? '待配置' : '未启用')) + '</span>' +
      '</div>';
    }).join('');
  }
}

/* ---------- 行渲染 ---------- */
function alertRow(a, data, clickable){
  const el = document.createElement('div');
  const st = alertStatusOf(a);
  el.className = 'alert-item ' + a.level + (clickable ? ' rich' : ' is-static') +
                 (st === 'done' ? ' done' : '');
  el.title = fullTime(a.ts);

  /* 概览视图里只作展示，保持紧凑样式 */
  if (!clickable){
    el.innerHTML =
      '<div class="alert-icon">' + (a.level === 'critical' ? '!' : a.level === 'warning' ? '!' : 'i') + '</div>' +
      '<div class="alert-body">' +
        '<div class="alert-title">' + a.title + '</div>' +
        '<div class="alert-meta">' + timeText(a.ts) + ' · ' + a.meta + '</div>' +
      '</div>' +
      '<span class="alert-tag">' + a.tag + '</span>';
    return el;
  }

  const dev = data.devices.find(d => d.id === a.deviceId);
  const reason = dev ? a.title.replace(dev.id + ' ', '') : a.title;
  el.innerHTML =
    '<div class="alert-icon">' + (a.level === 'critical' ? '!' : a.level === 'warning' ? '!' : 'i') + '</div>' +
    '<div class="alert-body">' +
      '<div class="al-title">' + reason + '</div>' +
      '<div class="al-detail">' + a.deviceId +
        (dev ? ' | ' + dev.zone + ' · ' + dev.area : '') + ' · ' + a.meta + '</div>' +
      '<div class="al-tags">' +
        '<span class="al-tag ' + a.level + '">' + a.tag + '</span>' +
        '<span class="al-tag">' + alertCatOf(a) + '</span>' +
        '<span class="al-tag">持续 ' + alertDurOf(a) + ' 分钟</span>' +
        '<span class="al-tag st">' + ALERT_STATUS_TEXT[st] +
          (st === 'pending' ? '' : ' · ' + alertOwnerOf(a)) + '</span>' +
      '</div>' +
    '</div>' +
    '<div class="al-right">' +
      '<span class="al-time">' + timeText(a.ts) + '</span>' +
      '<div class="al-ops">' +
        (st === 'pending'
          ? '<button class="al-op" data-op="done" type="button">处理</button>'
          : '<span class="al-op done">已处理</span>') +
      '</div>' +
    '</div>';

  /* 点「处理」只改状态；点行其他区域定位到设备 */
  el.addEventListener('click', e => {
    const op = e.target.closest('[data-op]');
    if (op){
      e.stopPropagation();
      setAlertStatus(a, 'done');
      renderAlerts(data);
      renderAlertKpi(data);
      return;
    }
    const dev2 = data.devices.find(d => d.id === a.deviceId);
    if (!dev2){ toastErr('定位失败：未找到该告警关联的设备'); return; }
    locateDevice(dev2);
  });
  return el;
}

/* 探针用的最长内容，保证量出的行高与真实行一致 */
const ALERT_PROBE_RICH = {
  level:'critical', tag:'严重', deviceId:'SZ-DEVICE-00',
  title:'SZ-DEVICE-00 数据上报中断', meta:'C区 · 仓储中心 · 链路无响应', ts:Date.now()
};

/* 告警定位：跳到「设备管理」页并带上设备号，由那一页（数据就绪后）打开该设备详情。
   多页面结构下，设备列表与详情都在设备管理页，本页只负责跳转。 */
function locateDevice(dev){
  if (dev && window.App && App.nav){ App.nav.to('devices', { dev: dev.id }); return; }
  toastErr('打开失败：无法跳转到设备管理');
}

/* 告警筛选：等级 + 处置状态 + 关键字 */
function alertQueryHit(a, q){
  return !q || (a.title + ' ' + a.meta + ' ' + a.tag + ' ' + a.deviceId).toUpperCase().indexOf(q) > -1;
}
function matchAlerts(data){
  const q = state.alertQuery.trim().toUpperCase();
  const f = state.alertFilter, st = state.alertStatus;
  return data.alerts.filter(a => {
    if (!alertQueryHit(a, q)) return false;
    const s = alertStatusOf(a);
    if (st !== 'all' && s !== st) return false;
    if (f === 'active') return s !== 'done';
    return f === 'all' || a.level === f;
  });
}
/* 标签计数：按全量事件统计，不受搜索与筛选影响（与设备列表的标签行为一致） */
function alertChipCounts(data){
  const base = data.alerts;
  const done = base.filter(a => alertStatusOf(a) === 'done').length;
  return {
    all: base.length,
    active: base.length - done,
    critical: base.filter(a => a.level === 'critical').length,
    warning: base.filter(a => a.level === 'warning').length,
    info: base.filter(a => a.level === 'info').length
  };
}

function renderAlerts(data){
  const list = document.getElementById('alertList');
  if (!list) return;

  syncAlertDefaults(data);
  /* 概览视图里的告警流只作展示：藏起筛选条，行也换成紧凑样式 */
  const clickable = alertClickable();
  const panel = document.getElementById('panel-alerts');
  if (panel) panel.classList.toggle('is-center', clickable);

  const matched = matchAlerts(data);
  const q = state.alertQuery.trim();
  const counts = alertChipCounts(data);
  const filtering = q !== '' || state.alertFilter !== 'all' || state.alertStatus !== 'all';

  /* 筛选标签计数（与设备列表的标签同款） */
  Array.prototype.forEach.call(document.querySelectorAll('#panel-alerts .tab[data-filter]'), t => {
    const b = t.querySelector('b');
    if (b) b.textContent = counts[t.dataset.filter];
    t.classList.toggle('active', t.dataset.filter === state.alertFilter);
  });

  list.innerHTML = '';

  /* 每页条数按面板可用高度自适应（行高固定，量一次即可） */
  const avail = list.clientHeight;
  const probe = clickable ? alertRow(ALERT_PROBE_RICH, data, true) : ALERT_ROW_PROBE;
  const rowH = avail > 0 ? probeRowHeight(list, 'alert-item', probe) : 0;
  const size = rowH > 0 ? Math.max(1, Math.floor((avail - 2) / rowH)) : 4;

  const pages = Math.max(1, Math.ceil(matched.length / size));
  if (state.alertPage > pages) state.alertPage = pages;
  if (state.alertPage < 1) state.alertPage = 1;

  const start = (state.alertPage - 1) * size;
  const rows = matched.slice(start, start + size);
  rows.forEach(a => list.appendChild(alertRow(a, data, clickable)));

  if (!rows.length){
    list.innerHTML = '<div class="act-empty" style="text-align:center;padding:26px 0">' +
      (q ? '未找到匹配「' + q + '」的告警'
         : (filtering ? '当前筛选条件下暂无告警' : '该项目暂无告警')) + '</div>';
  }

  const info = document.getElementById('alertPageInfo');
  if (info) info.textContent = '第 ' + state.alertPage + ' / ' + pages + ' 页';
  const prev = document.getElementById('alertPrev');
  const next = document.getElementById('alertNext');
  if (prev) prev.disabled = state.alertPage <= 1;
  if (next) next.disabled = state.alertPage >= pages;
}

/* ---------- 告警规则 ---------- */
const ALERT_RULES = [
  { id:'volt', name:'输出电压越限', cond:'实际电压 > 5500 V 且持续 1 分钟', level:'critical' },
  { id:'link', name:'数据上报中断', cond:'连续 3 个上报周期（180s）无数据', level:'critical' },
  { id:'setv', name:'设定电压偏高', cond:'设定电压 > 5000 V 且持续 5 分钟', level:'warning' },
  { id:'off',  name:'云端连接断开', cond:'AirCloud 长连接断开且重连失败 3 次', level:'critical' },
  { id:'uart', name:'串口通信异常', cond:'UART 状态帧校验连续失败',        level:'warning' },
  { id:'fota', name:'固件升级异常', cond:'FOTA 下载或重启升级失败',       level:'warning' },
  { id:'acc',  name:'设备接入',     cond:'新设备 IMEI 注册接入',          level:'info' }
];
const alertRuleOff = {};   /* 会话内关闭的规则 */

/* ---------- 交互（面板会被摘除/挂载，统一走事件委托） ---------- */
(function bindAlertCenter(){
  const chips = document.getElementById('alertTabs');
  const stBtn = document.getElementById('alStatusBtn');
  const stPop = document.getElementById('alStatusPop');

  if (chips) chips.addEventListener('click', e => {
    const b = e.target.closest('.tab[data-filter]');
    if (!b) return;
    state.alertFilter = b.dataset.filter;
    state.alertPage = 1;
    renderAlerts(curData());
  });

  if (stBtn && stPop){
    stBtn.addEventListener('click', e => {
      e.stopPropagation();
      stPop.classList.toggle('show');
    });
    stPop.addEventListener('click', e => {
      const b = e.target.closest('button[data-st]');
      if (!b) return;
      state.alertStatus = b.dataset.st;
      state.alertPage = 1;
      stPop.querySelectorAll('button').forEach(x => x.classList.toggle('active', x === b));
      stBtn.innerHTML = b.textContent + ' <i>▾</i>';
      stPop.classList.remove('show');
      renderAlerts(curData());
    });
    document.addEventListener('click', e => {
      if (!stPop.contains(e.target) && !stBtn.contains(e.target)) stPop.classList.remove('show');
    });
  }

  /* 批量处理：把当前筛选下的待处理告警一次性置为已处理 */
  const batch = document.getElementById('akBatch');
  if (batch) batch.addEventListener('click', () => {
    const data = curData();
    syncAlertDefaults(data);
    const list = matchAlerts(data).filter(a => alertStatusOf(a) === 'pending');
    if (!list.length){ toastErr('批量处理失败：当前筛选条件下没有待处理告警'); return; }
    list.forEach(a => setAlertStatus(a, 'done'));
    state.alertPage = 1;
    renderAlerts(data);
    renderAlertKpi(data);
  });

  /* 告警规则弹窗 */
  const rulesBtn = document.getElementById('akRules');
  const ruleMask = document.getElementById('ruleMask');
  const ruleList = document.getElementById('ruleList');
  function renderRules(){
    if (!ruleList) return;
    ruleList.innerHTML = ALERT_RULES.map(r => {
      const on = !alertRuleOff[r.id];
      const lv = r.level === 'critical' ? '严重' : r.level === 'warning' ? '警告' : '提示';
      return '<div class="rule-row">' +
        '<div class="r-main"><b>' + r.name + '</b><span>' + r.cond + '</span></div>' +
        '<span class="al-tag ' + r.level + '">' + lv + '</span>' +
        '<button class="dv-switch' + (on ? ' on' : '') + '" data-rule="' + r.id +
          '" type="button" aria-pressed="' + on + '"><i></i></button>' +
      '</div>';
    }).join('');
  }
  if (rulesBtn && ruleMask){
    rulesBtn.addEventListener('click', () => {
      renderRules();
      ruleMask.classList.add('show');
    });
    ruleMask.addEventListener('click', e => {
      const sw = e.target.closest('[data-rule]');
      if (sw){
        const id = sw.dataset.rule;
        alertRuleOff[id] = !alertRuleOff[id];
        sw.classList.toggle('on', !alertRuleOff[id]);
        sw.setAttribute('aria-pressed', !alertRuleOff[id] ? 'true' : 'false');
        return;
      }
      if (e.target === ruleMask || e.target.closest('#ruleClose') || e.target.closest('#ruleSave')){
        ruleMask.classList.remove('show');
      }
    });
  }

  /* 右侧：跳到系统设置的通知设置页 */
  const toNotify = document.getElementById('asToNotify');
  if (toNotify) toNotify.addEventListener('click', () => {
    /* 多页面：跳到系统设置页并直接落在「通知设置」页签 */
    if (window.App && App.nav) App.nav.to('settings', { tab: 'notify' });
  });
})();


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
/* 告警中心页：三张指标 + 富列表 + 右侧态势 */
registerPageRenderer(function(data){ renderAlerts(data); renderAlertKpi(data); renderAlertSide(data); });

/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */

/* 告警条目可点击的视图：告警中心里点告警会跳到设备管理查看该设备 */
const DV_ALERT_VIEWS = ['告警中心'];

function alertClickable(){
  return DV_ALERT_VIEWS.indexOf(activeViewName()) > -1;
}

/* 告警中心：模糊搜索 */
bindSearch('alertSearch', 'alertClear', value => {
  state.alertQuery = value;
  state.alertPage = 1;
  renderAlerts(curData());
});

/* 告警历史翻页 */
(function(){
  const prev = document.getElementById('alertPrev');
  const next = document.getElementById('alertNext');
  if (!prev || !next) return;
  prev.addEventListener('click', () => {
    if (state.alertPage <= 1) return;
    state.alertPage--;
    renderAlerts(curData());
  });
  next.addEventListener('click', () => {
    state.alertPage++;
    renderAlerts(curData());
  });
})();

const ALERT_ROW_PROBE =
  '<div class="alert-icon">!</div>' +
  '<div class="alert-body"><div class="alert-title">W</div><div class="alert-meta">W</div></div>' +
  '<span class="alert-tag">严重</span>';

/* matchDevices() 属于设备管理页逻辑，已移回 pages/devices.js */

