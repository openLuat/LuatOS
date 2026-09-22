/* 打包产物（合并顺序 = 模块加载顺序，勿手改）：luat-sdk.js + config.js + storage.js + utils.js + http.js + auth.js + guards.js + components.js + api.js + shell.js + pages/settings.js + boot.js */
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

/* assets/js/pages/settings.js —— 由 index.html 内联脚本拆出（原行区间 8661-8983 / 9444-9684），内容未改动 */
/* =========================================================
   14.1 系统设置（主题风格 / 通知设置）
   ========================================================= */
/* ---------- 界面偏好：三项动效开关 ---------- */
const UI_KEY = 'nexus-ui';
/* 出厂默认：过渡动效开，背景星链与数字滚动关（低配设备 / 远程桌面更跟手） */
const UI_DEF = { motion:true, bg:false, roll:false };
const uiPrefs = Object.assign({}, UI_DEF);
try {
  const raw = localStorage.getItem(UI_KEY);
  if (raw) Object.assign(uiPrefs, JSON.parse(raw));
} catch(e){}

function applyUiPrefs(){
  document.documentElement.classList.toggle('no-motion', !uiPrefs.motion);
  if (typeof window.nexusBgSet === 'function') window.nexusBgSet(uiPrefs.bg);
  window.nexusNoRoll = !uiPrefs.roll;      /* KPI 数字滚动据此直接落值 */
}
function saveUiPrefs(){
  try { localStorage.setItem(UI_KEY, JSON.stringify(uiPrefs)); } catch(e){}
}
applyUiPrefs();

function syncUiSwitches(){
  document.querySelectorAll('[data-ui]').forEach(btn => {
    const on = !!uiPrefs[btn.dataset.ui];
    btn.classList.toggle('on', on);
    btn.setAttribute('aria-pressed', on ? 'true' : 'false');
  });
}

/* ---------- 通知渠道：钉钉 / 飞书 / 企业微信 ---------- */
/* NOTIFY_KEY / NOTIFY_META / NOTIFY_DEF / notifyCfg / notifyLog 全部在公共层 api.js：
   —— 配置的「读取」也必须在公共层做，否则只有本页显示真实配置，告警中心会显示默认值；
   —— 推送记录也由 api.js 托管（落盘，刷新不丢），这里只负责渲染。 */

let notifyOpen = null;      /* 当前展开的渠道 */
let setTab = 'theme';
let setSaveTimer = null;

/* 保存统一走公共层（保存的就是同一个 notifyCfg 对象） */
function saveNotify(){ saveNotifyConfig(); }
function ntMeta(id){ return NOTIFY_META.find(m => m.id === id); }

