const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');
const ts = require(path.join(process.env.DEVECO_SDK_HOME, '..', 'hvigor', 'hvigor', 'node_modules', 'typescript'));
const nativeRoot = path.resolve(__dirname, '../../ohos/entry/src/main/ets/stickercutout');

function load(name, mocks) {
  const filename = path.join(nativeRoot, `${name}.ets`);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText;
  const native = new Module(filename, module);
  native.require = (id) => {
    assert.ok(id in mocks, `Unexpected native dependency: ${id}`);
    return mocks[id];
  };
  native._compile(compiled, filename);
  return native.exports;
}

function harness(options = {}) {
  const events = [];
  const files = new Set(['/picked.jpg']);
  let id = 0;
  let active = 0;
  const size = { width: 1200, height: 900 };
  function pixel(name) {
    return { isEditable: options.editable !== false,
      getImageInfo: async () => ({ size }),
      flip: async (h, v) => events.push([name, 'flip', h, v]),
      rotate: async (degrees) => events.push([name, 'rotate', degrees]),
      crop: async (rect) => events.push([name, 'crop', rect]),
      release: async () => { events.push([name, 'release']); if (options.cleanupFails) throw Error('cleanup'); },
    };
  }
  const input = pixel('input');
  const foreground = pixel('foreground');
  const segmentation = {
    init: async () => {
      assert.equal(active++, 0, 'Native requests must be serialized');
      events.push(['service', 'init']);
      return !options.initFails;
    },
    doSegmentation: async (vision, config) => {
      assert.equal(vision.pixelMap, input);
      assert.equal(config.enableSubjectForegroundImage, true);
      events.push(['service', 'segment']);
      if (options.segmentationFails) throw Error('model failure');
      return { subjectCount: options.noSubject ? 0 : 1,
        fullSubject: { foregroundImage: options.noSubject ? undefined : foreground,
          subjectRectangle: { left: 10, top: 20, width: 200, height: 300 } },
      };
    },
    release: async () => { active--; events.push(['service', 'release']); },
  };
  const fileIo = {
    OpenMode: { READ_ONLY: 1, WRITE_ONLY: 2, CREATE: 4, TRUNC: 8 },
    access: async (p) => files.has(p),
    mkdir: async (p) => files.add(p),
    copyFile: async (source, dest) => {
      if (!files.has(source)) throw Error('source missing');
      files.add(dest); events.push(['copy', source, dest]);
    },
    open: async (p) => { files.add(p); return { fd: p }; },
    close: async (file) => events.push(['close', file.fd]),
    unlink: async (p) => { files.delete(p); events.push(['unlink', p]); },
  };
  const image = {
    PixelMapFormat: { RGBA_8888: 3 }, PropertyKey: { ORIENTATION: 'Orientation' },
    createImageSource: () => ({
      getImageInfo: async () => ({ size }),
      createPixelMap: async (config) => { events.push(['decode', config]); return input; },
      getImageProperty: async () => options.orientation ?? 'Top-left',
      release: async () => events.push(['source', 'release']),
    }),
    createImagePacker: () => ({
      packToFile: async (map, fd, config) => {
        assert.equal(map, foreground);
        events.push(['pack', fd, config]);
        if (options.packingFails) throw Error('disk full');
      },
      release: async () => events.push(['packer', 'release']),
    }),
  };
  global.canIUse = () => options.supported !== false;
  const processorModule = load('StickerProcessor', {
    '@kit.CoreVisionKit': { subjectSegmentation: segmentation }, '@kit.ImageKit': { image },
    '@kit.CoreFileKit': { fileIo }, '@kit.ArkTS': { util: { generateRandomUUID: () => `id${++id}` } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn: () => {} } }, '@kit.BasicServicesKit': {},
  });
  return { events, files, input, ...processorModule,
    processor: new processorModule.StickerProcessor('/files') };
}

test('persists original and produces a cropped transparent PNG through native segmentation', async () => {
  const h = harness({ orientation: 'Right-top' });
  const output = await h.processor.generate('/picked.jpg');
  assert.equal(output.status, 'processed');
  assert.ok(h.files.has(output.photoPath));
  assert.ok(output.stickerPath.endsWith('_sticker.png'));
  assert.deepEqual(h.events.find(e => e[0] === 'pack')[2], { format: 'image/png', quality: 100 });
  assert.ok(h.events.some(e => e[0] === 'input' && e[1] === 'rotate' && e[2] === 90));
  assert.ok(h.events.some(e => e[0] === 'foreground' && e[1] === 'crop'));
  for (const resource of ['input', 'foreground', 'source', 'packer', 'service']) {
    assert.equal(h.events.filter(e => e[0] === resource && e[1] === 'release').length, 1);
  }
  assert.equal(h.events.filter(e => e[0] === 'close').length, 2);
});

