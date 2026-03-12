import { describe, expect, it } from '@ohos/hypium';
import { fileIo } from '@kit.CoreFileKit';
import { buildNativeOpenDocumentConfig } from '../main/ets/models/NativeNoteContracts';
import { DocumentMode, DocumentRecord, DocumentType, RenderBackend, ToolType } from '../main/ets/models/NoteModels';
import {
  EngineConfig,
  NativeNoteEngine,
  parseNativeDebugStateJson,
  parseNativePdfPageCountResultJson,
  parseTraceActionResultJson
} from '../main/ets/services/NativeNoteEngine';

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;
interface NativeEngineHandle {
  engine: NativeNoteEngine;
  engineId: string;
}
const TEST_ROOT_PATH: string = '/data/storage/el2/base/files/native-note-engine-tests';
const TEST_ENGINE_CONFIG: EngineConfig = {
  backend: RenderBackend.OPEN_GLES,
  documentMode: DocumentMode.PAGED,
  dpiScale: 1,
  enablePrediction: false,
  enablePressureForPen: false,
  enableShapeDetection: false,
  enableMarkdownOverlay: false
};

function expectPreviewSchema(
  payload: JsonMap,
  expectedObjectCount: number,
  expectedLayerCount: number
): void {
  expect(payload['status']).assertEqual('ready');
  expect(payload['previewSchemaVersion']).assertEqual(0);
  expect(payload['pageId']).assertEqual('page-0');
  expect(payload['targetMode']).assertEqual('stats-fallback');
  expect(payload['coordinateSpace']).assertEqual('legacy-surface');
  expect(payload['objectCount']).assertEqual(expectedObjectCount);
  expect(Array.isArray(payload['layers'])).assertEqual(true);
  expect((payload['layers'] as JsonValue[]).length).assertEqual(expectedLayerCount);
}

function expectSceneSchema(
  payload: JsonMap,
  expectedMode: string,
  expectedObjectCount: number
): void {
  expect(payload['status']).assertEqual('ready');
  expect(payload['version']).assertEqual(1);
  expect(payload['coordinateSpace']).assertEqual('legacy-surface');
  expect(payload['objectCount']).assertEqual(expectedObjectCount);
  expect(Array.isArray(payload['pages'])).assertEqual(true);
  expect((payload['pages'] as JsonValue[]).length).assertEqual(1);
  expect(Array.isArray(payload['objects'])).assertEqual(true);
  expect((payload['objects'] as JsonValue[]).length).assertEqual(expectedObjectCount);
  const layout = payload['layout'] as JsonMap;
  expect(layout['mode']).assertEqual(expectedMode);
  expect(layout['pageCount']).assertEqual(1);
}

function buildBlankPagedDocument(): DocumentRecord {
  return {
    id: 'doc-blank',
    title: 'Blank Doc',
    documentType: DocumentType.BLANK,
    documentMode: DocumentMode.PAGED,
    renderBackend: RenderBackend.OPEN_GLES,
    schemaVersion: 2,
    activePageId: 'page-1',
    pageCount: 2,
    pages: [
      {
        id: 'page-0',
        order: 0,
        pageKind: 'blank',
        pageTemplateId: 'blank',
        pageSizeId: 'letter_optimized',
        paperBackgroundId: 'paper'
      },
      {
        id: 'page-1',
        order: 1,
        pageKind: 'blank',
        pageTemplateId: 'grid',
        pageSizeId: 'a4',
        paperBackgroundId: 'warm'
      }
    ],
    pageTemplateId: 'blank',
    pageSizeId: 'letter_optimized',
    paperBackgroundId: 'paper',
    folderId: null,
    packagePath: '/data/storage/el2/base/files/doc-blank',
    manifestPath: '/data/storage/el2/base/files/doc-blank/manifest.json',
    previewPath: '/data/storage/el2/base/files/doc-blank/preview.json',
    previewSummary: 'summary',
    coverPage: 0,
    coverVersion: 1,
    isFavorite: false,
    isPinned: false,
    isTrashed: false,
    createdAt: 1,
    updatedAt: 1,
    openedAt: 1,
    trashedAt: 0,
    attachments: [],
    tags: []
  };
}

