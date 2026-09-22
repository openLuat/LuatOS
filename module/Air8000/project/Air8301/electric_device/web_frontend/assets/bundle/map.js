/* 打包产物（合并顺序 = 模块加载顺序，勿手改）：luat-sdk.js + config.js + storage.js + utils.js + http.js + auth.js + guards.js + components.js + api.js + shell.js + pages/map.js + boot.js */
/* assets/js/luat-sdk.js —— 由 index.html 内联脚本拆出（原行区间 2934-3026），内容未改动 */
/* =========================================================
   LuatSDK —— 独立、零依赖的请求与存储能力（唯一直接调用 fetch 的层）
   ========================================================= */
(function(global){
  'use strict';
  var config = {
    API_HOST: 'https://api-iot.luatos.com',
    BASE_HOST: 'https://iot.luatos.com',
    API_BASE: 'https://api-iot.luatos.com/iot',
    OAUTH_AUTHORIZE_URL: 'https://api-iot.luatos.com/iam/luat_oauth/authorize',
    OAUTH_LOGIN_URL: 'https://api-iot.luatos.com/iam/luat_oauth/v2/login',
    REQUEST_TIMEOUT: 15000
  };
  var reqInts = [], resInts = [];
  var storage = {
    get: function(key){
      try { var raw = localStorage.getItem(key); if (raw === null || raw === '') return null; return JSON.parse(raw); }
      catch (e) { return null; }
    },
    set: function(key, value){ try { localStorage.setItem(key, JSON.stringify(value)); return true; } catch (e) { return false; } },
    remove: function(key){ try { localStorage.removeItem(key); } catch (e) {} },
    clear: function(prefix){
      try {
        var keys = [];
        for (var i = 0; i < localStorage.length; i++){ var k = localStorage.key(i); if (k && k.indexOf(prefix) === 0) keys.push(k); }
        for (var j = 0; j < keys.length; j++) localStorage.removeItem(keys[j]);
      } catch (e) {}
    },
    sessionGet: function(key){ try { return sessionStorage.getItem(key); } catch (e) { return null; } },
    sessionSet: function(key, value){ try { sessionStorage.setItem(key, value); return true; } catch (e) { return false; } },
    sessionRemove: function(key){ try { sessionStorage.removeItem(key); } catch (e) {} }
  };
  function buildUrl(url, baseURL){
    if (/^https?:\/\//i.test(url)) return url;
    var base = baseURL || config.API_BASE;
    return String(base).replace(/\/+$/, '') + '/' + String(url).replace(/^\/+/, '');
  }
  function makeError(type, message, extra){
    var e = new Error(message || type); e.type = type;
    if (extra) { for (var k in extra) if (Object.prototype.hasOwnProperty.call(extra, k)) e[k] = extra[k]; }
    return e;
  }
  function request(options){
    var opts = options || {};
    var cfg = {
      url: opts.url, method: String(opts.method || 'GET').toUpperCase(), baseURL: opts.baseURL,
      body: opts.body, params: opts.params,
      headers: opts.headers ? Object.assign({}, opts.headers) : {},
      timeout: opts.timeout || config.REQUEST_TIMEOUT
    };
    for (var i = 0; i < reqInts.length; i++){ var r = reqInts[i](cfg); if (r) cfg = r; }
    var fullUrl = buildUrl(cfg.url, cfg.baseURL);
    if (cfg.params){
      var usp = new URLSearchParams();
      Object.keys(cfg.params).forEach(function(k){ var v = cfg.params[k]; if (v !== undefined && v !== null) usp.append(k, v); });
      var qs = usp.toString();
      if (qs) fullUrl += (fullUrl.indexOf('?') > -1 ? '&' : '?') + qs;
    }
    var controller = (typeof AbortController !== 'undefined') ? new AbortController() : null;
    var timer = setTimeout(function(){ if (controller) controller.abort(); }, cfg.timeout);
    var init = { method: cfg.method, headers: cfg.headers };
    if (controller) init.signal = controller.signal;
    if (cfg.body !== undefined && cfg.body !== null){
      if (typeof cfg.body === 'string'){ init.body = cfg.body; }
      else { if (!init.headers['Content-Type']) init.headers['Content-Type'] = 'application/json'; init.body = JSON.stringify(cfg.body); }
    }
    return fetch(fullUrl, init).then(function(res){
      return res.text().then(function(text){
        if (!res.ok) throw makeError('http', 'HTTP ' + res.status, { status: res.status });
        if (!text) return {};
        try { return JSON.parse(text); } catch (e) { throw makeError('parse', '响应解析失败'); }
      });
    }).catch(function(err){
      if (err && (err.name === 'AbortError' || err.aborted)) throw makeError('timeout', '请求超时');
      if (err && (err.type === 'http' || err.type === 'parse')) throw err;
      throw makeError('network', '网络请求失败');
    }).then(function(data){
      for (var k = 0; k < resInts.length; k++){ var out = resInts[k](data); if (out !== undefined) data = out; }
      return data;
    }).then(function(data){ clearTimeout(timer); return data; }, function(err){ clearTimeout(timer); throw err; });
  }
  global.LuatSDK = {
    config: config,
    http: {
      request: request,
      get: function(url, params, c){ return request({ url: url, method: 'GET', params: params, baseURL: c && c.baseURL, headers: c && c.headers }); },
      post: function(url, body, c){ return request({ url: url, method: 'POST', body: body, baseURL: c && c.baseURL, headers: c && c.headers }); },
      interceptors: { request: { use: function(fn){ reqInts.push(fn); } }, response: { use: function(fn){ resInts.push(fn); } } }
    },
    storage: storage
  };
})(window);


/* assets/js/config.js —— 由 index.html 内联脚本拆出（原行区间 3027-3094），内容未改动 */
/* =========================================================
   App.config —— 公开常量、真实接口表、appId、应用 base path
   ========================================================= */
window.App = window.App || {};
App.config = (function(){
  var SDK = window.LuatSDK;
  var path = window.location.pathname;
  var slash = path.lastIndexOf('/');
  var basePath = (slash >= 0) ? path.slice(0, slash + 1) : '/';
  var m = path.match(/\/ai_app\/luatos\/([^\/?#]+)/i);
  var APP_ID_FALLBACK = '';
  var appId = (m && m[1]) ? m[1] : APP_ID_FALLBACK;
  return {
    APP_ID: appId,
    BASE_PATH: basePath,
    API_HOST: SDK.config.API_HOST,
    BASE_HOST: SDK.config.BASE_HOST,
    API_BASE: SDK.config.API_BASE,
    OAUTH_AUTHORIZE_URL: SDK.config.OAUTH_AUTHORIZE_URL,
    OAUTH_LOGIN_URL: SDK.config.OAUTH_LOGIN_URL,
    PAGE: document.body.getAttribute('data-page') || '',
    AUTH: document.body.getAttribute('data-auth') || 'public',
    API: {
      PROJECTS: '/open_api/list_my_projects',
      SEARCH_DEVICES: '/open_api/search_my_devices',
      LIST_BY_TAGS: '/open_api/aircloud/list_by_tags',
      LATEST_LOCATION: '/open_api/aircloud/latest_location',
      SEND_CMD: '/open_api/aircloud/send_cmd',
      /* 告警通知的「服务端中继」（可选；留空 = 浏览器直连渠道 Webhook）
         —— 留空：浏览器直接 POST 钉钉/飞书/企微 Webhook，受跨域限制读不到渠道回执，
                  只能确认「已提交」，且必须页面开着才会推送；
         —— 填写后：由服务端转发，可拿到真实回执，也能做到页面关着也推送。
         中继契约：POST { channel, url, secret, payload } → { ok:true } 或 { code:0 } 表示成功 */
      NOTIFY_RELAY: ''
    },
    TAGS: {
      /* 与设备端 protocol_app.lua 的字段表严格一致：
         19=控制命令(下行) 20=控制回应(上行) 25=运维日志上传请求(下行)
         265=工作状态 799=实际电压 800=设定电压 783=SIM卡ICCID
         798=设备号(IMEI) 1027=固件版本号 512=经度 513=纬度
         781=联网方式（1=4G / 2=WiFi / 3=以太网）
         782=信号强度（统一 0~31 刻度：4G=CSQ 原值，99=无信号/不可测；
                        WiFi=RSSI 折算：≥-50→31、≤-100→0、中间按比例）
         注意：781/782 是设备端新增字段，随周期上报纸文一起发（不是单独报文）；
              老固件不上报 → 界面显示「未上报」，绝不把缺失数据伪装成 0 */
      WORK_STATUS: 265, VOLTAGE: 799, SET_VOLTAGE: 800, ICCID: 783,
      DEVICE_ID: 798, VERSION: 1027, REPORT_TIME: 1280,
      LNG: 512, LAT: 513,
      NETWORK_TYPE: 781, SIGNAL: 782,
      CTRL_CMD: 19, CTRL_RESP: 20, MTN_LOG_REQ: 25
    },
    TAG_META: {
      19: { name: '控制命令', type: '嵌套TLV', cat: '控制信令（下行）' },
      20: { name: '控制回应', type: '嵌套TLV', cat: '控制信令（上行）' },
      25: { name: '运维日志上传请求', type: '字节', cat: '控制信令（下行）' },
      265: { name: '工作状态', type: '整数', cat: '传感数据（1开机/0关机/255未同步）' },
      512: { name: '经度', type: 'ASCII', cat: '定位数据（基站定位LBS）' },
      513: { name: '纬度', type: 'ASCII', cat: '定位数据（基站定位LBS）' },
      781: { name: '联网方式', type: '整数', cat: '网络数据（1=4G/2=WiFi/3=以太网）' },
      782: { name: '信号强度', type: '整数', cat: '网络数据（统一0~31；4G=CSQ，99=无信号）' },
      783: { name: 'ICCID', type: '整数', cat: '设备参数' },
      798: { name: '设备号（IMEI）', type: '整数', cat: '设备参数' },
      799: { name: '实际电压', type: '整数', cat: '传感数据（V）' },
      800: { name: '设定电压', type: '整数', cat: '设备参数（V）' },
      1027: { name: '固件版本号', type: 'ASCII', cat: '软件数据' }
    },
    BIZ: {
      VOLTAGE_MIN: 0, VOLTAGE_MAX: 6000, VOLTAGE_STEP: 100,
      DEFAULT_SET_VOLTAGE: 3500, ONLINE_WINDOW_MS: 300000,
      CONTROL_TAG: 19, DEVICE_MODEL: 'Air8301 · 电场发生器通讯控制板',
      /* Tag 781 取值 → 文案（0/缺省=老固件未上报，不编造） */
      NET_TYPE_TEXT: { 1: '4G', 2: 'WiFi', 3: '以太网' }
    },
    /* 上报类 Tag：周期 60s 一次；此外设备在电压等发生变化时会即时上报（excloud trigger_report），
   所以前端可以按秒跟进最新一条（实际电压 / 工作状态 / 设定电压 / 联网方式 / 信号强度）
       —— 781/782 必须并进这一次查询：平台限频规则是"查询频率 ≈ 设备上报频率"，
          单独为它们再查一次会被直接拒绝（实测：请求过于频繁） */
    /* 周期 Tag：实际电压 / 工作状态 / 设定电压 / 联网方式 / 信号强度，
     外加设备上报的经纬度（512/513）——它们在同一条周期报文里（仅定位有效时追加），
     并进来不增加请求，却能避免"位置只靠 latest_location、一被限频就停在旧值" */
  DEVICE_TAGS: [799, 265, 800, 781, 782, 512, 513],
    /* 设备信息 Tag（鉴权成功后开机上报一次）：设备号 IMEI / ICCID / 固件版本
       —— 它们不在周期报文里，必须单独按较长时间窗查询，否则永远取不到 */
    INFO_TAGS: [798, 783, 1027]
  };
})();


/* assets/js/storage.js —— 由 index.html 内联脚本拆出（原行区间 3095-3162），内容未改动 */
/* =========================================================
   App.storage
   ========================================================= */
App.storage = (function(){
  var SDK = window.LuatSDK;
  function id(){ return App.config.APP_ID || '_app'; }
  var K = {
    auth: function(){ return id() + '_auth'; }, service: function(){ return id() + '_service'; },
    profile: function(){ return id() + '_profile'; }, tenant: function(){ return id() + '_tenant'; },
    sets: function(){ return id() + '_sets'; }, mAuth: function(){ return 'm_' + id() + '_auth'; },
    mService: function(){ return 'm_' + id() + '_service'; }, mProfile: function(){ return 'm_' + id() + '_profile'; },
    mSets: function(){ return 'm_' + id() + '_sets'; }, host: function(){ return 'm_' + id() + '_host_session'; },
    ui: function(){ return id() + '_ui'; }
  };
  function str(v){ return (typeof v === 'string') ? v : ''; }
  function readBundle(a, s, p, t){
    var A = SDK.storage.get(a) || {}, S = SDK.storage.get(s) || {}, P = SDK.storage.get(p) || {}, T = SDK.storage.get(t) || {};
    return {
      auth: { token: str(A.token), salt: str(A.salt) },
      service: { sid: str(S.sid) },
      profile: { name: str(P.name || P.user_name), mobile: str(P.mobile || P.user_phone) },
      sets: T
    };
  }
  function complete(ctx){ return !!(ctx && ctx.auth && ctx.auth.token && ctx.auth.salt && ctx.service && ctx.service.sid); }
  return {
    keys: K,
    readIndependent: function(){ return readBundle(K.auth(), K.service(), K.profile(), K.sets()); },
    readHost: function(){ return readBundle(K.mAuth(), K.mService(), K.mProfile(), K.mSets()); },
    isComplete: complete,
    hasHostSession: function(){ return SDK.storage.sessionGet(K.host()) === '1'; },
    setHostSession: function(on){ if (on) SDK.storage.sessionSet(K.host(), '1'); else SDK.storage.sessionRemove(K.host()); },
    saveLogin: function(value){
      if (!value || !value.auth || !value.service) return false;
      if (!complete({ auth: value.auth, service: value.service })) return false;
      var ok1 = SDK.storage.set(K.auth(), { token: value.auth.token, salt: value.auth.salt });
      var ok2 = SDK.storage.set(K.service(), { sid: value.service.sid });
      var user = value.user || {};
      SDK.storage.set(K.profile(), { name: str(user.name || user.user_name), mobile: str(user.mobile || user.user_phone) });
      if (value.tenant) SDK.storage.set(K.tenant(), value.tenant); else SDK.storage.remove(K.tenant());
      if (value.sets) SDK.storage.set(K.sets(), value.sets); else SDK.storage.remove(K.sets());
      return ok1 && ok2;
    },
    clearIndependent: function(){
      [K.auth(), K.service(), K.profile(), K.tenant(), K.sets()].forEach(function(k){ SDK.storage.remove(k); });
      [K.mAuth(), K.mService(), K.mProfile(), K.mSets()].forEach(function(k){ SDK.storage.remove(k); });
    },
    clearHost: function(){ [K.mAuth(), K.mService(), K.mProfile(), K.mSets()].forEach(function(k){ SDK.storage.remove(k); }); },
    applyHostInjection: function(p){
      if (!str(p.m_token) || !str(p.m_salt) || !str(p.m_sid)) return false;
      SDK.storage.set(K.mAuth(), { token: str(p.m_token), salt: str(p.m_salt) });
      SDK.storage.set(K.mService(), { sid: str(p.m_sid) });
      SDK.storage.set(K.mProfile(), { name: str(p.m_name), mobile: str(p.m_phone) });
      var sets = {};
      if (str(p.m_algorithm)) sets.algorithm = str(p.m_algorithm);
      if (str(p.m_encryptOutput)) sets.encryptOutput = str(p.m_encryptOutput);
      if (str(p.m_padding)) sets.padding = str(p.m_padding);
      if (str(p.m_publicKey)) sets.publicKey = str(p.m_publicKey);
      if (str(p.m_publicKeyEncoding)) sets.publicKeyEncoding = str(p.m_publicKeyEncoding);
      if (Object.keys(sets).length) SDK.storage.set(K.mSets(), sets);
      this.setHostSession(true);
      return true;
    },
    getUi: function(){ return SDK.storage.get(K.ui()) || {}; },
    setUi: function(obj){ SDK.storage.set(K.ui(), obj || {}); }
  };
})();


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

/* assets/js/http.js —— 由 index.html 内联脚本拆出（原行区间 3203-3234），内容未改动 */
/* =========================================================
   App.http —— 业务状态码与认证头
   ========================================================= */
App.http = (function(){
  var SDK = window.LuatSDK;
  var invalidHandler = null;
  function headers(){
    var ctx = App.auth.getAuthContext();
    if (!ctx) return {};
    return { 'authorization': ctx.auth.token, 'salt': ctx.auth.salt, 'sid': ctx.service.sid };
  }
  function handleBiz(promise){
    return promise.then(function(res){
      if (!res || typeof res.code === 'undefined') return res;
      if (res.code === 0) return res;
      if (res.code === 102 || res.code === 103 || res.code === 105){
        var msg = (typeof res.value === 'string' && res.value) ? res.value : '登录状态已失效，请重新登录';
        if (invalidHandler) invalidHandler();
        var e = new Error(msg); e.type = 'auth'; e.code = res.code; throw e;
      }
      var m = (typeof res.value === 'string' && res.value) ? res.value : ('业务处理失败（code ' + res.code + '）');
      var err = new Error(m); err.type = 'biz'; err.code = res.code; throw err;
    });
  }
  return {
    onInvalid: function(fn){ invalidHandler = fn; },
    getHeaders: headers,
    post: function(path, body){ return handleBiz(SDK.http.post(path, body || {}, { headers: headers() })); },
    get: function(path, params){ return handleBiz(SDK.http.get(path, params || {}, { headers: headers() })); }
  };
})();


/* assets/js/auth.js —— 由 index.html 内联脚本拆出（原行区间 3235-3357），内容未改动 */
/* =========================================================
   App.auth
   ========================================================= */
App.auth = (function(){
  var SDK = window.LuatSDK, C = App.config, S = App.storage;
  var M_PARAMS = ['m_token','m_salt','m_sid','m_name','m_phone','m_algorithm','m_encryptOutput','m_padding','m_publicKey','m_publicKeyEncoding'];
  var OAUTH_PARAMS = ['token','error','error_description','code','state'];
  function query(name){ try { return new URLSearchParams(window.location.search).get(name) || ''; } catch (e) { return ''; } }
  function hashQuery(name){
    try { var h = window.location.hash.replace(/^#/, ''); if (!h) return ''; return new URLSearchParams(h).get(name) || ''; } catch (e) { return ''; }
  }
  function cleanUrl(removeKeys){
    try {
      var url = new URL(window.location.href);
      removeKeys.forEach(function(k){ url.searchParams.delete(k); });
      var next = url.pathname + (url.search ? url.search : '') + (url.hash ? url.hash : '');
      window.history.replaceState(null, '', next);
    } catch (e) {}
  }
  function consumeInjection(){
    var p = {}, has = false;
    M_PARAMS.forEach(function(k){ var v = query(k); p[k] = v; if (v) has = true; });
    if (has) S.applyHostInjection(p);
    cleanUrl(M_PARAMS);
    return has;
  }
  function getAuthContext(){
    if (S.hasHostSession()){ var host = S.readHost(); if (S.isComplete(host)) { host.source = 'host'; return host; } return null; }
    var indep = S.readIndependent();
    if (S.isComplete(indep)) { indep.source = 'app'; return indep; }
    var host2 = S.readHost();
    if (S.isComplete(host2)) { host2.source = 'host'; return host2; }
    return null;
  }
  function isAuthenticated(){ return !!getAuthContext(); }
  function getProfile(){ var ctx = getAuthContext(); return ctx ? ctx.profile : { name: '', mobile: '' }; }
  function getAuthHeaders(){
    var ctx = getAuthContext();
    if (!ctx) return {};
    return { 'authorization': ctx.auth.token, 'salt': ctx.auth.salt, 'sid': ctx.service.sid };
  }
  function validateReturnTo(path){
    if (!path || typeof path !== 'string') return '';
    if (path.charAt(0) !== '/' || path.charAt(1) === '/') return '';
    if (/[\r\n\\]/.test(path)) return '';
    if (/^[a-z][a-z0-9+.-]*:/i.test(path)) return '';
    if (/\b(m_token|m_salt|m_sid|m_algorithm|m_encryptOutput|m_padding|m_publicKey|m_publicKeyEncoding|token)=/i.test(path)) return '';
    return path;
  }
  function defaultHome(){ return C.BASE_PATH + 'index.html'; }
  function currentReturnTo(){ var p = window.location.pathname; return (p.indexOf(C.BASE_PATH) === 0) ? (p + window.location.search) : p; }
  function buildLoginUrl(returnTo){
    var rt = validateReturnTo(returnTo || currentReturnTo()) || defaultHome();
    return C.BASE_HOST + C.BASE_PATH + 'login.html?returnTo=' + encodeURIComponent(rt);
  }
  function goToLogin(){ window.location.replace(buildLoginUrl(currentReturnTo())); }
  function requireAuth(){ if (!isAuthenticated()){ goToLogin(); return false; } return true; }
  function loginInvalid(){
    if (S.hasHostSession()){ S.clearHost(); return { mode: 'host', message: '登录状态已失效，请重新进入应用' }; }
    S.clearIndependent();
    var rt = validateReturnTo(currentReturnTo());
    S.setUi(Object.assign({}, S.getUi(), { returnTo: rt }));
    return { mode: 'app', message: '登录状态已失效，请重新登录', returnTo: rt };
  }
  function logout(){
    if (S.hasHostSession()){ S.clearHost(); return { mode: 'host', message: '已退出当前设备账号，请重新进入应用' }; }
    S.clearIndependent();
    var rt = validateReturnTo(currentReturnTo());
    S.setUi(Object.assign({}, S.getUi(), { returnTo: rt }));
    window.location.replace(buildLoginUrl(rt));
    return { mode: 'app' };
  }
  var pendingLogin = null;
  function readOAuthToken(){ var t = query('token') || hashQuery('token'); return t ? String(t) : ''; }
  function readOAuthError(){
    var e = query('error') || hashQuery('error'), d = query('error_description') || hashQuery('error_description');
    if (!e) return null;
    return { error: String(e), description: d ? String(d) : '' };
  }
  function startOAuth(returnTo){
    var rt = validateReturnTo(returnTo || query('returnTo') || defaultHome()) || defaultHome();
    var callback = C.BASE_HOST + C.BASE_PATH + 'login.html?returnTo=' + encodeURIComponent(rt);
    window.location.href = C.OAUTH_AUTHORIZE_URL + '?return_to=' + encodeURIComponent(callback);
  }
  function loginWithToken(token){
    if (pendingLogin) return pendingLogin;
    pendingLogin = SDK.http.post(C.OAUTH_LOGIN_URL + '?token=' + encodeURIComponent(token), undefined)
      .then(function(res){
        if (!res || res.code !== 0 || !res.value) throw new Error('授权登录失败');
        var v = res.value, auth = { token: '', salt: '' }, service = { sid: '' };
        if (v.auth) auth = { token: String(v.auth.token || ''), salt: String(v.auth.salt || '') };
        if (v.service) service = { sid: String(v.service.sid || '') };
        if (!auth.token || !auth.salt || !service.sid) throw new Error('授权信息不完整');
        if (S.hasHostSession()){ S.setHostSession(true); }
        else {
          var ok = S.saveLogin({ auth: auth, service: service, user: v.user || {}, tenant: v.tenant || null, sets: v.sets || null });
          if (!ok) throw new Error('登录状态保存失败');
        }
        return true;
      })
      .then(function(r){ pendingLogin = null; return r; }, function(e){ pendingLogin = null; throw e; });
    return pendingLogin;
  }
  function resolveReturnTo(){
    var safe = validateReturnTo(query('returnTo'));
    if (safe) return safe;
    safe = validateReturnTo(S.getUi().returnTo);
    return safe || defaultHome();
  }
  function goHome(){ window.location.replace(C.BASE_HOST + resolveReturnTo()); }
  return {
    consumeInjection: consumeInjection, cleanUrl: cleanUrl,
    getAuthContext: getAuthContext, isAuthenticated: isAuthenticated,
    getAuthHeaders: getAuthHeaders, getProfile: getProfile,
    validateReturnTo: validateReturnTo, defaultHome: defaultHome,
    currentReturnTo: currentReturnTo, buildLoginUrl: buildLoginUrl,
    goToLogin: goToLogin, requireAuth: requireAuth, loginInvalid: loginInvalid, logout: logout,
    readOAuthToken: readOAuthToken, readOAuthError: readOAuthError, startOAuth: startOAuth,
    loginWithToken: loginWithToken, resolveReturnTo: resolveReturnTo, goHome: goHome,
    query: query, hashQuery: hashQuery
  };
})();


/* assets/js/guards.js —— 由 index.html 内联脚本拆出（原行区间 3358-3368），内容未改动 */
/* =========================================================
   App.guards
   ========================================================= */
App.guards = {
  isProtected: function(){ return App.config.AUTH === 'required'; },
  guard: function(){
    if (App.guards.isProtected() && !App.auth.isAuthenticated()){ App.auth.goToLogin(); return false; }
    return true;
  }
};


/* assets/js/components.js —— 由 index.html 内联脚本拆出（原行区间 3369-3427 / 3428-3527 / 8467-8483），内容未改动 */

/* =========================================================
   工具
   ========================================================= */
function cssVar(name){
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}
function numOf(el){
  return parseFloat(String(el.textContent).replace(/[^\d.-]/g, '')) || 0;
}
/* KPI 数字滚动（系统设置里可关闭，关闭后直接落值） */
function rollNumber(el, to){
  if (!el) return;
  const from = numOf(el);
  if (from === to){ el.textContent = to.toLocaleString('en-US'); return; }
  if (window.nexusNoRoll){ el.textContent = to.toLocaleString('en-US'); return; }
  const dur = 700, t0 = performance.now();
  function step(t){
    const p = Math.min((t - t0) / dur, 1);
    const e = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(from + (to - from) * e).toLocaleString('en-US');
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

/* =========================================================
   1. 背景粒子星链（颜色随主题）
   —— 偏好存在 localStorage（与系统设置同一个键），并且本模块在**所有页面**都会读它，
      所以「关」现在是全站生效；出厂默认也是关（与 UI_DEF.bg 一致）。
   —— 开启时：限帧 30fps；去掉每颗粒子的发光模糊（shadowBlur 是这堆绘制里最贵的一项）；
      标签页切到后台立即停帧，切回来自动续上。
   ========================================================= */
(function(){
  const cvs = document.getElementById('bg');
  if (!cvs) return;
  const ctx = cvs.getContext('2d');
  const UI_KEY = 'nexus-ui';
  const FPS = 30;
  let W, H, dpr, parts = [], rafId = 0, lastT = 0, running = false;
  let palette = ['#22e1ff','#8b5cf6','#2bffb0','#4f8cff'];
  let linkRGB = '80,160,255';

  /* 读/写与系统设置同一份偏好（不依赖设置页是否加载过） */
  function prefOn(){
    try {
      const raw = localStorage.getItem(UI_KEY);
      if (raw) return !!JSON.parse(raw).bg;
    } catch (e){}
    return false;                    /* 出厂默认：关 */
  }
  function prefSave(on){
    try {
      const raw = localStorage.getItem(UI_KEY);
      const o = raw ? JSON.parse(raw) : {};
      o.bg = !!on;
      localStorage.setItem(UI_KEY, JSON.stringify(o));
    } catch (e){}
  }

  function readPalette(){
    palette = [cssVar('--particle-1'), cssVar('--particle-2'), cssVar('--particle-3'), cssVar('--particle-4')];
    linkRGB = cssVar('--particle-link') || '80,160,255';
    parts.forEach(p => { p.c = palette[p.ci]; });
  }

  function init(){
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = cvs.width = innerWidth * dpr;
    H = cvs.height = innerHeight * dpr;
    cvs.style.width = innerWidth + 'px';
    cvs.style.height = innerHeight + 'px';
    const count = Math.min(Math.floor(innerWidth / 26), 68);
    parts = [];
    for (let i = 0; i < count; i++){
      const ci = (Math.random() * palette.length) | 0;
      parts.push({
        x: Math.random() * W,
        y: Math.random() * H,
        vx: (Math.random() - .5) * .28 * dpr,
        vy: (Math.random() - .5) * .28 * dpr,
        r: (Math.random() * 1.5 + .6) * dpr,
        ci: ci,
        c: palette[ci],
        a: Math.random() * .5 + .25
      });
    }
  }

  function step(){
    ctx.clearRect(0, 0, W, H);
    const linkDist = 135 * dpr;

    for (let i = 0; i < parts.length; i++){
      const p = parts[i];
      p.x += p.vx; p.y += p.vy;
      if (p.x < 0 || p.x > W) p.vx *= -1;
      if (p.y < 0 || p.y > H) p.vy *= -1;
    }

    for (let i = 0; i < parts.length; i++){
      for (let j = i + 1; j < parts.length; j++){
        const a = parts[i], b = parts[j];
        const dx = a.x - b.x, dy = a.y - b.y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < linkDist){
          const alpha = (1 - d / linkDist) * .16;
          ctx.strokeStyle = 'rgba(' + linkRGB + ',' + alpha + ')';
          ctx.lineWidth = .7 * dpr;
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.stroke();
        }
      }
    }

    for (const p of parts){
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = p.c;
      ctx.globalAlpha = p.a;
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }

  /* 限帧：30fps 足够表现，绘制量减半。用时间戳判断，不依赖帧回调频率 */
  function frame(t){
    rafId = 0;
    if (!running) return;
    if (lastT && t - lastT < 1000 / FPS - 1){ rafId = requestAnimationFrame(frame); return; }
    lastT = t;
    step();
    rafId = requestAnimationFrame(frame);
  }
  function start(){
    if (running) return;
    running = true;
    window.nexusBgOff = false;      /* nexusBgOff 保留：老代码/开关用它判断当前是否关闭 */
    lastT = 0;
    if (!rafId) rafId = requestAnimationFrame(frame);
  }
  function stop(){
    running = false;
    window.nexusBgOff = true;
    if (rafId){ cancelAnimationFrame(rafId); rafId = 0; }
    ctx.clearRect(0, 0, W, H);
  }

  readPalette();
  init();
  window.nexusBgOff = !prefOn();
  if (prefOn()) start();

  addEventListener('resize', () => { init(); if (running) step(); });
  window.addEventListener('themechange', readPalette);

  /* 切到后台立即停帧，回到前台（且偏好为开）再续上 */
  document.addEventListener('visibilitychange', function(){
    if (document.hidden){
      if (running){ running = false; if (rafId){ cancelAnimationFrame(rafId); rafId = 0; } }
    } else if (prefOn() && !running){
      start();
    }
  });

  /* 供系统设置里的开关调用：写偏好 + 当前页立即生效（其它页下次加载生效） */
  window.nexusBgSet = function(on){
    prefSave(on);
    if (on) start(); else stop();
  };
})();

/* 数字滚动已并入 KPI 渲染（renderKpi），见第 6.2 节 */

/* =========================================================
   10. Toast
   ========================================================= */
const toastWrap = document.getElementById('toastWrap');
function toast(msg, isErr){
  const el = document.createElement('div');
  el.className = 'toast' + (isErr ? ' err' : '');
  el.textContent = msg;
  toastWrap.appendChild(el);
  setTimeout(() => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 420);
  }, isErr ? 3200 : 2200);
}
/* 仅用于失败提示：操作成功不弹任何提示 */
function toastErr(msg){ toast(msg, true); }


/* ==== 跨页共用（由 _deploy/fix-shared.js 移入）==== */

/* 量出单行高度（含下外边距）：行样式固定，探针量一次即可推算每页条数
   html 可以是字符串，也可以直接给一个已构建好的行元素（比如带 rich 样式的告警行），
   给元素时沿用它自己的类名，避免把行套进行里导致量出的高度翻倍 */
function probeRowHeight(box, className, html){
  const isEl = html && html.nodeType === 1;
  const probe = isEl ? html : document.createElement('div');
  if (!isEl){
    probe.className = className;
    probe.innerHTML = html;
  }
  probe.style.cssText = 'position:absolute;left:-9999px;top:0;width:100%;visibility:hidden;pointer-events:none';
  box.appendChild(probe);
  const h = probe.getBoundingClientRect().height +
            (parseFloat(getComputedStyle(probe).marginBottom) || 0);
  box.removeChild(probe);
  return h;
}

function bindSearch(inputId, clearId, onInput){
  const input = document.getElementById(inputId);
  if (!input) return;
  const box = input.closest('.list-search');
  const sync = () => box.classList.toggle('has-text', input.value.length > 0);

  input.addEventListener('input', () => {
    onInput(input.value);
    sync();
  });
  const clear = document.getElementById(clearId);
  if (clear) clear.addEventListener('click', () => {
    onInput('');
    input.value = '';
    sync();
    input.focus();
  });
}

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

/* assets/js/shell.js —— 由 index.html 内联脚本拆出（原行区间 8496-8660 / 8984-9318），内容未改动 */
/* =========================================================
   12. 多页面导航 + 本页渲染登记
   —— 每个菜单现在是独立 HTML：侧栏项就是普通 <a>（地址在生成页面时写死），
      不再有 SPA 的「视图切换 / 面板摘除挂载」。
   —— 页面之间不共享内存，所以：
        · 当前页名由 <body data-page-name> 提供，等价于原来的 window.nexusCurrentView
        · 各页把自己的重绘函数登记到渲染表（registerPageRenderer），
          shell 的 renderAllViews 只跑本页登记过的，不会去调用别的页面才有的函数
   ========================================================= */
(function(){
  const pageName = document.body.getAttribute('data-page-name') || '';
  window.nexusCurrentView = pageName;

  /* 侧栏高亮（静态 href 已写好，这里只按页名兜底同步一次） */
  document.querySelectorAll('.nav-item').forEach(function(item){
    item.classList.toggle('active', item.dataset.tip === pageName);
  });

  /* 本页渲染表 */
  const renderers = [];
  window.registerPageRenderer = function(fn){
    if (typeof fn === 'function' && renderers.indexOf(fn) === -1) renderers.push(fn);
  };
  window.runPageRenderers = function(){
    const data = (typeof curData === 'function') ? curData() : null;
    renderers.forEach(function(fn){
      try { fn(data); }
      catch (e){ console.error('[页面渲染] 失败：', e); }
    });
  };

  /* 页面参数处理表（?dev= / ?tab= ...），数据就绪后由 shell 统一触发 */
  const queryHandlers = [];
  window.onPageQuery = function(fn){ if (typeof fn === 'function') queryHandlers.push(fn); };
  window.runPageQuery = function(){
    /* 缓存优先时数据可能被拉两次（缓存一次、接口一次），页面参数只执行一次即可 */
    if (window.__pageQueryDone) return;
    window.__pageQueryDone = 1;
    let q = {};
    try { q = Object.fromEntries(new URLSearchParams(location.search)); } catch (e) { q = {}; }
    queryHandlers.forEach(function(fn){
      try { fn(q); } catch (e){ console.error('[页面参数] 失败：', e); }
    });
  };

  /* 页面间跳转：目标地址按当前页所在层级计算（根目录 / pages） */
  const IN_PAGES = location.pathname.indexOf('/pages/') > -1;
  const URL_MAP = IN_PAGES
    ? { overview:'../index.html', devices:'devices.html', alerts:'alerts.html', map:'map.html', topo:'topo.html', settings:'settings.html' }
    : { overview:'index.html', devices:'pages/devices.html', alerts:'pages/alerts.html', map:'pages/map.html', topo:'pages/topo.html', settings:'pages/settings.html' };
  const NAME_KEY = { '运营总览':'overview', '设备管理':'devices', '告警中心':'alerts', '位置地图':'map', '网络拓扑':'topo', '系统设置':'settings' };

  function pageUrl(key, params){
    const base = URL_MAP[key];
    if (!base) return null;
    const q = Object.keys(params || {}).map(function(k){
      return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
    }).join('&');
    /* 跳转带上版本参数（见 renderPublishFoot 的说明）：
       平台对 HTML 只回 ETag/Last-Modified、没有 Cache-Control，浏览器会按启发式缓存
       直接把旧 HTML 拿出来用；带上版本号后每次发布 URL 都变，因此总能拿到最新页面。*/
    const ver = window.__pageVer ? ((q ? '&' : '?') + 'v=' + encodeURIComponent(window.__pageVer)) : '';
    return base + (q ? ('?' + q) : '') + ver;
  }
  const nav = {
    url: pageUrl,
    to: function(key, params){ const u = pageUrl(key, params); if (u) location.href = u; },
    /* 兼容旧写法：nexusGoToView('设备管理') */
    goToView: function(name){ nav.to(NAME_KEY[name], null); }
  };
  window.App = window.App || {};
  window.App.nav = nav;
  window.nexusGoToView = nav.goToView;
})();

/* =========================================================
   13. 主题管理
   ========================================================= */
(function(){
  const THEMES = ['nebula','aurora','dawn','mist'];
  const root = document.documentElement;

  function applyTheme(name){
    if (!THEMES.includes(name)){
      toastErr('主题切换失败：不支持的配色方案「' + name + '」');
      return false;
    }
    root.dataset.theme = name;
    try {
      localStorage.setItem('nexus-theme', name);
    } catch(e){
      toastErr('主题偏好保存失败，本次切换仅在当前会话生效');
    }
    document.querySelectorAll('.theme-opt').forEach(o => {
      o.classList.toggle('active', o.dataset.theme === name);
    });
    // 延迟一帧，让 CSS 变量生效后再通知图表
    requestAnimationFrame(() => {
      window.dispatchEvent(new Event('themechange'));
    });
    return true;
  }

  // 初始化（历史残留的无效主题静默回退，不打扰用户）
  let saved = 'nebula';
  try { saved = localStorage.getItem('nexus-theme') || 'nebula'; } catch(e){}
  if (!THEMES.includes(saved)) saved = 'nebula';
  applyTheme(saved);

  // 绑定主题选项（事件委托，面板在视图切换时会被摘除/挂载）
  document.addEventListener('click', e => {
    const opt = e.target.closest('.theme-opt');
    if (!opt) return;
    // 切换成功不提示；失败由 applyTheme 内部给出原因
    applyTheme(opt.dataset.theme);
  });
})();

/* =========================================================
   14. 账号：用户菜单 / 退出登录
   —— 认证统一走 login.html（合宙 OAuth），此处不再有演示账号与内置登录表单
   ========================================================= */
const avatarBtn  = document.getElementById('avatarBtn');
const userPop    = document.getElementById('userPop');
const logoutMask = document.getElementById('logoutMask');

function closeUserPop(){ userPop.classList.remove('show'); }
function openUserPop(){
  userPop.classList.add('show');
  if (typeof closeProjPop === 'function') closeProjPop();
}
function openLogoutConfirm(){ logoutMask.classList.add('show'); }
function closeLogoutConfirm(){ logoutMask.classList.remove('show'); }

avatarBtn.addEventListener('click', e => {
  e.stopPropagation();
  if (userPop.classList.contains('show')) closeUserPop();
  else openUserPop();
});
document.addEventListener('click', e => {
  if (!userPop.contains(e.target) && !avatarBtn.contains(e.target)) closeUserPop();
});
document.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  closeUserPop();
  closeLogoutConfirm();
});

document.getElementById('logoutBtn').addEventListener('click', () => {
  closeUserPop();
  openLogoutConfirm();
});
document.getElementById('logoutCancel').addEventListener('click', closeLogoutConfirm);
logoutMask.addEventListener('click', e => {
  if (e.target === logoutMask) closeLogoutConfirm();
});

function doLogout(){
  closeLogoutConfirm();
  closeUserPop();
  if (typeof closeDeviceView === 'function') closeDeviceView();
  const r = App.auth.logout();
  if (r && r.mode === 'host'){ toastErr(r.message); }
}
document.getElementById('logoutConfirm').addEventListener('click', doLogout);


/* 顶栏用户信息（来自 OAuth 登录态） */
(function fillUser(){
  const p = App.auth.getProfile();
  const uname = p.name || '合宙用户';
  const ua = document.getElementById('userName'); if (ua) ua.textContent = uname;
  const um = document.getElementById('userMobile'); if (um) um.textContent = p.mobile ? App.utils.maskMobile(p.mobile) : '';
  /* 顶栏显示**完整账户名**：原来只放首字（如「朱」），看不出是哪位的账号。
     加 has-name 后由 CSS 把圆形改成自适应胶囊。 */
  const av = document.getElementById('avatarBtn');
  if (av){
    av.textContent = uname;
    av.title = '账号：' + uname;
    av.classList.add('has-name');
  }
  /* 下拉卡片左侧那个「运」是页面模板里写死的占位字符（运行时从未被更新过，故与账号无关），
     按需求直接去掉；卡片里已有完整账户名与手机号，不再需要这个字母块。 */
  const uab = document.querySelector('#userPop .ua');
  if (uab) uab.remove();
})();

/* =========================================================
   16. 项目切换器
   ========================================================= */
const projBtn = document.getElementById('projBtn');
const projPop = document.getElementById('projPop');

function closeProjPop(){
  projPop.classList.remove('show');
  projBtn.classList.remove('open');
}

function toggleProjPop(){
  const open = projPop.classList.toggle('show');
  projBtn.classList.toggle('open', open);
  if (!open) return;
  /* 打开菜单即渲染已有列表（即时可见），同时重新请求账号下全部项目，
     并逐个项目补齐真实设备总数，取到一个就刷新一次 */
  renderProjList();
  refreshProjects();
}

function renderProjList(){
  const list = document.getElementById('projList');
  if (!list) return;
  list.innerHTML = '';

  /* 头部：账号下项目总数 + 刷新状态（数量来自 list_my_projects 的真实返回） */
  const head = document.createElement('div');
  head.style.cssText = 'padding:7px 12px 6px;font-size:12px;color:var(--muted);letter-spacing:.3px;' +
                       'border-bottom:1px solid var(--line)';
  head.innerHTML = '账号下共 <b style="color:var(--text)">' + PROJECTS.length + '</b> 个项目' +
                   (projRefreshing ? ' · 正在刷新…' : '');
  list.appendChild(head);

  if (!PROJECTS.length){
    const empty = document.createElement('div');
    empty.style.cssText = 'padding:12px;font-size:12px;color:var(--muted)';
    empty.textContent = '未获取到项目';
    list.appendChild(empty);
    return;
  }

  /* 账号下全部项目逐个渲染，不做任何条数裁剪 */
  PROJECTS.forEach(p => {
    const item = document.createElement('div');
    item.className = 'proj-item' + (p.id === state.projectId ? ' active' : '');

    /* 每个项目只显示名称：原先右侧还有一列「型号 · N 台」，按需求整列删除。
       型号 / 设备台数 / 创建时间仍保留在 item.title 悬停提示里，需要时鼠标停一下即可。 */
    item.innerHTML =
      '<span class="pi-name">' + p.name + '</span>' +
      '<span class="pi-check">✓</span>';
    item.title = 'project_key: ' + p.code +
                 (p.info ? '\n' + p.info : '') +
                 (p.ctime ? '\n创建时间: ' + p.ctime : '') +
                 (p.counted ? '\n设备总数: ' + p.total : '');
    item.addEventListener('click', () => {
      closeProjPop();
      if (p.id === state.projectId) return;
      applyProject(p.id);
    });
    list.appendChild(item);
  });
}

projBtn.addEventListener('click', e => {
  e.stopPropagation();
  toggleProjPop();
});
document.addEventListener('click', e => {
  if (!projPop.contains(e.target) && !projBtn.contains(e.target)) closeProjPop();
});
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeProjPop();
});

/* =========================================================
   17. 项目切换（重新渲染与该项目相关的全部视图）
   ========================================================= */
/* ---------- 由 project_key 派生稳定种子 ---------- */
function hashSeed(s){
  let h = 0;
  s = String(s || '');
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h % 100003;
}

/* 重绘当前项目相关的全部面板
   —— 多页面：各页只登记自己的重绘函数（见 12 节 registerPageRenderer），
      这里不再直接调用任何具体页面函数，否则会引用到别的页面上才存在的实现 */
function renderAllViews(){
  renderProjList();                 /* 顶栏项目列表：所有页面都有 */
  if (typeof runPageRenderers === 'function') runPageRenderers();
  requestAnimationFrame(() => window.dispatchEvent(new Event('resize')));
}
/* 合并高频重绘（逐台补 Tag 时会多次触发） */
let renderTimer = null;
function scheduleRender(){
  if (renderTimer) return;
  renderTimer = setTimeout(function(){
    renderTimer = null;
    renderAllViews();
    /* 真实数据变化后同步腾讯地图标注（视图未挂载时内部自动跳过） */
    if (typeof TMapEngine !== 'undefined') TMapEngine.sync();
    /* 自绘覆盖层（聚合气泡/ID标签/浮卡/比例尺）也跟着重绘 */
    if (typeof TMapOverlay !== 'undefined') TMapOverlay.refresh();
  }, 300);
}
/* 视图切换会派发 resize：此时地图容器才真正可见且有尺寸，需要重新量取并同步 */
window.addEventListener('resize', function(){
  if (typeof TMapEngine !== 'undefined') TMapEngine.sync();
  if (typeof TMapOverlay !== 'undefined') TMapOverlay.refresh();
});

/* =========================================================
   账号下全部项目的真实设备总数
   —— 对每个项目调用 /open_api/search_my_devices（page=1 size=1）只取 total
   —— 串行 + 间�隔 150ms，避免一次性并发把平台接口打爆
   —— 每取到一个就重绘，数字逐个落位（不是等全部完成才显示）
   ========================================================= */
let projCountSeq = 0;
let projCountRunning = false;
/* force=true：整轮重取（刷新项目列表后）；force=false：只补还没统计到的项目 */
function fetchProjectCounts(force){
  if (projCountRunning && !force) return;
  projCountRunning = true;
  const seq = ++projCountSeq;
  let i = 0;
  function next(){
    if (seq !== projCountSeq){ projCountRunning = false; return; }
    if (!force) while (i < PROJECTS.length && PROJECTS[i].counted) i++;
    if (i >= PROJECTS.length){ projCountRunning = false; return; }
    const p = PROJECTS[i++];
    apiDevices(p.code, 1, 1, '').then(function(res){
      const v = (res && res.value) || {};
      p.total = Number(v.total || 0);
      p.counted = true;
      if (seq !== projCountSeq) return;
      renderProjList();
    }, function(){ p.counted = true; }).then(function(){
      setTimeout(next, 150);
    });
  }
  next();
}

/* 打开项目菜单时重新请求一次账号下的全部项目（不依赖缓存/页面初始化时的那一次） */
let projRefreshing = false;
function refreshProjects(){
  if (projRefreshing) return Promise.resolve();
  projRefreshing = true;
  const seq = ++projCountSeq;                 /* 作废上一轮还在跑的计数任务 */
  return apiProjects().then(function(res){
    const list = Array.isArray(res.value) ? res.value : [];
    const prevTotal = {};
    PROJECTS.forEach(function(x){ prevTotal[x.id] = x; });
    PROJECTS = list.map(function(p){
      const old = prevTotal[p.project_key];
      return {
        id: p.project_key,
        short: (p.name || '').slice(0, 2),
        code: p.project_key,
        name: p.name || '未命名项目',
        model: p.model || '',
        info: p.info || '',
        ctime: p.ctime || '',
        keyId: p.key_id || '',
        region: p.info || '',
        net: 0,
        total: old ? old.total : 0,
        counted: old ? !!old.counted : false,
        offline: 0, warn: 0,
        seed: hashSeed(p.project_key)
      };
    });
    renderProjList();
  }).catch(function(e){
    toastErr('项目列表刷新失败：' + ((e && e.message) ? e.message : ''));
  }).then(function(){
    projRefreshing = false;
    /* 项目列表刚刷新过：整轮重取设备数，保证数字是最新的 */
    if (seq === projCountSeq) fetchProjectCounts(true);
  });
}

/* ---------- 项目选择：首屏落地 / 用户切换 ----------
   多页面结构下，切换项目 = 记住选择 + 重新加载当前页（各页用新项目重新初始化），
   这样不必再手工清空「别的页面」的内存态（设备、告警、7 天态势缓存等）。 */
function setCurrentProject(prj){
  if (!prj) return;
  state.projectId = prj.id;
  state.projectName = prj.name;
  try { localStorage.setItem(STORE_KEY, prj.id); } catch(e){}
  const el = document.getElementById('projCurName');
  if (el) el.textContent = prj.name;
}

/* 用户主动切换项目（来自顶栏项目菜单） */
function applyProject(id){
  if (id === state.projectId) return;
  const prj = PROJECTS.find(p => p.id === id);
  if (!prj){ toastErr('项目切换失败：项目不存在'); return; }
  setCurrentProject(prj);
  location.reload();
}

/* 拉取项目列表（/open_api/list_my_projects）
   —— 同样缓存优先：命中就先渲染顶栏项目名与项目菜单，避免白等一次接口往返 */
/* 顶栏「设备列表已更新 · 年月日时分秒」提示已按需求整体删除：
   —— 该提示只代表设备列表（search_my_devices）那一次加载，容易被误读成"整页数据时间"，
      与实时值 / 历史曲线 / 位置各自独立的刷新口径也不一致，故不再展示。
   —— 原先的 setSyncHint() 函数、.sync-hint 样式与其两处调用（api.js 的缓存铺屏分支、
      本文件的设备列表加载成功分支）一并移除，避免留下死代码。
   —— 数据仍照旧：缓存优先铺屏 + 接口结果到达后差异更新，只是不再用顶栏文案提示时刻。 */

function loadProjects(){
  try {
    const c = cacheGet('projects', null);
    /* 项目列表缓存：过期也用（上限 6 小时，与设备缓存一致）——先拿它把顶栏画出来，
       并**立刻**用缓存里的项目启动设备数据加载，不必等 list_my_projects 回来。
       这一步省下的是整条接口链最前端的那 340–750ms（C：砍串行） */
    if (c && (Date.now() - c.at) < CACHE_STALE_MAX && Array.isArray(c.list) && c.list.length && !PROJECTS.length){
      PROJECTS = c.list.slice();
      renderProjList();
      const p0 = curProject();
      if (p0){
        setCurrentProject(p0);
        /* 关键：不等项目接口返回，立刻用会话缓存把本页数据铺出来（切页几乎瞬开） */
        loadProjectData(p0).then(function(){ if (typeof runPageQuery === 'function') runPageQuery(); });
      }
    }
  } catch (e){}
  return apiProjects().then(function(res){
    const list = Array.isArray(res.value) ? res.value : [];
    /* 保留上一轮已取到的设备总数，避免刷新菜单时数字闪回 0 */
    const prevTotal = {};
    PROJECTS.forEach(function(x){ prevTotal[x.id] = x; });
    PROJECTS = list.map(function(p){
      const old = prevTotal[p.project_key];
      return {
        id: p.project_key,
        short: (p.name || '').slice(0, 2),
        code: p.project_key,
        name: p.name || '未命名项目',
        /* list_my_projects 返回的真实项目信息，全部保留并展示 */
        model: p.model || '',
        info: p.info || '',
        ctime: p.ctime || '',
        keyId: p.key_id || '',
        region: p.info || '',
        net: 0,
        total: old ? old.total : 0,
        counted: old ? !!old.counted : false,
        offline: 0, warn: 0,
        seed: hashSeed(p.project_key)
      };
    });
    renderProjList();
    cacheSet('projects', null, { list: PROJECTS });   /* 落缓存：下次进其它页先渲染顶栏 */
    const prj = curProject();
    if (!prj){
      const el = document.getElementById('projCurName');
      if (el) el.textContent = '暂无项目';
      renderAllViews();
      return;
    }
    /* 首屏：先把当前项目落地（不重载），再拉真实数据；
       页面参数（?dev= / ?tab=）等数据就绪后再执行 */
    setCurrentProject(prj);
    renderAllViews();
    loadProjectData(prj).then(function(){
      if (typeof runPageQuery === 'function') runPageQuery();
    });
  }).catch(function(e){
    toastErr('项目加载失败：' + e.message);
    const el = document.getElementById('projCurName');
    if (el) el.textContent = '加载失败';
  });
}

/* 加载项目的真实设备列表（/open_api/search_my_devices，按 pages 全量取完，不再只取第一页）
   —— 缓存优先：切页回来时先用 sessionStorage 里的「设备清单 + 实时值」把界面铺出来（几乎瞬开），
      再用接口结果做差异更新；过期的实时值由 queueTags 按 tagAt（65s）自动补拉。 */
/* 同一项目短时间内被调用两次（缓存优先一次 + 接口返回一次）时只跑一次，避免重复请求 */
let lastDataLoad = { id: '', at: 0 };
function loadProjectData(prj){
  const now0 = Date.now();
  /* 同一项目短时间内重复调用只跑一次：缓存优先那次 + 项目接口返回那次
     （项目接口有时要 1s 以上，窗口给到 10s 才不至于重复拉一遍设备清单） */
  if (lastDataLoad.id === prj.id && (now0 - lastDataLoad.at) < 10000) return Promise.resolve();
  lastDataLoad = { id: prj.id, at: now0 };

  /* 1) 缓存命中就先渲染一次：设备列表 / 地图点位 / 告警立即可见 */
  let painted = false;
  try { painted = hydrateProjectFromCache(prj); }
  catch (e){ console.error('[cache] 读取缓存失败：', e); }
  if (painted){
    try { renderAllViews(); }
    catch (e){ console.error('[render] 渲染异常：', e); }
  }

  /* 2) 接口结果到达后做差异更新：
        保留已拉取（或来自缓存）的实时值 / 位置 / 设备信息，
        否则每次刷新都会把界面清空，还要再等限频闸门重新拉一遍 */
  return apiAllDevices(prj.code).then(function(list){
    const data = projectData(prj);
    data.project = prj;
    const prev = {};
    (data.devices || []).forEach(function(d){ prev[d.id] = d; });
    data.devices = list.map(function(r){
      const nd = deviceFromRecord(r.id, null, null);
      const old = prev[r.id];
      if (old) CACHE_DEV_FIELDS.forEach(function(k){ if (old[k] !== undefined) nd[k] = old[k]; });
      return nd;
    });
    data.loaded = true;
    prj.total = list.length;
    /* 先发起真实数据拉取，再渲染：渲染异常绝不能再阻断数据加载 */
    queueTags(list.map(function(r){ return r.id; }));
    try { renderAllViews(); } catch (err) { console.error('[render] 渲染异常：', err); }
    scheduleCacheFlush();          /* 台账变化同样落进缓存 */
    /* 顶栏「设备列表已更新 …」提示已按需求删除，此处不再写提示 */
  }).catch(function(e){
    toastErr('设备加载失败：' + e.message);
  });
}


/* =========================================================
   侧栏底部：发布时间
   —— 时间来自打包时注入的 window.__buildTime（同一次发布六个页面一致），
      既能满足展示需求，出问题时也能据此判断用户跑的是哪一版。
   —— 窄屏（侧栏变横向）时由 CSS 隐藏，避免挤坏布局。
   ========================================================= */
(function renderPublishFoot(){
  const side = document.querySelector('.sidebar');
  if (!side || document.getElementById('sidePublish')) return;
  const el = document.createElement('div');
  el.id = 'sidePublish';
  el.className = 'side-publish';
  el.textContent = '发布于：' + (window.__buildTime || '--');
  el.title = '本页面发布时间（每次发布自动更新）· 构建号 ' + (window.__build || '--');
  side.appendChild(el);

  /* 一、时间与跳转都以「当前部署」为准（不能信页面自己的缓存版本）：
     —— 平台对 HTML 只回 ETag / Last-Modified，没有 Cache-Control，浏览器按启发式缓存把旧
        HTML 直接拿来用：于是出现过「各菜单发布时间不一致」、「必须逐页强刷才更新」；
     —— 这里读一次打包产物里的 version.json（带时间戳绕开缓存），拿到全站最新构建时间；
     —— 同时把这个版本号当作跳转参数：菜单链接统一带 ?v=…，每次发布 URL 都变，因此点任何
        一个菜单都会拿到最新 HTML，不必逐页强刷（首次仍需刷一次，见下方注释）。 */
  function versionToken(){
    /* 纯数字的版本号（如 20260921210951）：先取页面注入的构建时间，退而用构建号 */
    const t = String(window.__buildTime || '').replace(/\D/g, '');
    return t || String(window.__build || '').replace(/\D/g, '');
  }
  function applyVersion(token){
    if (!token) return;
    window.__pageVer = token;                 /* pageUrl() 给程序化跳转（App.nav.to）带上它 */
    document.querySelectorAll('.nav-item[href]').forEach(function(a){
      /* 记住原始地址：版本号变化时要能重新拼接（不能只追加一次，否则拿不到服务器最新版本） */
      const raw = a.getAttribute('data-raw-href') || a.getAttribute('href');
      if (!raw) return;
      a.setAttribute('data-raw-href', raw);
      const bare = raw.replace(/([?&])v=[^&]*/g, '$1').replace(/[?&]$/, '');
      a.setAttribute('href', bare + (bare.indexOf('?') > -1 ? '&' : '?') + 'v=' + encodeURIComponent(token));
    });
  }
  /* 先用页面注入的构建号兜底，保证「点菜单」这一步从第一次起就已经绕开缓存 */
  applyVersion(versionToken());

  try {
    let url = null;
    const tag = document.querySelector('script[src*="assets/bundle/"]');
    if (tag && tag.src) url = tag.src.replace(/[?#].*$/, '').replace(/[^/]*$/, 'version.json');
    else {
      const base = (App.config && App.config.BASE_PATH) || '';
      if (base) url = base.replace(/\/?$/, '/') + 'assets/bundle/version.json';
    }
    if (url) {
      fetch(url + '?t=' + Date.now(), { cache: 'no-store' })
        .then(function(r){ return r && r.ok ? r.json() : null; })
        .then(function(v){
          if (!v || !v.buildTime) return;
          /* 以服务器上的版本为准：页脚时间 + 后续跳转参数都用它 */
          applyVersion(String(v.buildTime).replace(/\D/g, ''));
          if (v.buildTime === window.__buildTime) return;
          window.__buildTime = v.buildTime;
          if (v.build) window.__build = v.build;
          el.textContent = '发布于：' + v.buildTime;
          el.title = '全站发布时间（最近一次发布）· 构建号 ' + (v.build || '--');
        })
        .catch(function(){ /* 静默失败：保留注入值 */ });
    }
  } catch (e) { /* 任何异常都不该影响页脚显示 */ }
})();

/* locHash() 已移到公共层（多页面下别的页面也要用） */


/* ---------- 左栏条目：状态点与占比条 ----------
   g.online / g.warn / g.offline 就是三种展示组合：
   在线·无告警 / 在线·告警 / 离线·失联 */

/* ---------- 坐标来源：设备真实经纬度（AirCloud Tag 512 经度 / 513 纬度，基站定位 LBS） ---------- */
/* 仅当设备上报了有效经纬度才落点；无坐标的设备不虚构位置（地图上不显示点位） */
/* ---------- 浮卡行构建：TMapOverlay（8.2c）的浮卡复用这两个小工具 ---------- */
/* ---------- 选中设备浮卡 ---------- */
function locMiniRow(label, text, pct, color){
  return '<div class="loc-row"><span>' + label + '</span>' +
    '<i class="loc-mini"><i style="width:' + Math.max(2, Math.min(100, pct)) + '%;background:' + color + '"></i></i>' +
    '<b>' + text + '</b></div>';
}
function locPlainRow(label, val, color, title){
  /* loc-plain：纯文本行（没有占比条）。值可能很长（典型是「安装位置」的地址），
     CSS 对这一类放行自动换行，避免一行放不下被裁掉。 */
  return '<div class="loc-row loc-plain"' + (title ? ' title="' + title + '"' : '') + '><span>' + label + '</span>' +
    '<b' + (color ? ' style="color:' + color + '"' : '') + '>' + val + '</b></div>';
}

/* =========================================================
   8.2 位置地图面板入口
   —— 底图与点位现由腾讯地图 GL（8.2b TMapEngine）+ 自绘覆盖层（8.2c TMapOverlay）负责，
      模板自带的自绘瓦片引擎（瓦片池 / 世界层 / 自绘标记与自绘交互）已整体退役。
      本函数只判断「面板是否在本页」，再把最新数据推给上面两个模块。
      keep=true（主题切换 / 定时刷新）表示保留选中与视野。
   ========================================================= */
function buildLocationMap(data, keep){
  if (!document.getElementById('panel-location')) return;   /* 面板不在本页 */
  if (typeof TMapEngine !== 'undefined') TMapEngine.sync();
  if (typeof TMapOverlay !== 'undefined') TMapOverlay.refresh();
}
/* =========================================================
   8.2b 位置地图引擎：腾讯位置服务 JavaScript API GL
   —— 按 AirCloud 资源包《腾讯地图.md》实现：
      · SDK 由 HTML 头部加载（Key 写死在加载地址，不做输入项、不向用户索要）
      · 地图初始化要求容器已在 DOM 且尺寸可计算，重复使用先销毁旧实例
      · 标注使用官方组件（MultiCircleMarker 画点 + InfoWindow 信息窗体），
        坐标全部来自设备真实上报（latest_location / Tag 512,513），不编造
      · 定位必须由用户主动点击触发，且区分权限拒绝/不支持/超时/失败
      · SDK 不可用或鉴权失败统一降级为「地图组件加载失败，请检查网络后重试」
   ========================================================= */
window.__tmapEngine = true;      /* 通知模板自研引擎不再接管地图交互 */

/* =========================================================
   地图定位基准与坐标有效性（腾讯地图口径，GCJ-02）
   ========================================================= */
/* 园区兜底定位点：上海市浦东新区康桥镇浦三路3801号（秀沿路100号）城置广场。
   —— 设备拿不到经纬度时用它，避免视野落到 (0,0)（几内亚湾）。
   —— 坐标取自平台对该地址的实际上报值（GCJ-02，与腾讯地图同一坐标系；
      同址 WGS-84 约为 121.544305 / 31.134473）。换园区只改这一行。 */
const FALLBACK_CENTER = { lng: 121.54858067926361, lat: 31.1322844858936, zoom: 16 };
/* 点到设备图标时放大到的等级（腾讯 GL 矢量底图最大 20 级，超范围引擎会自动收敛） */
const MAX_FOCUS_ZOOM = 20;

/* 坐标是否可用：空值 / 非数字 / 0 一律视为"拿不到经纬度"
   —— 0,0 是平台对"无定位"的常见回填值，直接用会把点位画到几内亚湾 */
function hasPos(d){
  if (!d) return false;
  const lng = Number(d.lng), lat = Number(d.lat);
  if (!isFinite(lng) || !isFinite(lat)) return false;
  return lng !== 0 && lat !== 0;
}
/* 把视野移到园区兜底点（一台设备的可用坐标都没有时） */
function centerFallback(map){
  if (!map) return;
  try {
    map.setCenter(new TMap.LatLng(FALLBACK_CENTER.lat, FALLBACK_CENTER.lng));
    map.setZoom(FALLBACK_CENTER.zoom);
  } catch (e){}
}

/* 取设备用于绘制的坐标：没有实测坐标（空 / 0,0 / 非数字）的设备统一落到园区默认位置，
   保证它们在地图上看得见；fixed 标记会一路传到界面，注明"这是默认位置、不是实测定位" */
function posOf(d){
  if (hasPos(d)) return { lng: Number(d.lng), lat: Number(d.lat), fixed: false };
  return { lng: FALLBACK_CENTER.lng, lat: FALLBACK_CENTER.lat, fixed: true };
}


const TMapEngine = (function(){
  let box = null, map = null, marks = null, win = null, ready = false;
  let lastSig = '', tries = 0;
  let viewedOnce = false;      /* 默认视野是否已框过（首次拿到数据后置位） */
  let fitSig = '';             /* 最近一次框选时的"设备坐标签名" */
  let userMoved = false;       /* 用户是否自己动过地图（动过就再也不自动改视野） */
  let filter = 'all', keyword = '';

  /* 底图类型：腾讯 GL 的默认路网是 'vector'，不是 'roadmap'
     —— 传 {type:'roadmap'} 接口不报错、getBaseMap() 也返回 roadmap，
        但画布会渲染成一片空白（线上实测：截图从 1MB 级掉到 30KB 级）,
        这就是「切到卫星再切回路网，地图不显示」的根因。
     所以：进入卫星前先把当前底图配置记下来（baseHome），切回路网时原样还原；
     万一取不到就退回 ROAD_BASE。 */
  const ROAD_BASE = { type: 'vector' };
  let baseHome = null, baseIsSat = false;

  /* 点位图标：内联 SVG（状态色与模板一致），避免引入外部图片资源 */
  function dot(bg){
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34">' +
      '<circle cx="17" cy="17" r="13" fill="' + bg + '" fill-opacity="0.26"/>' +
      '<circle cx="17" cy="17" r="7" fill="' + bg + '" stroke="#0b1220" stroke-width="2.5"/></svg>';
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  }
  /* 点位样式：腾讯要求必须是 TMap.MarkerStyle 实例，传普通对象会报
     「MultiMarker.styles: 样式id ok 希望传入MarkerStyle实例，实际传入：Object」；
     而腾讯脚本可能晚于本脚本就绪，因此推迟到建图时（TMap 已存在）再构造，
     真取不到就退回普通对象。 */
  let STYLES = null;
  function markerStyles(){
    if (STYLES) return STYLES;
    function mk(bg){
      const cfg = { width:34, height:34, anchor:{ x:17, y:17 }, src: dot(bg) };
      return (window.TMap && TMap.MarkerStyle) ? new TMap.MarkerStyle(cfg) : cfg;
    }
    STYLES = { ok: mk('#2bffb0'), alarm: mk('#ffb648'), off: mk('#ff4d6d') };
    return STYLES;
  }
  const DEGRADE = '地图组件加载失败，请检查网络后重试';

  /* =======================================================
     地图状态机（资源包「UI 状态 / 状态机」要求的统一状态）
       idle → loading-map → map-ready
                          ↘ map-error（统一降级文案 + 重新加载入口）
       locating → locate-success / locate-denied / locate-error / locate-unsupported
     只用一个状态变量驱动界面，不用一堆互相冲突的 boolean
     ======================================================= */
  let STATE = 'idle';
  let authWatch = null, consolePatched = false, readyChecked = false;

  function stateOf(){ return STATE; }

  function stateUI(){
    const h = host();
    if (!h) return null;
    let el = h.querySelector('.tmap-state');
    if (!el){
      el = document.createElement('div');
      el.className = 'tmap-state';
      el.style.cssText = 'position:absolute;inset:0;z-index:8;display:grid;place-items:center;text-align:center;' +
        'padding:20px;background:color-mix(in srgb,var(--bg) 74%,transparent)';
      h.appendChild(el);
    }
    return el;
  }
  function hideStateUI(){
    const h = host();
    const el = h ? h.querySelector('.tmap-state') : null;
    if (el) el.remove();
  }

  /* 地图就绪 / 降级 时切换面板模式（见 CSS .lm2.tmap-active）：
     就绪 → 缩放/罗盘/比例尺交给腾讯自带控件，我们重复的 ＋ − 与自算比例尺让位，
            只留腾讯没有的「回到园区」「定位到当前位置」两个业务按钮；
     降级 → 腾讯控件根本不存在，我们的 ＋ − 与比例尺必须留着，否则没法缩放 */
  function setTmapActive(on){
    const stage = document.querySelector('#panel-location .lm2');
    if (stage) stage.classList.toggle('tmap-active', !!on);
  }

  function setState(s){
    if (STATE === s) return;
    STATE = s;
    if (s === 'map-ready'){ hideStateUI(); setTmapActive(true); return; }
    if (s === 'locating'){ toast('正在定位…'); return; }
    if (s === 'locate-success'){ toast('已定位到当前位置'); return; }
    if (s === 'locate-denied'){ toastErr('定位权限未开启，请允许本页面使用定位后重试'); return; }
    if (s === 'locate-error'){ toastErr('暂时无法获取您的位置，请稍后重试'); return; }
    if (s === 'locate-unsupported'){ toastErr('当前浏览器暂不支持定位，可在地图上手动查看位置'); return; }

    const el = stateUI();
    if (!el) return;
    if (s === 'loading-map'){
      el.style.display = 'grid';
      el.innerHTML = '<div style="color:var(--dim);font-size:14px;letter-spacing:.4px">地图加载中…</div>';
    } else if (s === 'map-error'){
      setTmapActive(false);          /* 腾讯地图不可用：恢复我们自己的缩放按钮与比例尺 */
      el.style.display = 'grid';
      el.innerHTML =
        '<div style="display:flex;flex-direction:column;align-items:center;gap:12px">' +
          '<div style="color:var(--dim);font-size:14px;letter-spacing:.4px">' + DEGRADE + '</div>' +
          '<button type="button" class="set-btn" data-tmap-reload="1">重新加载地图</button>' +
        '</div>';
      const btn = el.querySelector('[data-tmap-reload]');
      if (btn) btn.addEventListener('click', function(){ reloadMap(); });
    } else {
      el.style.display = 'none';
    }
  }

  /* 鉴权失败检测：① 拦截 console 中的「鉴权失败」 ② 轮询容器内腾讯自带的失败提示
     ③ 兜底：等够了时间仍没有新增任何地图资源请求 → 按运行环境失败处理（这就是白板的情况） */
  function patchConsole(){
    if (consolePatched) return;
    consolePatched = true;
    ['error', 'warn'].forEach(function(k){
      const orig = console[k];
      if (typeof orig !== 'function') return;
      console[k] = function(){
        try {
          const s = Array.prototype.map.call(arguments, function(x){ return String(x); }).join(' ');
          if (s.indexOf('鉴权失败') > -1 || s.indexOf('产品鉴权') > -1) failMap();
        } catch (e){}
        return orig.apply(console, arguments);
      };
    });
  }

  function mapReqCount(){
    try {
      return performance.getEntriesByType('resource').filter(function(e){
        return e.name.indexOf('map.qq.com') > -1 || e.name.indexOf('apis.map.qq.com') > -1;
      }).length;
    } catch (e){ return -1; }
  }

  function startAuthWatch(){
    if (authWatch) return;
    patchConsole();
    const t0 = Date.now();
    const base = mapReqCount();
    authWatch = setInterval(function(){
      const h = host();
      const txt = h ? (h.innerText || '') : '';
      /* ① 腾讯自带的鉴权失败提示出现 → 立即降级（不能把它当最终状态留在页面上） */
      if (txt.indexOf('鉴权失败') > -1 || txt.indexOf('产品鉴权') > -1){ failMap(); return; }
      const el = Date.now() - t0;
      /* ② 已有画布且无失败提示 → 就绪 */
      if (STATE === 'loading-map' && h && h.querySelector('canvas') && el > 1200){
        stopAuthWatch();
        setState('map-ready');
        return;
      }
      /* ③ 兜底：12 秒过去地图没有产生任何新增资源请求 → 判定失败（白板） */
      if (!readyChecked && el > 12000){
        readyChecked = true;
        if (mapReqCount() <= base + 2){ failMap(); return; }
      }
      /* ④ 15 秒仍未就绪 → 失败 */
      if (el > 15000 && STATE === 'loading-map'){ failMap(); return; }
    }, 500);
  }
  function stopAuthWatch(){
    if (authWatch){ clearInterval(authWatch); authWatch = null; }
  }

  /* 失败：销毁失效实例并进入 map-error（提供「重新加载地图」入口） */
  function failMap(){
    if (STATE === 'map-error') return;
    stopAuthWatch();
    try { if (map && typeof map.destroy === 'function') map.destroy(); } catch (e){}
    map = null; marks = null; win = null; ready = false;
    window.__tmapMap = null;
    setState('map-error');
  }

  /* 重新检测入口 */
  function reloadMap(){
    stopAuthWatch();
    try { if (map && typeof map.destroy === 'function') map.destroy(); } catch (e){}
    map = null; marks = null; win = null; ready = false; tries = 0;
    readyChecked = false;
    window.__tmapMap = null;
    lastSig = '';
    viewedOnce = false;
    fitSig = '';
    userMoved = false;
    STATE = 'idle';
    setState('loading-map');
    if (init()){ setState('map-ready'); render(); return; }
    startAuthWatch();
  }

  /* 热力层：用真实设备坐标画覆盖圆（半径按米，随缩放正确变化，不随屏幕像素漂移）。
     样式必须是 TMap.CircleStyle 实例，传普通对象腾讯会报
     「MultiCircle.styles: 样式id ok 希望传入CircleStyle实例，实际传入：Object」
     （连带的 MultiPolygon.styles 也是同一处触发的），
     所以推迟到第一次打开热力开关时（TMap 已就绪）再构造。 */
  let HEAT_STYLES = null;
  function heatStyles(){
    if (HEAT_STYLES) return HEAT_STYLES;
    function mk(color, borderColor){
      const cfg = { color: color, borderColor: borderColor, borderWidth: 1 };
      return (window.TMap && TMap.CircleStyle) ? new TMap.CircleStyle(cfg) : cfg;
    }
    HEAT_STYLES = {
      ok:    mk('rgba(43,255,176,.14)', 'rgba(43,255,176,.22)'),
      alarm: mk('rgba(255,182,72,.17)', 'rgba(255,182,72,.26)'),
      off:   mk('rgba(255,77,109,.14)', 'rgba(255,77,109,.22)')
    };
    return HEAT_STYLES;
  }
  let heat = null, heatOn = false;

  function syncHeat(list){
    if (!heat) return;
    if (!heatOn){ heat.setGeometries([]); return; }
    /* 热力圆必须用实测坐标：无坐标设备（空值会被 Number() 算成 0）会在几内亚湾画出热点 */
    heat.setGeometries((list || []).filter(hasPos).map(function(d){
      const tone = (typeof devTone === 'function') ? devTone(d) : 'ok';
      return {
        id: 'h_' + d.id, styleId: tone,
        center: new TMap.LatLng(Number(d.lat), Number(d.lng)),
        radius: 260
      };
    }));
  }
  function ensureHeat(){
    if (heat || !map || !window.TMap) return;
    try { heat = new TMap.MultiCircle({ map: map, styles: heatStyles(), geometries: [] }); }
    catch (e){ heat = null; }
  }

  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c];
    });
  }

  /* 容器：在地图面板里创建腾讯地图容器，并隐藏模板自研瓦片层 */
  function host(){
    if (box && document.body.contains(box)) return box;
    const panel = document.getElementById('panel-location');
    if (!panel) return null;
    const stage = panel.querySelector('.lm2');
    if (!stage) return null;
    /* 只隐藏自研瓦片层；左栏清单与设备浮卡保留 —— 自绘覆盖层（TMapOverlay）要复用它们 */
    ['lm2Map', 'lm2Marks'].forEach(function(id){
      const el = document.getElementById(id);
      if (el) el.style.display = 'none';
    });
    box = document.createElement('div');
    box.id = 'lm2Tmap';
    /* 位置与占位底色交给 CSS（.lm2-tmap-host）：底色必须跟随主题 ——
       原先内联写死 #0a1020（星云蓝的深色），地图出来之前会先闪一块星云蓝；
       而且内联值在切换主题后不会更新，用类名走 CSS 变量才能自动跟随。 */
    box.className = 'lm2-tmap-host';
    stage.insertBefore(box, stage.firstChild);
    return box;
  }

  /* 统一走状态机：失败一律进 map-error（带统一降级文案 + 「重新加载地图」入口），
     不再往容器里塞一个孤立提示 */
  function degrade(){ failMap(); }

  function visible(){
    /* 不按坐标过滤：没有实测坐标的设备也要出现在地图上（点位由 posOf 落到园区默认位置），
       否则"默认视野显示全部设备"就无从谈起 */
    const list = (curData().devices || []);
    return list.filter(function(d){
      const tone = (typeof devTone === 'function') ? devTone(d) : 'ok';
      if (filter === 'online'  && tone === 'off') return false;
      if (filter === 'offline' && tone !== 'off') return false;
      if (filter === 'alarm'   && tone !== 'alarm') return false;
      if (keyword && String(d.id).indexOf(keyword) < 0) return false;
      return true;
    });
  }

  /* 视野统计已移到 TMapOverlay 的 syncVp()：那里的口径跟随「连接轴 + 告警轴 + 检索」，
     而这里的版本只看旧模块自己的 filter，筛选/检索一变数字不动，看着像没生效。 */

  function showInfo(id){
    const d = (curData().devices || []).find(function(x){ return x.id === id; });
    if (!d || !map) return;
    const tone = (typeof devTone === 'function') ? devTone(d) : 'ok';
    const state = (typeof devStateText === 'function' ? devStateText(d) : '') ;
    const html = '<div style="min-width:210px;font-size:13px;line-height:1.75;color:var(--text)">' +
      '<div style="font-weight:650;margin-bottom:6px">' + esc(d.id) + '</div>' +
      '<div style="color:var(--dim)">状态：' + esc(state) + '</div>' +
      '<div style="color:var(--dim)">实际电压：' + esc(d.online ? d.load + ' V' : '--') +
        ' · 设定电压：' + esc(d.temp + ' V') + '</div>' +
      '<div style="color:var(--dim)">工作状态：' + esc(App.utils.workStatusText(d.workStatus)) + '</div>' +
      '<div style="color:var(--dim)">最近上报：' + esc(d.online ? hbText(d.hbOffset) : '已失联') + '</div>' +
      '<div style="color:var(--dim)">位置：' + esc(d.address || '--') + '</div>' +
    '</div>';
    if (win){ win.destroy(); win = null; }
    win = new TMap.InfoWindow({
      map: map,
      position: new TMap.LatLng(Number(d.lat), Number(d.lng)),
      offset: { x: 0, y: -18 },
      content: html
    });
    win.open();
  }

  function init(){
    if (ready || !window.TMap) return false;
    const h = host();
    if (!h) return false;
    const r = h.getBoundingClientRect();
    if (!r.width || !r.height) return false;         /* 视图未挂载/不可见时不初始化 */
    if (h.firstChild) h.innerHTML = '';               /* 清掉可能残留的降级提示后再建图 */
    try {
      /* 只认真正有坐标的设备；一台都没有就用园区兜底点，
         绝不把中心设成 (0,0) 或 NaN */
      const first = visible().filter(hasPos)[0];
      map = new TMap.Map(h, {
        zoom: first ? 15 : FALLBACK_CENTER.zoom,
        center: first ? new TMap.LatLng(Number(first.lat), Number(first.lng))
                      : new TMap.LatLng(FALLBACK_CENTER.lat, FALLBACK_CENTER.lng),
        viewMode: '2D', pitch: 0, rotation: 0
      });
      /* gljs 的点标注是 TMap.MultiMarker（不存在 MultiCircleMarker） */
      marks = new TMap.MultiMarker({ map: map, styles: markerStyles(), geometries: [] });
      marks.on('click', function(evt){
        if (evt && evt.geometry) showInfo(evt.geometry.id);
      });
      map.on('tilesloaded', function(){ /* 瓦片加载完成 */ });
      /* 暴露地图实例：自绘覆盖层（TMapOverlay）需要 projectToContainer 做地理↔像素换算 */
      window.__tmapMap = map;
      /* 记住初始底图配置（默认是 vector 路网）：从卫星切回路网时还原，避免切成空白。
         只保留 type —— getBaseMap() 还会带回 features / buildingRange:[16.5,null] 这类字段，
         原样回传会被腾讯地图判为非法参数并报错（buildingRange 的最大值、最小值应传入数字） */
      try { baseHome = { type: (map.getBaseMap() || {}).type || ROAD_BASE.type }; }
      catch (e){ baseHome = ROAD_BASE; }
      /* 用户一旦自己拖动 / 滚轮 / 触摸地图，就彻底放手：默认视野只负责"打开时看全"，
         之后不再自动改动视野（否则用户拖到哪都会被下一次数据刷新拽回去） */
      try {
        const panel = document.getElementById('panel-location') || h;
        ['pointerdown', 'wheel', 'touchstart'].forEach(function(t){
          panel.addEventListener(t, function(){ userMoved = true; }, { passive: true, capture: true });
        });
      } catch (e){}
      baseIsSat = false;
      ready = true;
      setState('map-ready');
      return true;
    } catch (e){
      console.error('[tmap] 地图初始化异常', e);
      degrade();
      return false;
    }
  }

  /* =========================================================
     默认视野：框住「当前项目下所有设备」
     —— 包含没上报经纬度的设备：它们的点位落在园区默认位置（posOf 解析），
        既然要求"看得见所有设备"，它们就必须落在视野内；
        （点位在界面上按像素小幅散开只为避免互相遮挡，不影响地理归属。）
     —— 单台 / 全部重合（例如都没上报经纬度、点位都在园区）时不框选：
        fitBounds 在退化包围盒上会把级别顶到最大，看到的就是"空地图 + 一个点"。
     —— 框选后限制最大级别：两台挨得很近时不要把周边全挤出视野。
     ========================================================= */
  const FIT_PADDING = 80;       /* 框选留白（像素） */
  const FIT_MAX_ZOOM = 16;      /* 框选后允许的最大级别：再高就只剩楼栋、"看不出这是哪儿" */
  const FIT_SINGLE_ZOOM = 16;   /* 只有一台（或全部重合）时的默认级别 */
  const FIT_MERGE_DEG = 2e-4;   /* 跨度过小视为重合：约 20 米 */

  /* URL 是否指定了设备：指定时默认视野交给深链聚焦，这里不覆盖
     （当前没有跳转到地图页并带设备的入口，留作保护） */
  function hasDevParam(){
    try { return !!new URLSearchParams(location.search).get('dev'); } catch (e){ return false; }
  }

  function fitAllDevices(){
    if (!map) return false;
    const list = visible();
    if (!list.length){ centerFallback(map); return true; }   /* 一台设备都没有：停在园区兜底点 */
    const pts = list.map(posOf);
    let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
    pts.forEach(function(p){
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    });
    const cLat = (minLat + maxLat) / 2, cLng = (minLng + maxLng) / 2;
    const tight = (maxLat - minLat) < FIT_MERGE_DEG && (maxLng - minLng) < FIT_MERGE_DEG;
    if (pts.length === 1 || tight){
      map.setCenter(new TMap.LatLng(cLat, cLng));
      map.setZoom(FIT_SINGLE_ZOOM);
      return true;
    }
    map.fitBounds(new TMap.LatLngBounds(
      new TMap.LatLng(minLat, minLng),
      new TMap.LatLng(maxLat, maxLng)
    ), { padding: FIT_PADDING });
    /* fitBounds 带动画：必须等动画停下来再限级别，否则读到的是旧缩放、限制等于没做
       （这就是默认视野会顶到 20 级的原因）。多次兜底，谁最后生效以最后一次为准。 */
    const clampZoom = function(){
      try {
        if (typeof map.getZoom !== 'function') return;
        const z = map.getZoom();
        if (z > FIT_MAX_ZOOM && typeof map.setZoom === 'function') map.setZoom(FIT_MAX_ZOOM);
      } catch (e){}
    };
    clampZoom();
    setTimeout(clampZoom, 320);
    setTimeout(clampZoom, 900);
    return true;
  }

  function render(){
    if (!ready) return;
    const list = visible();
    const sig = list.map(function(d){
      return d.id + ',' + d.lng + ',' + d.lat + ',' + ((typeof devTone === 'function') ? devTone(d) : '');
    }).join('|');
    /* 视野统计由 TMapOverlay.syncVp() 统一写（口径跟随筛选与检索） */
    syncHeat(list);                       /* 热力层跟随当前筛选/数据变化 */
    if (sig === lastSig) return;
    lastSig = sig;

    /* 所有设备都画（没上报经纬度的落到园区默认位置），
       但视野只按有实测坐标的设备算——默认位置的点全堆在园区，参与框选会把视野拽偏 */
    const geoms = list.map(function(d){
      const tone = (typeof devTone === 'function') ? devTone(d) : 'ok';
      const p = posOf(d);
      return { id: d.id, styleId: tone, position: new TMap.LatLng(p.lat, p.lng), fixed: p.fixed };
    });
    /* 点位改由自绘覆盖层（TMapOverlay）绘制：保留模板的聚合占比环 / ID 标签 / 选中光环 */
    marks.setGeometries(window.__tmapOverlay ? [] : geoms);
    /* =========================================================
       默认视野（"打开就看得见当前项目下所有设备"）
       —— 只在「用户还没自己动过地图」时生效，且以**设备坐标签名**为准：
          打开地图时定位数据往往还没回来（latest_location 是另一个接口，
          第一次渲染时所有设备都还没有经纬度、全部落园区），
          只框一次就会把视野绑在这个中间态上，等真实坐标到达反而看不见设备。
          所以坐标一变就跟着重框，直到用户自己拖动/缩放为止。
       —— 状态变化（在线/告警）、周期上报不会改坐标 → 签名不变 → 不会动视野。
       —— 用户动过之后彻底放手；想手动框回全部用「回到园区」按钮。
       —— URL 指定了设备时交给深链聚焦，不在这里改视野。
       ========================================================= */
    if (hasDevParam()) return;
    if (!list.length) return;                 /* 数据还没到：等下一次渲染 */
    const posSig = list.map(function(d){ return d.id + ':' + d.lng + ',' + d.lat; }).join('|');
    if (!viewedOnce || (!userMoved && posSig !== fitSig)){
      viewedOnce = true;
      fitSig = posSig;
      fitAllDevices();
    }
  }

  /* 定位：必须由用户主动触发；错误分类按资源包要求区分 */
  function locate(){
    /* 定位必须由用户主动触发；各阶段进入状态机，错误按类型区分（资源包要求） */
    if (!navigator.geolocation){ setState('locate-unsupported'); return; }
    setState('locating');
    navigator.geolocation.getCurrentPosition(function(pos){
      if (!map){ setState('locate-error'); return; }
      const p = new TMap.LatLng(pos.coords.latitude, pos.coords.longitude);
      userMoved = true;
      map.setCenter(p); map.setZoom(16);
      setState('locate-success');
    }, function(err){
      if (err && err.code === 1) setState('locate-denied');
      else if (err && err.code === 3){ STATE = 'locate-error'; toastErr('定位超时，请检查网络或移步空旷处重试'); }
      else setState('locate-error');
    }, { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 });
  }

  /* 回到园区：与"打开时的默认视野"一致——框住当前项目下全部设备。
     手动点过之后重新进入"跟随"状态：后续坐标变化仍会自动框选，直到用户再动地图 */
  function resetView(){
    viewedOnce = true;
    userMoved = false;
    fitSig = visible().map(function(d){ return d.id + ':' + d.lng + ',' + d.lat; }).join('|');
    fitAllDevices();
  }

  function sync(){
    if (ready){ render(); return; }
    if (STATE === 'idle') setState('loading-map');
    /* 任何地图动作前先确认 SDK 存在（资源包要求），不存在时只走状态机，不抛异常 */
    if (!window.TMap){                                     /* SDK 仍在加载 */
      if (tries < 40){ tries++; setTimeout(sync, 500); } else degrade();
      return;
    }
    if (init()){ tries = 0; startAuthWatch(); render(); return; }
    /* 初始化未成功（容器此时可能还不可见 / 尺寸为 0）：
       稍后重试，不轻易降级——降级只留给 SDK 真不可用的情况 */
    if (tries < 40){ tries++; setTimeout(sync, 500); } else degrade();
  }

  /* 工具栏与筛选（复用模板 UI）：缩放 / 定位 / 检索 / 状态筛选 */
  function bind(){
    const panel = document.getElementById('panel-location');
    if (!panel) return;

    /* ---- 缩放 / 回到园区 / 定位（模板原有三个控件，按 data-zoom 绑定） ---- */
    const ctrlBox = panel.querySelector('.lm2-ctrl');
    if (ctrlBox && !ctrlBox.querySelector('[data-zoom="locate"]')){
      /* 资源包要求地图必须同时提供「定位到当前位置」，模板原本没有这个按钮，补一个 */
      const b = document.createElement('button');
      b.type = 'button'; b.dataset.zoom = 'locate'; b.title = '定位到当前位置'; b.textContent = '◎';
      ctrlBox.appendChild(b);
    }
    panel.querySelectorAll('.lm2-ctrl button').forEach(function(b){
      b.addEventListener('click', function(){
        const act = b.dataset.zoom;
        if (act === 'in'  && map){ userMoved = true; map.setZoom(map.getZoom() + 1); }
        if (act === 'out' && map){ userMoved = true; map.setZoom(map.getZoom() - 1); }
        if (act === 'locate') locate();
        if (act === 'reset') resetView();
      });
    });

    /* ---- 底图切换：路网 / 卫星（腾讯地图 GL setBaseMap） ---- */
    const baseBox = document.getElementById('lm2Base');
    if (baseBox){
      baseBox.addEventListener('click', function(e){
        const b = e.target.closest('button[data-base]');
        if (!b || !map) return;
        /* 卫星 ↔ 路网：路网必须还原成初始化时记下的配置（vector），
           写成 {type:'roadmap'} 会让画布变空白（见 ROAD_BASE 处的说明） */
        if (b.dataset.base === 'sat'){
          if (baseIsSat) return;
          try { map.setBaseMap({ type: 'satellite' }); }
          catch (err){ toastErr('底图切换失败，请稍后重试'); return; }
          baseIsSat = true;
        } else {
          if (!baseIsSat) return;
          try { map.setBaseMap(baseHome || ROAD_BASE); }
          catch (err){ toastErr('底图切换失败，请稍后重试'); return; }
          baseIsSat = false;
        }
        baseBox.querySelectorAll('button').forEach(function(x){ x.classList.toggle('active', x === b); });
      });
    }

    /* ---- 热力开关：用真实坐标画覆盖圆（半径按米） ---- */
    const heatBtn = document.getElementById('lm2Heat');
    if (heatBtn){
      heatBtn.addEventListener('click', function(){
        ensureHeat();
        if (!heat){ toastErr('热力图层暂不可用，请检查网络后重试'); return; }
        heatOn = !heatOn;
        heatBtn.classList.toggle('on', heatOn);
        heatBtn.setAttribute('aria-pressed', heatOn ? 'true' : 'false');
        syncHeat(visible());
      });
    }

    const input = panel.querySelector('.lm2-search input');
    const clear = panel.querySelector('.lm2-search button');
    const boxEl = panel.querySelector('.lm2-search');
    if (input){
      input.addEventListener('input', function(){
        keyword = input.value.trim();
        if (boxEl) boxEl.classList.toggle('has-text', !!keyword);
        lastSig = ''; render();
      });
    }
    if (clear && input){
      clear.addEventListener('click', function(){
        input.value = ''; keyword = '';
        if (boxEl) boxEl.classList.remove('has-text');
        lastSig = ''; render();
      });
    }
    /* 筛选轴由 TMapOverlay 统一驱动（见 8.2c 的 bindPanel）：
       —— 「全部 / 在线 / 离线」是三选一，本模块只同步自己的 filter（供热力图层使用）；
       —— 「有告警」是**另一条独立轴**，不在此映射里 —— 所以这里既不会把它的点击当成连接筛选，
          也不会去清除其它按钮的高亮（此前把它并进同一组，点它会把「在线/离线」的高亮清掉，
          表现成"四个按钮四选一"）。 */
    /* 用 data-val 取轴值（不再读 textContent）：按钮里现在带数量徽标 <b>N</b>，
       读文本会把徽标一起读进来（"全部 8"）导致映射失效。 */
    panel.querySelectorAll('.lm2-chips button[data-dim="conn"]').forEach(function(b){
      b.addEventListener('click', function(){
        const key = b.getAttribute('data-val');
        if (!key) return;
        filter = key;
        panel.querySelectorAll('.lm2-chips button[data-dim="conn"]').forEach(function(x){ x.classList.remove('active'); });
        b.classList.add('active');
        lastSig = ''; render();
      });
    });
  }

  bind();
  return { sync: sync, locate: locate, state: stateOf,
           render: function(){ lastSig = ''; render(); } };
})();

