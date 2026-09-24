import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const send = (type, detail) => {
  if (window.SiponThree) window.SiponThree.postMessage(JSON.stringify({ type, detail }));
};

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(34, 1, 0.01, 30);
camera.position.set(0, 1.28, 3.0);
camera.lookAt(0, 0.5, 0);
scene.add(new THREE.HemisphereLight(0xe9f4ff, 0x6d645d, 2.3));
const keyLight = new THREE.DirectionalLight(0xffffff, 3.0);
keyLight.position.set(-2, 3, 3);
scene.add(keyLight);
const edgeLight = new THREE.DirectionalLight(0xb1d9ff, 2.5);
edgeLight.position.set(2, 2, -2);
scene.add(edgeLight);

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setClearColor(0, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  document.body.appendChild(renderer.domElement);
} catch (error) {
  send('error', 'WebGL unavailable: ' + String(error));
}

const loader = new GLTFLoader();
const modelCache = new Map();
const modelPromises = new Map();
const root = new THREE.Group();
scene.add(root);
const iceMaterial = new THREE.MeshPhongMaterial({
  color: 0xe6f9ff, emissive: 0x8db7ce, emissiveIntensity: 0.42,
  specular: 0xffffff, shininess: 90, transparent: true,
  opacity: 0.78, depthWrite: false, side: THREE.DoubleSide,
});
let active = null;
let glassObject = null;
let liquidObject = null;
let iceObject = null;
let foamObject = null;
let bubblesObject = null;
let garnishObject = null;
let profile = [];
let currentRemaining = 1;
let targetRemaining = 1;
let tiltUntil = 0;
let running = true;
let raf = 0;
let generation = 0;
let lastLiquidLevel = -1;
let lastBubbleTime = 0;

function resize() {
  if (!renderer) return;
  const width = Math.max(1, document.documentElement.clientWidth);
  const height = Math.max(1, document.documentElement.clientHeight);
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setSize(width, height, false);
}
window.addEventListener('resize', resize);
resize();

function cleanObject(object, disposeMaterials = true) {
  if (!object) return;
  root.remove(object);
  object.traverse((part) => {
    if (!part.isMesh) return;
    if (part.userData.ownedGeometry) part.geometry.dispose();
    if (disposeMaterials && part.userData.ownedMaterial) {
      const materials = Array.isArray(part.material) ? part.material : [part.material];
      for (const material of materials) material.dispose();
    }
  });
}

function assetUrl(code, kind) {
  const asset = active?.assets?.find((item) => item.code === code && item.kind === kind);
  if (!asset || typeof asset.url !== 'string') return null;
  try {
    const url = new URL(asset.url, active.baseUrl);
    const base = new URL(active.baseUrl);
    if (url.origin !== base.origin || !url.pathname.startsWith('/assets/virtual-drinking/')) return null;
    return url.href;
  } catch (_) {
    return null;
  }
}

async function model(url) {
  if (modelCache.has(url)) return modelCache.get(url);
  if (!modelPromises.has(url)) {
    modelPromises.set(url, loader.loadAsync(url).then((gltf) => {
      modelCache.set(url, gltf.scene);
      return gltf.scene;
    }).finally(() => modelPromises.delete(url)));
  }
  return modelPromises.get(url);
}

function normalizeProfile(raw) {
  if (!Array.isArray(raw)) return [];
  const points = raw
    .filter((p) => Number.isFinite(p?.y) && Number.isFinite(p?.radius) && p.radius > 0)
    .map((p) => ({ y: p.y, radius: p.radius }))
    .sort((a, b) => a.y - b.y);
  return points.length >= 2 ? points : [];
}

function radiusAt(y) {
  if (!profile.length) return 0;
  if (y <= profile[0].y) return profile[0].radius;
  for (let i = 1; i < profile.length; i++) {
    if (y <= profile[i].y) {
      const a = profile[i - 1], b = profile[i];
      return a.radius + (b.radius - a.radius) * (y - a.y) / (b.y - a.y);
    }
  }
  return profile[profile.length - 1].radius;
}

function volumeTo(y) {
  let total = 0;
  for (let i = 1; i < profile.length; i++) {
    const a = profile[i - 1], b = profile[i];
    const top = Math.min(y, b.y);
    if (top <= a.y) break;
    const r = radiusAt(top);
    const height = top - a.y;
    total += Math.PI * height * (a.radius * a.radius + a.radius * r + r * r) / 3;
    if (top < b.y) break;
  }
  return total;
}

