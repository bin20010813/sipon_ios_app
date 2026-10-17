const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');
const ts = require(path.join(process.env.DEVECO_SDK_HOME, '..', 'hvigor', 'hvigor', 'node_modules', 'typescript'));

function harness(unavailable = []) {
  const callbacks = new Map();
  const events = [];
  const ended = [];
  let rotation = 0;
  let handler;
  const sensor = {
    SensorId: { GRAVITY: 257, ACCELEROMETER: 1 },
    on(id, callback, options) {
      assert.equal(options.interval, 33333333);
      if (unavailable.includes(id)) throw Error('Sensor unavailable');
      callbacks.set(id, callback);
    },
    off(id, callback) {
      assert.equal(callbacks.get(id), callback);
      callbacks.delete(id);
    },
  };
  const mocks = {
    '@kit.SensorServiceKit': { sensor },
    '@kit.ArkUI': { display: { getDefaultDisplaySync: () => ({ rotation }) } },
    '@ohos/flutter_ohos': { EventChannel: class {
      constructor(_, name) { assert.equal(name, 'sipon/sticker_motion'); }
      setStreamHandler(value) { handler = value; }
    } },
  };
  const filename = path.resolve(__dirname,
    '../../ohos/entry/src/main/ets/stickermotion/SiponStickerMotionPlugin.ets');
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText;
  const native = new Module(filename, module);
  native.require = id => { assert.ok(id in mocks); return mocks[id]; };
  native._compile(compiled, filename);
  const plugin = new native.exports.SiponStickerMotionPlugin();
  plugin.onAttachedToEngine({ getBinaryMessenger: () => ({}) });
  const listen = () => handler.onListen(null, {
    success: event => events.push(event), endOfStream: () => ended.push(true),
  });
  return { plugin, callbacks, events, ended, listen,
    rotate: value => { rotation = value; },
    emit: (x, y) => [...callbacks.values()].forEach(callback => callback({ x, y })),
    handler: () => handler };
}

test('normalizes gravity to g and follows all four live display rotations', () => {
  const h = harness();
  h.listen();
  for (let i = 0; i < 4; i++) { h.rotate(i); h.emit(9.80665, 19.6133); }
  assert.deepEqual(h.events, [[-1, 2], [2, 1], [1, -2], [-2, -1]]);
  h.emit(NaN, 1);
  assert.equal(h.events.length, 4);
});

test('only subscribes while listened and foreground; releases on cancel and detach', () => {
  const h = harness();
  assert.equal(h.callbacks.size, 0);
  h.listen();
  const staleCallback = h.callbacks.get(257);
  h.plugin.setActive(false);
  assert.equal(h.callbacks.size, 0);
  staleCallback({ x: 1, y: 2 });
  assert.equal(h.events.length, 0);
  h.plugin.setActive(true);
  assert.equal(h.callbacks.size, 1);
  h.listen(); // Hot restart replaces the listener.
  assert.equal(h.callbacks.size, 1);
  h.plugin.onCancel(null);
  h.plugin.setActive(true);
  assert.equal(h.callbacks.size, 0);
  h.listen();
  h.plugin.onDetachedFromEngine({});
  assert.equal(h.callbacks.size, 0);
  assert.equal(h.handler(), null);
});

test('accelerometer fallback filters movement and resets after resuming', () => {
  const h = harness([257]);
  h.listen();
  assert.ok(h.callbacks.has(1));
  h.emit(0, 9.80665);
  h.emit(9.80665, 9.80665);
  assert.ok(Math.abs(h.events[1][0] + 0.18) < 1e-9);
  h.plugin.setActive(false);
  h.plugin.setActive(true);
  h.emit(9.80665, 9.80665);
  assert.deepEqual(h.events[2], [-1, 1]);
});

test('missing or denied sensors end gracefully without retaining a subscription', () => {
  const h = harness([257, 1]);
  h.listen();
  assert.equal(h.ended.length, 1);
  assert.equal(h.callbacks.size, 0);
  h.plugin.onCancel(null);
  h.plugin.onDetachedFromEngine({});
});
