/* 打包产物（合并顺序 = 模块加载顺序，勿手改）：pages/map.js */
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