function fillHeight(fraction) {
  if (!profile.length) return 0;
  const bottom = profile[0].y, top = profile[profile.length - 1].y;
  const max = volumeTo(top);
  let low = bottom, high = top;
  const wanted = max * THREE.MathUtils.clamp(fraction, 0, 1);
  for (let i = 0; i < 22; i++) {
    const middle = (low + high) / 2;
    if (volumeTo(middle) < wanted) low = middle;
    else high = middle;
  }
  return (low + high) / 2;
}

function updateLiquid(force = false) {
  if (!active || !profile.length) return;
  const level = fillHeight(currentRemaining);
  if (!force && Math.abs(level - lastLiquidLevel) < 0.002) return;
  lastLiquidLevel = level;
  cleanObject(liquidObject);
  cleanObject(foamObject);
  liquidObject = null;
  foamObject = null;
  if (currentRemaining <= 0.003) {
    if (iceObject) iceObject.visible = false;
    if (bubblesObject) bubblesObject.visible = false;
    if (garnishObject?.userData.coffee) garnishObject.visible = false;
    return;
  }
  if (bubblesObject) bubblesObject.visible = true;
  if (garnishObject?.userData.coffee) {
    garnishObject.visible = true;
    garnishObject.position.y = level + 0.025;
  }
  const points = [new THREE.Vector2(0, profile[0].y)];
  points.push(new THREE.Vector2(profile[0].radius, profile[0].y));
  for (let i = 1; i < profile.length && profile[i].y < level; i++) {
    points.push(new THREE.Vector2(profile[i].radius, profile[i].y));
  }
  const radius = radiusAt(level);
  points.push(new THREE.Vector2(radius, level), new THREE.Vector2(0, level));
  const geometry = new THREE.LatheGeometry(points, 48);
  const color = new THREE.Color(active.drink.color || '#b8d4c4');
  const material = new THREE.MeshPhysicalMaterial({
    color, roughness: 0.18, metalness: 0, transparent: true,
    opacity: THREE.MathUtils.clamp(active.drink.opacity ?? 0.78, 0.18, 0.96),
    depthWrite: false, side: THREE.DoubleSide,
  });
  liquidObject = new THREE.Mesh(geometry, material);
  liquidObject.userData.ownedGeometry = true;
  liquidObject.userData.ownedMaterial = true;
  liquidObject.renderOrder = 1;
  root.add(liquidObject);
  if (active.drink.foam) {
    const foamGeometry = new THREE.CylinderGeometry(radius * 0.96, radius * 0.96, 0.012, 40);
    const foamMaterial = new THREE.MeshStandardMaterial({
      color: active.drink.foamColor || '#f4e6c7', transparent: true, opacity: 0.88,
      roughness: 0.8, depthWrite: false,
    });
    foamObject = new THREE.Mesh(foamGeometry, foamMaterial);
    foamObject.position.y = level + 0.008;
    foamObject.userData.ownedGeometry = true;
    foamObject.userData.ownedMaterial = true;
    foamObject.renderOrder = 2;
    root.add(foamObject);
  }
  if (iceObject) {
    const bottom = profile[0].y;
    iceObject.position.y = Math.max(bottom, level - 0.28);
    iceObject.visible = level > bottom + 0.12;
  }
}

function makeBubbles() {
  cleanObject(bubblesObject);
  bubblesObject = null;
  if (!active?.drink?.bubbles || !profile.length) return;
  bubblesObject = new THREE.Group();
  const geometry = new THREE.SphereGeometry(0.008, 8, 6);
  const material = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.45, depthWrite: false });
  for (let i = 0; i < 14; i++) {
    const bubble = new THREE.Mesh(geometry, material);
    const angle = i * 2.4;
    const radius = radiusAt(profile[0].y) * (0.2 + (i % 4) * 0.15);
    bubble.position.set(Math.cos(angle) * radius, profile[0].y + (i % 7) * 0.09, Math.sin(angle) * radius);
    bubble.userData.offset = i / 14;
    bubblesObject.add(bubble);
  }
  bubblesObject.traverse((part) => {
    if (part.isMesh) { part.userData.ownedGeometry = true; part.userData.ownedMaterial = true; }
  });
  root.add(bubblesObject);
}

