/* assets/js/api.js —— 由 index.html 内联脚本拆出（原行区间 3528-3839 / 8484-8495 / 9319-9443），内容未改动 */
/* =========================================================
   6. 数据模型
   —— 全场只有一种设备：同一型号、同一属性、同一控制动作集
   —— 各项目按地域复制部署，设备实例之间仅以「设备 ID」区分
   ========================================================= */
const DEVICE_SPEC = {
  model: 'Air8301',
  label: '电场发生器通讯控制板',
  /* 每页条数由面板高度自适应决定；此值仅作为面板不可测量时的兜底 */
  pageSize: 12,
  /* 设备的安装位置不同，设备本身完全相同 */
  sites: [
    { zone:'A区', area:'中控室' },
    { zone:'A区', area:'机房' },
    { zone:'B区', area:'3号车间' },
    { zone:'B区', area:'东门' },
    { zone:'C区', area:'配电房' },
    { zone:'D区', area:'主入口' },
    { zone:'E区', area:'水泵房' },
    { zone:'C区', area:'仓储中心' }
  ],
  /* 控制动作集（协议 265：1=开机 / 0=关机） */
  actions: ['开机', '关机'],
  /* 上报周期（秒）：协议 7.5 电压/状态/设定电压 1 分钟一次 */
  period: 60
};

/* =========================================================
   6.0 设备状态：三条正交维度
   —— 连接：online  true 在线 / false 离线
   —— 告警：alarm   'none' 无告警 / 'warning' 告警 / 'critical' 严重告警
            （离线必然伴随链路失联，所以离线设备的 alarm 恒为 'critical'）
   —— 电源：power   'on' 开机 / 'off' 关机
            （关机必然导致离线，但离线不等于关机——链路故障时设备仍在运行）
   展示层把「连接 × 告警」合成为三种组合，全站配色与文案都以此为唯一口径：
     在线 · 无告警（绿）/ 在线 · 告警（琥珀）/ 离线 · 失联（红）
   ========================================================= */
const devOnline    = d => !!d.online;
/* 告警口径：离线即视为失联告警，在线则看 alarm 字段 */
const devAlarmed   = d => !d.online || d.alarm !== 'none';
/* 展示配色口径：ok / alarm / off，与 CSS 的 .ok / .alarm / .off 一一对应 */
const devTone      = d => (!d.online ? 'off' : (d.alarm !== 'none' ? 'alarm' : 'ok'));
const devToneColor = d => cssVar(devTone(d) === 'off' ? '--red'
                               : devTone(d) === 'alarm' ? '--amber' : '--green');
const devConnText  = d => (d.online ? '在线' : '离线');
const devAlarmText = d => (!d.online ? '失联'
                        : d.alarm === 'critical' ? '严重告警'
                        : d.alarm === 'warning' ? '告警' : '无告警');
/* 同时表达两条轴的完整状态文案：在线 · 无告警 / 在线 · 告警 / 离线 · 失联 */
const devStateText = d => devConnText(d) + ' · ' + devAlarmText(d);
/* 分桶口径（与三色图例一一对应），供聚合统计复用 */
const devBucket    = d => (devTone(d) === 'ok' ? 'online' : devTone(d) === 'alarm' ? 'warn' : 'offline');

/* =========================================================
   真实数据层：全部来自合宙 AirCloud 开放接口（无任何随机 / 假数据）
   设备对象沿用模板字段，渲染层零改动：
     load  → 实际电压(799, V)      temp → 设定电压(800, V)
     snr   → 4G信号强度(782)       hbOffset → 距最近上报秒数
     lng/lat → 经纬度（Tag 512 经度 / 513 纬度，基站定位 LBS）
   ========================================================= */
let PROJECTS = [];
const ONLINE_WINDOW_MS = 300000;   /* 在线判定：最近上报在 5 分钟内（设备 60s 上报一次） */
const ALERT_HISTORY_MAX = 200;

const DATA = {};
function emptyProject(prj){
  var p = prj || { id:'', short:'', code:'', name:'--', region:'', net:0, total:0, offline:0, warn:0, seed:0 };
  return {
    project: p, devices: [], alerts: [],
    health: 0, stable: 0, latency: 0, usage: 0,
    kpi: { online: 0, alert: 0, onlineDelta: 0 },
    loaded: false
  };
}
function projectData(prj){
  if (!prj) return null;
  if (!DATA[prj.id]) DATA[prj.id] = emptyProject(prj);
  return DATA[prj.id];
}

/* ---------- 真实接口封装 ---------- */
function apiProjects(){ return App.http.post(App.config.API.PROJECTS, {}); }
function apiDevices(projectKey, page, size, prefix){
  return App.http.post(App.config.API.SEARCH_DEVICES, {
    project: projectKey, imei_prefix: prefix || '', page: page, size: size
  });
}
function apiTags(clientId, tags, page, size, filter){
  var body = { client_id: clientId, tags: tags, page: page, size: size };
  if (filter) body.filter = filter;
  return App.http.post(App.config.API.LIST_BY_TAGS, body);
}
/* =========================================================
   平台限频口径（《AirCloud 接口文档.md》，注意：是「每秒次数」，与设备上报频率无关）
     · list_by_tags：单用户 10 次/秒；
       指定时间区间的历史查询「不应轮询调用」（结果不变，只增加服务器负担）；
       需要轮询的最新数据，建议每 10 秒左右一次
     · latest_location：单用户 10 次/秒；单用户每设备 5 次/秒
     · 同一页面多设备轮询：设备之间间隔 ~100ms（一批 >10 台同时下发，服务端反而更慢）
   —— 因此闸门只做两件事：全局串行（避免同时挤爆服务端）+ 两级最小间隔，
      整体节奏不超过单用户 10 次/秒；命中"请求过于频繁"时退避重试，不丢数据。
   （早先这里按"查询频率≈上报频率 60s"把同设备间隔设成了 15s，比文档允许值
     严了约 75 倍，反而把队列堵住——已按文档更正）
   ========================================================= */
const TAG_GAP_DEV_MS = 300;    /* 同一设备两次查询最小间隔（文档允许单设备 5 次/秒 = 200ms） */
const TAG_GAP_ALL_MS = 110;    /* 任意两次查询之间最小间隔（文档：多设备间隔 ~100ms，即 ≤10 次/秒） */
const TAG_BACKOFF_MS = 3000;   /* 被判「请求过于频繁」后的退避时长 */
const TAG_TASK_MAX_MS = 45000; /* 单个任务占用闸门的上限（看门狗）：HTTP 层 15s 超时 + 两次退避重试
                                  都在这个额度内；即使出现"永不 settle"的请求，队列也一定会继续前进 */
const lastTagAt = {};          /* 每台设备上次查询时刻 */
let lastTagAllAt = 0;          /* 全体上次查询时刻（全局节奏） */
let tagChain = Promise.resolve();

