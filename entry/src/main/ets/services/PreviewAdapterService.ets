import {
  buildDefaultPreviewLayers,
  buildNativePageContractFromMetadata,
  buildPageId,
  NativeCornellGuideConfig,
  NativeGuideKind,
  NativeGuidePrimitive,
  NativeGuidePrimitiveKind,
  NativeLayerId,
  NativePageContract,
  NativePreviewBounds,
  NativePreviewLayout,
  NativeRatioBounds,
  NativeWeeklyGuideConfig,
  NATIVE_PRIMARY_PAGE_ID
} from '../models/NativeNoteContracts';
import {
  DocumentPreviewSnapshot,
  DocumentPreviewSource,
  DocumentPreviewStatus,
  DOCUMENT_PREVIEW_SCHEMA_VERSION,
  PreviewNormalizationContext,
  PreviewRasterAsset
} from '../models/PreviewModels';
import { DocumentType } from '../models/NoteModels';

type PreviewValue = Object | string | number | boolean | null;
type PreviewMap = Record<string, PreviewValue>;

export class PreviewAdapterService {
  normalizeRequestPreviewRenderPayload(
    rawPayload: string | Object | null | undefined,
    context: PreviewNormalizationContext
  ): DocumentPreviewSnapshot {
    const rawMap: PreviewMap | undefined = this.toPreviewMap(rawPayload);
    const pageIndex: number = this.readInteger(rawMap, ['pageIndex', 'page', 'page_number'], context.fallbackPageIndex ?? 0);
    const fallbackContract: NativePageContract = buildNativePageContractFromMetadata(
      context.pageMetadata,
      pageIndex >= 0 ? buildPageId(pageIndex) : NATIVE_PRIMARY_PAGE_ID
    );
    const pageContract: NativePageContract = this.normalizePageContract(rawMap, fallbackContract);
    const hasNativePayload: boolean = this.hasNativePayload(rawMap);
    const source: DocumentPreviewSource = this.resolveSource(rawMap, hasNativePayload);
    const previewStatus: DocumentPreviewStatus = this.resolvePreviewStatus(rawMap, source, hasNativePayload);
    const rawSummary: string = this.readString(rawMap, ['nativeSummary', 'summary']);
    const summary: string = context.fallbackSummary.length > 0
      ? context.fallbackSummary
      : (rawSummary.length > 0 ? rawSummary : '');
    const rawStatus: string = this.readString(rawMap, ['status']);
    const targetMode: string = this.readString(rawMap, ['targetMode']) || (source === 'markdown' ? 'summary-only' : 'structured');
    const previewLabel: string = this.readString(rawMap, ['previewLabel', 'label']) || context.fallbackPreviewLabel;
    const layers: NativeLayerId[] = this.normalizeLayers(rawMap, context.documentType);
    const defaultCoverPageId: string = pageContract.pageId.length > 0 ? pageContract.pageId : NATIVE_PRIMARY_PAGE_ID;
    const coverPageId: string = this.resolveCoverPageId(rawMap, defaultCoverPageId, pageIndex);
    const pageIds: string[] = this.normalizePageIds(rawMap, defaultCoverPageId, pageIndex, coverPageId);
    const coordinateSpace: string = this.readString(rawMap, ['coordinateSpace']);
    const raster: PreviewRasterAsset | undefined = this.normalizeRaster(rawMap);
    const layout: NativePreviewLayout | undefined = this.normalizeLayout(rawMap);
    const targetBounds: NativePreviewBounds | undefined = this.normalizeBounds(rawMap?.['targetBounds']);
    const nativeStatus: string = this.readString(rawMap, ['nativeStatus', 'renderStatus']);
    const errorMessage: string = this.readString(rawMap, ['errorMessage', 'error', 'message']);
    const extension: Record<string, Object | string | number | boolean | null> | undefined = this.extractExtension(rawMap);

    const snapshot: DocumentPreviewSnapshot = {
      schemaVersion: DOCUMENT_PREVIEW_SCHEMA_VERSION,
      previewSchemaVersion: this.readInteger(rawMap, ['previewSchemaVersion'], 0),
      generatedAt: this.readInteger(rawMap, ['generatedAt', 'generated_at', 'timestamp'], context.generatedAt),
      summary,
      previewLabel,
      type: context.documentType,
      source,
      previewStatus,
      status: rawStatus.length > 0 ? rawStatus : (source === 'markdown' ? 'summary-only' : 'ready'),
      targetMode,
      coverPageId,
      pageIds,
      layers,
      pageIndex,
      documentMode: context.documentMode,
      renderBackend: context.renderBackend,
      pageContract
    };

    if (rawSummary.length > 0 && rawSummary !== summary) {
      snapshot.nativeSummary = rawSummary;
    }
    if (coordinateSpace.length > 0) {
      snapshot.coordinateSpace = coordinateSpace;
    }
    if (targetBounds !== undefined) {
      snapshot.targetBounds = targetBounds;
    }
    if (layout !== undefined) {
      snapshot.layout = layout;
    }
    const checkpointCount: number | undefined = this.readOptionalNumber(rawMap, ['checkpointCount']);
    const objectCount: number | undefined = this.readOptionalNumber(rawMap, ['objectCount', 'strokeCount']);
    const renderWidth: number | undefined = this.readOptionalNumber(rawMap, ['renderWidth', 'width', 'requestWidth']);
    const renderHeight: number | undefined = this.readOptionalNumber(rawMap, ['renderHeight', 'height', 'requestHeight']);
    if (checkpointCount !== undefined) {
      snapshot.checkpointCount = Math.max(0, Math.trunc(checkpointCount));
    }
    if (objectCount !== undefined) {
      snapshot.objectCount = Math.max(0, Math.trunc(objectCount));
    }
    if (renderWidth !== undefined) {
      snapshot.renderWidth = renderWidth;
    }
    if (renderHeight !== undefined) {
      snapshot.renderHeight = renderHeight;
    }
    if (nativeStatus.length > 0) {
      snapshot.nativeStatus = nativeStatus;
    }
    if (raster !== undefined) {
      snapshot.raster = raster;
    }
    if (errorMessage.length > 0) {
      snapshot.errorMessage = errorMessage;
    }
    if (extension !== undefined && Object.keys(extension).length > 0) {
      snapshot.extension = extension;
    }
    return snapshot;
  }