/* ---------- 渲染：渠道卡片 ---------- */
function ntField(m, key, label, ph){
  const c = notifyCfg[m.id];
  return '<label class="nt-field"><span>' + label + '</span>' +
    '<input type="text" data-nt-field="' + key + '" value="' + String(c[key] || '').replace(/"/g, '&quot;') +
    '" placeholder="' + ph + '" spellcheck="false"></label>';
}
function ntChips(list, cur, attr){
  return list.map(([k, t]) =>
    '<button type="button" data-' + attr + '="' + k + '" class="' + (cur === k ? 'active' : '') + '">' + t + '</button>').join('');
}

function renderNotifyGrid(){
  const box = document.getElementById('ntGrid');
  if (!box) return;

  box.innerHTML = NOTIFY_META.map(m => {
    const c = notifyCfg[m.id];
    const open = notifyOpen === m.id;
    return '<div class="nt-card' + (open ? ' open' : '') + '" data-ch="' + m.id + '">' +
      '<div class="nt-head">' +
        '<span class="nt-ic" style="--brand:' + m.brand + '"><svg viewBox="0 0 24 24"><path d="' + m.icon + '"/></svg></span>' +
        '<div class="nt-title"><b>' + m.name + '</b><span>' + m.desc + '</span></div>' +
        '<button class="dv-switch' + (c.on ? ' on' : '') + '" data-nt-switch type="button" aria-pressed="' +
          (c.on ? 'true' : 'false') + '"><i></i></button>' +
      '</div>' +
      '<div class="nt-foot">' +
        '<span class="nt-state' + (c.on && String(c.webhook || '').trim() ? ' on' : '') + '">' +
          (!c.on ? '未启用' : (String(c.webhook || '').trim() ? '已启用' : '待配置')) + '</span>' +
        /* 统计是真实计数（只统计渠道确认送达的），不再显示原来写死的演示数字 */
        '<span class="nt-sent">' + (!c.on ? '开启后开始推送' :
          (String(c.webhook || '').trim() ? '累计送达 <b>' + (Number(c.sent) || 0) + '</b> 条' : '尚未填写 Webhook')) + '</span>' +
      '</div>' +
      '<div class="nt-config">' +
        ntField(m, 'webhook', 'Webhook 地址', m.demo) +
        ntField(m, 'secret', m.secret, '用于加签校验，留空表示不校验') +
        ntField(m, 'to', m.to, '多个用逗号分隔，留空表示不 @') +
        '<div class="nt-row"><span>消息格式</span><div class="nt-chips">' +
          ntChips([['md','Markdown'],['text','纯文本'],['card','卡片']], c.fmt, 'nt-fmt') +
        '</div></div>' +
        '<div class="nt-actions">' +
          '<button type="button" class="nt-test" data-nt-test>发送测试消息</button>' +
          '<span class="nt-last">' + (c.last ? '最近推送 ' + dvDT(c.last) : '尚未推送过') + '</span>' +
        '</div>' +
      '</div>' +
    '</div>';
  }).join('');
}

/* ---------- 渲染：推送策略 ---------- */
function renderNotifyStrategy(){
  const box = document.getElementById('ntStrategy');
  if (!box) return;
  const s = notifyCfg.strategy;
  box.innerHTML =
    '<div class="nt-row"><span>触发等级</span><div class="nt-chips">' +
      ntChips([['critical','仅严重'],['warning','警告及以上'],['all','全部']], s.level, 'nt-level') +
    '</div></div>' +
    '<div class="nt-row"><span>聚合窗口</span><div class="nt-inline">' +
      '<input class="nt-num" id="ntWin" type="number" min="0" max="600" step="10" value="' + s.win + '">' +
      '<em>秒内的同类告警合并成一条推送</em></div></div>' +
    '<div class="nt-row"><span>夜间免打扰</span>' +
      '<button class="dv-switch' + (s.quiet ? ' on' : '') + '" data-nt-quiet type="button" aria-pressed="' +
        (s.quiet ? 'true' : 'false') + '"><i></i></button>' +
      '<em style="font-style:normal;font-size:12px;color:var(--muted)">22:00 ~ 08:00 只记录不推送</em></div>';
}

/* ---------- 渲染：推送记录 ---------- */
function renderNotifyLog(){
  const box = document.getElementById('ntLog');
  if (!box) return;
  if (!notifyLog.length){
    box.innerHTML = '<div class="nt-empty">暂无推送记录：新告警会自动推送，也可展开渠道卡片点「发送测试消息」立即验证配置</div>';
    return;
  }
  /* state: ok=已送达 / unknown=已提交（结果未知） / fail=失败 / quiet=免打扰 / skip=无可用渠道 */
  const MARK = { ok:'✓', unknown:'·', fail:'×', quiet:'·', skip:'·' };
  box.innerHTML = notifyLog.slice(0, 40).map(r => {
    const m = ntMeta(r.ch) || { short:'系统', brand:'#8a93a6' };
    return '<div class="nt-log-row">' +
      '<span class="nt-log-ch" style="--brand:' + m.brand + '">' + m.short + '</span>' +
      '<b>' + (MARK[r.state] ? MARK[r.state] + ' ' : '') + r.text + '</b><em>' + r.time + '</em></div>';
  }).join('');
}

/* ---------- 标签页切换 ---------- */
function setSetTab(name){
  setTab = name === 'notify' ? 'notify' : 'theme';
  document.querySelectorAll('.set-tab').forEach(t => t.classList.toggle('active', t.dataset.set === setTab));
  const theme = document.getElementById('setPageTheme');
  const notify = document.getElementById('setPageNotify');
  if (theme) theme.classList.toggle('hide', setTab !== 'theme');
  if (notify) notify.classList.toggle('hide', setTab !== 'notify');
}

/* ---------- 整页渲染（视图切换时会重新挂载面板） ---------- */
function renderSettings(){
  setSetTab(setTab);
  syncUiSwitches();
  renderNotifyGrid();
  renderNotifyStrategy();
  renderNotifyLog();
}

/* ---------- 发送测试消息 ----------
   真的发：走公共层同一套发送链路（中继优先，否则直连渠道 Webhook）。
   浏览器直连时跨域限制读不到渠道回执，会把「已提交、结果未知」如实说出来，不再假装成功。 */
function ntTest(id){
  const m = ntMeta(id);
  const c = notifyCfg[id];
  if (!m || !c) return;
  if (!c.on){ toastErr('发送失败：' + m.name + ' 未启用'); return; }
  const url = String(c.webhook || '').trim();
  if (!url){ toastErr('发送失败：请先填写 ' + m.name + ' 的 Webhook 地址'); return; }
  if (!/^https:\/\/\S+$/i.test(url)){ toastErr('发送失败：Webhook 地址需以 https:// 开头'); return; }

  const btn = document.querySelector('.nt-card[data-ch="' + id + '"] [data-nt-test]');
  if (btn){ btn.disabled = true; btn.textContent = '发送中…'; }
  App.notify.test(id).then(function(r){
    if (btn){ btn.disabled = false; btn.textContent = '发送测试消息'; }
    if (r.state === 'ok') toast(m.name + '：测试消息已送达');
    else if (r.state === 'unknown') toast(m.name + '：' + r.detail + '（如需可靠回执请配置 NOTIFY_RELAY 服务端中继）');
    else toastErr(m.name + ' 发送失败：' + r.detail);
    /* 记录 / 统计 / 渠道卡片刷新都由公共层 notifyDeliver 完成，这里不重复处理 */
  }).catch(function(e){
    if (btn){ btn.disabled = false; btn.textContent = '发送测试消息'; }
    toastErr(m.name + ' 发送失败：' + ((e && e.message) || '未知错误'));
  });
}

/* ---------- 按钮反馈：不弹 toast，按钮自身给结果 ---------- */
function setBtnFlash(btn, text){
  if (!btn) return;
  const raw = btn.dataset.raw || btn.textContent;
  btn.dataset.raw = raw;
  btn.textContent = text;
  if (setSaveTimer) clearTimeout(setSaveTimer);
  setSaveTimer = setTimeout(() => { btn.textContent = raw; }, 1400);
}

/* ---------- 交互（事件委托：面板会被摘除/挂载） ---------- */
document.addEventListener('click', e => {
  const tab = e.target.closest('.set-tab');
  if (tab){ setSetTab(tab.dataset.set); return; }

  const sw = e.target.closest('[data-nt-switch]');
  if (sw){
    const id = sw.closest('.nt-card').dataset.ch;
    notifyCfg[id].on = !notifyCfg[id].on;
    saveNotify();
    renderNotifyGrid();
    return;
  }

  const test = e.target.closest('[data-nt-test]');
  if (test){ ntTest(test.closest('.nt-card').dataset.ch); return; }

  const fmt = e.target.closest('[data-nt-fmt]');
  if (fmt){
    const id = fmt.closest('.nt-card').dataset.ch;
    notifyCfg[id].fmt = fmt.dataset.ntFmt;
    saveNotify();
    fmt.parentNode.querySelectorAll('button').forEach(b => b.classList.toggle('active', b === fmt));
    return;
  }

  const lv = e.target.closest('[data-nt-level]');
  if (lv){
    notifyCfg.strategy.level = lv.dataset.ntLevel;
    saveNotify();
    lv.parentNode.querySelectorAll('button').forEach(b => b.classList.toggle('active', b === lv));
    return;
  }

  const quiet = e.target.closest('[data-nt-quiet]');
  if (quiet){
    notifyCfg.strategy.quiet = !notifyCfg.strategy.quiet;
    saveNotify();
    quiet.classList.toggle('on', notifyCfg.strategy.quiet);
    quiet.setAttribute('aria-pressed', notifyCfg.strategy.quiet ? 'true' : 'false');
    return;
  }

  const ui = e.target.closest('[data-ui]');
  if (ui){
    const key = ui.dataset.ui;
    uiPrefs[key] = !uiPrefs[key];
    saveUiPrefs();
    applyUiPrefs();
    syncUiSwitches();
    return;
  }

  if (e.target.closest('#ntClear')){
    notifyLogClear();          /* 记录已落盘，清空要同步 localStorage */
    renderNotifyLog();
    return;
  }

  if (e.target.closest('#setSave')){
    saveNotify();
    saveUiPrefs();
    setBtnFlash(e.target.closest('#setSave'), '已保存');
    return;
  }

  if (e.target.closest('#setReset')){
    const btn = e.target.closest('#setReset');
    if (setTab === 'notify'){
      /* 通知设置：恢复出厂值（Webhook / 密钥 / 记录一并清空）
         —— 就地重置：notifyCfg 被公共层等多处引用，不能整体重新赋值 */
      notifyResetConfig();
      notifyOpen = null;
      notifyLogClear();
      renderSettings();
    } else {
      Object.assign(uiPrefs, UI_DEF);
      saveUiPrefs();
      applyUiPrefs();
      syncUiSwitches();
    }
    setBtnFlash(btn, '已恢复');
    return;
  }

  /* 点卡片空白处展开/收起配置（点配置区内部不收起） */
  const card = e.target.closest('.nt-card');
  if (card && !e.target.closest('.nt-config')){
    notifyOpen = (notifyOpen === card.dataset.ch) ? null : card.dataset.ch;
    renderNotifyGrid();
  }
});

/* 输入类控件：只更新状态，不重渲染（否则会丢焦点） */
let ntInputTimer = null;
document.addEventListener('input', e => {
  const f = e.target.closest('[data-nt-field]');
  if (f){
    notifyCfg[f.closest('.nt-card').dataset.ch][f.dataset.ntField] = f.value.trim();
    if (ntInputTimer) clearTimeout(ntInputTimer);
    ntInputTimer = setTimeout(saveNotify, 400);
    return;
  }
  if (e.target.id === 'ntWin'){
    const v = Math.max(0, Math.min(600, parseInt(e.target.value, 10) || 0));
    notifyCfg.strategy.win = v;
    if (ntInputTimer) clearTimeout(ntInputTimer);
    ntInputTimer = setTimeout(saveNotify, 400);
  }
});

/* =========================================================
   系统自检（真实接口逐项验证）
   —— 每一步都是对 AirCloud 开放接口的真实调用，并打印原始返回；
      便于在真实环境下定位"哪一层没数据、字段长什么样"。
   —— 默认只做只读探测；send_cmd 需人工点击（tag=19 会真实控制设备）
   ========================================================= */
function runSelfTest(){
  const t0 = Date.now();
  const out = [];
  const push = function(s){ out.push(s); };
  const ctx = App.auth.getAuthContext();

  push('===== 上海合宙电力控制平台 · 系统自检报告 =====');
  push('时间：' + App.utils.formatTime(t0));
  push('地址：' + location.href);
  push('appId：' + (App.config.APP_ID || '(空，需部署在 /ai_app/luatos/<应用名>/ 下)'));
  push('认证：' + (ctx
      ? (ctx.source + ' · token' + (ctx.auth && ctx.auth.token ? '✓' : '✗') +
         ' salt' + (ctx.auth && ctx.auth.salt ? '✓' : '✗') +
         ' sid' + (ctx.service && ctx.service.sid ? '✓' : '✗'))
      : '未登录（无 token/salt/sid）'));
  push('');

  let first = null;
  const prjOf = function(){ return curProject() || PROJECTS[0] || null; };
  const guard = function(label, fn){
    return Promise.resolve().then(fn).then(
      function(v){ push('✔ ' + label + '：' + v); },
      function(e){ push('✘ ' + label + '：' + ((e && e.message) ? e.message : e)); }
    );
  };

  return guard('1. 项目列表 /open_api/list_my_projects', function(){
      return apiProjects().then(function(res){
        const list = Array.isArray(res.value) ? res.value : [];
        if (!list.length) throw new Error('接口返回 0 个项目（value=' + JSON.stringify(res.value) + '）');
        list.slice(0, 5).forEach(function(p){
          push('    · ' + p.name + ' | project_key=' + p.project_key + ' | model=' + (p.model || '') + ' | ctime=' + (p.ctime || ''));
        });
        return list.length + ' 个项目';
      });
    })
  .then(function(){ return guard('2. 设备列表 /open_api/search_my_devices（page=1 size=100）', function(){
      const prj = prjOf();
      if (!prj) throw new Error('无可用项目');
      return apiDevices(prj.code, 1, 100, '').then(function(res){
        const v = res.value || {};
        const recs = Array.isArray(v.records) ? v.records : [];
        push('    项目：' + prj.name + '（' + prj.code + '）');
        push('    total=' + v.total + ' pages=' + v.pages + ' current=' + v.current + ' size=' + v.size + ' 本次返回=' + recs.length);
        recs.slice(0, 5).forEach(function(x){ push('    · ' + JSON.stringify(x)); });
        if (!recs.length) throw new Error('该项目下没有设备（total=' + v.total + '）');
        first = recs[0].deviceid || recs[0].imei || '';
        return recs.length + ' 台（total=' + v.total + '）';
      });
    }); })
  .then(function(){ return guard('3. 全量分页拉取 apiAllDevices', function(){
      const prj = prjOf();
      return apiAllDevices(prj.code).then(function(list){ return list.length + ' 台'; });
    }); })
  .then(function(){ return guard('4. 最新 Tag /open_api/aircloud/list_by_tags（设备 ' + (first || '-') + '）', function(){
      if (!first) throw new Error('无设备，跳过');
      const tags = App.config.DEVICE_TAGS.concat([App.config.TAGS.LNG, App.config.TAGS.LAT]);
      push('    请求 tags=' + JSON.stringify(tags));
      return apiTags(first, tags, 1, 1).then(function(res){
        const v = res.value || {};
        const rec = (v.records && v.records[0]) || null;
        push('    total=' + v.total + ' 本次返回=' + ((v.records || []).length));
        push('    原始记录：' + JSON.stringify(rec));
        if (!rec) throw new Error('该设备没有任何上报记录（total=' + v.total + '）');
        return '解析结果 = ' + JSON.stringify({
          ct: rec.ct, 实际电压_799: rec.val_799, 工作状态_265: rec.val_265,
          设定电压_800: rec.val_800, ICCID_783: rec.val_783,
          IMEI_798: rec.val_798, 版本_1027: rec.val_1027
        });
      });
    }); })
  .then(function(){ return guard('5. 最新位置 /open_api/aircloud/latest_location', function(){
      if (!first) throw new Error('无设备，跳过');
      return apiLatestLocation(first).then(function(res){
        push('    原始返回：' + JSON.stringify(res.value));
        return 'ok';
      });
    }); })
  .then(function(){ return guard('6. 历史查询 list_by_tags（近 7 天 filter）', function(){
      if (!first) throw new Error('无设备，跳过');
      const now = new Date();
      const from = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6, 0, 0, 0);
      const filter = { aks: ['ct', 'ct'], acs: ['ge', 'le'],
        avs: [App.utils.formatLocalParam(from.getTime()), App.utils.formatLocalParam(now.getTime())] };
      push('    filter=' + JSON.stringify(filter));
      return apiTags(first, [799, 800, 265], 1, 100, filter).then(function(res){
        const v = res.value || {};
        push('    total=' + v.total + ' 本次返回=' + ((v.records || []).length));
        return '近 7 天共 ' + v.total + ' 条记录';
      });
    }); })
  .then(function(){ return guard('7. 控制接口 /open_api/aircloud/send_cmd', function(){
      return Promise.resolve('未自动下发（避免误控现场设备）；请用下方按钮做真实探测');
    }); })
  .then(function(){
    push('');
    push('--- 页面实际使用的设备对象（当前项目第 1 台）---');
    const d = curData().devices[0];
    if (d){
      push(JSON.stringify({
        id: d.id, online: d.online, 实际电压: d.load, 设定电压: d.temp,
        工作状态265: d.workStatus,
    联网方式781: d.netType ? (netTagText(d.netType) + '(' + d.netType + ')') : '未上报',
    信号强度782: d.hasSignal ? (d.snr + '/31' + (d.signalSrc === 'loc' ? '(来自位置接口)' : '')) : '未上报',
    电量percent: d.percent,
        地址: d.address, lng: d.lng, lat: d.lat, 最近上报秒: d.hbOffset,
        ICCID: d.iccid, 版本: d.version
      }));
    } else push('（当前项目尚无设备对象）');
    push('');
    push('===== 报告结束（耗时 ' + (Date.now() - t0) + ' ms）=====');
    return out.join('\n');
  });
}