function scheduleTagQuery(devId, fn, retry){
  const left = (retry === undefined) ? 2 : retry;

  /* 排队等待（全局节奏 + 同设备间隔）后执行一次任务；命中"请求过于频繁"时在本任务内部
     退避重试 —— 关键：绝不能再调用 scheduleTagQuery 重新入队，
     那样新任务会排在 tagChain 尾部等它完成，而尾部正包含等待中的自己 → 自己等自己、永久死锁
     （表现为整个页面的平台查询全部冻结，实测遇到过）。 */
  function attempt(n){
    return fn().catch(function(e){
      if (n > 0 && e && /频繁|排队/.test(String(e.message || ''))){
        return new Promise(function(r){ setTimeout(r, TAG_BACKOFF_MS); }).then(function(){
          return attempt(n - 1);
        });
      }
      throw e;
    });
  }

  const run = tagChain.then(function(){
    const now = Date.now();
    const wait = Math.max(TAG_GAP_ALL_MS - (now - lastTagAllAt),
                          TAG_GAP_DEV_MS - (now - (lastTagAt[devId] || 0)));
    return new Promise(function(r){ setTimeout(r, Math.max(0, wait)); });
  }).then(function(){
    lastTagAt[devId] = Date.now();
    lastTagAllAt = Date.now();
    /* 看门狗：即使某个请求的 promise 永不 settle（异常网络/被中断），
       到点也把这一环放掉，保证后续任务不会无限等待 */
    return Promise.race([
      attempt(left),
      new Promise(function(_, rej){
        setTimeout(function(){ rej(new Error('平台查询超时（闸门看门狗）')); }, TAG_TASK_MAX_MS);
      })
    ]);
  });
  tagChain = run.catch(function(){});   /* 队列不被单次失败打断 */
  return run;
}


function apiTagsGated(devId, tags, page, size, filter){
  return scheduleTagQuery(devId, function(){
    return apiTags(devId, tags, page, size, filter);
  });
}

/* 最新位置：真实经纬度(国测局02) + 地址描述 + 当时信号量 signal + 电量 percent */
function apiLatestLocation(clientId){
  return App.http.post(App.config.API.LATEST_LOCATION, { client_id: clientId });
}
/* 设备列表全量拉取：search_my_devices 每页上限 100 条，按 pages 翻页取完（不再只取第一页） */
function apiAllDevices(projectKey){
  var size = 100, out = [];
  function step(page){
    return apiDevices(projectKey, page, size, '').then(function(res){
      var v = res.value || {};
      var recs = Array.isArray(v.records) ? v.records : [];
      recs.forEach(function(r){
        var id = r.deviceid || r.imei || '';
        if (id) out.push({ id: String(id), name: r.name || r.device_name || '' });
      });
      var pages = Number(v.pages || 1);
      if (recs.length && page < pages) return step(page + 1);
      return out;
    });
  }
  return step(1);
}
function parseTagRecord(rec){
  function raw(id){
    var k = 'val_' + id;
    if (rec[k] === undefined || rec[k] === null || rec[k] === '') return undefined;
    return rec[k];
  }
  function v(id){                       /* 数值型 Tag */
    var s = raw(id);
    if (s === undefined) return undefined;
    var n = Number(s);
    return isFinite(n) ? n : s;
  }
  function s(id){                       /* 字符串型 Tag：ICCID(20位)/版本号/设备号 必须保持字符串 */
    var x = raw(id);
    return (x === undefined) ? undefined : String(x);
  }
  return {
    ct: rec.ct, lastCt: App.utils.parseLocal(rec.ct),
    voltage: v(App.config.TAGS.VOLTAGE),
    setVoltage: v(App.config.TAGS.SET_VOLTAGE),
    workStatus: v(App.config.TAGS.WORK_STATUS),
    /* 781/782：设备端新增的上行字段（随周期上报纸文一起发）
       netType：1=4G / 2=WiFi / 3=以太网（老固件不发 → undefined）
       signal ：统一 0~31 刻度（4G=CSQ 原值，99=无信号；WiFi=RSSI 折算） */
    netType: v(App.config.TAGS.NETWORK_TYPE),
    signal: v(App.config.TAGS.SIGNAL),
    /* ICCID 有 20 位数字，转 Number 会精度溢出，必须保留字符串 */
    iccid: s(App.config.TAGS.ICCID),
    deviceId: s(App.config.TAGS.DEVICE_ID),
    version: s(App.config.TAGS.VERSION),
    lng: v(App.config.TAGS.LNG),
    lat: v(App.config.TAGS.LAT)
  };
}

/* list_by_tags 的时间过滤条件（ct ∈ [from, to]，本地时间，接口规定格式 yyyy-MM-dd HH:mm:ss） */
function periodFilter(fromTs, toTs){
  return {
    aks: ['ct', 'ct'], acs: ['ge', 'le'],
    avs: [App.utils.formatLocalParam(fromTs), App.utils.formatLocalParam(toTs)]
  };
}

/* 地址 → 省/市 + 详细地址（用于列表与地图卡展示，真实数据，无需编造） */
function splitAddress(addr){
  var a = String(addr || '').trim();
  if (!a) return { zone: '未定位', area: '' };
  var m = a.match(/^(.{2,4}?(?:省|自治区|特别行政区|市))(.+)$/);
  if (m) return { zone: m[1], area: m[2] };
  return { zone: a.slice(0, 8), area: a.slice(8) };
}

/* ---------- 由真实 Tag 记录 + 最新位置构造设备对象 ----------
   rec: list_by_tags 最新一条（val_799 实际电压 / val_265 工作状态 / val_800 设定电压
        / val_783 ICCID / val_798 IMEI / val_1027 版本 / val_512,513 经纬度
        / val_781 联网方式 / val_782 信号强度）
   loc: latest_location 的 value（address/lng/lat/signal/percent）—— 位置来源；
        其 signal 仅 4G 场景有值，作为信号的回退来源
   模板字段沿用：load → 实际电压(V)，temp → 设定电压(V)，snr → 信号强度(0~31，见下)
   ========================================================= */
