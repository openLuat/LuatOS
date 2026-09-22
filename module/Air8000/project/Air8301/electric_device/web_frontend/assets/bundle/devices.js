/* 打包产物（合并顺序 = 模块加载顺序，勿手改）：luat-sdk.js + config.js + storage.js + utils.js + http.js + auth.js + guards.js + components.js + api.js + shell.js + pages/devices.js + boot.js */
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

/* assets/js/pages/devices.js —— 由 index.html 内联脚本拆出（原行区间 4023-4494 / 7262-8466），内容未改动 */
/* =========================================================
   6.2 设备列表
   ========================================================= */
/* =========================================================
   6.3 列表按可用高度自适应（不出现滚动条）
   ========================================================= */
/* probeRowHeight() 已移到公共层（多页面下别的页面也要用） */

/* 行模板，供探针测量每页条数使用（状态文案取最长的一档：在线 · 严重告警） */
const DEV_ROW_PROBE =
  '<span class="dot ok"></span>' +
  '<div class="dev-info"><div class="dev-name">W</div><div class="dev-meta">W</div></div>' +
  '<div class="dev-val ok">在线 · 严重告警</div>';

/* ALERT_ROW_PROBE 已移到 pages/alerts.js */

function deviceRow(d, clickable){
  const row = document.createElement('div');
  row.className = 'dev-row' + (clickable ? '' : ' is-static');
  /* 一个标签同时说清两条轴：在线 · 无告警 / 在线 · 告警 / 离线 · 失联 */
  row.innerHTML =
    '<span class="dot ' + devTone(d) + '"></span>' +
    '<div class="dev-info">' +
      '<div class="dev-name">' + d.id + '</div>' +
      '<div class="dev-meta">' + d.zone + ' · ' + d.area + ' · ' + netTagText(d.netType) + '</div>' +
    '</div>' +
    '<div class="dev-val ' + devTone(d) + '">' + devStateText(d) + '</div>';
  /* 行会被复用（见 renderDevices 的增量更新）：点击时按 id 取当前最新数据，
     避免复用行里闭包捕获的还是上一轮刷新的旧对象 */
  if (clickable) row.addEventListener('click', () => openDeviceView(freshDev(d), 'basic'));
  return row;
}

/* 按 id 取当前最新的设备对象（增量渲染后行对象可能复用，数据对象却已换代） */
function freshDev(d){
  const list = (typeof curData === 'function' ? curData().devices : null) || [];
  return list.find(x => x.id === d.id) || d;
}

/* qualityOf() 已移到公共层 api.js（地图页也要用） */

/* 设备列表表格：表头 / 行模板 */
const DEV_SORT_ICON =
  '<svg class="th-ico" viewBox="0 0 10 14" aria-hidden="true">' +
    '<path class="up" d="M5 1 8.4 5.4H1.6z"/>' +
    '<path class="down" d="M5 13 1.6 8.6h6.8z"/>' +
  '</svg>';

/* 可排序列：顺序须与表格第 1~5 列一一对应（末列「操作」不参与排序） */
const DEV_SORT_COLS = [
  { key:'id',        label:'设备号' },
  { key:'area',      label:'位置' },
  { key:'status',    label:'状态' },
  { key:'quality',   label:'通信质量' },
  { key:'heartbeat', label:'最近上报' }
];

function devSortTh(col){
  const dir = state.devSort === col.key ? state.devSortDir : '';
  return '<button class="th-sort" data-sort="' + col.key + '"' +
         (dir ? ' data-dir="' + dir + '"' : '') +
         ' title="按「' + col.label + '」排序">' +
         '<span>' + col.label + '</span>' + DEV_SORT_ICON +
         '</button>';
}

function devTableHead(){
  return DEV_SORT_COLS.map(devSortTh).join('') + '<span>操作</span>';
}

/* 状态排序权重：离线·失联 → 在线·告警 → 在线·无告警（由异常到正常） */
const TONE_RANK = { off: 0, alarm: 1, ok: 2 };
const toneRank = d => (TONE_RANK[devTone(d)] != null ? TONE_RANK[devTone(d)] : 9);

/* 按表头排序取排序副本（sort 是稳定的，同值时保持原有设备顺序） */
function sortDevices(rows){
  const key = state.devSort;
  if (!key) return rows;
  const dir = state.devSortDir === 'desc' ? -1 : 1;

  return rows.slice().sort((a, b) => {
    /* 字符串列：设备 ID 按数字段自然排序，位置按中文拼音 */
    if (key === 'id') return dir * a.id.localeCompare(b.id, 'en', { numeric: true });
    if (key === 'area'){
      return dir * (a.zone + a.area).localeCompare(b.zone + b.area, 'zh-Hans-CN');
    }
    let va, vb;
    if (key === 'status'){ va = toneRank(a); vb = toneRank(b); }
    /* 信号排序：先按分级（4 档），再按原值 —— 避免 4G 的 99（无信号）被排到最前 */
    else if (key === 'quality'){ va = qualityOf(a).lv * 100 + a.snr; vb = qualityOf(b).lv * 100 + b.snr; }
    else { va = a.hbOffset || 0; vb = b.hbOffset || 0; }
    return (va - vb) * dir;
  });
}

/* 点击表头：首次按升序，再次点击同一列切换为降序 */
function toggleDevSort(key){
  if (state.devSort === key){
    state.devSortDir = state.devSortDir === 'asc' ? 'desc' : 'asc';
  } else {
    state.devSort = key;
    state.devSortDir = 'asc';
  }
  state.devPage = 1;
  renderDevices(curData());
}

const DEV_TABLE_PROBE =
  '<span class="dt-id">W</span>' +
  '<span class="dt-cell">W</span>' +
  '<span class="dt-cell dt-flex"><span class="dev-val ok">在线 · 严重告警</span></span>' +
  '<span class="dt-cell dt-flex"><span class="q-bar" data-lv="4"><i></i><i></i><i></i><i></i></span><span class="q-text">优秀</span></span>' +
  '<span class="dt-cell">W</span>' +
  '<span class="dt-ops"><button class="mini-btn">详情</button><button class="mini-btn">指令</button></span>';

function deviceTableRow(d, clickable){
  const q = qualityOf(d);
  const row = document.createElement('div');
  row.className = 'dev-row-t' + (clickable ? '' : ' is-static');
  row.innerHTML =
    '<span class="dt-id">' + d.id + '</span>' +
    '<span class="dt-cell">' + d.zone + ' · ' + d.area + '</span>' +
    '<span class="dt-cell dt-flex"><span class="dev-val ' + devTone(d) + '">' + devStateText(d) + '</span></span>' +
    '<span class="dt-cell dt-flex">' +
      /* 联网方式（Tag 781）短标签：4G / WiFi / 以太网 / 未上报 */
      '<span class="net-tag" data-net="' + (d.netType || 0) + '">' + netTagText(d.netType) + '</span>' +
      '<span class="q-bar" data-lv="' + q.lv + '" style="--qc:' + q.color + '"><i></i><i></i><i></i><i></i></span>' +
      '<span class="q-text">' + q.text + '</span>' +
    '</span>' +
    '<span class="dt-cell">' + hbRelText(d) + '</span>' +
    (clickable
      ? '<span class="dt-ops">' +
          '<button class="mini-btn" data-op="detail">详情</button>' +
          '<button class="mini-btn" data-op="cmd">指令</button>' +
        '</span>'
      : '<span class="dt-ops"><span class="dt-static" title="在「设备管理」中查看详情与下发指令">—</span></span>');

  if (!clickable) return row;

  row.addEventListener('click', () => openDeviceView(freshDev(d), 'basic'));
  row.querySelector('[data-op="detail"]').addEventListener('click', e => {
    e.stopPropagation();
    openDeviceView(freshDev(d), 'basic');
  });
  row.querySelector('[data-op="cmd"]').addEventListener('click', e => {
    e.stopPropagation();
    openDeviceView(freshDev(d), 'control');
  });
  return row;
}

/* 面板宽度够宽时用表格（带表头与多列），窄面板沿用紧凑行 */
const TABLE_MIN_WIDTH = 720;

/* =========================================================
   列宽自适应
   表头与每个数据行都是各自独立的 grid 容器，只有写入同一份列宽模板
   才能保证纵向对齐。做法：先按 max-content 量出各列内容的自然宽度，
   再用「水位线」把剩余空间补给内容较窄的列——低于水位的列补到水位，
   高于水位的列保持自身宽度，从而让各列宽度尽量接近且都不窄于内容。
   ========================================================= */
const DEV_TABLE_COLS = 6;
const DEV_TABLE_SEAM = 2;   /* 行左右各 1px 边框，留出余量避免横向溢出 */

function balanceDeviceColumns(list){
  const grids = Array.from(list.children).filter(
    el => el.classList.contains('dev-thead') || el.classList.contains('dev-row-t')
  );
  if (!grids.length) return;

  const cs = getComputedStyle(grids[0]);
  const gap = parseFloat(cs.columnGap) || 0;
  const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);

  /* 面板不在当前视图时宽度为 0，此时沿用 CSS 里的兜底列宽 */
  const avail = list.clientWidth - padX - DEV_TABLE_SEAM - gap * (DEV_TABLE_COLS - 1);
  if (avail <= 0) return;

  /* 先把所有容器切成 max-content，再统一读取宽度：写读分离，期间不会触发绘制 */
  const probeTpl = 'repeat(' + DEV_TABLE_COLS + ', max-content)';
  grids.forEach(g => { g.style.gridTemplateColumns = probeTpl; });

  const need = new Array(DEV_TABLE_COLS).fill(0);
  grids.forEach(g => {
    Array.from(g.children).forEach((cell, i) => {
      if (i >= DEV_TABLE_COLS) return;
      const w = cell.getBoundingClientRect().width;
      if (w > need[i]) need[i] = w;
    });
  });

  /* 二分求水位线 L：sum(max(内容宽, L)) 恰好不超过可用宽度 */
  let lo = 0, hi = avail;
  for (let i = 0; i < 32; i++){
    const mid = (lo + hi) / 2;
    const total = need.reduce((a, w) => a + (w > mid ? w : mid), 0);
    if (total > avail) hi = mid; else lo = mid;
  }
  let widths = need.map(w => (w > lo ? w : lo));

  /* 面板过窄、内容总和超宽时整体等比收缩，宁可省略号也不出现横向溢出 */
  const total = widths.reduce((a, w) => a + w, 0);
  if (total > avail) widths = widths.map(w => w * avail / total);

  const tpl = widths.map(w => Math.floor(w) + 'px').join(' ');
  grids.forEach(g => { g.style.gridTemplateColumns = tpl; });
}

