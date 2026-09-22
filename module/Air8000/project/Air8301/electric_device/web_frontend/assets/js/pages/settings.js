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
