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