/* 设备筛选：连接轴（全部/在线/离线）+ 告警轴（是否只看告警）+ 设备 ID 模糊匹配 */
function matchDevices(data){
  const q = state.devQuery.trim().toUpperCase();
  const f = state.devFilter;                    /* all / online / offline */
  const alarmOnly = state.devAlarmOnly;         /* 只看有告警（含离线失联） */
  if (!q && f === 'all' && !alarmOnly) return data.devices;
  return data.devices.filter(d =>
    (f === 'all' || (f === 'online') === devOnline(d)) &&
    (!alarmOnly || devAlarmed(d)) &&
    (!q || d.id.toUpperCase().indexOf(q) > -1)
  );
}

/* 行的增量更新池：id → { el, sig }
   —— 定时刷新时通常只有少数几行真的变了，按签名复用 DOM，只重建变化的行 */
let devRowPool = new Map();
let devHead = null;          /* 表格模式的表头：只在「宽窄 / 排序」变化时重建 */
let devHeadSum = '';
let devEmpty = null;         /* 「无匹配设备」提示：复用同一个节点 */

/* 「最近上报」的相对文案。
   —— 注意 hbOffset 为 0 有两种含义：① 刚刚上报过（lastCt 有值）② 云端从未有过记录。
      必须用 lastCt 区分，否则"从未上报"的设备会被当成"刚刚"
      （原实现写的是 `d.hbOffset || 30`：0 被兜底成 30 秒 → timeText 算出"刚刚"）。 */
function hbRelText(d){
  if (!d) return '--';
  const hasLastCt = (typeof d.lastCt === 'number' && d.lastCt > 0);
  const hasOffset = (typeof d.hbOffset === 'number' && d.hbOffset > 0);
  if (!hasLastCt && !hasOffset) return '从未上报';
  const ts = hasLastCt ? d.lastCt : (Date.now() - d.hbOffset * 1000);
  return timeText(ts);
}

/* 行内容签名：这几项决定了一个行长什么样（表格模式还要含"最近上报"的相对时间文案） */
function devRowSig(d, wide, clickable){
  const base = [d.id, d.zone, d.area, devTone(d), devStateText(d), wide ? 1 : 0, clickable ? 1 : 0].join('|');
  if (!wide) return base;
  const q = qualityOf(d);
  return base + '|' + q.lv + '|' + q.text + '|' + hbRelText(d);
}

function renderDevices(data){
  const list = document.getElementById('deviceList');
  if (!list) return;

  const matched = sortDevices(matchDevices(data));
  const wide = list.clientWidth >= TABLE_MIN_WIDTH;

  /* ---------- 表头：只在宽窄模式或排序变化时重建 ---------- */
  const headSig = wide + '|' + (wide ? (state.devSort || '') + state.devSortDir : '');
  if (headSig !== devHeadSum){
    devHeadSum = headSig;
    if (devHead && devHead.parentNode) devHead.remove();
    devHead = null;
    if (wide){
      const thead = document.createElement('div');
      thead.className = 'dev-thead';
      thead.innerHTML = devTableHead();
      /* 表头重建时在此绑定排序点击 */
      thead.querySelectorAll('.th-sort').forEach(btn => {
        btn.addEventListener('click', () => toggleDevSort(btn.dataset.sort));
      });
      devHead = thead;
    }
  }
  if (devHead && devHead.parentNode !== list) list.insertBefore(devHead, list.firstChild);

  /* 表格模式的表头高度要从可用高度里扣掉 */
  const headH = devHead ? devHead.getBoundingClientRect().height : 0;

  /* 每页条数由面板可用高度决定：行高固定，量一次即可（面板被摘除时用兜底值） */
  const avail = list.clientHeight - headH;
  const rowH = avail > 0
    ? probeRowHeight(list, wide ? 'dev-row-t' : 'dev-row', wide ? DEV_TABLE_PROBE : DEV_ROW_PROBE)
    : 0;
  const size = rowH > 0
    ? Math.max(1, Math.floor((avail - 2) / rowH))
    : DEVICE_SPEC.pageSize;

  const pages = Math.max(1, Math.ceil(matched.length / size));
  if (state.devPage > pages) state.devPage = pages;
  if (state.devPage < 1) state.devPage = 1;

  const start = (state.devPage - 1) * size;
  const rows = matched.slice(start, start + size);
  /* 概览视图里的设备列表仅作展示，不提供进入详情的交互 */
  const clickable = detailAllowed();

  /* ---------- 行：按 id 复用，签名变了才重建（appendChild 顺带把复用的行摆到正确位置） ---------- */
  const keep = new Set();
  rows.forEach(d => {
    const sig = devRowSig(d, wide, clickable);
    let row = devRowPool.get(d.id);
    if (!row || row.sig !== sig){
      const el = wide ? deviceTableRow(d, clickable) : deviceRow(d, clickable);
      if (row && row.el && row.el.parentNode) row.el.parentNode.replaceChild(el, row.el);
      row = { el: el, sig: sig };
      devRowPool.set(d.id, row);
    }
    keep.add(d.id);
    list.appendChild(row.el);
  });
  /* 回收不在本页的行（翻页 / 筛选 / 项目切换后不留残行） */
  devRowPool.forEach((row, id) => {
    if (keep.has(id)) return;
    if (row.el && row.el.parentNode) row.el.remove();
    devRowPool.delete(id);
  });

  /* 当前页设备 → 实时拉取最新 Tag（切页 / 搜索 / 筛选后由本函数重新触发） */
  queueTags(rows.map(d => d.id));

  if (!rows.length){
    const tip = state.devQuery
      ? '未找到匹配「' + state.devQuery + '」的设备'
      : (state.devFilter !== 'all' || state.devAlarmOnly ? '当前筛选条件下没有设备' : '该项目下暂无设备');
    if (!devEmpty){
      devEmpty = document.createElement('div');
      devEmpty.className = 'act-empty';
      devEmpty.style.cssText = 'text-align:center;padding:26px 0';
    }
    devEmpty.textContent = tip;
    if (devEmpty.parentNode !== list) list.appendChild(devEmpty);
  } else if (devEmpty && devEmpty.parentNode){
    devEmpty.remove();
  }
  if (rows.length && wide){
    /* 行都挂载完成后按内容重新分配列宽（表头与各行同步写入） */
    balanceDeviceColumns(list);
  }

  /* 副标题：总数 / 筛选命中数 */

  /* 连接轴计数：在线 = 所有在线设备（含在线告警），离线同理 */
  const dc = { all: data.devices.length, online: 0, offline: 0 };
  let alarmed = 0;
  data.devices.forEach(d => {
    dc[d.online ? 'online' : 'offline']++;
    if (devAlarmed(d)) alarmed++;
  });
  Array.prototype.forEach.call(document.querySelectorAll('#panel-devices .tab'), t => {
    const b = t.querySelector('b');
    if (b) b.textContent = dc[t.dataset.dev];
  });
  /* 告警轴计数：在线告警 + 离线失联 */
  const alarmBtn = document.getElementById('devAlarmOnly');
  if (alarmBtn){
    alarmBtn.setAttribute('aria-pressed', state.devAlarmOnly ? 'true' : 'false');
    const b = alarmBtn.querySelector('b');
    if (b) b.textContent = alarmed;
  }

  const info = document.getElementById('devPageInfo');
  if (info) info.textContent = '第 ' + state.devPage + ' / ' + pages + ' 页';
  const prev = document.getElementById('devPrev');
  const next = document.getElementById('devNext');
  if (prev) prev.disabled = state.devPage <= 1;
  if (next) next.disabled = state.devPage >= pages;
}

/* 通用搜索框绑定：输入即筛选，带清空按钮 */
/* bindSearch() 已移到公共层（多页面下别的页面也要用） */

/* 设备列表：模糊搜索 */
bindSearch('devSearch', 'devClear', value => {
  state.devQuery = value;
  state.devPage = 1;
  renderDevices(curData());
});

/* 告警中心搜索绑定 已移到 pages/alerts.js（属于该页的交互） */

/* 告警历史翻页绑定 已移到 pages/alerts.js（属于该页的交互） */

/* 设备列表翻页 */
(function(){
  const prev = document.getElementById('devPrev');
  const next = document.getElementById('devNext');
  if (!prev || !next) return;
  prev.addEventListener('click', () => {
    if (state.devPage <= 1) return;
    state.devPage--;
    renderDevices(curData());
  });
  next.addEventListener('click', () => {
    state.devPage++;
    renderDevices(curData());
  });
})();

/* 面板高度变化（窗口缩放 / 视图切换 / 布局回流）时重算可见条数。
   窗口拖拽会连续触发 resize，绝大多数帧的尺寸其实没变——尺寸没变就不重排，
   只重算需要跟着尺寸走的那一项（本页就是设备列表的可见条数）。 */