  private toPreviewMap(rawPayload: string | Object | null | undefined): PreviewMap | undefined {
    if (typeof rawPayload === 'string') {
      const text: string = rawPayload.trim();
      if (text.length === 0) {
        return undefined;
      }
      try {
        const parsed: Object = JSON.parse(text) as Object;
        return this.toPreviewMap(parsed);
      } catch (_) {
        return undefined;
      }
    }
    if (!rawPayload || typeof rawPayload !== 'object' || Array.isArray(rawPayload)) {
      return undefined;
    }
    return rawPayload as PreviewMap;
  }

  private hasNativePayload(rawMap: PreviewMap | undefined): boolean {
    if (!rawMap) {
      return false;
    }
    const source: string = this.readString(rawMap, ['source']);
    if (source === 'native' || source === 'hybrid') {
      return true;
    }
    return rawMap['pageContract'] !== undefined ||
      rawMap['previewSchemaVersion'] !== undefined ||
      rawMap['targetMode'] !== undefined ||
      rawMap['layout'] !== undefined ||
      rawMap['layers'] !== undefined ||
      rawMap['targetBounds'] !== undefined ||
      rawMap['imageBase64'] !== undefined ||
      rawMap['pngBase64'] !== undefined ||
      rawMap['raster'] !== undefined ||
      rawMap['guideKind'] !== undefined;
  }