function deviceFromRecord(imei, rec, loc){
  var now = Date.now();
  var fresh = !!(rec && rec.lastCt && (now - rec.lastCt) <= ONLINE_WINDOW_MS);
  var voltage = (rec && typeof rec.voltage === 'number') ? rec.voltage : 0;
  var setV = (rec && typeof rec.setVoltage === 'number') ? rec.setVoltage : 0;
  /* 告警口径：只表达设备端协议里真实存在的异常，不再臆造电压阈值
     · 无最近上报（离线）            → 严重（由 buildAlertsFromDevices 生成）
     · 工作状态 265=255「未同步」    → 警告（设备与高压板通信未同步）
     · 开机(265=1) 但实际电压 < 设定电压一半 → 警告（输出异常） */
  var ws = (rec && rec.workStatus !== undefined && rec.workStatus !== null)
         ? Number(rec.workStatus) : undefined;
  var unsynced  = fresh && ws === 255;
  var badOutput = fresh && ws === 1 && setV > 0 && voltage < setV * 0.5;
  var over = unsynced || badOutput;
  var alarmReason = unsynced ? '工作状态未同步' : (badOutput ? '输出电压异常' : '');

  var addr = (loc && loc.address) ? String(loc.address) : '';
  var sp = splitAddress(addr);
  var lng = (loc && isFinite(Number(loc.lng))) ? Number(loc.lng)
          : ((rec && typeof rec.lng === 'number') ? rec.lng : null);
  var lat = (loc && isFinite(Number(loc.lat))) ? Number(loc.lat)
          : ((rec && typeof rec.lat === 'number') ? rec.lat : null);
  /* 原始 GNSS 坐标：latest_location 同时返回 wlng/wlat（WGS-84，与设备上报的
     Tag 512/513 原文一致），而 lng/lat 是平台为地图转换好的国测局 GCJ-02。
     两者是同一个点（上海地区相差约 500 米）；取出来在界面上并列显示，
     便于和 AirCloud 后台的原始报文核对，避免被误判成"定位不准/位置没更新" */
  var wlng = (loc && isFinite(Number(loc.wlng))) ? Number(loc.wlng) : null;
  var wlat = (loc && isFinite(Number(loc.wlat))) ? Number(loc.wlat) : null;
  /* 位置数据自身的产生时间（latest_location.time，形如 "2026-09-21 11:05:34"）：
     界面上显示出来，用于一眼判断"显示的还是不是旧位置" */
  var locTime = (loc && loc.time) ? String(loc.time) : null;
  /* 信号强度：优先设备端上行的 Tag 782（统一 0~31 刻度，4G/WiFi 同一口径），
     回退 latest_location.signal（老固件只有这里带 4G CSQ）。
     两个来源都没有 → hasSignal=false，界面显示「未上报」，绝不伪装成 0 */
  var tagSig = (rec && isFinite(Number(rec.signal))) ? Number(rec.signal) : null;
  var locSig = (loc && isFinite(Number(loc.signal))) ? Number(loc.signal) : null;
  var sigValue = (tagSig !== null) ? tagSig : locSig;
  var sigSrc = (tagSig !== null) ? 'tag' : (locSig !== null ? 'loc' : 'none');

  return {
    id: imei, name: imei, model: App.config.BIZ.DEVICE_MODEL,
    zone: sp.zone, area: sp.area, address: addr,
    ip: '--',
    online: fresh,
    alarm: !fresh ? 'critical' : (over ? 'warning' : 'none'),
    alarmReason: !fresh ? '数据上报中断' : alarmReason,
    power: (rec && (rec.workStatus === 0 || rec.workStatus === '0')) ? 'off' : 'on',
    load: voltage,
    temp: setV,
    /* 信号强度（0~31 统一刻度）：snr 为沿用的旧字段名，signal 为正式名 */
    snr: sigValue === null ? 0 : sigValue,
    signal: sigValue,
    signalSrc: sigSrc,
    hasSignal: sigValue !== null,
    /* 联网方式（Tag 781）：1=4G / 2=WiFi / 3=以太网；0=老固件未上报 */
    netType: (rec && isFinite(Number(rec.netType))) ? Number(rec.netType) : 0,
    /* 设备电量百分比：latest_location.percent（同上，无数据为 null） */
    percent: (loc && isFinite(Number(loc.percent))) ? Number(loc.percent) : null,
    hbOffset: (rec && rec.lastCt) ? Math.max(0, Math.round((now - rec.lastCt) / 1000)) : 0,
    /* 最近一次上报的云端时间戳（ms）：hbOffset 是「距上次上报多少秒」的相对值，
       刚上报完就是 0、用过期缓存还要补正，看不出到底是什么时候上报的。
       详情页要显示「年月日时分秒」，所以保留绝对值 lastCt */
    lastCt: (rec && rec.lastCt) ? Number(rec.lastCt) : null,
    lng: lng, lat: lat,
    /* 原始 WGS-84（设备上报口径），仅用于界面并列展示与核对 */
    wlng: wlng, wlat: wlat,
    locTime: locTime,
    iccid: rec ? rec.iccid : undefined,
    version: rec ? rec.version : undefined,
    workStatus: rec ? rec.workStatus : undefined,
    actions: ['开机', '关机'],
    period: 60,
    busy: false
  };
}

/* ---------- 由真实数据派生告警 ----------
   口径完全来自设备真实上报值与协议语义：
     · 离线（无最近上报）→ 严重「数据上报中断」
     · 工作状态 265=255  → 警告「工作状态未同步」
     · 开机但输出异常    → 警告「输出电压异常」
   不包含任何臆造的数值阈值告警 */
function buildAlertsFromDevices(devices){
  var out = [];
  devices.forEach(function(d){
    if (!d.online){
      out.push({
        level: 'critical', tag: '严重', deviceId: d.id,
        title: d.id + ' 数据上报中断',
        meta: '最近上报 ' + (d.hbOffset ? (d.hbOffset + ' 秒前') : '无记录') + ' · AirCloud 无数据',
        ts: Date.now() - (d.hbOffset || 0) * 1000
      });
    } else if (d.alarm === 'warning'){
      out.push({
        level: 'warning', tag: '警告', deviceId: d.id,
        title: d.id + ' ' + (d.alarmReason || '设备异常'),
        meta: '工作状态 ' + App.utils.workStatusText(d.workStatus) +
              ' · 实际电压 ' + d.load + ' V · 设定电压 ' + d.temp + ' V',
        ts: Date.now() - (d.hbOffset || 0) * 1000
      });
    }
  });
  return out;
}

/* ---------- 全局状态 ---------- */
const STORE_KEY = 'nexus-project';
const state = {
  projectId: null,
  projectName: '',
  projectKey: '',
  alertFilter: 'all', alertQuery: '', alertPage: 1,
  /* 告警处置状态筛选：all / pending / done */
  alertStatus: 'all',
  /* 设备列表两条筛选轴：devFilter 连接（all/online/offline），devAlarmOnly 告警（是否只看有告警） */
  devFilter: 'all', devAlarmOnly: false, devPage: 1, devQuery: '',
  /* 表格排序：devSort 为列键，null 表示保持设备原始顺序 */
  devSort: null, devSortDir: 'asc'
};
try {
  const savedPrj = localStorage.getItem(STORE_KEY);
  if (savedPrj) state.projectId = savedPrj;
} catch(e){}
function curProject(){
  return PROJECTS.find(p => p.id === state.projectId) || PROJECTS[0] || null;
}
function curData(){ return projectData(curProject()) || emptyProject(null); }

/* 操作记录：按项目隔离，切换项目时清空 */
const actionLog = [];

/* =========================================================
   sessionStorage 缓存（多页面结构下的「切页不重拉」）
   —— 每个页面都是独立文档，内存态不会延续，所以按项目把三类数据落进 sessionStorage：
        projects ：项目列表（顶栏项目名 / 项目菜单）        TTL 5 分钟
        devlist  ：设备清单（id + 名称）+ 设备总数           TTL 5 分钟
        devlive  ：每台设备的实时值（Tag / 位置 / 信号 / 电量）TTL 60 秒
        week     ：近 7 天告警态势（告警中心用）            TTL 5 分钟（见 pages/alerts.js）
   —— 切回页面时先用「未过期」的缓存直接把列表/点位/告警画出来，
      只对已过期的那部分重新请求：queueTags 按 tagAt 判断新鲜度（65s），
      缓存写入时把 tagAt 一并带上，因此刚查过的设备不会被重复请求。
   —— 键名一律带运行时 appId 前缀；读写异常（隐私模式 / 超配额 / 坏 JSON）静默降级为「不用缓存」，不影响功能。
   ========================================================= */
const CACHE_LIST_TTL = 300000;
const CACHE_LIVE_TTL = 60000;
function cacheKey(kind, prj){
  return App.config.APP_ID + '_' + kind + '_' + ((prj && prj.code) ? prj.code : 'all');
}
function cacheGet(kind, prj){
  try {
    const raw = sessionStorage.getItem(cacheKey(kind, prj));
    if (!raw) return null;
    const v = JSON.parse(raw);
    return (v && typeof v.at === 'number') ? v : null;
  } catch (e){ return null; }
}
function cacheSet(kind, prj, val){
  try { val.at = Date.now(); sessionStorage.setItem(cacheKey(kind, prj), JSON.stringify(val)); return true; }
  catch (e){ return false; }   /* 超配额等：放弃缓存，功能不受影响 */
}
/* 跨页复用的设备字段（列表 / 地图 / 详情都要用）
   —— netType/signal/signalSrc 是 Tag 781/782 带来的新字段，必须一起缓存，
      否则切页后要等下一次 Tag 拉取才有联网方式与信号 */
