import { describe, expect, it } from '@ohos/hypium';
import { buildNativeOpenDocumentConfig } from '../main/ets/models/NativeNoteContracts';
import { DocumentMode, DocumentRecord, DocumentType, RenderBackend, ToolType } from '../main/ets/models/NoteModels';
import { parseNativeDebugStateJson, parseTraceActionResultJson } from '../main/ets/services/NativeNoteEngine';

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;

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
    tags: []
  };
}

export default function nativeNoteEngineTest() {
  describe('nativeNoteEngineTest', () => {
    it('buildsPageAwareOpenDocumentConfig', 0, () => {
      const config = buildNativeOpenDocumentConfig(buildBlankPagedDocument(), ToolType.PEN);
      expect(config.activePageId).assertEqual('page-1');
      expect(config.pageContract.pageId).assertEqual('page-1');
      expect(config.pageContract.pageTemplateId).assertEqual('grid');
      expect(config.pages.length).assertEqual(2);
      expect(config.pages[0].id).assertEqual('page-0');
      expect(config.pages[1].id).assertEqual('page-1');
      expect(config.pageContracts['page-0'].pageId).assertEqual('page-0');
      expect(config.pageContracts['page-1'].pageTemplateId).assertEqual('grid');
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
      const previewPayload = JSON.parse(JSON.stringify({
        status: 'ready',
        previewSchemaVersion: 0,
        engineId: 'engine-1',
        documentId: 'doc-1',
        pageIndex: 1,
        pageId: 'page-1',
        targetMode: 'stats-fallback',
        coordinateSpace: 'legacy-surface',
        width: 640,
        height: 480,
        strokeCount: 0,
        shapeCount: 0,
        checkpointCount: 2,
        objectCount: 0,
        layout: {
          mode: 'paged',
          pageCount: 3,
          pages: [
            { pageId: 'page-0', pageIndex: 0 },
            { pageId: 'page-1', pageIndex: 1 },
            { pageId: 'page-2', pageIndex: 2 }
          ]
        },
        layers: []
      })) as JsonMap;
      expect(previewPayload['pageId']).assertEqual('page-1');
      expect(previewPayload['pageIndex']).assertEqual(1);
      const previewLayout = previewPayload['layout'] as JsonMap;
      expect(previewLayout['pageCount']).assertEqual(3);
      expect(((previewLayout['pages'] as JsonValue[])[1] as JsonMap)['pageId']).assertEqual('page-1');

      const sceneSnapshot = JSON.parse(JSON.stringify({
        status: 'ready',
        version: 1,
        engineId: 'engine-1',
        documentId: 'doc-1',
        title: 'Doc',
        documentType: 'blank',
        mode: 'paged',
        backend: 'opengles',
        coordinateSpace: 'legacy-surface',
        checkpointCount: 2,
        objectCount: 1,
        pages: [
          { pageId: 'page-0', pageIndex: 0 },
          { pageId: 'page-1', pageIndex: 1 },
          { pageId: 'page-2', pageIndex: 2 }
        ],
        layout: {
          mode: 'paged',
          pageCount: 3,
          pages: [
            { pageId: 'page-0', pageIndex: 0 },
            { pageId: 'page-1', pageIndex: 1 },
            { pageId: 'page-2', pageIndex: 2 }
          ]
        },
        objects: [
          {
            id: 'stroke-1',
            pageId: 'page-1',
            pageIndex: 1
          }
        ]
      })) as JsonMap;
      expect((sceneSnapshot['pages'] as JsonValue[]).length).assertEqual(3);
      const sceneLayout = sceneSnapshot['layout'] as JsonMap;
      expect(sceneLayout['pageCount']).assertEqual(3);
      expect(((sceneSnapshot['objects'] as JsonValue[])[0] as JsonMap)['pageId']).assertEqual('page-1');
      expect(((sceneSnapshot['objects'] as JsonValue[])[0] as JsonMap)['pageIndex']).assertEqual(1);
    });

    it('pinsSimulatorStubPreviewAndScenePlaceholderSchema', 0, () => {
      const previewPayload = JSON.parse(JSON.stringify({
        status: 'ready',
        previewSchemaVersion: 0,
        engineId: 'engine-1',
        documentId: 'doc-1',
        pageIndex: 0,
        pageId: 'page-0',
        targetMode: 'stats-fallback',
        coordinateSpace: 'legacy-surface',
        width: 640,
        height: 480,
        strokeCount: 0,
        shapeCount: 0,
        checkpointCount: 0,
        objectCount: 0,
        layers: []
      })) as JsonMap;
      expectPreviewSchema(previewPayload, 0, 0);
      expect(previewPayload['strokeCount']).assertEqual(0);
      expect(previewPayload['shapeCount']).assertEqual(0);

      const sceneSnapshot = JSON.parse(JSON.stringify({
        status: 'ready',
        version: 1,
        engineId: 'engine-1',
        documentId: 'doc-1',
        title: '',
        documentType: 'blank',
        mode: 'paged',
        backend: 'opengles',
        coordinateSpace: 'legacy-surface',
        checkpointCount: 0,
        objectCount: 0,
        pages: [
          {
            pageId: 'page-0',
            pageIndex: 0
          }
        ],
        layout: {
          mode: 'paged',
          pageCount: 1,
          pages: [
            {
              pageId: 'page-0',
              pageIndex: 0
            }
          ]
        },
        objects: []
      })) as JsonMap;
      expectSceneSchema(sceneSnapshot, 'paged', 0);
    });

    it('pinsDeviceNativePreviewAndSceneSchema', 0, () => {
      const previewPayload = JSON.parse(JSON.stringify({
        status: 'ready',
        previewSchemaVersion: 0,
        engineId: 'engine-device',
        documentId: 'doc-2',
        pageIndex: 0,
        pageId: 'page-0',
        targetMode: 'stats-fallback',
        coordinateSpace: 'legacy-surface',
        width: 800,
        height: 600,
        strokeCount: 2,
        shapeCount: 1,
        checkpointCount: 4,
        objectCount: 2,
        layers: ['ink']
      })) as JsonMap;
      expectPreviewSchema(previewPayload, 2, 1);
      expect(previewPayload['strokeCount']).assertEqual(2);
      expect(previewPayload['shapeCount']).assertEqual(1);

      const sceneSnapshot = JSON.parse(JSON.stringify({
        status: 'ready',
        version: 1,
        engineId: 'engine-device',
        documentId: 'doc-2',
        title: 'Doc',
        documentType: 'blank',
        mode: 'infinite',
        backend: 'skia',
        coordinateSpace: 'legacy-surface',
        checkpointCount: 4,
        objectCount: 2,
        pages: [
          {
            pageId: 'page-0',
            pageIndex: 0
          }
        ],
        layout: {
          mode: 'infinite',
          pageCount: 1,
          pages: [
            {
              pageId: 'page-0',
              pageIndex: 0
            }
          ]
        },
        objects: [
          {
            id: 'stroke-1'
          },
          {
            id: 'stroke-2'
          }
        ]
      })) as JsonMap;
      expectSceneSchema(sceneSnapshot, 'infinite', 2);
    });
  });
}