  private resolveSource(rawMap: PreviewMap | undefined, hasNativePayload: boolean): DocumentPreviewSource {
    const source: string = this.readString(rawMap, ['source']);
    if (source === 'markdown' || source === 'native' || source === 'hybrid') {
      return source;
    }
    return hasNativePayload ? 'native' : 'markdown';
  }

  private resolvePreviewStatus(
    rawMap: PreviewMap | undefined,
    source: DocumentPreviewSource,
    hasNativePayload: boolean
  ): DocumentPreviewStatus {
    const rawStatus: string = this.readString(rawMap, ['status', 'renderStatus', 'nativeStatus']).toLowerCase();
    if (rawStatus === 'error' || rawStatus === 'failed' || rawStatus === 'failure') {
      return 'error';
    }
    if (rawStatus === 'ready' || rawStatus === 'ok' || rawStatus === 'success' || rawStatus === 'completed') {
      return 'ready';
    }
    if (source === 'markdown' && !hasNativePayload) {
      return 'fallback';
    }
    return hasNativePayload ? 'ready' : 'fallback';
  }

  private normalizePageContract(rawMap: PreviewMap | undefined, fallback: NativePageContract): NativePageContract {
    const contractMap: PreviewMap | undefined = this.extractPageContractMap(rawMap);
    if (!contractMap) {
      return fallback;
    }

    const contract: NativePageContract = {
      schemaVersion: this.readInteger(contractMap, ['schemaVersion'], fallback.schemaVersion),
      pageId: this.readString(contractMap, ['pageId']) || fallback.pageId,
      pageTemplateId: this.readString(contractMap, ['pageTemplateId']) || fallback.pageTemplateId,
      pageSizeId: this.readString(contractMap, ['pageSizeId']) || fallback.pageSizeId,
      widthPt: this.readNumber(contractMap, ['widthPt'], fallback.widthPt),
      heightPt: this.readNumber(contractMap, ['heightPt'], fallback.heightPt),
      paperBackgroundId: this.readString(contractMap, ['paperBackgroundId']) || fallback.paperBackgroundId,
      fill: this.readString(contractMap, ['fill', 'fillColor']) || fallback.fill,
      accent: this.readString(contractMap, ['accent', 'accentColor']) || fallback.accent,
      guideKind: this.readGuideKind(contractMap, fallback.guideKind),
      primitives: this.normalizePrimitives(contractMap['primitives'], fallback.primitives),
      fillColor: this.readString(contractMap, ['fillColor', 'fill']) || fallback.fillColor,
      accentColor: this.readString(contractMap, ['accentColor', 'accent']) || fallback.accentColor,
      guide: fallback.guide
    };

    const rawGuide: PreviewMap | undefined = this.toPreviewMap(contractMap['guide']);
    if (rawGuide !== undefined) {
      contract.guide = {
        guideKind: this.readGuideKind(rawGuide, fallback.guide.guideKind),
        contentBounds: this.normalizeRatioBounds(rawGuide['contentBounds'], fallback.guide.contentBounds),
        spacingX: this.readOptionalNumber(rawGuide, ['spacingX']) ?? fallback.guide.spacingX,
        spacingY: this.readOptionalNumber(rawGuide, ['spacingY']) ?? fallback.guide.spacingY,
        secondarySpacingY: this.readOptionalNumber(rawGuide, ['secondarySpacingY']) ?? fallback.guide.secondarySpacingY,
        accentLineX: this.readOptionalNumber(rawGuide, ['accentLineX']) ?? fallback.guide.accentLineX,
        dividerX: this.readOptionalNumber(rawGuide, ['dividerX']) ?? fallback.guide.dividerX,
        dividerY: this.readOptionalNumber(rawGuide, ['dividerY']) ?? fallback.guide.dividerY,
        headerHeight: this.readOptionalNumber(rawGuide, ['headerHeight']) ?? fallback.guide.headerHeight,
        columnCount: this.readOptionalNumber(rawGuide, ['columnCount']) ?? fallback.guide.columnCount,
        dotRadius: this.readOptionalNumber(rawGuide, ['dotRadius']) ?? fallback.guide.dotRadius
      };
    }

    const cornell: NativeCornellGuideConfig | undefined = this.normalizeCornellGuide(
      this.toPreviewMap(contractMap['cornell']),
      fallback.cornell
    );
    const weekly: NativeWeeklyGuideConfig | undefined = this.normalizeWeeklyGuide(
      this.toPreviewMap(contractMap['weekly']),
      fallback.weekly
    );
    if (cornell !== undefined) {
      contract.cornell = cornell;
    }
    if (weekly !== undefined) {
      contract.weekly = weekly;
    }
    return contract;
  }