let listResizeTimer = null;
let lastListBox = '';
window.addEventListener('resize', () => {
  if (listResizeTimer) clearTimeout(listResizeTimer);
  listResizeTimer = setTimeout(() => {
    const list = document.getElementById('deviceList');
    if (!list) return;
    const box = Math.round(list.clientWidth) + 'x' + Math.round(list.clientHeight);
    if (box === lastListBox) return;
    lastListBox = box;
    renderDevices(curData());
  }, 160);
});

/* 连接轴筛选标签（沿用告警中心类型标签的样式） */
document.querySelectorAll('#panel-devices .tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('#panel-devices .tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    state.devFilter = tab.dataset.dev;
    state.devPage = 1;
    renderDevices(curData());
  });
});

/* 告警轴开关：只筛「有告警（含离线失联）/ 无告警」，与连接轴叠加生效 */
(function bindDeviceAlarmToggle(){
  const btn = document.getElementById('devAlarmOnly');
  if (!btn) return;
  btn.addEventListener('click', () => {
    state.devAlarmOnly = !state.devAlarmOnly;
    btn.setAttribute('aria-pressed', state.devAlarmOnly ? 'true' : 'false');
    state.devPage = 1;
    renderDevices(curData());
  });
})();

/* =========================================================
   9. 设备全屏页（完全覆盖设备列表区域 · 详情 / 指令 两个页签）
   ========================================================= */
const deviceView = document.getElementById('deviceView');
let activeDevice = null;      /* 当前查看的设备（操作记录按设备过滤） */
let dvTab = 'basic';          /* 当前页签：basic 基本信息 / report 数据报表 / control 指令控制 */

/* 设备列表（以及覆盖其上的设备详情页）只挂在「设备管理」视图里；
   运营总览中的列表是概览卡片，仅作展示 */
const DV_DETAIL_VIEWS = ['设备管理'];
/* DV_ALERT_VIEWS() 已移到公共层（多页面下别的页面也要用） */

/* activeViewName() 已移到公共层（多页面下别的页面也要用） */

function detailAllowed(){
  return DV_DETAIL_VIEWS.indexOf(activeViewName()) > -1;
}

/* alertClickable() 已移到公共层（多页面下别的页面也要用） */

/* 状态文案与取色统一走 6.0 的 devStateText / devToneColor：
   连接与告警是两条独立的轴，不再有「第三种状态」需要判断 */

/* 主题变量取到的可能是 #hex 或 rgb()，统一转成带透明度的 rgba */
function toRgba(c, a){
  const v = String(c || '').trim();
  if (v.charAt(0) === '#'){
    let h = v.slice(1);
    if (h.length === 3) h = h.split('').map(x => x + x).join('');
    const n = parseInt(h, 16);
    return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')';
  }
  const m = v.match(/[\d.]+/g);
  return m ? 'rgba(' + m[0] + ',' + m[1] + ',' + m[2] + ',' + a + ')' : v;
}

/* 卡头状态胶囊：文字 + 同色系半透明底 */
function setDvState(id, text, colorVar){
  const el = document.getElementById(id);
  if (!el) return;
  const c = cssVar(colorVar);
  el.textContent = text;
  el.style.color = c;
  el.style.background = 'color-mix(in srgb, ' + c + ' 15%, transparent)';
  el.style.borderColor = 'color-mix(in srgb, ' + c + ' 38%, transparent)';
}

/* hbText() 已移到公共层 api.js（地图页也要用） */

/* =========================================================
   9.1b 详情页的数据保鲜（实时值 + 定期刷新）
   —— 现状问题：详情页的数值只来自「打开那一刻」的内存快照，
      之后无论列表怎么刷新，详情页都不会变（数据看似"卡住了"）：
        · 点开时没有任何请求；
        · 列表那套 60s 项目刷新只重绘列表（renderAllViews → renderDevices），
          没有详情页的重绘钩子；
        · 而且每次项目刷新会用**新对象**重建 data.devices（字段是拷过去的），
          activeDevice 会因此"脱钩"，就算数据更新了也落不到详情页上。
      这里补齐三件事：
        ① 打开即拉一次该设备的实时 Tag（force 忽略列表那套 65s 新鲜度节流）；
        ② 停留在详情页期间每 60 秒续拉一次（设备周期上报 60s，1 次/分钟在平台限额内；
           周期 Tag 一个报文就带回 799/265/800/781/782 + 设备上报的经纬度 512/513）；
        ③ 实时队列把数据落地后回调 refreshOpenDetail() 自动重绘，画面跟着变。
   ========================================================= */
let dvLiveTimer = null;
const DV_LIVE_MS = 60000;

/* 列表刷新会重建设备对象：按 id 把 activeDevice 重新指回当前那份 */
function syncActiveDevice(){
  if (!activeDevice) return null;
  const list = (typeof curData === 'function' ? curData().devices : null) || [];
  const cur = list.find(x => x.id === activeDevice.id);
  if (cur && cur !== activeDevice) activeDevice = cur;
  return activeDevice;
}

/* 拉一次当前设备的实时值（force=true 时忽略 65s 新鲜度） */
function refreshOpenDevice(force){
  const d = syncActiveDevice();
  if (!d) return;
  if (typeof queueTags === 'function') queueTags([d.id], force !== false);
}

/* 供 api.js 的实时 Tag 队列在数据落地后回调：详情正开着这台设备就重绘 */
function refreshOpenDetail(id){
  if (!activeDevice || !deviceView || !deviceView.classList.contains('show')) return;
  if (id && activeDevice.id !== id) return;
  if (dvTab === 'report') return;      /* 报表页签重绘会重跑历史查询，不在这里自动打 */
  syncActiveDevice();
  renderDeviceView(dvTab);
}

function startDvLive(){
  stopDvLive();
  dvLiveTimer = setInterval(function(){
    if (document.hidden) return;                                    /* 后台不请求 */
    if (!deviceView || !deviceView.classList.contains('show')) return;
    refreshOpenDevice(true);
  }, DV_LIVE_MS);
}
function stopDvLive(){
  if (dvLiveTimer){ clearInterval(dvLiveTimer); dvLiveTimer = null; }
}

/* ---------- 打开 / 关闭 ---------- */
function openDeviceView(d, tab){
  if (!d || !deviceView){
    toastErr('打开设备详情失败：设备数据缺失');
    return;
  }
  activeDevice = d;
  renderDeviceView(tab || 'basic');
  deviceView.classList.add('show');
  /* 打开即现拉一次该设备的实时值，并开启停留期间的定期刷新（见 9.1b） */
  refreshOpenDevice(true);
  startDvLive();
}

function closeDeviceView(){
  if (!deviceView || !deviceView.classList.contains('show')) return;
  deviceView.classList.remove('show');
  stopDvLive();                       /* 详情关闭即停止定期刷新 */
}

/* ---------- 页签切换 ---------- */
const DV_PAGES = { basic:'dvPageBasic', report:'dvPageReport', control:'dvPageControl' };

function setDvTab(name){
  dvTab = DV_PAGES[name] ? name : 'basic';
  document.querySelectorAll('.dv-tab').forEach(t => {
    t.classList.toggle('active', t.dataset.dv === dvTab);
  });
  Object.keys(DV_PAGES).forEach(k => {
    const el = document.getElementById(DV_PAGES[k]);
    if (el) el.classList.toggle('hide', k !== dvTab);
  });
  const sc = deviceView && deviceView.querySelector('.dv-scroll');
  if (sc) sc.scrollTop = 0;
  /* 报表画布在隐藏容器里量不到尺寸，切到该页签时按当前条件重绘 */
  if (dvTab === 'report' && activeDevice) renderDvReport(activeDevice);
}

document.querySelectorAll('.dv-tab').forEach(t => {
  t.addEventListener('click', () => setDvTab(t.dataset.dv));
});
document.getElementById('dvBack').addEventListener('click', closeDeviceView);
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeDeviceView();
});

/* ---------- 整页渲染 ---------- */
function renderDeviceView(tab){
  const d = activeDevice;
  if (!d) return;
  setDvTab(tab || dvTab);

  document.getElementById('dvCrumb').textContent = d.id;
  document.getElementById('dvId').textContent = d.id;

  /* 胶囊同时表达两条轴：在线 · 无告警 / 在线 · 告警 / 离线 · 失联 */
  const badge = document.getElementById('dvStatus');
  const c = devToneColor(d);
  badge.textContent = devStateText(d);
  badge.style.color = c;
  badge.style.background = 'color-mix(in srgb, ' + c + ' 16%, transparent)';
  badge.style.borderColor = 'color-mix(in srgb, ' + c + ' 40%, transparent)';

  renderDvMetrics(d);
  renderDvKv(d);
  renderDvEvents(d);
  renderDvPower(d);
  renderDvPeriod(d);
  renderLog();
}

/* ---------- 指标卡 ----------
   四张卡按「数据性质」配不同控件，不再一律用进度条（进度条对枚举量/时间量没有意义）：
     · 实际电压 / 设定电压 —— 连续量：量程条（0 ~ VOLTAGE_MAX），
       并在条上标出另一路电压的位置，一眼看出"实际 vs 设定"的差
     · 工作状态 —— 枚举量：状态徽标（运行中 / 已关机 / 未同步），不用进度条
     · 最近上报 —— 时间量：完整「年月日时分秒」+ 新鲜度（距今多久 / 已失联） */
