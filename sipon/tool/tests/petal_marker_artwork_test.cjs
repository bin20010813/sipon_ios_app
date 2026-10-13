const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');
const ts = require(path.join(process.env.DEVECO_SDK_HOME, '..', 'hvigor', 'hvigor', 'node_modules', 'typescript'));
const nativeRoot = path.resolve(__dirname, '../../ohos/entry/src/main/ets/siponmap');
const contexts = [];

class Context {
  constructor(width, height, settings, unit) {
    this.width = width; this.height = height; this.unit = unit;
    this.calls = []; contexts.push(this);
  }
  scale(...args) { this.calls.push(['scale', ...args]); }
  measureText(text) { return { width: Array.from(text).reduce((w, c) => w + (c.charCodeAt(0) > 255 ? 12 : 6), 0) }; }
  beginPath() {}
  closePath() {}
  moveTo(...args) { this.calls.push(['move', ...args]); }
  lineTo(...args) { this.calls.push(['line', ...args]); }
  arc() {}
  fill() { this.calls.push(['fill', this.fillStyle]); }
  stroke() { this.calls.push(['stroke', this.strokeStyle, this.lineWidth]); }
  drawImage(...args) { this.calls.push(['image', ...args]); }
  fillRect(...args) { this.calls.push(['rect', this.fillStyle, this.globalCompositeOperation, ...args]); }
  fillText(text, x, y) { this.calls.push(['text', text, x, y, this.font, this.fillStyle]); }
  getPixelMap(x, y, width, height) {
    const pixelMap = { width, height, released: false,
      release: async () => { pixelMap.released = true; } };
    return pixelMap;
  }
}
global.OffscreenCanvasRenderingContext2D = Context;
global.RenderingContextSettings = class {};
function load(name, mocks = {}) {
  const file = path.join(nativeRoot, `${name}.ets`);
  const native = new Module(file, module);
  native.require = id => { assert.ok(id in mocks, `Unexpected dependency: ${id}`); return mocks[id]; };
  native._compile(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText, file);
  return native.exports;
}
const artwork = load('PetalMarkerArtwork', {
  '@kit.ArkUI': { LengthMetricsUnit: { PX: 1 } }, './PetalMarkerLayout': load('PetalMarkerLayout'),
});

test('route texture points forward and preserves a continuous stroke between repeats', () => {
  contexts.length = 0;
  const icon = artwork.makePetalRouteTexture();
  const context = contexts[0];
  assert.equal(icon.width, 144);
  assert.equal(icon.height, 24);
  assert.deepEqual(context.calls.filter(c => c[0] === 'move' || c[0] === 'line'), [
    ['move', 0, 6], ['line', 72, 6],
    ['move', 33, 2], ['line', 39, 6], ['line', 33, 10],
  ]);
  assert.deepEqual(context.calls.filter(c => c[0] === 'stroke'), [
    ['stroke', '#FF4778', 5], ['stroke', '#FF4778', 4], ['stroke', '#FFFFFF', 2],
  ]);
});
const make = (selected = false, extra = {}) => {
  contexts.length = 0;
  const result = artwork.makePetalMarker(extra.label ?? 'Blue Note Beijing', extra.rating ?? 4.7,
    extra.sequence, selected, extra.dark ?? false, extra.noIcon ? undefined : {}, extra.density ?? 1);
  return { result, main: contexts[1], tint: contexts[2] };
};

test('normal marker has a white capsule, theme border, rating inside, name below', () => {
  const { result, main } = make();
  assert.ok(main.calls.some(c => c[0] === 'fill' && c[1] === '#FFFFFF'));
  assert.ok(main.calls.some(c => c[0] === 'stroke' && c[1] === '#9A3D78' && c[2] === 1));
  const texts = main.calls.filter(c => c[0] === 'text');
  assert.equal(texts[0][1], '★ 4.7');
  assert.equal(texts[0][3], 14);
  assert.ok(texts.slice(1).every(c => c[3] >= 33 && c[4] === '12px sans-serif'));
  assert.ok(Math.abs(result.height * result.anchorV - 14) < 0.000001);
});
test('selected marker fills theme color and tints both icon and rating white', () => {
  const { main, tint } = make(true);
  assert.ok(main.calls.some(c => c[0] === 'fill' && c[1] === '#9A3D78'));
  assert.equal(main.calls.find(c => c[0] === 'text')[5], '#FFFFFF');
  assert.ok(tint.calls.some(c => c[0] === 'rect' && c[1] === '#FFFFFF' && c[2] === 'source-in'));
  assert.equal(main.calls.find(c => c[0] === 'image')[1].released, true);
});
test('pixel density changes only bitmap resolution, not logical marker size or font', () => {
  const first = make(false, { density: 1 });
  const dense = make(false, { density: 3 });
  assert.equal(first.result.width, dense.result.width);
  assert.equal(first.result.height, dense.result.height);
  assert.equal(dense.result.icon.width, first.result.icon.width * 3);
  assert.equal(dense.result.icon.height, first.result.icon.height * 3);
  assert.deepEqual(dense.main.calls.find(c => c[0] === 'scale'), ['scale', 3, 3]);
});
test('long names wrap to at most two lines with an ellipsis', () => {
  const { main } = make(false, { label: '北京目的地酒吧工人体育场西路店这是一个很长很长的名字' });
  const names = main.calls.filter(c => c[0] === 'text').slice(1);
  assert.equal(names.length, 2);
  assert.ok(names[1][1].endsWith('…'));
  assert.ok(names.every(c => main.measureText(c[1]).width <= 128));
});
test('route stops keep the category icon inside a white circle and only the sequence below', () => {
  for (const sequence of [1, 2, 12]) {
    for (const selected of [false, true]) {
      const { main, result, tint } = make(selected, { sequence, dark: selected });
      const texts = main.calls.filter(c => c[0] === 'text');
      assert.equal(texts.length, 1);
      assert.equal(texts[0][1], String(sequence));
      assert.equal(texts[0][3], 33);
      assert.equal(result.width, 32);
      assert.equal(tint, undefined);
      assert.ok(main.calls.some(c => c[0] === 'fill' && c[1] === '#FFFFFF'));
      const icon = main.calls.find(c => c[0] === 'image');
      assert.deepEqual(icon.slice(2), [8, 6, 16, 16]);
    }
  }
});
test('unrated venues omit a fabricated score and dark mode remains legible', () => {
  const { main } = make(false, { rating: NaN, dark: true, noIcon: true });
  assert.equal(main.calls.find(c => c[0] === 'text')[1], '');
  assert.ok(main.calls.some(c => c[0] === 'fill' && c[1] === '#302B2A'));
  assert.ok(main.calls.filter(c => c[0] === 'text').slice(1).every(c => c[5] === '#C2B6C2'));
});