/* =========================================================
   8.2c 自绘覆盖层 TMapOverlay —— 在腾讯地图之上还原模板的全部可视化与交互
   —— 复用模板既有 CSS 类（.lm2-marks/.lm2-mark/.lm2-bub/.lm2-pin/.lm2-card/.loc-hit/.lm2-scale），
      外观与模板一致；唯一改动是把「地理坐标 → 容器像素」交给 TMap.projectToContainer
   —— 覆盖：聚合气泡（在·告警·离线占比环 + 台数）、单台 ID 标签、选中扩散光环、
            左栏命中清单、设备浮卡（可跳「设备管理」）、比例尺、Esc/点击空白关闭
   ========================================================= */
const TMapOverlay = (function(){
  const CLUSTER_PX = 46;      /* 容器像素内距离小于该值即聚合 */
  const MARK_MAX   = 400;     /* 单次最多绘制点位数（防极端项目卡死） */
  let layer = null, sel = null, key = '', conn = 'all', alarmOnly = false;
  let lastSig = '', started = false, bound = false;

  window.__tmapOverlay = true;     /* 通知 TMapEngine：点位交给覆盖层画 */

  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c];
    });
  }
  function m(){ return window.__tmapMap || null; }
  function panel(){ return document.getElementById('panel-location'); }
  function stage(){ const p = panel(); return p ? p.querySelector('.lm2') : null; }
  function visible(){ const st = stage(); return !!(st && st.offsetParent); }

  function ensureLayer(){
    const st = stage();
    if (!st) return null;
    if (layer && st.contains(layer)) return layer;
    layer = document.createElement('div');
    layer.className = 'lm2-marks';
    layer.style.zIndex = '5';
    st.appendChild(layer);
    return layer;
  }

  /* 与设备列表完全一致的筛选口径 */
  function filtered(){
    return (curData().devices || []).filter(function(d){
      /* 无坐标的设备不剔除：由 posOf() 落到园区默认位置显示（带上"默认位置"标注） */
      const tone = devTone(d);
      if (conn === 'online'  && tone === 'off') return false;
      if (conn === 'offline' && tone !== 'off') return false;
      /* 告警口径与设备列表页完全一致（api.js 的 devAlarmed：!online || alarm !== 'none'），
         即「在线告警」+「离线失联」都算 —— 之前只判 tone==='alarm'，把离线失联漏掉了。 */
      if (alarmOnly && tone !== 'alarm' && tone !== 'off') return false;
      if (key && String(d.id).indexOf(key) < 0) return false;
      return true;
    });
  }

  /* 容器像素聚合（模板做法）：同一格内的点位合成一个气泡。
     —— 没上报经纬度的设备（posOf().fixed）不参与聚合：它们的显示位置是园区同一个点，
        聚合后会被并成一个气泡、既看不出有几台、也没法单独点选；
        这里按等角散开成一小圈，让每台都是独立可点选的点位（虚线白边标明位置非实测）。 */
  function cluster(list, mm){
    const cells = new Map(), fixedList = [];
    list.forEach(function(d){
      const p = posOf(d);
      const px = mm.projectToContainer(new TMap.LatLng(p.lat, p.lng));
      if (!px || !isFinite(px.x) || !isFinite(px.y)) return;
      if (p.fixed){ fixedList.push({ d: d, x: px.x, y: px.y }); return; }
      const k = Math.round(px.x / CLUSTER_PX) + ':' + Math.round(px.y / CLUSTER_PX);
      let g = cells.get(k);
      if (!g){ g = { x:0, y:0, n:0, ok:0, alarm:0, off:0, fixed:0, devs:[] }; cells.set(k, g); }
      g.x += px.x; g.y += px.y; g.n++; g.devs.push(d);
      g[devTone(d)]++;
    });
    const groups = Array.from(cells.values()).map(function(g){ g.x /= g.n; g.y /= g.n; return g; });
    /* 无坐标设备：以园区点为圆心等角散开（R 固定，保证彼此以及与实测点位都不重叠） */
    const R = 34;
    fixedList.forEach(function(f, i){
      const th = -Math.PI / 2 + (i * 2 * Math.PI / Math.max(1, fixedList.length));
      const g = { x: f.x + R * Math.cos(th), y: f.y + R * Math.sin(th), n: 1,
                  ok: 0, alarm: 0, off: 0, fixed: 1, devs: [f.d] };
      g[devTone(f.d)]++;
      groups.push(g);
    });
    return groups;
  }

  function row(k, v){
    return '<div style="display:flex;gap:8px;justify-content:space-between;line-height:1.85">' +
             '<span style="color:var(--dim);flex-shrink:0">' + esc(k) + '</span>' +
             '<b style="font-weight:600;text-align:right;word-break:break-all">' + esc(v) + '</b>' +
           '</div>';
  }

  /* 设备浮卡：与模板完全一致 ——
     · 结构用模板的 .loc-card-head / .loc-tag / .loc-rows / locPlainRow / locMiniRow / .loc-open
     · 显隐必须用 .show 类（.lm2-card 默认 opacity:0 + pointer-events:none，
       设 style.display 根本不可能显示出来，这就是"点图标右下角不出浮窗"的原因） */
  function renderCard(){
    const box = document.getElementById('lm2Card');
    if (!box) return;
    const d = sel ? (curData().devices || []).find(function(x){ return x.id === sel; }) : null;
    if (!d){ box.classList.remove('show'); box.innerHTML = ''; return; }

    const off = !d.online;
    const tone = devTone(d);
    const color = tone === 'alarm' ? cssVar('--amber') : (tone === 'off' ? cssVar('--red') : cssVar('--green'));

    box.innerHTML =
      '<div class="loc-card-head"><h4>' + esc(d.id) + '</h4>' +
        '<span class="loc-tag" style="color:' + color + '">' + esc(devStateText(d)) + '</span></div>' +
      '<div class="loc-rows">' +
        locPlainRow('安装位置', d.address || '--') +
        /* 两组坐标都列出来：设备上报的是 GNSS 原始坐标（WGS-84，与 AirCloud 后台
           Tag 512/513 的报文原文一致），地图用的是平台转换后的国测局 GCJ-02。
           同一个点在这两套坐标系里数字不同（上海地区相差约 500 米），
           只显示其中一组时很容易被误读成"定位不对" */
        (hasPos(d) ? locPlainRow('地图定位',
          Number(d.lng).toFixed(6) + ', ' + Number(d.lat).toFixed(6),
          null, '国测局 GCJ-02：平台已把设备上报的经纬度转换好，腾讯地图必须用这套坐标绘制，否则会整体偏移约 500 米') : '') +
        /* 位置数据的时间：判断"显示的是不是旧位置"最直接的依据 */
        ((d.locTime && hasPos(d)) ? locPlainRow('位置数据时间', d.locTime,
          null, '平台产生这条位置数据的时间；若明显早于当前时间，说明位置还没刷新过来') : '') +
        ((d.wlng != null && d.wlat != null) ? locPlainRow('设备上报',
          Number(d.wlng).toFixed(6) + ', ' + Number(d.wlat).toFixed(6),
          null, '设备 GNSS 上报的原始坐标（WGS-84），与 AirCloud 后台 Tag 512 经度 / 513 纬度的报文原文一致；与上面「地图定位」是同一个位置') : '') +
        /* 位置不是实测的必须说清楚，否则会被误读为设备真的在那儿 */
        (!hasPos(d) ? locPlainRow('定位来源', '默认位置（设备未上报经纬度）') : '') +
        locMiniRow('实际电压', off ? '--' : d.load + ' V', d.load / 60, cssVar('--cyan')) +
        locMiniRow('设定电压', d.temp + ' V', d.temp / 60, cssVar('--violet')) +
        locPlainRow('工作状态', App.utils.workStatusText(d.workStatus)) +
        /* Tag 781/782：设备端新增的联网方式与信号强度（统一 0~31 刻度） */
        locPlainRow('联网方式', netTagText(d.netType)) +
        locPlainRow('信号强度', d.hasSignal ? (d.snr + '/31 · ' + qualityOf(d).text) : '未上报') +
        locPlainRow('最近上报', off ? '已失联' : hbText(d.hbOffset)) +
      '</div>' +
      '<button class="loc-open" data-dev="' + esc(d.id) + '" type="button">在「设备管理」中打开</button>';
    box.classList.add('show');
  }

  /* 左栏命中清单：与模板一致 ——
     · 显隐用 #lm2List 的 .show 类（.loc-list 默认隐藏）
     · 列表项是 .lm2-hit（内部 b=设备号 / em=状态），不是 .loc-hit */
  function renderRail(){
    const box = document.getElementById('lm2List');
    if (!box) return;
    const hasQuery = !!key;
    box.classList.toggle('show', hasQuery);
    if (!hasQuery){ box.innerHTML = ''; return; }

    const list = filtered();
    const rows = list.slice(0, 60);
    box.innerHTML =
      '<div class="loc-hit-head">命中 <b>' + list.length + '</b> 台' +
        (list.length > rows.length ? ' · 列出前 ' + rows.length + ' 台' : ' · 点击定位') + '</div>' +
      rows.map(function(d){
        return '<button class="lm2-hit' + (sel === d.id ? ' active' : '') + '" data-dev="' + esc(d.id) + '" type="button">' +
          '<span class="loc-dot ' + devTone(d) + '"></span>' +
          '<b>' + esc(d.id) + '</b>' +
          '<em>' + esc(d.online ? (App.utils.workStatusText(d.workStatus) || '在线') : '离线') + '</em>' +
        '</button>';
      }).join('');
  }

  function renderScale(){
    const mm = m(), el = document.getElementById('lm2Scale');
    if (!mm || !el) return;
    try {
      const c = mm.getCenter();
      const lat = c.getLat(), lng = c.getLng();
      const p1 = mm.projectToContainer(new TMap.LatLng(lat, lng));
      const p2 = mm.projectToContainer(new TMap.LatLng(lat, lng + 0.001));
      if (!p1 || !p2) return;
      const meters = 111320 * Math.cos(lat * Math.PI / 180) * 0.001;   /* 0.001° 经度 ≈ 多少米 */
      const pxPerM = Math.abs(p2.x - p1.x) / meters;
      if (!isFinite(pxPerM) || pxPerM <= 0) return;
      const cand = [10,20,50,100,200,500,1000,2000,5000,10000,20000,50000];
      const nice = cand.filter(function(v){ return v >= 90 / pxPerM; })[0] || 50000;
      el.style.display = '';
      el.innerHTML = '<span style="display:inline-block;height:6px;border-left:1px solid var(--dim);' +
        'border-right:1px solid var(--dim);border-bottom:1px solid var(--dim);width:' + (nice * pxPerM).toFixed(0) + 'px"></span>' +
        '<em style="font-style:normal;margin-left:5px">' + (nice >= 1000 ? (nice / 1000) + ' km' : nice + ' m') + '</em>';
    } catch (e){}
  }

  /* ---- 筛选计数与视野统计（口径与设备管理页「设备列表」一致）----
     连接轴：全部 / 在线 / 离线（在线含"在线告警"）；告警轴：有告警（含离线失联）。
     这两个函数不依赖地图实例，所以放在 render() 的早退之前 —— 数据/筛选一变就立刻反映。 */
  function chipCounts(){
    const all = (curData().devices || []);
    let online = 0, offline = 0, alarm = 0;
    all.forEach(function(d){
      const t = devTone(d);
      if (t === 'off') offline++; else online++;
      /* 告警口径 = 设备列表页 devAlarmed()：离线失联 或 在线告警（两者都算） */
      if (!d.online || d.alarm !== 'none') alarm++;
    });
    return { all: all.length, online: online, offline: offline, alarm: alarm };
  }
  /* 把数量写进四枚筛选按钮的徽标 <b>N</b>，并同步告警按钮的 aria-pressed —— 
     设备列表页的「在线 <b>N</b>」「有告警 <b>N</b>」就是这个做法。 */
  function syncChips(){
    const c = chipCounts();
    const btns = document.querySelectorAll('.lm2-chips button');
    if (!btns.length) return;
    Array.prototype.forEach.call(btns, function(b){
      const dim = b.getAttribute('data-dim') || '';
      const val = b.getAttribute('data-val') || '';
      const isAlarm = (dim === 'alarm') || val === 'alarm';
      const n = isAlarm ? c.alarm
              : (val === 'all' ? c.all : (val === 'online' ? c.online : (val === 'offline' ? c.offline : null)));
      if (n === null) return;
      let badge = b.querySelector('b');
      if (!badge){
        badge = document.createElement('b');
        b.appendChild(document.createTextNode('\u2009'));   /* 细空格：数字不贴着文字 */
        b.appendChild(badge);
      }
      if (badge.textContent !== String(n)) badge.textContent = String(n);
      if (isAlarm) b.setAttribute('aria-pressed', alarmOnly ? 'true' : 'false');
    });
  }
  /* 左上角「当前视野 … · 告警 N」：口径跟随**当前筛选与检索**（此前用的是旧模块的 filter，
     不含告警轴也不含检索，于是筛选后数字不动、看起来像没生效）。 */
  function syncVp(){
    const el = document.querySelector('#panel-location .lm2-vp');
    if (!el) return;
    const list = filtered();
    let online = 0, offline = 0, alarm = 0;
    list.forEach(function(d){
      const t = devTone(d);
      if (t === 'off') offline++; else online++;
      if (!d.online || d.alarm !== 'none') alarm++;   /* 与设备列表 devAlarmed() 同口径 */
    });
    el.innerHTML = '当前视野 <b>' + list.length + '</b> 台 · 在线 <b>' + online + '</b> · 离线 <b>' + offline +
                   '</b> · 告警 <b>' + alarm + '</b>';
  }

  function render(){
    /* 计数与统计先更新：它们不依赖地图实例，筛选/检索一变就该立刻反映 */
    syncChips();
    syncVp();
    const mm = m();
    if (!mm || !visible()) return;
    const lay = ensureLayer();
    if (!lay) return;
    bindAll();          /* 幂等：面板/标记的监听器缺失时在这里补挂（自愈） */

    const list = filtered();
    const shown = list.slice(0, MARK_MAX);
    let c = null;
    try { c = mm.getCenter(); } catch (e){ return; }

    /* 视图状态也纳入签名：拖动/缩放后必须重新投影，否则点位会僵在原处 */
    const sig = 'v' + (mm.getZoom ? mm.getZoom().toFixed(3) : '') + ',' +
                c.getLat().toFixed(6) + ',' + c.getLng().toFixed(6) + '|' +
                shown.map(function(d){ return d.id + ',' + d.lng + ',' + d.lat + ',' + devTone(d) + (hasPos(d) ? '' : 'F'); }).join(';') +
                '#' + sel + '#' + key + '#' + conn + alarmOnly;
    if (sig !== lastSig){
      lastSig = sig;
      const groups = cluster(shown, mm);
      lay.innerHTML = groups.map(function(g){
        if (g.n === 1){
          const d = g.devs[0];
          const fixed = !hasPos(d);
          return '<div class="lm2-mark single' + (fixed ? ' nopos' : '') + (sel === d.id ? ' sel' : '') + '" data-dev="' + esc(d.id) + '"' +
            ' style="transform:translate(' + g.x.toFixed(1) + 'px,' + g.y.toFixed(1) + 'px)"' +
            (fixed ? ' title="该设备未上报经纬度，按园区默认位置显示"' : '') + '>' +
              /* 点位尺寸/描边/光晕/呼吸光环全部由 CSS（.lm2-pin / .lm2-pin i）定义，
                 这里不再写内联尺寸，避免两处各写一套、改一处漏一处 */
              '<div class="lm2-pin ' + devTone(d) + (fixed ? ' nopos' : '') + '">' +
                '<i></i>' +
                '<b>' + esc(d.id) + '</b></div></div>';
        }
        const a = g.alarm / g.n * 100, b = (g.alarm + g.ok) / g.n * 100;
        const ring = 'conic-gradient(var(--amber) 0 ' + a.toFixed(1) + '%,' +
                     'var(--green) ' + a.toFixed(1) + '% ' + b.toFixed(1) + '%,' +
                     'var(--red) ' + b.toFixed(1) + '% 100%)';
        const size = Math.min(64, 38 + g.n * 1.2);
        /* 无坐标的设备不会进到这个分支（cluster() 里已单独成点） */
        return '<div class="lm2-mark cluster" data-cell="' + g.devs.map(function(d){ return esc(d.id); }).join(',') + '"' +
          ' style="transform:translate(' + g.x.toFixed(1) + 'px,' + g.y.toFixed(1) + 'px)">' +
            '<div class="lm2-bub" style="--s:' + size.toFixed(0) + 'px;background:' + ring + '">' +
              '<i class="lm2-num">' + g.n + '</i></div></div>';
      }).join('');
      renderRail();
      renderCard();
      renderScale();
    }
  }

  /* 点到设备图标：先走原有选中链路（浮卡 / 左栏高亮 / 告警联动都靠它），
     再把视野对齐该设备并放大到最大等级。
     与 select() 分开写是为了不影响其它入口：左栏点击只居中、不改缩放；
     集群气泡保持原有"展开成员"逻辑不变。 */
  function focusDevice(id){
    if (!id) return;
    select(id, false);
    const mm = m();
    if (!mm) return;
    const d = (curData().devices || []).find(function(x){ return x.id === id; });
    if (!d) return;
    /* 无坐标的设备同样放大到最大级别：它的点位就在园区默认位置（posOf 统一解析） */
    const p = posOf(d);
    userMoved = true;      /* 用户点了某个设备：视野交给它，之后不再自动框选 */
    try {
      mm.setCenter(new TMap.LatLng(p.lat, p.lng));
      if (typeof mm.setZoom === 'function') mm.setZoom(MAX_FOCUS_ZOOM);
    } catch (e){}
  }

  function select(id, center){
    sel = id || null;
    if (sel && center !== false){
      const d = (curData().devices || []).find(function(x){ return x.id === sel; });
      const mm = m();
      if (d && mm){
        /* 无坐标的设备也居中：它的点位就显示在园区默认位置 */
        const p = posOf(d);
        try { mm.setCenter(new TMap.LatLng(p.lat, p.lng)); } catch (e){}
      }
    }
    lastSig = '';
    render();
  }

  /* 交互绑定拆成两组、各自幂等，并由 render() 自愈式补挂：
     之前合成一个 bind()，任何一处抛错都会让后面的搜索/筛选彻底失去监听器
     —— 这正是"搜索后左栏不出清单、筛选按钮点了没反应"的原因 */
  let boundMarks = false, boundPanel = false;

  function bindMarks(){
    if (boundMarks) return;
    const st = stage();
    if (!st) return;
    st.addEventListener('mouseover', function(e){
      const mk = e.target.closest ? e.target.closest('.lm2-mark.single') : null;
      if (mk) mk.classList.add('hover');
    });
    st.addEventListener('mouseout', function(e){
      const mk = e.target.closest ? e.target.closest('.lm2-mark.single') : null;
      if (mk) mk.classList.remove('hover');
    });
    st.addEventListener('click', function(e){
      const mk = e.target.closest ? e.target.closest('.lm2-mark') : null;
      if (!mk) return;
      e.stopPropagation();
      if (mk.classList.contains('single')){ focusDevice(mk.dataset.dev); return; }
      const ids = String(mk.dataset.cell || '').split(',').filter(Boolean);
      if (ids.length) select(ids[0], false);
    });
    document.addEventListener('keydown', function(e){ if (e.key === 'Escape') select(null); });
    boundMarks = true;
  }

  /* 面板交互：检索框 / 状态筛选 / 左栏命中项 / 设备浮卡按钮（全部委托到面板上） */
  function bindPanel(){
    if (boundPanel) return;
    const p = panel();
    if (!p) return;

    const input = p.querySelector('.lm2-search input');
    const boxEl = p.querySelector('.lm2-search');
    const clearBtn = p.querySelector('.lm2-search button');
    if (input){
      input.addEventListener('input', function(){
        key = input.value.trim();
        if (boxEl) boxEl.classList.toggle('has-text', !!key);
        lastSig = ''; render();
      });
    }
    /* 清空按钮：输入框与检索词一起清 —— 左栏清单的显示条件是「检索词非空」（见 renderRail），
       key 归零后 render() 就会把清单收起来（此前只清了输入框，清单还挂在那儿）。 */
    if (clearBtn){
      clearBtn.addEventListener('click', function(){
        if (input) input.value = '';
        key = '';
        if (boxEl) boxEl.classList.remove('has-text');
        lastSig = ''; render();
      });
    }

    /* 两条独立筛选轴（与页面结构一致：data-dim="conn" 三枚 + data-dim="alarm" 一枚）：
       · 连接：全部 / 在线 / 离线 —— 三选一；
       · 告警：有告警 —— 独立开关，可选中也可取消，不影响连接轴，自身也有高亮反馈。
       轴值一律从 data-val 读：按钮里现在有数量徽标 <b>N</b>，读 textContent 会把徽标读进来。 */
    p.querySelectorAll('.lm2-chips button').forEach(function(b){
      b.addEventListener('click', function(){
        const dim = b.getAttribute('data-dim') || '';
        const val = b.getAttribute('data-val') || '';
        const isAlarm = (dim === 'alarm') || val === 'alarm';
        if (isAlarm){
          alarmOnly = !alarmOnly;
          b.classList.toggle('active', alarmOnly);
        } else if (val === 'all' || val === 'online' || val === 'offline'){
          conn = val;
          p.querySelectorAll('.lm2-chips button[data-dim="conn"]').forEach(function(x){
            x.classList.toggle('active', x === b);
          });
        } else {
          return;
        }
        lastSig = ''; render();
      });
    });

    /* 左栏命中项 → 定位到该台；浮卡关闭 / 「在设备管理中打开」 */
    p.addEventListener('click', function(e){
      if (!e.target.closest) return;
      /* 列表项类名是 .lm2-hit（不是 .loc-hit —— 之前选择器写错，点列表项没反应）。
         行为与「点击地图上的设备圆点」完全一致：统一走 focusDevice()
         （select 选中 → 浮卡/左栏高亮 → 视野居中 → 放大到最大级别）。 */
      const hit = e.target.closest('.lm2-hit');
      if (hit){
        e.stopPropagation();
        e.preventDefault();
        focusDevice(hit.dataset.dev);
        return;
      }
      if (e.target.closest('[data-close]')){ select(null); return; }
      const open = e.target.closest('.loc-open');
      if (open){
        /* 多页面：跳到设备管理页并带上设备号，由那一页打开详情 */
        if (window.App && App.nav) App.nav.to('devices', { dev: open.dataset.dev });
      }
    });
    boundPanel = true;
  }

  /* 滚轮缩放的转发：点位是真实尺寸的 DOM（pointer-events:auto），鼠标停在点位上时
     滚轮事件落在点位内部，传不到腾讯地图的容器 → 缩放失效。
     这里把事件原样转发给地图容器，保留"以光标为锚点"的原生缩放手感；
     若该版本不处理合成事件，60ms 后校验缩放没变就直接 setZoom 兜底。
     —— 挂载目标必须是覆盖层自己创建的那个层（ensureLayer）：页面里还有一个模板遗留的
        同名层 #lm2Marks（在隐藏的 #lm2Map 内、0×0），querySelector('.lm2-marks')
        会先命中它，挂上去等于没挂（这是转发一开始不生效的原因）。 */
  let boundWheel = false;
  function bindWheelForward(){
    if (boundWheel) return;
    const mm = m();
    const lay = ensureLayer();
    const card = document.getElementById('lm2Card');
    /* 腾讯地图把监听挂在自己的容器上（宿主 #lm2Tmap 内的那个 div） */
    const box = document.querySelector('#lm2Tmap > div') || document.getElementById('lm2Tmap');
    if (!mm || !lay || !box) return;

    function onWheel(e){
      e.preventDefault();
      e.stopPropagation();
      const before = (typeof mm.getZoom === 'function') ? mm.getZoom() : null;
      let sent = true;
      try {
        box.dispatchEvent(new WheelEvent('wheel', {
          bubbles: true, cancelable: true, view: window,
          deltaX: e.deltaX, deltaY: e.deltaY, deltaZ: e.deltaZ, deltaMode: e.deltaMode,
          clientX: e.clientX, clientY: e.clientY, screenX: e.screenX, screenY: e.screenY,
          ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, altKey: e.altKey, metaKey: e.metaKey
        }));
      } catch (err){ sent = false; }
      if (!sent || before === null) return;
      setTimeout(function(){
        try {
          if (mm.getZoom() === before && typeof mm.setZoom === 'function'){
            mm.setZoom(before + (e.deltaY < 0 ? 1 : -1));
          }
        } catch (err){}
      }, 60);
    }

    /* 点位层与浮卡都是地图之上的 DOM，两者都会挡住容器的滚轮，都要转发 */
    lay.addEventListener('wheel', onWheel, { passive: false });
    if (card) card.addEventListener('wheel', onWheel, { passive: false });
    boundWheel = true;
  }

  function bindAll(){
    try { bindMarks(); } catch (e){ console.error('[overlay] bindMarks 失败', e); }
    try { bindPanel(); } catch (e){ console.error('[overlay] bindPanel 失败', e); }
    try { bindWheelForward(); } catch (e){ console.error('[overlay] bindWheelForward 失败', e); }
  }

  /* 地图视图事件：拖动/缩放/俯仰/旋转后必须重新投影，否则点位会僵在原处。
     注意：这里不能用 requestAnimationFrame 节流 —— 页面不在前台时 rAF 会被浏览器挂起，
     会表现成"拖动地图点位完全不动"。改用时间戳节流，同步重绘。 */
  let lastView = 0;
  function onViewChange(){
    const now = Date.now();
    if (now - lastView < 60) return;      /* 约 16 次/秒 */
    lastView = now;
    lastSig = '';
    render();
  }

  /* 视图跟随（可靠兜底）：各家版本的地图事件名不一致，programmatic 缩放也未必触发事件，
     因此固定间隔比对「中心 + 缩放」，一变就重新投影。
     用 setInterval 而不是 requestAnimationFrame —— 后台标签页里 rAF 会被浏览器挂起。 */
  let lastViewKey = '';
  function watchView(){
    const mm = m();
    if (!mm || !visible()) return;
    let k = '';
    try {
      const c = mm.getCenter();
      k = (mm.getZoom ? mm.getZoom() : '') + ',' + c.getLat().toFixed(6) + ',' + c.getLng().toFixed(6);
    } catch (e){ return; }
    if (k !== lastViewKey){ lastViewKey = k; lastSig = ''; render(); }
  }
  setInterval(watchView, 120);

  function tick(){
    if (!started) return;
    try { render(); } catch (e){}
    requestAnimationFrame(tick);
  }

  /* 等地图实例就绪后再挂载（地图由 TMapEngine 异步创建） */
  let tries = 0;
  function boot(){
    const mm = m();
    if (!mm){ if (tries++ < 120) setTimeout(boot, 500); return; }
    /* 事件绑定失败绝不能阻断渲染循环：渲染与交互互相独立 */
    bindAll();
    try { mm.on('click', function(){ select(null); }); } catch (e){}
    /* 地图视图变化 → 重新投影所有点位（拖动/缩放/俯仰/旋转） */
    ['pan','zoom','bounds_changed','pitch','rotation'].forEach(function(ev){
      try { mm.on(ev, onViewChange); } catch (e){}
    });
    started = true;
    requestAnimationFrame(tick);
  }
  boot();

  return {
    refresh: function(){ lastSig = ''; render(); },
    select: select
  };
})();



