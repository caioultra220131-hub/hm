import { NativeGuidePrimitive, NativePageContract, NativeRatioBounds } from '../models/NativeNoteContracts';
import { DocumentPreviewSnapshot } from '../models/PreviewModels';

interface PreviewRectNode {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  fill: string;
  opacity: number;
  radius?: number;
  borderColor?: string;
  borderWidth?: number;
}

interface PreviewTextNode {
  id: string;
  x: number;
  y: number;
  text: string;
  color: string;
  opacity: number;
  fontSize: number;
}

function normalizeBounds(bounds: NativeRatioBounds | undefined): NativeRatioBounds {
  if (bounds !== undefined) {
    return bounds;
  }
  return {
    x: 0.08,
    y: 0.08,
    width: 0.84,
    height: 0.84
  };
}

function safeRatio(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, value);
}

function toPixelX(width: number, x: number): number {
  return Math.round(width * safeRatio(x));
}

function toPixelY(height: number, y: number): number {
  return Math.round(height * safeRatio(y));
}

function toPixelWidth(width: number, ratioWidth: number): number {
  return Math.max(1, Math.round(width * safeRatio(ratioWidth)));
}

function toPixelHeight(height: number, ratioHeight: number): number {
  return Math.max(1, Math.round(height * safeRatio(ratioHeight)));
}

function resolveRasterUri(previewSnapshot: DocumentPreviewSnapshot | undefined): string {
  const uri: string | undefined = previewSnapshot?.raster?.uri;
  return typeof uri === 'string' ? uri.trim() : '';
}

function buildGuideFrame(contract: NativePageContract, width: number, height: number): PreviewRectNode {
  const contentBounds: NativeRatioBounds = normalizeBounds(contract.guide?.contentBounds);
  return {
    id: 'guide-frame',
    x: toPixelX(width, contentBounds.x),
    y: toPixelY(height, contentBounds.y),
    width: toPixelWidth(width, contentBounds.width),
    height: toPixelHeight(height, contentBounds.height),
    fill: 'transparent',
    opacity: 0.18,
    borderColor: contract.accent,
    borderWidth: 1
  };
}

function pushHorizontalLines(
  nodes: PreviewRectNode[],
  primitive: NativeGuidePrimitive,
  width: number,
  height: number
): void {
  const startX: number = toPixelX(width, primitive.x);
  const startY: number = toPixelY(height, primitive.y);
  const lineWidth: number = toPixelWidth(width, primitive.width);
  const lineHeight: number = Math.max(1, Math.round(primitive.strokeWidth ?? 1));
  const totalHeight: number = toPixelHeight(height, primitive.height);
  const spacingY: number = Math.max(6, toPixelHeight(height, primitive.spacingY ?? 0.05));
  const stroke: string = primitive.stroke ?? primitive.fill ?? '#B8C4D6';
  let cursorY: number = startY;
  let lineIndex: number = 0;
  while (cursorY <= startY + totalHeight) {
    nodes.push({
      id: `${primitive.id}-line-${lineIndex}`,
      x: startX,
      y: cursorY,
      width: lineWidth,
      height: lineHeight,
      fill: stroke,
      opacity: primitive.opacity ?? 0.88
    });
    cursorY += spacingY;
    lineIndex += 1;
  }
}

function pushGrid(
  nodes: PreviewRectNode[],
  primitive: NativeGuidePrimitive,
  width: number,
  height: number
): void {
  const startX: number = toPixelX(width, primitive.x);
  const startY: number = toPixelY(height, primitive.y);
  const totalWidth: number = toPixelWidth(width, primitive.width);
  const totalHeight: number = toPixelHeight(height, primitive.height);
  const spacingX: number = Math.max(6, toPixelWidth(width, primitive.spacingX ?? 0.05));
  const spacingY: number = Math.max(6, toPixelHeight(height, primitive.spacingY ?? 0.05));
  const stroke: string = primitive.stroke ?? primitive.fill ?? '#B8C4D6';
  const strokeWidth: number = Math.max(1, Math.round(primitive.strokeWidth ?? 1));
  let cursorY: number = startY;
  let rowIndex: number = 0;
  while (cursorY <= startY + totalHeight) {
    nodes.push({
      id: `${primitive.id}-row-${rowIndex}`,
      x: startX,
      y: cursorY,
      width: totalWidth,
      height: strokeWidth,
      fill: stroke,
      opacity: primitive.opacity ?? 0.78
    });
    cursorY += spacingY;
    rowIndex += 1;
  }
  let cursorX: number = startX;
  let columnIndex: number = 0;
  while (cursorX <= startX + totalWidth) {
    nodes.push({
      id: `${primitive.id}-col-${columnIndex}`,
      x: cursorX,
      y: startY,
      width: strokeWidth,
      height: totalHeight,
      fill: stroke,
      opacity: primitive.opacity ?? 0.78
    });
    cursorX += spacingX;
    columnIndex += 1;
  }
}