const CACHE_DEV_FIELDS = ['name','online','alarm','alarmReason','power','load','temp','workStatus',
  'snr','signal','signalSrc','netType','hasSignal','percent','hbOffset','lastCt','lng','lat','wlng','wlat','locTime','address',
  'zone','area','iccid','version','deviceId','tagAt','locAt','infoAt'];

/* 写缓存：台账 + 逐台实时值。节流 800ms；页面隐藏 / 卸载时立即落盘。 */
let cacheFlushTimer = null;
function flushDeviceCache(){
  const prj = curProject();
  if (!prj) return;
  const data = projectData(prj);
  if (!data || !data.devices || !data.devices.length) return;
  const live = {};
  data.devices.forEach(function(d){
    const o = {};
    CACHE_DEV_FIELDS.forEach(function(k){ if (d[k] !== undefined) o[k] = d[k]; });
    live[d.id] = o;
  });
  cacheSet('devlive', prj, { live: live });
  cacheSet('devlist', prj, {
    total: data.devices.length,
    list: data.devices.map(function(d){ return { id: d.id, name: d.name }; })
  });
}
function scheduleCacheFlush(){
  if (cacheFlushTimer) return;
  cacheFlushTimer = setTimeout(function(){ cacheFlushTimer = null; flushDeviceCache(); }, 800);
}
window.addEventListener('pagehide', function(){
  if (cacheFlushTimer){ clearTimeout(cacheFlushTimer); cacheFlushTimer = null; }
  flushDeviceCache();
});
document.addEventListener('visibilitychange', function(){ if (document.hidden) flushDeviceCache(); });

/* ---------------- 用缓存先把页面铺出来（stale-while-revalidate） ----------------
   —— 多页面结构下这是「切页几乎瞬开」的关键：只要缓存还有参考价值就先画，
      不必等接口链（项目列表 → 设备清单 → 实时值/位置，串行 1.7–3.9s 才齐）。
   —— 过期缓存也照用（原先顶栏会提示「设备列表为缓存数据 · 更新于 …」，该提示已按需求删除），
      接口结果到达后再做差异更新——用户先看到内容，数值随后刷新。
   —— 只有超过 CACHE_STALE_MAX（6 小时）的缓存才放弃（参考价值太低）。 */
const CACHE_STALE_MAX = 6 * 3600000;
/* 原 lastHydrateAt（最近一次用缓存铺屏的数据时刻）只服务于已删除的顶栏提示，一并移除 */

function hydrateProjectFromCache(prj){
  const data = projectData(prj);
  const list = cacheGet('devlist', prj);
  const now = Date.now();
  if (!list || !Array.isArray(list.list) || !list.list.length) return false;
  const listAge = now - list.at;
  if (listAge >= CACHE_STALE_MAX) return false;

  const live = cacheGet('devlive', prj);
  const liveAge = live ? (now - live.at) : Infinity;
  const liveOk = liveAge < CACHE_STALE_MAX;
  data.project = prj;
  data.devices = list.list.map(function(r){
    const d = deviceFromRecord(r.id, null, null);
    d.name = r.name || r.id;
    const c = liveOk ? (live.live || {})[r.id] : null;
    if (c){
      CACHE_DEV_FIELDS.forEach(function(k){ if (c[k] !== undefined) d[k] = c[k]; });
      /* 相对时间（hbOffset = 距最近上报多少秒）是落盘那一刻算出来的：
         用过期缓存时必须按缓存年龄补正，否则会显示「3 分钟前」这种假新鲜感 */
      if (typeof c.hbOffset === 'number' && liveAge > CACHE_LIVE_TTL){
        d.hbOffset = c.hbOffset + Math.round(liveAge / 1000);
      }
      d.fromCache = true;
    }
    return d;
  });
  data.loaded = true;
  prj.total = list.total || data.devices.length;
  recomputeProjectStats(prj);
  /* 顶栏更新提示已按需求删除（原 lastHydrateAt = list.at 一并移除）；
     缓存照旧用于铺屏，listAge 仍参与上面的过期判断 */
  return true;
}

/* =========================================================
   11. 数据刷新（真实数据 · 与设备上报周期对齐 60s）
   —— 模板此处原为「模拟实时告警推送」（随机造事件），
      现改为定时拉取真实数据；页面隐藏时跳过，避免无谓请求与平台限频。
   ========================================================= */
let lastRefreshAt = Date.now();
function scheduleProjectRefresh(){
  setInterval(function(){
    if (document.hidden) return;              /* 后台不刷新：省请求、也避开平台限频 */
    lastRefreshAt = Date.now();
    if (typeof refreshCurrentProject === 'function') refreshCurrentProject();
  }, 60000);

  /* 后台期间数据会变旧，回到前台时若已超过一个刷新周期就补刷一次。
     但**不能立刻补**：用户切回标签页往往紧接着就点导航，那一刻的刷新会和
     新页面的接口链抢带宽（实测会把这几个请求的等待时间拉长一倍）。
     所以延后 3 秒；期间若点了导航链接（马上要离开本页）或页面又被隐藏，就放弃这次补刷。 */
  let visibleTimer = null;
  function cancelCatchUp(){ if (visibleTimer){ clearTimeout(visibleTimer); visibleTimer = null; } }
  document.addEventListener('click', function(e){
    if (e.target && e.target.closest && e.target.closest('a[href]')) cancelCatchUp();
  }, true);
  window.addEventListener('pagehide', cancelCatchUp);
  document.addEventListener('visibilitychange', function(){
    if (document.hidden){ cancelCatchUp(); return; }
    if (Date.now() - lastRefreshAt < 60000) return;
    cancelCatchUp();
    visibleTimer = setTimeout(function(){
      visibleTimer = null;
      if (document.hidden) return;
      lastRefreshAt = Date.now();
      if (typeof refreshCurrentProject === 'function') refreshCurrentProject();
    }, 3000);
  });
}

/* =========================================================
   设备最新 Tag：串行队列 + 按需拉取
   —— 设备列表每页渲染即触发「该页设备」的实时拉取；
      切换页码 / 搜索 / 筛选都会重新触发（renderDevices 内调用）。
   —— 逐台串行、设备间间隔 100ms（平台建议），无固定台数上限；
      同一设备 20s 内不重复拉取（避免滚动/重绘造成重复请求）。
   —— 队列优先级 = 入队顺序，因此首屏先取当前页，其余设备随后补齐。
   ========================================================= */
/* 实时 Tag 的「够新鲜就不重复查」窗口 —— 这是前端自己的节流，不是平台限制
   （平台限制见文件上方闸门注释：单用户 10 次/秒等）。设备周期上报 60s、
   电压变化时另有即时上报，列表侧 65s 内不重复拉一次即可。 */
const TAG_FRESH_MS = 65000;
const LOC_FRESH_MS = 300000;    /* 位置/地址：5 分钟 */
const INFO_FRESH_MS = 3600000;  /* 设备信息(798/783/1027)：开机上报一次，1 小时查一次足够 */
let tagQueue = [];
let tagPumping = false;

function queueTags(imeis, force){
  const data = curData();
  const seen = {};
  (imeis || []).filter(Boolean).forEach(function(id){
    if (seen[id]) return;
    seen[id] = 1;
    const dev = data.devices.find(function(x){ return x.id === id; });
    if (!dev) return;
    if (!force && dev.tagAt && (Date.now() - dev.tagAt) < TAG_FRESH_MS) return;
    if (tagQueue.indexOf(id) === -1) tagQueue.push(id);
  });
  pumpTags();
}

