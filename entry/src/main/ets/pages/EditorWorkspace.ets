import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import nativeModule from 'libentry.so';
import { PreviewThumbnail } from '../components/PreviewThumbnail';
import {
  buildNativeOpenDocumentConfig,
  buildNativePageContractForEntry,
  buildNativePreviewRequestSize,
  NativePreviewPayload
} from '../models/NativeNoteContracts';
import {
  DOCUMENT_MODE_LABELS,
  DOCUMENT_TYPE_LABELS,
  DocumentMode,
  DocumentPageEntry,
  DocumentRecord,
  DocumentType,
  PALETTE_COLORS,
  RenderBackend,
  RENDER_BACKEND_LABELS,
  ToolType
} from '../models/NoteModels';
import { DocumentPreviewSnapshot } from '../models/PreviewModels';
import { DocumentLibraryService } from '../services/DocumentLibraryService';
import { EngineConfig, NativeDebugState, NativeNoteEngine, TraceActionResult } from '../services/NativeNoteEngine';
import { MarkdownPreviewBlock, MarkdownUtils } from '../utils/MarkdownUtils';

function parseAreaValue(value: Object): number {
  const parsed: number = Number.parseFloat(`${value}`);
  return Number.isNaN(parsed) ? 0 : parsed;
}

interface EditorWorkspaceCopy {
  back: string;
  save: string;
  undo: string;
  redo: string;
  toolPen: string;
  toolPencil: string;
  toolHighlighter: string;
  toolEraser: string;
  toolLasso: string;
  toolText: string;
  toolHand: string;
  collapseOptions: string;
  more: string;
  collapsePanel: string;
  openPanel: string;
  render: string;
  mode: string;
  placeholder: string;
  longPressCollapseDebugPanel: string;
  longPressExpandTracePanel: string;
  formula: string;
  previewPanel: string;
  sourcePanel: string;
  close: string;
  preview: string;
  source: string;
  debugPanel: string;
  collapse: string;
  startTrace: string;
  stopTrace: string;
  replayLastTrace: string;
  traceStatus: string;
  tracePath: string;
  traceSampleCount: string;
  traceUnsupported: string;
  recentAction: string;
  openingEditor: string;
  openDocumentFailed: string;
  documentNotFound: string;
  returnLibrary: string;
  sourcePlaceholder: string;
}

const EDITOR_HOME_ROUTE: string = 'pages/Index';
const BACK_HIT_TARGET_WIDTH: number = 156;
const BACK_HIT_TARGET_HEIGHT: number = 56;
const NATIVE_PAGE_METHOD_SET_ACTIVE: string = 'setActivePage';
const NATIVE_PAGE_METHOD_INSERT: string = 'insertPage';
const NATIVE_PAGE_METHOD_DELETE: string = 'deletePage';
const EDITOR_WORKSPACE_COPY: EditorWorkspaceCopy = {
  back: '返回',
  save: '保存',
  undo: '撤',
  redo: '重',
  toolPen: '笔',
  toolPencil: '铅',
  toolHighlighter: '荧',
  toolEraser: '橡',
  toolLasso: '套',
  toolText: '文',
  toolHand: '手',
  collapseOptions: '收起选项',
  more: '更多',
  collapsePanel: '收起面板',
  openPanel: '打开面板',
  render: '渲染',
  mode: '模式',
  placeholder: '占位',
  longPressCollapseDebugPanel: '长按画布可收起调试面板',
  longPressExpandTracePanel: '长按画布可展开 trace/debug',
  formula: '公式',
  previewPanel: '预览面板',
  sourcePanel: '源码面板',
  close: '关闭',
  preview: '预览',
  source: '源码',
  debugPanel: '调试面板',
  collapse: '收起',
  startTrace: '开始 Trace',
  stopTrace: '停止 Trace',
  replayLastTrace: '回放最近 Trace',
  traceStatus: '状态',
  tracePath: '路径',
  traceSampleCount: '采样数',
  traceUnsupported: '模拟器冒烟模式不支持 trace 录制与回放，因此这些控件保持禁用。',
  recentAction: '最近操作',
  openingEditor: '正在打开编辑器...',
  openDocumentFailed: '无法打开文档',
  documentNotFound: '未找到文档',
  returnLibrary: '返回笔记库',
  sourcePlaceholder: '输入 Markdown 和公式，例如 $x^2$ 或 $$\\int_0^1 x dx$$'
};

@Entry
@Component
struct EditorWorkspace {
  private readonly appContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private readonly xComponentController: XComponentController = new XComponentController();
  private readonly nativeEngine: NativeNoteEngine = new NativeNoteEngine();
  private readonly nativePageBridge: Record<string, Object> = nativeModule as Record<string, Object>;
  private readonly xComponentId: string = `note-surface-${Date.now()}`;
  private libraryService?: DocumentLibraryService;
  private readonly pageMarkdownDrafts: Map<string, string> = new Map<string, string>();
  private readonly dirtyPageIds: Set<string> = new Set<string>();
  private bootstrapping: boolean = false;
  private shutdownScheduled: boolean = false;
  private shuttingDown: boolean = false;
  private leavingEditor: boolean = false;
  private debugRefreshTimerId: number = -1;
  private persistTask: Promise<boolean> | null = null;

  @State private loading: boolean = true;
  @State private errorMessage: string = '';
  @State private document: DocumentRecord | null = null;
  @State private markdownText: string = '';
  @State private previewMode: 'preview' | 'source' = 'preview';
  @State private showInspectorDrawer: boolean = false;
  @State private showToolExtras: boolean = false;
  @State private activePageId: string = '';
  @State private activePageIndex: number = 0;
  @State private engineId: string = '';
  @State private currentTool: ToolType = ToolType.PEN;
  @State private currentColor: string = PALETTE_COLORS[0];
  @State private currentMode: DocumentMode = DocumentMode.PAGED;
  @State private currentBackend: RenderBackend = RenderBackend.OPEN_GLES;
  @State private debugStateText: string = '';
  @State private debugState: NativeDebugState | null = null;
  @State private showTracePanel: boolean = false;
  @State private traceActionMessage: string = '';
  @State private surfaceReady: boolean = false;
  @State private saveState: 'idle' | 'saving' | 'saved' | 'failed' = 'idle';

  aboutToAppear(): void {
    if (this.bootstrapping || this.engineId.length > 0 || this.document !== null || !this.loading) {
      return;
    }
    this.bootstrap();
  }

  aboutToDisappear(): void {
    if (this.leavingEditor || this.shuttingDown) {
      if (!this.shuttingDown && !this.shutdownScheduled) {
        this.shutdownScheduled = true;
        setTimeout(() => {
          this.shutdown();
        }, 0);
      }
      return;
    }
    this.persistDocumentState();
  }

  private formatError(error: Object): string {
    const errorMap: Record<string, Object> = error as Record<string, Object>;
    const name: string = typeof errorMap['name'] === 'string' ? errorMap['name'] as string : '';
    const message: string = typeof errorMap['message'] === 'string' ? errorMap['message'] as string : '';
    const code: string = typeof errorMap['code'] === 'number' || typeof errorMap['code'] === 'string'
      ? `${errorMap['code']}`
      : '';
    const stage: string = typeof errorMap['stage'] === 'string' ? errorMap['stage'] as string : '';
    const path: string = typeof errorMap['path'] === 'string' ? errorMap['path'] as string : '';
    const details: string[] = [];
    if (name.length > 0) {
      details.push(name);
    }
    if (message.length > 0) {
      details.push(message);
    }
    if (code.length > 0) {
      details.push(`code=${code}`);
    }
    if (stage.length > 0) {
      details.push(`stage=${stage}`);
    }
    if (path.length > 0) {
      details.push(`path=${path}`);
    }
    if (details.length > 0) {
      return details.join(' | ');
    }
    try {
      const serialized: string = JSON.stringify(error);
      if (serialized.length > 0 && serialized !== '{}') {
        return serialized;
      }
    } catch (_) {
      // Fall through to string coercion.
    }
    const fallback: string = `${error}`;
    if (fallback.length > 0 && fallback !== '[object Object]') {
      return fallback;
    }
    return 'Unknown error';
  }