function pushDots(
  nodes: PreviewRectNode[],
  primitive: NativeGuidePrimitive,
  width: number,
  height: number
): void {
  const startX: number = toPixelX(width, primitive.x);
  const startY: number = toPixelY(height, primitive.y);
  const totalWidth: number = toPixelWidth(width, primitive.width);
  const totalHeight: number = toPixelHeight(height, primitive.height);
  const spacingX: number = Math.max(8, toPixelWidth(width, primitive.spacingX ?? 0.05));
  const spacingY: number = Math.max(8, toPixelHeight(height, primitive.spacingY ?? 0.05));
  const radius: number = Math.max(1, Math.round(primitive.dotRadius ?? 1.5));
  const dotSize: number = Math.max(2, radius * 2);
  const fill: string = primitive.fill ?? primitive.stroke ?? '#8FA4C7';
  let cursorY: number = startY;
  let rowIndex: number = 0;
  while (cursorY <= startY + totalHeight) {
    let cursorX: number = startX;
    let columnIndex: number = 0;
    while (cursorX <= startX + totalWidth) {
      nodes.push({
        id: `${primitive.id}-dot-${rowIndex}-${columnIndex}`,
        x: cursorX,
        y: cursorY,
        width: dotSize,
        height: dotSize,
        fill,
        opacity: primitive.opacity ?? 0.75,
        radius
      });
      cursorX += spacingX;
      columnIndex += 1;
    }
    cursorY += spacingY;
    rowIndex += 1;
  }
}

function pushDivider(
  nodes: PreviewRectNode[],
  primitive: NativeGuidePrimitive,
  width: number,
  height: number
): void {
  nodes.push({
    id: primitive.id,
    x: toPixelX(width, primitive.x),
    y: toPixelY(height, primitive.y),
    width: toPixelWidth(width, primitive.width),
    height: toPixelHeight(height, primitive.height),
    fill: primitive.stroke ?? primitive.fill ?? '#C3CCDA',
    opacity: primitive.opacity ?? 0.92
  });
}

function pushPanel(
  nodes: PreviewRectNode[],
  primitive: NativeGuidePrimitive,
  width: number,
  height: number
): void {
  nodes.push({
    id: primitive.id,
    x: toPixelX(width, primitive.x),
    y: toPixelY(height, primitive.y),
    width: toPixelWidth(width, primitive.width),
    height: toPixelHeight(height, primitive.height),
    fill: primitive.fill ?? primitive.stroke ?? '#D9E1EE',
    opacity: primitive.opacity ?? 0.22,
    borderColor: primitive.stroke,
    borderWidth: primitive.strokeWidth !== undefined ? Math.max(1, Math.round(primitive.strokeWidth)) : 1
  });
}

function pushLabel(
  texts: PreviewTextNode[],
  primitive: NativeGuidePrimitive,
  width: number,
  height: number,
  accentColor: string
): void {
  const labelText: string = primitive.text ?? '';
  if (labelText.length === 0) {
    return;
  }
  texts.push({
    id: primitive.id,
    x: toPixelX(width, primitive.x) + 2,
    y: toPixelY(height, primitive.y) + 2,
    text: labelText,
    color: primitive.stroke ?? accentColor,
    opacity: primitive.opacity ?? 0.9,
    fontSize: 9
  });
}

