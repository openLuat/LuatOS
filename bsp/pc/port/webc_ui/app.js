(function () {
  const $ = (id) => document.getElementById(id);
  const API = {
    health: '/api/health',
    status: '/api/status',
    telemetry: '/api/telemetry',
    config: '/api/config',
    events: '/api/events',
    uart31Console: '/api/uart31/console',
    uart31Inject: '/api/uart31/inject',
    gnss: '/api/uart32/gnss',
    gnssConfig: '/api/uart32/gnss/config',
    sht20: '/api/mock/sht20',
  };

  const state = {
    status: null,
    telemetry: null,
    config: null,
    uart31: null,
    gnss: null,
    sht20: null,
    source: null,
  };

  async function request(url, options) {
    const res = await fetch(url, options);
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!res.ok) {
      const message = data && data.error ? data.error : res.statusText;
      throw new Error(message);
    }
    return data;
  }

  function fmt(v) {
    if (v == null) return '-';
    if (typeof v === 'object') return JSON.stringify(v, null, 2);
    return String(v);
  }

  function setText(id, value) {
    const el = $(id);
    if (el) el.textContent = fmt(value);
  }

  function setStatusPill(ok, text) {
    const el = $('health-pill');
    if (!el) return;
    el.textContent = text;
    el.style.color = ok ? 'var(--good)' : 'var(--bad)';
    el.style.background = ok ? 'rgba(66,211,146,.12)' : 'rgba(255,107,107,.12)';
  }

  function drawCurve() {
    const canvas = $('memory-curve');
    if (!canvas || !state.telemetry || !state.telemetry.history) return;
    const scale = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    canvas.width = Math.max(1, Math.floor(w * scale));
    canvas.height = Math.max(1, Math.floor(h * scale));
    const ctx = canvas.getContext('2d');
    ctx.scale(scale, scale);
    ctx.clearRect(0, 0, w, h);
    const points = state.telemetry.history;
    const lua = points.map((p) => Number(p.lua_used || 0));
    const sys = points.map((p) => Number(p.sys_used || 0));
    const max = Math.max(1, ...lua, ...sys);
    const pad = 18;
    const plotW = w - pad * 2;
    const plotH = h - pad * 2;
    const xFor = (i) => pad + (points.length <= 1 ? 0 : (i / (points.length - 1)) * plotW);
    const yFor = (v) => pad + plotH - ((v / max) * plotH);

    ctx.strokeStyle = 'rgba(255,255,255,.1)';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const y = pad + (plotH / 4) * i;
      ctx.beginPath();
      ctx.moveTo(pad, y);
      ctx.lineTo(w - pad, y);
      ctx.stroke();
    }

    function line(values, color) {
      if (!values.length) return;
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.beginPath();
      values.forEach((v, i) => {
        const x = xFor(i);
        const y = yFor(v);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
    }

    line(lua, '#57b6ff');
    line(sys, '#42d392');
  }

  function updateDashboard() {
    if (!state.status) return;
    setStatusPill(true, `online · port ${state.status.port}`);
    setText('status-json', state.status);
    setText('op-info', {
      service: 'web-runtime-core',
      cadence_sec: state.status.cadence_sec,
      history_count: state.status.history_count,
      mcu_mhz: state.status.mcu_mhz,
    });
    setText('memory-snapshot', state.status.memory);
  }

  function updateTelemetry() {
    if (!state.telemetry) return;
    setText('telemetry-meta', {
      cadence_sec: state.telemetry.cadence_sec,
      samples: state.telemetry.history ? state.telemetry.history.length : 0,
    });
    drawCurve();
  }

  function updateConfig() {
    if (!state.config) return;
    setText('config-json', state.config);
    const web = state.config.web_console || {};
    const net = state.config.network || {};
    const storage = state.config.storage || {};
    const eff = storage.effective || {};
    const configForm = $('config-form');
    if (configForm) {
      configForm.port.value = web.effective_port || web.port || 0;
      configForm.refresh_interval.value = web.effective_refresh_interval || web.refresh_interval || 5;
    }
    const networkForm = $('network-form');
    if (networkForm) networkForm.enabled.checked = !!net.enabled;
    const storageForm = $('storage-form');
    if (storageForm) {
      storageForm.tf_enabled.checked = !!storage.tf_enabled;
      storageForm.nor_enabled.checked = !!storage.nor_enabled;
      storageForm.nand_enabled.checked = !!storage.nand_enabled;
      storageForm.tf_capacity_mb.value = storage.tf_capacity_mb || 0;
      storageForm.nor_capacity_mb.value = storage.nor_capacity_mb || 0;
      storageForm.nand_capacity_mb.value = storage.nand_capacity_mb || 0;
      storageForm.nor_model.value = storage.nor_model || '';
      storageForm.nand_model.value = storage.nand_model || '';
    }
    setText('network-status', net);
    setText('storage-status', {
      storage,
      effective: eff,
    });
  }

  function updateUart31() {
    if (!state.uart31) return;
    setText('uart31-console', state.uart31);
  }

  function updateGnss() {
    if (!state.gnss) return;
    setText('gnss-status', state.gnss);
    const form = $('gnss-form');
    if (form) {
      form.mode.value = state.gnss.mode || 'fixed';
      form.running.checked = !!state.gnss.running;
      form.lat.value = state.gnss.fixed_lat ?? form.lat.value;
      form.lon.value = state.gnss.fixed_lon ?? form.lon.value;
    }
  }

  function updateSht20() {
    if (!state.sht20) return;
    setText('sht20-status', state.sht20);
    const form = $('sht20-form');
    if (form) {
      form.temperature_c.value = state.sht20.temperature_c ?? '';
      form.humidity_rh.value = state.sht20.humidity_rh ?? '';
    }
  }

  async function loadAll() {
    const [health, status, telemetry, config, uart31, gnss, sht20] = await Promise.all([
      request(API.health),
      request(API.status),
      request(API.telemetry),
      request(API.config),
      request(API.uart31Console),
      request(API.gnss),
      request(API.sht20),
    ]);
    state.status = status;
    state.telemetry = telemetry;
    state.config = config;
    state.uart31 = uart31;
    state.gnss = gnss;
    state.sht20 = sht20;
    setStatusPill(!!health.ok, health.service || 'offline');
    updateDashboard();
    updateTelemetry();
    updateConfig();
    updateUart31();
    updateGnss();
    updateSht20();
  }

  async function refreshSection(name) {
    if (name === 'uart31') state.uart31 = await request(API.uart31Console);
    if (name === 'gnss') state.gnss = await request(API.gnss);
    if (name === 'sht20') state.sht20 = await request(API.sht20);
    if (name === 'config') state.config = await request(API.config);
    if (name === 'status') state.status = await request(API.status);
    if (name === 'telemetry') {
      const [status, telemetry] = await Promise.all([
        request(API.status),
        request(API.telemetry),
      ]);
      state.status = status;
      state.telemetry = telemetry;
    }
    updateDashboard();
    updateTelemetry();
    updateConfig();
    updateUart31();
    updateGnss();
    updateSht20();
  }

  async function postJson(url, body) {
    return request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }

  function bindForms() {
    $('refresh-all').addEventListener('click', () => loadAll());
    $('uart31-refresh').addEventListener('click', () => refreshSection('uart31'));
    $('gnss-refresh').addEventListener('click', () => refreshSection('gnss'));
    $('sht20-refresh').addEventListener('click', () => refreshSection('sht20'));
    $('storage-refresh').addEventListener('click', () => refreshSection('config'));
    $('network-refresh').addEventListener('click', () => refreshSection('config'));
    $('config-refresh').addEventListener('click', () => refreshSection('config'));
    document.querySelectorAll('button[data-cadence]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const cadence = Number(btn.dataset.cadence);
        document.querySelectorAll('button[data-cadence]').forEach((b) => b.classList.toggle('active', b === btn));
        await postJson(API.config, { web_console: { refresh_interval: cadence } });
        await loadAll();
      });
    });

    $('uart31-form').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const form = ev.currentTarget;
      await postJson(API.uart31Inject, {
        direction: form.direction.value,
        encoding: form.encoding.value,
        payload: form.payload.value,
      });
      await refreshSection('uart31');
    });

    $('gnss-form').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const form = ev.currentTarget;
      const body = {
        mode: form.mode.value,
        running: form.running.checked,
      };
      if (form.mode.value === 'fixed') {
        body.fixed = {
          lat: Number(form.lat.value),
          lon: Number(form.lon.value),
          speed_knots: Number(form.speed_knots.value),
          course: Number(form.course.value),
        };
      } else if (form.mode.value === 'kml' || form.mode.value === 'file') {
        body.source_text = form.source_text.value;
      }
      await postJson(API.gnssConfig, body);
      await loadAll();
    });

    $('sht20-form').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const form = ev.currentTarget;
      await postJson(API.sht20, {
        temperature_c: Number(form.temperature_c.value),
        humidity_rh: Number(form.humidity_rh.value),
      });
      await loadAll();
    });

    $('storage-form').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const form = ev.currentTarget;
      await postJson(API.config, {
        storage: {
          tf_enabled: form.tf_enabled.checked ? 1 : 0,
          nor_enabled: form.nor_enabled.checked ? 1 : 0,
          nand_enabled: form.nand_enabled.checked ? 1 : 0,
          tf_capacity_mb: Number(form.tf_capacity_mb.value),
          nor_capacity_mb: Number(form.nor_capacity_mb.value),
          nand_capacity_mb: Number(form.nand_capacity_mb.value),
          nor_model: form.nor_model.value,
          nand_model: form.nand_model.value,
        },
      });
      await loadAll();
    });

    $('network-form').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const form = ev.currentTarget;
      await postJson(API.config, {
        network: {
          enabled: form.enabled.checked ? 1 : 0,
        },
      });
      await loadAll();
    });

    $('config-form').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const form = ev.currentTarget;
      await postJson(API.config, {
        web_console: {
          port: Number(form.port.value),
          refresh_interval: Number(form.refresh_interval.value),
        },
      });
      await loadAll();
    });
  }

  function startTelemetryStream() {
    if (state.source) {
      state.source.close();
    }
    state.source = new EventSource(API.events);
    state.source.addEventListener('telemetry', async () => {
      await refreshSection('telemetry');
    });
    state.source.onerror = () => {
      setStatusPill(false, 'reconnecting…');
    };
  }

  async function bootstrap() {
    bindForms();
    try {
      await loadAll();
      startTelemetryStream();
    } catch (err) {
      setStatusPill(false, err.message);
      setText('status-json', { error: err.message });
    }
    window.addEventListener('resize', drawCurve);
  }

  document.addEventListener('DOMContentLoaded', bootstrap);
}());
