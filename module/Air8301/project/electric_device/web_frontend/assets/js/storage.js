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