function buildPreviewRectNodes(
  previewSnapshot: DocumentPreviewSnapshot | undefined,
  width: number,
  height: number
): PreviewRectNode[] {
  const contract: NativePageContract | undefined = previewSnapshot?.pageContract;
  if (contract === undefined) {
    return [];
  }
  const nodes: PreviewRectNode[] = [buildGuideFrame(contract, width, height)];
  contract.primitives.forEach((primitive: NativeGuidePrimitive) => {
    switch (primitive.kind) {
      case 'horizontalLines':
        pushHorizontalLines(nodes, primitive, width, height);
        break;
      case 'grid':
        pushGrid(nodes, primitive, width, height);
        break;
      case 'dots':
        pushDots(nodes, primitive, width, height);
        break;
      case 'divider':
        pushDivider(nodes, primitive, width, height);
        break;
      case 'header':
      case 'sidebar':
        pushPanel(nodes, primitive, width, height);
        break;
      default:
        break;
    }
  });
  return nodes;
}

function buildPreviewTextNodes(
  previewSnapshot: DocumentPreviewSnapshot | undefined,
  width: number,
  height: number
): PreviewTextNode[] {
  const contract: NativePageContract | undefined = previewSnapshot?.pageContract;
  if (contract === undefined) {
    return [];
  }
  const texts: PreviewTextNode[] = [];
  contract.primitives.forEach((primitive: NativeGuidePrimitive) => {
    if (primitive.kind === 'label') {
      pushLabel(texts, primitive, width, height, contract.accent);
    }
  });
  return texts;
}

function resolvePageFill(previewSnapshot: DocumentPreviewSnapshot | undefined): string {
  return previewSnapshot?.pageContract.fill ?? '#FFFFFF';
}

function resolvePageAccent(previewSnapshot: DocumentPreviewSnapshot | undefined): string {
  return previewSnapshot?.pageContract.accent ?? '#D0D5DD';
}

@Component
export struct PreviewThumbnail {
  previewSnapshot?: DocumentPreviewSnapshot;
  fallbackSummary: string = '';
  thumbnailWidth: number = 128;
  thumbnailHeight: number = 172;

  private rasterUri(): string {
    return resolveRasterUri(this.previewSnapshot);
  }

  private rectNodes(): PreviewRectNode[] {
    return buildPreviewRectNodes(this.previewSnapshot, this.thumbnailWidth, this.thumbnailHeight);
  }

  private textNodes(): PreviewTextNode[] {
    return buildPreviewTextNodes(this.previewSnapshot, this.thumbnailWidth, this.thumbnailHeight);
  }

  private pageFill(): string {
    return resolvePageFill(this.previewSnapshot);
  }

  private pageAccent(): string {
    return resolvePageAccent(this.previewSnapshot);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width(this.thumbnailWidth)
        .height(this.thumbnailHeight)
        .backgroundColor(this.pageFill())
        .borderRadius(16)
        .border({ width: 1, color: this.pageAccent() })

      if (this.rasterUri().length > 0) {
        Image(this.rasterUri())
          .width(this.thumbnailWidth)
          .height(this.thumbnailHeight)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
      } else {
        ForEach(this.rectNodes(), (node: PreviewRectNode) => {
          Row()
            .width(node.width)
            .height(node.height)
            .backgroundColor(node.fill)
            .opacity(node.opacity)
            .borderRadius(node.radius ?? 0)
            .border({
              width: node.borderWidth ?? 0,
              color: node.borderColor ?? 'transparent'
            })
            .position({ x: node.x, y: node.y })
        }, (node: PreviewRectNode): string => node.id)

        ForEach(this.textNodes(), (node: PreviewTextNode) => {
          Text(node.text)
            .fontSize(node.fontSize)
            .fontColor(node.color)
            .opacity(node.opacity)
            .maxLines(1)
            .position({ x: node.x, y: node.y })
        }, (node: PreviewTextNode): string => node.id)

        if (this.rectNodes().length === 0 && this.textNodes().length === 0) {
          Column() {
            Text(this.fallbackSummary.length > 0 ? this.fallbackSummary : 'Preview unavailable')
              .fontSize(11)
              .fontColor('#667085')
              .maxLines(4)
          }
          .width(this.thumbnailWidth - 28)
          .height(this.thumbnailHeight - 28)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
          .position({ x: 14, y: 14 })
        }
      }
    }
    .width(this.thumbnailWidth)
    .height(this.thumbnailHeight)
  }
}
