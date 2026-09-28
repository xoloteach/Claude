#!/usr/bin/env node
// IRONLINE headless playtest harness.
//
//   node tools/playtest.mjs [scenario.json|name] [--timeout ms] [--boot-timeout ms]
//        [--build dir] [--port n] [--headed] [--allow-errors] [--keep-open]
//
// Serves build/web, boots the game in headless Chromium (SwiftShader WebGL2),
// runs the scenario steps, writes screenshots to tools/shots/<scenario>/ and the
// console log to tools/shots/console.log. Exit code != 0 on failure.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(TOOLS, '..');

// ---------------------------------------------------------------- args
const argv = process.argv.slice(2);
const opt = { timeout: 300000, bootTimeout: 180000, build: path.join(ROOT, 'build/web'), port: 0,
  headed: false, allowErrors: false, scenario: 'smoke' };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => argv[++i];
  if (a === '--timeout') opt.timeout = Number(next());
  else if (a === '--boot-timeout') opt.bootTimeout = Number(next());
  else if (a === '--build') opt.build = path.resolve(next());
  else if (a === '--port') opt.port = Number(next());
  else if (a === '--headed') opt.headed = true;
  else if (a === '--allow-errors') opt.allowErrors = true;
  else if (a === '-h' || a === '--help') {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 10).join('\n'));
    process.exit(0);
  } else opt.scenario = a;
}
let scenarioPath = opt.scenario;
if (!fs.existsSync(scenarioPath)) scenarioPath = path.join(TOOLS, 'scenarios', `${opt.scenario.replace(/\.json$/, '')}.json`);
if (!fs.existsSync(scenarioPath)) die(`scenario not found: ${opt.scenario}`);
const scenarioName = path.basename(scenarioPath, '.json');
const scenario = JSON.parse(fs.readFileSync(scenarioPath, 'utf8'));
const steps = Array.isArray(scenario) ? scenario : scenario.steps;
if (!Array.isArray(steps)) die('scenario must be an array of steps or {"steps":[...]}');
if (!fs.existsSync(path.join(opt.build, 'index.html'))) die(`no export at ${opt.build}; run tools/export_web.sh first`);

const SHOTS = path.join(TOOLS, 'shots');
const OUT = path.join(SHOTS, scenarioName);
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(SHOTS, '.gdignore'), ''); // keep Godot from importing screenshots
const consoleLogPath = path.join(SHOTS, 'console.log');
const consoleLog = fs.createWriteStream(consoleLogPath);

// ---------------------------------------------------------------- playwright
function loadPlaywright() {
  const candidates = [path.join(TOOLS, 'package.json'), '/opt/tools/package.json', path.join(ROOT, 'package.json')];
  for (const c of candidates) {
    try { return createRequire(c)('playwright'); } catch { /* next */ }
  }
  die('playwright not found. Run `npm ci --prefix tools && npx --prefix tools playwright install chromium`');
}
const { chromium } = loadPlaywright();

// ---------------------------------------------------------------- static server
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
  '.css': 'text/css', '.txt': 'text/plain', '.jpg': 'image/jpeg', '.webp': 'image/webp',
};
function serve(dir, port) {
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(dir, path.normalize(p));
    if (!file.startsWith(dir) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      res.writeHead(404); res.end('not found'); return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': fs.statSync(file).size, 'Cache-Control': 'no-store',
    });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}

