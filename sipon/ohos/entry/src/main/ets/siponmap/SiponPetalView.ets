import { MapComponent, map, mapCommon, navi, site } from '@kit.MapKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { BinaryMessenger, MethodCall, MethodCallHandler, MethodChannel, MethodResult, PlatformView } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { items, numberValue, payload, position, textValue } from './PetalPayload';
import { PetalLabelCandidate, petalMarkerCaption, selectPetalLabels } from './PetalMarkerLayout';
import { makePetalMarker, makePetalRouteTexture } from './PetalMarkerArtwork';

// Keep these published cloud styles in sync with Android's SiponPetalView.
const LIGHT_MAP_STYLE_ID: string = '2061929205284932992';
const DARK_MAP_STYLE_ID: string = '2061970525261063552';

interface PetalMarkerEntry {
  marker: map.Marker;
  location: mapCommon.LatLng;
  caption: string;
  selected: boolean;
  routeStop: boolean;
  width: number;
  height: number;
  anchorV: number;
}

@Builder
function petalBuilder(params: Params) {
  PetalMapComponent({ host: params.platformView as SiponPetalView });
}

@Component
struct PetalMapComponent {
  host: SiponPetalView | null = null;

  build() {
    if (this.host !== null) {
      MapComponent({
        mapOptions: this.host.options,
        mapCallback: (error: BusinessError, controller: map.MapComponentController) => {
          this.host?.onMapCreated(error, controller);
        }
      }).width('100%').height('100%')
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.host?.onSizeChanged(Number(area.width), Number(area.height));
        });
    }
  }
}

