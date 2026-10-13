import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { PETAL_LABEL_FONT_SIZE } from './PetalMarkerLayout';

export const PETAL_MARKER_THEME = '#9A3D78';
export const PETAL_CAPSULE_HEIGHT = 28;

// Mapping mode aligns the texture's x-axis with the ordered polyline. Keep the
// full route stroke in the texture because mapping mode ignores line.color.
export function makePetalRouteTexture(): image.PixelMap {
  const context = canvas(72, 12, 2);
  context.strokeStyle = '#FF4778';
  context.lineWidth = 5;
  context.beginPath();
  context.moveTo(0, 6);
  context.lineTo(72, 6);
  context.stroke();
  context.beginPath();
  context.moveTo(33, 2);
  context.lineTo(39, 6);
  context.lineTo(33, 10);
  context.lineJoin = 'round';
  context.lineCap = 'round';
  context.lineWidth = 4;
  context.stroke();
  context.strokeStyle = '#FFFFFF';
  context.lineWidth = 2;
  context.stroke();
  return context.getPixelMap(0, 0, 144, 24);
}

export interface PetalMarkerArtwork {
  icon: image.PixelMap;
  width: number;
  height: number;
  anchorV: number;
}

function canvas(width: number, height: number, density: number): OffscreenCanvasRenderingContext2D {
  const context = new OffscreenCanvasRenderingContext2D(Math.ceil(width * density),
    Math.ceil(height * density), new RenderingContextSettings(true), LengthMetricsUnit.PX);
  context.scale(density, density);
  return context;
}

function nameLines(label: string, context: OffscreenCanvasRenderingContext2D): string[] {
  const characters = Array.from(label.trim().replace(/\s+/g, ' '));
  const lines: string[] = [];
  let line = '';
  for (let i = 0; i < characters.length; ++i) {
    const character = characters[i];
    if (line.length > 0 && context.measureText(line + character).width > 128) {
      lines.push(line);
      line = character;
      if (lines.length === 2) {
        let last = lines[1];
        while (last.length > 0 && context.measureText(last + '…').width > 128) {
          last = Array.from(last).slice(0, -1).join('');
        }
        lines[1] = last + '…';
        return lines;
      }
    } else {
      line += character;
    }
  }
  if (line.length > 0) lines.push(line);
  return lines;
}

export function makePetalMarker(label: string, rating: number, sequence: number | undefined,
  selected: boolean, dark: boolean, categoryIcon: image.PixelMap | undefined,
  density: number): PetalMarkerArtwork {
  // Use physical pixels once at the canvas boundary; all layout remains in logical units.
  const ratio = Number.isFinite(density) && density > 0 ? density : 1;
  const routeStop = sequence !== undefined;
  const measuring = canvas(1, 1, ratio);
  measuring.font = `${PETAL_LABEL_FONT_SIZE}px sans-serif`;
  const lines = routeStop ? [`${sequence}`] : nameLines(label, measuring);
  const nameWidth = lines.reduce((width: number, line: string) =>
    Math.max(width, measuring.measureText(line).width), 0);
  const badgeText = routeStop ? '' :
    Number.isFinite(rating) && rating > 0 ? `★ ${rating.toFixed(1)}` : '';
  measuring.font = 'bold 11px sans-serif';
  const iconSize = categoryIcon === undefined ? 0 : 16;
  const gap = iconSize > 0 && badgeText.length > 0 ? 4 : 0;
  const badgeWidth = routeStop ? 28 : Math.max(28, 14 + iconSize + gap + measuring.measureText(badgeText).width);
  const width = Math.ceil(Math.max(badgeWidth, nameWidth) + 4);
  const height = PETAL_CAPSULE_HEIGHT + (lines.length > 0 ? 5 + lines.length * 15 : 0) + 3;
  const context = canvas(width, height, ratio);
  const left = (width - badgeWidth) / 2;
  const radius = (PETAL_CAPSULE_HEIGHT - 2) / 2;
  context.beginPath();
  context.moveTo(left + 1 + radius, 1);
  context.lineTo(left + badgeWidth - 1 - radius, 1);
  context.arc(left + badgeWidth - 1 - radius, 14, radius, -Math.PI / 2, Math.PI / 2);
  context.lineTo(left + 1 + radius, PETAL_CAPSULE_HEIGHT - 1);
  context.arc(left + 1 + radius, 14, radius, Math.PI / 2, Math.PI * 1.5);
  context.closePath();
  context.fillStyle = routeStop ? '#FFFFFF' : selected ? PETAL_MARKER_THEME : dark ? '#302B2A' : '#FFFFFF';
  context.fill();
  context.strokeStyle = PETAL_MARKER_THEME;
  context.lineWidth = routeStop && selected ? 2 : 1;
  context.stroke();
  let textX = routeStop ? left + (badgeWidth - iconSize) / 2 : left + 7;
  if (categoryIcon !== undefined) {
    if (selected && !routeStop) {
      const tint = canvas(16, 16, ratio);
      tint.drawImage(categoryIcon, 0, 0, 16, 16);
      tint.globalCompositeOperation = 'source-in';
      tint.fillStyle = '#FFFFFF';
      tint.fillRect(0, 0, 16, 16);
      const whiteIcon = tint.getPixelMap(0, 0, Math.ceil(16 * ratio), Math.ceil(16 * ratio));
      try { context.drawImage(whiteIcon, textX, 6, 16, 16); }
      finally { whiteIcon.release().catch(() => {}); }
    } else {
      context.drawImage(categoryIcon, textX, 6, 16, 16);
    }
    textX += 16 + gap;
  }
  context.font = 'bold 11px sans-serif';
  context.fillStyle = selected || dark ? '#FFFFFF' : '#2A2321';
  context.textBaseline = 'middle';
  if (!routeStop) context.fillText(badgeText, textX, 14);
  context.font = `${routeStop ? 'bold ' : ''}${PETAL_LABEL_FONT_SIZE}px sans-serif`;
  context.textAlign = 'center';
  context.textBaseline = 'top';
  context.fillStyle = routeStop ? (dark ? '#E8C4DD' : PETAL_MARKER_THEME) : dark ? '#C2B6C2' : '#666C76';
  lines.forEach((line: string, index: number) => context.fillText(line, width / 2, 33 + index * 15));
  return { icon: context.getPixelMap(0, 0, Math.ceil(width * ratio), Math.ceil(height * ratio)),
    width, height, anchorV: 14 / height };
}
