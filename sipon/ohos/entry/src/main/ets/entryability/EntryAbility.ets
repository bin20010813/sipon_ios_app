
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { SiponPetalPlugin } from '../siponmap/SiponPetalPlugin';
import { SiponStickerPlugin } from '../stickercutout/SiponStickerPlugin';
import { SiponStickerMotionPlugin } from '../stickermotion/SiponStickerMotionPlugin';

export default class EntryAbility extends FlutterAbility {
  private stickerMotion: SiponStickerMotionPlugin = new SiponStickerMotionPlugin();

  onForeground(): void {
    super.onForeground();
    this.stickerMotion.setActive(true);
  }

  onBackground(): void {
    this.stickerMotion.setActive(false);
    super.onBackground();
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new SiponPetalPlugin(this.context))
    flutterEngine.getPlugins()?.add(new SiponStickerPlugin(this.context))
    flutterEngine.getPlugins()?.add(this.stickerMotion)
  }
}