// The shared contract is GCJ-02. Device GPS is normalized once in Dart's
// BusinessCoordinates before entering the city controller or this view.
// Mainland Map Kit places and viewports already use the business datum.
export class SiponPetalView extends PlatformView implements MethodCallHandler {
  readonly options: mapCommon.MapOptions = {
    position: { target: { latitude: 31.2304, longitude: 121.4737 }, zoom: 12 },
    tiltGesturesEnabled: false,
    dayNightMode: mapCommon.DayNightMode.DAY
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
  private markerIcons: image.PixelMap[] = [];
  private markerEntries: PetalMarkerEntry[] = [];
  private mapWidth: number = 0;
  private mapHeight: number = 0;
  private bottomPadding: number = 0;
  private circles: map.MapCircle[] = [];
  private venueByOverlay: Map<string, string> = new Map();
  private routeLines: map.MapPolyline[] = [];
  private routeTexture?: image.PixelMap;
  private routeRevision: number = 0;
  private renderRevision: number = 0;
  private renderQueue: Promise<void> = Promise.resolve();

  constructor(messenger: BinaryMessenger, id: number,
    creation: Map<string, Object>, onDisposed: () => void) {
    super();
    this.creation = creation;
    this.brightness = textValue(creation, 'brightness', 'light');
    this.options.styleId = this.customMapStyleId;
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
    if (this.initializationError) return;
    this.controller = controller;
    try {
      controller.setZoomControlsEnabled(false);
      controller.setMyLocationControlsEnabled(false);
      controller.setCompassControlsEnabled(this.creation.has('compassTopInset') &&
        typeof this.creation.get('compassTopInset') === 'number');
      if (typeof this.creation.get('compassTopInset') === 'number') {
        controller.setCompassPosition({ positionX: vp2px(16),
          positionY: vp2px(numberValue(this.creation, 'compassTopInset')) });
      }
      const events = controller.getEventManager();
      events.on('cameraIdle', () => {
        this.updateMarkerVisibility();
        this.emitViewport();
      });
      events.on('mapClick', () => this.emit('onBlankTapped', null));
      events.on('markerClick', (marker: map.Marker) => this.onOverlayTap(marker.getId()));
      events.on('circleClick', (circle: map.MapCircle) => this.onOverlayTap(circle.getId()));
      this.finishSetup();
    } catch (error) {
      this.failSetup((error as Error).message);
    }
  }

  private emit(method: string, args: Object | null): void {
    if (!this.destroyed) this.channel.invokeMethod(method, args);
  }

  private onOverlayTap(id: string): void {
    const venueId = this.venueByOverlay.get(id);
    if (venueId) this.emit('onVenueTapped', new Map<string, Object>([['venueId', venueId]]));
  }

  onSizeChanged(width: number, height: number): void {
    this.mapWidth = width;
    this.mapHeight = height;
    this.updateMarkerVisibility();
  }

  private updateMarkerVisibility(): void {
    const controller = this.controller;
    if (!controller || this.destroyed || this.mapWidth <= 0 || this.mapHeight <= 0) return;
    const projection = controller.getProjection();
    const candidates: PetalLabelCandidate[] = this.markerEntries.map((entry: PetalMarkerEntry) => {
      const screen = projection.toScreenLocation(entry.location);
      return { id: entry.marker.getId(), x: px2vp(screen.positionX), y: px2vp(screen.positionY),
        caption: entry.caption, selected: entry.selected, routeStop: entry.routeStop,
        width: entry.width, height: entry.height, anchorV: entry.anchorV };
    });
    const visible = selectPetalLabels(candidates, this.mapWidth, this.mapHeight, this.bottomPadding);
    this.markerEntries.forEach((entry: PetalMarkerEntry) => entry.marker.setVisible(visible.has(entry.marker.getId())));
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
      await this.redrawMarkers();
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
        await this.redrawMarkers();
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
        this.bottomPadding = numberValue(args, 'bottomPadding');
        controller.setPadding({ bottom: vp2px(this.bottomPadding) });
        this.updateMarkerVisibility();
        controller.animateCamera(map.newCameraPosition({
          target: position(args), zoom: numberValue(args, 'zoom', 15),
          tilt: 0, bearing: numberValue(args, 'bearing')
        }), numberValue(args, 'durationMs', 350));
        return null;
      case 'applyStage':
        this.bottomPadding = numberValue(args, 'bottomPadding');
        controller.setPadding({ bottom: vp2px(this.bottomPadding) });
        this.updateMarkerVisibility();
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

  private get useDarkPalette(): boolean {
    return this.style === 'muted' || this.brightness === 'dark';
  }

  private get customMapStyleId(): string {
    return this.useDarkPalette ? DARK_MAP_STYLE_ID : LIGHT_MAP_STYLE_ID;
  }

  private async applyStyle(): Promise<void> {
    const controller = this.controller;
    if (!controller) return;
    controller.setMapType(this.style === 'satellite' ? mapCommon.MapType.HYBRID : mapCommon.MapType.STANDARD);
    // The cloud style owns the palette and base-map POIs, not the SDK night mode or local JSON.
    controller.setDayNightMode(mapCommon.DayNightMode.DAY);
    await controller.setCustomMapStyle({ styleId: this.customMapStyleId });
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
      const source = image.createImageSource(
        bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
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
    this.markerIcons.forEach((icon: image.PixelMap) => { icon.release().catch(() => {}); });
    this.markerIcons = [];
    this.markerEntries = [];
    this.circles = [];
    this.venueByOverlay.clear();
  }

  private async redrawMarkers(): Promise<void> {
    const frame = this.lastFrame;
    if (!frame) return;
    const revision = ++this.renderRevision;
    const work = this.renderQueue.then(() => this.render(frame, revision));
    this.renderQueue = work.catch(() => {});
    await work;
  }

  private async render(args: Map<string, Object>, revision: number): Promise<void> {
    const controller = this.controller;
    if (!controller || this.destroyed || revision !== this.renderRevision) return;
    this.clearOverlays();
    for (const item of items(args, 'circles')) {
      const circle = await controller.addCircle({ center: position(item), radius: 18,
        fillColor: 0xff9a3d78, strokeColor: 0xffffffff, strokeWidth: 1, clickable: true });
      if (this.destroyed || revision !== this.renderRevision) { circle.remove(); return; }
      this.circles.push(circle);
      this.venueByOverlay.set(circle.getId(), textValue(item, 'venueId'));
    }
    const selected = payload(args.get('selected'));
    const selectedVenueId = textValue(selected, 'venueId');
    for (const item of items(args, 'markers')) {
      const sequenceValue = item.get('sequence');
      const sequence = typeof sequenceValue === 'number' ? sequenceValue : undefined;
      const label = textValue(item, 'label');
      const rating = numberValue(item, 'rating', NaN);
      const caption = petalMarkerCaption(label, rating, sequence);
      const venueId = textValue(item, 'venueId');
      const isSelected = selectedVenueId.length > 0 && venueId === selectedVenueId;
      const routeStop = sequence !== undefined;
      const location = position(item);
      const artwork = makePetalMarker(label, rating, sequence, isSelected,
        this.useDarkPalette,
        this.assets.get(textValue(item, 'category')), vp2px(1));
      const options: mapCommon.MarkerOptions = {
        position: location,
        icon: artwork.icon,
        // Logical collision checks include both capsule and name and reserve the page controls.
        collisionRule: mapCommon.CollisionRule.NONE,
        visible: false, clickable: true, anchorU: 0.5, anchorV: artwork.anchorV, zIndex: isSelected ? 3 : 2
      };
      let marker: map.Marker;
      try { marker = await controller.addMarker(options); }
      catch (error) { await artwork.icon.release().catch(() => {}); throw error as Error; }
      if (this.destroyed || revision !== this.renderRevision) {
        marker.remove();
        await artwork.icon.release();
        return;
      }
      this.markerIcons.push(artwork.icon);
      this.markers.push(marker);
      this.markerEntries.push({ marker, location, caption, selected: isSelected, routeStop,
        width: artwork.width, height: artwork.height, anchorV: artwork.anchorV });
      this.venueByOverlay.set(marker.getId(), venueId);
    }
    this.updateMarkerVisibility();
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
      if (!this.routeTexture) this.routeTexture = makePetalRouteTexture();
      for (const points of legs) {
        const line = await controller.addPolyline({ points, width: 12, zIndex: 1,
          customTexture: this.routeTexture, isTextureMappingUsed: true });
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
      throw error as Error;
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
    this.routeTexture?.release().catch(() => {});
    this.routeTexture = undefined;
    this.assets.forEach((icon: image.PixelMap) => { icon.release(); });
    this.assets.clear();
    this.channel.setMethodCallHandler(null);
    this.controller = undefined;
    this.onDisposed();
  }
}