function renderDvMetrics(d){
  const box = document.getElementById('dvMetrics');
  if (!box) return;
  const off = !d.online;
  const MAX = App.config.BIZ.VOLTAGE_MAX || 6000;
  const pos = v => Math.max(0, Math.min(100, (Number(v) || 0) / MAX * 100));
  const loadV = Number(d.load) || 0, setV = Number(d.temp) || 0;
  const over = setV > 0 && loadV > setV;                   /* 实际高于设定：值得提醒 */
  const ws = d.workStatus;
  const stTone = ws === 1 ? 'ok' : (ws === 0 ? 'off' : (ws === 255 ? 'warn' : 'muted'));
  const stText = off ? '离线' : (App.utils.workStatusText(ws) || '--');
  const age = (typeof d.hbOffset === 'number') ? d.hbOffset : null;
  const freshTone = off ? 'off' : (age === null ? 'muted' : (age < 120 ? 'ok' : 'warn'));
  const freshText = off ? '已失联'
                  : (age === null ? '无上报记录'
                  : (age < 60 ? '刚刚上报（' + age + ' 秒前）' : hbText(age)));
  const icon = p => '<svg viewBox="0 0 24 24"><path d="' + p + '"/></svg>';

  /* 量程条：底轨铺满量程 + 当前值填充 + 另一路电压的刻度标记 */
  function gauge(value, other, tone, otherName){
    const mk = (!off && other > 0 && other <= MAX)
      ? '<u class="dv-gauge-mark" style="left:' + pos(other).toFixed(2) + '%" title="' +
          otherName + ' ' + Math.round(other) + ' V"></u>'
      : '';
    return '<div class="dv-gauge ' + (off ? 'is-off' : tone) + '">' +
             '<i class="dv-gauge-fill" style="width:' + (off ? 0 : pos(value)).toFixed(2) + '%"></i>' +
             mk +
           '</div>';
  }

  box.innerHTML = [
    /* ① 实际电压 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>实际电压</span>' + icon('M4 19h16M7 19V9M12 19V5M17 19v-6') + '</div>' +
      '<div class="dv-metric-value' + (over ? ' is-warn' : '') + '"><b>' + (off ? '--' : Math.round(loadV)) + '</b><em>V</em></div>' +
      gauge(loadV, setV, over ? 'warn' : 'ok', '设定') +
      '<div class="dv-metric-foot"><span>量程 0–' + MAX + ' V</span><span>' +
        (off ? 'Tag 799' : '设定 ' + Math.round(setV) + ' V') + '</span></div>' +
    '</div>',
    /* ② 设定电压 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>设定电压</span>' + icon('M12 3v10.6a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2z') + '</div>' +
      '<div class="dv-metric-value"><b>' + Math.round(setV) + '</b><em>V</em></div>' +
      gauge(setV, loadV, 'violet', '实际') +
      '<div class="dv-metric-foot"><span>量程 0–' + MAX + ' V</span><span>Tag 800</span></div>' +
    '</div>',
    /* ③ 工作状态 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>工作状态</span>' + icon('M12 2v3.5M12 18.5V22M4.2 4.2l2.5 2.5M17.3 17.3l2.5 2.5M2 12h3.5M18.5 12H22M4.2 19.8l2.5-2.5M17.3 6.7l2.5-2.5') + '</div>' +
      '<div class="dv-state ' + stTone + '"><i></i>' + stText + '</div>' +
      '<div class="dv-metric-foot"><span>Tag 265</span><span>1=开机 · 0=关机 · 255=未同步</span></div>' +
    '</div>',
    /* ④ 最近上报 */
    '<div class="dv-metric">' +
      '<div class="dv-metric-top"><span>最近上报</span>' + icon('M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 7.6V12l3 2') + '</div>' +
      '<div class="dv-metric-value is-time"><b>' + hbTimeText(d) + '</b></div>' +
      '<div class="dv-fresh ' + freshTone + '"><i></i>' + freshText + '</div>' +
      '<div class="dv-metric-foot"><span>Tag 799</span><span>周期 60s · 变化即时上报</span></div>' +
    '</div>'
  ].join('');
}

/* ---------- 设备参数 ---------- */
function renderDvKv(d){
  const box = document.getElementById('dvKv');
  if (!box) return;
  const prj = curProject();

  const rows = [
    ['所属项目', prj.name],
    ['项目编号', prj.code],
    ['设备型号', d.model],
    ['设备号 IMEI', d.id],
    ['ICCID', d.iccid !== undefined ? String(d.iccid) : '--'],
    ['安装位置', d.zone + ' · ' + d.area],
    ['接入协议', 'AirCloud · TCP 长连接'],
    /* Tag 781/782：设备端新增的联网方式与信号强度（统一 0~31 刻度） */
    ['联网方式', netTagText(d.netType)],
    ['信号强度', d.hasSignal ? (d.snr + '/31 · ' + qualityOf(d).text) : '未上报'],
    ['固件版本', d.version !== undefined ? String(d.version) : '--'],
    ['上报周期', d.period + ' s'],
    ['工作状态（265）', App.utils.workStatusText(d.workStatus)],
    ['连接状态', devConnText(d)],
    ['告警状态', devAlarmText(d)],
    ['开关机状态', d.power === 'off' ? '已关机（265=0）' : '已开机（265=1）'],
    /* 同上：给出实际上报时间；离线时补一句状态（失联设备更需要知道是什么时候断的） */
    ['最近上报', hbTimeText(d) + (d.online ? '' : ' · 已失联')]
  ];

  box.innerHTML = rows.map(r => '<div><span>' + r[0] + '</span><b>' + r[1] + '</b></div>').join('');
}

/* ---------- 相关事件 ---------- */
function renderDvEvents(d){
  const box = document.getElementById('dvEvents');
  if (!box) return;

  const evts = curData().alerts.filter(a => a.deviceId === d.id).slice(0, 10);
  const cnt = document.getElementById('dvEventCount');
  if (cnt) cnt.textContent = evts.length + ' 条';

  if (!evts.length){
    box.innerHTML = '<div class="act-empty">该设备近期无异常事件</div>';
    return;
  }
  box.innerHTML = evts.map(a =>
    '<div class="dv-event ' + a.level + '">' +
      '<div class="dv-event-main">' +
        '<div class="dv-event-title">' + a.title + '</div>' +
        '<div class="dv-event-meta">' + a.meta + '</div>' +
      '</div>' +
      '<span class="dv-event-time">' + timeText(a.ts) + '</span>' +
    '</div>'
  ).join('');
}

/* =========================================================
   9.1 功能块一：开关机控制
   —— 显示当前开关机状态，并提供开机 / 关机 / 重启三个动作
   ========================================================= */
/* 动作元信息：tone 决定按钮悬停配色，state 为执行后设备所处状态 */
const DV_ACTION_META = {
  '开机': { state:'on',  tone:'ok',     desc:'协议 265=1：启动电场发生器输出' },
  '关机': { state:'off', tone:'danger', desc:'协议 265=0：停止输出，云端链路保持' }
};

/* 开关机状态是独立的第三条维度：关机必然离线，但离线不等于关机
   （链路故障时设备仍在运行，所以不能拿连接状态反推电源状态） */
function powerStateOf(d){
  return d.power === 'off' ? 'off' : 'on';
}

function renderDvPower(d){
  const box = document.getElementById('dvPowerBtns');
  if (!box) return;

  const state = powerStateOf(d);
  const on = state === 'on';

  /* 卡头状态胶囊 */
  setDvState('dvPowerState', d.busy ? '指令执行中' : (on ? '已开机' : '已关机'),
             d.busy ? '--cyan' : (on ? '--green' : '--red'));

  const val = (id, text) => { const el = document.getElementById(id); if (el) el.textContent = text; };
  val('dvPowerLoad', on ? d.load + ' V' : '--');
  val('dvPowerTemp', (d.temp || 0) + ' V');
  val('dvPowerSnr', d.online ? (d.power === 'off' ? '已关机' : '运行中') : '未同步');
  val('dvPowerHb', d.online ? hbText(d.hbOffset) : '已失联');

  box.innerHTML = '';
  (d.actions || []).forEach(name => {
    const meta = DV_ACTION_META[name];
    if (!meta) return;
    const btn = document.createElement('button');
    btn.className = 'dv-act' + (meta.state === state ? ' current' : '');
    btn.dataset.tone = meta.tone;
    btn.dataset.action = name;
    btn.title = meta.desc;
    btn.textContent = name;
    btn.disabled = !!d.busy;
    btn.addEventListener('click', () => runPowerAction(d, name, btn));
    box.appendChild(btn);
  });
}

function runPowerAction(dev, action, btn){
  const data = curData();
  const d = data.devices.find(x => x.id === dev.id) || dev;

  if (d.busy){
    toastErr('操作失败：' + d.id + ' 正在执行其他指令，请稍后重试');
    return;
  }
  /* 关机需要链路在线（离线不一定是关机，提示要分清） */
  if (action !== '开机' && !d.online){
    const why = d.power === 'off' ? '设备已关机' : '设备离线（AirCloud 无最近上报）';
    logAction(d, action, false, why + '，指令未送达');
    renderLog();
    setDvExec('失败', why + '，指令未能送达', -1);
    toastErr('操作失败：' + d.id + ' ' + why + (d.power === 'off' ? '，请先开机' : '，请检查链路'));
    return;
  }

  setDvPowerBusy(true);
  if (btn) btn.classList.add('running');
  /* 真实下发：send_cmd tag=19（嵌套 265 工作状态） */
  sendControl(d, action, buildControlValue(action === '开机' ? 1 : 0, undefined), function(){
    applyPowerEffect(d, action);
  });
  setTimeout(function(){
    setDvPowerBusy(false);
    if (btn) btn.classList.remove('running');
    renderDevices(data);
    if (activeDevice && activeDevice.id === d.id) renderDeviceView(dvTab);
  }, 1800);
}