for (const [name, options, status] of [
  ['unsupported device', { supported: false }, 'unsupported'],
  ['model initialization failure', { initFails: true }, 'processing_failed'],
  ['no subject', { noSubject: true }, 'no_subject'],
  ['segmentation failure', { segmentationFails: true }, 'processing_failed'],
  ['PNG encoding failure', { packingFails: true }, 'processing_failed'],
]) {
  test(`${name} preserves the saved photo and returns no fake sticker`, async () => {
    const h = harness(options);
    const output = await h.processor.generate('/picked.jpg');
    assert.equal(output.status, status);
    assert.equal(output.stickerPath, '');
    assert.ok(h.files.has(output.photoPath));
    assert.equal([...h.files].filter(p => p.endsWith('_sticker.png')).length, 0);
    assert.equal(h.events.filter(e => e[0] === 'service' && e[1] === 'release').length,
      options.supported === false ? 0 : 1);
  });
}

test('cleanup errors do not discard successful output or skip other cleanup', async () => {
  const h = harness({ cleanupFails: true });
  assert.equal((await h.processor.generate('/picked.jpg')).status, 'processed');
  assert.ok(h.events.some(e => e[0] === 'service' && e[1] === 'release'));
  assert.ok(h.events.some(e => e[0] === 'source' && e[1] === 'release'));
});

test('non-editable foreground is still saved without a failing crop', async () => {
  const h = harness({ editable: false });
  assert.equal((await h.processor.generate('/picked.jpg')).status, 'processed');
  assert.equal(h.events.filter(e => e[1] === 'crop').length, 0);
});

test('queued requests are isolated and a missing file does not block the next photo', async () => {
  const h = harness();
  const missing = h.processor.generate('/missing.jpg');
  const one = h.processor.generate('/picked.jpg');
  const two = h.processor.generate('/picked.jpg');
  await assert.rejects(missing, /source missing/);
  const results = await Promise.all([one, two]);
  assert.ok(results.every(r => r.status === 'processed'));
  assert.notEqual(results[0].photoPath, results[1].photoPath);
  const serviceEvents = h.events.filter(e => e[0] === 'service').map(e => e[1]);
  assert.deepEqual(serviceEvents, ['init', 'segment', 'release', 'init', 'segment', 'release']);
});

test('all EXIF orientations map to the required native transforms', async () => {
  const h = harness();
  const transforms = [[], [['flip', true, false]], [['rotate', 180]], [['flip', false, true]],
    [['flip', true, false], ['rotate', 270]], [['rotate', 90]],
    [['flip', true, false], ['rotate', 90]], [['rotate', 270]]];
  for (let orientation = 1; orientation <= 8; orientation++) {
    h.events.length = 0;
    await h.orientPhoto(h.input, String(orientation));
    assert.deepEqual(h.events.map(e => e.slice(1)), transforms[orientation - 1]);
  }
});

test('Flutter channel registration and result use the existing Dart contract', async () => {
  const h = harness();
  let channel;
  class MethodChannel {
    constructor(_messenger, name) { this.name = name; channel = this; }
    setMethodCallHandler(handler) { this.handler = handler; }
  }
  const { SiponStickerPlugin } = load('SiponStickerPlugin', {
    '@kit.AbilityKit': {}, '@ohos/flutter_ohos': { MethodChannel },
    './StickerProcessor': { StickerProcessor: h.StickerProcessor },
  });
  const plugin = new SiponStickerPlugin({ filesDir: '/files' });
  plugin.onAttachedToEngine({ getBinaryMessenger: () => ({}) });
  assert.equal(channel.name, 'sipon/sticker_cutout');
  const output = await new Promise((resolve, reject) => plugin.onMethodCall({
    method: 'generateSticker', args: new Map([['sourcePath', '/picked.jpg']]),
  }, { success: resolve, error: reject }));
  assert.equal(output.get('status'), 'processed');
  assert.ok(h.files.has(output.get('photoPath')));
  assert.ok(output.get('stickerPath').endsWith('.png'));
  const errors = [];
  plugin.onMethodCall({ method: 'generateSticker', args: new Map() }, { error: code => errors.push(code) });
  assert.deepEqual(errors, ['invalid_arguments']);
  plugin.onDetachedFromEngine({});
  assert.equal(channel.handler, null);
});