function makeGarnish() {
  cleanObject(garnishObject);
  garnishObject = null;
  const items = active?.drink?.garnish;
  if (!Array.isArray(items) || !items.length || !profile.length) return;
  garnishObject = new THREE.Group();
  const rim = profile[profile.length - 1];
  const add = (mesh) => {
    mesh.userData.ownedGeometry = true;
    mesh.userData.ownedMaterial = true;
    mesh.renderOrder = 5;
    garnishObject.add(mesh);
  };
  if (items.includes('lime') || items.includes('lemon')) {
    const lemon = items.includes('lemon');
    const fruit = new THREE.Mesh(
      new THREE.CircleGeometry(0.065, 24),
      new THREE.MeshBasicMaterial({ color: lemon ? 0xf8e7a0 : 0xc7ed8f, side: THREE.DoubleSide }),
    );
    fruit.position.set(rim.radius * 0.85, rim.y + 0.025, rim.radius * 0.36);
    fruit.rotation.x = -0.3;
    add(fruit);
    const peel = new THREE.Mesh(
      new THREE.TorusGeometry(0.063, 0.008, 6, 24),
      new THREE.MeshBasicMaterial({ color: lemon ? 0xe6c94d : 0x6daa45 }),
    );
    peel.position.copy(fruit.position);
    peel.rotation.copy(fruit.rotation);
    add(peel);
  }
  if (items.includes('mint')) {
    for (let i = 0; i < 3; i++) {
      const leaf = new THREE.Mesh(
        new THREE.SphereGeometry(1, 10, 8),
        new THREE.MeshPhongMaterial({ color: 0x4e9d67, side: THREE.DoubleSide }),
      );
      leaf.scale.set(0.026, 0.075, 0.008);
      leaf.position.set(-rim.radius * 0.65 + i * 0.028, rim.y + 0.04, 0);
      leaf.rotation.z = (i - 1) * 0.55;
      add(leaf);
    }
  }
  if (items.includes('coffee_beans')) {
    garnishObject.userData.coffee = true;
    garnishObject.position.y = fillHeight(currentRemaining) + 0.025;
    for (let i = 0; i < 3; i++) {
      const bean = new THREE.Mesh(
        new THREE.SphereGeometry(1, 10, 8),
        new THREE.MeshPhongMaterial({ color: 0x432518 }),
      );
      bean.scale.set(0.031, 0.012, 0.018);
      bean.position.set((i - 1) * 0.07, 0, i === 1 ? 0.03 : -0.02);
      bean.rotation.y = i * 0.8;
      add(bean);
    }
  }
  root.add(garnishObject);
}

async function buildGlass(token) {
  cleanObject(glassObject);
  glassObject = null;
  const url = assetUrl(active.glass.assetCode, 'glass_model');
  if (!url) throw new Error('Glass model missing from asset catalog');
  const source = await model(url);
  if (token !== generation) return;
  glassObject = source.clone(true);
  glassObject.traverse((part) => {
    if (!part.isMesh) return;
    part.renderOrder = 4;
    const wasArray = Array.isArray(part.material);
    const materials = wasArray ? part.material : [part.material];
    part.material = materials.map(() => new THREE.MeshPhongMaterial({
      color: 0xe9f6ff, emissive: 0x314a5b, emissiveIntensity: 0.25,
      specular: 0xffffff, shininess: 110, transparent: true,
      opacity: 0.10, depthWrite: false, side: THREE.DoubleSide,
    }));
    if (!wasArray) part.material = part.material[0];
    part.userData.ownedMaterial = true;
  });
  root.add(glassObject);
  send('ready', active.glass.assetCode);
}

