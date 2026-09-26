// Injected after index.html's main script. Renders the HTML building painters
// (PAINT + natOverlay) off-screen and returns base + team-colour mask images.
window.__nat = 'hu';
window.__col = '#000000';
window.__acc = '#000000';
nationOf = function(o){ return window.__nat; };
ownerColor = function(o){ return window.__col; };
ownerAccent = function(o){ return window.__acc; };

function __renderOne(type, age, nation, scale, col, acc){
  window.__col = col; window.__acc = acc; window.__nat = nation;
  G.nation = nation;
  const painter = PAINT[type] || PAINT.barracks;
  const d = BUILDS[type] || BUILDS.barracks;
  const H = bhOf(type, age);
  const padT = (type === 'tower' && age === 0) ? 120 : 64;
  const padL = 46, padR = 52, padB = 34;
  const cw = d.w + padL + padR, ch = d.h + H + padT + padB;
  const cn = document.createElement('canvas');
  cn.width = Math.ceil(cw * scale); cn.height = Math.ceil(ch * scale);
  const cg = cn.getContext('2d');
  cg.setTransform(scale, 0, 0, scale, 0, 0);
  const ox = padL + d.w / 2, oy = padT + H + d.h / 2;
  cg.translate(ox, oy);
  const prev = GX; GX = cg;
  SHADOW_BAKE = true;
  if (typeof toronySisakNemzet === 'function') toronySisakNemzet(nation);
  const key = type + '|' + age + '|0|' + nation;
  painter(d.w, d.h, H, age, 0, seedRand(key));
  SHADOW_BAKE = false;
  natOverlay(type, d.w, d.h, H, age, 0, seedRand(key + 'n'));
  GX = prev;
  return { cn, ox: ox * scale, oy: oy * scale, w: d.w, h: d.h, H };
}

window.__bakeBuilding = function(type, age, nation, scale){
  const r0 = __renderOne(type, age, nation, scale, '#000000', '#000000');
  const r1 = __renderOne(type, age, nation, scale, '#ffffff', '#000000');
  const r2 = __renderOne(type, age, nation, scale, '#000000', '#ffffff');
  const W = r0.cn.width, Hc = r0.cn.height;
  const d0 = r0.cn.getContext('2d').getImageData(0, 0, W, Hc).data;
  const d1 = r1.cn.getContext('2d').getImageData(0, 0, W, Hc).data;
  const d2 = r2.cn.getContext('2d').getImageData(0, 0, W, Hc).data;
  // bounding box of visible pixels
  let x0 = W, y0 = Hc, x1 = -1, y1 = -1;
  for (let y = 0; y < Hc; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    if (d0[i + 3] > 2 || d1[i + 3] > 2 || d2[i + 3] > 2) {
      if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
  }
  if (x1 < 0) return { empty: true };
  x0 = Math.max(0, x0 - 1); y0 = Math.max(0, y0 - 1);
  x1 = Math.min(W - 1, x1 + 1); y1 = Math.min(Hc - 1, y1 + 1);
  const cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  const base = document.createElement('canvas'); base.width = cw; base.height = ch;
  const mask = document.createElement('canvas'); mask.width = cw; mask.height = ch;
  const bg = base.getContext('2d'), mg = mask.getContext('2d');
  const bi = bg.createImageData(cw, ch), mi = mg.createImageData(cw, ch);
  let maxMask = 0;
  for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
    const s = ((y + y0) * W + (x + x0)) * 4, t = (y * cw + x) * 4;
    bi.data[t] = d0[s]; bi.data[t + 1] = d0[s + 1]; bi.data[t + 2] = d0[s + 2]; bi.data[t + 3] = d0[s + 3];
    let mc = 0, ma = 0;
    if (d0[s + 3] > 0) {
      mc = ((d1[s] - d0[s]) + (d1[s + 1] - d0[s + 1]) + (d1[s + 2] - d0[s + 2])) / 3;
      ma = ((d2[s] - d0[s]) + (d2[s + 1] - d0[s + 1]) + (d2[s + 2] - d0[s + 2])) / 3;
    }
    mc = Math.max(0, Math.min(255, Math.round(mc)));
    ma = Math.max(0, Math.min(255, Math.round(ma)));
    if (mc > maxMask) maxMask = mc; if (ma > maxMask) maxMask = ma;
    mi.data[t] = mc; mi.data[t + 1] = ma; mi.data[t + 2] = 0; mi.data[t + 3] = 255;
  }
  bg.putImageData(bi, 0, 0); mg.putImageData(mi, 0, 0);
  return {
    base: base.toDataURL('image/png'),
    mask: maxMask > 3 ? mask.toDataURL('image/png') : null,
    ox: r0.ox - x0, oy: r0.oy - y0, w: r0.w, h: r0.h, H: r0.H, scale,
  };
};
window.__bakeReady = true;
