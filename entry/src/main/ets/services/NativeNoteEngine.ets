import nativeModule from 'libentry.so';
import { DocumentMode, RenderBackend, ToolType } from '../models/NoteModels';
import {
  buildPageId,
  NativeGuideKind,
  NativeLayerId,
  NativeOpenDocumentConfig,
  NativePageContract,
  NativePreviewBounds,
  NativePreviewLayout,
  NativePreviewPage,
  NativePreviewPayload,
  NativePreviewRasterAsset,
  NativeSceneObject,
  NativeScenePoint,
  NativeSceneSnapshot
} from '../models/NativeNoteContracts';

interface NativeEntryModule {
  createEngine(configJson: string): string;
  openDocument(engineId: string, documentId: string, packagePath: string, configJson: string): boolean;
  attachXComponent(engineId: string, xComponentId: string, surfaceId: string): boolean;
  resize(engineId: string, width: number, height: number, density: number): boolean;
  saveCheckpoint(engineId: string, documentId: string): boolean;
  readPdfPageCount?: (pdfPath: string) => string;
  requestPreviewRender(engineId: string, documentId: string, pageIndex: number, width: number, height: number): string;
  exportSceneSnapshot(engineId: string, documentId: string): string;
  setActivePage(engineId: string, pageId: string): boolean;
  insertPage(engineId: string, afterPageId: string, pageConfigJson: string): boolean;
  deletePage(engineId: string, pageId: string): boolean;
  setTool(engineId: string, tool: string): boolean;
  setFingerWritingEnabled(engineId: string, enabled: boolean): boolean;
  injectSimulatorFingerEvent(
    engineId: string,
    action: string,
    pageXRatio: number,
    pageYRatio: number,
    pointerCount: number
  ): boolean;
  getSimulatorPrediction(engineId: string): string;
  setBackend(engineId: string, backend: string): boolean;
  setDocumentMode(engineId: string, mode: string): boolean;
  setBrushColor(engineId: string, colorHex: string): boolean;
  setBrushWidth(engineId: string, width: number): boolean;
  undo(engineId: string): boolean;
  redo(engineId: string): boolean;
  startInputTraceRecording(engineId: string, tracePath?: string): boolean;
  stopInputTraceRecording(engineId: string): string;
  replayInputTrace(engineId: string, tracePath?: string): string;
  disposeDocument(engineId: string, documentId: string): boolean;
  disposeEngine(engineId: string): boolean;
  getDebugState(engineId: string): string;
}

export interface EngineConfig {
  backend: RenderBackend;
  documentMode: DocumentMode;
  dpiScale: number;
  enablePrediction: boolean;
  enablePressureForPen: boolean;
  enableShapeDetection: boolean;
  enableMarkdownOverlay: boolean;
}

export interface NativeDebugState {
  engineId: string;
  activeDocumentId: string;
  activePageId: string;
  activePageIndex: number;
  pageCount: number;
  activeTool: string;
  activeBackend: string;
  activeMode: string;
  activeColor: string;
  activeBrushWidth: number;
  xComponentId: string;
  surfaceId: string;
  checkpointCount: number;
  fingerWritingEnabled: boolean;
  predictionEnabled: boolean;
  pressureEnabled: boolean;
  shapeRecognitionEnabled: boolean;
  surfaceReady: boolean;
  surfaceWidth: number;
  surfaceHeight: number;
  surfaceOffsetX: number;
  surfaceOffsetY: number;
  touchEventCount: number;
  uiTouchEventCount: number;
  keyEventCount: number;
  stylusEventCount: number;
  fingerEventCount: number;
  palmRejectedCount: number;
  activePointerCount: number;
  stylusActive: boolean;
  multitouchGestureActive: boolean;
  lastHistoricalCount: number;
  lastUiHistoryCount: number;
  predictedPointCount: number;
  lastEventTime: number;
  lastPressure: number;
  lastTiltX: number;
  lastTiltY: number;
  lastRollAngle: number;
  lastTouchAction: string;
  lastToolType: string;
  lastSourceType: string;
  lastKeyCode: number;
  lastKeyAction: number;
  lastKeySourceType: number;
  lastKeyEventTime: number;
  committedStrokeCount: number;
  undoDepth: number;
  redoDepth: number;
  lastCommittedStrokeType: string;
  inputTraceRecording: boolean;
  inputReplayActive: boolean;
  inputTraceStatus: string;
  inputTracePath: string;
  inputTraceSampleCount: number;
  runtimeProfile: string;
  traceSupported: boolean;
  previewRenderSupported: boolean;
  sceneExportSupported: boolean;
  stubReason: string;
}

