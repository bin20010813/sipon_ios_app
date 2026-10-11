import path from 'path'
import fs from 'fs';
import { hvigor } from '@ohos/hvigor';
import { injectNativeModules } from 'flutter-hvigor-plugin';

injectNativeModules(__dirname, path.dirname(__dirname))

const cropLibrary = path.join(path.dirname(__dirname), '.harmony_plugins', 'image_cropper',
  'ohos', 'src', 'lib', 'image_crop_ohos');
if (fs.existsSync(cropLibrary)) {
  hvigor.getHvigorConfig().includeNode('image_crop_ohos', path.relative(__dirname, cropLibrary).replace(/\\/g, '/'));
}
