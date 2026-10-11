import { common } from '@kit.AbilityKit';
import {
  FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult
} from '@ohos/flutter_ohos';
import { StickerProcessor, StickerOutput } from './StickerProcessor';

export class SiponStickerPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private processor: StickerProcessor;

  constructor(context: common.UIAbilityContext) {
    this.processor = new StickerProcessor(context.filesDir);
  }

  getUniqueClassName(): string { return 'SiponStickerPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'sipon/sticker_cutout');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'generateSticker') { result.notImplemented(); return; }
    const args = call.args instanceof Map ? call.args as Map<string, Object> : new Map<string, Object>();
    const sourcePath = args.get('sourcePath');
    if (typeof sourcePath !== 'string' || sourcePath.trim().length === 0) {
      result.error('invalid_arguments', 'sourcePath is required.', null);
      return;
    }
    this.processor.generate(sourcePath).then((output: StickerOutput) => {
      result.success(new Map<string, Object>([
        ['photoPath', output.photoPath], ['stickerPath', output.stickerPath], ['status', output.status]
      ]));
    }).catch((error: Error) => result.error('storage_failed', error.message, null));
  }
}