function pumpTags(){
  if (tagPumping) return;
  const id = tagQueue.shift();
  if (!id){ tagPumping = false; return; }
  tagPumping = true;

  const now = Date.now();
  const prj = curProject();
  const data = curData();
  const dev0 = data.devices.find(function(x){ return x.id === id; });
  /* 位置是否要重新查：除"我们自己的取数时刻 locAt"外，还要看**平台位置数据的时间 locTime**
     —— 只信 locAt 会被伪刷新骗过（见 flush 注释），历史缓存里就有这种脏数据；
        以 locTime 为准，任何"数据本身已经过期"的位置都会被重新拉取 */
  const locTimeMs = (dev0 && dev0.locTime) ? (App.utils.parseLocal(dev0.locTime) || 0) : 0;
  const needLoc  = !dev0 || !dev0.locAt || (now - dev0.locAt) > LOC_FRESH_MS ||
                   (locTimeMs > 0 && (now - locTimeMs) > LOC_FRESH_MS);
  const needInfo = !dev0 || !dev0.infoAt || (now - dev0.infoAt) > INFO_FRESH_MS;

  /* 本设备的中间态 + 落地函数：
     周期 Tag / 位置 / 设备信息 三个数据源「各自到达即立即合并渲染」，
     绝不互相等待——否则设备信息被限频闸门排在 15s 之后，实时值会一直不显示。 */
  const devState = { rec: null, loc: null, info: null, locFromApi: false, locFromTag: false };
  function flush(){
    const dev = data.devices.find(function(x){ return x.id === id; });
    if (!dev) return;
    /* 沿用设备上已有的位置信息，只是为了不让 address/percent 被清空；
       —— 注意：这**不算**"取到了新位置"，绝不能因此盖 locAt（那是本次报障的根因） */
    if (!devState.loc && (dev.address || dev.lng != null)){
      devState.loc = {
        address: dev.address, lng: dev.lng, lat: dev.lat,
        signal: dev.hasSignal ? dev.snr : undefined, percent: dev.percent
      };
    }
    /* 周期报文里自带经纬度（Tag 512/513）：这也是一次真实的位置更新，
       同时把"位置数据时间"记成该报文的时间（界面显示才与事实一致） */
    if (devState.rec && devState.rec.lng != null && devState.rec.lat != null){
      devState.locFromTag = true;
      if (devState.rec.lastCt){
        try { devState.locTimeText = App.utils.formatTime(devState.rec.lastCt); } catch (e){}
      }
    }
    const merged = Object.assign({}, devState.rec || {}, {
      iccid:   (devState.info && devState.info.iccid   !== undefined) ? devState.info.iccid   : dev.iccid,
      version: (devState.info && devState.info.version !== undefined) ? devState.info.version : dev.version,
      deviceId:(devState.info && devState.info.deviceId!== undefined) ? devState.info.deviceId: dev.deviceId
    });
    if (!devState.rec && devState.info && devState.info.lastCt) merged.lastCt = devState.info.lastCt;
    const nd = deviceFromRecord(id, merged, devState.loc);
    nd.name = dev.name;
    Object.assign(dev, nd);
    dev.tagAt = Date.now();
    /* 只有「接口取回位置」或「周期报文带经纬度」才算位置刷新过 */
    if (devState.locFromApi || devState.locFromTag) dev.locAt = Date.now();
    if (devState.locFromTag && devState.locTimeText) dev.locTime = devState.locTimeText;
    if (devState.info) dev.infoAt = Date.now();
    dev.fromCache = false;          /* 已是刚拉到的真实值 */
    if (prj) recomputeProjectStats(prj);
    scheduleRender();
    scheduleCacheFlush();          /* 节流写回 sessionStorage，供切页复用 */
    /* 详情页正开着这台设备时让它跟着刷新（否则画面停在打开那一刻的快照） */
    if (typeof refreshOpenDetail === 'function') refreshOpenDetail(id);
  }

  /* 0) 位置与设备信息各自独立发起，**绝不依赖周期 Tag 是否成功**
     —— 周期 Tag 会失败（设备从无上报记录、或命中平台限频），
        原先把位置查询挂在它的成功回调里，等于这类设备永远不问位置：
        经纬度一直是 null → 地图上永远停在园区默认位置（本次报障的根因）。
     —— 三个数据源各自到达即落地（flush），互不等待。 */
  if (needLoc){
    apiLatestLocation(id).then(function(l){
      if (l && l.value){ devState.loc = l.value; devState.locFromApi = true; flush(); }
    }, function(){});
  }
  if (needInfo){
    apiTagsGated(id, App.config.INFO_TAGS, 1, 1, periodFilter(now - 30 * 86400000, now))
      .then(function(r2){
        const v2 = r2.value || {};
        const rr = (v2.records && v2.records[0]) || null;
        if (rr){ devState.info = parseTagRecord(rr); flush(); }
      }, function(){});
  }

  /* 1) 周期 Tag（799/265/800/781/782 + 经纬度 512/513）——统一走限频闸门 */
  apiTagsGated(id, App.config.DEVICE_TAGS, 1, 1).then(function(res){
    const v = res.value || {};
    const rec = (v.records && v.records[0]) || null;
    devState.rec = rec ? parseTagRecord(rec) : null;
    flush();
  }).catch(function(){
    /* 单台失败不影响整体；标记时间避免立刻重试打爆限频 */
    const dev = data.devices.find(function(x){ return x.id === id; });
    if (dev) dev.tagAt = Date.now();
  }).then(function(){
    tagPumping = false;
    setTimeout(pumpTags, 100);   /* 平台建议：多设备轮询时设备间隔 ≥100ms */
  });
}

/* 由已拉取到的真实 Tag 重算项目级统计 */
function recomputeProjectStats(prj){
  const data = projectData(prj);
  data.alerts = buildAlertsFromDevices(data.devices);
  data.kpi.online = data.devices.filter(devOnline).length;
  data.kpi.alert = data.devices.filter(devAlarmed).length;
  data.kpi.loaded = data.devices.filter(function(d){ return !!d.tagAt; }).length;
  prj.offline = data.devices.filter(function(d){ return d.tagAt && !d.online; }).length;
  prj.warn = data.devices.filter(function(d){ return d.tagAt && d.online && d.alarm !== 'none'; }).length;
  /* 告警通知：每次数据刷新都比对一次（页面打开后第一次只登记现有告警，不推历史告警）。
     放在这里是「跨页共用」的告警重算汇聚点 —— 任一页面开着都能推送。 */
  try { notifyDispatch(data.alerts); } catch(e){}
}

/* 手动 / 定时刷新当前项目 */
function refreshCurrentProject(){
  const prj = curProject();
  if (!prj) return Promise.resolve();
  return loadProjectData(prj);
}


/* ==== 跨页共用：由 _deploy/fix-crosspage.js 从 pages/devices.js 移入 ==== */
/* 通信质量：按信号强度分级（离线无读数，直接判失联）
   —— Tag 782 是统一 0~31 刻度：4G=CSQ 原值；WiFi=RSSI 折算（≥-50→31、≤-100→0）
   —— 4G 沿用 CSQ 经验阈值；WiFi 反推回 RSSI 后套用设备端屏幕同一套阈值
      （home_win.lua：rssi>-60→4 档、>-70→3 档、>-80→2 档、其余 1 档），
      这样网页档位与设备屏幕一致，不会出现"机器 4 格、网页说一般"
   —— 99（设备端规定 4G 无信号/不可测）与缺数据都如实显示，绝不判成"优秀" */