function setDvPowerBusy(busy){
  const box = document.getElementById('dvPowerBtns');
  if (box) box.querySelectorAll('.dv-act').forEach(b => { b.disabled = busy; });
}

function applyPowerEffect(d, action){
  if (action === '关机'){
    /* 关机（265=0）：停止电场输出，实际电压归零；云端链路保持在线 */
    d.power = 'off';
    d.alarm = 'none';
    d.load = 0;
    d.hbOffset = 5;
  } else {
    /* 开机（265=1）：启动输出，实际电压向设定值靠拢，告警解除 */
    d.power = 'on';
    d.online = true;
    d.alarm = 'none';
    d.load = d.temp || 0;
    d.hbOffset = 5;
  }
}

/* =========================================================
   9.2 功能块二：设定电压下发（Tag 800）
   —— 显示当前设定电压，可从预设中选择或直接输入，再下发
      （经 send_cmd tag=19 的嵌套子 TLV 下发到设备）
   ========================================================= */
const DV_PERIOD_PRESETS = [1000, 2000, 3500, 5000, 6000];

function renderDvPeriod(d){
  /* 卡头状态胶囊显示当前设定电压 */
  setDvState('dvPeriodState',
             d.busy ? '下发中…' : '当前 ' + (d.temp || 0) + ' V',
             d.busy ? '--cyan' : '--violet');

  /* 输入框与预设 chip 同步（正在输入时不覆盖用户输入） */
  const input = document.getElementById('dvPeriodInput');
  if (input && document.activeElement !== input) input.value = (d.temp || App.config.BIZ.DEFAULT_SET_VOLTAGE);
  syncPeriodChips();
}

function syncPeriodChips(){
  const input = document.getElementById('dvPeriodInput');
  const val = input ? Math.round(+input.value) : NaN;
  document.querySelectorAll('#dvPeriodChips .dv-chip').forEach(c => {
    c.classList.toggle('active', Math.round(+c.dataset.sec) === val);
  });
}

function setDvPeriodBusy(busy){
  const chips = document.getElementById('dvPeriodChips');
  const input = document.getElementById('dvPeriodInput');
  const apply = document.getElementById('dvPeriodApply');
  if (chips) chips.querySelectorAll('.dv-chip').forEach(c => { c.disabled = busy; });
  if (input) input.disabled = busy;
  if (apply) apply.disabled = busy;
}

/* 构造 tag=19「控制命令」的 value（协议 8.3.2 控制命令 / 10.2 下行 TLV 选用规则）
   —— 约定：value 是**顶层裸数组的 JSON 字符串**，数组元素形如
        [{"field_meaning":265,"data_type":0,"value":1}]
      · field_meaning：TLV 字段含义（265 工作状态 / 800 设定电压，均为「自主补充」字段）
      · data_type    ：0 = 整数
      · value        ：字段值（265：1=开机 / 0=关机；800：0~6000 V）
      设备端 protocol_app.handle_aircloud_msg 收到 Type=19 后，从 value 里取出
      field=265/800 的子项，发布 CTRL_CMD_RECV 交给 business_app 执行（再经 UART 下发给高压板）。
   —— 原来的写法是 { "265": 1 } 这种「以 tag 为键的对象」：平台按 Type=19 封装后，
      设备端拿到的 value 不是可解析的子 TLV（excloud 解不出 265/800），
      ctrl_fields 为空 → 设备收到但不执行（这正是"报文已下发但设备没动作"的原因）。
   —— 与合宙 excloud 扩展库 demo 约定一致（Air8782 泵控项目同写法，已实测可用）。 */
function buildControlValue(workStatus, setVoltage){
  const items = [];
  if (workStatus !== undefined && workStatus !== null){
    items.push({ field_meaning: App.config.TAGS.WORK_STATUS, data_type: 0, value: workStatus });
  }
  if (setVoltage !== undefined && setVoltage !== null){
    items.push({ field_meaning: App.config.TAGS.SET_VOLTAGE, data_type: 0, value: setVoltage });
  }
  return JSON.stringify(items);
}

/* 真实下发控制命令（send_cmd），统一走执行监控与操作记录 */
function sendControl(d, label, value, onOk, tag){
  const data = curData();
  if (!d.online){
    const why = '设备离线（AirCloud 无最近上报）';
    logAction(d, label, false, why + '，指令未送达');
    renderLog();
    setDvExec('失败', why, -1);
    toastErr('下发失败：' + d.id + ' ' + why);
    return Promise.resolve();
  }
  setDvExec('执行中', '正在下发「' + label + '」…', 0);
  return App.http.post(App.config.API.SEND_CMD, {
    client_id: d.id,
    tag: (tag === undefined ? App.config.BIZ.CONTROL_TAG : tag),
    value: value,
    protocol: 0
  }).then(function(res){
    if (onOk) onOk();
    const r = (res && typeof res.value === 'string') ? res.value : '操作成功';
    logAction(d, label, true, r);
    setDvExec('已完成', '「' + label + '」已下发（平台已受理）', 100);
    toast(label + '：' + r);
    renderDevices(data);
  }).catch(function(e){
    logAction(d, label, false, e.message);
    setDvExec('失败', e.message, -1);
    toastErr('下发失败：' + e.message);
  }).then(function(){
    if (activeDevice && activeDevice.id === d.id) renderDeviceView(dvTab);
  });
}

function runPeriodApply(value){
  const dev = activeDevice;
  if (!dev){ toastErr('下发失败：未选择设备'); return; }

  const data = curData();
  const d = data.devices.find(x => x.id === dev.id) || dev;

  if (d.busy){
    toastErr('操作失败：' + d.id + ' 正在执行其他指令，请稍后重试');
    return;
  }
  if (value < App.config.BIZ.VOLTAGE_MIN || value > App.config.BIZ.VOLTAGE_MAX){
    toastErr('下发失败：设定电压需在 0 ~ 6000 V 之间');
    return;
  }
  if (value === d.temp){
    toastErr('下发失败：' + value + ' V 与当前设定电压相同');
    return;
  }

  d.busy = true;
  setDvPeriodBusy(true);
  sendControl(d, '设定电压 ' + value + 'V', buildControlValue(undefined, value), function(){
    d.temp = value;
    if (d.power === 'on') d.load = value;
  });
  setTimeout(function(){
    d.busy = false;
    setDvPeriodBusy(false);
    renderDevices(data);
    if (activeDevice && activeDevice.id === d.id) renderDeviceView(dvTab);
  }, 1800);
}

/* =========================================================
   9.3 / 9.4 已按需求删除
   —— 原「设备信息」块（IMEI / ICCID / 版本 / 云端连接 展示）与
      「运维日志上报」块（send_cmd tag=25 通知设备上传日志）一并移除。
   —— 说明两点，避免以后重复踩：
      · 设备身份信息仍可在「基本信息」页签的详细信息里看到（ICCID/版本/IMEI 都在）；
      · 平台的「通知设备上传日志」信令是 tag=22，不是 25（见接口文档 send_cmd 支持的
        Tag：19 控制命令 / 21 iRTU / 1281 自定义 / 22 通知上传日志），原实现用错了。
   ========================================================= */

/* =========================================================
   9.5 执行监控（仅「指令下发」「回执确认」两个阶段）
   ========================================================= */
const DV_STEP_COUNT = 2;

function setDvExec(state, sub, pct){
  setDvState('dvExecState', state,
             pct < 0 ? '--red' : pct >= 100 ? '--green' : pct > 0 ? '--cyan' : '--muted');
  const sub2 = document.getElementById('dvExecSub');
  if (sub2) sub2.textContent = sub;

  const failed = pct < 0;
  const prog = document.getElementById('dvProgress');
  const bar = document.getElementById('dvBar');
  const pctEl = document.getElementById('dvBarPct');
  if (prog) prog.classList.toggle('fail', failed);
  if (bar) bar.style.width = (failed ? 100 : pct) + '%';
  if (pctEl) pctEl.textContent = failed ? '失败' : pct + '%';

  /* 两个阶段：已过阶段点亮、当前阶段高亮 */
  const steps = document.getElementById('dvSteps');
  if (!steps) return;
  const idx = failed ? -1 : Math.min(DV_STEP_COUNT - 1, Math.floor(pct / (100 / DV_STEP_COUNT)));
  Array.from(steps.children).forEach((el, k) => {
    el.classList.toggle('done', !failed && (pct >= 100 || k < idx));
    el.classList.toggle('active', !failed && pct < 100 && k === idx);
  });
}

function runDvProgress(label, onDone){
  const total = 1300, t0 = performance.now();
  function tick(t){
    const p = Math.min((t - t0) / total, 1);
    setDvExec('执行中', '正在下发「' + label + '」…', Math.round(p * 100));
    if (p < 1) requestAnimationFrame(tick);
    else onDone();
  }
  requestAnimationFrame(tick);
}

/* =========================================================
   9.6 操作记录
   ========================================================= */