  private extractPageContractMap(rawMap: PreviewMap | undefined): PreviewMap | undefined {
    if (!rawMap) {
      return undefined;
    }
    const nestedContract: PreviewMap | undefined = this.toPreviewMap(rawMap['pageContract']);
    if (nestedContract !== undefined) {
      return nestedContract;
    }
    const hasTopLevelContractKeys: boolean = rawMap['guideKind'] !== undefined ||
      rawMap['widthPt'] !== undefined ||
      rawMap['heightPt'] !== undefined ||
      rawMap['fill'] !== undefined ||
      rawMap['accent'] !== undefined ||
      rawMap['primitives'] !== undefined ||
      rawMap['cornell'] !== undefined ||
      rawMap['weekly'] !== undefined;
    return hasTopLevelContractKeys ? rawMap : undefined;
  }

  private normalizePrimitives(value: PreviewValue | undefined, fallback: NativeGuidePrimitive[]): NativeGuidePrimitive[] {
    if (!Array.isArray(value)) {
      return fallback;
    }
    const primitives: NativeGuidePrimitive[] = [];
    value.forEach((entry: Object | string | number | boolean | null) => {
      const primitiveMap: PreviewMap | undefined = this.toPreviewMap(entry as Object);
      if (!primitiveMap) {
        return;
      }
      const kind: NativeGuidePrimitiveKind | undefined = this.readPrimitiveKind(primitiveMap);
      const id: string = this.readString(primitiveMap, ['id']);
      if (kind === undefined || id.length === 0) {
        return;
      }
      const primitive: NativeGuidePrimitive = {
        id,
        kind,
        x: this.readNumber(primitiveMap, ['x'], 0),
        y: this.readNumber(primitiveMap, ['y'], 0),
        width: this.readNumber(primitiveMap, ['width'], 0),
        height: this.readNumber(primitiveMap, ['height'], 0)
      };
      const stroke: string = this.readString(primitiveMap, ['stroke', 'strokeColor']);
      const fill: string = this.readString(primitiveMap, ['fill', 'fillColor']);
      const text: string = this.readString(primitiveMap, ['text']);
      if (stroke.length > 0) {
        primitive.stroke = stroke;
      }
      if (fill.length > 0) {
        primitive.fill = fill;
      }
      if (text.length > 0) {
        primitive.text = text;
      }
      const strokeWidth: number | undefined = this.readOptionalNumber(primitiveMap, ['strokeWidth']);
      const opacity: number | undefined = this.readOptionalNumber(primitiveMap, ['opacity']);
      const spacingX: number | undefined = this.readOptionalNumber(primitiveMap, ['spacingX']);
      const spacingY: number | undefined = this.readOptionalNumber(primitiveMap, ['spacingY']);
      const dotRadius: number | undefined = this.readOptionalNumber(primitiveMap, ['dotRadius']);
      const metadata: PreviewMap | undefined = this.toPreviewMap(primitiveMap['metadata']);
      if (strokeWidth !== undefined) {
        primitive.strokeWidth = strokeWidth;
      }
      if (opacity !== undefined) {
        primitive.opacity = opacity;
      }
      if (spacingX !== undefined) {
        primitive.spacingX = spacingX;
      }
      if (spacingY !== undefined) {
        primitive.spacingY = spacingY;
      }
      if (dotRadius !== undefined) {
        primitive.dotRadius = dotRadius;
      }
      if (metadata !== undefined) {
        primitive.metadata = metadata as Record<string, string | number | boolean>;
      }
      primitives.push(primitive);
    });
    return primitives.length > 0 ? primitives : fallback;
  }

