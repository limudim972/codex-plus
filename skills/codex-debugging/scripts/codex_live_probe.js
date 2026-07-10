#!/usr/bin/env node

const args = process.argv.slice(2);
const getArg = (name, fallback = null) => {
  const exact = args.find((arg) => arg === `--${name}` || arg.startsWith(`--${name}=`));
  if (!exact) return fallback;
  if (exact.includes('=')) return exact.split('=').slice(1).join('=');
  const idx = args.indexOf(exact);
  return idx >= 0 && idx + 1 < args.length ? args[idx + 1] : fallback;
};

const port = Number(getArg('port', '18317'));
const selector = getArg('selector', '');
const jsonListUrl = `http://127.0.0.1:${port}/json/list`;

async function main() {
  const list = await fetch(jsonListUrl).then((r) => {
    if (!r.ok) throw new Error(`Unable to fetch ${jsonListUrl}: ${r.status}`);
    return r.json();
  });

  const pages = Array.isArray(list) ? list : list.value || [];
  const page =
    pages.find((item) => item && item.type === 'page' && /app:\/\/-\/index\.html$/i.test(String(item.url || '')) && /codex/i.test(String(item.title || ''))) ||
    pages.find((item) => item && item.type === 'page' && /app:\/\/-\/index\.html$/i.test(String(item.url || ''))) ||
    pages.find((item) => item && item.type === 'page' && /codex/i.test(String(item.title || ''))) ||
    pages.find((item) => item && item.type === 'page' && item.webSocketDebuggerUrl) ||
    pages[0];
  if (!page || !page.webSocketDebuggerUrl) {
    throw new Error('No debugger target found');
  }

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let nextId = 1;
  const pending = new Map();

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  };

  const send = (method, params = {}) => {
    const id = nextId++;
    ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve) => pending.set(id, resolve));
  };

  await new Promise((resolve, reject) => {
    ws.onopen = resolve;
    ws.onerror = reject;
  });

  await send('Runtime.enable');
  const expression = `(() => {
    const payload = {
      title: document.title,
      url: location.href,
      readyState: document.readyState,
      bodyText: document.body ? document.body.innerText.slice(0, 600) : ''
    };
    const target = ${JSON.stringify(selector)} ? document.querySelector(${JSON.stringify(selector)}) : null;
    if (target) {
      payload.target = {
        tag: target.tagName.toLowerCase(),
        className: typeof target.className === 'string' ? target.className : '',
        id: target.id || '',
        text: (target.innerText || '').slice(0, 600),
        dir: target.getAttribute('dir') || '',
        styleDirection: getComputedStyle(target).direction,
        textAlign: getComputedStyle(target).textAlign,
        unicodeBidi: getComputedStyle(target).unicodeBidi
      };
    }
    return payload;
  })()`;

  const result = await send('Runtime.evaluate', {
    expression,
    returnByValue: true,
  });

  console.log(JSON.stringify(result.result.result.value, null, 2));
  ws.close();
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exitCode = 1;
});