function nowText(){
  const d = new Date(), p = n => String(n).padStart(2, '0');
  return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

function logAction(d, action, ok, note){
  actionLog.unshift({ deviceId: d.id, name: d.name, action: action, ok: ok, note: note, time: nowText() });
  if (actionLog.length > 40) actionLog.pop();
}

function renderLog(){
  const box = document.getElementById('dvLog');
  if (!box) return;
  const rows = actionLog.filter(r => activeDevice && r.deviceId === activeDevice.id);
  const cnt = document.getElementById('dvLogCount');
  if (cnt) cnt.textContent = rows.length + ' 条';

  box.innerHTML = '';
  if (!rows.length){
    box.innerHTML = '<div class="act-empty">暂无操作记录，在上方功能块中下发指令后会记录在此</div>';
    return;
  }
  rows.slice(0, 20).forEach(r => {
    const el = document.createElement('div');
    el.className = 'act-line' + (r.ok ? '' : ' fail');
    el.innerHTML =
      '<span>' + r.time + '</span>' +
      '<b>' + r.action + '</b>' +
      '<span class="act-note">' + r.note + '</span>';
    box.appendChild(el);
  });
}

/* =========================================================
   9.7 实时趋势曲线
   ========================================================= */
/* =========================================================
   9.7 折线图鼠标读数（十字线 + 数值气泡）
   —— 数据报表四张历史曲线用：鼠标移到图上 → 竖向虚线 + 采样点圆点 + 读数气泡
   —— 气泡用 DOM 而不是 canvas 文字：排版交给浏览器，样式好统一
   —— 画布 X 轴是「等距采样点」，鼠标 x 反解成最近下标即可
   —— 画布每次查询都会重建，所以监听器用事件委托挂在容器上
   ========================================================= */
/* 惰性创建气泡元素（挂在绘图区外层，外层需 position:relative） */
/* 画布内边距：绘图（drawDvChart）与鼠标读数的坐标反解共用这一处定义。
   —— 它原先定义在已删除的「实际电压趋势」代码块里，删掉后本文件就只剩引用、
      没有定义 → drawDvChart 一进函数就抛 ReferenceError，四张图全空白；
      而表格是在 requestAnimationFrame(绘图) 之前渲染的，所以表格照常有数据。 */
const RP_PAD = { l: 38, r: 12, t: 12, b: 22 };

function dvTipEl(box){
  if (!box) return null;
  for (const c of box.children) if (c.classList && c.classList.contains('dv-tip')) return c;
  const el = document.createElement('div');
  el.className = 'dv-tip';
  box.appendChild(el);
  return el;
}
/* 显示气泡：默认在光标右上，贴边自动翻转/收边，保证不出框 */
function dvTipShow(box, tip, x, y, html){
  if (!box || !tip) return;
  tip.innerHTML = html;
  tip.style.display = 'block';
  const bw = tip.offsetWidth, bh = tip.offsetHeight;
  const W = box.clientWidth, H = box.clientHeight;
  let left = x + 14, top = y - bh - 12;
  if (left + bw > W - 4) left = x - bw - 14;
  if (left < 4) left = 4;
  if (top < 4) top = y + 16;
  if (top + bh > H - 4) top = Math.max(4, H - bh - 4);
  tip.style.left = Math.round(left) + 'px';
  tip.style.top = Math.round(top) + 'px';
}
function dvTipHide(tip){ if (tip) tip.style.display = 'none'; }

/* 数据报表四张曲线：画布每次查询都会重建，所以用事件委托挂在容器上
   （mouseout 会冒泡，mouseleave 不会，故用 mouseout + relatedTarget 判断） */
(function bindRpChartHover(){
  const box = document.getElementById('rpCharts');
  if (!box) return;
  const canvasOf = e => (e.target && e.target.tagName === 'CANVAS' && e.target.dataset.chart !== undefined) ? e.target : null;
  const repaint = cvs => {
    const card = DV_REPORT_CARDS[+cvs.dataset.chart];
    if (card) drawDvChart(cvs, card);
  };
  box.addEventListener('mousemove', function(e){
    const cvs = canvasOf(e);
    if (!cvs || !dvReport) return;
    const n = dvReport.times.length;
    const r = cvs.getBoundingClientRect();
    const plotW = r.width - RP_PAD.l - RP_PAD.r;
    if (n < 2 || plotW <= 0) return;
    /* 与 drawDvChart 里的 X(i) = padL + i/(n-1)*plotW 互为反解 */
    const i = Math.round((e.clientX - r.left - RP_PAD.l) / plotW * (n - 1));
    const idx = Math.max(0, Math.min(n - 1, i));
    const y = e.clientY - r.top;
    if (idx !== cvs.__hover || Math.abs((cvs.__hoverY || 0) - y) > 2){
      cvs.__hover = idx; cvs.__hoverY = y;
      repaint(cvs);
    }
  });
  box.addEventListener('mouseout', function(e){
    const cvs = canvasOf(e);
    if (!cvs) return;
    const to = e.relatedTarget;
    if (to && cvs.contains(to)) return;          /* 仍在画布内（子节点间移动）不算离开 */
    if (typeof cvs.__hover !== 'number' || cvs.__hover < 0) return;
    cvs.__hover = -1;
    repaint(cvs);
  });
})();


/* =========================================================
   9.8 上报周期的选择与输入控件
   ========================================================= */
(function bindDvPeriod(){
  const chips = document.getElementById('dvPeriodChips');
  const input = document.getElementById('dvPeriodInput');
  const apply = document.getElementById('dvPeriodApply');
  if (!chips || !input || !apply) return;

  /* 预设值 chip：选中即填入输入框 */
  chips.innerHTML = DV_PERIOD_PRESETS.map(s =>
    '<button class="dv-chip" data-sec="' + s + '">' + s + ' V</button>').join('');

  chips.addEventListener('click', e => {
    const chip = e.target.closest('.dv-chip');
    if (!chip) return;
    input.value = chip.dataset.sec;
    syncPeriodChips();
  });

  input.addEventListener('input', syncPeriodChips);

  apply.addEventListener('click', () => {
    const v = Math.round(+input.value);
    if (isNaN(v) || v < App.config.BIZ.VOLTAGE_MIN || v > App.config.BIZ.VOLTAGE_MAX){
      toastErr('下发失败：设定电压需在 0 ~ 6000 V 之间');
      return;
    }
    runPeriodApply(v);
  });
})();

/* =========================================================
   9.5 数据报表（时间段查询 · 折线趋势 · 明细表）
   —— 全部为 list_by_tags 的真实历史记录：一条上报纸文 = 一个点，
      不做采样降频、不补点、不插值/合成；某条记录缺某个 Tag 时该点为空，
      曲线在这一段断开（如实呈现），明细表也只列真实上报过的时刻
   ========================================================= */
const DV_RANGES = {
  '1h':  { span: 3600000,   label: '近 1 小时' },
  '6h':  { span: 21600000,  label: '近 6 小时' },
  '24h': { span: 86400000,  label: '近 24 小时' },
  '7d':  { span: 604800000, label: '近 7 天' }
};

/* 报表卡片：一张图可叠多条同量纲曲线（与参考图一致） */
/* 报表卡片：全部由 list_by_tags 的真实历史记录绘制（无合成曲线）
   —— 信号强度（Tag 782）是统一 0~31 刻度，按当条记录的联网方式（Tag 781）拆成两张图：
      4G 期间的上报进「4G 信号强度」，WiFi 期间的上报进「WiFi 信号强度」，
      另一条链路就是断点（不插值、不混画）
   —— 上报间隔不再单独出图（数值仍在下方明细表与 CSV 里） */
const DV_REPORT_CARDS = [
  { title:'电压', sub:'实际电压(799) / 设定电压(800) · 单位 V', floor:0, series:[
      { label:'实际电压', color:'--cyan',   key:'load', unit:' V' },
      { label:'设定电压', color:'--violet', key:'temp', unit:' V' } ] },
  { title:'工作状态', sub:'Tag 265 · 1=开机 / 0=关机 / 255=未同步', floor:0, series:[
      { label:'工作状态', color:'--green',  key:'work', fmt:function(v){ return workLabel(v); } } ] },
  { title:'4G 信号强度', sub:'Tag 782 · 统一 0~31 刻度（4G=CSQ 原值）· 仅统计 4G 期间的上报', floor:0, emptyText:'4G 信号', series:[
      { key:'sig4', label:'4G 信号（CSQ）', color:'--cyan' } ] },
  { title:'WiFi 信号强度', sub:'Tag 782 · 统一 0~31 刻度（WiFi=RSSI 折算）· 仅统计 WiFi 期间的上报', floor:0, emptyText:'WiFi 信号', series:[
      { key:'sigwifi', label:'WiFi 信号', color:'--violet' } ] }
];

let dvRange = '6h';         /* 当前区间：预设键，或 custom（自定义） */
let dvFrom = 0, dvTo = 0;   /* 自定义区间起止时间戳 */
let dvReport = null;        /* 当前查询结果：表格与导出共用 */

/* ---------- 确定性噪声 ---------- */
function dvHashAt(seed, i){
  let h = (seed ^ 0x9e3779b9) >>> 0;
  h = Math.imul(h ^ (i | 0), 0x85ebca6b) >>> 0;
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h ^= h >>> 16;
  return (h >>> 8) / 8388608 - 1;      /* -1 ~ 1 */
}
function dvOctave(seed, x){
  const i = Math.floor(x), f = x - i;
  const a = dvHashAt(seed, i), b = dvHashAt(seed, i + 1);
  const u = f * f * (3 - 2 * f);       /* 平滑插值，避免折线出现锯齿拐点 */
  return a + (b - a) * u;
}
function dvNoise(seed, x){
  return dvOctave(seed, x) * .68 + dvOctave(seed + 977, x * 3.1) * .32;
}
const dvClamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

/* ---------- 真实历史数据（list_by_tags） ---------- */
function dvFetchHistory(d, from, to, tags, size){
  const filter = {
    aks: ['ct', 'ct'], acs: ['ge', 'le'],
    avs: [App.utils.formatLocalParam(from), App.utils.formatLocalParam(to)]
  };
  /* 走全局限频闸门：报表查询与 App 自身的 Tag 查询共用一条队列，
     平台规则是"查询频率 ≈ 上报频率"，两条查询挨着发必然被拒（实测报"请求过于频繁"）。
     闸门内自带同设备 15s 间隔与"频繁"自动退避重试，因此这里只会慢一点、不会失败 */
  return scheduleTagQuery(d.id, function(){
    return apiTags(d.id, tags, 1, size || 100, filter);
  }).then(function(res){
    const v = res.value || {};
    return {
      total: Number(v.total || 0),
      records: Array.isArray(v.records) ? v.records : []      /* 接口按 ct 降序返回 */
    };
  });
}

/* 直接用查询回来的真实记录出点：一条上报纸文 = 一个点。
   —— 不按采样间隔落桶、不补点、不做插值/合成：查询条件给多宽就覆盖多宽，
      "有多少是多少"；某条记录缺某个 Tag 时该点为空，曲线在此断开。
   —— 因为点与记录一一对应，明细表自然只会出现真实上报过的时刻（不再有空行）。 */
function dvBuildReportFromRecords(records, from, to){
  const sorted = records.slice().sort(function(a, b){
    return (App.utils.parseLocal(a.ct) || 0) - (App.utils.parseLocal(b.ct) || 0);
  });

  const times = [], load = [], temp = [], work = [], hb = [],
        net = [], sig = [], sig4 = [], sigwifi = [];

  let prevTs = null;
  sorted.forEach(function(rec){
    const ts = App.utils.parseLocal(rec.ct);
    if (!ts || ts < from || ts > to) return;

    const v7 = Number(rec['val_' + App.config.TAGS.VOLTAGE]);
    const v8 = Number(rec['val_' + App.config.TAGS.SET_VOLTAGE]);
    const v2 = Number(rec['val_' + App.config.TAGS.WORK_STATUS]);
    const vNet = Number(rec['val_' + App.config.TAGS.NETWORK_TYPE]);
    const vSig = Number(rec['val_' + App.config.TAGS.SIGNAL]);

    times.push(ts);
    load.push(isFinite(v7) ? v7 : null);
    temp.push(isFinite(v8) ? v8 : null);
    work.push(isFinite(v2) ? v2 : null);
    net.push(isFinite(vNet) ? vNet : null);
    sig.push(isFinite(vSig) ? vSig : null);
    /* 信号强度(782) 是统一 0~31 刻度，按该条记录实际走的链路（781）归到对应曲线：
       4G(1) 进「4G 信号强度」，WiFi(2) 进「WiFi 信号强度」，其它链路/未上报留空；
       4G 的 99（无信号/不可测）不进曲线，避免把纵轴拉到 99 */
    sig4.push((vNet === 1 && vSig >= 0 && vSig < 99) ? vSig : null);
    sigwifi.push((vNet === 2 && vSig >= 0 && vSig <= 31) ? vSig : null);
    /* 上报间隔 = 相邻两条真实记录的时间差 */
    hb.push(prevTs ? Math.round((ts - prevTs) / 1000) : null);
    prevTs = ts;
  });

  return {
    times: times,
    count: times.length,
    /* 最后一条真实记录时刻（明细表/CSV 的状态列用） */
    failAt: times.length ? times[times.length - 1] : 0,
    series: { load: load, temp: temp, work: work, hb: hb, net: net, sig: sig, sig4: sig4, sigwifi: sigwifi }
  };
}

/* dv2() 已移到公共层（多页面下别的页面也要用） */
/* dvDT() 在公共层 utils.js（系统设置页也要用） */

function dvFull(ts){
  const d = new Date(ts);
  return d.getFullYear() + '-' + dvDT(ts) + ':' + dv2(d.getSeconds());
}
function dvLocalInput(ts){
  const d = new Date(ts);
  return d.getFullYear() + '-' + dv2(d.getMonth() + 1) + '-' + dv2(d.getDate()) +
         'T' + dv2(d.getHours()) + ':' + dv2(d.getMinutes());
}

/* ---------- 报表渲染 ---------- */
function renderDvReport(d){
  const charts = document.getElementById('rpCharts');
  if (!charts || !d) return;

  const now = Date.now();
  let from, to, label;
  if (dvRange === 'custom'){
    from = dvFrom; to = dvTo; label = '自定义区间';
  } else {
    const cfg = DV_RANGES[dvRange] || DV_RANGES['6h'];
    to = now; from = now - cfg.span; label = cfg.label;
  }

  dvReport = null;

  /* 先建骨架：画布尺寸依赖布局，等下一帧再绘制 */
  charts.innerHTML = DV_REPORT_CARDS.map((c, i) =>
    '<div class="rp-card">' +
      '<div class="rp-card-head"><h4>' + c.title + '</h4><span>' + c.sub + '</span></div>' +
      '<div class="rp-legend">' + c.series.map(s =>
        '<span><i style="--c:' + cssVar(s.color) + '"></i>' + s.label + '</span>').join('') + '</div>' +
      '<div class="rp-plot"><canvas data-chart="' + i + '"></canvas></div>' +
    '</div>').join('');

  const meta = document.getElementById('rpMeta');
  if (meta){
    meta.textContent = d.id + ' · ' + dvDT(from) + ' ~ ' + dvDT(to);
  }

  const body = document.getElementById('rpBody');
  if (body) body.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:18px 0">正在查询真实历史数据…</td></tr>';
  const cnt = document.getElementById('rpCount');
  if (cnt) cnt.textContent = '查询中…';
  const tsub = document.getElementById('rpTableSub');
  if (tsub) tsub.textContent = label + ' · 正在查询 AirCloud 历史记录…';

  /* 真实查询：区间内取最近 100 条原始记录
     —— 100 就是平台限额（接口文档：size 建议在 [0,100] 内），有多少取多少，
        区间记录数超过限额时按限额取最近 100 条展示，不再为了"凑点数"做采样降频。
     —— 一并取联网方式(781)与信号强度(782)：它们是同一条上报纸文里的字段，
        并进这次查询不会增加请求次数（平台限频要求查询频率≈上报频率） */
  dvFetchHistory(d, from, to, [App.config.TAGS.VOLTAGE, App.config.TAGS.SET_VOLTAGE, App.config.TAGS.WORK_STATUS,
    App.config.TAGS.NETWORK_TYPE, App.config.TAGS.SIGNAL], 100)
    .then(function(h){
      dvReport = dvBuildReportFromRecords(h.records, from, to);
      dvReport.total = h.total;
      if (cnt) cnt.textContent = h.records.length + ' 条实际上报（区间共 ' + h.total + ' 条）';
      if (tsub){
        tsub.textContent = label + ' · 最新在上 · 区间共 ' + h.total + ' 条，本次取回最近 ' + h.records.length + ' 条' +
          (h.total > h.records.length ? '（接口单页上限 100 条）' : '');
      }
      renderDvTable();
      requestAnimationFrame(drawDvCharts);
    })
    .catch(function(e){
      const msg = (e && e.message) ? e.message : '未知错误';
      toastErr('历史数据查询失败：' + msg);
      if (cnt) cnt.textContent = '查询失败';
      if (tsub) tsub.textContent = label + ' · 查询失败：' + msg;
      if (body) body.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:18px 0">查询失败：' + msg + '</td></tr>';
    });
}

/* ---------- 明细表（全部为真实记录落桶结果） ---------- */
function workLabel(v){
  if (v === 1 || v === '1') return '开机';
  if (v === 0 || v === '0') return '关机';
  if (v === 255 || v === '255') return '未同步';
  return String(v);
}
function renderDvTable(){
  const body = document.getElementById('rpBody');
  if (!body || !dvReport) return;
  const { times, series } = dvReport;

  /* 一行 = 一条真实上报纸文：不再有「无上报」的空行占位（表里出现的就是上报过的时刻） */
  if (!times.length){
    body.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:18px 0">该查询区间内没有任何上报记录</td></tr>';
    return;
  }

  const rows = [];
  for (let i = times.length - 1; i >= 0; i--){      /* 最新在上 */
    const t = times[i];
    const voltage = series.load[i], setV = series.temp[i], work = series.work[i], hb = series.hb[i];
    const netV = series.net[i], sigV = series.sig[i];
    const warn = (voltage != null && voltage > 5500) || (setV != null && setV > 5000);
    rows.push('<tr>' +
      '<td>' + dvDT(t) + '</td>' +
      '<td>' + (voltage == null ? '--' : Math.round(voltage) + ' V') + '</td>' +
      '<td>' + (setV == null ? '--' : Math.round(setV) + ' V') + '</td>' +
      '<td>' + (work == null ? '--' : workLabel(work)) + '</td>' +
      /* 联网方式 + 信号强度：同一条记录里的 Tag 781/782（信号带档位词） */
      '<td>' + (netV == null ? '--' : netTagText(netV)) + '</td>' +
      '<td>' + (sigV == null ? '--' : (sigV + '/31 · ' + signalLevelText(netV, sigV))) + '</td>' +
      '<td>' + (hb == null ? '--' : hb + ' s') + '</td>' +
      '<td><span class="rp-st ' + (warn ? 'alarm' : 'ok') + '">' +
        (warn ? '已上报 · 告警' : '已上报 · 正常') + '</span></td>' +
    '</tr>');
  }
  body.innerHTML = rows.join('');
}

/* ---------- 趋势图 ---------- */
function drawDvCharts(){
  if (!dvReport) return;
  document.querySelectorAll('#rpCharts canvas').forEach(cvs => {
    const card = DV_REPORT_CARDS[+cvs.dataset.chart];
    if (card) drawDvChart(cvs, card);
  });
}

function drawDvChart(cvs, card){
  const r = cvs.getBoundingClientRect();
  if (!r.width || !r.height) return;          /* 页签隐藏时量不到尺寸，等可见后再画 */
  const ctx = cvs.getContext('2d');
  const dpr = Math.min(devicePixelRatio || 1, 2);
  cvs.width = Math.round(r.width * dpr);
  cvs.height = Math.round(r.height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  const W = r.width, H = r.height;
  /* 内边距与鼠标读数的坐标反解共用一套（见 RP_PAD），避免两处各写一份 */
  const padL = RP_PAD.l, padR = RP_PAD.r, padT = RP_PAD.t, padB = RP_PAD.b;
  const plotW = W - padL - padR, plotH = H - padT - padB;
  const times = dvReport.times, series = dvReport.series;

  /* 同一张图共用一套刻度：取所有曲线的取值范围 */
  let lo = Infinity, hi = -Infinity;
  card.series.forEach(s => {
    series[s.key].forEach(v => {
      if (v == null) return;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    });
  });
  if (!isFinite(lo)){
    /* 该区间没有任何可用样本（例如设备全程走 WiFi，4G 信号图就一个点都没有）：
       明确写出来，而不是画一张空网格让人以为图坏了 */
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = cssVar('--muted');
    ctx.font = '12px -apple-system,system-ui,sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('该区间内没有' + (card.emptyText || '') + '上报记录', W / 2, H / 2);
    dvTipHide(dvTipEl(cvs.parentElement));      /* 数据变空时别留着上一次的读数 */
    return;
  }
  const pad = (hi - lo) * .15 || 1;
  lo = lo - pad;
  hi = hi + pad;
  if (card.floor != null) lo = Math.max(card.floor, lo);
  if (hi - lo < 1e-6) hi = lo + 1;

  const X = i => padL + (times.length <= 1 ? plotW / 2 : (i / (times.length - 1)) * plotW);
  const Y = v => padT + plotH - ((v - lo) / (hi - lo)) * plotH;

  ctx.clearRect(0, 0, W, H);
  ctx.font = '10px ui-monospace,Consolas,monospace';

  /* 横向网格 + Y 轴刻度 */
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';
  ctx.strokeStyle = cssVar('--chart-grid');
  ctx.fillStyle = cssVar('--muted');
  ctx.lineWidth = 1;
  for (let k = 0; k <= 4; k++){
    const v = lo + (hi - lo) * k / 4;
    const y = Math.round(Y(v)) + .5;
    ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(W - padR, y); ctx.stroke();
    ctx.fillText(dvTick(v), padL - 7, y);
  }

  /* X 轴时间刻度 */
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  const stride = Math.max(1, Math.round((times.length - 1) / 5));
  for (let i = 0; i < times.length; i += stride){
    ctx.fillText(dvDT(times[i]), X(i), padT + plotH + 7);
  }
  ctx.textAlign = 'right';
  ctx.fillText(dvDT(times[times.length - 1]), W - padR, padT + plotH + 7);

  /* 每条曲线：渐变面积 + 发光折线；null 处断开 */
  card.series.forEach(s => {
    const color = cssVar(s.color);
    const vals = series[s.key];

    const segs = [];
    let cur = null;
    vals.forEach((v, i) => {
      if (v == null){ cur = null; return; }
      if (!cur){ cur = []; segs.push(cur); }
      cur.push([X(i), Y(v)]);
    });

    segs.forEach(pts => {
      const base = padT + plotH;

      if (pts.length > 1){
        const g = ctx.createLinearGradient(0, padT, 0, base);
        g.addColorStop(0, toRgba(color, .28));
        g.addColorStop(1, toRgba(color, 0));
        ctx.beginPath();
        pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]));
        ctx.lineTo(pts[pts.length - 1][0], base);
        ctx.lineTo(pts[0][0], base);
        ctx.closePath();
        ctx.fillStyle = g;
        ctx.fill();
      }

      ctx.beginPath();
      pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]));
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.7;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.shadowBlur = 8;
      ctx.shadowColor = toRgba(color, .7);
      ctx.stroke();
      ctx.shadowBlur = 0;

      /* 末端光点：单点段也画，避免曲线在末端突然消失 */
      const lastP = pts[pts.length - 1];
      ctx.beginPath();
      ctx.arc(lastP[0], lastP[1], 2.6, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
    });
  });

  /* ---- 鼠标读数：竖向虚线 + 各曲线在该时刻的采样点 + 读数气泡 ---- */
  const tip = dvTipEl(cvs.parentElement);
  const hvI = (typeof cvs.__hover === 'number') ? cvs.__hover : -1;
  if (hvI < 0 || hvI >= times.length){
    dvTipHide(tip);
    return;
  }
  const hx = X(hvI);
  ctx.strokeStyle = cssVar('--line-strong');
  ctx.lineWidth = 1;
  ctx.setLineDash([4, 4]);
  ctx.beginPath(); ctx.moveTo(hx, padT); ctx.lineTo(hx, padT + plotH); ctx.stroke();
  ctx.setLineDash([]);

  let html = '<div class="t-time">' + dvFull(times[hvI]) + '</div>';
  card.series.forEach(s => {
    const v = series[s.key][hvI];
    const color = cssVar(s.color);
    if (v == null){
      html += '<div><i style="background:' + color + ';opacity:.35"></i><em>' + s.label + ' 该时刻无上报</em></div>';
      return;
    }
    const txt = s.fmt ? s.fmt(v) : (Math.round(v * 100) / 100) + (s.unit || '');
    html += '<div><i style="background:' + color + '"></i>' + s.label + ' <b>' + txt + '</b></div>';
    const py = Y(v);
    ctx.beginPath(); ctx.arc(hx, py, 6, 0, Math.PI * 2);
    ctx.fillStyle = toRgba(color, .25); ctx.fill();
    ctx.beginPath(); ctx.arc(hx, py, 3, 0, Math.PI * 2);
    ctx.fillStyle = color; ctx.fill();
  });
  dvTipShow(cvs.parentElement, tip, cvs.offsetLeft + hx, cvs.offsetTop + (cvs.__hoverY || (padT + plotH / 2)), html);
}