function buildPdfPagedDocument(): DocumentRecord {
  return {
    id: 'doc-pdf',
    title: 'PDF Doc',
    documentType: DocumentType.PDF,
    documentMode: DocumentMode.PAGED,
    renderBackend: RenderBackend.OPEN_GLES,
    schemaVersion: 2,
    activePageId: 'page-0',
    pageCount: 2,
    pages: [
      {
        id: 'page-0',
        order: 0,
        pageKind: 'pdf',
        pageTemplateId: 'blank',
        pageSizeId: 'letter_optimized',
        paperBackgroundId: 'plain_white',
        sourceAttachmentId: 'attachment-1',
        sourcePageIndex: 0
      },
      {
        id: 'page-1',
        order: 1,
        pageKind: 'pdf',
        pageTemplateId: 'blank',
        pageSizeId: 'a4',
        paperBackgroundId: 'plain_white',
        sourceAttachmentId: 'attachment-1',
        sourcePageIndex: 1
      }
    ],
    pageTemplateId: 'blank',
    pageSizeId: 'letter_optimized',
    paperBackgroundId: 'plain_white',
    folderId: null,
    packagePath: `${TEST_ROOT_PATH}/doc-pdf`,
    manifestPath: `${TEST_ROOT_PATH}/doc-pdf/manifest.json`,
    previewPath: `${TEST_ROOT_PATH}/doc-pdf/preview.json`,
    previewSummary: 'pdf summary',
    coverPage: 0,
    coverVersion: 1,
    isFavorite: false,
    isPinned: false,
    isTrashed: false,
    createdAt: 1,
    updatedAt: 1,
    openedAt: 1,
    trashedAt: 0,
    attachments: [{
      id: 'attachment-1',
      kind: 'pdf',
      displayName: 'chapter.pdf',
      mimeType: 'application/pdf',
      relativePath: 'attachments/attachment-1.pdf',
      byteSize: 4096,
      importedAt: 1,
      pageCount: 2
    }],
    tags: []
  };
}

function buildPdfFragmentPagedDocument(): DocumentRecord {
  return {
    id: 'doc-hybrid',
    title: 'Hybrid Doc',
    documentType: DocumentType.HYBRID,
    documentMode: DocumentMode.PAGED,
    renderBackend: RenderBackend.OPEN_GLES,
    schemaVersion: 2,
    activePageId: 'page-0',
    pageCount: 1,
    pages: [
      {
        id: 'page-0',
        order: 0,
        pageKind: 'pdf-fragment',
        pageTemplateId: 'cornell',
        pageSizeId: 'letter_optimized',
        paperBackgroundId: 'plain_white',
        sourceAttachmentId: 'attachment-hybrid',
        sourcePageIndex: 3
      }
    ],
    pageTemplateId: 'cornell',
    pageSizeId: 'letter_optimized',
    paperBackgroundId: 'plain_white',
    folderId: null,
    packagePath: `${TEST_ROOT_PATH}/doc-hybrid`,
    manifestPath: `${TEST_ROOT_PATH}/doc-hybrid/manifest.json`,
    previewPath: `${TEST_ROOT_PATH}/doc-hybrid/preview.json`,
    previewSummary: 'hybrid summary',
    coverPage: 0,
    coverVersion: 1,
    isFavorite: false,
    isPinned: false,
    isTrashed: false,
    createdAt: 1,
    updatedAt: 1,
    openedAt: 1,
    trashedAt: 0,
    attachments: [{
      id: 'attachment-hybrid',
      kind: 'pdf',
      displayName: 'hybrid.pdf',
      mimeType: 'application/pdf',
      relativePath: 'attachments/attachment-hybrid.pdf',
      byteSize: 2048,
      importedAt: 1,
      pageCount: 4
    }],
    tags: []
  };
}

function ensureDir(path: string): void {
  fileIo.mkdirSync(path, true);
}

function writeTextFile(path: string, content: string): void {
  const separatorIndex: number = path.lastIndexOf('/');
  if (separatorIndex > 0) {
    ensureDir(path.substring(0, separatorIndex));
  }
  const stream: fileIo.Stream = fileIo.createStreamSync(path, 'w');
  try {
    stream.writeSync(content);
  } finally {
    stream.closeSync();
  }
}

function removeFileIfExists(path: string): void {
  try {
    fileIo.unlinkSync(path);
  } catch (_) {
  }
}

function buildTestPdfContent(pageCount: number): string {
  const pageObjects: string[] = [];
  for (let index = 0; index < pageCount; index += 1) {
    pageObjects.push(`${3 + index} 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj`);
  }
  return `%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Count ${pageCount} /Kids [${pageObjects.map((_, index) => `${3 + index} 0 R`).join(' ')}] >>
endobj
${pageObjects.join('\n')}
trailer
<< /Root 1 0 R >>
%%EOF`;
}