  private isBlankPagedEditable(document: DocumentRecord | null = this.document): boolean {
    return document?.documentType === DocumentType.BLANK && document.documentMode === DocumentMode.PAGED;
  }

  private supportsPagedDocumentRuntime(document: DocumentRecord | null = this.document): boolean {
    return document?.documentMode === DocumentMode.PAGED &&
      (document?.schemaVersion ?? 0) >= 2 &&
      (document?.pages.length ?? 0) > 0;
  }

  private editablePages(document: DocumentRecord | null = this.document): DocumentPageEntry[] {
    if (!document || !this.supportsPagedDocumentRuntime(document)) {
      return [];
    }
    return [...document.pages].sort((left, right) => left.order - right.order);
  }

  private canMutatePageSet(document: DocumentRecord | null = this.document): boolean {
    return this.isBlankPagedEditable(document);
  }

  private canChangeDocumentMode(document: DocumentRecord | null = this.document): boolean {
    if (!document) {
      return true;
    }
    return !(document.documentType !== DocumentType.BLANK && this.supportsPagedDocumentRuntime(document));
  }

  private hasOptionalNativePageMethod(methodName: string): boolean {
    return typeof this.nativePageBridge[methodName] === 'function';
  }

  private shouldUsePageBridge(): boolean {
    return this.supportsPagedDocumentRuntime() && this.hasOptionalNativePageMethod(NATIVE_PAGE_METHOD_SET_ACTIVE);
  }

  private async primeBlankPagedRuntime(pageId: string): Promise<void> {
    if (!this.document || !this.libraryService || !this.supportsPagedDocumentRuntime() || this.engineId.length === 0) {
      return;
    }
    if (this.shouldUsePageBridge()) {
      return;
    }
    await this.libraryService.stagePageStrokesForRuntime(this.document.id, pageId);
  }

  private async persistBlankPagedRuntimePage(): Promise<void> {
    if (!this.document || !this.libraryService || !this.supportsPagedDocumentRuntime() || this.engineId.length === 0) {
      return;
    }
    this.nativeEngine.saveCheckpoint(this.engineId, this.document.id);
    if (!this.shouldUsePageBridge() && this.activePageId.length > 0) {
      await this.libraryService.captureRuntimePageStrokes(this.document.id, this.activePageId);
    }
  }

  private applyDocumentActivePage(document: DocumentRecord, pageId: string): void {
    const pages: DocumentPageEntry[] = this.editablePages(document);
    if (pages.length === 0) {
      this.document = document;
      this.activePageId = '';
      this.activePageIndex = document.previewSnapshot?.pageIndex ?? 0;
      return;
    }
    const activePage: DocumentPageEntry = pages.find((page) => page.id === pageId) ?? pages[0];
    const nextDocument: DocumentRecord = {
      id: document.id,
      title: document.title,
      documentType: document.documentType,
      documentMode: document.documentMode,
      renderBackend: document.renderBackend,
      previewSnapshot: document.previewSnapshot,
      schemaVersion: document.schemaVersion,
      activePageId: activePage.id,
      pageCount: pages.length,
      pages,
      pageTemplateId: activePage.pageTemplateId,
      pageSizeId: activePage.pageSizeId,
      paperBackgroundId: activePage.paperBackgroundId,
      folderId: document.folderId,
      packagePath: document.packagePath,
      manifestPath: document.manifestPath,
      previewPath: document.previewPath,
      previewSummary: document.previewSummary,
      coverPage: activePage.order,
      coverVersion: document.coverVersion,
      isFavorite: document.isFavorite,
      isPinned: document.isPinned,
      isTrashed: document.isTrashed,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      openedAt: document.openedAt,
      trashedAt: document.trashedAt,
      attachments: document.attachments,
      tags: document.tags
    };
    this.document = nextDocument;
    this.activePageId = activePage.id;
    this.activePageIndex = activePage.order;
  }

  private stageCurrentPageDraft(): void {
    if (!this.supportsPagedDocumentRuntime() || this.activePageId.length === 0) {
      return;
    }
    this.pageMarkdownDrafts.set(this.activePageId, this.markdownText);
    this.dirtyPageIds.add(this.activePageId);
  }

  private async loadPageMarkdown(pageId: string): Promise<void> {
    if (!this.document || !this.libraryService) {
      return;
    }
    const draft: string | undefined = this.pageMarkdownDrafts.get(pageId);
    if (draft !== undefined) {
      this.markdownText = draft;
      return;
    }
    const markdownText: string = await this.libraryService.getDocumentMarkdown(this.document.id, pageId);
    this.pageMarkdownDrafts.set(pageId, markdownText);
    this.markdownText = markdownText;
  }