function probeSendCmd(pre, tag, value){
  const dev = curData().devices[0];
  if (!dev){ toastErr('无设备可探测'); return; }
  const body = { client_id: dev.id, tag: tag, protocol: 0 };
  if (value !== undefined) body.value = value;
  pre.textContent += '\n\n--- send_cmd 真实探测 @' + App.utils.formatTime(Date.now()) + ' ---\n' +
    '设备：' + dev.id + '\n请求体：' + JSON.stringify(body);
  App.http.post(App.config.API.SEND_CMD, body).then(function(res){
    pre.textContent += '\n结果：成功 · value=' + JSON.stringify(res.value) +
      '\n→ 平台已受理 tag=' + tag + '（设备侧是否执行需看设备回执 20）';
  }, function(e){
    pre.textContent += '\n结果：失败 · ' + ((e && e.message) ? e.message : e) +
      (e && e.code ? '（code ' + e.code + '）' : '') +
      '\n→ 该 tag 不被 send_cmd 支持，需调整下发通道';
  });
}

function showSelfTest(text){
  let mask = document.getElementById('stMask');
  if (!mask){
    mask = document.createElement('div');
    mask.id = 'stMask';
    mask.style.cssText = 'position:fixed;inset:0;z-index:130;display:flex;align-items:center;justify-content:center;background:var(--mask);backdrop-filter:blur(10px)';
    mask.innerHTML =
      '<div style="width:min(92vw,780px);max-height:86vh;display:flex;flex-direction:column;gap:12px;padding:20px;border-radius:18px;' +
        'background:linear-gradient(158deg,var(--panel-from),var(--panel-to));border:1px solid var(--line-strong);' +
        'box-shadow:0 30px 72px -24px var(--shadow-a)">' +
        '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">' +
          '<b style="font-size:17px;color:var(--text)">系统自检报告</b>' +
          '<span style="font-size:12px;color:var(--dim)">全部为真实 AirCloud 接口返回</span>' +
          '<span style="flex:1"></span>' +
          '<button type="button" id="stCopy" class="set-btn">复制报告</button>' +
          '<button type="button" id="stClose" class="set-btn">关闭</button>' +
        '</div>' +
        '<pre id="stText" style="flex:1;overflow:auto;margin:0;padding:14px;border-radius:12px;background:var(--soft-bg2);' +
          'border:1px solid var(--line);color:var(--text);font-size:13px;line-height:1.7;white-space:pre-wrap;word-break:break-all"></pre>' +
        '<div style="display:flex;gap:10px;flex-wrap:wrap">' +
          '<button type="button" id="stProbe25" class="set-btn">探测 send_cmd(tag=25 运维日志请求)</button>' +
          '<button type="button" id="stProbe19" class="set-btn" style="color:var(--amber)">探测 send_cmd(tag=19 控制命令 · 会真实控制设备)</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(mask);

    mask.querySelector('#stClose').addEventListener('click', function(){ mask.remove(); });
    mask.querySelector('#stCopy').addEventListener('click', function(){
      const t = mask.querySelector('#stText').textContent;
      if (navigator.clipboard && navigator.clipboard.writeText){
        navigator.clipboard.writeText(t).then(function(){ toast('自检报告已复制'); },
          function(){ toastErr('复制失败，请手动选择文本'); });
      } else toastErr('当前环境不支持剪贴板，请手动选择文本');
    });
    mask.querySelector('#stProbe25').addEventListener('click', function(){
      probeSendCmd(mask.querySelector('#stText'), App.config.TAGS.MTN_LOG_REQ, undefined);
    });
    mask.querySelector('#stProbe19').addEventListener('click', function(){
      const dev = curData().devices[0];
      if (!dev) { toastErr('无设备可探测'); return; }
      if (!window.confirm('将向设备 ' + dev.id + ' 真实下发控制命令 tag=19（子 TLV 265=1 开机）。\n这会实际动作现场设备，确认继续？')) return;
      /* value 必须是「顶层裸数组的 JSON 字符串」：元素 {field_meaning, data_type, value}
         —— 与指令控制页 buildControlValue 一致；写成 { "265": 1 } 会被平台受理但设备解不出子 TLV */
      probeSendCmd(mask.querySelector('#stText'), App.config.BIZ.CONTROL_TAG,
        JSON.stringify([{ field_meaning: App.config.TAGS.WORK_STATUS, data_type: 0, value: 1 }]));
    });
  }
  const pre = mask.querySelector('#stText');
  pre.textContent = text || '正在执行真实接口自检…';
  mask.style.display = 'flex';
}