async function buildIce(token) {
  cleanObject(iceObject);
  iceObject = null;
  const ice = active.ice || {};
  if (ice.code === 'none' || !profile.length) return;
  iceObject = new THREE.Group();
  const places = ice.code === 'crushed'
    ? [[-0.09, 0, 0], [0.07, 0.08, 0], [0.02, 0.17, -0.06], [-0.05, 0.24, 0.06], [0.1, 0.26, 0.04]]
    : [[0, 0, 0]];
  if ((ice.renderer === 'glb-v1' || ice.renderer === 'instanced-cubes-v1') && ice.assetCode) {
    const url = assetUrl(ice.assetCode, 'ice_model');
    if (!url) throw new Error('Ice model missing from asset catalog');
    const source = await model(url);
    if (token !== generation) return;
    const bounds = new THREE.Box3().setFromObject(source);
    const size = new THREE.Vector3();
    bounds.getSize(size);
    const center = new THREE.Vector3();
    bounds.getCenter(center);
    const desired = ice.code === 'crushed' ? 0.13 : 0.26;
    const scale = desired / Math.max(size.x, size.y, size.z, 0.001);
    for (const [x, y, z] of places) {
      const item = source.clone(true);
      item.scale.setScalar(scale);
      item.position.set(x - center.x * scale, y - center.y * scale, z - center.z * scale);
      item.rotation.y = x * 5;
      item.traverse((part) => {
        if (!part.isMesh) return;
        if (part.material?.normalMap && !iceMaterial.normalMap) {
          iceMaterial.normalMap = part.material.normalMap;
          iceMaterial.normalScale.copy(part.material.normalScale);
          iceMaterial.needsUpdate = true;
        }
        part.material = iceMaterial;
        part.renderOrder = 3;
      });
      iceObject.add(item);
    }
  } else if (ice.renderer === 'procedural-column-v1' || ice.code === 'column') {
    const geometry = new THREE.BoxGeometry(0.16, 0.42, 0.16, 2, 3, 2);
    const cube = new THREE.Mesh(geometry, iceMaterial);
    cube.rotation.z = 0.16;
    cube.position.y = 0.18;
    cube.renderOrder = 3;
    cube.userData.ownedGeometry = true;
    iceObject.add(cube);
  }
  if (token !== generation) return;
  root.add(iceObject);
  updateLiquid(true);
}

async function applyState(value) {
  if (!renderer || !value || !value.glass || !value.drink) return;
  const old = active;
  active = value;
  targetRemaining = THREE.MathUtils.clamp(Number(value.remaining) || 0, 0, 1);
  if (value.tilt) tiltUntil = performance.now() + 260;
  const glassChanged = !glassObject || !old || old.glass.assetCode !== value.glass.assetCode;
  const iceChanged = !iceObject || glassChanged || !old || old.ice?.code !== value.ice?.code;
  const drinkChanged = !old || JSON.stringify(old.drink) !== JSON.stringify(value.drink);
  profile = normalizeProfile(value.glass.profile);
  if (glassChanged || drinkChanged) {
    currentRemaining = targetRemaining;
    lastLiquidLevel = -1;
    updateLiquid(true);
    makeBubbles();
    makeGarnish();
  }
  const token = ++generation;
  try {
    if (glassChanged) await buildGlass(token);
    if (token !== generation) return;
    if (iceChanged) await buildIce(token);
  } catch (error) {
    if (token === generation) send('error', String(error));
  }
}

function frame(now) {
  if (!running || !renderer) return;
  raf = requestAnimationFrame(frame);
  if (Math.abs(currentRemaining - targetRemaining) > 0.001) {
    currentRemaining += (targetRemaining - currentRemaining) * 0.18;
    updateLiquid();
  } else if (currentRemaining !== targetRemaining) {
    currentRemaining = targetRemaining;
    updateLiquid();
  }
  root.rotation.z = THREE.MathUtils.lerp(root.rotation.z, now < tiltUntil ? -0.11 : 0, 0.17);
  if (bubblesObject && now - lastBubbleTime > 40) {
    lastBubbleTime = now;
    const level = fillHeight(currentRemaining);
    for (const bubble of bubblesObject.children) {
      bubble.position.y += 0.003;
      if (bubble.position.y > level - 0.025) bubble.position.y = profile[0].y + bubble.userData.offset * 0.05;
      bubble.visible = bubble.position.y < level - 0.025;
    }
  }
  renderer.render(scene, camera);
}

window.siponScene = {
  setState: applyState,
  setVisible(visible) {
    running = Boolean(visible);
    if (running) { cancelAnimationFrame(raf); raf = requestAnimationFrame(frame); }
    else cancelAnimationFrame(raf);
  },
  dispose() {
    running = false;
    cancelAnimationFrame(raf);
    generation++;
    cleanObject(glassObject);
    cleanObject(liquidObject);
    cleanObject(iceObject);
    cleanObject(foamObject);
    cleanObject(bubblesObject);
    cleanObject(garnishObject);
    iceMaterial.dispose();
    for (const item of modelCache.values()) {
      item.traverse((part) => {
        if (!part.isMesh) return;
        part.geometry.dispose();
        const materials = Array.isArray(part.material) ? part.material : [part.material];
        for (const material of materials) {
          for (const value of Object.values(material)) {
            if (value?.isTexture) { value.dispose(); value.image?.close?.(); }
          }
          material.dispose();
        }
      });
    }
    modelCache.clear();
    renderer?.dispose();
    renderer?.forceContextLoss();
  },
};
if (renderer) {
  raf = requestAnimationFrame(frame);
  send('loaded', '');
}
