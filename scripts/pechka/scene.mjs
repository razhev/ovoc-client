// Сцена «изба, печь, ушат и Вовка» для приложения и холста Design.
// Пересобрать App/Scene/scene.html: `make scene`.
// Всё рисуется в координатах 390×470 (верх телефона), контуры — «сажей».

export const C = {
  ink: '#2A1F1B', inkSoft: '#66523F', smetana: '#F6EBD4', muka: '#FFF8EA',
  ryabina: '#B83E27', med: '#F2B33D', medTint: '#FBE3B0', izrazets: '#2A6B68',
  noch: '#22304F', nochTint: '#DDE2EE', zhar: '#F07A2A', klyukva: '#9B2A1B',
  testo: '#F3D6A4', testoShade: '#E3BC80', testoLight: '#FFF3DC', rumyanets: '#EC8E7C',
  log1: '#CF9D66', log2: '#C7945C', logSeam: '#8A5730', logHi: '#E2B886',
  floor: '#7E4E2B', floorSeam: '#5F3A20',
  pobelka: '#F1ECE1', pobelkaShade: '#DDD4C5', soot: '#2B211E',
  iron: '#3B3634', ironHi: '#5E5754',
  valenok: '#8C8580', valenokCuff: '#ABA49D', skin: '#F6C9A0', nose: '#F2B08C',
  hair: '#A23E1C', shirt: '#3F8A86', shorts: '#2F3E6B', apron: '#FBF3E4',
  paper: '#EFE9DC', print: '#A39A8B',
  wood: '#A8652F', woodDark: '#7E4A22', woodInner: '#4E2F18', hoop: '#4A4442',
  smoke: '#8F8A85', smokeHi: '#B8B3AD', glass: '#22304F', moon: '#FFF1C1',
  sash: '#E8DCC0', mouth: '#7A2E1E',
};
const INK = C.ink;

// ---------- мелкие помощники ----------
const r1 = (n) => Math.round(n * 10) / 10;
const pt = ([x, y]) => `${r1(x)} ${r1(y)}`;
const rad = (d) => (d * Math.PI) / 180;
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const mul = (a, k) => [a[0] * k, a[1] * k];
const len = (v) => Math.hypot(v[0], v[1]);
// поворот как у SVG rotate(): положительный угол — по часовой на экране
export const rot = ([x, y], deg, [cx, cy] = [0, 0]) => {
  const a = rad(deg), c = Math.cos(a), s = Math.sin(a), dx = x - cx, dy = y - cy;
  return [cx + dx * c - dy * s, cy + dx * s + dy * c];
};
// направление конечности: 0° — вниз, +90° — вперёд (+x)
const dirv = (phi) => [Math.sin(rad(phi)), Math.cos(rad(phi))];

