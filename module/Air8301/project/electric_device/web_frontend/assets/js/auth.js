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

