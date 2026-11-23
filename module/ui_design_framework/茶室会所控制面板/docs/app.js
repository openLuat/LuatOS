/* =============================================================
   松风阁 · 茶室会所控制面板 —— 交互原型
   规则：state 为唯一数据源；render 只读 state；不引外部依赖
   ============================================================= */
(function () {
  'use strict';

  /* ---------------- 数据表（对应真机 app_config.lua 的设备表） ---------------- */
  var DEVICES = [
    { key: 'light',   name: '茶台灯光', en: 'TEA TABLE LIGHT', img: 'img/dev_light.png',
      desc: '主位吊灯与茶台灯带联动，亮度越低，汤色越显。', hint: '灯光明暗' },
    { key: 'incense', name: '香薰',     en: 'INCENSE',         img: 'img/dev_incense.png',
      desc: '炉火保温，香片渐展；浓度过高会压住茶香。',       hint: '香薰浓度' },
    { key: 'music',   name: '背景音乐', en: 'AMBIENCE',        img: 'img/dev_music.png',
      desc: '古琴与环境声分层混音，静修时只留水声。',           hint: '音量' },
    { key: 'humid',   name: '加湿',     en: 'HUMIDIFIER',      img: 'img/dev_humid.png',
      desc: '细雾补湿，秋冬防燥；靠窗位湿度略高。',             hint: '雾量' },
    { key: 'ambient', name: '氛围',     en: 'MOOD',            img: 'img/dev_ambient.png',
      desc: '纱帘、投影与暗角联动，决定整室的呼吸感。',         hint: '氛围强度' }
  ];

  var SCENES = [
    { name: '待客', idx: '壹', en: 'RECEPTION',  levels: [7, 3, 4, 4, 5], hint: '待客：灯光放亮，茶席齐备' },
    { name: '静修', idx: '贰', en: 'QUIET',      levels: [2, 8, 3, 2, 3], hint: '静修：一灯一香，声息皆缓' },
    { name: '茶会', idx: '叁', en: 'TEA GATHER', levels: [9, 5, 6, 5, 7], hint: '茶会：满室暖光，起汤待客' },
    { name: '清场', idx: '肆', en: 'CLEAR',      levels: [0, 0, 0, 0, 0], hint: '清场：设备已全部关闭' }
  ];

  var QUICK = [2, 6, 9];          // 快捷档位：柔和 / 适中 / 浓郁
  var LEVELS = 10;                // 档位总数
  var DIM = [0.72, 1, 1.12];      // 屏幕亮度：暗 / 标准 / 亮
  var THEME_KEY = 'songfengge-theme';

  var state = {
    view: 'wall',
    device: 0,
    theme: 'night',
    scene: 0,                     // 当前命中的一键场景，-1 表示手动调过
    levels: [7, 3, 4, 4, 5],
    lastOn: [7, 3, 4, 4, 5],      // 关闭前的档位，重新开启时恢复
    muted: false,
    bright: 1,
    bell: true
  };

  /* ---------------- DOM ---------------- */
  var screenEl = document.getElementById('screen');
  var viewport = document.getElementById('viewport');
  var viewWall = document.getElementById('viewWall');
  var viewDetail = document.getElementById('viewDetail');
  var cardMain = document.getElementById('cardMain');
  var cardSide = document.getElementById('cardSide');
  var sceneRow = document.getElementById('sceneRow');
  var hero = document.getElementById('hero');
  var heroImg = document.getElementById('heroImg');
  var heroName = document.getElementById('heroName');
  var heroEn = document.getElementById('heroEn');
  var dState = document.getElementById('dState');
  var dSwitch = document.getElementById('dSwitch');
  var dDesc = document.getElementById('dDesc');
  var dLevel = document.getElementById('dLevel');
  var dSegs = document.getElementById('dSegs');
  var dHint = document.getElementById('dHint');
  var dChips = document.getElementById('dChips');
  var sheet = document.getElementById('sheet');
  var toast = document.getElementById('toast');
  var clockEl = document.getElementById('clock');
  var dateEl = document.getElementById('dateLine');

  /* ---------------- 工具 ---------------- */
  function clamp(v, min, max) { return Math.min(max, Math.max(min, v)); }
  function segsHtml(n, dev) {
    var out = '';
    for (var i = 0; i < n; i++) {
      out += '<b data-dev="' + dev + '" data-seg="' + i + '"></b>';
    }
    return out;
  }
  function cardHtml(i, mini) {
    var d = DEVICES[i];
    return '<div class="card ' + (mini ? 'card--mini' : 'card--main') + '" data-card="' + i +
             '" role="button" tabindex="0" aria-label="' + d.name + '">' +
             '<img class="card__img" src="' + d.img + '" alt="' + d.name + '">' +
             '<span class="card__shade"></span>' +
             (mini ? '' : '<span class="card__tag"><i></i>主位</span>') +
             '<button class="card__st" data-act="power-mini" data-dev="' + i + '">' +
               '<i></i><span class="card__stx">开启</span></button>' +
             '<span class="card__foot">' +
               '<span class="card__name serif">' + d.name + '</span>' +
               (mini ? '' : '<span class="card__en">' + d.en + '</span>') +
               '<span class="segs">' + segsHtml(LEVELS, i) + '</span>' +
             '</span>' +
           '</div>';
  }

  /* ---------------- 构建（只做一次，避免图片重载闪烁） ---------------- */
  (function build() {
    cardMain.innerHTML = cardHtml(0, false);
    var side = '';
    for (var i = 1; i < DEVICES.length; i++) side += cardHtml(i, true);
    cardSide.innerHTML = side;

    dSegs.innerHTML = segsHtml(LEVELS, 0);   // 详情页的档位格单独一套

    var tray = '';
    for (var k = 0; k < SCENES.length; k++) {
      tray += '<button class="tray__btn" data-scene="' + k + '">' +
                '<span class="tray__idx serif">' + SCENES[k].idx + '</span>' +
                '<span class="tray__name serif">' + SCENES[k].name + '</span>' +
                '<span class="tray__en">' + SCENES[k].en + '</span>' +
              '</button>';
    }
    sceneRow.innerHTML = tray;
  })();

  function cardOf(i) {
    return document.querySelector('[data-card="' + i + '"]');
  }

  /* ---------------- 渲染 ---------------- */
  function renderCards() {
    for (var i = 0; i < DEVICES.length; i++) {
      var lv = state.levels[i];
      var card = cardOf(i);
      if (!card) continue;
      card.classList.toggle('is-on', lv > 0);
      card.classList.toggle('is-off', lv === 0);
      card.querySelector('.card__stx').textContent = lv > 0 ? lv + ' 档' : '已关闭';
      var cells = card.querySelectorAll('.segs b');
      for (var c = 0; c < cells.length; c++) cells[c].classList.toggle('on', c < lv);
    }
  }

  function renderDetail() {
    var d = DEVICES[state.device];
    var lv = state.levels[state.device];
    heroImg.src = d.img;
    heroImg.alt = d.name;
    heroName.textContent = d.name;
    heroEn.textContent = d.en;
    dDesc.textContent = d.desc;
    dHint.textContent = d.hint;
    hero.classList.toggle('is-off', lv === 0);
    dSwitch.classList.toggle('is-on', lv > 0);
    dState.innerHTML = lv > 0 ? '已开启 · <b>' + lv + '</b> 档' : '已关闭';
    dLevel.textContent = lv;

    var cells = dSegs.querySelectorAll('b');
    for (var c = 0; c < cells.length; c++) cells[c].classList.toggle('on', c < lv);

    var chips = dChips.querySelectorAll('.chip');
    for (var k = 0; k < chips.length; k++) {
      chips[k].classList.toggle('is-on', QUICK[k] === lv);
    }
  }

  function renderTray() {
    var btns = sceneRow.querySelectorAll('.tray__btn');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('is-on', i === state.scene);
    }
  }

  function renderTheme() {
    document.documentElement.dataset.theme = state.theme;
    var btns = sheet.querySelectorAll('[data-theme-set]');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('is-on', btns[i].dataset.themeSet === state.theme);
    }
  }

  function renderBright() {
    screenEl.style.filter = 'brightness(' + DIM[state.bright] + ')';
    var btns = sheet.querySelectorAll('[data-bright]');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('is-on', +btns[i].dataset.bright === state.bright);
    }
  }

  function renderRail() {
    document.querySelector('[data-act="mute"]').classList.toggle('is-on', state.muted);
    document.querySelector('[data-act="to-wall"]').classList.toggle('is-on', state.view === 'wall');
    document.getElementById('sSwitch').classList.toggle('is-on', state.bell);
  }

  function renderClock() {
    var now = new Date();
    var h = now.getHours(), m = now.getMinutes();
    clockEl.textContent = (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
    var wk = '日一二三四五六'.charAt(now.getDay());
    dateEl.textContent = (now.getMonth() + 1) + '月' + now.getDate() + '日 · 周' + wk + ' · 室外 16° 晴';
  }

  function renderAll() {
    renderCards();
    renderDetail();
    renderTray();
    renderRail();
    renderTheme();
    renderBright();
  }

  /* ---------------- 页面切换 ---------------- */
  function setView(view) {
    state.view = view;
    viewWall.classList.toggle('is-active', view === 'wall');
    viewDetail.classList.toggle('is-active', view === 'detail');
    renderRail();
  }

  function openDetail(i) {
    state.device = i;
    // 详情页档位格需重新绑定设备号，点击任意一格直接跳到该档
    var cells = dSegs.querySelectorAll('b');
    for (var c = 0; c < cells.length; c++) cells[c].dataset.dev = i;
    renderDetail();
    setView('detail');
  }

  /* ---------------- 业务动作 ---------------- */
  var toastTimer = null;
  function showToast(text) {
    toast.textContent = text;
    toast.classList.add('is-on');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove('is-on'); }, 2200);
  }

  function setLevel(i, v, silent) {
    var old = state.levels[i];
    v = clamp(v, 0, LEVELS);
    if (v === old) return;
    state.levels[i] = v;
    if (v > 0) state.lastOn[i] = v;
    if (!silent) state.scene = -1;      // 手动调过就不再挂在某个场景上
    renderCards();
    renderTray();
    if (state.view === 'detail') renderDetail();
  }

  function togglePower(i) {
    var lv = state.levels[i];
    if (lv > 0) {
      state.lastOn[i] = lv;
      setLevel(i, 0);
    } else {
      setLevel(i, state.lastOn[i] || 5);
    }
  }

  function applyScene(k) {
    var scene = SCENES[k];
    for (var i = 0; i < DEVICES.length; i++) {
      state.levels[i] = scene.levels[i];
      if (scene.levels[i] > 0) state.lastOn[i] = scene.levels[i];
    }
    state.scene = k;
    setView('wall');
    renderAll();
    // 卡片描边脉冲一次，给出"整室一起变"的反馈
    for (var j = 0; j < DEVICES.length; j++) {
      var card = cardOf(j);
      if (!card) continue;
      card.classList.remove('is-pulse');
      void card.offsetWidth;
      card.classList.add('is-pulse');
    }
    showToast(scene.hint);
  }

  function setTheme(name) {
    state.theme = name === 'paper' ? 'paper' : 'night';
    try { localStorage.setItem(THEME_KEY, state.theme); } catch (e) { /* 隐私模式忽略 */ }
    renderTheme();
  }

  function openSheet() { sheet.classList.add('is-open'); }
  function closeSheet() { sheet.classList.remove('is-open'); }

  /* ---------------- 事件 ---------------- */
  document.addEventListener('click', function (event) {
    var el = event.target.closest('[data-act],[data-card],[data-scene],[data-seg],[data-chip],[data-theme-set],[data-bright]');
    if (!el) return;

    if (el.dataset.act) {
      switch (el.dataset.act) {
        case 'to-wall': setView('wall'); break;
        case 'service': showToast('已呼叫服务，稍候即到'); break;
        case 'mute':
          state.muted = !state.muted;
          renderRail();
          showToast(state.muted ? '已静音' : '已取消静音');
          break;
        case 'settings': openSheet(); break;
        case 'close-sheet': closeSheet(); break;
        case 'bell': state.bell = !state.bell; renderRail(); break;
        case 'power': togglePower(state.device); break;
        case 'power-mini': togglePower(+el.dataset.dev); break;
        case 'inc': setLevel(state.device, state.levels[state.device] + 1); break;
        case 'dec': setLevel(state.device, state.levels[state.device] - 1); break;
      }
      return;
    }
    if (el.dataset.card != null) { openDetail(+el.dataset.card); return; }
    if (el.dataset.scene != null) { applyScene(+el.dataset.scene); return; }
    if (el.dataset.seg != null) {          // 点刻度直接跳档
      setLevel(+el.dataset.dev, +el.dataset.seg + 1);
      return;
    }
    if (el.dataset.chip != null) { setLevel(state.device, QUICK[+el.dataset.chip]); return; }
    if (el.dataset.themeSet) { setTheme(el.dataset.themeSet); return; }
    if (el.dataset.bright != null) { state.bright = +el.dataset.bright; renderBright(); return; }
  });

  // 卡片键盘可达
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') {
      if (sheet.classList.contains('is-open')) { closeSheet(); return; }
      if (state.view === 'detail') { setView('wall'); return; }
    }
    var card = event.target.closest && event.target.closest('[data-card]');
    if (card && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      openDetail(+card.dataset.card);
    }
  });

  // 长按连续调节（与真机"按一下 ±1、按住快调"一致）
  function bindHold(el, step) {
    var delay = null, rep = null;
    function tick() { setLevel(state.device, state.levels[state.device] + step); }
    el.addEventListener('pointerdown', function (event) {
      event.preventDefault();
      tick();
      delay = setTimeout(function () { rep = setInterval(tick, 90); }, 420);
    });
    ['pointerup', 'pointerleave', 'pointercancel'].forEach(function (type) {
      el.addEventListener(type, function () {
        clearTimeout(delay); clearInterval(rep);
      });
    });
  }
  bindHold(document.querySelector('[data-act="inc"]'), 1);
  bindHold(document.querySelector('[data-act="dec"]'), -1);

  // 弹层：点遮罩关闭（点面板内部不关）
  sheet.addEventListener('click', function (event) {
    if (event.target === sheet) closeSheet();
  });

  /* ---------------- 自适应缩放 ---------------- */
  function fit() {
    var scale = Math.min(1, (window.innerWidth - 40) / 1024, (window.innerHeight - 40) / 600);
    screenEl.style.transform = 'scale(' + scale + ')';
    viewport.style.width = 1024 * scale + 'px';
    viewport.style.height = 600 * scale + 'px';
  }
  window.addEventListener('resize', fit);

  /* ---------------- 启动 ---------------- */
  try {
    var saved = localStorage.getItem(THEME_KEY);
    if (saved === 'night' || saved === 'paper') state.theme = saved;
  } catch (e) { /* 忽略 */ }

  /* URL 直达状态，便于演示与截图：
     ?view=detail&device=2&theme=paper&scene=1&level=7&sheet=1 */
  (function applyQuery() {
    var q = new URLSearchParams(window.location.search);
    var view = q.get('view');
    var theme = q.get('theme');
    var device = q.get('device');
    var scene = q.get('scene');
    var level = q.get('level');

    if (theme === 'night' || theme === 'paper') state.theme = theme;
    if (device !== null && !isNaN(+device)) state.device = clamp(+device, 0, DEVICES.length - 1);
    if (scene !== null && !isNaN(+scene)) {
      var s = SCENES[clamp(+scene, 0, SCENES.length - 1)];
      state.levels = s.levels.slice();
      state.scene = clamp(+scene, 0, SCENES.length - 1);
    }
    if (level !== null && !isNaN(+level)) {
      state.levels[state.device] = clamp(+level, 0, LEVELS);
      state.scene = -1;
    }
    if (view === 'detail') {
      openDetail(state.device);
    }
    if (q.get('sheet') === '1') openSheet();
  })();

  renderClock();
  setInterval(renderClock, 15000);
  renderAll();
  renderDetail();
  fit();
})();