  private normalizeCornellGuide(
    rawMap: PreviewMap | undefined,
    fallback: NativeCornellGuideConfig | undefined
  ): NativeCornellGuideConfig | undefined {
    if (!rawMap && fallback === undefined) {
      return undefined;
    }
    const base: NativeCornellGuideConfig = fallback ?? {
      headerHeight: 0.08,
      cueColumnStart: 0.08,
      cueColumnWidth: 0.18,
      noteColumnStart: 0.32,
      noteColumnWidth: 0.60,
      summaryTop: 0.76,
      summaryHeight: 0.18,
      cueRuleSpacing: 0.10,
      noteRuleSpacing: 0.06
    };
    if (!rawMap) {
      return base;
    }
    return {
      headerHeight: this.readNumber(rawMap, ['headerHeight'], base.headerHeight),
      cueColumnStart: this.readNumber(rawMap, ['cueColumnStart'], base.cueColumnStart),
      cueColumnWidth: this.readNumber(rawMap, ['cueColumnWidth'], base.cueColumnWidth),
      noteColumnStart: this.readNumber(rawMap, ['noteColumnStart'], base.noteColumnStart),
      noteColumnWidth: this.readNumber(rawMap, ['noteColumnWidth'], base.noteColumnWidth),
      summaryTop: this.readNumber(rawMap, ['summaryTop'], base.summaryTop),
      summaryHeight: this.readNumber(rawMap, ['summaryHeight'], base.summaryHeight),
      cueRuleSpacing: this.readNumber(rawMap, ['cueRuleSpacing'], base.cueRuleSpacing),
      noteRuleSpacing: this.readNumber(rawMap, ['noteRuleSpacing'], base.noteRuleSpacing)
    };
  }

  private normalizeWeeklyGuide(
    rawMap: PreviewMap | undefined,
    fallback: NativeWeeklyGuideConfig | undefined
  ): NativeWeeklyGuideConfig | undefined {
    if (!rawMap && fallback === undefined) {
      return undefined;
    }
    const base: NativeWeeklyGuideConfig = fallback ?? {
      headerHeight: 0.08,
      dayColumnCount: 7,
      weekGridTop: 0.14,
      weekGridHeight: 0.56,
      dayColumnWidth: 0.128,
      notesTop: 0.77,
      notesHeight: 0.16,
      noteRuleSpacing: 0.045
    };
    if (!rawMap) {
      return base;
    }
    return {
      headerHeight: this.readNumber(rawMap, ['headerHeight'], base.headerHeight),
      dayColumnCount: this.readInteger(rawMap, ['dayColumnCount'], base.dayColumnCount),
      weekGridTop: this.readNumber(rawMap, ['weekGridTop'], base.weekGridTop),
      weekGridHeight: this.readNumber(rawMap, ['weekGridHeight'], base.weekGridHeight),
      dayColumnWidth: this.readNumber(rawMap, ['dayColumnWidth'], base.dayColumnWidth),
      notesTop: this.readNumber(rawMap, ['notesTop', 'notesAreaTop'], base.notesTop),
      notesHeight: this.readNumber(rawMap, ['notesHeight', 'notesAreaHeight'], base.notesHeight),
      noteRuleSpacing: this.readNumber(rawMap, ['noteRuleSpacing'], base.noteRuleSpacing)
    };
  }

