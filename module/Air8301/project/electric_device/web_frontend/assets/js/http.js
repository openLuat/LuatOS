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

