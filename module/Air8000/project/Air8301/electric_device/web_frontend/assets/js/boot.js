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
