// AZ EREDETI ÉPÜLETRAJZOK KISÜTÉSE (assets/buildings_html).
//
// A böngészős eredeti (index.html) PAINT + natOverlay rajzolóit fej nélküli
// Chrome-ban lefuttatja, és minden épületet, korszakot és nemzetet PNG-be ment:
// <kulcs>.png (az alapkép, fekete csapatszínnel) és <kulcs>_m.png (maszk:
// R = csapatszín, G = kiemelőszín aránya), valamint manifest.json-t (a talp
// helye a képen és a nagyítás). Futtatás a projekt gyökeréből:
//
//   node scripts/dev/html_sutes/drive.mjs index.html assets/buildings_html 2
//
// Utána: Godot --headless --import, majd a .import fájlokban mipmaps/generate=true.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const INDEX = process.argv[2];
const OUT = process.argv[3];
const SCALE = parseFloat(process.argv[4] || '2');
const ONLY = process.argv[5] || '';
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 9333;
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), 'html_sutes_'));
const profile = path.join(WORK, 'profile');
fs.mkdirSync(OUT, { recursive: true });

// A rajzolók a játék belső függvényében (IIFE) élnek, ezért a sütő kódot a
// záró "})();" elé fűzzük be.
const html = fs.readFileSync(INDEX, 'utf8');
const vege = html.lastIndexOf('})();', html.lastIndexOf('</body>'));
fs.writeFileSync(path.join(WORK, 'harness.html'), html.slice(0, vege) + '\n'
  + fs.readFileSync(path.join(HERE, 'bake.js'), 'utf8') + '\n' + html.slice(vege));
const page = 'file:///' + path.join(WORK, 'harness.html').replace(/\\/g, '/');
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--allow-file-access-from-files', '--disable-gpu', '--mute-audio',
  '--window-size=1200,800', page,
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function getWs() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json`);
      const list = await r.json();
      const p = list.find((t) => t.type === 'page');
      if (p) return p.webSocketDebuggerUrl;
    } catch (e) {}
    await sleep(500);
  }
  throw new Error('no chrome');
}

const ws = new WebSocket(await getWs());
await new Promise((r) => ws.addEventListener('open', r));
let seq = 0;
const pending = new Map();
ws.addEventListener('message', (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  if (m.method === 'Runtime.exceptionThrown') console.error('EXC', JSON.stringify(m.params.exceptionDetails).slice(0, 400));
});
function send(method, params = {}) {
  const id = ++seq;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((r) => pending.set(id, r));
}
async function evaluate(expr) {
  const m = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
  if (m.result && m.result.exceptionDetails) throw new Error(JSON.stringify(m.result.exceptionDetails).slice(0, 600));
  return m.result.result.value;
}
await send('Runtime.enable');
for (let i = 0; i < 60; i++) {
  const ok = await evaluate('!!window.__bakeReady').catch(() => false);
  if (ok) break;
  await sleep(500);
}

const TYPES = ['hq', 'barracks', 'stable', 'farm', 'tower', 'house', 'harbor', 'temple',
  'goldmine', 'airfield', 'sugar', 'market', 'hospital', 'smith', 'academy'];
const NATIONS = ['hu', 'es', 'at', 'pl', 'de', 'fr', 'gb', 'ru', 'ns', 'bb', 'sb'];
const LPC_TYPES = ['hq', 'barracks', 'house', 'market', 'tower', 'harbor'];
const PIRATES = ['ns', 'bb', 'sb'];
const manifest = {};
const dataToFile = (url, file) => fs.writeFileSync(file, Buffer.from(url.split(',')[1], 'base64'));
for (const nat of NATIONS) {
  for (const type of TYPES) {
    for (let age = 0; age < 4; age++) {
      const key = `${type}_${age}_${nat}`;
      if (ONLY && !key.startsWith(ONLY)) continue;
      // Pirate factions never leave the sailing age (age 1).
      if (PIRATES.includes(nat) && age !== 1) continue;
      let r;
      try {
        r = await evaluate(`__bakeBuilding(${JSON.stringify(type)},${age},${JSON.stringify(nat)},${SCALE})`);
      } catch (e) { console.error('FAIL', key, e.message); continue; }
      if (!r || r.empty) { console.error('EMPTY', key); continue; }
      dataToFile(r.base, path.join(OUT, key + '.png'));
      if (r.mask) dataToFile(r.mask, path.join(OUT, key + '_m.png'));
      manifest[key] = { ox: r.ox, oy: r.oy, s: r.scale, m: !!r.mask };
    }
  }
  console.log('done', nat);
}
fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest));
ws.close();
chrome.kill();
process.exit(0);
