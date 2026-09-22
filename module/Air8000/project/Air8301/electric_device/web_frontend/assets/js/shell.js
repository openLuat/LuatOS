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