  private normalizeRaster(rawMap: PreviewMap | undefined): PreviewRasterAsset | undefined {
    if (!rawMap) {
      return undefined;
    }
    const rasterMap: PreviewMap | undefined = this.toPreviewMap(rawMap['raster']);
    const base64: string = this.readString(rasterMap, ['base64', 'imageBase64']) ||
      this.readString(rawMap, ['imageBase64', 'pngBase64', 'previewBase64']);
    const uri: string = this.readString(rasterMap, ['uri', 'imageUri']) || this.readString(rawMap, ['imageUri']);
    const mimeType: string = this.readString(rasterMap, ['mimeType']) || this.readString(rawMap, ['mimeType']);
    if (base64.length === 0 && uri.length === 0) {
      return undefined;
    }
    const raster: PreviewRasterAsset = {
      mimeType: mimeType.length > 0 ? mimeType : 'image/png'
    };
    if (base64.length > 0) {
      raster.base64 = base64;
    }
    if (uri.length > 0) {
      raster.uri = uri;
    }
    const width: number | undefined = this.readOptionalNumber(rasterMap ?? rawMap, ['width', 'pixelWidth']);
    const height: number | undefined = this.readOptionalNumber(rasterMap ?? rawMap, ['height', 'pixelHeight']);
    if (width !== undefined) {
      raster.width = width;
    }
    if (height !== undefined) {
      raster.height = height;
    }
    return raster;
  }

  private normalizeLayout(rawMap: PreviewMap | undefined): NativePreviewLayout | undefined {
    const layoutMap: PreviewMap | undefined = this.toPreviewMap(rawMap?.['layout']);
    if (!layoutMap) {
      return undefined;
    }
    const pages: Object | string | number | boolean | null = layoutMap['pages'] ?? null;
    const normalizedPages: Record<string, Object | string | number | boolean | null>[] = [];
    if (Array.isArray(pages)) {
      pages.forEach((entry: Object | string | number | boolean | null) => {
        if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
          normalizedPages.push(entry as Record<string, Object | string | number | boolean | null>);
        }
      });
    }

