// Layout uses logical screen units, independent of the device pixel density.
export const PETAL_LABEL_FONT_SIZE = 12;

export interface PetalLabelCandidate {
  id: string;
  x: number;
  y: number;
  caption: string;
  selected: boolean;
  routeStop: boolean;
  width?: number;
  height?: number;
  anchorV?: number;
}

interface LabelBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export function petalMarkerCaption(label: string, rating: number, sequence?: number): string {
  if (sequence !== undefined) return `${sequence}`;
  const characters = Array.from(label.trim());
  const name = characters.length > 14 ? characters.slice(0, 14).join('') + '…' : characters.join('');
  // Rating is drawn inside the capsule, separate from the name below it.
  return name;
}

export function selectPetalLabels(candidates: PetalLabelCandidate[], width: number,
  height: number, bottomPadding: number): Set<string> {
  const result = new Set<string>();
  if (width <= 0 || height <= 0) return result;
  const fullMap = height >= 500;
  const top = fullMap ? 140 : 0;
  const bottom = fullMap ? Math.max(245, bottomPadding) : bottomPadding;
  const usableHeight = Math.max(1, height - top - bottom);
  const limit = Math.max(3, Math.min(10, Math.floor(width / 140 * usableHeight / 110 * 0.8)));
  const occupied: LabelBounds[] = [];
  // Selection and numbered route stops are placed before ordinary venues.
  const ordered = candidates.slice().sort((a: PetalLabelCandidate, b: PetalLabelCandidate) =>
    Number(b.selected) - Number(a.selected) || Number(b.routeStop) - Number(a.routeStop));
  let ordinaryCount = 0;
  for (const candidate of ordered) {
    if (!Number.isFinite(candidate.x) || !Number.isFinite(candidate.y) ||
      candidate.x < 0 || candidate.x > width || candidate.y < 0 || candidate.y > height) continue;
    const pinned = candidate.selected || candidate.routeStop;
    if (!pinned && (candidate.y < top || candidate.y > height - bottom)) continue;
    const halfWidth = (candidate.width ?? Math.max(36,
      Array.from(candidate.caption).length * PETAL_LABEL_FONT_SIZE)) / 2 + 6;
    const markerHeight = candidate.height ?? 80;
    const anchorV = candidate.anchorV ?? 0.625;
    const bounds: LabelBounds = { left: candidate.x - halfWidth, right: candidate.x + halfWidth,
      top: candidate.y - markerHeight * anchorV - 4,
      bottom: candidate.y + markerHeight * (1 - anchorV) + 4 };
    const overlaps = occupied.some((other: LabelBounds) => bounds.left < other.right &&
      bounds.right > other.left && bounds.top < other.bottom && bounds.bottom > other.top);
    if (!pinned && (ordinaryCount >= limit || overlaps)) continue;
    result.add(candidate.id);
    occupied.push(bounds);
    if (!candidate.routeStop) ++ordinaryCount;
  }
  return result;
}
