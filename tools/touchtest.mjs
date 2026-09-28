#!/usr/bin/env node
// IRONLINE touch playtest: mobile-emulated Chromium (hasTouch/isMobile) + CDP multi-touch.
//
//   node tools/touchtest.mjs [scenario.json|name] [--viewport 915x412] [--timeout ms] [--build dir]
//
// Steps (JSON array or {"steps": [...]}):
//   {"wait": ms} {"log": "text"} {"screenshot": "name"} {"godot": "cmd"} {"state": true} {"eval": "js"}
//   {"tap": [x, y]}                                 single finger tap (touchstart+touchend)
//   {"down": {"id": 0, "at": [x, y]}}               finger down (other active fingers kept)
//   {"move": {"id": 0, "to": [x, y], "steps": 8}}   move one finger (interpolated)
//   {"up": 0}                                        finger up
//   {"multi_move": [{"id":0,"to":[x,y]}, {"id":1,"to":[x,y]}], "steps": 8, "step_ms": 60}
//   {"expect": "js expression over s (state)", "label": "..."}  assertion on window state
// Screenshots -> tools/shots/<scenario>/, exit code != 0 on failure / failed expectation.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(TOOLS, '..');
const argv = process.argv.slice(2);
const opt = { timeout: 600000, build: path.join(ROOT, 'build/web'), scenario: 'ui_touch', vw: 915, vh: 412, dpr: 1 };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--viewport') { const [w, h] = argv[++i].split('x').map(Number); opt.vw = w; opt.vh = h; }
  else if (a === '--timeout') opt.timeout = Number(argv[++i]);
  else if (a === '--build') opt.build = path.resolve(argv[++i]);
  else if (a === '--dpr') opt.dpr = Number(argv[++i]);
  else opt.scenario = a;
}
let sp = opt.scenario;
if (!fs.existsSync(sp)) sp = path.join(TOOLS, 'scenarios', `${opt.scenario.replace(/\.json$/, '')}.json`);
if (!fs.existsSync(sp)) { console.error(`scenario not found: ${opt.scenario}`); process.exit(2); }
const name = path.basename(sp, '.json');
const sc = JSON.parse(fs.readFileSync(sp, 'utf8'));
const steps = Array.isArray(sc) ? sc : sc.steps;
const OUT = path.join(TOOLS, 'shots', name);
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(TOOLS, 'shots', '.gdignore'), '');

