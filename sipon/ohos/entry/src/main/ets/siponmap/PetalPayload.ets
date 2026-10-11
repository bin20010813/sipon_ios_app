import { mapCommon } from '@kit.MapKit';

export function payload(value: Object | null | undefined): Map<string, Object> {
  return value instanceof Map ? value as Map<string, Object> : new Map<string, Object>();
}

export function numberValue(args: Map<string, Object>, key: string, fallback: number = 0): number {
  const value = args.get(key);
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

export function textValue(args: Map<string, Object>, key: string, fallback: string = ''): string {
  const value = args.get(key);
  return typeof value === 'string' ? value : fallback;
}

export function position(args: Map<string, Object>): mapCommon.LatLng {
  const lat = numberValue(args, 'lat', NaN);
  const lng = numberValue(args, 'lng', NaN);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 85.2 || lng < -180 || lng >= 180) {
    throw new Error('Invalid map coordinate');
  }
  return { latitude: lat, longitude: lng };
}

export function items(args: Map<string, Object>, key: string): Map<string, Object>[] {
  const value = args.get(key);
  if (!Array.isArray(value)) return [];
  return (value as Object[]).map((item: Object) => payload(item));
}