function attrs(a) {
  return Object.entries(a)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => `${k}="${typeof v === 'number' ? r1(v) : v}"`)
    .join(' ');
}
export const el = (tag, a = {}, children = '') => `<${tag} ${attrs(a)}>${children}</${tag}>`;
export const P = (d, a = {}) => el('path', { d, ...a });
export const circ = (cx, cy, r, a = {}) => el('circle', { cx, cy, r, ...a });
export const ell = (cx, cy, rx, ry, a = {}) => el('ellipse', { cx, cy, rx, ry, ...a });
export const rect = (x, y, width, height, a = {}) => el('rect', { x, y, width, height, ...a });
export const g = (a, children) => el('g', a, children);
export const S = (w = 2.5, color = INK) => ({
  stroke: color, 'stroke-width': w, 'stroke-linejoin': 'round', 'stroke-linecap': 'round',
});
const line = (d, color, w, extra = {}) =>
  P(d, { fill: 'none', stroke: color, 'stroke-width': w, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', ...extra });

// 4-лучевая искорка и 5-конечная звёздочка
export const star4 = (x, y, s, fill = C.med) =>
  P(`M ${x} ${y - s} Q ${x} ${y} ${x + s} ${y} Q ${x} ${y} ${x} ${y + s} Q ${x} ${y} ${x - s} ${y} Q ${x} ${y} ${x} ${y - s} Z`,
    { fill, ...S(1.4) });
function star5(x, y, r, fill = C.med) {
  const pts = [];
  for (let i = 0; i < 10; i++) {
    const a = rad(-90 + i * 36), rr = i % 2 ? r * 0.45 : r;
    pts.push([x + rr * Math.cos(a), y + rr * Math.sin(a)]);
  }
  return P('M ' + pts.map(pt).join(' L ') + ' Z', { fill, ...S(1.5) });
}
// облако: сначала толстые контуры всех кругов, потом заливки поверх — получается общий силуэт
function cloud(circles, fill, hi) {
  const outline = circles.map(([x, y, r]) => circ(x, y, r, { fill: INK, stroke: INK, 'stroke-width': 5 })).join('');
  const body = circles.map(([x, y, r]) => circ(x, y, r, { fill })).join('');
  const shine = hi ? circles.map(([x, y, r]) => circ(x - r * 0.3, y - r * 0.35, r * 0.35, { fill: hi })).join('') : '';
  return outline + body + shine;
}

// ---------- двухзвенная рука: плечо → кисть в точку target ----------
const ARM1 = 20, ARM2 = 19, LEG = 22;
function ik(Sh, T, L1, L2, bend) {
  let d = sub(T, Sh), dist = len(d);
  const maxR = L1 + L2 - 0.6, minR = Math.abs(L1 - L2) + 0.6;
  if (dist > maxR) { d = mul(d, maxR / dist); dist = maxR; }
  if (dist < minR) { d = mul(d, minR / dist); dist = minR; }
  const base = Math.atan2(d[1], d[0]);
  const a = Math.acos(Math.max(-1, Math.min(1, (L1 * L1 + dist * dist - L2 * L2) / (2 * L1 * dist))));
  const ang = base + bend * a;
  return { E: [Sh[0] + L1 * Math.cos(ang), Sh[1] + L1 * Math.sin(ang)], W: add(Sh, d) };
}

// ---------- Вовка ----------
function boot() {
  const body = 'M -8 -12 Q 0 -15.5 8 -12 L 8.5 7 Q 9.5 11 15 11.5 Q 22.5 12.5 22.5 17 Q 22.5 22 16.5 22 L -5.5 22 Q -9.5 22 -9.5 17.5 Z';
  const cuff = 'M -8 -12 Q 0 -15.5 8 -12 L 8.3 -5.5 Q 0 -9 -8.3 -5.5 Z';
  return P(body, { fill: C.valenok, ...S(2.3) }) + P(cuff, { fill: C.valenokCuff, ...S(2) })
    + circ(2, 3, 0.9, { fill: '#6E6863' }) + circ(-3, 10, 0.9, { fill: '#6E6863' }) + circ(13, 16.5, 0.9, { fill: '#6E6863' });
}
const SOLE = [[-5.5, 22], [16.5, 22], [22.5, 17], [-9.5, 17.5]];

function hairPath() {
  const H = (th, r) => [r * Math.cos(rad(th)), -r * Math.sin(rad(th))];
  const pts = [H(26, 27.6), H(33, 21.5), H(40, 30.5), H(47, 23), H(54, 31)];
  for (let th = 61; th <= 201; th += 7) pts.push(H(th, th > 150 ? 32 : 31));
  pts.push(H(207, 34.5), H(213, 28.5), H(220, 34), H(226, 27), H(232, 30.5), H(237, 23));
  for (let th = 226; th >= 71; th -= 15) pts.push(H(th, th > 130 ? 19 : 21 + (130 - th) / 18));
  pts.push(H(58, 25));
  return 'M ' + pts.map(pt).join(' L ') + ' Z';
}

export function hat(extra = '') {
  const top = 'M -25.5 -22 L 23.5 -28 L -6 -55 Z';
  const band = 'M -27 -15 L 24 -21 L 23.5 -28 L -25.5 -22 Z';
  return P(top, { fill: C.paper, ...S(2.2) })
    + line('M -15 -31 L 8 -33.8', C.print, 1.3) + line('M -12 -36.5 L 4.5 -38.3', C.print, 1.3)
    + line('M -9 -42 L 0 -43', C.print, 1.3) + line('M -17 -27 L -3 -28.6', C.print, 2.2)
    + P(band, { fill: C.paper, ...S(2.2) })
    + line('M -20 -18.8 L 17 -23.3', C.print, 1.1, { 'stroke-dasharray': '3 2.5' }) + extra;
}

function face(kind) {
  const eye = ell(14, -2, 3.3, 4.3, { fill: INK }) + circ(15.3, -3.6, 1.2, { fill: '#FFFFFF' });
  const brow = (d, w = 2.2) => line(d, INK, w);
  switch (kind) {
    case 'sleep':
      return line('M 10 -1 Q 14 2.6 18 -1', INK, 2.1) + brow('M 9 -9.5 Q 14 -11.5 19 -9.5', 1.9)
        + ell(19, 19.5, 2.4, 3, { fill: C.mouth, ...S(1.5) });
    case 'effort':
      return line('M 18.5 -5.5 L 11 -2 L 18.5 1.5', INK, 2.2) + brow('M 8 -13 L 20.5 -8.5')
        + rect(12, 14.5, 12.5, 7, { rx: 2, fill: '#FFFFFF', ...S(1.8) })
        + line('M 12.5 18 L 24 18', INK, 1) + line('M 16.5 15 L 16.5 21 M 20.5 15 L 20.5 21', INK, 1);
    case 'laugh':
      return line('M 10 -1 Q 14 -6.8 18 -1', INK, 2.2) + brow('M 8.5 -14 Q 14 -18.5 20 -15', 2)
        + P('M 11 15 Q 18 29 26 14 Z', { fill: C.mouth, ...S(2) }) + ell(18.5, 19.8, 3.4, 1.9, { fill: C.rumyanets });
    case 'daze':
      return line('M 14 -2 A 1.2 1.2 0 0 1 16.4 -2 A 2.4 2.4 0 0 1 11.6 -2 A 3.6 3.6 0 0 1 18.8 -2', INK, 1.6)
        + brow('M 8.5 -12 Q 14 -10 20 -13', 1.9) + line('M 11 20 Q 14 17 17 20 Q 20 23 23 20', INK, 2);
    case 'puzzled':
      return ell(14.5, 0, 3.3, 4.3, { fill: INK }) + circ(15.8, -1.6, 1.2, { fill: '#FFFFFF' })
        + brow('M 8 -16.5 Q 13 -21 19 -16.5') + line('M 13 21.5 Q 17 18.5 22.5 21.5', INK, 2);
    default:
      return eye + brow('M 9 -12 Q 14 -15 20 -12') + line('M 12 19 Q 18 24 24 18.5', INK, 2);
  }
}

// o: {x, y, flip, torso, head, legs:{far,near}, arms:{far,near}, face, hat:{rot,dx,dy}|null, soot, singed, hipFromFloor}
export function vovka(o) {
  const T = o.torso ?? 0;
  const Sh = rot([0, -34], T);
  const N0 = [1, -40], N = rot(N0, T);
  const headAbs = T + (o.head ?? 0);
  const Hc = add(N, rot(sub([4, -66], N0), headAbs));
  const hipF = rot([-5, 3], T), hipN = rot([5, 3], T);

  // «встаём» на пол: средняя из нижних точек двух подошв = o.floor
  const legEnd = (hip, psi) => add(hip, mul(dirv(psi), LEG));
  let y = o.y;
  if (o.floor !== undefined) {
    const lows = [[hipF, o.legs.far], [hipN, o.legs.near]].map(([hip, psi]) => {
      const A = legEnd(hip, psi);
      return Math.max(...SOLE.map((s) => add(A, rot(s, -psi))[1]));
    });
    y = o.floor - (lows[0] + lows[1]) / 2;
  }

  const arm = (spec) => {
    if (spec.target) return ik(Sh, spec.target({ Hc, Sh, y }), ARM1, ARM2, spec.bend ?? 1);
    const E = add(Sh, mul(dirv(spec.a1), ARM1));
    return { E, W: add(E, mul(dirv(spec.a2), ARM2)) };
  };
  const aF = arm(o.arms.far), aN = arm(o.arms.near);
  const toScene = (p) => [o.x + (o.flip ? -p[0] : p[0]), y + p[1]];

  const drawArm = ({ E, W }) => {
    const d = `M ${pt(Sh)} L ${pt(E)} L ${pt(W)}`;
    const sl = `M ${pt(Sh)} L ${pt(add(Sh, mul(sub(E, Sh), 0.5)))}`;
    return line(d, INK, 10.5) + line(d, C.skin, 6.5) + line(sl, INK, 14) + line(sl, C.shirt, 10)
      + circ(W[0], W[1], 5.8, { fill: C.skin, ...S(2) });
  };
  const drawLeg = (hip, psi) => {
    const A = legEnd(hip, psi), d = `M ${pt(hip)} L ${pt(A)}`;
    return line(d, INK, 11.5) + line(d, C.skin, 7.5) + g({ transform: `translate(${pt(A)}) rotate(${r1(-psi)})` }, boot());
  };
  const torso = g({ transform: `rotate(${r1(T)})` },
    P('M -14 -10 L 14 -10 Q 17 -2 17 8 L 4 8 L 0 4 L -4 8 L -17 8 Q -17 -2 -14 -10 Z', { fill: C.shorts, ...S(2.5) })
    + P('M -15 -5 Q -16 -24 -12 -34 Q -8 -41 0 -41 Q 8 -41 12 -34 Q 16 -24 15 -5 Q 0 -2 -15 -5 Z', { fill: C.shirt, ...S(2.5) })
    + P('M 3 -33 Q 10 -35 14 -31 Q 18 -16 18.5 5 Q 10 8 1.5 6 Q 3 -14 3 -33 Z', { fill: C.apron, ...S(2.2) })
    + line('M 5 -33 L -3 -40.5', INK, 2) + line('M 2 -13 L -15 -13', INK, 1.8)
    + ell(-17, -15.5, 3.6, 2.2, { fill: C.apron, ...S(1.5), transform: 'rotate(-30 -17 -15.5)' })
    + ell(-17, -10.5, 3.6, 2.2, { fill: C.apron, ...S(1.5), transform: 'rotate(30 -17 -10.5)' })
    + rect(6.5, -8, 8, 7, { rx: 2, fill: 'none', ...S(1.3) })
    + ell(12, -22, 3, 1.8, { fill: '#FFFFFF', opacity: 0.9 }) + ell(8, 0, 2, 1.3, { fill: '#FFFFFF', opacity: 0.9 }));

  const soot = o.soot
    ? ell(29, 5.5, 3.3, 2.8, { fill: INK, opacity: 0.32 }) + ell(8.5, 9, 5, 2.8, { fill: INK, opacity: 0.2 })
      + ell(6, -13, 4, 2.2, { fill: INK, opacity: 0.2 })
    : '';
  const tuft = o.hat ? '' :
    P('M -9 -26 Q -18 -38 -15 -47 Q -8 -38 -4 -30 Q -4 -43 1 -51 Q 5 -40 3 -29 Q 9 -38 16 -41 Q 12 -32 7 -26 Z',
      { fill: C.hair, ...S(2.2) })
    + (o.singed ? line('M 2 -56 Q -5 -62 1 -68 Q 7 -74 1 -81', C.smoke, 3) + line('M 11 -48 Q 16 -54 12 -60', C.smoke, 2.4) : '');
  const hatOn = o.hat
    ? g({ transform: `rotate(${o.hat.rot ?? 0} 0 -20) translate(${o.hat.dx ?? 0} ${o.hat.dy ?? 0})` }, hat())
    : '';
  const head = g({ transform: `translate(${pt(Hc)}) rotate(${r1(headAbs)})` },
    circ(0, 0, 28, { fill: C.skin, ...S(2.5) })
    + circ(13, 12, 6, { fill: C.rumyanets, opacity: o.face === 'effort' ? 0.85 : 0.55 })
    + P(hairPath(), { fill: C.hair, ...S(2.2) })
    + ell(-13, 2, 6, 8, { fill: C.skin, ...S(2) }) + line('M -14.5 -2 Q -10.5 2 -14 6.5', '#C98F6E', 1.6)
    + circ(20.5, 10.5, 1, { fill: '#B5653F' }) + circ(23.5, 13, 1, { fill: '#B5653F' }) + circ(18, 14.2, 0.9, { fill: '#B5653F' })
    + face(o.face)
    + circ(28, 4, 6.5, { fill: C.nose, ...S(2) })
    + soot + tuft + hatOn);

  const tf = `translate(${r1(o.x)} ${r1(y)})${o.flip ? ' scale(-1 1)' : ''}`;
  return {
    back: g({ transform: tf }, drawArm(aF) + drawLeg(hipF, o.legs.far) + drawLeg(hipN, o.legs.near)),
    front: g({ transform: tf }, torso + head + drawArm(aN)),
    handN: toScene(aN.W), handF: toScene(aF.W), head: toScene(Hc), shoulder: toScene(Sh), hipY: y,
  };
}

// ---------- тесто-«верёвка» ----------
function rope(d) {
  return line(d, INK, 13) + line(d, C.testo, 8.5)
    + line(d, C.testoLight, 2.2, { 'stroke-dasharray': '5 13', 'stroke-dashoffset': '2', opacity: 0.95 });
}
function frayed([x, y], deg) {
  // рваный кончик теста
  return g({ transform: `translate(${pt([x, y])}) rotate(${deg})` },
    P('M -6.5 -2 L -4 7 L -1.5 2 L 1 8 L 3.5 2 L 6.5 6 L 6.5 -2 Z', { fill: C.testo, ...S(2) }));
}

// ---------- постоянные части сцены ----------
function wall() {
  let s = '';
  for (let i = 0; i < 13; i++) {
    const y0 = -8 + i * 34;
    s += rect(-5, y0, 400, 34, { fill: i % 2 ? C.log2 : C.log1 });
    s += line(`M -5 ${y0 + 5} L 395 ${y0 + 5}`, C.logHi, 2, { opacity: 0.55 });
    for (let k = 0; k < 3; k++) {
      const gx = (i * 97 + k * 139) % 370, gy = y0 + 13 + (k % 2) * 8;
      s += line(`M ${gx} ${gy} q 14 -3 28 0`, C.logSeam, 1.3, { opacity: 0.45 });
    }
    s += line(`M -5 ${y0 + 34} L 395 ${y0 + 34}`, C.logSeam, 2.5);
  }
  return s;
}
function floor() {
  let s = rect(-5, 404, 400, 70, { fill: C.floor });
  for (const [yy, off] of [[422, 30], [442, 90], [462, 10]]) {
    s += line(`M -5 ${yy} L 395 ${yy}`, C.floorSeam, 2);
    for (let x = off; x < 390; x += 120) s += line(`M ${x} ${yy - 18} L ${x} ${yy}`, C.floorSeam, 1.6);
  }
  return s + line('M -5 404 L 395 404', INK, 2.5);
}
function windowEl() {
  let teeth = '';
  for (let x = 16; x < 126; x += 14) teeth += P(`M ${x} 232 A 7 7 0 0 0 ${x + 14} 232 Z`, { fill: C.izrazets, ...S(2) });
  let drops = '';
  for (const t of [0.14, 0.3, 0.7, 0.86]) {
    const x = 14 + 116 * t, yy = 128 - 2 * t * (1 - t) * 62 + 7;
    drops += circ(x, yy, 2.2, { fill: C.sash });
  }
  return P('M 14 128 Q 72 66 130 128 Z', { fill: C.izrazets, ...S(2.5) })
    + P('M 58 128 A 14 14 0 0 1 86 128 Z', { fill: C.med, ...S(2) })
    + line('M 72 108 L 72 102 M 62 111 L 58 106 M 82 111 L 86 106', INK, 2)
    + drops
    + rect(18, 126, 108, 100, { rx: 3, fill: C.izrazets, ...S(2.5) })
    + circ(24, 132, 2, { fill: C.sash }) + circ(120, 132, 2, { fill: C.sash })
    + rect(30, 136, 84, 80, { fill: C.glass, ...S(2) })
    + circ(94, 156, 11, { fill: C.moon }) + circ(100, 151, 9.6, { fill: C.glass })
    + star4(46, 152, 3.5, C.moon) + star4(58, 200, 2.6, C.moon) + star4(102, 196, 3, C.moon)
    + rect(69.5, 136, 5, 80, { fill: C.sash, ...S(1.5) }) + rect(30, 172, 84, 5, { fill: C.sash, ...S(1.5) })
    + teeth
    + rect(10, 222, 124, 10, { rx: 2, fill: C.sash, ...S(2.5) });
}
const MOUTH = 'M 262 346 L 262 306 A 38 38 0 0 1 338 306 L 338 346 Z';
function stove() {
  let zig = '';
  for (let x = 230; x < 400; x += 12) zig += `L ${x + 6} 195.5 L ${x + 12} 200.5 `;
  const ornament = g({ transform: 'translate(300 249)' },
    P('M -4 5 C -16 9 -28 5 -34 -3 C -22 -5 -12 -2 -4 5 Z', { fill: C.izrazets, ...S(1.6) })
    + P('M 4 5 C 16 9 28 5 34 -3 C 22 -5 12 -2 4 5 Z', { fill: C.izrazets, ...S(1.6) })
    + P('M 0 8 C -14 2 -12 -12 -6 -14 C -4 -8 -2 -6 0 -4 C 2 -6 4 -8 6 -14 C 12 -12 14 2 0 8 Z', { fill: C.ryabina, ...S(1.8) })
    + ell(0, -9, 3, 6, { fill: C.med, ...S(1.4) })
    + circ(-40, -1, 3, { fill: C.ryabina, ...S(1.3) }) + circ(-43, 5, 3, { fill: C.ryabina, ...S(1.3) })
    + circ(40, -1, 3, { fill: C.ryabina, ...S(1.3) }) + circ(43, 5, 3, { fill: C.ryabina, ...S(1.3) }));
  const logEnd = (x, y) => circ(x, y, 7.5, { fill: '#D9A870', ...S(1.6) }) + circ(x, y, 3.5, { fill: 'none', stroke: C.woodDark, 'stroke-width': 1.2 });
  return rect(300, -10, 52, 210, { fill: C.pobelka }) + rect(300, -10, 9, 210, { fill: C.pobelkaShade })
    + rect(300, -10, 52, 210, { fill: 'none', ...S(2.5) })
    + rect(294, 64, 64, 12, { fill: C.pobelka, ...S(2.5) })
    + rect(232, 202, 170, 212, { fill: C.pobelka }) + rect(232, 202, 12, 212, { fill: C.pobelkaShade })
    + rect(232, 202, 170, 212, { fill: 'none', ...S(2.5) })
    + line('M 372 280 l 6 10 l -3 8 M 250 380 l 5 6', '#CFC5B5', 1.4)
    + rect(224, 190, 180, 13, { rx: 2, fill: C.pobelka, ...S(2.5) })
    + line(`M 224 200.5 ${zig}`, C.izrazets, 1.6)
    + P('M 250 244 L 250 229 A 12 12 0 0 1 274 229 L 274 244 Z', { fill: '#3A2E2A', ...S(2) })
    + P('M 352 244 L 352 229 A 12 12 0 0 1 376 229 L 376 244 Z', { fill: '#3A2E2A', ...S(2) })
    + ornament
    + P('M 255 346 L 255 306 A 45 45 0 0 1 345 306 L 345 346', { fill: 'none', stroke: C.izrazets, 'stroke-width': 3 })
    + P(MOUTH, { fill: C.soot, ...S(2.5) })
    + P('M 272 346 L 272 313 A 28 28 0 0 1 328 313 L 328 346 Z', { fill: '#3A2C27' })
    + rect(263.5, 337, 73, 9, { fill: '#4A3129' })
    + rect(238, 346, 166, 12, { fill: C.pobelka, ...S(2.5) }) + line('M 240 354 L 402 354', C.pobelkaShade, 2)
    + P('M 268 413 L 268 400 A 32 32 0 0 1 332 400 L 332 413 Z', { fill: '#3A2E2A', ...S(2) })
    + logEnd(284, 404) + logEnd(300, 404) + logEnd(316, 404) + logEnd(292, 390) + logEnd(308, 390);
}
function zaslonka(tf = '') {
  const shape = 'M 265.5 346 L 265.5 309 A 34.5 34.5 0 0 1 334.5 309 L 334.5 346 Z';
  return g({ transform: tf || undefined },
    P(shape, { fill: C.iron, ...S(2.5) })
    + line('M 273 316 A 27 27 0 0 1 300 283', C.ironHi, 3)
    + circ(271, 340, 1.8, { fill: C.ironHi }) + circ(329, 340, 1.8, { fill: C.ironHi })
    + circ(271, 318, 1.8, { fill: C.ironHi }) + circ(329, 318, 1.8, { fill: C.ironHi })
    + line('M 289 325 L 289 318 L 311 318 L 311 325', INK, 3)
    + rect(286, 311, 28, 7, { rx: 3.5, fill: C.ironHi, ...S(2) }));
}
const zaslonkaLeaning = () => zaslonka('translate(368 346) rotate(-7) scale(0.72) translate(-300 -346)');

function tub({ dough = 'full', peak = false }) {
  const xl = (y) => 32 + (y - 352) * (10 / 60), xr = (y) => 128 - (y - 352) * (10 / 60);
  let staves = '';
  for (let k = 1; k <= 5; k++) staves += line(`M ${32 + k * 16} 356 L ${42 + k * 12.67} 414`, C.woodDark, 1.6);
  const hoop = (y1, y2) =>
    P(`M ${r1(xl(y1))} ${y1} Q 80 ${y1 + 5} ${r1(xr(y1))} ${y1} L ${r1(xr(y2))} ${y2} Q 80 ${y2 + 5} ${r1(xl(y2))} ${y2} Z`,
      { fill: C.hoop, ...S(1.8) });
  let s = rect(28, 322, 15, 38, { rx: 4, fill: C.wood, ...S(2.5) }) + circ(35.5, 333, 3.8, { fill: C.woodInner, ...S(1.5) })
    + rect(117, 322, 15, 38, { rx: 4, fill: C.wood, ...S(2.5) }) + circ(124.5, 333, 3.8, { fill: C.woodInner, ...S(1.5) })
    + P('M 32 352 L 42 413 Q 80 421 118 413 L 128 352 Z', { fill: C.wood, ...S(2.5) })
    + staves + hoop(362, 369) + hoop(396, 403)
    + ell(80, 352, 48, 9, { fill: '#C8874B', ...S(2.5) }) + ell(80, 352.5, 43, 6.5, { fill: C.woodInner });
  if (dough === 'full' || dough === 'low') {
    const top = dough === 'full' ? 324 : 336;
    s += P(`M 44 355 C 42 ${top + 12} 60 ${top} 81 ${top} C 102 ${top} 120 ${top + 12} 117 355 Q 80 362 44 355 Z`,
      { fill: C.testo, ...S(2.5) })
      + circ(60, top + 13, 3, { fill: C.testoShade }) + circ(93, top + 9, 2.5, { fill: C.testoShade })
      + circ(104, top + 19, 3.4, { fill: C.testoShade }) + circ(74, top + 21, 2.2, { fill: C.testoShade })
      + line(`M 57 ${top + 7} Q 66 ${top + 1} 77 ${top + 1}`, C.testoLight, 3);
    if (peak) s += P('M 84 327 Q 93 318 97 305 Q 103 318 113 329 Z', { fill: C.testo, ...S(2.2) });
  } else {
    s += circ(62, 351, 1.3, { fill: C.testoLight }) + circ(98, 353, 1.1, { fill: C.testoLight });
  }
  return s;
}
function rug() {
  const colors = ['#C95B3E', '#EBDDC2', '#4E8C88', '#E6B04A', '#EBDDC2'];
  let stripes = '';
  for (let i = 0, x = 92; x < 292; x += 12, i++) stripes += rect(x, 420, 12, 30, { fill: colors[i % colors.length] });
  let fringe = '';
  for (let y = 425; y <= 445; y += 5) fringe += line(`M 92 ${y} L 85 ${y}`, INK, 1.5) + line(`M 292 ${y} L 299 ${y}`, INK, 1.5);
  return fringe + g({ 'clip-path': 'url(#pkRugClip)' }, stripes) + rect(92, 420, 200, 30, { rx: 15, fill: 'none', ...S(2.5) });
}
function flames(scale, outerCls, innerCls) {
  const outer = 'M 276 342 C 270 326 282 318 285 304 C 291 314 294 300 300 286 C 306 300 311 306 313 296 C 322 310 330 326 324 342 Z';
  const sc = (k) => `translate(300 342) scale(${k}) translate(-300 -342)`;
  return g({ 'clip-path': 'url(#pkMouthClip)' },
    g({ class: outerCls },
      g({ transform: sc(scale) },
        g({ class: innerCls },
          P(outer, { fill: '#E0542B', ...S(1.8) })
          + P(outer, { fill: '#F28C28', transform: sc(0.72) })
          + P(outer, { fill: '#FFD34D', transform: sc(0.44) }))))
    + rect(280, 337, 40, 7, { rx: 3.5, fill: '#6E4424', ...S(1.5), transform: 'rotate(-7 300 340)' })
    + rect(282, 337, 38, 7, { rx: 3.5, fill: '#83522C', ...S(1.5), transform: 'rotate(8 300 340)' }));
}
function kolobok(cx, cy, r, extra = '') {
  return el('clipPath', { id: 'pkKbClip' }, circ(cx, cy, r))
    + circ(cx, cy, r, { fill: '#D98A2B' })
    + g({ 'clip-path': 'url(#pkKbClip)' }, circ(cx - 4, cy - 5, r, { fill: '#F0B03A' }))
    + circ(cx, cy, r, { fill: 'none', ...S(2.5) })
    + ell(cx - 8, cy - 10, 5, 2.8, { fill: '#FFE08A', transform: `rotate(-30 ${cx - 8} ${cy - 10})` })
    + ell(cx - 6, cy - 3, 2.2, 3.1, { fill: INK }) + ell(cx + 6, cy - 3, 2.2, 3.1, { fill: INK })
    + circ(cx - 5.3, cy - 4.4, 0.8, { fill: '#FFFFFF' }) + circ(cx + 6.7, cy - 4.4, 0.8, { fill: '#FFFFFF' })
    + circ(cx - 11, cy + 4, 3.5, { fill: C.rumyanets, opacity: 0.85 }) + circ(cx + 11, cy + 4, 3.5, { fill: C.rumyanets, opacity: 0.85 })
    + P(`M ${cx - 7} ${cy + 4} Q ${cx} ${cy + 13} ${cx + 7} ${cy + 4} Z`, { fill: C.mouth, ...S(1.6) })
    + extra;
}
const zText = (x, y, size, rotDeg = -8) =>
  el('text', { x, y, 'font-family': "Marmelad, 'Trebuchet MS', sans-serif", 'font-size': size, fill: C.muka, stroke: INK,
    'stroke-width': 2.2, 'paint-order': 'stroke', 'stroke-linejoin': 'round', transform: `rotate(${rotDeg} ${x} ${y})` }, 'з');

// ---------- покадровая анимация ----------
// Каждый кадр — отдельная группа; CSS показывает их по очереди ступеньками,
// как в перекладке «на двойках». Первый кадр виден и без анимации.
const FRAMESETS = new Map();
function frames(name, dur, list) {
  FRAMESETS.set(name, { n: list.length, dur });
  return list.map((s, k) => g({ class: `pk-fr pk-${name}-${k}${k === 0 ? ' pk-k0' : ''}` }, s)).join('');
}
const wrap = (cls, inner, style) => g({ class: cls, style }, inner);

// ---------- позы ----------
function poseNokey(scratch) {
  const v = vovka({
    x: 170, floor: 433, flip: true, torso: 20, head: 14,
    legs: { near: 8, far: -10 },
    arms: {
      far: { target: ({ y }) => [170 - 124, 351 - y], bend: 1 },
      near: { target: ({ Hc }) => add(add(Hc, rot([-14, -4], 34)), [0, scratch ? 5 : 0]), bend: 1 },
    },
    face: 'puzzled', hat: { rot: scratch ? 3 : 6 },
  });
  return v;
}
function nokeyLayer() {
  const v = poseNokey(false);
  const [hx, hy] = v.head;
  const q = el('text', { x: hx + 16, y: hy - 46, 'font-family': "Marmelad, 'Trebuchet MS', sans-serif", 'font-size': 46,
    fill: C.med, stroke: INK, 'stroke-width': 2.6, 'paint-order': 'stroke', 'stroke-linejoin': 'round',
    transform: `rotate(12 ${r1(hx + 16)} ${r1(hy - 46)})` }, '?');
  const f = [false, true].map((s) => { const p = poseNokey(s); return p.back + p.front; });
  return frames('nk', 0.56, f) + wrap('pk-bob', q);
}
function offLayer() {
  const v = vovka({
    x: 152, y: 425, torso: -16, head: 30,
    legs: { far: 84, near: 93 },
    arms: {
      far: { target: () => [-19, -1], bend: 1 },
      near: { target: () => rot([14, -15], -16), bend: 1 },
    },
    face: 'sleep', hat: { rot: 14 },
  });
  const [hx, hy] = v.head;
  return wrap('pk-breathe', v.back + v.front)
    + wrap('pk-z pk-z0', zText(hx + 30, hy - 24, 15)) + wrap('pk-z pk-z1', zText(hx + 44, hy - 44, 20, -4))
    + wrap('pk-z pk-z2', zText(hx + 62, hy - 66, 26, 4));
}
// тянет-потянет: 4 ключевые позы, туда-обратно
const TUG = [
  { torso: -15, head: 7, far: [29, -36], near: [32, -30], hat: -6, peak: 310 },
  { torso: -21, head: 10, far: [23, -37], near: [27, -31], hat: -8, peak: 306 },
  { torso: -28, head: 13, far: [16, -37], near: [20, -31], hat: -11, peak: 300 },
  { torso: -34, head: 16, far: [10, -38], near: [14, -32], hat: -14, peak: 293, strain: true },
];
function tugFrame(k) {
  const t = TUG[k];
  const v = vovka({
    x: 204, floor: 433, flip: true, torso: t.torso, head: t.head,
    legs: { near: 30, far: -4 },
    arms: { far: { target: () => t.far, bend: 1 }, near: { target: () => t.near, bend: 1 } },
    face: 'effort', hat: { rot: t.hat },
  });
  const [hx, hy] = v.handN, [sx, sy] = v.shoulder, [qx, qy] = v.head;
  // тесто вытягивается из горки: заливка без контура у основания, контур — только по бокам
  const cone = P(`M 80 332 Q 93 318 97 ${t.peak + 2} Q 103 318 116 334 Z`, { fill: C.testo })
    + line(`M 84 326 Q 93 318 97 ${t.peak + 2} Q 103 318 112 327`, INK, 2.2);
  const d = `M 97 ${t.peak} Q 138 ${r1(Math.min(hy, 318) - 4)} ${r1(hx)} ${r1(hy)} L ${r1(sx)} ${r1(sy + 4)} Q 246 ${r1(sy + 2)} 262 344 L 293 338`;
  const marks = t.strain
    ? line(`M ${r1(hx - 20)} ${r1(hy - 16)} q -6 4 -4 10`, INK, 2) + line(`M ${r1(hx - 12)} ${r1(hy - 22)} q -4 3 -3 7`, INK, 2)
      + P(`M ${r1(qx + 34)} ${r1(qy - 20)} q 5 6 0 9 q -5 -3 0 -9 Z`, { fill: '#9FD3E0', ...S(1.5) })
    : '';
  return cone + v.back + rope(d) + v.front + marks;
}
function connectingLayer() {
  return frames('tug', 0.8, [0, 1, 2, 3, 3, 3, 2, 1].map(tugFrame));
}
function onPose() {
  return vovka({
    x: 190, y: 425, torso: -18, head: -6,
    legs: { far: 84, near: 101 },
    arms: { far: { target: () => [-27, -1], bend: -1 }, near: { target: () => [-21, 2], bend: -1 } },
    face: 'laugh', hat: null, soot: true, singed: true,
  });
}
function errorLayer() {
  const v = vovka({
    x: 174, y: 425, torso: -8, head: 8,
    legs: { far: 84, near: 104 },
    arms: { far: { target: () => [-23, -1], bend: -1 }, near: { target: () => [27, -29], bend: 1 } },
    face: 'daze', hat: null,
  });
  const [wx, wy] = v.handN, [hx, hy] = v.head;
  const piece = `M ${r1(wx)} ${r1(wy)} Q ${r1(wx + 16)} ${r1(wy + 2)} ${r1(wx + 18)} ${r1(wy + 22)}`;
  const orbit = ell(hx + 2, hy - 44, 30, 8, { fill: 'none', stroke: INK, 'stroke-width': 1.3, 'stroke-dasharray': '4 4', opacity: 0.6 });
  const stars = wrap('pk-orbit', wrap('pk-tw pk-tw0', star5(hx - 24, hy - 43, 6)) + wrap('pk-tw pk-tw1', star5(hx + 6, hy - 52, 5))
    + wrap('pk-tw pk-tw2', star5(hx + 29, hy - 40, 6)));
  const puffs = cloud([[140, 426, 7], [150, 421, 8], [160, 428, 6]], C.muka)
    + cloud([[214, 431, 6], [222, 426, 7], [230, 432, 5]], C.muka);
  const hatOnFloor = g({ transform: 'translate(346 428) rotate(24) scale(0.8)' }, hat());
  return puffs + v.back + v.front + rope(piece) + frayed([wx + 18, wy + 26], -4) + hatOnFloor + orbit + stars;
}

// ---------- «ПЫХ!» ----------
function burst(cx, cy, R, r, n) {
  const pts = [];
  for (let i = 0; i < n * 2; i++) {
    const a = rad(-90 + (i * 180) / n), rr = i % 2 ? r : R * (i % 4 ? 0.9 : 1);
    pts.push([cx + rr * Math.cos(a), cy + rr * Math.sin(a)]);
  }
  return P('M ' + pts.map(pt).join(' L ') + ' Z', { fill: C.med, ...S(2.5) });
}
function onLayer() {
  const v = onPose();
  const kbHat = g({ transform: 'translate(70 202) scale(0.72) rotate(-12)' }, hat());
  const sparkles = wrap('pk-appear', wrap('pk-tw pk-tw0', star4(40, 178, 6)) + wrap('pk-tw pk-tw1', star4(104, 168, 5))
    + wrap('pk-tw pk-tw2', star4(110, 205, 4)));
  const sparks = wrap('pk-spark pk-sp0', circ(288, 262, 2.6, { fill: C.med, ...S(1.2) }))
    + wrap('pk-spark pk-sp1', circ(313, 252, 2, { fill: C.med, ...S(1.2) }))
    + wrap('pk-spark pk-sp2', star4(298, 240, 5)) + wrap('pk-spark pk-sp3', star4(322, 232, 4));
  const puff = (cls, circles) => wrap(`pk-puff ${cls}`, cloud(circles, C.muka));
  return sparks
    + wrap('pk-knock', wrap('pk-laugh', v.back + v.front))
    + wrap('pk-flash', ell(300, 318, 46, 40, { fill: '#FFF6C8' }))
    + puff('pk-pf0', [[252, 300, 10], [242, 290, 8], [258, 286, 7]])
    + puff('pk-pf1', [[350, 300, 10], [360, 290, 8], [344, 286, 7]])
    + puff('pk-pf2', [[300, 356, 9], [288, 362, 7], [313, 362, 7]])
    + wrap('pk-fly', wrap('pk-land', kolobok(70, 202, 20, '')))
    + wrap('pk-hatfly', kbHat)
    + sparkles
    + wrap('pk-pyh', burst(300, 262, 50, 32, 9)
      + el('text', { x: 300, y: 272, 'text-anchor': 'middle', 'font-family': "Marmelad, 'Trebuchet MS', sans-serif", 'font-size': 30,
        fill: C.ryabina, stroke: C.muka, 'stroke-width': 4, 'paint-order': 'stroke', 'stroke-linejoin': 'round',
        transform: 'rotate(-8 300 262)' }, 'ПЫХ!'));
}

// ---------- сборка ----------
// mode 'dc' — для холста Design (видимость через {{d.*}}),
// mode 'app' — для приложения (видимость через классы и фазу на корне).
export function sceneSVG(mode = 'dc') {
  FRAMESETS.clear();
  const defs = el('defs', {},
    el('clipPath', { id: 'pkMouthClip' }, P(MOUTH))
    + el('clipPath', { id: 'pkRugClip' }, rect(92, 420, 200, 30, { rx: 15 }))
    + el('radialGradient', { id: 'pkGlow', cx: 0.5, cy: 0.5, r: 0.5 },
      el('stop', { offset: 0, 'stop-color': '#FFB347', 'stop-opacity': 0.7 })
      + el('stop', { offset: 0.55, 'stop-color': '#FF9A3D', 'stop-opacity': 0.22 })
      + el('stop', { offset: 1, 'stop-color': '#FF9A3D', 'stop-opacity': 0 }))
    + el('filter', { id: 'pkGrain', x: 0, y: 0, width: '100%', height: '100%' },
      el('feTurbulence', { type: 'fractalNoise', baseFrequency: 0.85, numOctaves: 2, seed: 3, stitchTiles: 'stitch' })
      + el('feColorMatrix', { type: 'saturate', values: 0 })));

  const only = (key, inner) => mode === 'app'
    ? g({ class: `pk-only pk-only-${key}` }, inner)
    : g({ display: `{{d.${key}}}` }, inner);
  const errorSmoke = wrap('pk-smoke', cloud([[300, 304, 17], [283, 292, 15], [314, 286, 14], [294, 270, 14], [275, 276, 12], [283, 250, 11], [266, 256, 10]],
    '#A9A39D', '#CBC6C0'))
    + wrap('pk-ember pk-em0', circ(290, 341, 2, { fill: C.zhar })) + wrap('pk-ember pk-em1', circ(302, 343, 1.6, { fill: C.zhar }))
    + wrap('pk-ember pk-em2', circ(313, 340, 2, { fill: C.zhar }));
  const errorRopes = rope('M 104 331 Q 127 327 132 350 Q 138 384 148 409') + frayed([148, 413], -18)
    + rope('M 293 338 L 263 343 Q 249 347 248 370 Q 247 390 240 402') + frayed([239, 406], 14);
  const moonbeam = P('M 30 216 L 114 216 L 210 432 L 104 432 Z', { fill: C.moon, opacity: 0.1 });

  const open = mode === 'app'
    ? '<svg viewBox="0 0 390 470" preserveAspectRatio="xMidYMax slice" aria-hidden="true">'
    : '<svg width="390" height="470" viewBox="0 0 390 470" role="img" aria-label="{{label}}" style="display: block">';
  return open
    + defs
    + wall() + floor() + windowEl() + stove()
    + only('connecting', flames(0.58, 'pk-grow', 'pk-flicker'))
    + only('on', flames(1, 'pk-flare', 'pk-flicker'))
    + only('shut', zaslonka()) + only('open', zaslonkaLeaning())
    + only('connecting', wrap('pk-glow', ell(300, 318, 72, 58, { fill: 'url(#pkGlow)' })))
    + only('on', wrap('pk-glow', ell(300, 316, 124, 104, { fill: 'url(#pkGlow)' })))
    + only('nokey', tub({ dough: 'none' })) + only('off', tub({ dough: 'full' }))
    + only('connecting', tub({ dough: 'full' })) + only('on', tub({ dough: 'low' }))
    + only('error', tub({ dough: 'full' }))
    + rug()
    + only('error', errorRopes)
    + only('nokey', nokeyLayer()) + only('off', offLayer()) + only('connecting', connectingLayer())
    + only('on', onLayer()) + only('error', errorLayer() + errorSmoke)
    + only('night', rect(0, 0, 390, 470, { fill: '#1B2440', opacity: 0.34, style: 'mix-blend-mode: multiply' }) + moonbeam)
    + rect(0, 0, 390, 470, { filter: 'url(#pkGrain)', opacity: 0.12, style: 'mix-blend-mode: multiply' })
    + '</svg>';
}

// ---------- CSS анимаций (вызывать после sceneSVG) ----------
export function sceneCSS() {
  const pct = (x) => `${+(x * 100).toFixed(3)}%`;
  let css = ':where(.pk-scene g[class]){transform-box:fill-box;transform-origin:50% 50%}'
    + '.pk-fr{visibility:hidden}.pk-k0{visibility:visible}';
  const ns = new Set();
  for (const [name, { n, dur }] of FRAMESETS) {
    if (!ns.has(n)) { ns.add(n); css += `@keyframes pk-show-${n}{0%{visibility:visible}${pct(1 / n)}{visibility:hidden}100%{visibility:hidden}}`; }
    for (let k = 0; k < n; k++) css += `.pk-${name}-${k}{animation:pk-show-${n} ${dur}s step-end infinite;animation-delay:${+((k * dur) / n - dur).toFixed(3)}s}`;
  }
  css += [
    // огонь, свечение, искры
    '.pk-flicker{transform-origin:50% 100%;animation:pk-flicker .48s step-end infinite}',
    '@keyframes pk-flicker{0%{transform:scale(1,1)}25%{transform:scale(.95,1.08)}50%{transform:scale(1.04,.94)}75%{transform:scale(.97,1.05)}}',
    '.pk-grow{transform-origin:50% 100%;animation:pk-grow 4s ease-out both}',
    '@keyframes pk-grow{0%{transform:scale(.35)}100%{transform:scale(1.15)}}',
    '.pk-glow{animation:pk-glow 1.6s ease-in-out infinite alternate}',
    '@keyframes pk-glow{0%{opacity:.75}100%{opacity:1}}',
    '.pk-spark{animation:pk-spark 1.8s ease-out infinite}.pk-sp1{animation-delay:.45s}.pk-sp2{animation-delay:.9s}.pk-sp3{animation-delay:1.35s}',
    '@keyframes pk-spark{0%{opacity:0;transform:translate(0,14px)}15%{opacity:1}100%{opacity:0;transform:translate(-6px,-34px)}}',
    // спит
    '.pk-breathe{animation:pk-breathe 1.4s ease-in-out infinite alternate}',
    '@keyframes pk-breathe{0%{transform:translate(0,0)}100%{transform:translate(0,1.6px)}}',
    '.pk-z{opacity:0;animation:pk-z 2.7s ease-in-out infinite}.pk-z1{animation-delay:.9s}.pk-z2{animation-delay:1.8s}',
    '@keyframes pk-z{0%{opacity:0;transform:translate(-4px,8px)}20%{opacity:1}75%{opacity:1}100%{opacity:0;transform:translate(10px,-14px)}}',
    // нет ключа
    '.pk-bob{animation:pk-bob .9s step-end infinite}',
    '@keyframes pk-bob{0%{transform:rotate(-7deg)}50%{transform:rotate(7deg) translate(0,-3px)}}',
    // ошибка
    '.pk-smoke{animation:pk-smoke 1.8s ease-in-out infinite alternate}',
    '@keyframes pk-smoke{0%{transform:translate(0,0) scale(1)}100%{transform:translate(-4px,-8px) scale(1.06)}}',
    '.pk-ember{animation:pk-ember .7s step-end infinite}.pk-em1{animation-delay:.23s}.pk-em2{animation-delay:.46s}',
    '@keyframes pk-ember{0%{opacity:1}50%{opacity:.25}}',
    '.pk-orbit{animation:pk-orbit 1.2s step-end infinite}',
    '@keyframes pk-orbit{0%{transform:translate(-5px,1px)}25%{transform:translate(0,-2px)}50%{transform:translate(5px,1px)}75%{transform:translate(0,3px)}}',
    '.pk-tw{animation:pk-tw 1.4s ease-in-out infinite}.pk-tw1{animation-delay:.45s}.pk-tw2{animation-delay:.9s}',
    '@keyframes pk-tw{0%,100%{transform:scale(.6)}50%{transform:scale(1.15)}}',
    // «ПЫХ!» — момент подключения, 1,6 с
    '.pk-flare{transform-origin:50% 100%;animation:pk-flare .6s cubic-bezier(.2,.8,.3,1) both}',
    '@keyframes pk-flare{0%{transform:scale(1.7)}100%{transform:scale(1)}}',
    '.pk-flash{opacity:0;animation:pk-flash .45s ease-out both}',
    '@keyframes pk-flash{0%{opacity:0;transform:scale(.4)}18%{opacity:1;transform:scale(1.2)}100%{opacity:0;transform:scale(1.7)}}',
    '.pk-pyh{opacity:0;animation:pk-pyh 1.6s both}',
    '@keyframes pk-pyh{0%{opacity:0;transform:scale(0) rotate(0deg)}7%{opacity:1;transform:scale(0) rotate(0deg)}14%{transform:scale(1.25) rotate(4deg)}24%{transform:scale(1) rotate(0deg)}78%{opacity:1;transform:scale(1) rotate(0deg)}100%{opacity:0;transform:scale(.85) rotate(0deg)}}',
    '.pk-puff{opacity:0;animation:pk-puff .9s ease-out .08s both}.pk-pf1{animation-delay:.14s}.pk-pf2{animation-delay:.2s}',
    '@keyframes pk-puff{0%{opacity:1;transform:scale(.3)}100%{opacity:0;transform:scale(1.5)}}',
    '.pk-knock{animation:pk-knock .4s cubic-bezier(.3,0,.5,1) both}',
    '@keyframes pk-knock{0%{transform:translate(30px,-26px) rotate(8deg)}60%{transform:translate(6px,-8px) rotate(2deg)}100%{transform:translate(0,0) rotate(0deg)}}',
    '.pk-laugh{animation:pk-laugh .36s step-end .6s infinite}',
    '@keyframes pk-laugh{0%{transform:translate(0,0)}50%{transform:translate(0,-2px)}}',
    '.pk-fly{animation:pk-fly 1.1s cubic-bezier(.35,.1,.55,1) .1s both}',
    '@keyframes pk-fly{0%{opacity:0;transform:translate(230px,118px) scale(.45) rotate(0deg)}10%{opacity:1;transform:translate(224px,100px) scale(.8) rotate(-40deg)}35%{transform:translate(170px,-8px) scale(1) rotate(-150deg)}55%{transform:translate(110px,-50px) scale(1) rotate(-250deg)}75%{transform:translate(48px,-36px) scale(1) rotate(-320deg)}90%{transform:translate(8px,-8px) scale(1) rotate(-352deg)}100%{opacity:1;transform:translate(0,0) scale(1) rotate(-360deg)}}',
    '.pk-land{transform-origin:50% 100%;animation:pk-land .45s ease-out 1.2s both}',
    '@keyframes pk-land{0%{transform:scale(1.28,.72)}40%{transform:scale(.9,1.12)}70%{transform:scale(1.04,.96)}100%{transform:scale(1,1)}}',
    '.pk-hatfly{animation:pk-hatfly 1.3s cubic-bezier(.3,.1,.5,1) .06s both}',
    '@keyframes pk-hatfly{0%{transform:translate(101px,154px) scale(1.3) rotate(-20deg)}30%{transform:translate(126px,50px) scale(1.2) rotate(150deg)}58%{transform:translate(84px,-46px) scale(1.05) rotate(290deg)}82%{transform:translate(22px,-30px) scale(1) rotate(340deg)}100%{transform:translate(0,0) scale(1) rotate(360deg)}}',
    '.pk-appear{opacity:0;animation:pk-appear .3s ease-out 1.35s both}',
    '@keyframes pk-appear{0%{opacity:0}100%{opacity:1}}',
    // «Уменьшение движения»: остаются первые кадры и итоговые позы
    '@media (prefers-reduced-motion: reduce){.pk-scene g[class]{animation:none !important}}',
  ].join('');
  return css;
}
