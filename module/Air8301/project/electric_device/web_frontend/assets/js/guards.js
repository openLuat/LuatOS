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

