/*
 * 零依赖 CDP 驱动（用于真实环境自动化测试）
 * 用法：
 *   node cdp.js open <url>                 打开页面并等待加载
 *   node cdp.js eval <js表达式>            在「主页面」上下文求值（支持 await）
 *   node cdp.js evalf <frame子串> <js>      在「URL 含该子串的 frame」上下文求值
 *   node cdp.js frames                     列出所有 frame 的 url
 *   node cdp.js shot <文件路径>             截图
 *   node cdp.js reload                     重新加载当前页
 * 说明：Chrome 需以 --remote-debugging-port=9222 启动
 */
const API = 'http://127.0.0.1:9222';
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function listTargets() {
  const res = await fetch(API + '/json/list');
  return await res.json();
}

function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const pending = new Map();
    const handlers = [];
    let seq = 0;
    ws.onopen = () => resolve({
      send(method, params) {
        const id = ++seq;
        return new Promise((res, rej) => {
          pending.set(id, { res, rej });
          ws.send(JSON.stringify({ id, method, params: params || {} }));
        });
      },
      on(fn) { handlers.push(fn); },
      close() { try { ws.close(); } catch (e) {} },
      raw: ws
    });
    ws.onmessage = ev => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (e) { return; }
      if (msg.id && pending.has(msg.id)) {
        const p = pending.get(msg.id);
        pending.delete(msg.id);
        msg.error ? p.rej(new Error(msg.error.message)) : p.res(msg.result);
      } else if (msg.method) {
        handlers.forEach(h => { try { h(msg); } catch (e) {} });
      }
    };
    ws.onerror = () => reject(new Error('无法连接 CDP（Chrome 是否以 --remote-debugging-port=9222 启动？）'));
  });
}

async function pickPage() {
  const list = await listTargets();
  const page = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
  if (!page) throw new Error('没有可用页面 target');
  return page;
}

async function main() {
  const [action, a1, a2] = process.argv.slice(2);
  if (!action) { console.log('缺少动作参数'); process.exit(1); }

  const page = await pickPage();
  const cdp = await connect(page.webSocketDebuggerUrl);
  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');

  let loadDone = false;
  cdp.on(m => { if (m.method === 'Page.loadEventFired') loadDone = true; });

  try {
    if (action === 'open' || action === 'reload') {
      await cdp.send('Page.navigate', { url: a1 || page.url });
      for (let i = 0; i < 60 && !loadDone; i++) await sleep(250);
      await sleep(1200);
      console.log('OPENED ' + (a1 || page.url));
    } else if (action === 'frames') {
      const tree = await cdp.send('Page.getFrameTree');
      const out = [];
      (function walk(n) {
        out.push(n.frame.url);
        (n.childFrames || []).forEach(walk);
      })(tree.frameTree);
      console.log(out.join('\n'));
    } else if (action === 'eval' || action === 'evalf') {
      const expr = action === 'eval' ? a1 : a2;
      const need = action === 'evalf' ? a1 : null;
      let ctxId = undefined;
      if (need) {
        const tree = await cdp.send('Page.getFrameTree');
        let found = null;
        (function walk(n) {
          if (n.frame.url && n.frame.url.indexOf(need) > -1) found = n.frame;
          (n.childFrames || []).forEach(walk);
        })(tree.frameTree);
        if (!found) throw new Error('未找到匹配 frame: ' + need);
        const res = await cdp.send('Page.createIsolatedWorld', { frameId: found.id, worldName: 'qc' });
        ctxId = res.executionContextId;
      }
      const r = await cdp.send('Runtime.evaluate', {
        expression: expr,
        returnByValue: true,
        awaitPromise: true,
        userGesture: true,
        contextId: ctxId
      });
      if (r.exceptionDetails) {
        console.log('EXCEPTION: ' + JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text));
      } else {
        const v = r.result && r.result.value;
        console.log(typeof v === 'string' ? v : JSON.stringify(v, null, 2));
      }
    } else if (action === 'shot') {
      const r = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
      require('fs').writeFileSync(a1 || 'shot.png', Buffer.from(r.data, 'base64'));
      console.log('SHOT ' + (a1 || 'shot.png'));
    } else {
      console.log('未知动作: ' + action);
    }
  } finally {
    cdp.close();
  }
  process.exit(0);
}

main().catch(e => { console.log('ERROR: ' + e.message); process.exit(2); });