/* Y 轴刻度文案：大数少留小数，小数保留一位 */
function dvTick(v){
  const a = Math.abs(v);
  if (a >= 1000) return (v / 1000).toFixed(1) + 'k';
  if (a >= 100) return Math.round(v) + '';
  return v.toFixed(1);
}

/* ---------- 导出 ---------- */
function exportDvCsv(){
  if (!dvReport || !activeDevice) return;
  const { times, series, failAt } = dvReport;

  /* 列与明细表保持一致；数值一律走空值安全输出
     （原实现误用 series.snr[i].toFixed()，而 series 里从来没有 snr → 导出会抛错） */
  const num = v => (v == null ? '' : v.toFixed(0));
  const lines = times.map((t, i) => {
    const off = t > failAt;
    const warn = !off && ((series.load[i] || 0) > 5500 || (series.temp[i] || 0) > 5000);
    const netV = series.net[i], sigV = series.sig[i];
    return [dvFull(t),
      num(series.load[i]), num(series.temp[i]),
      series.work[i] == null ? '' : workLabel(series.work[i]),
      netV == null ? '' : netTagText(netV),
      sigV == null ? '' : sigV,
      num(series.hb[i]),
      off ? '离线·失联' : warn ? '在线·告警' : '在线·正常'].join(',');
  });

  const csv = '时间,实际电压(V),设定电压(V),工作状态,联网方式,信号强度(0~31),上报间隔(s),状态\n' + lines.join('\n');
  try {
    const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = activeDevice.id + '_' + dvDT(Date.now()).replace(/[ :]/g, '') + '.csv';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  } catch (e){
    toastErr('导出失败：当前环境不支持文件下载');
  }
}