const SIGNAL_LEVEL_TEXT = ['', '较差', '一般', '良好', '优秀'];
/* 782（0~31）反推 WiFi RSSI（dBm）：与设备端折算公式互逆 */
function signalToRssi(v){ return Math.round(v / 31 * 50 - 100); }
/* 联网方式文案：0/缺省=老固件未上报（绝不编造） */
function netTagText(n){ return (App.config.BIZ.NET_TYPE_TEXT || {})[Number(n)] || '未上报'; }
/* 只要强弱档位词（明细表这类密集场合用），避免塞整句 */
function signalLevelText(netType, value){
  const t = String(qualityOf({ online: true, hasSignal: true, snr: value, netType: netType }).text || '');
  if (t.indexOf('无信号') > -1) return '无信号';
  const m = t.match(/(较差|一般|良好|优秀)/);
  return m ? m[1] : '--';
}

function qualityOf(d){
  const nt = Number(d.netType) || 0;
  if (!d.online) return { lv: 0, text: '失联', color: cssVar('--muted') };
  /* 设备不上报信号时如实显示“未上报”，不伪装成 0 */
  if (!d.hasSignal) return { lv: 0, text: '设备未上报信号', color: cssVar('--muted') };
  const v = Number(d.snr);
  const toneOf = lv => cssVar(lv >= 4 ? '--green' : (lv === 3 ? '--cyan' : (lv === 2 ? '--amber' : '--red')));
  if (nt === 1 && v >= 99) return { lv: 0, text: '4G 无信号', color: cssVar('--red') };
  if (nt === 2){
    const rssi = signalToRssi(v);
    const lv = rssi > -60 ? 4 : (rssi > -70 ? 3 : (rssi > -80 ? 2 : 1));
    return { lv: lv, text: 'WiFi 信号 ' + SIGNAL_LEVEL_TEXT[lv] + '（约 ' + rssi + ' dBm）', color: toneOf(lv) };
  }
  /* 4G；未上报联网方式的老固件按 CSQ 处理 */
  const lv = v >= 20 ? 4 : (v >= 15 ? 3 : (v >= 10 ? 2 : 1));
  return { lv: lv, text: (nt === 1 ? '4G · ' : '') + 'CSQ ' + v + ' · ' + SIGNAL_LEVEL_TEXT[lv], color: toneOf(lv) };
}

/* 上报间隔文案（秒 → 可读文本） */
function hbText(sec){
  if (sec < 60) return sec + ' 秒前';
  if (sec < 3600) return Math.round(sec / 60) + ' 分钟前';
  return (sec / 3600).toFixed(1) + ' 小时前';
}

/* 最近上报的绝对时间文案：年月日时分秒（本地时区）
   —— 优先用云端上报时间戳 lastCt；没有（老缓存 / 云端无记录）才用
      「当前时间 − 距上次上报秒数」回推，两者口径一致。
   —— 设备详情「基本信息」用它，替代原来的「0 秒前 / 0s」 */
function hbTimeText(d){
  if (!d) return '--';
  const ts = (typeof d.lastCt === 'number' && d.lastCt > 0) ? d.lastCt
           : ((typeof d.hbOffset === 'number' && d.hbOffset > 0) ? (Date.now() - d.hbOffset * 1000) : null);
  return (ts === null) ? '无上报记录' : App.utils.formatTime(ts);
}

/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */

const NOTIFY_KEY = 'nexus-notify';

const NOTIFY_META = [
  { id:'dingtalk', name:'钉钉机器人', short:'钉钉', brand:'#3296fa',
    desc:'群机器人 Webhook · 支持加签校验',
    secret:'加签密钥', to:'@手机号',
    demo:'https://oapi.dingtalk.com/robot/send?access_token=DEMO-3f2a91c7',
    icon:'M12 2.5c5.2 0 9.5 4.3 9.5 9.5s-4.3 9.5-9.5 9.5S2.5 17.2 2.5 12 6.8 2.5 12 2.5zm1.3 5-4.5 6.2h3.1l-1 4.8 4.6-6.3h-3.2l1-4.7z' },
  { id:'feishu', name:'飞书机器人', short:'飞书', brand:'#3370ff',
    desc:'自定义机器人 · 支持签名校验',
    secret:'签名密钥', to:'接收人 OpenID',
    demo:'https://open.feishu.cn/open-apis/bot/v2/hook/DEMO-7b41e0',
    icon:'M20.8 3.3 3.5 10.4c-.9.4-.8 1.7.1 2l4.8 1.5 1.7 5c.3.9 1.6 1 2 .2l8.7-15.8zM9.9 13.4l7.4-6.8-6 8-.4 3.3-1-4.5z' },
  { id:'wecom', name:'企业微信机器人', short:'企微', brand:'#07c160',
    desc:'群机器人 · 支持 Markdown 消息',
    secret:'回调 Token', to:'@成员账号',
    demo:'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=DEMO-2c9d84',
    icon:'M9.3 3.4C5.3 3.4 2 6 2 9.3c0 1.9 1.1 3.5 2.8 4.6l-.7 2.3 2.5-1.3c.9.2 1.8.4 2.7.4h.4a5.6 5.6 0 0 1-.2-1.5c0-3.1 3.2-5.6 7.1-5.6h.5c-.9-2.9-4.2-4.8-7.8-4.8zm10.3 5.9c-3.3 0-5.9 2.1-5.9 4.6 0 2.6 2.6 4.6 5.9 4.6.7 0 1.3-.1 2-.3l2 1-.5-1.8c1.1-.8 1.8-2 1.8-3.5 0-2.5-2.6-4.6-5.3-4.6z' }
];

/* 通知渠道默认值：必须在 notifyCfg 初始化之前声明（否则 const 的 TDZ 会报
   "Cannot access 'NOTIFY_DEF' before initialization"）
   —— sent / last 是「真实推送统计」：只在实际送达时累加。
      早期版本这里写死的 214 / 96 是演示数字（从未真的发出过任何消息），已清零；
      浏览器里已存的旧值由 loadNotifyConfig() 迁移掉。 */
const NOTIFY_DEF = {
  dingtalk:{ on:true,  webhook:'', secret:'', to:'', fmt:'md', sent:0, last:0 },
  feishu:  { on:true,  webhook:'', secret:'', to:'', fmt:'md', sent:0, last:0 },
  wecom:   { on:false, webhook:'', secret:'', to:'', fmt:'md', sent:0, last:0 },
  strategy:{ level:'critical', win:60, quiet:true }
};

let notifyCfg = JSON.parse(JSON.stringify(NOTIFY_DEF));

/* =========================================================
   告警通知引擎（钉钉 / 飞书 / 企业微信）—— 跨页共用
   · 配置与推送记录都存本机 localStorage（换电脑/换浏览器/清站点数据会丢，不随账号同步）
   · 触发：任一页面拿到新数据时比对告警（见 recomputeProjectStats 末尾的调用），
     所以「页面开着」才可能推送 —— 这是纯前端方案的固有边界；
     要做到页面关着也能推、并能拿到渠道真实回执，需在 config.js 配 API.NOTIFY_RELAY 走服务端转发。
   · 发送是真的网络请求；结果如实区分 已送达 / 已提交但读不到回执 / 失败。
   ========================================================= */
const NOTIFY_LOG_KEY = 'nexus-notify-log';
const NOTIFY_LOG_MAX = 60;