  private invokeNativePageMethod(methodName: string, candidateArgs: Array<Array<string | number>>): boolean {
    const method: Object = this.nativePageBridge[methodName];
    if (typeof method !== 'function') {
      return false;
    }
    for (let index: number = 0; index < candidateArgs.length; index += 1) {
      try {
        const result: boolean = Boolean((method as (...args: Array<string | number>) => boolean)(...candidateArgs[index]));
        if (result) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  private notifyNativeActivePage(pageId: string): boolean {
    if (!this.document || this.engineId.length === 0) {
      return false;
    }
    return this.invokeNativePageMethod(NATIVE_PAGE_METHOD_SET_ACTIVE, [
      [this.engineId, this.document.id, pageId],
      [this.engineId, pageId]
    ]);
  }

  private notifyNativeInsertPage(page: DocumentPageEntry): boolean {
    if (!this.document || this.engineId.length === 0) {
      return false;
    }
    const payload: string = JSON.stringify({
      pageId: page.id,
      order: page.order,
      pageContract: buildNativePageContractForEntry(this.document, page)
    });
    return this.invokeNativePageMethod(NATIVE_PAGE_METHOD_INSERT, [
      [this.engineId, this.document.id, page.id, payload],
      [this.engineId, this.document.id, payload],
      [this.engineId, payload]
    ]);
  }

  private notifyNativeDeletePage(pageId: string): boolean {
    if (!this.document || this.engineId.length === 0) {
      return false;
    }
    return this.invokeNativePageMethod(NATIVE_PAGE_METHOD_DELETE, [
      [this.engineId, this.document.id, pageId],
      [this.engineId, pageId]
    ]);
  }

  private async reopenNativeDocumentForCurrentState(): Promise<void> {
    if (!this.document || this.engineId.length === 0) {
      return;
    }
    this.nativeEngine.openDocument(
      this.engineId,
      this.document.id,
      this.document.packagePath,
      buildNativeOpenDocumentConfig(this.document, this.currentTool)
    );
    this.nativeEngine.setBrushColor(this.engineId, this.currentColor);
    this.refreshDebugState();
  }

  private async bootstrap(): Promise<void> {
    if (this.bootstrapping || this.engineId.length > 0 || this.document !== null) {
      return;
    }
    this.bootstrapping = true;
    try {
      const params: Record<string, string | number | boolean | Object> =
        router.getParams() as Record<string, string | number | boolean | Object>;
      const documentId: string = String(params['documentId'] ?? '');
      if (documentId.length === 0) {
        throw new Error('Missing documentId');
      }
      this.libraryService = await DocumentLibraryService.getInstance(this.appContext);
      this.document = await this.libraryService.openDocumentById(documentId);
      this.currentMode = this.document.documentMode;
      this.currentBackend = this.document.renderBackend;
      if (this.supportsPagedDocumentRuntime(this.document)) {
        this.applyDocumentActivePage(this.document, this.document.activePageId);
        await this.loadPageMarkdown(this.activePageId);
      } else {
        this.activePageId = '';
        this.pageMarkdownDrafts.clear();
        this.dirtyPageIds.clear();
        this.markdownText = await this.libraryService.getDocumentMarkdown(documentId);
        this.activePageIndex = this.document.previewSnapshot?.pageIndex ?? 0;
      }

      const engineConfig: EngineConfig = {
        backend: this.currentBackend,
        documentMode: this.currentMode,
        dpiScale: 2,
        enablePrediction: true,
        enablePressureForPen: true,
        enableShapeDetection: true,
        enableMarkdownOverlay: true
      };
      this.engineId = this.nativeEngine.createEngine(engineConfig);
      if (this.supportsPagedDocumentRuntime()) {
        await this.primeBlankPagedRuntime(this.activePageId);
      }
      this.nativeEngine.openDocument(
        this.engineId,
        this.document.id,
        this.document.packagePath,
        buildNativeOpenDocumentConfig(this.document, this.currentTool)
      );
      this.nativeEngine.setBrushColor(this.engineId, this.currentColor);
      this.startDebugPolling();
      this.attachSurfaceIfReady();
      this.refreshDebugState();
    } catch (error) {
      this.errorMessage = this.formatError(error as Object);
    } finally {
      this.bootstrapping = false;
      this.loading = false;
    }
  }

  private attachSurfaceIfReady(): void {
    if (!this.surfaceReady || this.engineId.length === 0 || !this.shouldRenderNativeSurface()) {
      return;
    }
    const surfaceId: string = this.xComponentController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      return;
    }
    this.nativeEngine.attachXComponent(this.engineId, this.xComponentId, surfaceId);
    this.refreshDebugState();
  }

  private refreshDebugState(): void {
    if (this.engineId.length === 0) {
      this.debugStateText = '';
      this.debugState = null;
      return;
    }
    const state: NativeDebugState | null = this.nativeEngine.getDebugState(this.engineId);
    if (!state) {
      this.debugState = null;
      this.debugStateText = 'native debug unavailable';
      return;
    }
    this.debugState = state;
    this.debugStateText = `engine=${state.engineId}\n` +
      `doc=${state.activeDocumentId}\n` +
      `tool=${state.activeTool} native=${state.lastToolType}\n` +
      `color=${state.activeColor}\n` +
      `backend=${state.activeBackend}\n` +
      `mode=${state.activeMode}\n` +
      `runtimeProfile=${state.runtimeProfile}\n` +
      `stubReason=${state.stubReason || '-'}\n` +
      `caps=trace:${state.traceSupported} preview:${state.previewRenderSupported} scene:${state.sceneExportSupported}\n` +
      `surface=${state.surfaceId || '-'} ready=${state.surfaceReady}\n` +
      `size=${state.surfaceWidth}x${state.surfaceHeight} pointers=${state.activePointerCount}\n` +
      `touch=${state.touchEventCount} ui=${state.uiTouchEventCount} key=${state.keyEventCount}\n` +
      `stylus=${state.stylusEventCount} finger=${state.fingerEventCount} palm=${state.palmRejectedCount}\n` +
      `history=${state.lastHistoricalCount}/${state.lastUiHistoryCount} predict=${state.predictedPointCount}\n` +
      `pressure=${state.lastPressure.toFixed(3)} tilt=${state.lastTiltX.toFixed(1)},${state.lastTiltY.toFixed(1)} roll=${state.lastRollAngle.toFixed(1)}\n` +
      `strokes=${state.committedStrokeCount} undo=${state.undoDepth} redo=${state.redoDepth} shape=${state.lastCommittedStrokeType}\n` +
      `source=${state.lastSourceType} action=${state.lastTouchAction}\n` +
      `trace=${state.inputTraceStatus || 'idle'} recording=${state.inputTraceRecording} replay=${state.inputReplayActive} samples=${state.inputTraceSampleCount}\n` +
      `prediction=${state.predictionEnabled} pressureOn=${state.pressureEnabled} shape=${state.shapeRecognitionEnabled}`;
  }

  private startDebugPolling(): void {
    if (this.debugRefreshTimerId >= 0) {
      return;
    }
    this.debugRefreshTimerId = setInterval(() => {
      this.refreshDebugState();
    }, 180);
  }

  private stopDebugPolling(): void {
    if (this.debugRefreshTimerId < 0) {
      return;
    }
    clearInterval(this.debugRefreshTimerId);
    this.debugRefreshTimerId = -1;
  }

  private previewBlocks(): MarkdownPreviewBlock[] {
    return MarkdownUtils.buildPreviewBlocks(this.markdownText);
  }

  private saveButtonLabel(): string {
    if (this.saveState === 'saving') {
      return 'Saving...';
    }
    if (this.saveState === 'saved') {
      return 'Saved';
    }
    if (this.saveState === 'failed') {
      return 'Save failed';
    }
    return EDITOR_WORKSPACE_COPY.save;
  }

  private async persistDocumentState(): Promise<boolean> {
    if (this.persistTask) {
      return await this.persistTask;
    }
    if (!this.document || !this.libraryService) {
      return false;
    }
    const runPersist = async (): Promise<boolean> => {
      try {
        let nextDocument: DocumentRecord;
        let mustConfirmBlankPagedSave: boolean = false;
        let expectedConfirmedPageId: string = '';
        if (this.supportsPagedDocumentRuntime()) {
          this.stageCurrentPageDraft();
          await this.persistBlankPagedRuntimePage();
          if (this.isBlankPagedEditable()) {
            nextDocument = await this.libraryService!.prepareBlankPagedDocumentForSave(this.document!.id);
            mustConfirmBlankPagedSave = this.isBlankPagedEditable(nextDocument);
            for (const pageId of Array.from(this.dirtyPageIds.values())) {
              const markdownText: string = this.pageMarkdownDrafts.get(pageId) ?? '';
              nextDocument = await this.libraryService!.saveDocumentMarkdown(nextDocument.id, markdownText, pageId, false);
            }
            this.dirtyPageIds.clear();
          } else {
            const currentPageId: string = this.activePageId.length > 0 ? this.activePageId : this.document!.activePageId;
            const currentMarkdown: string = this.pageMarkdownDrafts.get(currentPageId) ?? this.markdownText;
            nextDocument = await this.libraryService!.saveDocumentMarkdown(this.document!.id, currentMarkdown, currentPageId, false);
            this.dirtyPageIds.delete(currentPageId);
          }
          const nextActivePageId: string = this.activePageId.length > 0 ? this.activePageId : nextDocument.activePageId;
          expectedConfirmedPageId = nextActivePageId;
          nextDocument = await this.libraryService!.setDocumentActivePage(nextDocument.id, nextActivePageId);
          nextDocument = await this.libraryService!.refreshPreview(nextDocument.id);
        } else {
          if (this.engineId.length > 0) {
            this.nativeEngine.saveCheckpoint(this.engineId, this.document!.id);
          }
          nextDocument = await this.libraryService!.saveDocumentMarkdown(this.document!.id, this.markdownText);
        }
        nextDocument = await this.libraryService!.updateDocumentPresentation(
          nextDocument.id,
          this.currentMode,
          this.currentBackend
        );
        if (mustConfirmBlankPagedSave) {
          nextDocument = await this.libraryService!.confirmBlankPagedSaveCompleted(nextDocument.id, expectedConfirmedPageId);
        }
        if (this.supportsPagedDocumentRuntime(nextDocument)) {
          this.applyDocumentActivePage(nextDocument, this.activePageId.length > 0 ? this.activePageId : nextDocument.activePageId);
        } else {
          this.activePageId = '';
          this.pageMarkdownDrafts.clear();
          this.dirtyPageIds.clear();
          this.document = nextDocument;
          this.activePageIndex = nextDocument.previewSnapshot?.pageIndex ?? this.activePageIndex;
        }
        if (this.engineId.length > 0) {
          await this.syncNativePreviewSnapshot();
        }
        this.activePageIndex = Math.min(this.activePageIndex, this.pageCount() - 1);
        this.refreshDebugState();
        this.traceActionMessage = 'save-complete';
        return true;
      } catch (error) {
        this.traceActionMessage = `save-failed ${this.formatError(error as Object)}`;
        return false;
      }
    };
    this.persistTask = runPersist();
    try {
      return await this.persistTask;
    } finally {
      this.persistTask = null;
    }
  }

  private async saveDocument(): Promise<boolean> {
    if (this.shuttingDown || this.leavingEditor) {
      return false;
    }
    this.saveState = 'saving';
    const didPersist: boolean = await this.persistDocumentState();
    this.saveState = didPersist ? 'saved' : 'failed';
    return didPersist;
  }

  private async shutdown(): Promise<void> {
    if (this.shuttingDown) {
      await this.persistDocumentState();
      return;
    }
    this.shutdownScheduled = false;
    this.shuttingDown = true;
    this.stopDebugPolling();
    await this.persistDocumentState();
    if (this.document && this.engineId.length > 0) {
      try {
        this.nativeEngine.disposeDocument(this.engineId, this.document.id);
      } catch (_) {
        // Ignore teardown failures during page exit.
      }
    }
    if (this.engineId.length > 0) {
      this.nativeEngine.disposeEngine(this.engineId);
      this.engineId = '';
    }
  }

  private goBack(): void {
    if (this.leavingEditor) {
      return;
    }
    this.leavingEditor = true;
    try {
      router.replaceUrl({ url: EDITOR_HOME_ROUTE });
    } catch (_) {
      this.leavingEditor = false;
    }
  }

  private undoStroke(): void {
    if (this.engineId.length === 0) {
      return;
    }
    this.nativeEngine.undo(this.engineId);
    this.refreshDebugState();
  }

  private redoStroke(): void {
    if (this.engineId.length === 0) {
      return;
    }
    this.nativeEngine.redo(this.engineId);
    this.refreshDebugState();
  }

  private setTool(tool: ToolType): void {
    this.currentTool = tool;
    if (this.engineId.length > 0) {
      this.nativeEngine.setTool(this.engineId, tool);
      this.refreshDebugState();
    }
  }

  private toolLabel(tool: ToolType): string {
    switch (tool) {
      case ToolType.PEN:
        return EDITOR_WORKSPACE_COPY.toolPen;
      case ToolType.PENCIL:
        return EDITOR_WORKSPACE_COPY.toolPencil;
      case ToolType.HIGHLIGHTER:
        return EDITOR_WORKSPACE_COPY.toolHighlighter;
      case ToolType.ERASER:
        return EDITOR_WORKSPACE_COPY.toolEraser;
      case ToolType.LASSO:
        return EDITOR_WORKSPACE_COPY.toolLasso;
      case ToolType.TEXT:
        return EDITOR_WORKSPACE_COPY.toolText;
      case ToolType.HAND:
        return EDITOR_WORKSPACE_COPY.toolHand;
      default:
        return tool;
    }
  }

  private selectedPageLabel(): string {
    const currentPageNumber: number = this.activePageIndex + 1;
    return `${currentPageNumber}/${this.pageCount()}`;
  }

  private async setMode(mode: DocumentMode): Promise<void> {
    if (!this.canChangeDocumentMode() && mode !== this.currentMode) {
      return;
    }
    if (this.document && this.libraryService && this.isBlankPagedEditable() && mode !== DocumentMode.PAGED) {
      this.stageCurrentPageDraft();
      await this.persistBlankPagedRuntimePage();
      if (this.activePageId.length > 0) {
        const currentMarkdown: string = this.pageMarkdownDrafts.get(this.activePageId) ?? this.markdownText;
        await this.libraryService.saveDocumentMarkdown(this.document.id, currentMarkdown, this.activePageId, false);
      }
    }
    this.currentMode = mode;
    if (this.engineId.length > 0) {
      this.nativeEngine.setDocumentMode(this.engineId, mode);
      this.refreshDebugState();
    }
    if (this.document && this.libraryService) {
      const nextDocument: DocumentRecord = await this.libraryService.updateDocumentPresentation(this.document.id, mode, this.currentBackend);
      if (this.supportsPagedDocumentRuntime(nextDocument)) {
        this.applyDocumentActivePage(nextDocument, this.activePageId.length > 0 ? this.activePageId : nextDocument.activePageId);
      } else {
        this.activePageId = '';
        this.pageMarkdownDrafts.clear();
        this.dirtyPageIds.clear();
        this.document = nextDocument;
        this.activePageIndex = nextDocument.previewSnapshot?.pageIndex ?? 0;
      }
    }
  }

  private async setBackend(backend: RenderBackend): Promise<void> {
    this.currentBackend = backend;
    if (this.engineId.length > 0) {
      this.nativeEngine.setBackend(this.engineId, backend);
      this.refreshDebugState();
    }
    if (this.document && this.libraryService) {
      const nextDocument: DocumentRecord = await this.libraryService.updateDocumentPresentation(this.document.id, this.currentMode, backend);
      if (this.supportsPagedDocumentRuntime(nextDocument)) {
        this.applyDocumentActivePage(nextDocument, this.activePageId.length > 0 ? this.activePageId : nextDocument.activePageId);
      } else {
        this.activePageId = '';
        this.pageMarkdownDrafts.clear();
        this.dirtyPageIds.clear();
        this.document = nextDocument;
      }
    }
  }

  private async syncNativePreviewSnapshot(): Promise<void> {
    if (!this.document || !this.libraryService || this.engineId.length === 0) {
      return;
    }
    try {
      const previewSize = buildNativePreviewRequestSize(this.document);
      const nativePreview: NativePreviewPayload | null = this.nativeEngine.requestPreviewRender(
        this.engineId,
        this.document.id,
        this.activePageIndex,
        previewSize.width,
        previewSize.height
      );
      const mergedDocument: DocumentRecord = await this.libraryService.mergeNativePreviewSnapshot(this.document.id, nativePreview);
      this.applyDocumentActivePage(mergedDocument, this.activePageId);
    } catch (_) {
      return;
    }
  }

  private runtimeProfileText(): string {
    const runtimeProfile: string = this.debugState?.runtimeProfile ?? 'device-native';
    return runtimeProfile.length > 0 ? runtimeProfile : 'device-native';
  }

  private stubReasonText(): string {
    const reason: string = this.debugState?.stubReason ?? '';
    return reason.length > 0 ? reason : 'none';
  }

  private shouldUseSimulatorStubUi(): boolean {
    return this.debugState?.runtimeProfile === 'simulator-stub';
  }

  private shouldRenderNativeSurface(): boolean {
    return !this.shouldUseSimulatorStubUi();
  }

  private isTraceSupported(): boolean {
    return this.debugState?.traceSupported ?? false;
  }

  private simulatorCapabilitySummary(): string {
    const state: NativeDebugState | null = this.debugState;
    if (!state) {
      return 'trace=false preview=false scene=false';
    }
    return `trace=${state.traceSupported} preview=${state.previewRenderSupported} scene=${state.sceneExportSupported}`;
  }

  private toggleTracePanel(): void {
    if (this.engineId.length === 0) {
      return;
    }
    this.showTracePanel = !this.showTracePanel;
  }

  private canStartTrace(): boolean {
    if (this.engineId.length === 0 || !this.debugState || !this.isTraceSupported()) {
      return false;
    }
    return !this.debugState.inputTraceRecording && !this.debugState.inputReplayActive;
  }

  private canStopTrace(): boolean {
    return this.engineId.length > 0 &&
      this.isTraceSupported() &&
      (this.debugState?.inputTraceRecording ?? false);
  }

  private canReplayTrace(): boolean {
    if (this.engineId.length === 0 || !this.debugState || !this.isTraceSupported()) {
      return false;
    }
    return !this.debugState.inputTraceRecording &&
      !this.debugState.inputReplayActive &&
      this.debugState.inputTracePath.length > 0;
  }

  private traceStatusText(): string {
    return this.debugState?.inputTraceStatus || 'idle';
  }

  private tracePathText(): string {
    const path: string = this.debugState?.inputTracePath ?? '';
    return path.length > 0 ? path : '-';
  }

  private traceSampleCountText(): string {
    return `${this.debugState?.inputTraceSampleCount ?? 0}`;
  }

  private updateTraceActionMessage(result: TraceActionResult | null, fallbackMessage: string): void {
    if (!result) {
      this.traceActionMessage = fallbackMessage;
      return;
    }
    const pathSuffix: string = result.path && result.path.length > 0 ? ` ${result.path}` : '';
    const sampleSuffix: string = result.sampleCount !== undefined ? ` (${result.sampleCount})` : '';
    this.traceActionMessage = `${result.status}${sampleSuffix}${pathSuffix}`.trim();
  }

  private handleStartTrace(): void {
    if (!this.canStartTrace()) {
      return;
    }
    try {
      const ok: boolean = this.nativeEngine.startInputTraceRecording(this.engineId);
      this.traceActionMessage = ok ? 'recording' : 'start-failed';
    } catch (_) {
      this.traceActionMessage = 'start-failed';
    }
    this.refreshDebugState();
  }

  private handleStopTrace(): void {
    if (!this.canStopTrace()) {
      return;
    }
    try {
      const result: TraceActionResult | null = this.nativeEngine.stopInputTraceRecording(this.engineId);
      this.updateTraceActionMessage(result, 'stop-failed');
    } catch (_) {
      this.traceActionMessage = 'stop-failed';
    }
    this.refreshDebugState();
  }

  private handleReplayTrace(): void {
    if (!this.canReplayTrace()) {
      return;
    }
    try {
      const tracePath: string = this.debugState?.inputTracePath ?? '';
      const result: TraceActionResult | null = this.nativeEngine.replayInputTrace(this.engineId, tracePath);
      this.updateTraceActionMessage(result, 'replay-failed');
    } catch (_) {
      this.traceActionMessage = 'replay-failed';
    }
    this.refreshDebugState();
  }

  private toggleInspector(mode: 'preview' | 'source'): void {
    if (this.showInspectorDrawer && this.previewMode === mode) {
      this.showInspectorDrawer = false;
      return;
    }
    this.previewMode = mode;
    this.showInspectorDrawer = true;
  }

  private closeInspector(): void {
    this.showInspectorDrawer = false;
  }

  private toggleToolExtras(): void {
    this.showToolExtras = !this.showToolExtras;
  }

  private previewSnapshot(): DocumentPreviewSnapshot | undefined {
    return this.document?.previewSnapshot;
  }

  private pageCount(): number {
    if (this.supportsPagedDocumentRuntime()) {
      return Math.max(1, this.editablePages().length);
    }
    const snapshot: DocumentPreviewSnapshot | undefined = this.previewSnapshot();
    const pageIdCount: number = snapshot?.pageIds.length ?? 0;
    const layoutCount: number = snapshot?.layout?.pageCount ?? 0;
    return Math.max(1, pageIdCount, layoutCount);
  }

  private pageIndexes(): number[] {
    const indexes: number[] = [];
    for (let index = 0; index < this.pageCount(); index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private async selectPage(index: number): Promise<void> {
    if (this.supportsPagedDocumentRuntime()) {
      const nextPage: DocumentPageEntry | undefined = this.editablePages()[index];
      if (!nextPage || nextPage.id === this.activePageId || !this.document || !this.libraryService) {
        return;
      }
      const currentPageId: string = this.activePageId;
      this.stageCurrentPageDraft();
      await this.persistBlankPagedRuntimePage();
      if (currentPageId.length > 0) {
        const currentMarkdown: string = this.pageMarkdownDrafts.get(currentPageId) ?? this.markdownText;
        await this.libraryService.saveDocumentMarkdown(this.document.id, currentMarkdown, currentPageId, false);
        this.dirtyPageIds.delete(currentPageId);
      }
      const nextDocument: DocumentRecord = await this.libraryService.setDocumentActivePage(this.document.id, nextPage.id);
      this.applyDocumentActivePage(nextDocument, nextPage.id);
      await this.loadPageMarkdown(nextPage.id);
      if (!this.notifyNativeActivePage(nextPage.id)) {
        await this.primeBlankPagedRuntime(nextPage.id);
        await this.reopenNativeDocumentForCurrentState();
      }
      this.refreshDebugState();
      return;
    }
    this.activePageIndex = index;
  }

  private canAddRealPages(): boolean {
    return this.canMutatePageSet() && this.document !== null && this.libraryService !== undefined;
  }

  private canDeleteCurrentPage(): boolean {
    return this.canAddRealPages() && this.editablePages().length > 1 && this.activePageId.length > 0;
  }

  private async addPage(): Promise<void> {
    if (!this.canAddRealPages()) {
      return;
    }
    this.stageCurrentPageDraft();
    await this.persistBlankPagedRuntimePage();
    const nextDocument: DocumentRecord = await this.libraryService!.addBlankPage((this.document as DocumentRecord).id);
    const insertedPage: DocumentPageEntry | undefined = nextDocument.pages.find((page) => page.id === nextDocument.activePageId);
    this.applyDocumentActivePage(nextDocument, nextDocument.activePageId);
    await this.loadPageMarkdown(this.activePageId);
    const inserted: boolean = insertedPage !== undefined ? this.notifyNativeInsertPage(insertedPage) : false;
    const activated: boolean = inserted && this.notifyNativeActivePage(this.activePageId);
    if (!activated) {
      await this.primeBlankPagedRuntime(this.activePageId);
      await this.reopenNativeDocumentForCurrentState();
    }
    this.refreshDebugState();
  }

  private async deleteCurrentPage(): Promise<void> {
    if (!this.canDeleteCurrentPage()) {
      return;
    }
    const deletedPageId: string = this.activePageId;
    this.stageCurrentPageDraft();
    await this.persistBlankPagedRuntimePage();
    const nextDocument: DocumentRecord = await this.libraryService!.deleteBlankPage((this.document as DocumentRecord).id, deletedPageId);
    this.pageMarkdownDrafts.delete(deletedPageId);
    this.dirtyPageIds.delete(deletedPageId);
    this.applyDocumentActivePage(nextDocument, nextDocument.activePageId);
    await this.loadPageMarkdown(this.activePageId);
    const deleted: boolean = this.notifyNativeDeletePage(deletedPageId);
    const activated: boolean = deleted && this.notifyNativeActivePage(this.activePageId);
    if (!activated) {
      await this.primeBlankPagedRuntime(this.activePageId);
      await this.reopenNativeDocumentForCurrentState();
    }
    this.refreshDebugState();
  }

  private pageEntryAt(index: number): DocumentPageEntry | undefined {
    return this.supportsPagedDocumentRuntime() ? this.editablePages()[index] : undefined;
  }

  private pageKeyAt(index: number): string {
    return this.pageEntryAt(index)?.id ?? `page-${index}`;
  }

  private isSelectedPageIndex(index: number): boolean {
    if (this.supportsPagedDocumentRuntime()) {
      return this.activePageId === this.pageKeyAt(index);
    }
    return this.activePageIndex === index;
  }

  @Builder
  private buildHeaderBar(): void {
    Row() {
      Button(EDITOR_WORKSPACE_COPY.back)
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor('#FFFFFF')
        .fontColor('#162033')
        .fontSize(12)
        .responseRegion({
          x: -24,
          y: -12,
          width: 150,
          height: 52
        })
        .onClick(() => {
          this.goBack();
        })
      Column() {
        Text((this.document as DocumentRecord).title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#162033')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8, right: 8 })
      Button(this.saveButtonLabel())
        .height(28)
        .padding({ left: 10, right: 10 })
        .enabled(this.saveState !== 'saving')
        .backgroundColor(this.saveState === 'saving' ? '#98A2B3' : '#162033')
        .fontColor('#FFFFFF')
        .fontSize(12)
        .onClick(async () => {
          await this.saveDocument();
        })
    }
    .padding({ left: 6, right: 6, top: 4, bottom: 4 })
    .backgroundColor('#FDFEFE')
    .border({ width: 1, color: '#E3E8EF' })
    .borderRadius(999)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildBackHitTarget(): void {
    Blank()
      .width(BACK_HIT_TARGET_WIDTH)
      .height(BACK_HIT_TARGET_HEIGHT)
      .backgroundColor('#01000000')
      .borderRadius(999)
      .onClick(() => {
        this.goBack();
      })
  }

  @Builder
  private buildFloatingToolbar(): void {
    Column() {
      Row({ space: 4 }) {
        Button(EDITOR_WORKSPACE_COPY.undo)
          .width(28)
          .height(28)
          .backgroundColor('#F3F6FB')
          .fontColor('#162033')
          .fontSize(11)
          .onClick(() => {
            this.undoStroke();
          })
        Button(EDITOR_WORKSPACE_COPY.redo)
          .width(28)
          .height(28)
          .backgroundColor('#F3F6FB')
          .fontColor('#162033')
          .fontSize(11)
          .onClick(() => {
            this.redoStroke();
          })
        ForEach([
          ToolType.PEN,
          ToolType.PENCIL,
          ToolType.HIGHLIGHTER,
          ToolType.ERASER,
          ToolType.LASSO,
          ToolType.TEXT,
          ToolType.HAND
        ], (tool: ToolType) => {
          Button(this.toolLabel(tool))
            .width(28)
            .height(28)
            .backgroundColor(this.currentTool === tool ? '#162033' : '#FFFFFF')
            .fontColor(this.currentTool === tool ? '#FFFFFF' : '#162033')
            .fontSize(11)
            .onClick(() => {
              this.setTool(tool);
            })
        }, (tool: ToolType): string => tool)
        Button(this.showToolExtras ? EDITOR_WORKSPACE_COPY.collapseOptions : EDITOR_WORKSPACE_COPY.more)
          .height(28)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.showToolExtras ? '#DCE6FF' : '#FFFFFF')
          .fontColor('#162033')
          .fontSize(11)
          .onClick(() => {
            this.toggleToolExtras();
          })
      }
      Row({ space: 8 }) {
        ForEach(PALETTE_COLORS, (color: string) => {
          Blank()
            .width(16)
            .height(16)
            .backgroundColor(color)
            .border({
              width: this.currentColor === color ? 3 : 1,
              color: this.currentColor === color ? '#162033' : '#D0D5DD'
            })
            .borderRadius(8)
            .onClick(() => {
              this.currentColor = color;
              if (this.engineId.length > 0) {
                this.nativeEngine.setBrushColor(this.engineId, color);
                this.refreshDebugState();
              }
            })
        }, (color: string): string => color)
      }
      .margin({ top: 8 })
      if (this.showToolExtras) {
        Row({ space: 10 }) {
          Button(this.showInspectorDrawer ? EDITOR_WORKSPACE_COPY.collapsePanel : EDITOR_WORKSPACE_COPY.openPanel)
            .height(30)
            .backgroundColor(this.showInspectorDrawer ? '#DCE6FF' : '#FFFFFF')
            .fontColor('#162033')
            .fontSize(11)
            .onClick(() => {
              this.toggleInspector('preview');
            })
          Blank()
            .width(1)
            .height(18)
            .backgroundColor('#D8E0EA')
          Text(EDITOR_WORKSPACE_COPY.render)
            .fontSize(12)
            .fontColor('#667085')
          Button(RENDER_BACKEND_LABELS[RenderBackend.OPEN_GLES])
            .height(30)
            .backgroundColor(this.currentBackend === RenderBackend.OPEN_GLES ? '#162033' : '#FFFFFF')
            .fontColor(this.currentBackend === RenderBackend.OPEN_GLES ? '#FFFFFF' : '#162033')
            .fontSize(11)
            .onClick(() => {
              this.setBackend(RenderBackend.OPEN_GLES);
            })
          Button(RENDER_BACKEND_LABELS[RenderBackend.SKIA])
            .height(30)
            .backgroundColor(this.currentBackend === RenderBackend.SKIA ? '#162033' : '#FFFFFF')
            .fontColor(this.currentBackend === RenderBackend.SKIA ? '#FFFFFF' : '#162033')
            .fontSize(11)
            .onClick(() => {
              this.setBackend(RenderBackend.SKIA);
            })
          Blank()
            .width(1)
            .height(18)
            .backgroundColor('#D8E0EA')
          Text(EDITOR_WORKSPACE_COPY.mode)
            .fontSize(12)
            .fontColor('#667085')
          Button(DOCUMENT_MODE_LABELS[DocumentMode.PAGED])
            .height(30)
            .enabled(this.canChangeDocumentMode())
            .backgroundColor(this.currentMode === DocumentMode.PAGED ? '#162033' : '#FFFFFF')
            .fontColor(this.currentMode === DocumentMode.PAGED ? '#FFFFFF' : '#162033')
            .fontSize(11)
            .onClick(() => {
              this.setMode(DocumentMode.PAGED);
            })
          Button(DOCUMENT_MODE_LABELS[DocumentMode.INFINITE])
            .height(30)
            .enabled(this.canChangeDocumentMode())
            .backgroundColor(this.currentMode === DocumentMode.INFINITE ? '#162033' : '#FFFFFF')
            .fontColor(this.currentMode === DocumentMode.INFINITE ? '#FFFFFF' : '#162033')
            .fontSize(11)
            .onClick(() => {
              this.setMode(DocumentMode.INFINITE);
            })
        }
        .margin({ top: 8 })
        .padding(10)
        .backgroundColor('#F7F9FC')
        .borderRadius(16)
      }
    }
    .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#D8E0EA' })
    .borderRadius(16)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildStubBadge(): void {
    Row({ space: 8 }) {
      Text(EDITOR_WORKSPACE_COPY.placeholder)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor('#7A2E0B')
      Text(`runtimeProfile=${this.runtimeProfileText()}`)
        .fontSize(10)
        .fontColor('#9A3412')
    }
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor('#FFF7ED')
    .border({ width: 1, color: '#FDBA74' })
    .borderRadius(999)
  }

  @Builder
  private buildPlaceholderSurface(): void {
    Column() {}
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }

  @Builder
  private buildWritingSurface(): void {
    Stack() {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#F8FAFC')
      if (this.shouldRenderNativeSurface()) {
        XComponent({
          id: this.xComponentId,
          type: XComponentType.SURFACE,
          controller: this.xComponentController,
          libraryname: 'entry'
        })
          .width('100%')
          .height('100%')
          .backgroundColor('#F8FAFC')
          .onLoad(() => {
            this.surfaceReady = true;
            this.attachSurfaceIfReady();
          })
          .onDestroy(() => {
            this.surfaceReady = false;
          })
          .onAreaChange((_, newValue) => {
            if (this.engineId.length === 0) {
              return;
            }
            const width: number = parseAreaValue(newValue.width);
            const height: number = parseAreaValue(newValue.height);
            if (width > 0 && height > 0) {
              this.nativeEngine.resize(this.engineId, width, height, 2);
              this.refreshDebugState();
            }
          })
      } else {
        this.buildPlaceholderSurface()
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      LongPressGesture({ repeat: false, duration: 600 })
        .onAction(() => {
          this.toggleTracePanel();
        })
    )
  }

  @Builder
  private buildBottomHint(): void {
    Row({ space: 8 }) {
      Text(this.showTracePanel ? EDITOR_WORKSPACE_COPY.longPressCollapseDebugPanel : EDITOR_WORKSPACE_COPY.longPressExpandTracePanel)
        .fontSize(11)
        .fontColor('#475467')
      if (this.shouldUseSimulatorStubUi()) {
        Text(`stubReason=${this.stubReasonText()}`)
          .fontSize(11)
          .fontColor('#667085')
      }
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#D8E0EA' })
    .borderRadius(999)
  }

  @Builder
  private buildPreviewDrawerBody(): void {
    Scroll() {
      Column() {
        ForEach(this.previewBlocks(), (block: MarkdownPreviewBlock, index: number) => {
          if (block.type === 'heading') {
            Text(block.text)
              .fontSize(block.level === 1 ? 24 : 19)
              .fontWeight(FontWeight.Bold)
              .fontColor('#162033')
              .width('100%')
              .margin({ top: index === 0 ? 0 : 14 })
          } else if (block.type === 'formula') {
            Text(`${EDITOR_WORKSPACE_COPY.formula}：${block.text}`)
              .fontSize(14)
              .fontColor('#0B57D0')
              .padding(14)
              .width('100%')
              .backgroundColor('#EEF4FF')
              .borderRadius(16)
              .margin({ top: 12 })
          } else if (block.type === 'list') {
            Text(`- ${block.text}`)
              .fontSize(14)
              .fontColor('#344054')
              .width('100%')
              .margin({ top: 8 })
          } else if (block.type === 'quote') {
            Text(block.text)
              .fontSize(14)
              .fontColor('#475467')
              .width('100%')
              .padding({ left: 12, top: 8, bottom: 8 })
              .border({
                width: { left: 3, right: 0, top: 0, bottom: 0 },
                color: '#D0D5DD'
              })
              .margin({ top: 10 })
          } else if (block.type === 'code') {
            Text(block.text)
              .fontSize(13)
              .fontColor('#E2E8F0')
              .width('100%')
              .padding(14)
              .backgroundColor('#162033')
              .borderRadius(16)
              .margin({ top: 10 })
          } else {
            Text(block.text)
              .fontSize(14)
              .fontColor('#344054')
              .width('100%')
              .lineHeight(22)
              .margin({ top: 10 })
          }
        }, (_: MarkdownPreviewBlock, index: number): string => `${index}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 8, bottom: 18 })
    }
    .layoutWeight(1)
  }

  @Builder
  private buildSourceDrawerBody(): void {
    TextArea({
      text: this.markdownText,
      placeholder: EDITOR_WORKSPACE_COPY.sourcePlaceholder
    })
      .layoutWeight(1)
      .margin({ top: 10 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#D0D5DD' })
      .borderRadius(18)
      .padding(16)
      .onChange((value: string) => {
        this.markdownText = value;
        this.saveState = 'idle';
        if (this.supportsPagedDocumentRuntime() && this.activePageId.length > 0) {
          this.pageMarkdownDrafts.set(this.activePageId, value);
          this.dirtyPageIds.add(this.activePageId);
        }
      })
  }

  @Builder
  private buildInspectorDrawer(): void {
    Column() {
      Row() {
        Text(this.previewMode === 'preview' ? EDITOR_WORKSPACE_COPY.previewPanel : EDITOR_WORKSPACE_COPY.sourcePanel)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#162033')
        Blank()
          .layoutWeight(1)
        Button(EDITOR_WORKSPACE_COPY.close)
          .height(34)
          .backgroundColor('#F3F6FB')
          .fontColor('#162033')
          .onClick(() => {
            this.closeInspector();
          })
      }
      Row({ space: 8 }) {
        Button(EDITOR_WORKSPACE_COPY.preview)
          .height(34)
          .backgroundColor(this.previewMode === 'preview' ? '#162033' : '#F3F6FB')
          .fontColor(this.previewMode === 'preview' ? '#FFFFFF' : '#162033')
          .onClick(() => {
            this.previewMode = 'preview';
          })
        Button(EDITOR_WORKSPACE_COPY.source)
          .height(34)
          .backgroundColor(this.previewMode === 'source' ? '#162033' : '#F3F6FB')
          .fontColor(this.previewMode === 'source' ? '#FFFFFF' : '#162033')
          .onClick(() => {
            this.previewMode = 'source';
          })
      }
      .margin({ top: 12 })
      if (this.previewMode === 'preview') {
        this.buildPreviewDrawerBody()
      } else {
        this.buildSourceDrawerBody()
      }
    }
    .width(300)
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#D8E0EA' })
    .borderRadius(22)
  }

  @Builder
  private buildTracePanel(): void {
    Column() {
      Row() {
        Text(EDITOR_WORKSPACE_COPY.debugPanel)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        Blank()
          .layoutWeight(1)
        Button(EDITOR_WORKSPACE_COPY.collapse)
          .height(30)
          .backgroundColor('#263244')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.showTracePanel = false;
          })
      }
      Row({ space: 8 }) {
        Button(EDITOR_WORKSPACE_COPY.startTrace)
          .height(32)
          .enabled(this.canStartTrace())
          .backgroundColor(this.canStartTrace() ? '#1D4ED8' : '#667085')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.handleStartTrace();
          })
        Button(EDITOR_WORKSPACE_COPY.stopTrace)
          .height(32)
          .enabled(this.canStopTrace())
          .backgroundColor(this.canStopTrace() ? '#B54708' : '#667085')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.handleStopTrace();
          })
        Button(EDITOR_WORKSPACE_COPY.replayLastTrace)
          .height(32)
          .enabled(this.canReplayTrace())
          .backgroundColor(this.canReplayTrace() ? '#047857' : '#667085')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.handleReplayTrace();
          })
      }
      .margin({ top: 12 })
      Text(`${EDITOR_WORKSPACE_COPY.traceStatus}：${this.traceStatusText()}`)
        .fontSize(12)
        .fontColor('#E2E8F0')
        .margin({ top: 10 })
      Text(`${EDITOR_WORKSPACE_COPY.tracePath}：${this.tracePathText()}`)
        .fontSize(11)
        .fontColor('#CBD5E1')
        .margin({ top: 6 })
        .maxLines(3)
      Text(`${EDITOR_WORKSPACE_COPY.traceSampleCount}：${this.traceSampleCountText()}`)
        .fontSize(11)
        .fontColor('#CBD5E1')
        .margin({ top: 4 })
      if (!this.isTraceSupported()) {
        Text(EDITOR_WORKSPACE_COPY.traceUnsupported)
          .fontSize(11)
          .fontColor('#F8FAFC')
          .margin({ top: 6 })
        Text(`stubReason=${this.stubReasonText()}`)
          .fontSize(11)
          .fontColor('#CBD5E1')
          .margin({ top: 4 })
      }
      if (this.traceActionMessage.length > 0) {
        Text(`${EDITOR_WORKSPACE_COPY.recentAction}：${this.traceActionMessage}`)
          .fontSize(11)
          .fontColor('#F8FAFC')
          .margin({ top: 6 })
      }
      Scroll() {
        Text(this.debugStateText)
          .fontSize(11)
          .fontColor('#CBD5E1')
          .width('100%')
      }
      .height(156)
      .margin({ top: 12 })
    }
    .width(430)
    .padding(16)
    .backgroundColor('#0F172A')
    .border({ width: 1, color: '#334155' })
    .borderRadius(22)
  }

  @Builder
  private buildPageRail(): void {
    Column() {
      Row() {
        Text(this.selectedPageLabel())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#667085')
          .layoutWeight(1)
        if (this.canAddRealPages()) {
          Button('+')
            .width(24)
            .height(24)
            .fontSize(14)
            .backgroundColor('#FFFFFF')
            .fontColor('#162033')
            .onClick(() => {
              this.addPage();
            })
        }
      }
      .margin({ bottom: 8 })
      Scroll() {
        Column() {
          ForEach(this.pageIndexes(), (pageIndex: number) => {
            Column() {
              PreviewThumbnail({
                previewSnapshot: this.document?.previewSnapshot,
                fallbackSummary: this.document?.previewSummary ?? '',
                thumbnailWidth: 56,
                thumbnailHeight: 78
              })
              Text(`${pageIndex + 1}`)
                .fontSize(10)
                .fontColor(this.isSelectedPageIndex(pageIndex) ? '#0F766E' : '#667085')
                .margin({ top: 4 })
              if (this.canDeleteCurrentPage() && this.isSelectedPageIndex(pageIndex)) {
                Button('-')
                  .width(24)
                  .height(18)
                  .margin({ top: 6 })
                  .fontSize(12)
                  .backgroundColor('#FDECEC')
                  .fontColor('#B42318')
                  .onClick(() => {
                    this.deleteCurrentPage();
                  })
              }
            }
            .width('100%')
            .padding({ top: 6, bottom: 6, left: 4, right: 4 })
            .margin({ bottom: 6 })
            .backgroundColor(this.isSelectedPageIndex(pageIndex) ? '#E8F5F3' : '#FFFFFF')
            .border({
              width: this.isSelectedPageIndex(pageIndex) ? 2 : 1,
              color: this.isSelectedPageIndex(pageIndex) ? '#0F766E' : '#D8E0EA'
            })
            .borderRadius(12)
            .onClick(() => {
              this.selectPage(pageIndex);
            })
          }, (pageIndex: number): string => this.pageKeyAt(pageIndex))
        }
      }
      .layoutWeight(1)
    }
    .width(82)
    .height('100%')
    .padding(6)
    .backgroundColor('#F7F9FC')
    .border({ width: 1, color: '#D8E0EA' })
    .borderRadius(18)
  }

  build() {
    Stack() {
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
          Text(EDITOR_WORKSPACE_COPY.openingEditor)
            .fontSize(14)
            .fontColor('#667085')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#EEF2F8')
      } else if (this.errorMessage.length > 0 || !this.document) {
        Column() {
          Text(EDITOR_WORKSPACE_COPY.openDocumentFailed)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#162033')
          Text(this.errorMessage.length > 0 ? this.errorMessage : EDITOR_WORKSPACE_COPY.documentNotFound)
            .fontSize(13)
            .fontColor('#B42318')
            .margin({ top: 10, bottom: 18 })
          Button(EDITOR_WORKSPACE_COPY.returnLibrary)
            .height(40)
            .backgroundColor('#162033')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.goBack();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#EEF2F8')
      } else {
        Row() {
          Stack() {
            this.buildWritingSurface()
            Row() {
              this.buildHeaderBar()
              Blank()
                .layoutWeight(1)
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .padding({ top: 8, left: 8, right: 8 })
            .hitTestBehavior(HitTestMode.Transparent)
            Row() {
              Blank()
                .layoutWeight(1)
                .hitTestBehavior(HitTestMode.None)
              this.buildFloatingToolbar()
              Blank()
                .layoutWeight(1)
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .padding({ top: 8, left: 72, right: 72 })
            .hitTestBehavior(HitTestMode.Transparent)
            if (this.shouldUseSimulatorStubUi()) {
              Row() {
                Blank()
                  .layoutWeight(1)
                  .hitTestBehavior(HitTestMode.None)
                this.buildStubBadge()
              }
              .width('100%')
              .padding({ top: 48, left: 8, right: 8 })
              .hitTestBehavior(HitTestMode.Transparent)
            }
            if (this.showInspectorDrawer) {
              Row() {
                Blank()
                  .layoutWeight(1)
                this.buildInspectorDrawer()
              }
              .width('100%')
              .height('100%')
              .padding({ top: 76, right: 8, bottom: 8, left: 8 })
            }
            if (this.showTracePanel) {
              Column() {
                Blank()
                  .layoutWeight(1)
                Row() {
                  this.buildTracePanel()
                  Blank()
                    .layoutWeight(1)
                }
              }
              .width('100%')
              .height('100%')
              .padding({ top: 96, right: 8, bottom: 8, left: 8 })
            }
            Row() {
              this.buildBackHitTarget()
              Blank()
                .layoutWeight(1)
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .padding({ top: 8, left: 8, right: 8 })
            .hitTestBehavior(HitTestMode.Transparent)
          }
          .layoutWeight(1)
          .height('100%')
          .margin({ right: 8 })
          .backgroundColor('#F4F7FB')
          .borderRadius(22)
          this.buildPageRail()
        }
        .width('100%')
        .height('100%')
        .padding(8)
        .backgroundColor('#E9EEF5')
      }
    }
  }
}
