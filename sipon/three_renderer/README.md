# Virtual drinking renderer

The Flutter app loads the generated `assets/virtual_drinking/three/scene.bundle.js` inside a WebView. The source is `scene.js` in this directory. The bundle includes Three.js and GLTFLoader, so the scene itself works without a JavaScript CDN; the GLB files still come from the virtual drinking API's public asset directory.

To rebuild after editing the renderer, run `npm ci` and `npm run build` from this directory. Keep the generated bundle committed with the Flutter changes. Three.js is MIT licensed; the full text is in `THREE_LICENSE` and the generated bundle retains the copyright notice.