/* ---------- 配置：读取（必须在公共层做，否则只有系统设置页显示真实配置） ---------- */
function loadNotifyConfig(){
  try {
    const raw = localStorage.getItem(NOTIFY_KEY);
    if (raw){
      const saved = JSON.parse(raw);
      Object.keys(NOTIFY_DEF).forEach(function(k){
        if (k === 'strategy') notifyCfg.strategy = Object.assign({}, NOTIFY_DEF.strategy, saved.strategy || {});
        else if (saved[k]) notifyCfg[k] = Object.assign({}, NOTIFY_DEF[k], saved[k]);
      });
      /* 迁移：老版本的 sent(214/96) 是演示数字，last=0 说明从未真正推送过 → 统计清零 */
      NOTIFY_META.forEach(function(m){
        const c = notifyCfg[m.id];
        if (c && !c.last && c.sent) c.sent = 0;
      });
    }
  } catch(e){}
  return notifyCfg;
}
function saveNotifyConfig(){
  try { localStorage.setItem(NOTIFY_KEY, JSON.stringify(notifyCfg)); } catch(e){}
}
/* 恢复出厂值：就地重置（notifyCfg 被多处引用，不能整体重新赋值） */
function notifyResetConfig(){
  const def = JSON.parse(JSON.stringify(NOTIFY_DEF));
  Object.keys(notifyCfg).forEach(function(k){ delete notifyCfg[k]; });
  Object.keys(def).forEach(function(k){ notifyCfg[k] = def[k]; });
  saveNotifyConfig();
}
loadNotifyConfig();        /* 加载即读：任何页面拿到的都是用户真实配置 */

/* ---------- 推送记录：落盘（刷新不丢） ---------- */
let notifyLog = (function(){
  try {
    const raw = localStorage.getItem(NOTIFY_LOG_KEY);
    const arr = raw ? JSON.parse(raw) : [];
    return Array.isArray(arr) ? arr : [];
  } catch(e){ return []; }
})();
function saveNotifyLog(){
  try { localStorage.setItem(NOTIFY_LOG_KEY, JSON.stringify(notifyLog.slice(0, NOTIFY_LOG_MAX))); } catch(e){}
}
function notifyLogAdd(entry){
  notifyLog.unshift(entry);
  if (notifyLog.length > NOTIFY_LOG_MAX) notifyLog.length = NOTIFY_LOG_MAX;
  saveNotifyLog();
  if (typeof renderNotifyLog === 'function' && document.getElementById('ntLog')) renderNotifyLog();
}
function notifyLogClear(){ notifyLog.length = 0; saveNotifyLog(); }

/* ---------- 时间戳：公共层没有页面级的 dvDT，这里自带实现 ---------- */
function notifyStamp(ts){
  if (typeof dvDT === 'function') return dvDT(ts);
  const d = new Date(ts), p = function(n){ return (n < 10 ? '0' : '') + n; };
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' +
         p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

/* ---------- 策略：触发等级 / 聚合窗口 / 夜间免打扰 ---------- */
const NOTIFY_RANK = { critical:3, warning:2, info:1 };
const NOTIFY_TH   = { critical:3, warning:2, all:0 };
function notifyStrategy(){ return notifyCfg.strategy || NOTIFY_DEF.strategy; }
function notifyLevelPass(level){
  const th = NOTIFY_TH[notifyStrategy().level];
  return (NOTIFY_RANK[level] || 1) >= (th === undefined ? 3 : th);
}
function notifyQuietNow(ts){
  if (!notifyStrategy().quiet) return false;
  const h = new Date(ts || Date.now()).getHours();
  return h >= 22 || h < 8;                 /* 22:00 ~ 08:00 只记录不推送 */
}
function notifyWindowMs(){
  return Math.max(0, Math.min(600, Number(notifyStrategy().win) || 0)) * 1000;
}

/* ---------- 消息体：按各渠道协议构造 ---------- */
function notifyPrjName(item){
  const prj = (item && item.prj) || curProject() || {};
  return prj.short || prj.name || '当前项目';
}
function notifyTitleOf(item){
  const n = (item.alerts || []).length;
  return notifyPrjName(item) + ' 电力告警' + (n > 1 ? '（' + n + ' 条）' : '') + (item.test ? '（测试）' : '');
}
function notifyTextOf(item){
  const lines = ['【' + notifyPrjName(item) + ' 电力告警】' + (item.test ? '（测试消息）' : '')];
  (item.alerts || []).forEach(function(a, i){
    lines.push((i + 1) + '. ' + (a.level === 'critical' ? '【严重】' : a.level === 'warning' ? '【警告】' : '【提示】') +
               (a.title || '') + (a.meta ? '（' + a.meta + '）' : ''));
  });
  lines.push('时间：' + notifyStamp(Date.now()));
  lines.push('（由网页端发出：页面需保持打开；要关页也推送需配置 NOTIFY_RELAY 服务端中继）');
  return lines.join('\n');
}
function notifySiteUrl(){
  try { return location.origin + (App.config.BASE_PATH || '/'); } catch(e){ return ''; }
}
function notifyPayload(chanId, cfg, item){
  const title = notifyTitleOf(item), text = notifyTextOf(item), fmt = cfg.fmt || 'md';
  const at = String(cfg.to || '').split(',').map(function(s){ return s.trim(); }).filter(Boolean);
  if (chanId === 'dingtalk'){
    if (fmt === 'text') return { msgtype:'text', text:{ content: title + '\n' + text }, at:{ atMobiles: at, isAtAll:false } };
    if (fmt === 'card') return { msgtype:'actionCard', actionCard:{ title: title, text: text.replace(/\n/g, '  \n'),
      singleTitle:'查看详情', singleURL: notifySiteUrl() } };
    return { msgtype:'markdown', markdown:{ title: title, text: '### ' + title + '\n' + text },
             at:{ atMobiles: at, isAtAll:false } };
  }
  if (chanId === 'wecom'){
    if (fmt === 'text') return { msgtype:'text', text:{ content: title + '\n' + text, mentioned_mobile_list: at } };
    /* 企业微信群机器人没有卡片消息，卡片格式降级为 markdown */
    return { msgtype:'markdown', markdown:{ content: '### ' + title + '\n' + text } };
  }
  /* 飞书自定义机器人：text 最通用（卡片需完整 interactive 结构，这里降级为 text） */
  return { msg_type:'text', content:{ text: title + '\n' + text } };
}

/* ---------- 加签（钉钉 / 飞书；密钥留空则不加签） ---------- */
function notifyB64(buf){
  const b = new Uint8Array(buf); let s = '';
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s);
}
function notifyHmacB64(secret, msg){
  const enc = new TextEncoder();
  return crypto.subtle.importKey('raw', enc.encode(secret), { name:'HMAC', hash:'SHA-256' }, false, ['sign'])
    .then(function(key){ return crypto.subtle.sign('HMAC', key, enc.encode(msg)); })
    .then(function(sig){ return notifyB64(sig); });
}
function notifySignedRequest(chanId, cfg, payload){
  const url = String(cfg.webhook || '').trim();
  const secret = String(cfg.secret || '').trim();
  if (!secret || !window.crypto || !crypto.subtle) return Promise.resolve({ url: url, body: payload });
  const ts = Date.now();
  if (chanId === 'dingtalk'){
    return notifyHmacB64(secret, ts + '\n' + secret).then(function(sign){
      return { url: url + (url.indexOf('?') > -1 ? '&' : '?') + 'timestamp=' + ts + '&sign=' + encodeURIComponent(sign), body: payload };
    }).catch(function(){ return { url: url, body: payload }; });
  }
  if (chanId === 'feishu'){
    /* 飞书：以「timestamp + \n + secret」为密钥、消息为空做 HMAC-SHA256 */
    return notifyHmacB64(ts + '\n' + secret, '').then(function(sign){
      return { url: url, body: Object.assign({}, payload, { timestamp: String(Math.floor(ts / 1000)), sign: sign }) };
    }).catch(function(){ return { url: url, body: payload }; });
  }
  return Promise.resolve({ url: url, body: payload });   /* 企微群机器人无需加签 */
}