(function bindDvReport(){
  const seg = document.getElementById('rpSeg');
  const fromEl = document.getElementById('rpFrom');
  const toEl = document.getElementById('rpTo');
  const query = document.getElementById('rpQuery');
  const exp = document.getElementById('rpExport');
  if (!seg || !fromEl || !toEl || !query || !exp) return;

  /* 自定义区间默认给「近 6 小时」，与默认预设一致 */
  dvTo = Date.now();
  dvFrom = dvTo - DV_RANGES['6h'].span;
  fromEl.value = dvLocalInput(dvFrom);
  toEl.value = dvLocalInput(dvTo);

  const setActive = key => {
    seg.querySelectorAll('button[data-range]').forEach(b => b.classList.toggle('active', b.dataset.range === key));
  };

  seg.addEventListener('click', e => {
    const b = e.target.closest('button[data-range]');
    if (!b) return;
    dvRange = b.dataset.range;
    setActive(dvRange);
    if (activeDevice) renderDvReport(activeDevice);
  });

  query.addEventListener('click', () => {
    const f = Date.parse(fromEl.value);
    const t = Date.parse(toEl.value);
    if (!f || !t){ toastErr('查询失败：请选择完整的起止时间'); return; }
    if (f >= t){ toastErr('查询失败：开始时间必须早于结束时间'); return; }
    if (t - f < 600000){ toastErr('查询失败：时间跨度至少 10 分钟'); return; }
    if (f > Date.now()){ toastErr('查询失败：开始时间不能晚于当前时间'); return; }
    if (t - f > 90 * 86400000){ toastErr('查询失败：时间跨度不能超过 90 天'); return; }
    dvRange = 'custom';
    dvFrom = f;
    dvTo = t;
    setActive('');
    if (activeDevice) renderDvReport(activeDevice);
  });

  exp.addEventListener('click', exportDvCsv);

  /* 窗口尺寸变化后画布要按新宽度重绘（防抖，且只在报表页签可见时执行） */
  let rzTimer = null;
  window.addEventListener('resize', () => {
    if (rzTimer) clearTimeout(rzTimer);
    rzTimer = setTimeout(() => { if (dvTab === 'report') drawDvCharts(); }, 180);
  });
})();

/* 主题切换后重绘（健康环渐变、指标卡取色都依赖于主题变量） */
window.addEventListener('themechange', () => {
  if (activeDevice && deviceView && deviceView.classList.contains('show')) renderDeviceView(dvTab);
});


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
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