(function bindSelfTest(){
  const btn = document.getElementById('setSelfTest');
  if (!btn) return;
  btn.addEventListener('click', function(){
    showSelfTest('正在执行真实接口自检…');
    setTimeout(function(){
      runSelfTest().then(function(text){
        const pre = document.getElementById('stText');
        if (pre) pre.textContent = text;
      }, function(e){
        const pre = document.getElementById('stText');
        if (pre) pre.textContent = '自检异常：' + ((e && e.message) ? e.message : e);
      });
    }, 30);
  });
})();

/* 登录失效统一处理（102/103/105） */
App.http.onInvalid(function(){
  const r = App.auth.loginInvalid();
  toastErr(r.message);
  if (r.mode === 'app') setTimeout(function(){ App.auth.goToLogin(); }, 1200);
});

/* 注：项目选择/切换（setCurrentProject / applyProject）已移到 shell.js ——
   它是所有页面共用的能力，而本文件只在「系统设置」页加载。 */


/* ==== 多页面接线（由 _deploy/wire-pages.js 追加）==== */
/* 系统设置页 */
registerPageRenderer(function(){ renderSettings(); });

/* 支持从告警中心跳过来直接落在「通知设置」页签：pages/settings.html?tab=notify */
onPageQuery(function(q){
  if (q.tab === 'notify'){
    if (typeof setSetTab === 'function') setSetTab('notify');
    if (typeof renderSettings === 'function') renderSettings();
  }
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