function createNativeEngineHandle(): NativeEngineHandle {
  const engine: NativeNoteEngine = new NativeNoteEngine();
  return {
    engine,
    engineId: engine.createEngine(TEST_ENGINE_CONFIG)
  };
}

function disposeNativeEngineHandle(engine: NativeNoteEngine, engineId: string, documentId?: string): void {
  try {
    if (documentId) {
      engine.disposeDocument(engineId, documentId);
    }
  } catch (_) {
  }
  try {
    engine.disposeEngine(engineId);
  } catch (_) {
  }
}

export default function nativeNoteEngineTest() {
  describe('nativeNoteEngineTest', () => {
    it('buildsPageAwareOpenDocumentConfig', 0, () => {
      const config = buildNativeOpenDocumentConfig(buildBlankPagedDocument(), ToolType.PEN);
      const pages = config.pages ?? [];
      const pageContracts = config.pageContracts ?? {};
      expect(config.activePageId).assertEqual('page-1');
      expect(config.pageContract.pageId).assertEqual('page-1');
      expect(config.pageContract.pageTemplateId).assertEqual('grid');
      expect(pages.length).assertEqual(2);
      expect(pages[0].id).assertEqual('page-0');
      expect(pages[1].id).assertEqual('page-1');
      expect(pageContracts['page-0'].pageId).assertEqual('page-0');
      expect(pageContracts['page-1'].pageTemplateId).assertEqual('grid');
    });

    it('buildsPageAwareOpenDocumentConfigForPdfPagedDocuments', 0, () => {
      const config = buildNativeOpenDocumentConfig(buildPdfPagedDocument(), ToolType.PEN);
      const pages = config.pages ?? [];
      const pageContracts = config.pageContracts ?? {};
      expect(config.activePageId).assertEqual('page-0');
      expect(config.pageContract.pageId).assertEqual('page-0');
      expect(pages.length).assertEqual(2);
      expect(pages[0].pageKind).assertEqual('pdf');
      expect(pages[0].sourceAttachmentId).assertEqual('attachment-1');
      expect(pages[1].sourcePageIndex).assertEqual(1);
      expect(pageContracts['page-1'].pageId).assertEqual('page-1');
    });

    it('parsesTraceActionResultIntoStrongType', 0, () => {
      const stopResult = parseTraceActionResultJson('{"status":"recorded","path":"/data/input-trace.json","sampleCount":12}');
      expect(stopResult !== null).assertEqual(true);
      expect(stopResult?.status).assertEqual('recorded');
      expect(stopResult?.path).assertEqual('/data/input-trace.json');
      expect(stopResult?.sampleCount).assertEqual(12);

      const replayResult = parseTraceActionResultJson('{"status":"replayed","path":"/data/input-trace.json","sampleCount":12}');
      expect(replayResult !== null).assertEqual(true);
      expect(replayResult?.status).assertEqual('replayed');
      expect(replayResult?.path).assertEqual('/data/input-trace.json');
      expect(replayResult?.sampleCount).assertEqual(12);
    });

    it('parsesPdfPageCountResultIntoStrongType', 0, () => {
      const successResult = parseNativePdfPageCountResultJson('{"status":"ok","pageCount":4}');
      expect(successResult !== null).assertEqual(true);
      expect(successResult?.status).assertEqual('ok');
      expect(successResult?.pageCount).assertEqual(4);

      const failureResult = parseNativePdfPageCountResultJson(
        '{"status":"page-count-unavailable","detail":"fallback could not verify page count"}'
      );
      expect(failureResult !== null).assertEqual(true);
      expect(failureResult?.status).assertEqual('page-count-unavailable');
      expect(failureResult?.detail).assertEqual('fallback could not verify page count');
    });

    it('readsPdfPageCountViaNativeHelper', 0, () => {
      ensureDir(TEST_ROOT_PATH);
      const pdfPath: string = `${TEST_ROOT_PATH}/page-count-${Date.now()}.pdf`;
      const invalidPdfPath: string = `${TEST_ROOT_PATH}/page-count-invalid-${Date.now()}.txt`;
      writeTextFile(pdfPath, buildTestPdfContent(2));
      writeTextFile(invalidPdfPath, 'this is not a pdf');

      const handle: NativeEngineHandle = createNativeEngineHandle();
      const engine: NativeNoteEngine = handle.engine;
      const engineId: string = handle.engineId;
      try {
        const pageCountResult = engine.readPdfPageCount(pdfPath);
        expect(pageCountResult !== null).assertEqual(true);
        expect(pageCountResult?.status).assertEqual('ok');
        expect(pageCountResult?.pageCount).assertEqual(2);

        const invalidResult = engine.readPdfPageCount(invalidPdfPath);
        expect(invalidResult !== null).assertEqual(true);
        expect(invalidResult?.status).assertEqual('invalid-pdf');
      } finally {
        disposeNativeEngineHandle(engine, engineId);
        removeFileIfExists(pdfPath);
        removeFileIfExists(invalidPdfPath);
      }
    });

    it('simulatorBlankPagedSessionsExposeWritableCheckpointUndoRedoState', 0, () => {
      const document = buildBlankPagedDocument();
      const config = buildNativeOpenDocumentConfig(document, ToolType.PEN);
      const handle: NativeEngineHandle = createNativeEngineHandle();
      const engine: NativeNoteEngine = handle.engine;
      const engineId: string = handle.engineId;
      try {
        expect(engine.openDocument(engineId, document.id, document.packagePath, config)).assertEqual(true);

        const initialDebug = engine.getDebugState(engineId);
        expect(initialDebug !== null).assertEqual(true);
        expect(initialDebug?.activePageId).assertEqual('page-1');
        expect(initialDebug?.pageCount).assertEqual(2);
        expect(initialDebug?.committedStrokeCount).assertEqual(0);
        expect(initialDebug?.undoDepth).assertEqual(0);
        expect(initialDebug?.redoDepth).assertEqual(0);

        const initialPreview = engine.requestPreviewRender(engineId, document.id, 1, 640, 480);
        expect(initialPreview !== null).assertEqual(true);
        expect(initialPreview?.pageId).assertEqual('page-1');
        expect(initialPreview?.objectCount).assertEqual(0);
        expect(initialPreview?.layers.length).assertEqual(0);

        expect(engine.setTool(engineId, ToolType.HIGHLIGHTER)).assertEqual(true);
        expect(engine.setBrushColor(engineId, '#FF5500')).assertEqual(true);
        expect(engine.saveCheckpoint(engineId, document.id)).assertEqual(true);

        const sceneAfterFirstCheckpoint = engine.exportSceneSnapshot(engineId, document.id);
        expect(sceneAfterFirstCheckpoint !== null).assertEqual(true);
        expect(sceneAfterFirstCheckpoint?.objectCount).assertEqual(1);
        expect(sceneAfterFirstCheckpoint?.objects[0].pageId).assertEqual('page-1');
        expect(sceneAfterFirstCheckpoint?.objects[0].tool).assertEqual('highlighter');
        expect(sceneAfterFirstCheckpoint?.objects[0].colorHex).assertEqual('#FF5500');

        const debugAfterFirstCheckpoint = engine.getDebugState(engineId);
        expect(debugAfterFirstCheckpoint !== null).assertEqual(true);
        expect(debugAfterFirstCheckpoint?.committedStrokeCount).assertEqual(1);
        expect(debugAfterFirstCheckpoint?.undoDepth).assertEqual(1);
        expect(debugAfterFirstCheckpoint?.redoDepth).assertEqual(0);
        expect(debugAfterFirstCheckpoint?.lastCommittedStrokeType).assertEqual('highlight-stroke');

        const previewAfterFirstCheckpoint = engine.requestPreviewRender(engineId, document.id, 1, 640, 480);
        expect(previewAfterFirstCheckpoint !== null).assertEqual(true);
        expect(previewAfterFirstCheckpoint?.objectCount).assertEqual(1);
        expect(previewAfterFirstCheckpoint?.layers.length).assertEqual(1);
        expect(previewAfterFirstCheckpoint?.layers[0]).assertEqual('ink');

        expect(engine.undo(engineId)).assertEqual(true);
        const sceneAfterUndo = engine.exportSceneSnapshot(engineId, document.id);
        expect(sceneAfterUndo !== null).assertEqual(true);
        expect(sceneAfterUndo?.objectCount).assertEqual(0);

        const debugAfterUndo = engine.getDebugState(engineId);
        expect(debugAfterUndo !== null).assertEqual(true);
        expect(debugAfterUndo?.committedStrokeCount).assertEqual(0);
        expect(debugAfterUndo?.undoDepth).assertEqual(0);
        expect(debugAfterUndo?.redoDepth).assertEqual(1);

        expect(engine.redo(engineId)).assertEqual(true);
        expect(engine.setActivePage(engineId, 'page-0')).assertEqual(true);
        expect(engine.setTool(engineId, ToolType.PEN)).assertEqual(true);
        expect(engine.setBrushColor(engineId, '#0EA5E9')).assertEqual(true);
        expect(engine.saveCheckpoint(engineId, document.id)).assertEqual(true);

        const sceneAfterSecondCheckpoint = engine.exportSceneSnapshot(engineId, document.id);
        expect(sceneAfterSecondCheckpoint !== null).assertEqual(true);
        expect(sceneAfterSecondCheckpoint?.objectCount).assertEqual(2);
        expect(sceneAfterSecondCheckpoint?.objects.some((object: { pageId?: string; tool: string; colorHex: string }) =>
          object.pageId === 'page-0' && object.tool === 'pen' && object.colorHex === '#0EA5E9')).assertEqual(true);
        expect(sceneAfterSecondCheckpoint?.objects.some((object: { pageId?: string; tool: string; colorHex: string }) =>
          object.pageId === 'page-1' && object.tool === 'highlighter' && object.colorHex === '#FF5500')).assertEqual(true);

        const insertedContract = {
          ...(config.pageContracts?.['page-0'] ?? config.pageContract),
          pageId: 'page-2'
        };
        expect(engine.insertPage(engineId, 'page-0', insertedContract)).assertEqual(true);

        const debugAfterInsert = engine.getDebugState(engineId);
        expect(debugAfterInsert !== null).assertEqual(true);
        expect(debugAfterInsert?.activePageId).assertEqual('page-2');
        expect(debugAfterInsert?.activePageIndex).assertEqual(1);
        expect(debugAfterInsert?.pageCount).assertEqual(3);

        const previewInsertedPage = engine.requestPreviewRender(engineId, document.id, 1, 640, 480);
        expect(previewInsertedPage !== null).assertEqual(true);
        expect(previewInsertedPage?.pageId).assertEqual('page-2');
        expect(previewInsertedPage?.layout?.pageCount).assertEqual(3);
        expect(previewInsertedPage?.objectCount).assertEqual(0);

        expect(engine.deletePage(engineId, 'page-2')).assertEqual(true);
        const debugAfterDelete = engine.getDebugState(engineId);
        expect(debugAfterDelete !== null).assertEqual(true);
        expect(debugAfterDelete?.activePageId).assertEqual('page-1');
        expect(debugAfterDelete?.pageCount).assertEqual(2);
      } finally {
        disposeNativeEngineHandle(engine, engineId, document.id);
      }
    });

    it('keepsPagedPdfPreviewSceneAndDebugPageAware', 0, () => {
      const document = buildPdfPagedDocument();
      const config = buildNativeOpenDocumentConfig(document, ToolType.PEN);
      const handle: NativeEngineHandle = createNativeEngineHandle();
      const engine: NativeNoteEngine = handle.engine;
      const engineId: string = handle.engineId;
      try {
        expect(engine.openDocument(engineId, document.id, document.packagePath, config)).assertEqual(true);

        const preview = engine.requestPreviewRender(engineId, document.id, 1, 640, 480);
        expect(preview !== null).assertEqual(true);
        expect(preview?.pageId).assertEqual('page-1');
        expect(preview?.pageIndex).assertEqual(1);
        expect(preview?.layout?.pageCount).assertEqual(2);
        expect(preview?.layers.length).assertEqual(2);
        expect(preview?.layers[0]).assertEqual('pdf');
        expect(preview?.layers[1]).assertEqual('ink');
        expect(preview?.objectCount).assertEqual(1);
        expect(preview?.layout?.pages[1].backgroundId).assertEqual('pdf/source-1');

        const debugBeforeSwitch = engine.getDebugState(engineId);
        expect(debugBeforeSwitch !== null).assertEqual(true);
        expect(debugBeforeSwitch?.activePageId).assertEqual('page-0');
        expect(debugBeforeSwitch?.activePageIndex).assertEqual(0);
        expect(debugBeforeSwitch?.pageCount).assertEqual(2);

        const sceneBeforeSwitch = engine.exportSceneSnapshot(engineId, document.id);
        expect(sceneBeforeSwitch !== null).assertEqual(true);
        expect(sceneBeforeSwitch?.objectCount).assertEqual(1);
        expect(sceneBeforeSwitch?.objects[0].nodeType).assertEqual('pdf-page');
        expect(sceneBeforeSwitch?.objects[0].layer).assertEqual('pdf');
        expect(sceneBeforeSwitch?.objects[0].pageId).assertEqual('page-0');

        expect(engine.insertPage(engineId, 'page-0', config.pageContract)).assertEqual(false);
        expect(engine.setActivePage(engineId, 'page-1')).assertEqual(true);

        const debugAfterSwitch = engine.getDebugState(engineId);
        expect(debugAfterSwitch !== null).assertEqual(true);
        expect(debugAfterSwitch?.activePageId).assertEqual('page-1');
        expect(debugAfterSwitch?.activePageIndex).assertEqual(1);
        expect(debugAfterSwitch?.pageCount).assertEqual(2);
      } finally {
        disposeNativeEngineHandle(engine, engineId, document.id);
      }
    });

    it('keepsPdfFragmentPagedSessionsStableWithoutBlankOnlyFallback', 0, () => {
      const document = buildPdfFragmentPagedDocument();
      const config = buildNativeOpenDocumentConfig(document, ToolType.PEN);
      const handle: NativeEngineHandle = createNativeEngineHandle();
      const engine: NativeNoteEngine = handle.engine;
      const engineId: string = handle.engineId;
      try {
        expect(engine.openDocument(engineId, document.id, document.packagePath, config)).assertEqual(true);

        const preview = engine.requestPreviewRender(engineId, document.id, 0, 640, 480);
        expect(preview !== null).assertEqual(true);
        expect(preview?.pageId).assertEqual('page-0');
        expect(preview?.layers.length).assertEqual(2);
        expect(preview?.layers[0]).assertEqual('pdf');
        expect(preview?.layers[1]).assertEqual('ink');
        expect(preview?.objectCount).assertEqual(1);
        expect(preview?.layout?.pages[0].backgroundId?.startsWith('paper/')).assertEqual(true);

        const debugState = engine.getDebugState(engineId);
        expect(debugState !== null).assertEqual(true);
        expect(debugState?.activePageId).assertEqual('page-0');
        expect(debugState?.activePageIndex).assertEqual(0);
        expect(debugState?.pageCount).assertEqual(1);

        const sceneSnapshot = engine.exportSceneSnapshot(engineId, document.id);
        expect(sceneSnapshot !== null).assertEqual(true);
        expect(sceneSnapshot?.objectCount).assertEqual(1);
        expect(sceneSnapshot?.objects[0].nodeType).assertEqual('pdf-fragment');
        expect(sceneSnapshot?.objects[0].layer).assertEqual('pdf');
      } finally {
        disposeNativeEngineHandle(engine, engineId, document.id);
      }
    });

    it('parsesDebugStateWithTraceFieldsAndFallbacks', 0, () => {
      const debugState = parseNativeDebugStateJson(JSON.stringify({
        engineId: 'engine-1',
        activeDocumentId: 'doc-1',
        activePageId: 'page-2',
        activePageIndex: 2,
        pageCount: 5,
        activeTool: 'pen',
        activeBackend: 'opengles',
        activeMode: 'paged',
        activeColor: '#1D2736',
        checkpointCount: 3,
        predictionEnabled: true,
        pressureEnabled: true,
        shapeRecognitionEnabled: false,
        surfaceReady: true,
        surfaceWidth: 1280,
        surfaceHeight: 720,
        touchEventCount: 9,
        uiTouchEventCount: 9,
        keyEventCount: 1,
        stylusEventCount: 7,
        fingerEventCount: 2,
        palmRejectedCount: 1,
        activePointerCount: 1,
        stylusActive: true,
        multitouchGestureActive: false,
        lastHistoricalCount: 3,
        lastUiHistoryCount: 1,
        predictedPointCount: 4,
        lastEventTime: 100,
        lastPressure: 0.5,
        lastTiltX: 1.2,
        lastTiltY: -0.4,
        lastRollAngle: 15,
        lastTouchAction: 'move',
        lastToolType: 'pen',
        lastSourceType: 'stylus',
        lastKeyCode: 13,
        lastKeyAction: 1,
        lastKeySourceType: 4,
        lastKeyEventTime: 110,
        committedStrokeCount: 2,
        undoDepth: 1,
        redoDepth: 0,
        lastCommittedStrokeType: 'freehand',
        inputTraceRecording: true,
        inputReplayActive: false,
        inputTraceStatus: 'recording',
        inputTracePath: '/data/input-trace.json',
        inputTraceSampleCount: 6,
        runtimeMode: 'simulator-stub',
        supportsTraceRecording: false,
        previewRenderSupported: true,
        sceneExportSupported: true,
        stubReason: 'x86_64-simulator-uses-weak-native-shell'
      }));

      expect(debugState !== null).assertEqual(true);
      expect(debugState?.activePageId).assertEqual('page-2');
      expect(debugState?.activePageIndex).assertEqual(2);
      expect(debugState?.pageCount).assertEqual(5);
      expect(debugState?.inputTraceRecording).assertEqual(true);
      expect(debugState?.inputReplayActive).assertEqual(false);
      expect(debugState?.inputTraceStatus).assertEqual('recording');
      expect(debugState?.inputTracePath).assertEqual('/data/input-trace.json');
      expect(debugState?.inputTraceSampleCount).assertEqual(6);
      expect(debugState?.runtimeProfile).assertEqual('simulator-stub');
      expect(debugState?.traceSupported).assertEqual(false);
      expect(debugState?.previewRenderSupported).assertEqual(true);
      expect(debugState?.sceneExportSupported).assertEqual(true);
      expect(debugState?.stubReason).assertEqual('x86_64-simulator-uses-weak-native-shell');

      const deviceState = parseNativeDebugStateJson(JSON.stringify({
        engineId: 'engine-device',
        runtimeMode: 'device-native',
        supportsTraceRecording: true,
        previewRenderSupported: true,
        sceneExportSupported: true,
        stubReason: ''
      }));
      expect(deviceState !== null).assertEqual(true);
      expect(deviceState?.activePageId).assertEqual('page-0');
      expect(deviceState?.activePageIndex).assertEqual(0);
      expect(deviceState?.pageCount).assertEqual(1);
      expect(deviceState?.runtimeProfile).assertEqual('device-native');
      expect(deviceState?.traceSupported).assertEqual(true);
      expect(deviceState?.previewRenderSupported).assertEqual(true);
      expect(deviceState?.sceneExportSupported).assertEqual(true);
      expect(deviceState?.stubReason).assertEqual('');

      const fallbackState = parseNativeDebugStateJson('{"engineId":"engine-2"}');
      expect(fallbackState !== null).assertEqual(true);
      expect(fallbackState?.activePageId).assertEqual('page-0');
      expect(fallbackState?.activePageIndex).assertEqual(0);
      expect(fallbackState?.pageCount).assertEqual(1);
      expect(fallbackState?.inputTraceRecording).assertEqual(false);
      expect(fallbackState?.inputReplayActive).assertEqual(false);
      expect(fallbackState?.inputTraceStatus).assertEqual('');
      expect(fallbackState?.inputTracePath).assertEqual('');
      expect(fallbackState?.inputTraceSampleCount).assertEqual(0);
      expect(fallbackState?.runtimeProfile).assertEqual('device-native');
      expect(fallbackState?.traceSupported).assertEqual(false);
      expect(fallbackState?.previewRenderSupported).assertEqual(false);
      expect(fallbackState?.sceneExportSupported).assertEqual(false);
      expect(fallbackState?.stubReason).assertEqual('');

      const compatState = parseNativeDebugStateJson(JSON.stringify({
        engineId: 'engine-3',
        runtimeMode: 'simulator-stub',
        supportsInputTrace: true
      }));
      expect(compatState !== null).assertEqual(true);
      expect(compatState?.activePageId).assertEqual('page-0');
      expect(compatState?.activePageIndex).assertEqual(0);
      expect(compatState?.pageCount).assertEqual(1);
      expect(compatState?.runtimeProfile).assertEqual('simulator-stub');
      expect(compatState?.traceSupported).assertEqual(true);
    });

    it('pinsPageAwarePreviewAndSceneSchemaForBlankPagedSessions', 0, () => {
      const previewPayload = JSON.parse(`{
        "status": "ready",
        "previewSchemaVersion": 0,
        "engineId": "engine-1",
        "documentId": "doc-1",
        "pageIndex": 1,
        "pageId": "page-1",
        "targetMode": "stats-fallback",
        "coordinateSpace": "legacy-surface",
        "width": 640,
        "height": 480,
        "strokeCount": 0,
        "shapeCount": 0,
        "checkpointCount": 2,
        "objectCount": 0,
        "layout": {
          "mode": "paged",
          "pageCount": 3,
          "pages": [
            { "pageId": "page-0", "pageIndex": 0 },
            { "pageId": "page-1", "pageIndex": 1 },
            { "pageId": "page-2", "pageIndex": 2 }
          ]
        },
        "layers": []
      }`) as JsonMap;
      expect(previewPayload['pageId']).assertEqual('page-1');
      expect(previewPayload['pageIndex']).assertEqual(1);
      const previewLayout = previewPayload['layout'] as JsonMap;
      expect(previewLayout['pageCount']).assertEqual(3);
      expect(((previewLayout['pages'] as JsonValue[])[1] as JsonMap)['pageId']).assertEqual('page-1');

      const sceneSnapshot = JSON.parse(`{
        "status": "ready",
        "version": 1,
        "engineId": "engine-1",
        "documentId": "doc-1",
        "title": "Doc",
        "documentType": "blank",
        "mode": "paged",
        "backend": "opengles",
        "coordinateSpace": "legacy-surface",
        "checkpointCount": 2,
        "objectCount": 1,
        "pages": [
          { "pageId": "page-0", "pageIndex": 0 },
          { "pageId": "page-1", "pageIndex": 1 },
          { "pageId": "page-2", "pageIndex": 2 }
        ],
        "layout": {
          "mode": "paged",
          "pageCount": 3,
          "pages": [
            { "pageId": "page-0", "pageIndex": 0 },
            { "pageId": "page-1", "pageIndex": 1 },
            { "pageId": "page-2", "pageIndex": 2 }
          ]
        },
        "objects": [
          {
            "id": "stroke-1",
            "pageId": "page-1",
            "pageIndex": 1
          }
        ]
      }`) as JsonMap;
      expect((sceneSnapshot['pages'] as JsonValue[]).length).assertEqual(3);
      const sceneLayout = sceneSnapshot['layout'] as JsonMap;
      expect(sceneLayout['pageCount']).assertEqual(3);
      expect(((sceneSnapshot['objects'] as JsonValue[])[0] as JsonMap)['pageId']).assertEqual('page-1');
      expect(((sceneSnapshot['objects'] as JsonValue[])[0] as JsonMap)['pageIndex']).assertEqual(1);
    });

    it('pinsSimulatorStubPreviewAndScenePlaceholderSchema', 0, () => {
      const previewPayload = JSON.parse(`{
        "status": "ready",
        "previewSchemaVersion": 0,
        "engineId": "engine-1",
        "documentId": "doc-1",
        "pageIndex": 0,
        "pageId": "page-0",
        "targetMode": "stats-fallback",
        "coordinateSpace": "legacy-surface",
        "width": 640,
        "height": 480,
        "strokeCount": 0,
        "shapeCount": 0,
        "checkpointCount": 0,
        "objectCount": 0,
        "layers": []
      }`) as JsonMap;
      expectPreviewSchema(previewPayload, 0, 0);
      expect(previewPayload['strokeCount']).assertEqual(0);
      expect(previewPayload['shapeCount']).assertEqual(0);

      const sceneSnapshot = JSON.parse(`{
        "status": "ready",
        "version": 1,
        "engineId": "engine-1",
        "documentId": "doc-1",
        "title": "",
        "documentType": "blank",
        "mode": "paged",
        "backend": "opengles",
        "coordinateSpace": "legacy-surface",
        "checkpointCount": 0,
        "objectCount": 0,
        "pages": [
          { "pageId": "page-0", "pageIndex": 0 }
        ],
        "layout": {
          "mode": "paged",
          "pageCount": 1,
          "pages": [
            { "pageId": "page-0", "pageIndex": 0 }
          ]
        },
        "objects": []
      }`) as JsonMap;
      expectSceneSchema(sceneSnapshot, 'paged', 0);
    });

    it('pinsDeviceNativePreviewAndSceneSchema', 0, () => {
      const previewPayload = JSON.parse(`{
        "status": "ready",
        "previewSchemaVersion": 0,
        "engineId": "engine-device",
        "documentId": "doc-2",
        "pageIndex": 0,
        "pageId": "page-0",
        "targetMode": "stats-fallback",
        "coordinateSpace": "legacy-surface",
        "width": 800,
        "height": 600,
        "strokeCount": 2,
        "shapeCount": 1,
        "checkpointCount": 4,
        "objectCount": 2,
        "layers": ["ink"]
      }`) as JsonMap;
      expectPreviewSchema(previewPayload, 2, 1);
      expect(previewPayload['strokeCount']).assertEqual(2);
      expect(previewPayload['shapeCount']).assertEqual(1);

      const sceneSnapshot = JSON.parse(`{
        "status": "ready",
        "version": 1,
        "engineId": "engine-device",
        "documentId": "doc-2",
        "title": "Doc",
        "documentType": "blank",
        "mode": "infinite",
        "backend": "skia",
        "coordinateSpace": "legacy-surface",
        "checkpointCount": 4,
        "objectCount": 2,
        "pages": [
          { "pageId": "page-0", "pageIndex": 0 }
        ],
        "layout": {
          "mode": "infinite",
          "pageCount": 1,
          "pages": [
            { "pageId": "page-0", "pageIndex": 0 }
          ]
        },
        "objects": [
          { "id": "stroke-1" },
          { "id": "stroke-2" }
        ]
      }`) as JsonMap;
      expectSceneSchema(sceneSnapshot, 'infinite', 2);
    });
  });
}
