const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');

const sdkRoot = process.env.DEVECO_SDK_HOME;
assert.ok(sdkRoot, 'Set DEVECO_SDK_HOME to the installed HarmonyOS SDK.');
const ts = require(path.join(sdkRoot, '..', 'hvigor', 'hvigor', 'node_modules', 'typescript'));
const sourcePath = path.resolve(__dirname, '../../ohos/entry/src/main/ets/siponmap/PetalMarkerLayout.ets');
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
const layoutModule = new Module(sourcePath, module);
layoutModule._compile(compiled, sourcePath);
const { selectPetalLabels, petalMarkerCaption, PETAL_LABEL_FONT_SIZE } = layoutModule.exports;
const point = (id, x, y, extra = {}) => ({ id, x, y, caption: '酒吧', selected: false, routeStop: false, ...extra });

test('dense venue labels do not cover one another', () => {
  const candidates = Array.from({ length: 100 }, (_, i) => point(String(i), 180, 300));
  assert.equal(selectPetalLabels(candidates, 390, 844, 0).size, 1);
});
test('a selected venue wins over a colliding ordinary venue', () => {
  const candidates = [point('ordinary', 180, 300), point('selected', 180, 300, { selected: true })];
  assert.deepEqual([...selectPetalLabels(candidates, 390, 844, 0)], ['selected']);
});
test('numbered route stops remain visible even when they overlap', () => {
  const candidates = [point('ordinary', 180, 300), point('one', 180, 300, { routeStop: true }),
    point('two', 180, 300, { routeStop: true })];
  assert.deepEqual([...selectPetalLabels(candidates, 390, 844, 0)], ['one', 'two']);
});
test('labels leave room for the controls and the bottom sheet', () => {
  const candidates = [point('top', 180, 100), point('bottom', 180, 650), point('middle', 180, 350)];
  assert.deepEqual([...selectPetalLabels(candidates, 390, 844, 0)], ['middle']);
  assert.equal(selectPetalLabels([point('covered', 180, 350)], 390, 844, 550).size, 0);
});
test('compact maps allow labels without full-page reserved areas', () => {
  assert.equal(selectPetalLabels([point('compact', 100, 80)], 390, 240, 0).size, 1);
});
test('large viewports still cap ordinary labels at ten', () => {
  const candidates = [];
  for (let y = 180; y < 1600; y += 120) {
    for (let x = 100; x < 1800; x += 180) candidates.push(point(`${x}-${y}`, x, y));
  }
  assert.equal(selectPetalLabels(candidates, 1800, 1800, 0).size, 10);
});
test('invalid and offscreen positions do not consume label slots', () => {
  assert.equal(selectPetalLabels([point('bad', NaN, 300), point('outside', -10, 300)], 390, 844, 0).size, 0);
});
test('captions stay short and route stops use only their number', () => {
  assert.equal(PETAL_LABEL_FONT_SIZE, 12);
  assert.equal(petalMarkerCaption('This venue has a very long name', 4.6), 'This venue has…');
  assert.equal(petalMarkerCaption('酒吧', NaN), '酒吧');
  assert.equal(petalMarkerCaption('酒吧', 4.6, 2), '2');
});
test('collision includes the capsule and the name below its geographic anchor', () => {
  const dimensions = { width: 128, height: 66, anchorV: 14 / 66 };
  const candidates = [point('first', 180, 300, dimensions), point('second', 180, 350, dimensions)];
  assert.deepEqual([...selectPetalLabels(candidates, 390, 844, 0)], ['first']);
  assert.equal(selectPetalLabels([point('one', 80, 300, dimensions),
    point('two', 230, 300, dimensions)], 390, 844, 0).size, 2);
});
