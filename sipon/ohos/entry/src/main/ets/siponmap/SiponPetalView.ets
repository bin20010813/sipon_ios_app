import { MapComponent, map, mapCommon, navi, site } from '@kit.MapKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { BinaryMessenger, MethodCall, MethodCallHandler, MethodChannel, MethodResult, PlatformView } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { items, numberValue, payload, position, textValue } from './PetalPayload';

@Builder
function petalBuilder(params: Params) {
  PetalMapComponent({ host: params.platformView as SiponPetalView });
}

@Component
struct PetalMapComponent {
  host: SiponPetalView;

  build() {
    MapComponent({
      mapOptions: this.host.options,
      mapCallback: (error: BusinessError, controller: map.MapComponentController) => {
        this.host.onMapCreated(error, controller);
      }
    }).width('100%').height('100%');
  }
}

// All business coordinates at this boundary use the Map Kit regional datum
// (GCJ-02 in mainland China/Hong Kong/Macao). Device GPS is converted once by
// SiponPetalPlugin before it enters the Dart city controller.
export class SiponPetalView extends PlatformView implements MethodCallHandler {
  readonly options: mapCommon.MapOptions = {
    position: { target: { latitude: 31.2304, longitude: 121.4737 }, zoom: 12 },
    tiltGesturesEnabled: false
  };
  private channel: MethodChannel;
  private controller?: map.MapComponentController;
  private destroyed: boolean = false;
  private setupResult?: MethodResult;
  private setupArgs?: Map<string, Object>;
  private setupRevision: number = 0;
  private readyTimer: number = -1;
  private brightness: string = 'light';
  private style: string = 'standard';
  private initializationError?: string;
  private creation: Map<string, Object>;
  private onDisposed: () => void;
  private lastFrame?: Map<string, Object>;
  private assets: Map<string, image.PixelMap> = new Map();
  private markers: map.Marker[] = [];
  private circles: map.MapCircle[] = [];
  private venueByOverlay: Map<string, string> = new Map();
  private routeLines: map.MapPolyline[] = [];
  private routeRevision: number = 0;
  private renderRevision: number = 0;
  private renderQueue: Promise<void> = Promise.resolve();