    const layout: NativePreviewLayout = {
      mode: this.readString(layoutMap, ['mode']) || undefined,
      pageCount: this.readInteger(layoutMap, ['pageCount'], normalizedPages.length),
      pages: []
    };
    const documentBounds: NativePreviewBounds | undefined = this.normalizeBounds(layoutMap['documentBounds']);
    if (documentBounds !== undefined) {
      layout.documentBounds = documentBounds;
    }
    normalizedPages.forEach((pageMap: Record<string, Object | string | number | boolean | null>, index: number) => {
      const pageBounds: NativePreviewBounds | undefined = this.normalizeBounds(pageMap['bounds']);
      layout.pages.push({
        pageId: this.readString(pageMap, ['pageId']) || buildPageId(index),
        pageIndex: this.readInteger(pageMap, ['pageIndex'], index),
        width: this.readOptionalNumber(pageMap, ['width']),
        height: this.readOptionalNumber(pageMap, ['height']),
        bounds: pageBounds,
        backgroundId: this.readString(pageMap, ['backgroundId']) || undefined,
        guideKind: this.readGuideKind(pageMap, 'plain')
      });
    });
    return layout;
  }

  private normalizeBounds(value: PreviewValue | undefined): NativePreviewBounds | undefined {
    const boundsMap: PreviewMap | undefined = this.toPreviewMap(value as Object);
    if (!boundsMap) {
      return undefined;
    }
    return {
      minX: this.readNumber(boundsMap, ['minX'], 0),
      minY: this.readNumber(boundsMap, ['minY'], 0),
      maxX: this.readNumber(boundsMap, ['maxX'], 0),
      maxY: this.readNumber(boundsMap, ['maxY'], 0)
    };
  }

  private normalizeRatioBounds(value: PreviewValue | undefined, fallback: NativeRatioBounds): NativeRatioBounds {
    const boundsMap: PreviewMap | undefined = this.toPreviewMap(value as Object);
    if (!boundsMap) {
      const fallbackBounds: NativeRatioBounds = {
        x: fallback.x,
        y: fallback.y,
        width: fallback.width,
        height: fallback.height
      };
      return fallbackBounds;
    }
    const normalizedBounds: NativeRatioBounds = {
      x: this.readNumber(boundsMap, ['x'], fallback.x),
      y: this.readNumber(boundsMap, ['y'], fallback.y),
      width: this.readNumber(boundsMap, ['width'], fallback.width),
      height: this.readNumber(boundsMap, ['height'], fallback.height)
    };
    return normalizedBounds;
  }

  private resolveCoverPageId(rawMap: PreviewMap | undefined, fallbackCoverPageId: string, pageIndex: number): string {
    const pageId: string = this.readString(rawMap, ['pageId']);
    if (pageId.length > 0) {
      return pageId;
    }
    if (pageIndex >= 0) {
      return buildPageId(pageIndex);
    }
    const rawCoverPageId: string = this.readString(rawMap, ['coverPageId']);
    return rawCoverPageId.length > 0 ? rawCoverPageId : fallbackCoverPageId;
  }

  private normalizePageIds(
    rawMap: PreviewMap | undefined,
    fallbackCoverPageId: string,
    pageIndex: number,
    preferredCoverPageId: string
  ): string[] {
    const pageIds: string[] = [];
    const directPageIds: PreviewValue | undefined = rawMap?.['pageIds'];
    if (Array.isArray(directPageIds)) {
      directPageIds.forEach((entry: Object | string | number | boolean | null) => {
        if (typeof entry === 'string' && entry.length > 0 && !pageIds.includes(entry)) {
          pageIds.push(entry);
        }
      });
    }

    const layout: NativePreviewLayout | undefined = this.normalizeLayout(rawMap);
    layout?.pages.forEach((page) => {
      if (page.pageId.length > 0 && !pageIds.includes(page.pageId)) {
        pageIds.push(page.pageId);
      }
    });

    const rawCoverPageId: string = this.readString(rawMap, ['coverPageId']);
    if (rawCoverPageId.length > 0 && !pageIds.includes(rawCoverPageId)) {
      pageIds.push(rawCoverPageId);
    }
    const pageId: string = this.readString(rawMap, ['pageId']);
    if (pageId.length > 0 && !pageIds.includes(pageId)) {
      pageIds.push(pageId);
    }
    if (pageIds.length === 0) {
      pageIds.push(preferredCoverPageId.length > 0
        ? preferredCoverPageId
        : (pageIndex >= 0 ? buildPageId(pageIndex) : fallbackCoverPageId));
    }
    if (preferredCoverPageId.length > 0 && !pageIds.includes(preferredCoverPageId)) {
      pageIds.push(preferredCoverPageId);
    }
    if (!pageIds.includes(fallbackCoverPageId)) {
      pageIds.push(fallbackCoverPageId);
    }
    return pageIds;
  }

  private normalizeLayers(rawMap: PreviewMap | undefined, documentType: DocumentType): NativeLayerId[] {
    const layers: NativeLayerId[] = [];
    const rawLayers: PreviewValue | undefined = rawMap?.['layers'];
    if (Array.isArray(rawLayers)) {
      rawLayers.forEach((entry: Object | string | number | boolean | null) => {
        if (entry === 'pdf' || entry === 'ink' || entry === 'transient') {
          const layer: NativeLayerId = entry as NativeLayerId;
          if (!layers.includes(layer)) {
            layers.push(layer);
          }
        }
      });
    }
    return layers.length > 0 ? layers : buildDefaultPreviewLayers(documentType);
  }

  private extractExtension(rawMap: PreviewMap | undefined): Record<string, Object | string | number | boolean | null> | undefined {
    if (!rawMap) {
      return undefined;
    }
    const knownKeys: string[] = [
      'schemaVersion',
      'previewSchemaVersion',
      'generatedAt',
      'generated_at',
      'timestamp',
      'summary',
      'nativeSummary',
      'previewLabel',
      'label',
      'type',
      'source',
      'status',
      'renderStatus',
      'nativeStatus',
      'targetMode',
      'coverPageId',
      'pageId',
      'pageIds',
      'pageIndex',
      'page',
      'page_number',
      'documentMode',
      'renderBackend',
      'renderWidth',
      'renderHeight',
      'width',
      'height',
      'requestWidth',
      'requestHeight',
      'layout',
      'layers',
      'coordinateSpace',
      'targetBounds',
      'checkpointCount',
      'objectCount',
      'strokeCount',
      'pageContract',
      'guide',
      'guideKind',
      'pageTemplateId',
      'pageSizeId',
      'paperBackgroundId',
      'widthPt',
      'heightPt',
      'fill',
      'accent',
      'fillColor',
      'accentColor',
      'primitives',
      'cornell',
      'weekly',
      'raster',
      'imageBase64',
      'pngBase64',
      'previewBase64',
      'imageUri',
      'mimeType',
      'errorMessage',
      'error',
      'message'
    ];
    const extension: Record<string, Object | string | number | boolean | null> = {};
    Object.keys(rawMap).forEach((key: string) => {
      if (knownKeys.includes(key)) {
        return;
      }
      extension[key] = rawMap[key];
    });
    return extension;
  }

  private readPrimitiveKind(rawMap: PreviewMap): NativeGuidePrimitiveKind | undefined {
    const rawKind: string = this.readString(rawMap, ['kind', 'type']);
    switch (rawKind) {
      case 'horizontalLines':
      case 'horizontal_lines':
        return 'horizontalLines';
      case 'grid':
        return 'grid';
      case 'dots':
        return 'dots';
      case 'divider':
        return 'divider';
      case 'header':
        return 'header';
      case 'sidebar':
        return 'sidebar';
      case 'label':
        return 'label';
      default:
        return undefined;
    }
  }

  private readGuideKind(rawMap: PreviewMap, fallback: NativeGuideKind): NativeGuideKind {
    const rawKind: string = this.readString(rawMap, ['guideKind']);
    switch (rawKind) {
      case 'plain':
      case 'blank':
        return 'plain';
      case 'lined':
        return 'lined';
      case 'grid':
        return 'grid';
      case 'dotted':
        return 'dotted';
      case 'cornell':
        return 'cornell';
      case 'weekly':
      case 'weekly_planner':
        return 'weekly';
      default:
        return fallback;
    }
  }

  private readString(rawMap: PreviewMap | undefined, keys: string[]): string {
    if (!rawMap) {
      return '';
    }
    for (const key of keys) {
      const value: PreviewValue | undefined = rawMap[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
    return '';
  }

  private readNumber(rawMap: PreviewMap | undefined, keys: string[], fallback: number): number {
    const value: number | undefined = this.readOptionalNumber(rawMap, keys);
    return value !== undefined ? value : fallback;
  }

  private readInteger(rawMap: PreviewMap | undefined, keys: string[], fallback: number): number {
    const value: number | undefined = this.readOptionalNumber(rawMap, keys);
    return value !== undefined ? Math.trunc(value) : fallback;
  }

  private readOptionalNumber(rawMap: PreviewMap | undefined, keys: string[]): number | undefined {
    if (!rawMap) {
      return undefined;
    }
    for (const key of keys) {
      const value: PreviewValue | undefined = rawMap[key];
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
      if (typeof value === 'string' && value.trim().length > 0) {
        const parsed: number = Number(value);
        if (Number.isFinite(parsed)) {
          return parsed;
        }
      }
    }
    return undefined;
  }
}