/* ---------- 发送（真实网络请求） ----------
   返回 { state, detail }：ok=已送达 / unknown=已提交但读不到回执 / fail=失败 */
function notifySendOnce(chanId, cfg, item){
  const relay = (App.config.API && App.config.API.NOTIFY_RELAY) || '';
  return notifySignedRequest(chanId, cfg, notifyPayload(chanId, cfg, item)).then(function(target){
    if (relay){
      return App.http.post(relay, { channel: chanId, url: target.url, secret: String(cfg.secret || ''), payload: target.body })
        .then(function(res){
          const ok = res && (res.ok === true || res.code === 0 || res.errcode === 0);
          return ok ? { state:'ok', detail:'服务端中继已送达' }
                    : { state:'fail', detail:'中继返回失败：' + JSON.stringify((res && (res.msg || res.value || res.errmsg)) || res) };
        })
        .catch(function(e){ return { state:'fail', detail:'中继请求失败：' + ((e && e.message) || '未知错误') }; });
    }
    const body = JSON.stringify(target.body);
    return fetch(target.url, { method:'POST', mode:'cors', headers:{ 'Content-Type':'application/json' }, body: body })
      .then(function(r){
        return r.text().then(function(txt){
          let j = null; try { j = JSON.parse(txt); } catch(e){}
          const code = j ? (j.errcode !== undefined ? j.errcode : j.code) : (r.ok ? 0 : r.status);
          if (r.ok && (code === 0 || code === undefined || code === null)){
            return { state:'ok', detail:'渠道回执：发送成功' };
          }
          return { state:'fail', detail:'渠道返回 ' + code + '：' + (((j && (j.errmsg || j.msg)) || txt || '').slice(0, 80)) };
        });
      })
      .catch(function(e1){
        /* 直连被跨域拦下：用 no-cors 再投一次（请求会真正发出，但读不到回执） */
        return fetch(target.url, { method:'POST', mode:'no-cors',
          headers:{ 'Content-Type':'text/plain;charset=UTF-8' }, body: body })
          .then(function(){ return { state:'unknown', detail:'已提交，但浏览器跨域限制读不到渠道回执' }; })
          .catch(function(e2){
            return { state:'fail', detail:'发送失败：' + ((e2 && e2.message) || (e1 && e1.message) || '网络或跨域错误') };
          });
      });
  });
}

/* ---------- 投递一条（含记录 + 统计 + 界面刷新） ---------- */
function notifyRefreshGrid(){
  if (typeof renderNotifyGrid !== 'function' || !document.getElementById('ntGrid')) return;
  const ae = document.activeElement;
  if (ae && ae.closest && ae.closest('[data-nt-field], #ntWin')) return;   /* 正在输入时不重渲染 */
  renderNotifyGrid();
}
function notifyDeliver(chanId, item, quiet){
  const c = notifyCfg[chanId];
  const title = notifyTitleOf(item);
  if (quiet){
    notifyLogAdd({ ch: chanId, state:'quiet', text: title + ' · 夜间免打扰（仅记录不推送）', time: notifyStamp(Date.now()) });
    return Promise.resolve({ state:'quiet', detail:'夜间免打扰' });
  }
  return notifySendOnce(chanId, c, item).then(function(r){
    const label = { ok:'已送达', unknown:'已提交·结果未知', fail:'失败' }[r.state] || r.state;
    notifyLogAdd({ ch: chanId, state: r.state,
      text: title + ' · ' + label + (r.detail ? '：' + r.detail : ''), time: notifyStamp(Date.now()) });
    if (r.state === 'ok') c.sent = (Number(c.sent) || 0) + 1;   /* 只统计「确认送达」的 */
    c.last = Date.now();
    saveNotifyConfig();
    notifyRefreshGrid();
    return r;
  });
}

/* ---------- 去重 / 聚合：同一设备同一告警只推一次，窗口内合并 ---------- */
const notifyMem = { seen:{}, buf:{}, timers:{}, seeded:{} };
function notifyKey(prjId, a){ return prjId + '|' + (a.deviceId || '') + '|' + (a.title || ''); }

function notifyDispatch(alerts){
  if (!alerts || !alerts.length) return;
  const prj = curProject();
  const pk = prj ? prj.id : '-';
  /* 本页打开后的第一次：把当前已有告警登记为「已知」——历史告警不该被当成新告警刷屏 */
  if (!notifyMem.seeded[pk]){
    notifyMem.seeded[pk] = true;
    alerts.forEach(function(a){ notifyMem.seen[notifyKey(pk, a)] = Date.now(); });
    return;
  }
  /* 已恢复的告警清掉记忆：同一告警再次出现时能重新推送 */
  const live = {};
  alerts.forEach(function(a){ live[notifyKey(pk, a)] = 1; });
  Object.keys(notifyMem.seen).forEach(function(k){
    if (k.indexOf(pk + '|') === 0 && !live[k]) delete notifyMem.seen[k];
  });

  alerts.forEach(function(a){
    const k = notifyKey(pk, a);
    if (notifyMem.seen[k]) return;         /* 已推送/已登记 */
    notifyMem.seen[k] = Date.now();
    if (!notifyLevelPass(a.level)) return; /* 未达触发等级：登记但不推送 */
    notifyMem.buf[k] = notifyMem.buf[k] || { prj: prj, alerts: [] };
    notifyMem.buf[k].alerts.push(a);
    if (!notifyMem.timers[k]) notifyMem.timers[k] = setTimeout(function(){ notifyFlushKey(k); }, notifyWindowMs());
  });
}

/* 聚合窗口结束：合并成一条，发给所有「已启用且填好 Webhook」的渠道 */
function notifyFlushKey(k){
  const item = notifyMem.buf[k];
  delete notifyMem.buf[k];
  if (notifyMem.timers[k]){ clearTimeout(notifyMem.timers[k]); delete notifyMem.timers[k]; }
  if (!item) return;
  const quiet = notifyQuietNow();
  const chans = NOTIFY_META.filter(function(m){
    const c = notifyCfg[m.id];
    return c && c.on && String(c.webhook || '').trim();
  });
  if (!chans.length){
    notifyLogAdd({ ch:'system', state:'skip', time: notifyStamp(Date.now()),
      text: notifyTitleOf(item) + ' · 未推送：没有已启用且填好 Webhook 的渠道' });
    return;
  }
  chans.forEach(function(m){ notifyDeliver(m.id, item, quiet); });
}

/* ---------- 测试消息：走同一套真实发送链路（系统设置页调用） ---------- */
function notifySendTest(chanId){
  const item = { prj: curProject(), test: true, alerts: [{
    level:'critical', deviceId:'TEST', title:'输出电压越限 5860 V',
    meta:'设定电压 3500 V · 测试消息，非真实告警'
  }] };
  return notifyDeliver(chanId, item, false);   /* 测试不套用等级 / 免打扰策略 */
}

/* ---------- 对外入口（跨页可用） ---------- */
window.App = window.App || {};
App.notify = {
  cfg: notifyCfg,
  load: loadNotifyConfig, save: saveNotifyConfig, reset: notifyResetConfig,
  log: notifyLog, logAdd: notifyLogAdd, logClear: notifyLogClear,
  levelPass: notifyLevelPass, quietNow: notifyQuietNow, windowMs: notifyWindowMs,
  payload: notifyPayload, deliver: notifyDeliver, send: notifySendOnce,
  dispatch: notifyDispatch, test: notifySendTest
};