window.addEventListener('themechange', () => buildLocationMap(curData(), true));


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
/* 位置地图页 */
registerPageRenderer(function(data){ buildLocationMap(data); });

/* assets/js/boot.js —— 每个页面共用的启动流程（多页面结构）
   —— 页面之间不共享内存：本页用到的面板只在本页 HTML 里，
      各页面把自己的重绘函数登记到 shell 的渲染表（registerPageRenderer），
      这里统一：注入认证 → 拉项目 → 拉当前项目真实数据 → 跑本页渲染与页面参数
   ========================================================= */
(function init(){
  /* URL 上的 m_* 宿主注入 / 宿主会话；未登录则跳转 login.html */
  App.auth.consumeInjection();
  if (!App.auth.requireAuth()) return;

  /* 侧栏高亮与「当前页名」已由 shell.js 的多页面导航段（12 节）初始化 */

  let lazyStarted = false;
  function loadLazyBundle(){
    if (lazyStarted) return;
    const lazy = (document.body && document.body.dataset) ? document.body.dataset.lazyBundle : '';
    if (!lazy) return;
    lazyStarted = true;
    const s = document.createElement('script');
    s.src = lazy;
    s.async = true;
    s.onload = function(){
      /* 地图引擎就位后补一次渲染：buildLocationMap 是刚刚才登记进渲染表的，
         renderAllViews 末尾还会派发一次 resize（引擎/覆盖层靠它做首次同步） */
      try { if (typeof renderAllViews === 'function') renderAllViews(); } catch (e){}
    };
    s.onerror = function(){ console.warn('[boot] 延迟分包加载失败：' + lazy); };
    document.head.appendChild(s);
  }

  /* 首屏（KPI/饼图）先渲染，再加载地图分包——它只服务地图面板，
     没必要占着首屏的关键路径（解析 + 执行）。带兜底定时器，
     保证接口卡住时地图也会自己加载起来。 */
  const lazyTimer = setTimeout(loadLazyBundle, 1500);
  const loading = loadProjects();
  const afterFirstRender = function(){ clearTimeout(lazyTimer); setTimeout(loadLazyBundle, 150); };
  if (loading && typeof loading.then === 'function') loading.then(afterFirstRender, afterFirstRender);

  scheduleProjectRefresh();

  /* 地图引擎要「容器已有尺寸」才建图：页面刚加载时偶发量到 0×0（布局未定），
     那样首屏地图就会一直空着——这是「地图经常刷新不出来」的偶发分支。
     只有本页确实有地图容器时才补发 resize 重试；其它页面补发没有意义，
     反而会让各页的 resize 渲染函数（设备页会整页重排）被反复重跑。 */
  if (document.getElementById('lm2Tmap')){
    [300, 1000, 2200, 4000].forEach(function(t){
      setTimeout(function(){ window.dispatchEvent(new Event('resize')); }, t);
    });
  }
})();
