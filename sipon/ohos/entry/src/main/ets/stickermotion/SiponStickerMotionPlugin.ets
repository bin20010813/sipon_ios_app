import { sensor } from '@kit.SensorServiceKit';
import { display } from '@kit.ArkUI';
import {
  Any, EventChannel, EventSink, FlutterPlugin, FlutterPluginBinding, StreamHandler
} from '@ohos/flutter_ohos';

// Same screen-relative gravity (in g) and 30 Hz cadence as iOS.
export class SiponStickerMotionPlugin implements FlutterPlugin, StreamHandler {
  private channel?: EventChannel;
  private sink?: EventSink;
  private active: boolean = true;
  private sensorId?: sensor.SensorId;
  private filteredX: number = 0;
  private filteredY: number = 0;
  private initialized: boolean = false;
  private gravityCallback = (event: sensor.GravityResponse): void => {
    this.emit(event.x, event.y, false);
  };
  private accelerationCallback = (event: sensor.AccelerometerResponse): void => {
    this.emit(event.x, event.y, true);
  };

  getUniqueClassName(): string { return 'SiponStickerMotionPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new EventChannel(binding.getBinaryMessenger(), 'sipon/sticker_motion');
    this.channel.setStreamHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.onCancel(null);
    this.channel?.setStreamHandler(null);
    this.channel = undefined;
  }

  onListen(_args: Any, events: EventSink): void {
    this.stop();
    this.sink = events;
    this.start();
  }

  onCancel(_args: Any): void {
    this.stop();
    this.sink = undefined;
  }

  setActive(active: boolean): void {
    this.active = active;
    if (active) this.start(); else this.stop();
  }

  private start(): void {
    if (!this.active || !this.sink || this.sensorId !== undefined) return;
    try {
      sensor.on(sensor.SensorId.GRAVITY, this.gravityCallback, { interval: 33333333 });
      this.sensorId = sensor.SensorId.GRAVITY;
      return;
    } catch (_) {}
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, this.accelerationCallback, { interval: 33333333 });
      this.sensorId = sensor.SensorId.ACCELEROMETER;
    } catch (_) {
      // Unsupported or disabled sensors leave the sticker pool's default gravity intact.
      this.sink?.endOfStream();
      this.sink = undefined;
    }
  }

  private stop(): void {
    const previous = this.sensorId;
    this.sensorId = undefined;
    try {
      if (previous === sensor.SensorId.GRAVITY) {
        sensor.off(sensor.SensorId.GRAVITY, this.gravityCallback);
      } else if (previous === sensor.SensorId.ACCELEROMETER) {
        sensor.off(sensor.SensorId.ACCELEROMETER, this.accelerationCallback);
      }
    } catch (_) {}
    this.initialized = false;
  }

  private emit(x: number, y: number, filter: boolean): void {
    if (!this.active || this.sensorId === undefined || !this.sink ||
      !Number.isFinite(x) || !Number.isFinite(y)) return;
    const alpha = filter && this.initialized ? 0.18 : 1;
    this.filteredX += alpha * (x - this.filteredX);
    this.filteredY += alpha * (y - this.filteredY);
    this.initialized = true;
    const gx = this.filteredX / 9.80665;
    const gy = this.filteredY / 9.80665;
    let rotation = 0;
    try { rotation = display.getDefaultDisplaySync().rotation; } catch (_) {}
    switch (rotation) {
      case 1: this.sink.success([gy, gx]); break;
      case 2: this.sink.success([gx, -gy]); break;
      case 3: this.sink.success([-gy, -gx]); break;
      default: this.sink.success([-gx, gy]); break;
    }
  }
}
