import { common } from '@kit.AbilityKit';
import { map, mapCommon, petalMaps } from '@kit.MapKit';
import {
  Any, BinaryMessenger, FlutterPlugin, FlutterPluginBinding,
  PlatformView, PlatformViewFactory, StandardMessageCodec,
  MethodCall, MethodCallHandler, MethodChannel, MethodResult
} from '@ohos/flutter_ohos';
import { SiponPetalView } from './SiponPetalView';
import { payload, position, textValue } from './PetalPayload';

class PetalViewFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;
  private views: SiponPetalView[];

  constructor(messenger: BinaryMessenger, views: SiponPetalView[]) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
    this.views = views;
  }

  create(_context: common.Context, viewId: number, args: Any): PlatformView {
    const view = new SiponPetalView(this.messenger, viewId, payload(args), () => {
      const index = this.views.indexOf(view);
      if (index >= 0) this.views.splice(index, 1);
    });
    this.views.push(view);
    return view;
  }
}

export class SiponPetalPlugin implements FlutterPlugin, MethodCallHandler {
  private views: SiponPetalView[] = [];
  private services?: MethodChannel;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) { this.context = context; }

  getUniqueClassName(): string { return 'SiponPetalPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.services = new MethodChannel(binding.getBinaryMessenger(), 'sipon/harmony');
    this.services.setMethodCallHandler(this);
    binding.getPlatformViewRegistry().registerViewFactory(
      'sipon/petal', new PetalViewFactory(binding.getBinaryMessenger(), this.views));
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.services?.setMethodCallHandler(null);
    this.services = undefined;
    this.views.slice().forEach((view: SiponPetalView) => view.dispose());
    this.views = [];
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = payload(call.args);
    try {
      if (call.method === 'convertDeviceLocation') {
        const converted = map.convertCoordinateSync(mapCommon.CoordinateType.WGS84,
          mapCommon.CoordinateType.GCJ02, position(args));
        result.success(new Map<string, Object>([['lng', converted.longitude], ['lat', converted.latitude]]));
      } else if (call.method === 'openPetalNavigation') {
        petalMaps.openMapRoutePlan(this.context, {
          destinationPosition: position(args), destinationName: textValue(args, 'name', '目的地')
        }).then(() => result.success(true))
          .catch((error: Error) => result.error('petal_navigation_failed', error.message, null));
      } else {
        result.notImplemented();
      }
    } catch (error) {
      result.error('harmony_service_failed', (error as Error).message, null);
    }
  }
}