export interface TraceActionResult {
  status: string;
  path?: string;
  sampleCount?: number;
}

export interface NativeSimulatorPrediction {
  status: string;
  suppressed: boolean;
  cpuBusyRatio: number;
  points: NativeScenePoint[];
}

export type NativePdfPageCountStatus =
  'ok' |
  'invalid-args' |
  'file-not-found' |
  'read-failed' |
  'invalid-pdf' |
  'page-count-unavailable';

export interface NativePdfPageCountResult {
  status: NativePdfPageCountStatus;
  pageCount?: number;
  detail?: string;
}

const nativeBridge: NativeEntryModule = nativeModule as NativeEntryModule;

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;

function readJsonMap(rawText: string): JsonMap | null {
  if (!rawText) {
    return null;
  }
  try {
    return JSON.parse(rawText) as JsonMap;
  } catch (_) {
    return null;
  }
}

function readStringValue(source: JsonMap, key: string, fallback: string = ''): string {
  const value: JsonValue | undefined = source[key];
  return typeof value === 'string' ? value : fallback;
}

function readNumberValue(source: JsonMap, key: string, fallback: number = 0): number {
  const value: JsonValue | undefined = source[key];
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed: number = Number.parseFloat(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function readOptionalNumberValue(source: JsonMap, key: string): number | undefined {
  const value: JsonValue | undefined = source[key];
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed: number = Number.parseFloat(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return undefined;
}

function readBooleanValue(source: JsonMap, key: string, fallback: boolean = false): boolean {
  const value: JsonValue | undefined = source[key];
  return typeof value === 'boolean' ? value : fallback;
}

function readStringValueByKeys(source: JsonMap, keys: string[], fallback: string = ''): string {
  for (let index = 0; index < keys.length; index += 1) {
    const key: string = keys[index];
    if (source[key] !== undefined) {
      return readStringValue(source, key, fallback);
    }
  }
  return fallback;
}

function readBooleanValueByKeys(source: JsonMap, keys: string[], fallback: boolean): boolean {
  for (let index = 0; index < keys.length; index += 1) {
    const key: string = keys[index];
    if (source[key] !== undefined) {
      return readBooleanValue(source, key, fallback);
    }
  }
  return fallback;
}

function readObjectValue(value: JsonValue | undefined): JsonMap | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as JsonMap;
}

function readArrayValue(value: JsonValue | undefined): JsonValue[] {
  return Array.isArray(value) ? value as JsonValue[] : [];
}

function normalizeLayerId(value: JsonValue | undefined, fallback: NativeLayerId = 'ink'): NativeLayerId {
  if (value === 'pdf' || value === 'ink' || value === 'transient') {
    return value as NativeLayerId;
  }
  return fallback;
}

function normalizeGuideKind(value: JsonValue | undefined): NativeGuideKind | undefined {
  if (value === 'plain' || value === 'lined' || value === 'grid' ||
    value === 'dotted' || value === 'cornell' || value === 'weekly') {
    return value as NativeGuideKind;
  }
  return undefined;
}

function parseBounds(value: JsonValue | undefined): NativePreviewBounds | undefined {
  const source: JsonMap | null = readObjectValue(value);
  if (!source) {
    return undefined;
  }
  return {
    minX: readNumberValue(source, 'minX', 0),
    minY: readNumberValue(source, 'minY', 0),
    maxX: readNumberValue(source, 'maxX', 0),
    maxY: readNumberValue(source, 'maxY', 0)
  };
}

function parsePageIndex(value: JsonValue | undefined): number | null | undefined {
  if (value === null) {
    return null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string') {
    const parsed: number = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return undefined;
}

function parsePreviewPage(value: JsonValue | undefined): NativePreviewPage | null {
  const source: JsonMap | null = readObjectValue(value);
  if (!source) {
    return null;
  }
  const pageIndex: number = Math.trunc(readNumberValue(source, 'pageIndex', 0));
  return {
    pageId: readStringValue(source, 'pageId', buildPageId(pageIndex)),
    pageIndex,
    width: readNumberValue(source, 'width', NaN),
    height: readNumberValue(source, 'height', NaN),
    bounds: parseBounds(source['bounds']),
    backgroundId: readStringValue(source, 'backgroundId', ''),
    guideKind: normalizeGuideKind(source['guideKind'])
  };
}

function compactPreviewPage(page: NativePreviewPage): NativePreviewPage {
  const width: number | undefined = typeof page.width === 'number' && Number.isFinite(page.width)
    ? page.width
    : undefined;
  const height: number | undefined = typeof page.height === 'number' && Number.isFinite(page.height)
    ? page.height
    : undefined;
  return {
    pageId: page.pageId,
    pageIndex: page.pageIndex,
    width,
    height,
    bounds: page.bounds,
    backgroundId: page.backgroundId && page.backgroundId.length > 0 ? page.backgroundId : undefined,
    guideKind: page.guideKind
  };
}

function parsePreviewLayout(value: JsonValue | undefined): NativePreviewLayout | undefined {
  const source: JsonMap | null = readObjectValue(value);
  if (!source) {
    return undefined;
  }
  const pages: NativePreviewPage[] = [];
  readArrayValue(source['pages']).forEach((entry: JsonValue) => {
    const parsedPage: NativePreviewPage | null = parsePreviewPage(entry);
    if (parsedPage !== null) {
      pages.push(compactPreviewPage(parsedPage));
    }
  });
  return {
    mode: readStringValue(source, 'mode', ''),
    pageCount: Math.max(pages.length, Math.trunc(readNumberValue(source, 'pageCount', pages.length))),
    documentBounds: parseBounds(source['documentBounds']),
    pages
  };
}

function normalizePreviewLayers(value: JsonValue | undefined, fallbackObjectCount: number): NativeLayerId[] {
  const layers: NativeLayerId[] = [];
  readArrayValue(value).forEach((entry: JsonValue) => {
    if (entry === 'pdf' || entry === 'ink' || entry === 'transient') {
      const layer: NativeLayerId = normalizeLayerId(entry);
      if (!layers.includes(layer)) {
        layers.push(layer);
      }
    }
  });
  if (layers.length === 0 && fallbackObjectCount > 0) {
    layers.push('ink');
  }
  return layers;
}

function parsePreviewRaster(value: JsonValue | undefined, source: JsonMap): NativePreviewRasterAsset | undefined {
  const rasterSource: JsonMap | null = readObjectValue(value);
  const base64: string = readStringValue(rasterSource ?? source, 'base64', '') ||
    readStringValue(rasterSource ?? source, 'imageBase64', '') ||
    readStringValue(source, 'imageBase64', '') ||
    readStringValue(source, 'pngBase64', '') ||
    readStringValue(source, 'previewBase64', '');
  const uri: string = readStringValue(rasterSource ?? source, 'uri', '') ||
    readStringValue(rasterSource ?? source, 'imageUri', '') ||
    readStringValue(source, 'imageUri', '');
  const mimeType: string = readStringValue(rasterSource ?? source, 'mimeType', '') ||
    readStringValue(source, 'mimeType', '');
  if (base64.length === 0 && uri.length === 0) {
    return undefined;
  }
  const raster: NativePreviewRasterAsset = {
    mimeType: mimeType.length > 0 ? mimeType : 'image/png'
  };
  if (base64.length > 0) {
    raster.base64 = base64;
  }
  if (uri.length > 0) {
    raster.uri = uri;
  }
  const width: number | undefined = readOptionalNumberValue(rasterSource ?? source, 'width') ??
    readOptionalNumberValue(rasterSource ?? source, 'pixelWidth');
  const height: number | undefined = readOptionalNumberValue(rasterSource ?? source, 'height') ??
    readOptionalNumberValue(rasterSource ?? source, 'pixelHeight');
  if (width !== undefined) {
    raster.width = width;
  }
  if (height !== undefined) {
    raster.height = height;
  }
  return raster;
}

function parsePreviewPayload(source: JsonMap, fallbackPageIndex: number): NativePreviewPayload {
  const pageIndex: number = Math.trunc(readNumberValue(source, 'pageIndex', fallbackPageIndex));
  const objectCount: number = Math.max(
    0,
    Math.trunc(readNumberValue(source, 'objectCount', readNumberValue(source, 'strokeCount', 0)))
  );
  const layout: NativePreviewLayout | undefined = parsePreviewLayout(source['layout']);
  const width: number | undefined = readOptionalNumberValue(source, 'width') ?? readOptionalNumberValue(source, 'renderWidth');
  const height: number | undefined = readOptionalNumberValue(source, 'height') ?? readOptionalNumberValue(source, 'renderHeight');
  const raster: NativePreviewRasterAsset | undefined = parsePreviewRaster(source['raster'], source);
  const payload: NativePreviewPayload = {
    status: readStringValue(source, 'status', 'ready'),
    previewSchemaVersion: Math.trunc(readNumberValue(source, 'previewSchemaVersion', 0)),
    pageIndex,
    pageId: readStringValue(source, 'pageId', pageIndex >= 0 ? buildPageId(pageIndex) : '') || undefined,
    targetMode: readStringValue(source, 'targetMode', 'stats-fallback'),
    coordinateSpace: readStringValue(source, 'coordinateSpace', '') || undefined,
    targetBounds: parseBounds(source['targetBounds']),
    layout,
    layers: normalizePreviewLayers(source['layers'], objectCount),
    checkpointCount: Math.max(0, Math.trunc(readNumberValue(source, 'checkpointCount', 0))),
    objectCount
  };
  if (width !== undefined) {
    payload.width = width;
  }
  if (height !== undefined) {
    payload.height = height;
  }
  if (raster !== undefined) {
    payload.raster = raster;
    if (raster.base64 !== undefined) {
      payload.imageBase64 = raster.base64;
    }
    if (raster.uri !== undefined) {
      payload.imageUri = raster.uri;
    }
    payload.mimeType = raster.mimeType;
  }
  return payload;
}

function buildStatsFallbackPreview(source: JsonMap, fallbackPageIndex: number): NativePreviewPayload {
  const pageIndex: number = Math.trunc(readNumberValue(source, 'pageIndex', fallbackPageIndex));
  const objectCount: number = Math.max(
    0,
    Math.trunc(readNumberValue(source, 'strokeCount', readNumberValue(source, 'objectCount', 0)))
  );
  return {
    status: readStringValue(source, 'status', 'ready'),
    previewSchemaVersion: 0,
    pageIndex,
    pageId: pageIndex >= 0 ? buildPageId(pageIndex) : undefined,
    targetMode: 'stats-fallback',
    layers: objectCount > 0 ? ['ink'] : [],
    checkpointCount: Math.max(0, Math.trunc(readNumberValue(source, 'checkpointCount', 0))),
    objectCount
  };
}

function parseSceneObject(value: JsonValue | undefined): NativeSceneObject | null {
  const source: JsonMap | null = readObjectValue(value);
  if (!source) {
    return null;
  }
  const nodeType: string = readStringValue(source, 'nodeType', 'ink');
  const pageIndex: number | null | undefined = parsePageIndex(source['pageIndex']);
  const pageIdFallback: string = pageIndex !== undefined && pageIndex !== null ? buildPageId(pageIndex) : '';
  const bounds: NativePreviewBounds = parseBounds(source['bounds']) ?? { minX: 0, minY: 0, maxX: 0, maxY: 0 };
  const points: NativeScenePoint[] = [];
  readArrayValue(source['points']).forEach((entry: JsonValue) => {
    const pointSource: JsonMap | null = readObjectValue(entry);
    if (!pointSource) {
      return;
    }
    points.push({
      x: readNumberValue(pointSource, 'x', 0),
      y: readNumberValue(pointSource, 'y', 0)
    });
  });
  return {
    id: readStringValue(source, 'id', ''),
    nodeType,
    shapeType: readStringValue(source, 'shapeType', 'freehand'),
    tool: readStringValue(source, 'tool', 'pen'),
    colorHex: readStringValue(source, 'colorHex', '#1D2736'),
    strokeWidth: readOptionalNumberValue(source, 'strokeWidth'),
    selected: readBooleanValue(source, 'selected', false),
    pointCount: Math.max(0, Math.trunc(readNumberValue(source, 'pointCount', 0))),
    closed: readBooleanValue(source, 'closed', false),
    bounds,
    points: points.length > 0 ? points : undefined,
    layer: normalizeLayerId(source['layer'], nodeType.includes('pdf') ? 'pdf' : 'ink'),
    pageIndex,
    pageId: readStringValue(source, 'pageId', pageIdFallback) || undefined
  };
}

function parseSceneSnapshot(source: JsonMap): NativeSceneSnapshot {
  const parsedPages: NativePreviewPage[] = [];
  readArrayValue(source['pages']).forEach((entry: JsonValue) => {
    const parsedPage: NativePreviewPage | null = parsePreviewPage(entry);
    if (parsedPage !== null) {
      parsedPages.push(compactPreviewPage(parsedPage));
    }
  });
  const layout: NativePreviewLayout | undefined = parsePreviewLayout(source['layout']);
  const pages: NativePreviewPage[] = parsedPages.length > 0 ? parsedPages : (layout?.pages ?? []);
  const objects: NativeSceneObject[] = [];
  readArrayValue(source['objects']).forEach((entry: JsonValue) => {
    const parsedObject: NativeSceneObject | null = parseSceneObject(entry);
    if (parsedObject !== null) {
      objects.push(parsedObject);
    }
  });
  return {
    status: readStringValue(source, 'status', 'ready'),
    version: Math.trunc(readNumberValue(source, 'version', 1)),
    engineId: readStringValue(source, 'engineId', ''),
    documentId: readStringValue(source, 'documentId', ''),
    title: readStringValue(source, 'title', ''),
    documentType: readStringValue(source, 'documentType', ''),
    mode: readStringValue(source, 'mode', ''),
    backend: readStringValue(source, 'backend', ''),
    coordinateSpace: readStringValue(source, 'coordinateSpace', 'legacy-surface'),
    checkpointCount: Math.max(0, Math.trunc(readNumberValue(source, 'checkpointCount', 0))),
    objectCount: Math.max(objects.length, Math.trunc(readNumberValue(source, 'objectCount', objects.length))),
    layout: layout ?? (pages.length > 0 ? { pageCount: pages.length, pages } : undefined),
    pages,
    objects
  };
}

export function parseTraceActionResultJson(rawText: string): TraceActionResult | null {
  const parsed: JsonMap | null = readJsonMap(rawText);
  if (!parsed) {
    return null;
  }
  const result: TraceActionResult = {
    status: readStringValue(parsed, 'status', 'unknown')
  };
  const path: string = readStringValue(parsed, 'path', '');
  if (path.length > 0) {
    result.path = path;
  }
  const hasSampleCount: boolean = parsed['sampleCount'] !== undefined;
  if (hasSampleCount) {
    result.sampleCount = Math.max(0, Math.trunc(readNumberValue(parsed, 'sampleCount', 0)));
  }
  return result;
}

export function parseNativeDebugStateJson(rawText: string): NativeDebugState | null {
  const parsed: JsonMap | null = readJsonMap(rawText);
  if (!parsed) {
    return null;
  }
  return {
    engineId: readStringValue(parsed, 'engineId', ''),
    activeDocumentId: readStringValue(parsed, 'activeDocumentId', ''),
    activePageId: readStringValue(parsed, 'activePageId', buildPageId(0)),
    activePageIndex: Math.trunc(readNumberValue(parsed, 'activePageIndex', 0)),
    pageCount: Math.max(1, Math.trunc(readNumberValue(parsed, 'pageCount', 1))),
    activeTool: readStringValue(parsed, 'activeTool', ''),
    activeBackend: readStringValue(parsed, 'activeBackend', ''),
    activeMode: readStringValue(parsed, 'activeMode', ''),
    activeColor: readStringValue(parsed, 'activeColor', ''),
    activeBrushWidth: readNumberValue(parsed, 'activeBrushWidth', 3.2),
    xComponentId: readStringValue(parsed, 'xComponentId', ''),
    surfaceId: readStringValue(parsed, 'surfaceId', ''),
    checkpointCount: Math.trunc(readNumberValue(parsed, 'checkpointCount', 0)),
    fingerWritingEnabled: readBooleanValue(parsed, 'fingerWritingEnabled', false),
    predictionEnabled: readBooleanValue(parsed, 'predictionEnabled', false),
    pressureEnabled: readBooleanValue(parsed, 'pressureEnabled', false),
    shapeRecognitionEnabled: readBooleanValue(parsed, 'shapeRecognitionEnabled', false),
    surfaceReady: readBooleanValue(parsed, 'surfaceReady', false),
    surfaceWidth: readNumberValue(parsed, 'surfaceWidth', 0),
    surfaceHeight: readNumberValue(parsed, 'surfaceHeight', 0),
    surfaceOffsetX: readNumberValue(parsed, 'surfaceOffsetX', 0),
    surfaceOffsetY: readNumberValue(parsed, 'surfaceOffsetY', 0),
    touchEventCount: Math.trunc(readNumberValue(parsed, 'touchEventCount', 0)),
    uiTouchEventCount: Math.trunc(readNumberValue(parsed, 'uiTouchEventCount', 0)),
    keyEventCount: Math.trunc(readNumberValue(parsed, 'keyEventCount', 0)),
    stylusEventCount: Math.trunc(readNumberValue(parsed, 'stylusEventCount', 0)),
    fingerEventCount: Math.trunc(readNumberValue(parsed, 'fingerEventCount', 0)),
    palmRejectedCount: Math.trunc(readNumberValue(parsed, 'palmRejectedCount', 0)),
    activePointerCount: Math.trunc(readNumberValue(parsed, 'activePointerCount', 0)),
    stylusActive: readBooleanValue(parsed, 'stylusActive', false),
    multitouchGestureActive: readBooleanValue(parsed, 'multitouchGestureActive', false),
    lastHistoricalCount: Math.trunc(readNumberValue(parsed, 'lastHistoricalCount', 0)),
    lastUiHistoryCount: Math.trunc(readNumberValue(parsed, 'lastUiHistoryCount', 0)),
    predictedPointCount: Math.trunc(readNumberValue(parsed, 'predictedPointCount', 0)),
    lastEventTime: readNumberValue(parsed, 'lastEventTime', 0),
    lastPressure: readNumberValue(parsed, 'lastPressure', 0),
    lastTiltX: readNumberValue(parsed, 'lastTiltX', 0),
    lastTiltY: readNumberValue(parsed, 'lastTiltY', 0),
    lastRollAngle: readNumberValue(parsed, 'lastRollAngle', 0),
    lastTouchAction: readStringValue(parsed, 'lastTouchAction', ''),
    lastToolType: readStringValue(parsed, 'lastToolType', ''),
    lastSourceType: readStringValue(parsed, 'lastSourceType', ''),
    lastKeyCode: Math.trunc(readNumberValue(parsed, 'lastKeyCode', 0)),
    lastKeyAction: Math.trunc(readNumberValue(parsed, 'lastKeyAction', 0)),
    lastKeySourceType: Math.trunc(readNumberValue(parsed, 'lastKeySourceType', 0)),
    lastKeyEventTime: readNumberValue(parsed, 'lastKeyEventTime', 0),
    committedStrokeCount: Math.trunc(readNumberValue(parsed, 'committedStrokeCount', 0)),
    undoDepth: Math.trunc(readNumberValue(parsed, 'undoDepth', 0)),
    redoDepth: Math.trunc(readNumberValue(parsed, 'redoDepth', 0)),
    lastCommittedStrokeType: readStringValue(parsed, 'lastCommittedStrokeType', ''),
    inputTraceRecording: readBooleanValue(parsed, 'inputTraceRecording', false),
    inputReplayActive: readBooleanValue(parsed, 'inputReplayActive', false),
    inputTraceStatus: readStringValue(parsed, 'inputTraceStatus', ''),
    inputTracePath: readStringValue(parsed, 'inputTracePath', ''),
    inputTraceSampleCount: Math.trunc(readNumberValue(parsed, 'inputTraceSampleCount', 0)),
    runtimeProfile: readStringValueByKeys(parsed, ['runtimeProfile', 'runtimeMode'], 'device-native'),
    traceSupported: readBooleanValueByKeys(
      parsed,
      ['traceSupported', 'supportsInputTrace', 'supportsTraceRecording', 'supportsTrace'],
      false
    ),
    previewRenderSupported: readBooleanValueByKeys(
      parsed,
      ['previewRenderSupported'],
      false
    ),
    sceneExportSupported: readBooleanValueByKeys(
      parsed,
      ['sceneExportSupported'],
      false
    ),
    stubReason: readStringValueByKeys(parsed, ['stubReason'], '')
  };
}

export function parseNativeSimulatorPredictionJson(rawText: string): NativeSimulatorPrediction | null {
  const parsed: JsonMap | null = readJsonMap(rawText);
  if (!parsed) {
    return null;
  }
  const pointValues: JsonValue[] = readArrayValue(parsed['points']);
  const points: NativeScenePoint[] = [];
  pointValues.forEach((value: JsonValue) => {
    const pointObject: JsonMap | null = readObjectValue(value);
    if (!pointObject) {
      return;
    }
    points.push({
      x: readNumberValue(pointObject, 'x', 0),
      y: readNumberValue(pointObject, 'y', 0)
    });
  });
  return {
    status: readStringValue(parsed, 'status', 'unknown'),
    suppressed: readBooleanValue(parsed, 'suppressed', false),
    cpuBusyRatio: readNumberValue(parsed, 'cpuBusyRatio', 0),
    points
  };
}

export function parseNativePdfPageCountResultJson(rawText: string): NativePdfPageCountResult | null {
  const parsed: JsonMap | null = readJsonMap(rawText);
  if (!parsed) {
    return null;
  }
  const status: string = readStringValue(parsed, 'status', '');
  if (
    status !== 'ok' &&
    status !== 'invalid-args' &&
    status !== 'file-not-found' &&
    status !== 'read-failed' &&
    status !== 'invalid-pdf' &&
    status !== 'page-count-unavailable'
  ) {
    return null;
  }
  const result: NativePdfPageCountResult = {
    status: status as NativePdfPageCountStatus
  };
  if (parsed['pageCount'] !== undefined) {
    result.pageCount = Math.trunc(readNumberValue(parsed, 'pageCount', 0));
  }
  const detail: string = readStringValue(parsed, 'detail', '');
  if (detail.length > 0) {
    result.detail = detail;
  }
  return result;
}

export class NativeNoteEngine {
  createEngine(config: EngineConfig): string {
    return nativeBridge.createEngine(JSON.stringify(config));
  }

  openDocument(engineId: string, documentId: string, packagePath: string, config: NativeOpenDocumentConfig): boolean {
    return nativeBridge.openDocument(engineId, documentId, packagePath, JSON.stringify(config));
  }

  attachXComponent(engineId: string, xComponentId: string, surfaceId: string): boolean {
    return nativeBridge.attachXComponent(engineId, xComponentId, surfaceId);
  }

  resize(engineId: string, width: number, height: number, density: number): boolean {
    return nativeBridge.resize(engineId, width, height, density);
  }

  saveCheckpoint(engineId: string, documentId: string): boolean {
    return nativeBridge.saveCheckpoint(engineId, documentId);
  }

  readPdfPageCount(pdfPath: string): NativePdfPageCountResult | null {
    const bridgeMethod: ((pdfPath: string) => string) | undefined = nativeBridge.readPdfPageCount;
    if (bridgeMethod === undefined) {
      return null;
    }
    try {
      const rawText: string = String(bridgeMethod(pdfPath) ?? '');
      return parseNativePdfPageCountResultJson(rawText);
    } catch (_) {
      return null;
    }
  }

  requestPreviewRender(
    engineId: string,
    documentId: string,
    pageIndex: number,
    width: number,
    height: number
  ): NativePreviewPayload | null {
    const rawText: string = nativeBridge.requestPreviewRender(engineId, documentId, pageIndex, width, height);
    const parsed: JsonMap | null = readJsonMap(rawText);
    if (!parsed) {
      return null;
    }
    if (typeof parsed['previewSchemaVersion'] === 'number' || typeof parsed['targetMode'] === 'string') {
      return parsePreviewPayload(parsed, pageIndex);
    }
    return buildStatsFallbackPreview(parsed, pageIndex);
  }

  exportSceneSnapshot(engineId: string, documentId: string): NativeSceneSnapshot | null {
    const rawText: string = nativeBridge.exportSceneSnapshot(engineId, documentId);
    const parsed: JsonMap | null = readJsonMap(rawText);
    if (!parsed) {
      return null;
    }
    return parseSceneSnapshot(parsed);
  }

  setActivePage(engineId: string, pageId: string): boolean {
    return nativeBridge.setActivePage(engineId, pageId);
  }

  insertPage(engineId: string, afterPageId: string, pageConfig: NativePageContract): boolean {
    return nativeBridge.insertPage(engineId, afterPageId, JSON.stringify(pageConfig));
  }

  deletePage(engineId: string, pageId: string): boolean {
    return nativeBridge.deletePage(engineId, pageId);
  }

  setTool(engineId: string, tool: ToolType): boolean {
    return nativeBridge.setTool(engineId, tool);
  }

  setFingerWritingEnabled(engineId: string, enabled: boolean): boolean {
    return nativeBridge.setFingerWritingEnabled(engineId, enabled);
  }

  injectSimulatorFingerEvent(
    engineId: string,
    action: string,
    pageXRatio: number,
    pageYRatio: number,
    pointerCount: number
  ): boolean {
    return nativeBridge.injectSimulatorFingerEvent(engineId, action, pageXRatio, pageYRatio, pointerCount);
  }

  getSimulatorPrediction(engineId: string): NativeSimulatorPrediction | null {
    const rawText: string = nativeBridge.getSimulatorPrediction(engineId);
    if (!rawText) {
      return null;
    }
    return parseNativeSimulatorPredictionJson(rawText);
  }

  setBackend(engineId: string, backend: RenderBackend): boolean {
    return nativeBridge.setBackend(engineId, backend);
  }

  setDocumentMode(engineId: string, mode: DocumentMode): boolean {
    return nativeBridge.setDocumentMode(engineId, mode);
  }

  setBrushColor(engineId: string, colorHex: string): boolean {
    return nativeBridge.setBrushColor(engineId, colorHex);
  }

  setBrushWidth(engineId: string, width: number): boolean {
    return nativeBridge.setBrushWidth(engineId, width);
  }

  undo(engineId: string): boolean {
    return nativeBridge.undo(engineId);
  }

  redo(engineId: string): boolean {
    return nativeBridge.redo(engineId);
  }

  startInputTraceRecording(engineId: string, tracePath: string = ''): boolean {
    return nativeBridge.startInputTraceRecording(engineId, tracePath);
  }

  stopInputTraceRecording(engineId: string): TraceActionResult | null {
    const rawText: string = nativeBridge.stopInputTraceRecording(engineId);
    return parseTraceActionResultJson(rawText);
  }

  replayInputTrace(engineId: string, tracePath: string = ''): TraceActionResult | null {
    const rawText: string = nativeBridge.replayInputTrace(engineId, tracePath);
    return parseTraceActionResultJson(rawText);
  }

  disposeDocument(engineId: string, documentId: string): boolean {
    return nativeBridge.disposeDocument(engineId, documentId);
  }

  disposeEngine(engineId: string): boolean {
    return nativeBridge.disposeEngine(engineId);
  }

  getDebugState(engineId: string): NativeDebugState | null {
    const rawText: string = nativeBridge.getDebugState(engineId);
    if (!rawText) {
      return null;
    }
    return parseNativeDebugStateJson(rawText);
  }
}