  constructor(messenger: BinaryMessenger, id: number,
    creation: Map<string, Object>, onDisposed: () => void) {
    super();
    this.creation = creation;
    this.onDisposed = onDisposed;
    this.channel = new MethodChannel(messenger, `sipon/petal_${id}`);
    this.channel.setMethodCallHandler(this);
  }

  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(petalBuilder); }

  onMapCreated(error: BusinessError, controller: map.MapComponentController): void {
    if (this.destroyed) return;
    if (error) {
      this.failSetup(error.message);
      return;
    }
    this.controller = controller;
    controller.setZoomControlsEnabled(false);
    controller.setMyLocationControlsEnabled(false);
    controller.setCompassControlsEnabled(this.creation.has('compassTopInset') &&
      typeof this.creation.get('compassTopInset') === 'number');
    if (typeof this.creation.get('compassTopInset') === 'number') {
      controller.setCompassPosition({ positionX: vp2px(16),
        positionY: vp2px(numberValue(this.creation, 'compassTopInset')) });
    }
    const events = controller.getEventManager();
    events.on('cameraIdle', () => this.emitViewport());
    events.on('mapClick', () => this.emit('onBlankTapped', null));
    events.on('markerClick', (marker: map.Marker) => this.onOverlayTap(marker.getId()));
    events.on('circleClick', (circle: map.MapCircle) => this.onOverlayTap(circle.getId()));
    this.finishSetup();
  }

  private emit(method: string, args: Object | null): void {
    if (!this.destroyed) this.channel.invokeMethod(method, args);
  }

  private onOverlayTap(id: string): void {
    const venueId = this.venueByOverlay.get(id);
    if (venueId) this.emit('onVenueTapped', new Map<string, Object>([['venueId', venueId]]));
  }

  private failSetup(message: string): void {
    ++this.setupRevision;
    this.initializationError = message;
    clearTimeout(this.readyTimer);
    this.emit('onMapError', new Map<string, Object>([['message', `花瓣地图加载失败：${message}`]]));
    this.setupResult?.error('petal_initialization_failed', message, null);
    this.setupResult = undefined;
    this.setupArgs = undefined;
  }

  private finishSetup(): void {
    const args = this.setupArgs;
    const result = this.setupResult;
    if (!this.controller || !args || !result || this.destroyed) return;
    const revision = this.setupRevision;
    this.setupArgs = undefined;
    this.style = textValue(args, 'styleId', 'standard');
    this.applyStyle().then(() => {
      if (this.destroyed || revision !== this.setupRevision) return;
      this.controller?.moveCamera(map.newLatLng(position(args), 12));
      clearTimeout(this.readyTimer);
      this.setupResult = undefined;
      this.emit('onMapReady', null);
      this.emitViewport();
      result.success(null);
    }).catch((error: Error) => {
      if (!this.destroyed && revision === this.setupRevision) this.failSetup(error.message);
    });
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (this.destroyed) { result.error('disposed', 'Map disposed', null); return; }
    const args = payload(call.args);
    if (call.method === 'setup') {
      if (this.initializationError) {
        result.error('petal_initialization_failed', this.initializationError, null);
        this.emit('onMapError', new Map<string, Object>([['message', `花瓣地图加载失败：${this.initializationError}`]]));
        return;
      }
      this.setupResult?.error('superseded', 'Map setup replaced', null);
      ++this.setupRevision;
      clearTimeout(this.readyTimer);
      this.setupArgs = args;
      this.setupResult = result;
      this.readyTimer = setTimeout(() => this.failSetup('初始化超时，请重试'), 15000);
      this.finishSetup();
      return;
    }
    // Invalidate immediately, even while a previous overlay/route is awaiting SDK I/O.
    if (call.method === 'clearRoute' || call.method === 'drawRoute') ++this.routeRevision;
    this.dispatch(call.method, args).then((value: Object | null) => result.success(value))
      .catch((error: Error) => result.error('petal_map_error', error.message, null));
  }

  private async dispatch(method: string, args: Map<string, Object>): Promise<Object | null> {
    if (method === 'dispose') { this.dispose(); return null; }
    if (method === 'setAppearance') {
      this.brightness = textValue(args, 'brightness', 'light');
      if (this.controller) await this.applyStyle();
      return null;
    }
    if (method === 'registerAssets') {
      await this.registerAssets(payload(args.get('assets')));
      if (this.lastFrame) {
        const frame = this.lastFrame;
        const revision = ++this.renderRevision;
        const work = this.renderQueue.then(() => this.render(frame, revision));
        this.renderQueue = work.catch(() => {});
        await work;
      }
      return null;
    }
    const controller = this.controller;
    if (!controller) throw new Error('Map is not ready');
    switch (method) {
      case 'readViewport': return this.viewport();
      case 'setStyle':
        this.style = textValue(args, 'styleId', 'standard');
        await this.applyStyle();
        return null;
      case 'setGestures':
        controller.setRotateGesturesEnabled(args.get('rotateEnabled') !== false);
        controller.setZoomGesturesEnabled(args.get('zoomEnabled') !== false);
        controller.setScrollGesturesEnabled(args.get('panEnabled') !== false);
        controller.setTiltGesturesEnabled(false);
        return null;
      case 'flyToCity':
      case 'focusOn':
      case 'centerOnUser':
        if (method === 'centerOnUser') controller.setMyLocationEnabled(true);
        controller.setPadding({ bottom: vp2px(numberValue(args, 'bottomPadding')) });
        controller.animateCamera(map.newCameraPosition({
          target: position(args), zoom: numberValue(args, 'zoom', 15),
          tilt: 0, bearing: numberValue(args, 'bearing')
        }), numberValue(args, 'durationMs', 350));
        return null;
      case 'applyStage':
        controller.setPadding({ bottom: vp2px(numberValue(args, 'bottomPadding')) });
        if (args.has('lat') && args.has('lng')) controller.moveCamera(map.newLatLng(position(args)));
        return null;
      case 'renderFrame': {
        this.lastFrame = args;
        const revision = ++this.renderRevision;
        const work = this.renderQueue.then(() => this.render(args, revision));
        this.renderQueue = work.catch(() => {});
        await work;
        return null;
      }
      case 'searchPlaces': return await this.search(textValue(args, 'query'));
      case 'drawRoute': return await this.drawRoute(items(args, 'points'), this.routeRevision);
      case 'clearRoute': this.clearRouteLines(); return null;
      default: throw new Error(`Unsupported Petal map command: ${method}`);
    }
  }

  private async applyStyle(): Promise<void> {
    const controller = this.controller;
    if (!controller) return;
    controller.setMapType(this.style === 'satellite' ? mapCommon.MapType.HYBRID : mapCommon.MapType.STANDARD);
    const dark = this.style === 'muted' || this.brightness === 'dark';
    await controller.setCustomMapStyle({ styleContent: dark ?
      '[{"mapFeature":"landcover.natural","options":"geometry.fill","paint":{"color":"#242730"}},' +
      '{"mapFeature":"water","options":"geometry.fill","paint":{"color":"#182333"}},' +
      '{"mapFeature":"road","options":"geometry.fill","paint":{"color":"#444852"}}]' : '[]' });
  }

  private viewport(): Map<string, Object> | null {
    const controller = this.controller;
    if (!controller) return null;
    const bounds = controller.getProjection().getVisibleRegion().bounds;
    const camera = controller.getCameraPosition();
    return new Map<string, Object>([
      ['west', bounds.southwest.longitude], ['south', bounds.southwest.latitude],
      ['east', bounds.northeast.longitude], ['north', bounds.northeast.latitude],
      ['zoom', camera.zoom], ['centerLng', camera.target.longitude], ['centerLat', camera.target.latitude]
    ]);
  }

  private emitViewport(): void {
    if (!this.destroyed && this.controller) this.emit('onViewportSettled', this.viewport());
  }

  private async registerAssets(values: Map<string, Object>): Promise<void> {
    for (const key of values.keys()) {
      const bytes = values.get(key);
      if (!(bytes instanceof Uint8Array)) continue;
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      try {
        const size = Math.round(vp2px(36));
        const icon = await source.createPixelMap({ desiredSize: { width: size, height: size } });
        if (this.destroyed) { await icon.release(); return; }
        const old = this.assets.get(key);
        this.assets.set(key, icon);
        if (old) await old.release();
      } finally { await source.release(); }
    }
  }

  private clearOverlays(): void {
    this.markers.forEach((marker: map.Marker) => marker.remove());
    this.circles.forEach((circle: map.MapCircle) => circle.remove());
    this.markers = [];
    this.circles = [];
    this.venueByOverlay.clear();
  }

  private async render(args: Map<string, Object>, revision: number): Promise<void> {
    const controller = this.controller;
    if (!controller || this.destroyed || revision !== this.renderRevision) return;
    this.clearOverlays();
    for (const item of items(args, 'circles')) {
      const circle = await controller.addCircle({ center: position(item), radius: 18,
        fillColor: 0xffed708f, strokeColor: 0xffffffff, strokeWidth: 1, clickable: true });
      if (this.destroyed || revision !== this.renderRevision) { circle.remove(); return; }
      this.circles.push(circle);
      this.venueByOverlay.set(circle.getId(), textValue(item, 'venueId'));
    }
    for (const item of items(args, 'markers')) {
      const sequence = item.get('sequence');
      const label = textValue(item, 'label');
      const rating = numberValue(item, 'rating', NaN);
      const caption = sequence === undefined ? label : `${sequence}. ${label}`;
      const options: mapCommon.MarkerOptions = {
        position: position(item),
        annotations: [{ content: Number.isFinite(rating) ? `${caption}  ${rating.toFixed(1)}` : caption,
          color: 0xff242730, strokeColor: 0xffffffff, fontSize: vp2px(12) }],
        clickable: true, anchorU: 0.5, anchorV: 1, zIndex: 2
      };
      const icon = this.assets.get(textValue(item, 'category'));
      if (icon) options.icon = icon;
      const marker = await controller.addMarker(options);
      if (this.destroyed || revision !== this.renderRevision) { marker.remove(); return; }
      this.markers.push(marker);
      this.venueByOverlay.set(marker.getId(), textValue(item, 'venueId'));
    }
    const selected = payload(args.get('selected'));
    if (selected.has('lat')) {
      const circle = await controller.addCircle({ center: position(selected), radius: 35,
        fillColor: 0x44ff4778, strokeColor: 0xffff4778, strokeWidth: 2, zIndex: 1 });
      if (this.destroyed || revision !== this.renderRevision) { circle.remove(); return; }
      this.circles.push(circle);
    }
  }

  private async search(query: string): Promise<Map<string, Object>[]> {
    if (!query.trim()) return [];
    const result = await site.searchByText({ query: query.trim(),
      location: this.controller?.getCameraPosition().target, language: 'zh_CN', pageSize: 20 });
    const places: Map<string, Object>[] = [];
    for (const place of result.sites ?? []) {
      const location = place.location;
      const name = place.name;
      if (!location || !name) continue;
      places.push(new Map<string, Object>([
        ['name', name], ['address', place.formatAddress ?? ''],
        ['city', place.addressComponent.city?.cityName ?? place.addressComponent.adminLevel2 ?? ''],
        ['lat', location.latitude], ['lng', location.longitude]
      ]));
    }
    return places;
  }

  private async drawRoute(stops: Map<string, Object>[], revision: number): Promise<boolean> {
    this.clearRouteLines();
    if (stops.length < 2) return false;
    const legs: mapCommon.LatLng[][] = [];
    const coordinates = stops.map((item: Map<string, Object>) => position(item));
    for (let i = 1; i < coordinates.length; i++) {
      const result = await navi.getWalkingRoutes({ origins: [coordinates[i - 1]],
        destination: coordinates[i], language: 'zh_CN' });
      if (this.destroyed || revision !== this.routeRevision) return false;
      if (!result.routes.length) return false;
      const points: mapCommon.LatLng[] = [];
      result.routes[0].steps.forEach((step: navi.RouteStep) => {
        step.roads.forEach((road: navi.RouteRoad) => {
          road.polyline.forEach((point: mapCommon.LatLng) => points.push(point));
        });
      });
      if (points.length < 2) return false;
      legs.push(points);
    }
    const controller = this.controller;
    if (!controller || this.destroyed || revision !== this.routeRevision) return false;
    const added: map.MapPolyline[] = [];
    try {
      for (const points of legs) {
        const line = await controller.addPolyline({ points, color: 0xffff4778, width: 6, zIndex: 1 });
        added.push(line);
        if (this.destroyed || revision !== this.routeRevision) {
          added.forEach((item: map.MapPolyline) => item.remove());
          return false;
        }
      }
      this.routeLines = added;
      const lats = coordinates.map((point: mapCommon.LatLng) => point.latitude);
      const lngs = coordinates.map((point: mapCommon.LatLng) => point.longitude);
      controller.animateCamera(map.newLatLngBounds({
        southwest: { latitude: Math.min(...lats), longitude: Math.min(...lngs) },
        northeast: { latitude: Math.max(...lats), longitude: Math.max(...lngs) }
      }, 48));
      return true;
    } catch (error) {
      added.forEach((item: map.MapPolyline) => item.remove());
      throw error;
    }
  }

  private clearRouteLines(): void {
    this.routeLines.forEach((line: map.MapPolyline) => line.remove());
    this.routeLines = [];
  }

  dispose(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    ++this.setupRevision;
    ++this.routeRevision;
    ++this.renderRevision;
    clearTimeout(this.readyTimer);
    this.setupResult?.error('disposed', 'Map disposed', null);
    this.setupResult = undefined;
    this.setupArgs = undefined;
    this.lastFrame = undefined;
    this.controller?.getEventManager().off('cameraIdle');
    this.controller?.getEventManager().off('mapClick');
    this.controller?.getEventManager().off('markerClick');
    this.controller?.getEventManager().off('circleClick');
    this.clearOverlays();
    this.clearRouteLines();
    this.assets.forEach((icon: image.PixelMap) => { icon.release(); });
    this.assets.clear();
    this.channel.setMethodCallHandler(null);
    this.controller = undefined;
    this.onDisposed();
  }
}