// ---------------------------------------------------------------- helpers
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(1).padStart(6) + 's';
function log(...a) { const s = `[playtest ${ts()}] ${a.join(' ')}`; console.log(s); consoleLog.write(s + '\n'); }
function die(msg) { console.error(`[playtest] FATAL: ${msg}`); process.exit(2); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const GODOT_ERR = /(^|\s)(SCRIPT ERROR|USER SCRIPT ERROR|ERROR|USER ERROR|Parse Error):/;

const summary = { scenario: scenarioName, bootMs: null, steps: 0, screenshots: [], fps: [], jsErrors: [],
  godotErrors: [], warnings: [], bridge: false, result: 'FAIL' };

// ---------------------------------------------------------------- main
async function main() {
  const server = await serve(opt.build, opt.port);
  const url = `http://127.0.0.1:${server.address().port}/index.html`;
  log(`serving ${path.relative(ROOT, opt.build)} at ${url}`);

  const browser = await chromium.launch({
    headless: !opt.headed,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      '--autoplay-policy=no-user-gesture-required', '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows'],
  });
  const context = await browser.newContext({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  page.setDefaultTimeout(opt.timeout);

  let booted = false;
  page.on('console', (m) => {
    const text = m.text();
    consoleLog.write(`[${ts()}] [${m.type()}] ${text}\n`);
    if (/Godot Engine v\d/.test(text)) booted = true;
    if (GODOT_ERR.test(text)) { summary.godotErrors.push(text.split('\n')[0]); log(`GODOT ERROR: ${text.split('\n')[0]}`); }
  });
  page.on('pageerror', (e) => { summary.jsErrors.push(String(e)); log(`JS ERROR: ${e}`); });
  page.on('crash', () => { summary.jsErrors.push('page crashed'); log('PAGE CRASHED'); });
  page.on('requestfailed', (r) => log(`request failed: ${r.url()} ${r.failure()?.errorText}`));

  // In-page FPS fallback counter (rAF based) + bridge helpers.
  await page.addInitScript(() => {
    window.__pt = { frames: 0, last: performance.now(), fps: 0 };
    const tick = (t) => {
      const s = window.__pt; s.frames++;
      if (t - s.last >= 1000) { s.fps = (s.frames * 1000) / (t - s.last); s.frames = 0; s.last = t; }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    window.__pt_state = () => {
      try {
        let s = typeof window.ironline_state === 'function' ? window.ironline_state() : window.ironline_state;
        if (s == null && window.ironline_state_json != null) s = window.ironline_state_json;
        if (typeof s === 'string') s = JSON.parse(s);
        return s ?? null;
      } catch (e) { return { error: String(e) }; }
    };
  });

  log(`loading game (boot timeout ${opt.bootTimeout} ms) ...`);
  const bootStart = Date.now();
  await page.goto(url, { waitUntil: 'load', timeout: opt.bootTimeout });
  while (!booted) {
    if (Date.now() - bootStart > opt.bootTimeout) throw new Error(`engine did not boot within ${opt.bootTimeout} ms`);
    if (summary.jsErrors.length) throw new Error('JS error during boot');
    await sleep(250);
  }
  // Wait for the loading overlay to disappear (engine started main loop).
  // The default shell calls statusOverlay.remove() once startGame() resolves.
  await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: Math.max(1000, opt.bootTimeout - (Date.now() - bootStart)) }).catch(() => log('warning: status overlay still visible'));
  summary.bootMs = Date.now() - bootStart;
  log(`engine booted in ${(summary.bootMs / 1000).toFixed(1)} s`);
  await sleep(1000);
  summary.bridge = await page.evaluate(() => typeof window.ironline_cmd === 'function');
  log(`JS bridge window.ironline_cmd: ${summary.bridge ? 'present' : 'ABSENT (godot steps will be skipped)'}`);

  const mouse = { x: 800, y: 450 };
  const deadline = Date.now() + opt.timeout;
  for (const [i, step] of steps.entries()) {
    if (Date.now() > deadline) throw new Error(`scenario timeout (${opt.timeout} ms) at step ${i}`);
    summary.steps++;
    const desc = JSON.stringify(step);
    log(`step ${i + 1}/${steps.length}: ${desc.length > 120 ? desc.slice(0, 117) + '...' : desc}`);
    await runStep(page, step, mouse);
    if (summary.jsErrors.length) throw new Error(`JS error after step ${i + 1}`);
  }
  await sampleFps(page, 'end');
  await browser.close();
  server.close();
}

async function sampleFps(page, label) {
  const r = await page.evaluate(() => ({ state: window.__pt_state(), raf: window.__pt.fps }));
  const fps = r.state && typeof r.state.fps === 'number' ? r.state.fps : null;
  summary.fps.push({ label, game: fps, raf: Math.round(r.raf * 10) / 10 });
  log(`fps @${label}: game=${fps ?? 'n/a'} raf=${r.raf.toFixed(1)}`);
}

async function godotCmd(page, cmd) {
  const ok = await page.evaluate((c) => {
    if (typeof window.ironline_cmd !== 'function') return false;
    window.ironline_cmd(c); return true;
  }, cmd);
  if (!ok) { const w = `window.ironline_cmd missing; skipped godot cmd "${cmd}"`; summary.warnings.push(w); log('warning:', w); }
  return ok;
}

async function runStep(page, s, mouse) {
  if ('wait' in s) return sleep(s.wait);
  if ('log' in s) return log(`# ${s.log}`);
  if ('click' in s) {
    const [x, y] = s.click; mouse.x = x; mouse.y = y;
    return page.mouse.click(x, y, { button: s.button || 'left', delay: s.delay ?? 60 });
  }
  if ('mouse_move' in s) {
    const [dx, dy] = s.mouse_move; mouse.x += dx; mouse.y += dy;
    return page.mouse.move(mouse.x, mouse.y, { steps: s.steps || 1 });
  }
  if ('mouse_to' in s) {
    [mouse.x, mouse.y] = s.mouse_to;
    return page.mouse.move(mouse.x, mouse.y, { steps: s.steps || 1 });
  }
  if ('mouse_down' in s) return page.mouse.down({ button: s.mouse_down || 'left' });
  if ('mouse_up' in s) return page.mouse.up({ button: s.mouse_up || 'left' });
  if ('key' in s) {
    if (s.up) return page.keyboard.up(s.key);
    return page.keyboard.down(s.key);
  }
  if ('press' in s) return page.keyboard.press(s.press, { delay: s.delay ?? 80 });
  if ('screenshot' in s) {
    const file = path.join(OUT, `${s.screenshot}.png`);
    await page.screenshot({ path: file });
    summary.screenshots.push(path.relative(ROOT, file));
    log(`screenshot -> ${path.relative(ROOT, file)}`);
    return sampleFps(page, s.screenshot);
  }
  if ('eval' in s) {
    const r = await page.evaluate((code) => { const v = (0, eval)(code); return v === undefined ? 'undefined' : JSON.stringify(v); }, s.eval);
    return log(`eval => ${r}`);
  }
  if ('godot' in s) {
    const ok = await godotCmd(page, s.godot);
    if (ok && /^state\b/.test(s.godot)) {
      await sleep(50);
      const st = await page.evaluate(() => window.__pt_state());
      log(`state => ${JSON.stringify(st)}`);
    }
    return;
  }
  if ('wait_for' in s) {
    return page.waitForFunction(s.wait_for, null, { timeout: s.timeout || 30000 });
  }
  if ('fps' in s) return sampleFps(page, s.fps || 'sample');
  throw new Error(`unknown step: ${JSON.stringify(s)}`);
}

function printSummary() {
  if (!opt.allowErrors && summary.godotErrors.length && summary.result === 'PASS') summary.result = 'FAIL';
  const L = [];
  L.push('================ PLAYTEST SUMMARY ================');
  L.push(`scenario     : ${summary.scenario} (${summary.steps}/${steps.length} steps)`);
  L.push(`result       : ${summary.result}${summary.reason ? ' - ' + summary.reason : ''}`);
  L.push(`boot time    : ${summary.bootMs != null ? (summary.bootMs / 1000).toFixed(1) + ' s' : 'did not boot'}`);
  L.push(`js bridge    : ${summary.bridge ? 'yes' : 'no'}`);
  L.push(`fps samples  : ${summary.fps.map((f) => `${f.label}=${f.game ?? '-'}/${f.raf}`).join(' ') || 'none'}  (game/raf)`);
  L.push(`screenshots  : ${summary.screenshots.length} in ${path.relative(ROOT, OUT)}/`);
  L.push(`js errors    : ${summary.jsErrors.length}`); summary.jsErrors.slice(0, 10).forEach((e) => L.push(`   - ${e}`));
  L.push(`godot errors : ${summary.godotErrors.length}`); summary.godotErrors.slice(0, 10).forEach((e) => L.push(`   - ${e}`));
  L.push(`warnings     : ${summary.warnings.length}`);
  L.push(`console log  : ${path.relative(ROOT, consoleLogPath)}`);
  L.push(`total time   : ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  L.push('==================================================');
  const s = L.join('\n'); console.log(s); consoleLog.write(s + '\n');
  fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 2));
}

const hardKill = setTimeout(() => { summary.reason = 'hard timeout'; printSummary(); process.exit(1); },
  opt.timeout + opt.bootTimeout + 60000);
main().then(() => {
  summary.result = summary.jsErrors.length ? 'FAIL' : 'PASS';
  if (summary.jsErrors.length) summary.reason = 'uncaught JS errors';
  else if (summary.godotErrors.length && !opt.allowErrors) summary.reason = 'Godot ERROR lines in console';
}).catch((e) => {
  summary.result = 'FAIL'; summary.reason = e.message; log(`FAILED: ${e.stack || e}`);
}).finally(() => {
  clearTimeout(hardKill);
  printSummary();
  consoleLog.end(() => process.exit(summary.result === 'PASS' ? 0 : 1));
});