function loadPlaywright() {
  for (const c of [path.join(TOOLS, 'package.json'), '/opt/tools/package.json', path.join(ROOT, 'package.json')]) {
    try { return createRequire(c)('playwright'); } catch { /* next */ }
  }
  console.error('playwright not found'); process.exit(2);
}
const { chromium } = loadPlaywright();

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
function serve(dir) {
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(dir, path.normalize(p));
    if (!file.startsWith(dir) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((r) => server.listen(0, '127.0.0.1', () => r(server)));
}

const t0 = Date.now();
const log = (...a) => console.log(`[touch ${((Date.now() - t0) / 1000).toFixed(1).padStart(6)}s] ${a.join(' ')}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const GODOT_ERR = /(^|\s)(SCRIPT ERROR|USER SCRIPT ERROR|ERROR|USER ERROR|Parse Error):/;
const result = { failures: [], godotErrors: [], jsErrors: [], shots: [] };

async function main() {
  const server = await serve(opt.build);
  const url = `http://127.0.0.1:${server.address().port}/index.html`;
  const browser = await chromium.launch({
    headless: true,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      '--autoplay-policy=no-user-gesture-required', '--disable-background-timer-throttling', '--disable-renderer-backgrounding'],
  });
  const context = await browser.newContext({ viewport: { width: opt.vw, height: opt.vh }, deviceScaleFactor: opt.dpr, hasTouch: true, isMobile: true });
  const page = await context.newPage();
  let booted = false;
  page.on('console', (m) => {
    const t = m.text();
    if (/Godot Engine v\d/.test(t)) booted = true;
    if (GODOT_ERR.test(t)) { result.godotErrors.push(t.split('\n')[0]); log('GODOT ERROR:', t.split('\n')[0]); }
  });
  page.on('pageerror', (e) => { result.jsErrors.push(String(e)); log('JS ERROR:', e); });
  const cdp = await context.newCDPSession(page);
  await page.goto(url, { waitUntil: 'load' });
  while (!booted) { if (Date.now() - t0 > 180000) throw new Error('no boot'); await sleep(250); }
  await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 120000 }).catch(() => {});
  log('booted; touchscreen:', await page.evaluate(() => navigator.maxTouchPoints));
  await sleep(1000);

  const fingers = new Map(); // id -> {x,y}
  const pts = () => [...fingers.entries()].map(([id, p]) => ({ x: p.x, y: p.y, id, radiusX: 8, radiusY: 8, force: 1 }));
  const touch = (type) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? pts() : pts() });
  const getState = async () => page.evaluate(() => { window.ironline_cmd && window.ironline_cmd('state'); return JSON.parse(window.ironline_state_json || 'null'); });
  const deadline = Date.now() + opt.timeout;

  for (const [i, s] of steps.entries()) {
    if (Date.now() > deadline) throw new Error('timeout');
    const d = JSON.stringify(s); log(`step ${i + 1}/${steps.length}: ${d.length > 110 ? d.slice(0, 107) + '...' : d}`);
    if ('wait' in s) await sleep(s.wait);
    else if ('log' in s) log('#', s.log);
    else if ('screenshot' in s) { const f = path.join(OUT, `${s.screenshot}.png`); await page.screenshot({ path: f }); result.shots.push(path.relative(ROOT, f)); }
    else if ('godot' in s) await page.evaluate((c) => window.ironline_cmd && window.ironline_cmd(c), s.godot);
    else if ('state' in s) log('state =>', JSON.stringify(await getState()));
    else if ('eval' in s) log('eval =>', JSON.stringify(await page.evaluate((c) => (0, eval)(c), s.eval)));
    else if ('tap' in s) {
      const [x, y] = s.tap; const id = 9;
      fingers.set(id, { x, y }); await touch('touchStart');
      await sleep(s.hold ?? 120);
      fingers.delete(id);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: pts() });
    } else if ('down' in s) {
      fingers.set(s.down.id, { x: s.down.at[0], y: s.down.at[1] }); await touch('touchStart');
    } else if ('move' in s) {
      const f = fingers.get(s.move.id); const n = s.move.steps || 8; const [tx, ty] = s.move.to; const sx = f.x, sy = f.y;
      for (let k = 1; k <= n; k++) { f.x = sx + (tx - sx) * k / n; f.y = sy + (ty - sy) * k / n; await touch('touchMove'); await sleep(s.step_ms ?? 50); }
    } else if ('multi_move' in s) {
      const n = s.steps || 8; const starts = s.multi_move.map((m) => ({ ...fingers.get(m.id) }));
      for (let k = 1; k <= n; k++) {
        s.multi_move.forEach((m, j) => { const f = fingers.get(m.id); f.x = starts[j].x + (m.to[0] - starts[j].x) * k / n; f.y = starts[j].y + (m.to[1] - starts[j].y) * k / n; });
        await touch('touchMove'); await sleep(s.step_ms ?? 60);
      }
    } else if ('up' in s) {
      fingers.delete(s.up); await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: pts() });
    } else if ('expect' in s) {
      const st = await getState();
      let ok = false;
      try { ok = !!(new Function('s', 'mem', `return (${s.expect});`))(st, globalThis.__mem || (globalThis.__mem = {})); } catch (e) { ok = false; }
      log(`${ok ? 'PASS' : 'FAIL'}: ${s.label || s.expect}`);
      if (!ok) result.failures.push(s.label || s.expect);
    } else if ('remember' in s) {
      const st = await getState(); (globalThis.__mem || (globalThis.__mem = {}))[s.remember] = st;
      log(`remember ${s.remember} =>`, JSON.stringify(st));
    } else throw new Error(`unknown step ${d}`);
    if (result.jsErrors.length) throw new Error('JS error');
  }
  await browser.close(); server.close();
}

main().catch((e) => { result.failures.push(`exception: ${e.message}`); log(e.stack || e); }).finally(() => {
  console.log('================ TOUCH TEST ================');
  console.log(`scenario : ${name}  viewport ${opt.vw}x${opt.vh}`);
  console.log(`shots    : ${result.shots.length} in ${path.relative(ROOT, OUT)}/`);
  console.log(`failures : ${result.failures.length}`); result.failures.forEach((f) => console.log('   - ' + f));
  console.log(`godot err: ${result.godotErrors.length}`); result.godotErrors.slice(0, 10).forEach((f) => console.log('   - ' + f));
  const ok = !result.failures.length && !result.godotErrors.length && !result.jsErrors.length;
  console.log(`result   : ${ok ? 'PASS' : 'FAIL'}`);
  process.exit(ok ? 0 : 1);
});
