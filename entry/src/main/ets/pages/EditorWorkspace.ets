import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import nativeModule from 'libentry.so';
import { PreviewThumbnail } from '../components/PreviewThumbnail';
import {
  buildNativeOpenDocumentConfig,
  buildNativePageContractForEntry,
  buildNativePreviewRequestSize,
  NativePreviewBounds,
  NativePreviewPage,
  NativePreviewPayload,
  NativeSceneObject,
  NativeSceneSnapshot
} from '../models/NativeNoteContracts';
import {
  DOCUMENT_MODE_LABELS,
  DOCUMENT_TYPE_LABELS,
  DocumentEmbeddedBlock,
  DocumentEmbeddedBlockBounds,
  DocumentEmbeddedBlockKind,
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

function clampToRange(value: number, minValue: number, maxValue: number): number {
  return Math.min(maxValue, Math.max(minValue, value));
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
  simulatorZoom: string;
  zoomOut: string;
  zoomIn: string;
  resetZoom: string;
  traceUnsupported: string;
  recentAction: string;
  openingEditor: string;
  openDocumentFailed: string;
  documentNotFound: string;
  returnLibrary: string;
  sourcePlaceholder: string;
}

interface GestureRatioPoint {
  xRatio: number;
  yRatio: number;
}

interface SimulatorCanvasFrame {
  frameX: number;
  frameY: number;
  frameWidth: number;
  frameHeight: number;
  contentX: number;
  contentY: number;
  contentWidth: number;
  contentHeight: number;
}

interface SimulatorFingerGestureTarget {
  pageIndex: number;
  point: GestureRatioPoint;
}

type EmbeddedOverlayDraft = DocumentEmbeddedBlock;
type SingleFingerPanMode = 'disabled' | 'vertical' | 'free';
type PageRailFilter = 'all' | 'bookmarked' | 'notes';
type ToolbarSnapSlot = 'top-center' | 'left-middle' | 'right-middle' | 'bottom-center';
type EditorUiIcon =
  'back' |
  'drag' |
  'pen' |
  'pencil' |
  'highlighter' |
  'eraser' |
  'text' |
  'lasso' |
  'fingerWriting' |
  'undo' |
  'redo' |
  'more' |
  'railCollapse' |
  'railExpand' |
  'addPage' |
  'bookmark';

const PAGE_RAIL_FILTER_OPTIONS: PageRailFilter[] = ['all', 'bookmarked', 'notes'];
const EDITOR_HOME_ROUTE: string = 'pages/Index';
const BACK_HIT_TARGET_WIDTH: number = 156;
const BACK_HIT_TARGET_HEIGHT: number = 56;
const NATIVE_PAGE_METHOD_SET_ACTIVE: string = 'setActivePage';
const NATIVE_PAGE_METHOD_INSERT: string = 'insertPage';
const NATIVE_PAGE_METHOD_DELETE: string = 'deletePage';
const EDITOR_INSPECTOR_WIDTH: number = 688;
const EDITOR_PAGE_RAIL_WIDTH: number = 156;
const EDITOR_PAGE_RAIL_COLLAPSED_WIDTH: number = 68;
const PAGE_RAIL_THUMBNAIL_WIDTH: number = 104;
const PAGE_RAIL_THUMBNAIL_HEIGHT: number = 142;
const PAGE_RAIL_MENU_WIDTH: number = 176;
const PAGE_RAIL_ACTION_BUTTON_SIZE: number = 30;
const PAGE_RAIL_CARD_RADIUS: number = 16;
const PAGE_RAIL_PAGE_MENU_BUTTON_SIZE: number = 26;
const FLOATING_TOOLBAR_WIDTH: number = 428;
const FLOATING_TOOLBAR_VERTICAL_WIDTH: number = 116;
const FLOATING_TOOL_BUTTON_SIZE: number = 36;
const FLOATING_TOOLBAR_MORE_BUTTON_SIZE: number = 34;
const FLOATING_TOOLBAR_COLOR_CHIP_SIZE: number = 16;
const AUTOSAVE_DEBOUNCE_MS: number = 900;
const PAGE_SWIPE_DRAG_LIMIT: number = 132;
const PAGE_SWIPE_TRIGGER_DISTANCE: number = 84;
const PAGE_STACK_GAP: number = 28;
const PAGE_STACK_SIDE_PADDING: number = 28;
const PAGE_STACK_VERTICAL_PADDING: number = 42;
const PAGE_STACK_MIN_ZOOM: number = 0.72;
const PAGE_STACK_MAX_ZOOM: number = 1.95;
const PAGE_STACK_BOUNDARY_PADDING: number = 28;
const TOOLBAR_DRAG_BOUNDARY: number = 36;
const EMBED_SELECTION_MIN_SIZE: number = 32;
const VIEWPORT_INERTIA_FRAME_MS: number = 16;
const VIEWPORT_INERTIA_FRICTION: number = 0.88;
const VIEWPORT_INERTIA_MIN_SPEED: number = 0.02;
const VIEWPORT_HORIZONTAL_OVERFLOW_THRESHOLD: number = 12;
const EDITOR_WORKSPACE_COPY: EditorWorkspaceCopy = {
  back: '返回',
  save: '保存',
  undo: '撤销',
  redo: '重做',
  toolPen: '钢笔',
  toolPencil: '铅笔',
  toolHighlighter: '荧光笔',
  toolEraser: '橡皮',
  toolLasso: '套索',
  toolText: '文字',
  toolHand: '手指写',
  collapseOptions: '收起选项',
  more: '更多',
  collapsePanel: '收起面板',
  openPanel: '展开面板',
  render: '渲染',
  mode: '模式',
  placeholder: '占位',
  longPressCollapseDebugPanel: '长按画布可收起调试面板',
  longPressExpandTracePanel: '长按画布可展开调试面板',
  formula: '公式',
  previewPanel: '预览面板',
  sourcePanel: '源码面板',
  close: '关闭',
  preview: '预览',
  source: '源码',
  debugPanel: '调试面板',
  collapse: '收起',
  startTrace: '开始录制',
  stopTrace: '停止录制',
  replayLastTrace: '回放上次记录',
  traceStatus: '状态',
  tracePath: '路径',
  traceSampleCount: '采样数',
  simulatorZoom: '模拟器缩放',
  zoomOut: '缩小',
  zoomIn: '放大',
  resetZoom: '重置',
  traceUnsupported: '当前模拟器模式不支持轨迹录制与回放，因此相关控件保持禁用。',
  recentAction: '最近操作',
  openingEditor: '正在打开编辑器...',
  openDocumentFailed: '无法打开文档',
  documentNotFound: '未找到文档',
  returnLibrary: '返回笔记库',
  sourcePlaceholder: '输入图文与公式，例如 $x^2$ 或 $\\int_0^1 x dx$'
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
  private autosaveTimerId: number = -1;
  private lastNativeMutationSignature: string = '';
  private contentMutationVersion: number = 0;
  private lastPersistedContentMutationVersion: number = 0;
  private pageSelectionInFlight: boolean = false;
  private pageViewportInitialized: boolean = false;
  private toolbarDragOriginX: number = 0;
  private toolbarDragOriginY: number = 0;
  private viewportPanOriginX: number = 0;
  private viewportPanOriginY: number = 0;
  private viewportPanLastOffsetX: number = 0;
  private viewportPanLastOffsetY: number = 0;
  private viewportPanLastTimestamp: number = 0;
  private viewportPanVelocityX: number = 0;
  private viewportPanVelocityY: number = 0;
  private viewportInertiaTimerId: number = -1;
  private viewportInertiaResolve: (() => void) | null = null;
  private viewportPinchOriginScale: number = 1;
  private simulatorFingerGestureActive: boolean = false;
  private simulatorFingerGesturePageIndex: number = -1;
  private simulatorFingerGestureLastXRatio: number = 0.5;
  private simulatorFingerGestureLastYRatio: number = 0.5;
  private pageHudAutoHideToken: number = 0;
  private embeddedSelectionOriginX: number = 0;
  private embeddedSelectionOriginY: number = 0;
  private readonly embeddedOverlaysByPage: Map<string, EmbeddedOverlayDraft[]> = new Map<string, EmbeddedOverlayDraft[]>();
  private readonly pageBookmarkIds: Set<string> = new Set<string>();

  @State private loading: boolean = true;
  @State private errorMessage: string = '';
  @State private document: DocumentRecord | null = null;
  @State private markdownText: string = '';
  @State private previewMode: 'preview' | 'source' = 'preview';
  @State private showInspectorDrawer: boolean = false;
  @State private showToolExtras: boolean = true;
  @State private activePageId: string = '';
  @State private activePageIndex: number = 0;
  @State private pageSearchText: string = '';
  @State private pageRailFilter: PageRailFilter = 'all';
  @State private showRailFilterMenu: boolean = false;
  @State private showPageHud: boolean = false;
  @State private showPageJumpInput: boolean = false;
  @State private pageJumpDraft: string = '';
  @State private showRailMenu: boolean = false;
  @State private openPageMenuId: string = '';
  @State private railCollapsed: boolean = false;
  @State private pageSwipeOffset: number = 0;
  @State private engineId: string = '';
  @State private currentTool: ToolType = ToolType.PEN;
  @State private currentColor: string = PALETTE_COLORS[0];
  @State private currentMode: DocumentMode = DocumentMode.PAGED;
  @State private currentBackend: RenderBackend = RenderBackend.OPEN_GLES;
  @State private debugStateText: string = '';
  @State private debugState: NativeDebugState | null = null;
  @State private simulatorSceneSnapshot: NativeSceneSnapshot | null = null;
  @State private showTracePanel: boolean = false;
  @State private traceActionMessage: string = '';
  @State private surfaceReady: boolean = false;
  @State private saveState: 'idle' | 'saving' | 'failed' = 'idle';
  @State private writingViewportWidth: number = 0;
  @State private writingViewportHeight: number = 0;
  @State private pageStackPanX: number = 0;
  @State private pageStackPanY: number = 0;
  @State private pageStackScale: number = 1;
  @State private fingerWritingEnabled: boolean = false;
  @State private floatingToolbarOffsetX: number = 0;
  @State private floatingToolbarOffsetY: number = 0;
  @State private toolbarSnapSlot: ToolbarSnapSlot = 'top-center';
  @State private overlaysVersion: number = 0;
  @State private bookmarksVersion: number = 0;
  @State private embedPlacementArmed: boolean = false;
  @State private embedSelectionVisible: boolean = false;
  @State private embedSelectionPageId: string = '';
  @State private embedSelectionX: number = 0;
  @State private embedSelectionY: number = 0;
  @State private embedSelectionWidth: number = 0;
  @State private embedSelectionHeight: number = 0;
  @State private showEmbeddedComposer: boolean = false;
  @State private embeddedComposerText: string = '';
  @State private embeddedComposerPageId: string = '';
  @State private embeddedComposerPageIndex: number = -1;
  @State private embeddedComposerPreviewVersion: number = 0;

  aboutToAppear(): void {
    if (this.bootstrapping || this.engineId.length > 0 || this.document !== null || !this.loading) {
      return;
    }
    this.bootstrap();
  }

  aboutToDisappear(): void {
    this.cancelPendingAutosave();
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
    const previousPageId: string = this.activePageId;
    if (pages.length === 0) {
      this.document = document;
      this.activePageId = '';
      this.activePageIndex = document.previewSnapshot?.pageIndex ?? 0;
      this.lastNativeMutationSignature = '';
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
      // Preserve document-level defaults; switching the active page must not rewrite
      // the fallback metadata that page-stack layout uses to derive page dimensions.
      pageTemplateId: document.pageTemplateId,
      pageSizeId: document.pageSizeId,
      paperBackgroundId: document.paperBackgroundId,
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
    if (this.activePageId !== previousPageId) {
      this.lastNativeMutationSignature = '';
    }
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
    this.applyFingerWritingState();
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
      await this.reloadDocumentEmbeddedBlocks();

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
      this.applyFingerWritingState();
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
      this.simulatorSceneSnapshot = null;
      this.lastNativeMutationSignature = '';
      return;
    }
    let state: NativeDebugState | null = this.nativeEngine.getDebugState(this.engineId);
    if (!state) {
      this.debugState = null;
      this.debugStateText = '原生调试信息不可用';
      this.simulatorSceneSnapshot = null;
      this.lastNativeMutationSignature = '';
      return;
    }
    if (
      state.runtimeProfile === 'simulator-stub' &&
      this.writingViewportWidth > 0 &&
      this.writingViewportHeight > 0 &&
      (!state.surfaceReady || state.surfaceWidth <= 0 || state.surfaceHeight <= 0)
    ) {
      this.nativeEngine.resize(this.engineId, this.writingViewportWidth, this.writingViewportHeight, 2);
      state = this.nativeEngine.getDebugState(this.engineId) ?? state;
    }
    this.fingerWritingEnabled = state.fingerWritingEnabled;
    this.debugState = state;
    this.debugStateText = `engine=${state.engineId}\n` +
      `doc=${state.activeDocumentId}\n` +
      `tool=${state.activeTool} native=${state.lastToolType}\n` +
      `fingerWrite=${state.fingerWritingEnabled}\n` +
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
    this.updateSimulatorSceneSnapshot();
    this.noteNativeStateMutationForAutosave(state);
  }

  private updateSimulatorSceneSnapshot(): void {
    if (!this.document || this.engineId.length === 0 || !this.shouldUseSimulatorStubUi()) {
      this.simulatorSceneSnapshot = null;
      return;
    }
    try {
      this.simulatorSceneSnapshot = this.nativeEngine.exportSceneSnapshot(this.engineId, this.document.id);
    } catch (_) {
      this.simulatorSceneSnapshot = null;
    }
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

  private hasPendingContentPersistence(): boolean {
    return this.contentMutationVersion > this.lastPersistedContentMutationVersion;
  }

  private markContentDirty(): void {
    this.contentMutationVersion += 1;
  }

  private markContentPersisted(version: number = this.contentMutationVersion): void {
    this.lastPersistedContentMutationVersion = Math.max(this.lastPersistedContentMutationVersion, version);
  }

  private cancelPendingAutosave(): void {
    if (this.autosaveTimerId >= 0) {
      clearTimeout(this.autosaveTimerId);
      this.autosaveTimerId = -1;
    }
  }

  private scheduleAutosave(delayMs: number = AUTOSAVE_DEBOUNCE_MS): void {
    if (this.shuttingDown || this.leavingEditor || !this.document || !this.libraryService) {
      return;
    }
    if (!this.hasPendingContentPersistence()) {
      return;
    }
    this.cancelPendingAutosave();
    this.autosaveTimerId = setTimeout(() => {
      this.autosaveTimerId = -1;
      void this.runAutosave();
    }, delayMs);
  }

  private noteDocumentMutationForAutosave(delayMs: number = AUTOSAVE_DEBOUNCE_MS): void {
    if (this.shuttingDown || this.leavingEditor || !this.document || !this.libraryService) {
      return;
    }
    this.markContentDirty();
    if (this.saveState !== 'saving') {
      this.saveState = 'idle';
    }
    this.scheduleAutosave(delayMs);
  }

  private noteNativeStateMutationForAutosave(state: NativeDebugState): void {
    const nextSignature: string = `${state.committedStrokeCount}:${state.undoDepth}:${state.redoDepth}`;
    if (this.lastNativeMutationSignature.length === 0) {
      this.lastNativeMutationSignature = nextSignature;
      return;
    }
    if (this.lastNativeMutationSignature === nextSignature) {
      return;
    }
    this.lastNativeMutationSignature = nextSignature;
    this.markContentDirty();
    if (this.saveState !== 'saving') {
      this.saveState = 'idle';
    }
    this.scheduleAutosave();
  }

  private async runAutosave(): Promise<void> {
    if (this.shuttingDown || this.leavingEditor || !this.document || !this.libraryService) {
      return;
    }
    if (!this.hasPendingContentPersistence()) {
      return;
    }
    if (this.persistTask) {
      this.scheduleAutosave(320);
      return;
    }
    const targetVersion: number = this.contentMutationVersion;
    this.saveState = 'saving';
    const didPersist: boolean = await this.persistDocumentState();
    this.saveState = didPersist ? 'idle' : 'failed';
    if (didPersist) {
      this.markContentPersisted(targetVersion);
      if (this.hasPendingContentPersistence()) {
        this.scheduleAutosave(320);
        return;
      }
    }
  }

  private async persistDocumentState(): Promise<boolean> {
    if (this.persistTask) {
      return await this.persistTask;
    }
    if (!this.document || !this.libraryService) {
      return false;
    }
    if (!this.hasPendingContentPersistence()) {
      return true;
    }
    this.cancelPendingAutosave();
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
        this.traceActionMessage = '保存完成';
        return true;
      } catch (error) {
        this.traceActionMessage = `保存失败 ${this.formatError(error as Object)}`;
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
    this.saveState = didPersist ? 'idle' : 'failed';
    return didPersist;
  }

  private async shutdown(): Promise<void> {
    if (this.shuttingDown) {
      await this.persistDocumentState();
      return;
    }
    this.shutdownScheduled = false;
    this.shuttingDown = true;
    this.cancelPendingAutosave();
    this.stopViewportInertia();
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
    if (tool === ToolType.HAND) {
      this.toggleFingerWritingMode();
      return;
    }
    const previousTool: ToolType = this.currentTool;
    const isSameTool: boolean = previousTool === tool;
    this.currentTool = tool;
    this.showToolExtras = isSameTool ? false : this.toolHasSecondaryControls(tool);
    if (previousTool !== tool || !this.toolUsesContextActions() || isSameTool) {
      this.clearEmbeddedPlacement();
    }
    if (this.engineId.length > 0) {
      this.nativeEngine.setTool(this.engineId, tool);
      this.refreshDebugState();
    }
  }

  private applyFingerWritingState(): void {
    this.resetSimulatorFingerGesture(true);
    if (this.engineId.length === 0) {
      return;
    }
    this.nativeEngine.setFingerWritingEnabled(this.engineId, this.fingerWritingEnabled);
  }

  private toggleFingerWritingMode(): void {
    this.fingerWritingEnabled = !this.fingerWritingEnabled;
    this.stopViewportInertia();
    this.applyFingerWritingState();
    this.refreshDebugState();
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

  private pageRailFilterLabel(filter: PageRailFilter = this.pageRailFilter): string {
    switch (filter) {
      case 'bookmarked':
        return '收藏页面';
      case 'notes':
        return '笔记页面';
      case 'all':
      default:
        return '所有页面';
    }
  }

  private pageHudLabel(): string {
    return `第 ${this.activePageIndex + 1} / ${this.pageCount()} 页`;
  }

  private keepPageHudVisible(): void {
    this.pageHudAutoHideToken += 1;
    this.showPageHud = true;
  }

  private schedulePageHudAutoHide(delayMs: number = 1200): void {
    const token: number = this.pageHudAutoHideToken + 1;
    this.pageHudAutoHideToken = token;
    setTimeout(() => {
      if (token !== this.pageHudAutoHideToken || this.showPageJumpInput || this.showRailMenu || this.showRailFilterMenu) {
        return;
      }
      if (this.openPageMenuId.length > 0) {
        return;
      }
      this.showPageHud = false;
    }, delayMs);
  }

  private pageHasNotes(index: number): boolean {
    return this.pageSceneObjectsAt(index).length > 0 ||
      this.pageEmbeddedBlocksAt(index).length > 0 ||
      this.pageMarkdownTextAt(index).trim().length > 0;
  }

  private shouldUseWideComposerLayout(): boolean {
    return this.writingViewportWidth >= 920 && this.writingViewportWidth > this.writingViewportHeight;
  }

  private embeddedComposerModalWidth(): number {
    const viewportWidth: number = this.writingViewportWidth > 0 ? this.writingViewportWidth : 760;
    if (this.shouldUseWideComposerLayout()) {
      return Math.min(980, Math.max(880, viewportWidth - 40));
    }
    return Math.min(760, Math.max(560, viewportWidth - 24));
  }

  private currentDocumentCreatedLabel(): string {
    const createdAt: number = this.document?.createdAt ?? Date.now();
    const createdDate: Date = new Date(createdAt);
    return `${createdDate.getFullYear()}年${createdDate.getMonth() + 1}月${createdDate.getDate()}日 · ` +
      `${`${createdDate.getHours()}`.padStart(2, '0')}:${`${createdDate.getMinutes()}`.padStart(2, '0')}`;
  }

  private inspectorTabLabel(mode: 'preview' | 'source'): string {
    return mode === 'source' ? EDITOR_WORKSPACE_COPY.source : EDITOR_WORKSPACE_COPY.preview;
  }

  private inspectorPanelTitle(): string {
    return this.previewMode === 'preview' ? EDITOR_WORKSPACE_COPY.previewPanel : EDITOR_WORKSPACE_COPY.source;
  }

  private pageJumpTargetIndex(): number {
    const parsed: number = Number.parseInt(this.pageJumpDraft.trim(), 10);
    if (Number.isNaN(parsed)) {
      return -1;
    }
    const index: number = parsed - 1;
    if (index < 0 || index >= this.pageCount()) {
      return -1;
    }
    return index;
  }

  private filteredPageIndexes(): number[] {
    const query: string = this.pageSearchText.trim().toLowerCase();
    return this.pageIndexes().filter((pageIndex: number) => {
      if (this.pageRailFilter === 'bookmarked' && !this.isPageBookmarked(pageIndex)) {
        return false;
      }
      if (this.pageRailFilter === 'notes' && !this.pageHasNotes(pageIndex)) {
        return false;
      }
      if (query.length === 0) {
        return true;
      }
      const pageNumber: string = `${pageIndex + 1}`;
      const title: string = this.pagePlaceholderTitle(pageIndex).toLowerCase();
      const detail: string = this.pagePlaceholderDetail(pageIndex).toLowerCase();
      const previewText: string = this.pagePreviewFallbackBlocks(pageIndex)
        .map((block: MarkdownPreviewBlock) => block.text.toLowerCase())
        .join(' ');
      return pageNumber.includes(query) || title.includes(query) || detail.includes(query) || previewText.includes(query);
    });
  }

  private openPageJumpInput(): void {
    this.showRailMenu = false;
    this.showRailFilterMenu = false;
    this.openPageMenuId = '';
    this.keepPageHudVisible();
    this.showPageJumpInput = true;
    this.pageJumpDraft = `${this.activePageIndex + 1}`;
  }

  private closePageJumpInput(): void {
    this.showPageJumpInput = false;
    this.pageJumpDraft = '';
    this.schedulePageHudAutoHide(900);
  }

  private async jumpToDraftPage(): Promise<void> {
    const targetIndex: number = this.pageJumpTargetIndex();
    if (targetIndex < 0) {
      return;
    }
    await this.focusPageInViewport(targetIndex);
    this.closePageJumpInput();
  }

  private closeRailMenus(): void {
    this.showRailMenu = false;
    this.showRailFilterMenu = false;
    this.openPageMenuId = '';
  }

  private setRailCollapsed(collapsed: boolean): void {
    this.railCollapsed = collapsed;
    this.closeRailMenus();
    this.showPageJumpInput = false;
    this.keepPageHudVisible();
    this.schedulePageHudAutoHide();
  }

  private toggleRailMenu(): void {
    this.keepPageHudVisible();
    this.showRailFilterMenu = false;
    this.showPageJumpInput = false;
    this.showRailMenu = !this.showRailMenu;
    this.openPageMenuId = '';
    if (!this.showRailMenu) {
      this.schedulePageHudAutoHide();
    }
  }

  private toggleRailFilterMenu(): void {
    if (this.railCollapsed) {
      return;
    }
    this.keepPageHudVisible();
    this.showPageJumpInput = false;
    this.showRailMenu = false;
    this.openPageMenuId = '';
    this.showRailFilterMenu = !this.showRailFilterMenu;
    if (!this.showRailFilterMenu) {
      this.schedulePageHudAutoHide();
    }
  }

  private applyRailFilter(filter: PageRailFilter): void {
    this.pageRailFilter = filter;
    this.showRailFilterMenu = false;
    this.keepPageHudVisible();
    this.schedulePageHudAutoHide();
  }

  private isPageMenuOpen(pageIndex: number): boolean {
    return this.openPageMenuId === this.pageKeyAt(pageIndex);
  }

  private async togglePageMenu(pageIndex: number): Promise<void> {
    if (this.isPageMenuOpen(pageIndex)) {
      this.openPageMenuId = '';
      return;
    }
    this.showPageJumpInput = false;
    this.showRailMenu = false;
    this.showRailFilterMenu = false;
    this.keepPageHudVisible();
    if (!this.isSelectedPageIndex(pageIndex)) {
      await this.selectPage(pageIndex);
    }
    this.openPageMenuId = this.pageKeyAt(pageIndex);
  }

  private noteUnsupportedMenuAction(label: string): void {
    this.traceActionMessage = `${label} 暂未接入`;
    this.closeRailMenus();
  }

  private async duplicateCurrentPage(): Promise<void> {
    if (!this.canAddRealPages() || !this.document || !this.libraryService || this.activePageId.length === 0) {
      return;
    }
    const sourcePageId: string = this.activePageId;
    const sourceMarkdown: string = this.pageMarkdownDrafts.get(sourcePageId) ?? this.markdownText;
    this.stageCurrentPageDraft();
    await this.persistBlankPagedRuntimePage();
    await this.libraryService.saveDocumentMarkdown(this.document.id, sourceMarkdown, sourcePageId, false);
    this.dirtyPageIds.delete(sourcePageId);
    let nextDocument: DocumentRecord = await this.libraryService.addBlankPage(this.document.id);
    this.applyDocumentActivePage(nextDocument, nextDocument.activePageId);
    this.pageMarkdownDrafts.set(this.activePageId, sourceMarkdown);
    this.markdownText = sourceMarkdown;
    nextDocument = await this.libraryService.saveDocumentMarkdown(nextDocument.id, sourceMarkdown, this.activePageId, false);
    const sourceBlocks: DocumentEmbeddedBlock[] = this.pageEmbeddedBlocks(sourcePageId);
    if (sourceBlocks.length > 0) {
      const duplicatedBlocks: DocumentEmbeddedBlock[] = sourceBlocks.map((block: DocumentEmbeddedBlock, index: number) => {
        const createdAt: number = Date.now();
        const bounds: DocumentEmbeddedBlockBounds = {
          x: block.bounds.x,
          y: block.bounds.y,
          width: block.bounds.width,
          height: block.bounds.height
        };
        const duplicatedBlock: DocumentEmbeddedBlock = {
          id: `embedded-${createdAt}-${index}`,
          kind: block.kind,
          sourceText: block.sourceText,
          bounds,
          renderMeta: block.renderMeta,
          createdAt,
          updatedAt: createdAt
        };
        return duplicatedBlock;
      });
      nextDocument = await this.libraryService.replacePageEmbeddedBlocks(nextDocument.id, this.activePageId, duplicatedBlocks, false);
    }
    this.applyDocumentActivePage(nextDocument, nextDocument.activePageId);
    await this.loadPageMarkdown(this.activePageId);
    await this.reloadDocumentEmbeddedBlocks();
    this.syncViewportToActivePage(true);
    if (!this.notifyNativeActivePage(this.activePageId)) {
      await this.primeBlankPagedRuntime(this.activePageId);
      await this.reopenNativeDocumentForCurrentState();
    }
    this.refreshDebugState();
    this.closeRailMenus();
  }

  private async clearCurrentPageContent(): Promise<void> {
    if (!this.document || !this.libraryService || this.activePageId.length === 0) {
      return;
    }
    this.cancelPendingAutosave();
    this.markdownText = '';
    this.pageMarkdownDrafts.set(this.activePageId, '');
    this.dirtyPageIds.add(this.activePageId);
    await this.libraryService.saveDocumentMarkdown(this.document.id, '', this.activePageId, false);
    await this.libraryService.clearPageEmbeddedBlocks(this.document.id, this.activePageId, false);
    this.dirtyPageIds.delete(this.activePageId);
    this.markContentPersisted();
    await this.reloadDocumentEmbeddedBlocks();
    this.saveState = 'idle';
    this.traceActionMessage = '页面已清空';
    this.closeRailMenus();
  }

  private canSwipeBetweenPages(): boolean {
    return this.shouldUseSimulatorStubUi() && this.supportsPagedDocumentRuntime() && this.pageCount() > 1;
  }

  private updatePageSwipeOffset(offsetY: number): void {
    if (!this.canSwipeBetweenPages() || this.pageSelectionInFlight) {
      this.pageSwipeOffset = 0;
      return;
    }
    this.pageSwipeOffset = clampToRange(offsetY, -PAGE_SWIPE_DRAG_LIMIT, PAGE_SWIPE_DRAG_LIMIT);
  }

  private async finishPageSwipe(offsetY: number): Promise<void> {
    const clampedOffset: number = clampToRange(offsetY, -PAGE_SWIPE_DRAG_LIMIT, PAGE_SWIPE_DRAG_LIMIT);
    if (!this.canSwipeBetweenPages() || this.pageSelectionInFlight || Math.abs(clampedOffset) < PAGE_SWIPE_TRIGGER_DISTANCE) {
      this.pageSwipeOffset = 0;
      return;
    }
    const delta: number = clampedOffset < 0 ? 1 : -1;
    const nextIndex: number = clampToRange(this.activePageIndex + delta, 0, this.pageCount() - 1);
    if (nextIndex === this.activePageIndex) {
      this.pageSwipeOffset = 0;
      return;
    }
    await this.selectPage(nextIndex);
    this.pageSwipeOffset = 0;
  }

  private async setMode(mode: DocumentMode): Promise<void> {
    if (!this.canChangeDocumentMode() && mode !== this.currentMode) {
      return;
    }
    this.cancelPendingAutosave();
    if (this.document && this.libraryService && this.isBlankPagedEditable() && mode !== DocumentMode.PAGED &&
      this.hasPendingContentPersistence()) {
      this.stageCurrentPageDraft();
      await this.persistBlankPagedRuntimePage();
      if (this.activePageId.length > 0) {
        const currentMarkdown: string = this.pageMarkdownDrafts.get(this.activePageId) ?? this.markdownText;
        await this.libraryService.saveDocumentMarkdown(this.document.id, currentMarkdown, this.activePageId, false);
      }
      this.markContentPersisted();
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

  private shouldHandleSimulatorFingerWritingGesture(): boolean {
    return this.shouldUseSimulatorStubUi() &&
      this.fingerWritingEnabled &&
      !this.embedPlacementArmed &&
      !this.showEmbeddedComposer &&
      !this.showInspectorDrawer &&
      !this.toolUsesContextActions();
  }

  private canHandleSingleFingerSurfaceGesture(): boolean {
    return this.canSingleFingerPanViewport() || this.shouldHandleSimulatorFingerWritingGesture();
  }

  private syncSimulatorStubViewportSize(): void {
    if (
      this.engineId.length === 0 ||
      !this.shouldUseSimulatorStubUi() ||
      this.writingViewportWidth <= 0 ||
      this.writingViewportHeight <= 0
    ) {
      return;
    }
    this.nativeEngine.resize(this.engineId, this.writingViewportWidth, this.writingViewportHeight, 2);
  }

  private isTraceSupported(): boolean {
    return this.debugState?.traceSupported ?? false;
  }

  private nudgeSimulatorZoom(step: number): void {
    const nextScale: number = clampToRange(this.pageStackScale + step, PAGE_STACK_MIN_ZOOM, PAGE_STACK_MAX_ZOOM);
    this.pageStackScale = nextScale;
    this.pageStackPanX = this.clampedPageStackPanX(this.pageStackPanX);
    this.pageStackPanY = this.clampedPageStackPanY(this.pageStackPanY);
    this.traceActionMessage = `模拟器缩放 ${nextScale.toFixed(2)}x`;
  }

  private resetSimulatorZoom(): void {
    this.pageStackScale = 1;
    this.pageStackPanX = this.clampedPageStackPanX(0);
    this.pageStackPanY = this.clampedPageStackPanY(this.pageFocusTargetPanY(this.activePageIndex));
    this.traceActionMessage = '模拟器缩放已重置';
  }

  private simulatorCapabilitySummary(): string {
    const state: NativeDebugState | null = this.debugState;
    if (!state) {
      return 'trace=false preview=false scene=false';
    }
    return `trace=${state.traceSupported} preview=${state.previewRenderSupported} scene=${state.sceneExportSupported}`;
  }

  private simulatorPage(): NativePreviewPage | null {
    const scene: NativeSceneSnapshot | null = this.simulatorSceneSnapshot;
    if (!scene) {
      return null;
    }
    const activePageId: string = this.activePageId.length > 0 ? this.activePageId : (scene.pages[0]?.pageId ?? '');
    return scene.pages.find((page: NativePreviewPage) => page.pageId === activePageId) ?? scene.pages[0] ?? null;
  }

  private simulatorPageWidth(): number {
    const page: NativePreviewPage | null = this.simulatorPage();
    const bounds: NativePreviewBounds | undefined = page?.bounds;
    const boundedWidth: number = bounds ? Math.max(0, bounds.maxX - bounds.minX) : 0;
    const width: number = Number(page?.width ?? boundedWidth);
    return width > 0 ? width : 612;
  }

  private simulatorPageHeight(): number {
    const page: NativePreviewPage | null = this.simulatorPage();
    const bounds: NativePreviewBounds | undefined = page?.bounds;
    const boundedHeight: number = bounds ? Math.max(0, bounds.maxY - bounds.minY) : 0;
    const height: number = Number(page?.height ?? boundedHeight);
    return height > 0 ? height : 792;
  }

  private simulatorCanvasFrame(index: number): SimulatorCanvasFrame {
    const renderedWidth: number = this.renderedWritingPageWidth(index);
    const renderedHeight: number = this.renderedWritingPageHeight(index);
    const contentInsetX: number = clampToRange(renderedWidth * 0.028, 10, 18);
    const contentInsetY: number = clampToRange(renderedHeight * 0.03, 12, 20);
    const frame: SimulatorCanvasFrame = {
      frameX: 0,
      frameY: 0,
      frameWidth: renderedWidth,
      frameHeight: renderedHeight,
      contentX: contentInsetX,
      contentY: contentInsetY,
      contentWidth: Math.max(120, renderedWidth - (contentInsetX * 2)),
      contentHeight: Math.max(180, renderedHeight - (contentInsetY * 2))
    };
    return frame;
  }

  private activeSimulatorCanvasFrame(): SimulatorCanvasFrame {
    return this.simulatorCanvasFrame(this.activePageIndex);
  }

  private simulatorObjectsForActivePage(): NativeSceneObject[] {
    const scene: NativeSceneSnapshot | null = this.simulatorSceneSnapshot;
    if (!scene) {
      return [];
    }
    const activePageId: string = this.activePageId.length > 0 ? this.activePageId : (scene.pages[0]?.pageId ?? '');
    return scene.objects.filter((object: NativeSceneObject) => (object.pageId ?? '') === activePageId && object.layer === 'ink');
  }

  private simulatorObjectX(object: NativeSceneObject): number {
    const frame: SimulatorCanvasFrame = this.simulatorCanvasFrame(this.activePageIndex);
    const pageWidth: number = this.simulatorPageWidth();
    return frame.contentX +
      clampToRange((object.bounds.minX / pageWidth) * frame.contentWidth, 0, frame.contentWidth - 28);
  }

  private simulatorObjectY(object: NativeSceneObject): number {
    const frame: SimulatorCanvasFrame = this.simulatorCanvasFrame(this.activePageIndex);
    const pageHeight: number = this.simulatorPageHeight();
    return frame.contentY +
      clampToRange((object.bounds.minY / pageHeight) * frame.contentHeight, 0, frame.contentHeight - 22);
  }

  private simulatorObjectWidth(object: NativeSceneObject): number {
    const frame: SimulatorCanvasFrame = this.simulatorCanvasFrame(this.activePageIndex);
    const pageWidth: number = this.simulatorPageWidth();
    const widthRatio: number = Math.max(0, object.bounds.maxX - object.bounds.minX) / pageWidth;
    return clampToRange(widthRatio * frame.contentWidth, 34, frame.contentWidth - 4);
  }

  private simulatorObjectHeight(object: NativeSceneObject): number {
    const frame: SimulatorCanvasFrame = this.simulatorCanvasFrame(this.activePageIndex);
    const pageHeight: number = this.simulatorPageHeight();
    const heightRatio: number = Math.max(0, object.bounds.maxY - object.bounds.minY) / pageHeight;
    return clampToRange(heightRatio * frame.contentHeight, 20, Math.max(32, frame.contentHeight * 0.22));
  }

  private simulatorPageFillColor(): string {
    const backgroundId: string = this.simulatorPage()?.backgroundId ?? '';
    if (backgroundId.startsWith('pdf/')) {
      return '#F8FAFC';
    }
    if (backgroundId.includes('warm')) {
      return '#FFF7E8';
    }
    return '#FFFDF8';
  }

  private simulatorPageAccentColor(): string {
    const backgroundId: string = this.simulatorPage()?.backgroundId ?? '';
    if (backgroundId.startsWith('pdf/')) {
      return '#CBD5E1';
    }
    return '#D8DEE8';
  }

  private simulatorGuideLabel(): string {
    const guideKind: string = this.simulatorPage()?.guideKind ?? 'plain';
    const backgroundId: string = this.simulatorPage()?.backgroundId ?? 'paper';
    return `${guideKind} · ${backgroundId}`;
  }

  private simulatorGuideKind(): string {
    return this.simulatorPage()?.guideKind ?? 'plain';
  }

  private simulatorObjectLabel(object: NativeSceneObject): string {
    const pageNumber: number = (object.pageIndex ?? this.activePageIndex) + 1;
    return `${object.tool} · p${pageNumber}`;
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
      this.traceActionMessage = ok ? '正在录制' : '开始录制失败';
    } catch (_) {
      this.traceActionMessage = '开始录制失败';
    }
    this.refreshDebugState();
  }

  private handleStopTrace(): void {
    if (!this.canStopTrace()) {
      return;
    }
    try {
      const result: TraceActionResult | null = this.nativeEngine.stopInputTraceRecording(this.engineId);
      this.updateTraceActionMessage(result, '停止录制失败');
    } catch (_) {
      this.traceActionMessage = '停止录制失败';
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
      this.updateTraceActionMessage(result, '回放失败');
    } catch (_) {
      this.traceActionMessage = '回放失败';
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

  private pageContentAspectRatio(index: number): number {
    const width: number = Math.max(1, this.pageSceneWidthAt(index));
    const height: number = Math.max(1, this.pageSceneHeightAt(index));
    return height / width;
  }

  private baseWritingPageWidth(): number {
    if (this.writingViewportWidth <= 0) {
      return 620;
    }
    return clampToRange(this.writingViewportWidth - (PAGE_STACK_SIDE_PADDING * 2), 280, 860);
  }

  private renderedWritingPageWidth(index: number): number {
    return Math.max(240, this.baseWritingPageWidth() * this.pageStackScale);
  }

  private renderedWritingPageHeight(index: number): number {
    return Math.max(320, this.renderedWritingPageWidth(index) * this.pageContentAspectRatio(index));
  }

  private pageStackGap(): number {
    return PAGE_STACK_GAP * this.pageStackScale;
  }

  private pageTopOffsetAt(index: number): number {
    let top: number = PAGE_STACK_VERTICAL_PADDING;
    for (let cursor = 0; cursor < index; cursor += 1) {
      top += this.renderedWritingPageHeight(cursor) + this.pageStackGap();
    }
    return top;
  }

  private totalPageStackHeight(): number {
    const count: number = this.pageCount();
    if (count <= 0) {
      return this.writingViewportHeight;
    }
    let totalHeight: number = PAGE_STACK_VERTICAL_PADDING * 2;
    for (let index = 0; index < count; index += 1) {
      totalHeight += this.renderedWritingPageHeight(index);
      if (index < count - 1) {
        totalHeight += this.pageStackGap();
      }
    }
    return totalHeight;
  }

  private widestRenderedPageWidth(): number {
    let width: number = this.baseWritingPageWidth() * this.pageStackScale;
    for (let index = 0; index < this.pageCount(); index += 1) {
      width = Math.max(width, this.renderedWritingPageWidth(index));
    }
    return width;
  }

  private clampedPageStackPanX(value: number): number {
    if (this.writingViewportWidth <= 0) {
      return value;
    }
    const contentWidth: number = this.widestRenderedPageWidth();
    const overflow: number = Math.max(0, (contentWidth - this.writingViewportWidth) / 2);
    return clampToRange(value, -(overflow + PAGE_STACK_BOUNDARY_PADDING), overflow + PAGE_STACK_BOUNDARY_PADDING);
  }

  private clampedPageStackPanY(value: number): number {
    if (this.writingViewportHeight <= 0) {
      return value;
    }
    const contentHeight: number = this.totalPageStackHeight();
    if (contentHeight + (PAGE_STACK_BOUNDARY_PADDING * 2) <= this.writingViewportHeight) {
      return (this.writingViewportHeight - contentHeight) / 2;
    }
    const minPanY: number = this.writingViewportHeight - contentHeight - PAGE_STACK_BOUNDARY_PADDING;
    const maxPanY: number = PAGE_STACK_BOUNDARY_PADDING;
    return clampToRange(value, minPanY, maxPanY);
  }

  private pageCardOffsetX(index: number): number {
    return ((this.writingViewportWidth - this.renderedWritingPageWidth(index)) / 2) + this.pageStackPanX;
  }

  private pageCardOffsetY(index: number): number {
    return this.pageTopOffsetAt(index) + this.pageStackPanY;
  }

  private pageFocusTargetPanY(index: number): number {
    return (this.writingViewportHeight / 2) - (this.pageTopOffsetAt(index) + (this.renderedWritingPageHeight(index) / 2));
  }

  private nearestPageIndexToViewportCenter(): number {
    let nearestIndex: number = this.activePageIndex;
    let nearestDistance: number = Number.MAX_VALUE;
    const viewportCenterY: number = this.writingViewportHeight / 2;
    this.pageIndexes().forEach((pageIndex: number) => {
      const pageCenterY: number = this.pageTopOffsetAt(pageIndex) +
        (this.renderedWritingPageHeight(pageIndex) / 2) +
        this.pageStackPanY;
      const distance: number = Math.abs(pageCenterY - viewportCenterY);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = pageIndex;
      }
    });
    return nearestIndex;
  }

  private nearestPageIndexToViewportPoint(localX: number, localY: number): number {
    let nearestIndex: number = this.activePageIndex;
    let nearestDistance: number = Number.MAX_VALUE;
    const pageIndexes: number[] = this.pageIndexes();
    for (let offset: number = 0; offset < pageIndexes.length; offset += 1) {
      const pageIndex: number = pageIndexes[offset];
      const pageLeft: number = this.pageCardOffsetX(pageIndex);
      const pageTop: number = this.pageCardOffsetY(pageIndex);
      const pageRight: number = pageLeft + this.renderedWritingPageWidth(pageIndex);
      const pageBottom: number = pageTop + this.renderedWritingPageHeight(pageIndex);
      const clampedX: number = clampToRange(localX, pageLeft, pageRight);
      const clampedY: number = clampToRange(localY, pageTop, pageBottom);
      const deltaX: number = localX - clampedX;
      const deltaY: number = localY - clampedY;
      const distance: number = (deltaX * deltaX) + (deltaY * deltaY);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = pageIndex;
        if (distance === 0) {
          return nearestIndex;
        }
      }
    }
    return nearestIndex;
  }

  private syncSimulatorGestureActivePage(pageIndex: number): void {
    if (!this.supportsPagedDocumentRuntime() || pageIndex === this.activePageIndex) {
      return;
    }
    const nextPage: DocumentPageEntry | undefined = this.pageEntryAt(pageIndex);
    if (!nextPage || !this.document) {
      return;
    }
    this.applyDocumentActivePage(this.document, nextPage.id);
    this.pageJumpDraft = `${pageIndex + 1}`;
    if (this.notifyNativeActivePage(nextPage.id)) {
      this.refreshDebugState();
    }
  }

  private async settleViewportToNearestPage(): Promise<void> {
    const clampedX: number = this.clampedPageStackPanX(this.pageStackPanX);
    const clampedY: number = this.clampedPageStackPanY(this.pageStackPanY);
    if (clampedX !== this.pageStackPanX) {
      this.pageStackPanX = clampedX;
    }
    if (clampedY !== this.pageStackPanY) {
      this.pageStackPanY = clampedY;
    }
    const nearestIndex: number = this.nearestPageIndexToViewportCenter();
    if (nearestIndex !== this.activePageIndex) {
      await this.selectPage(nearestIndex);
    }
  }

  private async syncViewportAfterGesture(): Promise<void> {
    const clampedX: number = this.clampedPageStackPanX(this.pageStackPanX);
    const clampedY: number = this.clampedPageStackPanY(this.pageStackPanY);
    if (clampedX !== this.pageStackPanX) {
      this.pageStackPanX = clampedX;
    }
    if (clampedY !== this.pageStackPanY) {
      this.pageStackPanY = clampedY;
    }
    const nearestIndex: number = this.nearestPageIndexToViewportCenter();
    if (nearestIndex !== this.activePageIndex) {
      await this.selectPage(nearestIndex);
    }
  }

  private async focusPageInViewport(index: number): Promise<void> {
    await this.selectPage(index);
    this.pageStackPanY = this.clampedPageStackPanY(this.pageFocusTargetPanY(index));
    this.pageStackPanX = this.clampedPageStackPanX(this.pageStackPanX);
    this.keepPageHudVisible();
    this.schedulePageHudAutoHide();
  }

  private syncViewportToActivePage(forceFocus: boolean = false): void {
    if (this.writingViewportWidth <= 0 || this.writingViewportHeight <= 0) {
      return;
    }
    this.stopViewportInertia();
    if (!this.pageViewportInitialized || forceFocus) {
      this.pageStackPanX = this.clampedPageStackPanX(0);
      this.pageStackPanY = this.clampedPageStackPanY(this.pageFocusTargetPanY(this.activePageIndex));
      this.pageViewportInitialized = true;
      return;
    }
    this.pageStackPanX = this.clampedPageStackPanX(this.pageStackPanX);
    this.pageStackPanY = this.clampedPageStackPanY(this.pageStackPanY);
  }

  private updateWritingViewportSize(newValue: Object): void {
    const width: number = parseAreaValue((newValue as Record<string, Object>).width);
    const height: number = parseAreaValue((newValue as Record<string, Object>).height);
    if (width <= 0 || height <= 0) {
      return;
    }
    this.writingViewportWidth = width;
    this.writingViewportHeight = height;
    this.syncSimulatorStubViewportSize();
    this.syncViewportToActivePage();
    this.floatingToolbarOffsetX = 0;
    this.floatingToolbarOffsetY = 0;
  }

  private toolUsesColorPalette(): boolean {
    return this.currentTool === ToolType.PEN ||
      this.currentTool === ToolType.PENCIL ||
      this.currentTool === ToolType.HIGHLIGHTER;
  }

  private toolUsesContextActions(): boolean {
    return this.currentTool === ToolType.TEXT || this.currentTool === ToolType.LASSO;
  }

  private toolHasSecondaryControls(tool: ToolType): boolean {
    return tool === ToolType.PEN ||
      tool === ToolType.PENCIL ||
      tool === ToolType.HIGHLIGHTER ||
      tool === ToolType.TEXT ||
      tool === ToolType.LASSO;
  }

  private shouldShowSecondaryToolbar(): boolean {
    return this.showToolExtras && this.toolHasSecondaryControls(this.currentTool);
  }

  private secondaryToolbarAssistText(): string {
    return this.toolLabel(this.currentTool);
  }

  private secondaryToolbarHintText(): string {
    if (this.currentTool === ToolType.TEXT) {
      return this.embedPlacementArmed ? '在当前页拖出放置区域' : '放置图文块';
    }
    if (this.currentTool === ToolType.LASSO) {
      return this.embedPlacementArmed ? '在当前页拖出混排区域' : '套索后可插入图文块';
    }
    return '颜色';
  }

  private toolIconKind(tool: ToolType): EditorUiIcon {
    switch (tool) {
      case ToolType.PEN:
        return 'pen';
      case ToolType.PENCIL:
        return 'pencil';
      case ToolType.HIGHLIGHTER:
        return 'highlighter';
      case ToolType.ERASER:
        return 'eraser';
      case ToolType.LASSO:
        return 'lasso';
      case ToolType.TEXT:
        return 'text';
      case ToolType.HAND:
      default:
        return 'fingerWriting';
    }
  }

  private railToggleIconKind(): EditorUiIcon {
    return this.railCollapsed ? 'railExpand' : 'railCollapse';
  }

  private viewportHasHorizontalOverflow(): boolean {
    if (this.writingViewportWidth <= 0) {
      return false;
    }
    return (this.widestRenderedPageWidth() - this.writingViewportWidth) > VIEWPORT_HORIZONTAL_OVERFLOW_THRESHOLD;
  }

  private singleFingerPanMode(): SingleFingerPanMode {
    if (this.embedPlacementArmed || this.showEmbeddedComposer || this.showInspectorDrawer || this.fingerWritingEnabled) {
      return 'disabled';
    }
    if (this.debugState?.stylusActive ?? false) {
      return 'disabled';
    }
    return this.viewportHasHorizontalOverflow() ? 'free' : 'vertical';
  }

  private canSingleFingerPanViewport(): boolean {
    return this.singleFingerPanMode() !== 'disabled';
  }

  private canTwoFingerPanViewport(): boolean {
    return !this.embedPlacementArmed && !this.showEmbeddedComposer && !this.showInspectorDrawer;
  }

  private handleViewportPanStart(): void {
    this.stopViewportInertia();
    this.keepPageHudVisible();
    this.viewportPanOriginX = this.pageStackPanX;
    this.viewportPanOriginY = this.pageStackPanY;
    this.viewportPanLastOffsetX = 0;
    this.viewportPanLastOffsetY = 0;
    this.viewportPanLastTimestamp = Date.now();
    this.viewportPanVelocityX = 0;
    this.viewportPanVelocityY = 0;
  }

  private recordViewportPanVelocity(offsetX: number, offsetY: number, mode: SingleFingerPanMode | 'free'): void {
    const now: number = Date.now();
    const deltaMs: number = Math.max(1, now - this.viewportPanLastTimestamp);
    const deltaOffsetX: number = offsetX - this.viewportPanLastOffsetX;
    const deltaOffsetY: number = offsetY - this.viewportPanLastOffsetY;
    const instantVelocityX: number = mode === 'vertical' ? 0 : deltaOffsetX / deltaMs;
    const instantVelocityY: number = deltaOffsetY / deltaMs;
    this.viewportPanVelocityX = (this.viewportPanVelocityX * 0.42) + (instantVelocityX * 0.58);
    this.viewportPanVelocityY = (this.viewportPanVelocityY * 0.42) + (instantVelocityY * 0.58);
    this.viewportPanLastOffsetX = offsetX;
    this.viewportPanLastOffsetY = offsetY;
    this.viewportPanLastTimestamp = now;
  }

  private stopViewportInertia(): void {
    if (this.viewportInertiaTimerId >= 0) {
      clearInterval(this.viewportInertiaTimerId);
      this.viewportInertiaTimerId = -1;
    }
    if (this.viewportInertiaResolve) {
      const resolve: () => void = this.viewportInertiaResolve;
      this.viewportInertiaResolve = null;
      resolve();
    }
  }

  private startViewportInertia(mode: SingleFingerPanMode | 'free'): Promise<void> {
    this.stopViewportInertia();
    let velocityX: number = mode === 'vertical' ? 0 : this.viewportPanVelocityX;
    let velocityY: number = this.viewportPanVelocityY;
    if (Math.abs(velocityX) < VIEWPORT_INERTIA_MIN_SPEED && Math.abs(velocityY) < VIEWPORT_INERTIA_MIN_SPEED) {
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      this.viewportInertiaResolve = resolve;
      this.viewportInertiaTimerId = setInterval(() => {
        velocityX *= VIEWPORT_INERTIA_FRICTION;
        velocityY *= VIEWPORT_INERTIA_FRICTION;
        const nextX: number = mode === 'vertical'
          ? this.pageStackPanX
          : this.pageStackPanX + (velocityX * VIEWPORT_INERTIA_FRAME_MS);
        const nextY: number = this.pageStackPanY + (velocityY * VIEWPORT_INERTIA_FRAME_MS);
        const clampedX: number = this.clampedPageStackPanX(nextX);
        const clampedY: number = this.clampedPageStackPanY(nextY);
        const hitBoundaryX: boolean = mode !== 'vertical' && Math.abs(clampedX - nextX) > 0.5;
        const hitBoundaryY: boolean = Math.abs(clampedY - nextY) > 0.5;
        this.pageStackPanX = clampedX;
        this.pageStackPanY = clampedY;
        if (hitBoundaryX) {
          velocityX = 0;
        }
        if (hitBoundaryY) {
          velocityY = 0;
        }
        if (Math.abs(velocityX) < VIEWPORT_INERTIA_MIN_SPEED && Math.abs(velocityY) < VIEWPORT_INERTIA_MIN_SPEED) {
          this.stopViewportInertia();
        }
      }, VIEWPORT_INERTIA_FRAME_MS);
    });
  }

  private updateViewportPan(event: Object, fingers: number): void {
    const panMode: SingleFingerPanMode | 'free' = fingers === 1 ? this.singleFingerPanMode() : 'free';
    const canPan: boolean = fingers === 1 ? panMode !== 'disabled' : this.canTwoFingerPanViewport();
    if (!canPan) {
      return;
    }
    this.keepPageHudVisible();
    const offsetX: number = this.readGestureNumber(event, 'offsetX', 0);
    const offsetY: number = this.readGestureNumber(event, 'offsetY', 0);
    this.recordViewportPanVelocity(offsetX, offsetY, panMode);
    const nextX: number = panMode === 'vertical'
      ? this.pageStackPanX
      : this.viewportPanOriginX + offsetX;
    const nextY: number = this.viewportPanOriginY + offsetY;
    this.pageStackPanX = this.clampedPageStackPanX(nextX);
    this.pageStackPanY = this.clampedPageStackPanY(nextY);
  }

  private async finishViewportPan(fingers: number): Promise<void> {
    const panMode: SingleFingerPanMode | 'free' = fingers === 1 ? this.singleFingerPanMode() : 'free';
    const canPan: boolean = fingers === 1 ? panMode !== 'disabled' : this.canTwoFingerPanViewport();
    if (!canPan) {
      return;
    }
    await this.startViewportInertia(panMode);
    await this.syncViewportAfterGesture();
    this.schedulePageHudAutoHide();
  }

  private handleViewportPinchStart(): void {
    this.stopViewportInertia();
    this.keepPageHudVisible();
    this.viewportPinchOriginScale = this.pageStackScale;
  }

  private updateViewportPinch(event: Object): void {
    if (!this.canTwoFingerPanViewport()) {
      return;
    }
    this.keepPageHudVisible();
    const scaleDelta: number = this.readGestureNumber(event, 'scale', 1);
    const nextScale: number = clampToRange(
      this.viewportPinchOriginScale * (Number.isNaN(scaleDelta) ? 1 : scaleDelta),
      PAGE_STACK_MIN_ZOOM,
      PAGE_STACK_MAX_ZOOM
    );
    this.pageStackScale = nextScale;
    this.pageStackPanX = this.clampedPageStackPanX(this.pageStackPanX);
    this.pageStackPanY = this.clampedPageStackPanY(this.pageStackPanY);
  }

  private async finishViewportPinch(): Promise<void> {
    if (!this.canTwoFingerPanViewport()) {
      return;
    }
    await this.syncViewportAfterGesture();
    this.schedulePageHudAutoHide();
  }

  private floatingToolbarChromeHeight(): number {
    if (!this.toolbarUsesVerticalLayout()) {
      return this.shouldShowSecondaryToolbar() ? 118 : 74;
    }
    let height: number = 342;
    if (this.shouldShowSecondaryToolbar()) {
      height += this.toolUsesColorPalette() ? 80 : 116;
    }
    return height;
  }

  private toolbarUsesVerticalLayout(): boolean {
    return this.toolbarSnapSlot === 'left-middle' || this.toolbarSnapSlot === 'right-middle';
  }

  private floatingToolbarChromeWidth(): number {
    return this.toolbarUsesVerticalLayout() ? FLOATING_TOOLBAR_VERTICAL_WIDTH : FLOATING_TOOLBAR_WIDTH;
  }

  private toolbarAnchorPosition(slot: ToolbarSnapSlot = this.toolbarSnapSlot): GestureRatioPoint {
    const toolbarWidth: number = slot === 'left-middle' || slot === 'right-middle'
      ? FLOATING_TOOLBAR_VERTICAL_WIDTH
      : FLOATING_TOOLBAR_WIDTH;
    const topY: number = 18;
    const middleY: number = Math.max(topY, (this.writingViewportHeight - this.floatingToolbarChromeHeight()) / 2);
    const bottomY: number = Math.max(topY, this.writingViewportHeight - this.floatingToolbarChromeHeight() - 24);
    const leftX: number = 16;
    const rightX: number = Math.max(leftX, this.writingViewportWidth - toolbarWidth - 16);
    const centerX: number = Math.max(leftX, (this.writingViewportWidth - toolbarWidth) / 2);
    switch (slot) {
      case 'left-middle':
        return { xRatio: leftX, yRatio: middleY };
      case 'right-middle':
        return { xRatio: rightX, yRatio: middleY };
      case 'bottom-center':
        return { xRatio: centerX, yRatio: bottomY };
      case 'top-center':
      default:
        return { xRatio: centerX, yRatio: topY };
    }
  }

  private clampedFloatingToolbarX(value: number): number {
    if (this.writingViewportWidth <= 0) {
      return value;
    }
    const minX: number = 16;
    const maxX: number = Math.max(minX, this.writingViewportWidth - this.floatingToolbarChromeWidth() - 16);
    return clampToRange(value, minX, maxX);
  }

  private clampedFloatingToolbarY(value: number): number {
    if (this.writingViewportHeight <= 0) {
      return value;
    }
    const minY: number = 18;
    const maxY: number = Math.max(minY, this.writingViewportHeight - this.floatingToolbarChromeHeight() - 20);
    return clampToRange(value, minY, maxY);
  }

  private floatingToolbarPositionX(): number {
    const anchor: GestureRatioPoint = this.toolbarAnchorPosition();
    return this.clampedFloatingToolbarX(anchor.xRatio + this.floatingToolbarOffsetX);
  }

  private floatingToolbarPositionY(): number {
    const anchor: GestureRatioPoint = this.toolbarAnchorPosition();
    return this.clampedFloatingToolbarY(anchor.yRatio + this.floatingToolbarOffsetY);
  }

  private snapFloatingToolbarToNearestAnchor(): void {
    const currentX: number = this.floatingToolbarPositionX();
    const currentY: number = this.floatingToolbarPositionY();
    const slots: ToolbarSnapSlot[] = ['top-center', 'left-middle', 'right-middle', 'bottom-center'];
    let nearestSlot: ToolbarSnapSlot = this.toolbarSnapSlot;
    let nearestDistance: number = Number.MAX_VALUE;
    slots.forEach((slot: ToolbarSnapSlot) => {
      const anchor: GestureRatioPoint = this.toolbarAnchorPosition(slot);
      const deltaX: number = anchor.xRatio - currentX;
      const deltaY: number = anchor.yRatio - currentY;
      const distance: number = (deltaX * deltaX) + (deltaY * deltaY);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestSlot = slot;
      }
    });
    this.toolbarSnapSlot = nearestSlot;
    this.floatingToolbarOffsetX = 0;
    this.floatingToolbarOffsetY = 0;
  }

  private handleToolbarDragStart(): void {
    this.toolbarDragOriginX = this.floatingToolbarPositionX();
    this.toolbarDragOriginY = this.floatingToolbarPositionY();
  }

  private updateToolbarDrag(event: Object): void {
    const nextX: number = this.clampedFloatingToolbarX(this.toolbarDragOriginX + this.readGestureNumber(event, 'offsetX', 0));
    const nextY: number = this.clampedFloatingToolbarY(this.toolbarDragOriginY + this.readGestureNumber(event, 'offsetY', 0));
    const anchor: GestureRatioPoint = this.toolbarAnchorPosition();
    this.floatingToolbarOffsetX = nextX - anchor.xRatio;
    this.floatingToolbarOffsetY = nextY - anchor.yRatio;
  }

  private readGestureNumber(event: Object | undefined, key: string, fallback: number = 0): number {
    const eventMap: Record<string, Object> = (event ?? {}) as Record<string, Object>;
    const direct: number = Number.parseFloat(`${eventMap[key] ?? ''}`);
    if (!Number.isNaN(direct)) {
      return direct;
    }
    const fingerList: Object | undefined = eventMap['fingerList'];
    if (Array.isArray(fingerList) && fingerList.length > 0) {
      const firstFinger: Record<string, Object> = fingerList[0] as Record<string, Object>;
      const nested: number = Number.parseFloat(`${firstFinger[key] ?? ''}`);
      if (!Number.isNaN(nested)) {
        return nested;
      }
    }
    return fallback;
  }

  private readGestureCoordinate(event: Object | undefined, keys: string[], fallback: number): number {
    for (let index = 0; index < keys.length; index += 1) {
      const value: number = this.readGestureNumber(event, keys[index], Number.NaN);
      if (!Number.isNaN(value)) {
        return value;
      }
    }
    return fallback;
  }

  private simulatorFingerGestureTarget(event?: Object): SimulatorFingerGestureTarget | null {
    if (this.activePageIndex < 0 || this.activePageIndex >= this.pageCount()) {
      return null;
    }
    const fallbackPageIndex: number = this.simulatorFingerGestureActive && this.simulatorFingerGesturePageIndex >= 0
      ? this.simulatorFingerGesturePageIndex
      : this.activePageIndex;
    const fallbackFrame: SimulatorCanvasFrame = this.simulatorCanvasFrame(fallbackPageIndex);
    const fallbackPageOffsetX: number = this.pageCardOffsetX(fallbackPageIndex);
    const fallbackPageOffsetY: number = this.pageCardOffsetY(fallbackPageIndex);
    const localX: number = this.readGestureCoordinate(
      event,
      ['localX', 'x'],
      fallbackPageOffsetX + fallbackFrame.contentX + (fallbackFrame.contentWidth / 2)
    );
    const localY: number = this.readGestureCoordinate(
      event,
      ['localY', 'y'],
      fallbackPageOffsetY + fallbackFrame.contentY + (fallbackFrame.contentHeight / 2)
    );
    const pageIndex: number = this.simulatorFingerGestureActive && this.simulatorFingerGesturePageIndex >= 0
      ? this.simulatorFingerGesturePageIndex
      : this.nearestPageIndexToViewportPoint(localX, localY);
    const frame: SimulatorCanvasFrame = this.simulatorCanvasFrame(pageIndex);
    if (frame.contentWidth <= 0 || frame.contentHeight <= 0) {
      return null;
    }
    const pageOffsetX: number = this.pageCardOffsetX(pageIndex);
    const pageOffsetY: number = this.pageCardOffsetY(pageIndex);
    const pageLocalX: number = clampToRange(localX - pageOffsetX - frame.contentX, 0, frame.contentWidth);
    const pageLocalY: number = clampToRange(localY - pageOffsetY - frame.contentY, 0, frame.contentHeight);
    const target: SimulatorFingerGestureTarget = {
      pageIndex,
      point: {
        xRatio: frame.contentWidth > 0 ? pageLocalX / frame.contentWidth : 0.5,
        yRatio: frame.contentHeight > 0 ? pageLocalY / frame.contentHeight : 0.5
      }
    };
    return target;
  }

  private resetSimulatorFingerGesture(cancelNative: boolean = false): void {
    if (cancelNative && this.engineId.length > 0 && this.simulatorFingerGestureActive) {
      this.nativeEngine.injectSimulatorFingerEvent(
        this.engineId,
        'cancel',
        this.simulatorFingerGestureLastXRatio,
        this.simulatorFingerGestureLastYRatio,
        0
      );
    }
    this.simulatorFingerGestureActive = false;
    this.simulatorFingerGesturePageIndex = -1;
    this.simulatorFingerGestureLastXRatio = 0.5;
    this.simulatorFingerGestureLastYRatio = 0.5;
  }

  private updateSimulatorFingerGesture(event: Object): void {
    if (!this.shouldHandleSimulatorFingerWritingGesture()) {
      return;
    }
    const target = this.simulatorFingerGestureTarget(event);
    if (!target) {
      return;
    }
    if (!this.simulatorFingerGestureActive) {
      this.syncSimulatorGestureActivePage(target.pageIndex);
      this.simulatorFingerGesturePageIndex = target.pageIndex;
    }
    const point: GestureRatioPoint = target.point;
    this.simulatorFingerGestureLastXRatio = point.xRatio;
    this.simulatorFingerGestureLastYRatio = point.yRatio;
    if (!this.simulatorFingerGestureActive) {
      this.nativeEngine.injectSimulatorFingerEvent(this.engineId, 'down', point.xRatio, point.yRatio, 1);
      this.simulatorFingerGestureActive = true;
    }
    this.nativeEngine.injectSimulatorFingerEvent(this.engineId, 'move', point.xRatio, point.yRatio, 1);
  }

  private finishSimulatorFingerGesture(event?: Object): void {
    if (this.engineId.length === 0) {
      this.resetSimulatorFingerGesture(false);
      return;
    }
    const target = this.simulatorFingerGestureTarget(event);
    if (!this.simulatorFingerGestureActive && target) {
      this.syncSimulatorGestureActivePage(target.pageIndex);
      this.simulatorFingerGesturePageIndex = target.pageIndex;
    }
    const xRatio: number = target?.point.xRatio ?? this.simulatorFingerGestureLastXRatio;
    const yRatio: number = target?.point.yRatio ?? this.simulatorFingerGestureLastYRatio;
    if (this.shouldHandleSimulatorFingerWritingGesture() && !this.simulatorFingerGestureActive) {
      this.nativeEngine.injectSimulatorFingerEvent(this.engineId, 'down', xRatio, yRatio, 1);
    }
    if (this.simulatorFingerGestureActive || this.shouldHandleSimulatorFingerWritingGesture()) {
      this.nativeEngine.injectSimulatorFingerEvent(this.engineId, 'up', xRatio, yRatio, 0);
      this.traceActionMessage = this.fingerWritingEnabled ? '模拟器手指写入已注入' : '模拟器触摸事件已记录';
      this.refreshDebugState();
    }
    this.resetSimulatorFingerGesture(false);
  }

  private async reloadDocumentEmbeddedBlocks(): Promise<void> {
    if (!this.document || !this.libraryService) {
      return;
    }
    const blocksByPageId: Record<string, DocumentEmbeddedBlock[]> =
      await this.libraryService.getDocumentEmbeddedBlocks(this.document.id);
    this.embeddedOverlaysByPage.clear();
    Object.keys(blocksByPageId).forEach((pageId: string) => {
      this.embeddedOverlaysByPage.set(pageId, [...blocksByPageId[pageId]]);
    });
    this.overlaysVersion += 1;
  }

  private pageEmbeddedBlocks(pageId: string): EmbeddedOverlayDraft[] {
    this.overlaysVersion;
    return [...(this.embeddedOverlaysByPage.get(pageId) ?? [])];
  }

  private pageEmbeddedBlocksAt(index: number): EmbeddedOverlayDraft[] {
    return this.pageEmbeddedBlocks(this.pageKeyAt(index));
  }

  private detectEmbeddedBlockKind(sourceText: string): DocumentEmbeddedBlockKind {
    const hasMath: boolean = sourceText.includes('$$') || sourceText.includes('\\(') || sourceText.includes('\\[') ||
      /\$[^$]+\$/.test(sourceText);
    const hasMarkdown: boolean = /^#{1,6}\s|\*\*|__|^- |\d+\. |```|>\s/m.test(sourceText);
    if (hasMarkdown && hasMath) {
      return 'mixed';
    }
    if (hasMath) {
      return 'latex';
    }
    return 'markdown';
  }

  private embeddedBlockPlainText(block: EmbeddedOverlayDraft): string {
    const fromMeta: string = block.renderMeta?.plainText?.trim() ?? '';
    if (fromMeta.length > 0) {
      return fromMeta;
    }
    const previewText: string = MarkdownUtils.buildPreviewBlocks(block.sourceText)
      .map((item: MarkdownPreviewBlock) => item.text.trim())
      .filter((item: string) => item.length > 0)
      .join(' ')
      .trim();
    if (previewText.length > 0) {
      return previewText;
    }
    return block.sourceText.trim();
  }

  private embeddedComposerPreviewBlocks(): MarkdownPreviewBlock[] {
    this.embeddedComposerPreviewVersion;
    return MarkdownUtils.buildPreviewBlocks(this.embeddedComposerText);
  }

  private embeddedBlockPixelX(pageIndex: number, block: EmbeddedOverlayDraft): number {
    const pageWidth: number = this.renderedWritingPageWidth(pageIndex);
    const blockWidth: number = this.embeddedBlockPixelWidth(pageIndex, block);
    return clampToRange(pageWidth * block.bounds.x, 0, Math.max(0, pageWidth - blockWidth - 12));
  }

  private embeddedBlockPixelY(pageIndex: number, block: EmbeddedOverlayDraft): number {
    const pageHeight: number = this.renderedWritingPageHeight(pageIndex);
    const blockHeight: number = this.embeddedBlockPixelHeight(pageIndex, block);
    return clampToRange(pageHeight * block.bounds.y, 0, Math.max(0, pageHeight - blockHeight - 12));
  }

  private embeddedBlockPixelWidth(pageIndex: number, block: EmbeddedOverlayDraft): number {
    return clampToRange(this.renderedWritingPageWidth(pageIndex) * block.bounds.width, 120, this.renderedWritingPageWidth(pageIndex) - 18);
  }

  private embeddedBlockPixelHeight(pageIndex: number, block: EmbeddedOverlayDraft): number {
    return clampToRange(this.renderedWritingPageHeight(pageIndex) * block.bounds.height, 68, this.renderedWritingPageHeight(pageIndex) - 18);
  }

  private isPageBookmarked(pageIndex: number): boolean {
    return Boolean(this.pageEntryAt(pageIndex)?.bookmarked);
  }

  private async toggleBookmarkForPage(pageIndex: number): Promise<void> {
    const pageId: string = this.pageKeyAt(pageIndex);
    if (!this.document || !this.libraryService || pageId.length === 0) {
      return;
    }
    const nextBookmarked: boolean = !this.isPageBookmarked(pageIndex);
    const nextDocument: DocumentRecord = await this.libraryService.togglePageBookmark(this.document.id, pageId, nextBookmarked);
    if (this.supportsPagedDocumentRuntime(nextDocument)) {
      this.applyDocumentActivePage(nextDocument, this.activePageId.length > 0 ? this.activePageId : nextDocument.activePageId);
    } else {
      this.document = nextDocument;
    }
    this.bookmarksVersion += 1;
    this.traceActionMessage = nextBookmarked ? '页面已加书签' : '页面已取消书签';
  }

  private armEmbeddedPlacement(): void {
    if (!this.toolUsesContextActions()) {
      return;
    }
    this.embedPlacementArmed = true;
    this.embedSelectionVisible = false;
    this.traceActionMessage = '请在当前页拖出图文块区域';
  }

  private clearEmbeddedPlacement(resetArm: boolean = true): void {
    this.embedSelectionVisible = false;
    this.embedSelectionPageId = '';
    this.embedSelectionX = 0;
    this.embedSelectionY = 0;
    this.embedSelectionWidth = 0;
    this.embedSelectionHeight = 0;
    if (resetArm) {
      this.embedPlacementArmed = false;
    }
  }

  private beginEmbeddedSelection(event: Object, pageIndex: number): void {
    if (!this.embedPlacementArmed || !this.isSelectedPageIndex(pageIndex)) {
      return;
    }
    this.embedSelectionPageId = this.pageKeyAt(pageIndex);
    this.embeddedSelectionOriginX = this.readGestureNumber(event, 'localX', 0);
    this.embeddedSelectionOriginY = this.readGestureNumber(event, 'localY', 0);
    this.embedSelectionX = this.embeddedSelectionOriginX;
    this.embedSelectionY = this.embeddedSelectionOriginY;
    this.embedSelectionWidth = 0;
    this.embedSelectionHeight = 0;
    this.embedSelectionVisible = true;
  }

  private updateEmbeddedSelection(event: Object): void {
    if (!this.embedSelectionVisible) {
      return;
    }
    const currentX: number = this.readGestureNumber(event, 'localX', this.embeddedSelectionOriginX);
    const currentY: number = this.readGestureNumber(event, 'localY', this.embeddedSelectionOriginY);
    this.embedSelectionX = Math.min(this.embeddedSelectionOriginX, currentX);
    this.embedSelectionY = Math.min(this.embeddedSelectionOriginY, currentY);
    this.embedSelectionWidth = Math.abs(currentX - this.embeddedSelectionOriginX);
    this.embedSelectionHeight = Math.abs(currentY - this.embeddedSelectionOriginY);
  }

  private openEmbeddedComposer(): void {
    if (!this.embedSelectionVisible || this.embedSelectionPageId.length === 0) {
      return;
    }
    if (this.embedSelectionWidth < EMBED_SELECTION_MIN_SIZE || this.embedSelectionHeight < EMBED_SELECTION_MIN_SIZE) {
      this.clearEmbeddedPlacement(false);
      return;
    }
    this.showEmbeddedComposer = true;
    this.embeddedComposerText = '';
    this.embeddedComposerPageId = this.embedSelectionPageId;
    this.embeddedComposerPageIndex = this.activePageIndex;
    this.embeddedComposerPreviewVersion = 0;
  }

  private finishEmbeddedSelection(): void {
    if (!this.embedSelectionVisible) {
      return;
    }
    this.openEmbeddedComposer();
  }

  private cancelEmbeddedComposer(): void {
    this.showEmbeddedComposer = false;
    this.embeddedComposerText = '';
    this.embeddedComposerPageId = '';
    this.embeddedComposerPageIndex = -1;
    this.embeddedComposerPreviewVersion = 0;
    this.clearEmbeddedPlacement();
  }

  private embeddedSelectionBounds(): DocumentEmbeddedBlockBounds | undefined {
    if (this.embeddedComposerPageIndex < 0) {
      return undefined;
    }
    const pageWidth: number = this.renderedWritingPageWidth(this.embeddedComposerPageIndex);
    const pageHeight: number = this.renderedWritingPageHeight(this.embeddedComposerPageIndex);
    if (pageWidth <= 0 || pageHeight <= 0) {
      return undefined;
    }
    return {
      x: clampToRange(this.embedSelectionX / pageWidth, 0, 0.98),
      y: clampToRange(this.embedSelectionY / pageHeight, 0, 0.98),
      width: clampToRange(this.embedSelectionWidth / pageWidth, 0.04, 0.98),
      height: clampToRange(this.embedSelectionHeight / pageHeight, 0.04, 0.98)
    };
  }

  private async commitEmbeddedComposer(): Promise<void> {
    if (!this.document || !this.libraryService || this.embeddedComposerPageId.length === 0) {
      this.cancelEmbeddedComposer();
      return;
    }
    const sourceText: string = this.embeddedComposerText.trim();
    const bounds: DocumentEmbeddedBlockBounds | undefined = this.embeddedSelectionBounds();
    if (sourceText.length === 0 || bounds === undefined) {
      return;
    }
    const previewBlocks: MarkdownPreviewBlock[] = MarkdownUtils.buildPreviewBlocks(sourceText);
    const plainText: string = previewBlocks
      .map((block: MarkdownPreviewBlock) => block.text.trim())
      .filter((text: string) => text.length > 0)
      .join(' ')
      .trim();
    const now: number = Date.now();
    const block: DocumentEmbeddedBlock = {
      id: `embedded-${now}`,
      kind: this.detectEmbeddedBlockKind(sourceText),
      sourceText,
      bounds,
      renderMeta: {
        plainText,
        estimatedHeight: bounds.height,
        measuredHeight: bounds.height,
        version: 1
      },
      createdAt: now,
      updatedAt: now
    };
    const nextDocument: DocumentRecord = await this.libraryService.upsertPageEmbeddedBlock(
      this.document.id,
      this.embeddedComposerPageId,
      block,
      true
    );
    if (this.supportsPagedDocumentRuntime(nextDocument)) {
      this.applyDocumentActivePage(
        nextDocument,
        this.activePageId.length > 0 ? this.activePageId : nextDocument.activePageId
      );
    } else {
      this.document = nextDocument;
    }
    await this.reloadDocumentEmbeddedBlocks();
    this.traceActionMessage = '图文块已保存';
    this.cancelEmbeddedComposer();
  }

  private async selectPage(index: number): Promise<void> {
    if (index < 0 || index >= this.pageCount() || this.pageSelectionInFlight) {
      return;
    }
    this.pageSelectionInFlight = true;
    this.keepPageHudVisible();
    this.closeRailMenus();
    this.showPageJumpInput = false;
    try {
      if (this.supportsPagedDocumentRuntime()) {
        const nextPage: DocumentPageEntry | undefined = this.editablePages()[index];
        if (!nextPage || nextPage.id === this.activePageId || !this.document || !this.libraryService) {
          return;
        }
        const currentPageId: string = this.activePageId;
        const shouldPersistCurrentContent: boolean = this.hasPendingContentPersistence();
        if (shouldPersistCurrentContent) {
          this.cancelPendingAutosave();
          this.stageCurrentPageDraft();
          await this.persistBlankPagedRuntimePage();
          if (currentPageId.length > 0) {
            const currentMarkdown: string = this.pageMarkdownDrafts.get(currentPageId) ?? this.markdownText;
            await this.libraryService.saveDocumentMarkdown(this.document.id, currentMarkdown, currentPageId, false);
            this.dirtyPageIds.delete(currentPageId);
          }
          this.markContentPersisted();
        }
        const nextDocument: DocumentRecord = await this.libraryService.setDocumentActivePage(this.document.id, nextPage.id);
        this.applyDocumentActivePage(nextDocument, nextPage.id);
        await this.loadPageMarkdown(nextPage.id);
        if (!this.notifyNativeActivePage(nextPage.id)) {
          await this.primeBlankPagedRuntime(nextPage.id);
          await this.reopenNativeDocumentForCurrentState();
        }
        this.refreshDebugState();
        this.schedulePageHudAutoHide();
        return;
      }
      this.activePageIndex = index;
      this.schedulePageHudAutoHide();
    } finally {
      this.pageSelectionInFlight = false;
    }
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
    if (this.hasPendingContentPersistence()) {
      this.cancelPendingAutosave();
      this.stageCurrentPageDraft();
      await this.persistBlankPagedRuntimePage();
      this.markContentPersisted();
    }
    const nextDocument: DocumentRecord = await this.libraryService!.addBlankPage((this.document as DocumentRecord).id);
    const insertedPage: DocumentPageEntry | undefined = nextDocument.pages.find((page) => page.id === nextDocument.activePageId);
    this.applyDocumentActivePage(nextDocument, nextDocument.activePageId);
    await this.loadPageMarkdown(this.activePageId);
    await this.reloadDocumentEmbeddedBlocks();
    this.syncViewportToActivePage(true);
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
    if (this.hasPendingContentPersistence()) {
      this.cancelPendingAutosave();
      this.stageCurrentPageDraft();
      await this.persistBlankPagedRuntimePage();
      this.markContentPersisted();
    }
    const nextDocument: DocumentRecord = await this.libraryService!.deleteBlankPage((this.document as DocumentRecord).id, deletedPageId);
    this.pageMarkdownDrafts.delete(deletedPageId);
    this.dirtyPageIds.delete(deletedPageId);
    this.applyDocumentActivePage(nextDocument, nextDocument.activePageId);
    await this.loadPageMarkdown(this.activePageId);
    await this.reloadDocumentEmbeddedBlocks();
    this.syncViewportToActivePage(true);
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

  private isInspectorModeActive(mode: 'preview' | 'source'): boolean {
    return this.showInspectorDrawer && this.previewMode === mode;
  }

  private pagePreviewSnapshotAt(index: number): DocumentPreviewSnapshot | undefined {
    const snapshot: DocumentPreviewSnapshot | undefined = this.previewSnapshot();
    if (!snapshot) {
      return undefined;
    }
    const pageEntry: DocumentPageEntry | undefined = this.pageEntryAt(index);
    if (pageEntry) {
      if (snapshot.coverPageId === pageEntry.id) {
        return snapshot;
      }
      if (snapshot.pageIndex === index && (snapshot.pageIds.length === 0 || snapshot.pageIds.includes(pageEntry.id))) {
        return snapshot;
      }
      if (this.document?.coverPage === index && snapshot.pageIds.includes(pageEntry.id)) {
        return snapshot;
      }
      return undefined;
    }
    if (snapshot.pageIndex === index) {
      return snapshot;
    }
    return this.document?.coverPage === index ? snapshot : undefined;
  }

  private pageMarkdownTextAt(index: number): string {
    const pageId: string = this.pageEntryAt(index)?.id ?? '';
    if (pageId.length === 0) {
      return this.isSelectedPageIndex(index) ? this.markdownText : '';
    }
    if (pageId === this.activePageId) {
      return this.markdownText;
    }
    return this.pageMarkdownDrafts.get(pageId) ?? '';
  }

  private pagePreviewFallbackBlocks(index: number): MarkdownPreviewBlock[] {
    if (this.pageEntryAt(index)?.pageKind === 'pdf' || this.pageEntryAt(index)?.pageKind === 'pdf-fragment') {
      return [];
    }
    const normalizedBlocks: MarkdownPreviewBlock[] = [];
    const markdownText: string = this.pageMarkdownTextAt(index).trim();
    const embeddedText: string = this.pageEmbeddedBlocksAt(index)
      .map((block: DocumentEmbeddedBlock) => block.sourceText.trim())
      .filter((text: string) => text.length > 0)
      .join('\n\n')
      .trim();
    const previewSourceText: string = markdownText.length > 0 ? markdownText : embeddedText;
    if (previewSourceText.length === 0) {
      return [];
    }
    MarkdownUtils.buildPreviewBlocks(previewSourceText).forEach((block: MarkdownPreviewBlock) => {
      const normalizedText: string = block.text.replace(/\s+/g, ' ').trim();
      if (this.isPreviewPlaceholderText(normalizedText)) {
        return;
      }
      normalizedBlocks.push({
        type: block.type,
        level: block.level,
        text: normalizedText
      });
    });
    return normalizedBlocks.slice(0, 4);
  }

  private isPreviewPlaceholderText(text: string): boolean {
    const normalizedText: string = text.replace(/\s+/g, ' ').trim();
    return normalizedText.length === 0 || normalizedText === 'No text content yet.';
  }

  private embeddedComposerVisibleBlocks(): MarkdownPreviewBlock[] {
    const visibleBlocks: MarkdownPreviewBlock[] = [];
    this.embeddedComposerPreviewBlocks().forEach((block: MarkdownPreviewBlock) => {
      const normalizedText: string = block.text.replace(/\s+/g, ' ').trim();
      if (this.isPreviewPlaceholderText(normalizedText)) {
        return;
      }
      visibleBlocks.push({
        type: block.type,
        level: block.level,
        text: normalizedText
      });
    });
    return visibleBlocks;
  }

  private pageSceneAt(index: number): NativePreviewPage | undefined {
    const scene: NativeSceneSnapshot | null = this.simulatorSceneSnapshot;
    if (!scene) {
      return undefined;
    }
    const pageEntry: DocumentPageEntry | undefined = this.pageEntryAt(index);
    if (pageEntry) {
      return scene.pages.find((page: NativePreviewPage) => page.pageId === pageEntry.id) ??
        scene.pages.find((page: NativePreviewPage) => page.pageIndex === index);
    }
    return scene.pages.find((page: NativePreviewPage) => page.pageIndex === index);
  }

  private pageSceneWidthAt(index: number): number {
    const page: NativePreviewPage | undefined = this.pageSceneAt(index);
    const bounds: NativePreviewBounds | undefined = page?.bounds;
    const boundedWidth: number = bounds ? Math.max(0, bounds.maxX - bounds.minX) : 0;
    const width: number = Number(page?.width ?? boundedWidth);
    if (width > 0) {
      return width;
    }
    if (this.document) {
      return buildNativePageContractForEntry(this.document, this.pageEntryAt(index)).widthPt;
    }
    return 612;
  }

  private pageSceneHeightAt(index: number): number {
    const page: NativePreviewPage | undefined = this.pageSceneAt(index);
    const bounds: NativePreviewBounds | undefined = page?.bounds;
    const boundedHeight: number = bounds ? Math.max(0, bounds.maxY - bounds.minY) : 0;
    const height: number = Number(page?.height ?? boundedHeight);
    if (height > 0) {
      return height;
    }
    if (this.document) {
      return buildNativePageContractForEntry(this.document, this.pageEntryAt(index)).heightPt;
    }
    return 792;
  }

  private pageSceneObjectsAt(index: number): NativeSceneObject[] {
    const scene: NativeSceneSnapshot | null = this.simulatorSceneSnapshot;
    if (!scene) {
      return [];
    }
    const pageId: string = this.pageEntryAt(index)?.id ?? this.pageSceneAt(index)?.pageId ?? '';
    return scene.objects.filter((object: NativeSceneObject) => object.layer === 'ink' &&
      (((object.pageId ?? '') === pageId && pageId.length > 0) || (object.pageIndex ?? -1) === index));
  }

  private pageRailObjectX(index: number, object: NativeSceneObject): number {
    const innerWidth: number = PAGE_RAIL_THUMBNAIL_WIDTH - 20;
    return 10 + clampToRange(
      (object.bounds.minX / this.pageSceneWidthAt(index)) * innerWidth,
      0,
      innerWidth - 18
    );
  }

  private pageRailObjectY(index: number, object: NativeSceneObject): number {
    const innerHeight: number = PAGE_RAIL_THUMBNAIL_HEIGHT - 22;
    return 11 + clampToRange(
      (object.bounds.minY / this.pageSceneHeightAt(index)) * innerHeight,
      0,
      innerHeight - 14
    );
  }

  private pageRailObjectWidth(index: number, object: NativeSceneObject): number {
    const widthRatio: number = Math.max(0, object.bounds.maxX - object.bounds.minX) / this.pageSceneWidthAt(index);
    return clampToRange(widthRatio * (PAGE_RAIL_THUMBNAIL_WIDTH - 20), 12, PAGE_RAIL_THUMBNAIL_WIDTH - 22);
  }

  private pageRailObjectHeight(index: number, object: NativeSceneObject): number {
    const heightRatio: number = Math.max(0, object.bounds.maxY - object.bounds.minY) / this.pageSceneHeightAt(index);
    return clampToRange(heightRatio * (PAGE_RAIL_THUMBNAIL_HEIGHT - 22), 8, 44);
  }

  private pagePlaceholderTitle(index: number): string {
    if (!this.supportsPagedDocumentRuntime()) {
      return '文档页';
    }
    const pageEntry: DocumentPageEntry | undefined = this.pageEntryAt(index);
    if (pageEntry?.pageKind === 'pdf') {
      return 'PDF 页面';
    }
    if (pageEntry?.pageKind === 'pdf-fragment') {
      return '片段';
    }
    return '空白页';
  }

  private pagePlaceholderDetail(index: number): string {
    if (!this.supportsPagedDocumentRuntime()) {
      return '仅文档摘要';
    }
    if (this.pageSceneObjectsAt(index).length > 0) {
      return '运行时预览可用';
    }
    return this.pagePreviewFallbackBlocks(index).length > 0 ? '已有预览' : '暂无预览';
  }

  @Builder
  private buildInspectorShortcut(mode: 'preview' | 'source', label: string): void {
    Button(label)
      .height(40)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.isInspectorModeActive(mode) ? '#162033' : '#F3F6FB')
      .fontColor(this.isInspectorModeActive(mode) ? '#FFFFFF' : '#162033')
      .fontSize(12)
      .borderRadius(12)
      .onClick(() => {
        this.toggleInspector(mode);
      })
  }

  @Builder
  private buildHeaderBar(): void {
    Row({ space: 6 }) {
      this.buildInspectorShortcut('preview', this.inspectorTabLabel('preview'))
      this.buildInspectorShortcut('source', this.inspectorTabLabel('source'))
    }
    .padding(6)
    .backgroundColor('#F8F9FA')
    .border({ width: 1, color: '#E4E7EC' })
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
      Text('simulated state')
        .fontSize(10)
        .fontColor('#9A3412')
    }
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor('#FFF7ED')
    .border({ width: 1, color: '#FDBA74' })
    .borderRadius(999)
  }

  @Builder
  private buildSimulatorGuideLines(frame: SimulatorCanvasFrame): void {
    if (this.simulatorGuideKind() !== 'plain') {
      ForEach([0, 1, 2, 3, 4, 5], (lineIndex: number) => {
        Row()
          .width(frame.contentWidth)
          .height(this.simulatorGuideKind() === 'grid' ? 1 : 0.8)
          .backgroundColor(this.simulatorGuideKind() === 'cornell' ? '#D6DDE8' : '#E3E8EF')
          .opacity(this.simulatorGuideKind() === 'dotted' ? 0.5 : 0.8)
          .position({ x: frame.contentX, y: frame.contentY + 26 + lineIndex * ((frame.contentHeight - 48) / 6) })
      }, (lineIndex: number): string => `line-${lineIndex}`)
    }
    if (this.simulatorGuideKind() === 'grid' || this.simulatorGuideKind() === 'weekly') {
      ForEach([0, 1, 2, 3], (lineIndex: number) => {
        Row()
          .width(1)
          .height(frame.contentHeight)
          .backgroundColor('#E3E8EF')
          .opacity(0.75)
          .position({ x: frame.contentX + 28 + lineIndex * ((frame.contentWidth - 56) / 4), y: frame.contentY })
      }, (lineIndex: number): string => `vline-${lineIndex}`)
    }
    if (this.simulatorGuideKind() === 'cornell') {
      Row()
        .width(1)
        .height(frame.contentHeight)
        .backgroundColor('#CBD5E1')
        .position({ x: frame.contentX + clampToRange(frame.contentWidth * 0.20, 72, 120), y: frame.contentY })
      Row()
        .width(frame.contentWidth)
        .height(1)
        .backgroundColor('#CBD5E1')
        .position({ x: frame.contentX, y: frame.contentY + frame.contentHeight - clampToRange(frame.contentHeight * 0.12, 48, 72) })
    }
  }

  @Builder
  private buildPlaceholderSurface(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor(this.simulatorPageFillColor())

      this.buildSimulatorGuideLines(this.activeSimulatorCanvasFrame())

      if (this.simulatorObjectsForActivePage().length === 0) {
        ForEach([0, 1, 2], (rowIndex: number) => {
          Row({ space: 10 }) {
            Blank()
              .width(clampToRange(this.activeSimulatorCanvasFrame().contentWidth * 0.24, 56, 120))
              .height(6)
              .backgroundColor('#C2CFDF')
              .opacity(0.7)
              .borderRadius(999)
            Blank()
              .width(clampToRange(this.activeSimulatorCanvasFrame().contentWidth * 0.18, 40, 96))
              .height(6)
              .backgroundColor('#D3DDE9')
              .opacity(0.68)
              .borderRadius(999)
          }
          .position({
            x: this.activeSimulatorCanvasFrame().contentX + 18,
            y: this.activeSimulatorCanvasFrame().contentY +
              54 +
              rowIndex * clampToRange(this.activeSimulatorCanvasFrame().contentHeight * 0.18, 52, 84)
          })
        }, (rowIndex: number): string => `stub-line-${rowIndex}`)
      } else {
        ForEach(this.simulatorObjectsForActivePage(), (object: NativeSceneObject) => {
          Row() {
            Text(this.simulatorObjectLabel(object))
              .fontSize(10)
              .fontColor('#FFFFFF')
              .maxLines(1)
          }
          .justifyContent(FlexAlign.Center)
          .width(this.simulatorObjectWidth(object))
          .height(this.simulatorObjectHeight(object))
          .padding({ left: 6, right: 6 })
          .backgroundColor(object.colorHex)
          .opacity(object.tool === 'highlighter' ? 0.58 : 0.9)
          .borderRadius(object.tool === 'text' ? 10 : 16)
          .position({ x: this.simulatorObjectX(object), y: this.simulatorObjectY(object) })
        }, (object: NativeSceneObject): string => object.id)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildPageMotionLayer(): void {
    Stack() {
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
    .translate({ x: 0, y: this.canSwipeBetweenPages() ? this.pageSwipeOffset : 0 })
  }

  @Builder
  private buildWritingSurface(): void {
    Stack() {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#F8FAFC')
      this.buildPageMotionLayer()
    }
    .width('100%')
    .height('100%')
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 600 })
          .onAction(() => {
            this.toggleTracePanel();
          }),
        PanGesture({ direction: PanDirection.Vertical, distance: this.canSwipeBetweenPages() ? 16 : 100000 })
          .onActionUpdate((event) => {
            const offsetY: number = Number.parseFloat(`${event.offsetY ?? 0}`);
            this.updatePageSwipeOffset(Number.isNaN(offsetY) ? 0 : offsetY);
          })
          .onActionEnd(async (event) => {
            const offsetY: number = Number.parseFloat(`${event.offsetY ?? 0}`);
            await this.finishPageSwipe(Number.isNaN(offsetY) ? 0 : offsetY);
          })
      )
    )
  }

  @Builder
  private buildBottomHint(): void {
    Row({ space: 8 }) {
      Text(this.showTracePanel ? EDITOR_WORKSPACE_COPY.longPressCollapseDebugPanel : EDITOR_WORKSPACE_COPY.longPressExpandTracePanel)
        .fontSize(11)
        .fontColor('#475467')
      if (this.canSwipeBetweenPages()) {
        Text('上下滑动可切换页面')
          .fontSize(11)
          .fontColor('#0F766E')
      }
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
        if (this.supportsPagedDocumentRuntime() && this.activePageId.length > 0) {
          this.pageMarkdownDrafts.set(this.activePageId, value);
          this.dirtyPageIds.add(this.activePageId);
        }
        this.noteDocumentMutationForAutosave();
      })
  }

  @Builder
  private buildInspectorDrawer(): void {
    Column() {
      Row() {
        Text(this.inspectorPanelTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#162033')
        Blank()
          .layoutWeight(1)
        Button(EDITOR_WORKSPACE_COPY.close)
          .height(32)
          .backgroundColor('#F3F6FB')
          .fontColor('#162033')
          .onClick(() => {
            this.closeInspector();
          })
      }
      if (this.previewMode === 'preview') {
        this.buildPreviewDrawerBody()
      } else {
        this.buildSourceDrawerBody()
      }
    }
    .width(EDITOR_INSPECTOR_WIDTH)
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
      if (this.shouldUseSimulatorStubUi()) {
        Row({ space: 8 }) {
          Text(`${EDITOR_WORKSPACE_COPY.simulatorZoom}：${this.pageStackScale.toFixed(2)}x`)
            .fontSize(11)
            .fontColor('#CBD5E1')
          Button(EDITOR_WORKSPACE_COPY.zoomOut)
            .height(30)
            .backgroundColor('#334155')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.nudgeSimulatorZoom(-0.18);
            })
          Button(EDITOR_WORKSPACE_COPY.zoomIn)
            .height(30)
            .backgroundColor('#2563EB')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.nudgeSimulatorZoom(0.18);
            })
          Button(EDITOR_WORKSPACE_COPY.resetZoom)
            .height(30)
            .backgroundColor('#475467')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.resetSimulatorZoom();
            })
        }
        .margin({ top: 10 })
      }
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
  private buildPageRailPreviewCard(pageIndex: number): void {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pagePreviewSnapshotAt(pageIndex) !== undefined) {
        PreviewThumbnail({
          previewSnapshot: this.pagePreviewSnapshotAt(pageIndex) as DocumentPreviewSnapshot,
          fallbackSummary: '',
          thumbnailWidth: PAGE_RAIL_THUMBNAIL_WIDTH,
          thumbnailHeight: PAGE_RAIL_THUMBNAIL_HEIGHT
        })
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width(PAGE_RAIL_THUMBNAIL_WIDTH)
            .height(PAGE_RAIL_THUMBNAIL_HEIGHT)
            .backgroundColor('#FFFEFB')
            .borderRadius(PAGE_RAIL_CARD_RADIUS)
            .border({ width: 1, color: '#D8E0EA' })
          if (this.pageEntryAt(pageIndex)?.pageKind === 'pdf' || this.pageEntryAt(pageIndex)?.pageKind === 'pdf-fragment') {
            Column({ space: 8 }) {
              Row()
                .width(PAGE_RAIL_THUMBNAIL_WIDTH - 18)
                .height(78)
                .backgroundColor('#EEF2F6')
                .borderRadius(14)
              Row()
                .width(PAGE_RAIL_THUMBNAIL_WIDTH - 34)
                .height(10)
                .backgroundColor('#DCE4EE')
                .borderRadius(8)
              Row()
                .width(PAGE_RAIL_THUMBNAIL_WIDTH - 46)
                .height(10)
                .backgroundColor('#E2E8F0')
                .borderRadius(8)
            }
            .position({ x: 9, y: 10 })
            .alignItems(HorizontalAlign.Start)
          } else if (this.pageSceneObjectsAt(pageIndex).length > 0) {
            Stack({ alignContent: Alignment.TopStart }) {
              ForEach(this.pageSceneObjectsAt(pageIndex), (object: NativeSceneObject) => {
                Row()
                  .width(this.pageRailObjectWidth(pageIndex, object))
                  .height(this.pageRailObjectHeight(pageIndex, object))
                  .backgroundColor(object.colorHex)
                  .opacity(object.tool === 'highlighter' ? 0.42 : 0.82)
                  .borderRadius(object.tool === 'text' ? 8 : 999)
                  .position({
                    x: this.pageRailObjectX(pageIndex, object),
                    y: this.pageRailObjectY(pageIndex, object)
                  })
              }, (object: NativeSceneObject): string => object.id)
            }
            .width(PAGE_RAIL_THUMBNAIL_WIDTH)
            .height(PAGE_RAIL_THUMBNAIL_HEIGHT)
          } else if (this.pagePreviewFallbackBlocks(pageIndex).length > 0) {
            Column({ space: 6 }) {
              ForEach(this.pagePreviewFallbackBlocks(pageIndex), (block: MarkdownPreviewBlock, blockIndex: number) => {
                Text(block.text)
                  .width(PAGE_RAIL_THUMBNAIL_WIDTH - 24)
                  .maxLines(blockIndex === 0 ? 2 : 1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontSize(block.type === 'heading' ? 10 : 8)
                  .fontWeight(block.type === 'heading' ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(blockIndex === 0 ? '#344054' : '#667085')
                  .lineHeight(block.type === 'heading' ? 14 : 12)
              }, (block: MarkdownPreviewBlock, blockIndex: number): string => `${pageIndex}-fallback-${block.type}-${blockIndex}`)
            }
            .position({ x: 12, y: 14 })
            .alignItems(HorizontalAlign.Start)
          }
        }
      }
      if (this.isSelectedPageIndex(pageIndex)) {
        Row()
          .width(PAGE_RAIL_THUMBNAIL_WIDTH)
          .height(PAGE_RAIL_THUMBNAIL_HEIGHT)
          .border({ width: 1.5, color: '#2A9D8F' })
          .borderRadius(PAGE_RAIL_CARD_RADIUS)
      }
    }
  }

  @Builder
  private buildRailMenu(): void {
    Column() {
      Button('快速导出')
        .width('100%')
        .height(44)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(14)
        .onClick(async () => {
          this.closeRailMenus();
          await this.saveDocument();
        })
      Button('导出选项')
        .width('100%')
        .height(44)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(14)
        .onClick(() => {
          this.noteUnsupportedMenuAction('导出选项');
        })
      Button('发布到图库')
        .width('100%')
        .height(44)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(14)
        .onClick(() => {
          this.noteUnsupportedMenuAction('发布到图库');
        })
      Button('创建链接')
        .width('100%')
        .height(44)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(14)
        .onClick(() => {
          this.noteUnsupportedMenuAction('创建链接');
        })
      Blank()
        .width('100%')
        .height(1)
        .backgroundColor('#E4E7EC')
      Button('模板设置')
        .width('100%')
        .height(44)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(14)
        .onClick(() => {
          this.noteUnsupportedMenuAction('模板设置');
        })
      Button('查看设置')
        .width('100%')
        .height(44)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(14)
        .onClick(() => {
          this.previewMode = 'preview';
          this.showInspectorDrawer = true;
          this.closeRailMenus();
        })
      Column() {
        Text(this.document?.title ?? '未命名笔记')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#101828')
          .maxLines(2)
        Text(`创建于: ${this.currentDocumentCreatedLabel()}`)
          .fontSize(12)
          .fontColor('#667085')
          .margin({ top: 4 })
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .margin({ top: 8 })
      Row({ space: 8 }) {
        Button(EDITOR_WORKSPACE_COPY.preview)
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.previewMode === 'preview' ? '#162033' : '#FFFFFF')
          .fontColor(this.previewMode === 'preview' ? '#FFFFFF' : '#162033')
          .fontSize(13)
          .borderRadius(14)
          .onClick(() => {
            this.previewMode = 'preview';
            this.showInspectorDrawer = true;
            this.closeRailMenus();
          })
        Button(EDITOR_WORKSPACE_COPY.source)
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.previewMode === 'source' ? '#162033' : '#FFFFFF')
          .fontColor(this.previewMode === 'source' ? '#FFFFFF' : '#162033')
          .fontSize(13)
          .borderRadius(14)
          .onClick(() => {
            this.previewMode = 'source';
            this.showInspectorDrawer = true;
            this.closeRailMenus();
          })
      }
      .margin({ top: 8 })
    }
    .width(PAGE_RAIL_MENU_WIDTH)
    .padding(12)
    .backgroundColor('#F9FAFB')
    .border({ width: 1, color: '#E4E7EC' })
    .borderRadius(20)
  }

  @Builder
  private buildPageMenu(pageIndex: number): void {
    Column() {
      Button('添加页面')
        .width('100%')
        .height(40)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(13)
        .onClick(async () => {
          this.closeRailMenus();
          await this.addPage();
        })
      Button('剪切')
        .width('100%')
        .height(40)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(13)
        .onClick(() => {
          this.noteUnsupportedMenuAction('剪切');
        })
      Button('拷贝')
        .width('100%')
        .height(40)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(13)
        .onClick(() => {
          this.noteUnsupportedMenuAction('拷贝');
        })
      Button('复制')
        .width('100%')
        .height(40)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(13)
        .onClick(async () => {
          await this.duplicateCurrentPage();
        })
      Button('创建模板')
        .width('100%')
        .height(40)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(13)
        .onClick(() => {
          this.noteUnsupportedMenuAction('创建模板');
        })
      Button('清除页面')
        .width('100%')
        .height(40)
        .backgroundColor('#FFFFFF')
        .fontColor('#101828')
        .fontSize(13)
        .onClick(async () => {
          await this.clearCurrentPageContent();
        })
      Button('删除')
        .width('100%')
        .height(40)
        .enabled(this.canDeleteCurrentPage())
        .backgroundColor('#FFFFFF')
        .fontColor('#F04438')
        .fontSize(13)
        .onClick(async () => {
          this.closeRailMenus();
          await this.deleteCurrentPage();
        })
    }
    .width(PAGE_RAIL_MENU_WIDTH)
    .padding(10)
    .backgroundColor('#F9FAFB')
    .border({ width: 1, color: '#E4E7EC' })
    .borderRadius(20)
  }

  @Builder
  private buildPreviewBlockList(blocks: MarkdownPreviewBlock[]): void {
    Scroll() {
      Column({ space: 10 }) {
        if (blocks.length === 0) {
          Text('暂无预览内容')
            .fontSize(13)
            .fontColor('#667085')
        } else {
          ForEach(blocks, (block: MarkdownPreviewBlock, index: number) => {
            if (block.type === 'heading') {
              Text(block.text)
                .fontSize(block.level <= 1 ? 22 : 18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#162033')
                .width('100%')
            } else if (block.type === 'formula') {
              Text(block.text)
                .fontSize(14)
                .fontColor('#0B57D0')
                .padding(12)
                .width('100%')
                .backgroundColor('#EEF4FF')
                .borderRadius(14)
            } else if (block.type === 'code') {
              Text(block.text)
                .fontSize(12)
                .fontColor('#E2E8F0')
                .padding(12)
                .width('100%')
                .backgroundColor('#162033')
                .borderRadius(14)
            } else {
              Text(block.type === 'list' ? `- ${block.text}` : block.text)
                .fontSize(14)
                .fontColor('#344054')
                .width('100%')
                .lineHeight(22)
            }
          }, (_: MarkdownPreviewBlock, index: number): string => `preview-${index}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 4, bottom: 8 })
    }
    .width('100%')
  }

  @Builder
  private buildIconBar(x: number, y: number, width: number, height: number, color: string, opacity: number): void {
    Blank()
      .width(width)
      .height(height)
      .backgroundColor(color)
      .borderRadius(999)
      .opacity(opacity)
      .position({ x, y })
  }

  @Builder
  private buildIconDot(x: number, y: number, size: number, color: string, opacity: number): void {
    Blank()
      .width(size)
      .height(size)
      .backgroundColor(color)
      .borderRadius(999)
      .opacity(opacity)
      .position({ x, y })
  }

  @Builder
  private buildIconOutline(x: number, y: number, width: number, height: number, color: string, radius: number): void {
    Blank()
      .width(width)
      .height(height)
      .backgroundColor('#00000000')
      .border({ width: 1.6, color })
      .borderRadius(radius)
      .position({ x, y })
  }

  @Builder
  private buildEditorIcon(icon: EditorUiIcon, color: string, size: number): void {
    Stack({ alignContent: Alignment.TopStart }) {
      if (icon === 'drag') {
        this.buildIconDot(4, 4, 2.4, color, 0.92)
        this.buildIconDot(4, 8, 2.4, color, 0.92)
        this.buildIconDot(4, 12, 2.4, color, 0.92)
        this.buildIconDot(9.5, 4, 2.4, color, 0.92)
        this.buildIconDot(9.5, 8, 2.4, color, 0.92)
        this.buildIconDot(9.5, 12, 2.4, color, 0.92)
      } else if (icon === 'back') {
        this.buildIconBar(4, 8, 10, 2, color, 1)
        this.buildIconBar(4, 5, 5, 2, color, 1)
        this.buildIconBar(2, 7, 4, 2, color, 1)
        this.buildIconBar(4, 11, 5, 2, color, 1)
        this.buildIconBar(2, 9, 4, 2, color, 1)
      } else if (icon === 'pen') {
        this.buildIconBar(8, 2, 2, 7, color, 1)
        this.buildIconBar(6, 9, 6, 2, color, 1)
        this.buildIconBar(7, 11, 4, 2, color, 1)
        this.buildIconBar(8, 13, 2, 3, color, 1)
      } else if (icon === 'pencil') {
        this.buildIconBar(3, 6, 9, 2, color, 1)
        this.buildIconBar(4, 8, 8, 2, color, 1)
        this.buildIconBar(11, 5, 3, 2, color, 1)
        this.buildIconBar(11, 9, 3, 2, color, 1)
        this.buildIconBar(2, 8, 2, 2, color, 0.55)
      } else if (icon === 'highlighter') {
        this.buildIconBar(5, 2, 8, 3, color, 1)
        this.buildIconBar(6, 5, 6, 7, color, 1)
        this.buildIconBar(3, 13, 12, 3, color, 0.4)
      } else if (icon === 'eraser') {
        this.buildIconBar(4, 5, 10, 7, color, 0.96)
        this.buildIconBar(4, 5, 10, 2, color, 0.45)
        this.buildIconBar(6, 12, 6, 2, color, 1)
      } else if (icon === 'text') {
        this.buildIconBar(4, 3, 10, 2, color, 1)
        this.buildIconBar(8, 5, 2, 8, color, 1)
        this.buildIconBar(4, 13, 10, 2, color, 1)
      } else if (icon === 'lasso') {
        this.buildIconDot(4, 6, 2.4, color, 0.92)
        this.buildIconDot(6.5, 3.5, 2.4, color, 0.92)
        this.buildIconDot(10, 3.5, 2.4, color, 0.92)
        this.buildIconDot(12.5, 6, 2.4, color, 0.92)
        this.buildIconDot(10, 9.5, 2.4, color, 0.92)
        this.buildIconDot(6.5, 9.5, 2.4, color, 0.92)
        this.buildIconBar(11.5, 11.5, 4, 2, color, 1)
      } else if (icon === 'fingerWriting') {
        this.buildIconBar(8, 2, 2, 8, color, 1)
        this.buildIconBar(5, 10, 8, 5, color, 1)
        this.buildIconBar(3, 9, 4, 2, color, 1)
        this.buildIconBar(10, 7, 3, 2, color, 1)
      } else if (icon === 'undo') {
        this.buildIconBar(6, 4, 6, 2, color, 1)
        this.buildIconBar(5, 4, 2, 6, color, 1)
        this.buildIconBar(2, 5, 4, 2, color, 1)
        this.buildIconBar(3, 7, 3, 2, color, 1)
      } else if (icon === 'redo') {
        this.buildIconBar(6, 4, 6, 2, color, 1)
        this.buildIconBar(11, 4, 2, 6, color, 1)
        this.buildIconBar(12, 5, 4, 2, color, 1)
        this.buildIconBar(12, 7, 3, 2, color, 1)
      } else if (icon === 'more') {
        this.buildIconDot(3, 7.2, 3, color, 1)
        this.buildIconDot(7.5, 7.2, 3, color, 1)
        this.buildIconDot(12, 7.2, 3, color, 1)
      } else if (icon === 'railCollapse') {
        this.buildIconBar(12, 2, 2, 14, color, 1)
        this.buildIconBar(4, 8, 6, 2, color, 1)
        this.buildIconBar(7, 5, 4, 2, color, 1)
        this.buildIconBar(7, 11, 4, 2, color, 1)
      } else if (icon === 'railExpand') {
        this.buildIconBar(2, 2, 2, 14, color, 1)
        this.buildIconBar(8, 8, 6, 2, color, 1)
        this.buildIconBar(7, 5, 4, 2, color, 1)
        this.buildIconBar(7, 11, 4, 2, color, 1)
      } else if (icon === 'addPage') {
        this.buildIconOutline(3, 2, 10, 13, color, 3)
        this.buildIconBar(7.8, 6, 1.8, 6, color, 1)
        this.buildIconBar(5.7, 8.1, 6, 1.8, color, 1)
      } else if (icon === 'bookmark') {
        this.buildIconBar(5, 2, 8, 2, color, 1)
        this.buildIconBar(5, 4, 2, 10, color, 1)
        this.buildIconBar(11, 4, 2, 10, color, 1)
        this.buildIconBar(7, 11, 4, 2, color, 1)
        this.buildIconBar(6, 13, 2, 2, color, 1)
        this.buildIconBar(10, 13, 2, 2, color, 1)
      }
    }
    .width(size)
    .height(size)
  }

  @Builder
  private buildToolbarToolButton(tool: ToolType): void {
    Stack({ alignContent: Alignment.Center }) {
      this.buildEditorIcon(this.toolIconKind(tool), this.currentTool === tool ? '#FFFFFF' : '#344054', 18)
    }
    .width(FLOATING_TOOL_BUTTON_SIZE)
    .height(FLOATING_TOOL_BUTTON_SIZE)
    .backgroundColor(this.currentTool === tool ? '#16324F' : '#FFFFFF')
    .border({ width: 1, color: this.currentTool === tool ? '#16324F' : '#D8E0EA' })
    .borderRadius(14)
    .onClick(() => {
      this.setTool(tool);
    })
  }

  @Builder
  private buildFingerWritingToggleButton(): void {
    Stack({ alignContent: Alignment.Center }) {
      this.buildEditorIcon('fingerWriting', this.fingerWritingEnabled ? '#FFFFFF' : '#344054', 18)
    }
    .width(FLOATING_TOOL_BUTTON_SIZE)
    .height(FLOATING_TOOL_BUTTON_SIZE)
    .backgroundColor(this.fingerWritingEnabled ? '#0F766E' : '#FFFFFF')
    .border({ width: 1, color: this.fingerWritingEnabled ? '#0F766E' : '#D8E0EA' })
    .borderRadius(14)
    .onClick(() => {
      this.toggleFingerWritingMode();
    })
  }

  @Builder
  private buildEmbeddedComposerPreview(): void {
    Scroll() {
      Column({ space: 10 }) {
        if (this.embeddedComposerVisibleBlocks().length === 0) {
          Text('暂无预览内容')
            .fontSize(13)
            .fontColor('#667085')
        } else {
          ForEach(this.embeddedComposerVisibleBlocks(), (block: MarkdownPreviewBlock, index: number) => {
            if (block.type === 'heading') {
              Text(block.text)
                .fontSize(block.level <= 1 ? 22 : 18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#162033')
                .width('100%')
            } else if (block.type === 'formula') {
              Text(block.text)
                .fontSize(14)
                .fontColor('#0B57D0')
                .padding(12)
                .width('100%')
                .backgroundColor('#EEF4FF')
                .borderRadius(14)
            } else if (block.type === 'code') {
              Text(block.text)
                .fontSize(12)
                .fontColor('#E2E8F0')
                .padding(12)
                .width('100%')
                .backgroundColor('#162033')
                .borderRadius(14)
            } else {
              Text(block.type === 'list' ? `- ${block.text}` : block.text)
                .fontSize(14)
                .fontColor('#344054')
                .width('100%')
                .lineHeight(22)
            }
          }, (block: MarkdownPreviewBlock, index: number): string =>
            `composer-preview-${this.embeddedComposerPreviewVersion}-${index}-${block.type}-${block.text}`
          )
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 4, bottom: 8 })
    }
    .width('100%')
  }

  @Builder
  private buildFloatingBackButton(): void {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        this.buildEditorIcon('back', '#162033', 18)
      }
        .width(42)
        .height(42)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#D8E0EA' })
        .borderRadius(16)
        .onClick(() => {
          this.goBack();
        })
    }
    .position({ x: 18, y: 18 })
  }

  @Builder
  private buildToolbarPrimaryRow(): void {
    if (this.toolbarUsesVerticalLayout()) {
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.Center }) {
          this.buildEditorIcon('drag', '#667085', 16)
        }
        .width('100%')
        .height(FLOATING_TOOL_BUTTON_SIZE - 2)
        .backgroundColor('#EEF2F6')
        .borderRadius(12)
        .gesture(
          PanGesture({ fingers: 1, distance: 0 })
            .onActionStart(() => {
              this.handleToolbarDragStart();
            })
            .onActionUpdate((event) => {
              this.updateToolbarDrag(event as Object);
            })
            .onActionEnd(() => {
              this.snapFloatingToolbarToNearestAnchor();
            })
        )
        ForEach([
          ToolType.PEN,
          ToolType.PENCIL,
          ToolType.ERASER,
          ToolType.TEXT,
          ToolType.LASSO,
          ToolType.HIGHLIGHTER
        ], (tool: ToolType) => {
          this.buildToolbarToolButton(tool)
        }, (tool: ToolType): string => `toolbar-${tool}`)
        this.buildFingerWritingToggleButton()
      }
      .width('100%')
    } else {
      Row({ space: 4 }) {
        Stack({ alignContent: Alignment.Center }) {
          this.buildEditorIcon('drag', '#667085', 16)
        }
        .height(FLOATING_TOOL_BUTTON_SIZE - 2)
        .padding({ left: 8, right: 8 })
        .backgroundColor('#EEF2F6')
        .borderRadius(12)
        .gesture(
          PanGesture({ fingers: 1, distance: 0 })
            .onActionStart(() => {
              this.handleToolbarDragStart();
            })
            .onActionUpdate((event) => {
              this.updateToolbarDrag(event as Object);
            })
            .onActionEnd(() => {
              this.snapFloatingToolbarToNearestAnchor();
            })
        )
        ForEach([
          ToolType.PEN,
          ToolType.PENCIL,
          ToolType.ERASER,
          ToolType.TEXT,
          ToolType.LASSO,
          ToolType.HIGHLIGHTER
        ], (tool: ToolType) => {
          this.buildToolbarToolButton(tool)
        }, (tool: ToolType): string => `toolbar-${tool}`)
        this.buildFingerWritingToggleButton()
        Blank()
          .layoutWeight(1)
      }
      .width('100%')
    }
  }

  @Builder
  private buildToolbarSecondaryRow(): void {
    if (this.toolUsesColorPalette() && this.toolbarUsesVerticalLayout()) {
      Column({ space: 8 }) {
        Text(this.secondaryToolbarAssistText())
          .width('100%')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#344054')
          .textAlign(TextAlign.Center)
        Column({ space: 6 }) {
          ForEach(PALETTE_COLORS, (color: string) => {
            Blank()
              .width(FLOATING_TOOLBAR_COLOR_CHIP_SIZE + 10)
              .height(FLOATING_TOOLBAR_COLOR_CHIP_SIZE + 10)
              .backgroundColor(color)
              .border({
                width: this.currentColor === color ? 3 : 1,
                color: this.currentColor === color ? '#16324F' : '#D0D5DD'
              })
              .borderRadius(999)
              .onClick(() => {
                this.currentColor = color;
                if (this.engineId.length > 0) {
                  this.nativeEngine.setBrushColor(this.engineId, color);
                  this.refreshDebugState();
                }
              })
          }, (color: string): string => `toolbar-color-${color}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        Text(this.secondaryToolbarHintText())
          .width('100%')
          .fontSize(10)
          .fontColor('#667085')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
    } else if (this.toolUsesColorPalette()) {
      Row({ space: 8 }) {
        Text(this.secondaryToolbarAssistText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#344054')
        ForEach(PALETTE_COLORS, (color: string) => {
          Blank()
            .width(FLOATING_TOOLBAR_COLOR_CHIP_SIZE)
            .height(FLOATING_TOOLBAR_COLOR_CHIP_SIZE)
            .backgroundColor(color)
            .border({
              width: this.currentColor === color ? 3 : 1,
              color: this.currentColor === color ? '#16324F' : '#D0D5DD'
            })
            .borderRadius(999)
            .onClick(() => {
              this.currentColor = color;
              if (this.engineId.length > 0) {
                this.nativeEngine.setBrushColor(this.engineId, color);
                this.refreshDebugState();
              }
            })
        }, (color: string): string => `toolbar-color-${color}`)
        Blank()
          .layoutWeight(1)
        Text(this.secondaryToolbarHintText())
          .fontSize(11)
          .fontColor('#667085')
      }
      .width('100%')
    } else if (this.toolUsesContextActions() && this.toolbarUsesVerticalLayout()) {
      Column({ space: 8 }) {
        Text(this.secondaryToolbarAssistText())
          .width('100%')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#344054')
          .textAlign(TextAlign.Center)
        Button(this.embedPlacementArmed ? '取消放置' : '插入图文')
          .width('100%')
          .height(34)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.embedPlacementArmed ? '#FEE4E2' : '#162033')
          .fontColor(this.embedPlacementArmed ? '#B42318' : '#FFFFFF')
          .fontSize(11)
          .borderRadius(12)
          .onClick(() => {
            if (this.embedPlacementArmed) {
              this.clearEmbeddedPlacement();
            } else {
              this.armEmbeddedPlacement();
            }
          })
        Button('预览')
          .width('100%')
          .height(32)
          .backgroundColor('#FFFFFF')
          .fontColor('#162033')
          .fontSize(11)
          .border({ width: 1, color: '#D8E0EA' })
          .borderRadius(12)
          .onClick(() => {
            this.previewMode = 'preview';
            this.showInspectorDrawer = true;
          })
        Button('源码')
          .width('100%')
          .height(32)
          .backgroundColor('#FFFFFF')
          .fontColor('#162033')
          .fontSize(11)
          .border({ width: 1, color: '#D8E0EA' })
          .borderRadius(12)
          .onClick(() => {
            this.previewMode = 'source';
            this.showInspectorDrawer = true;
          })
        Text(this.secondaryToolbarHintText())
          .width('100%')
          .fontSize(10)
          .fontColor('#667085')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
    } else if (this.toolUsesContextActions()) {
      Row({ space: 8 }) {
        Text(this.secondaryToolbarAssistText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#344054')
        Button(this.embedPlacementArmed ? '取消放置' : '插入图文')
          .height(34)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.embedPlacementArmed ? '#FEE4E2' : '#162033')
          .fontColor(this.embedPlacementArmed ? '#B42318' : '#FFFFFF')
          .fontSize(12)
          .borderRadius(12)
          .onClick(() => {
            if (this.embedPlacementArmed) {
              this.clearEmbeddedPlacement();
            } else {
              this.armEmbeddedPlacement();
            }
          })
        Button('预览')
          .height(34)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#FFFFFF')
          .fontColor('#162033')
          .fontSize(12)
          .border({ width: 1, color: '#D8E0EA' })
          .borderRadius(12)
          .onClick(() => {
            this.previewMode = 'preview';
            this.showInspectorDrawer = true;
          })
        Button('源码')
          .height(34)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#FFFFFF')
          .fontColor('#162033')
          .fontSize(12)
          .border({ width: 1, color: '#D8E0EA' })
          .borderRadius(12)
          .onClick(() => {
            this.previewMode = 'source';
            this.showInspectorDrawer = true;
          })
        Blank()
          .layoutWeight(1)
        Text(this.secondaryToolbarHintText())
          .fontSize(11)
          .fontColor('#667085')
          .maxLines(2)
      }
      .width('100%')
    }
  }

  @Builder
  private buildFloatingToolbarChrome(): void {
    Column({ space: 8 }) {
      this.buildToolbarPrimaryRow()
      if (this.shouldShowSecondaryToolbar()) {
        this.buildToolbarSecondaryRow()
      }
    }
    .width(this.floatingToolbarChromeWidth())
    .padding(10)
    .backgroundColor('#FFFFFFF2')
    .border({ width: 1, color: '#DCE5EE' })
    .borderRadius(18)
    .position({
      x: this.floatingToolbarPositionX(),
      y: this.floatingToolbarPositionY()
    })
  }

  @Builder
  private buildRailActionStrip(): void {
    Row({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.buildEditorIcon('undo', '#344054', 15)
      }
      .width(38)
      .height(38)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#D8E0EA' })
      .borderRadius(14)
      .onClick(() => {
        this.undoStroke();
      })
      Stack({ alignContent: Alignment.Center }) {
        this.buildEditorIcon('redo', '#344054', 15)
      }
      .width(38)
      .height(38)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#D8E0EA' })
      .borderRadius(14)
      .onClick(() => {
        this.redoStroke();
      })
      Blank()
        .layoutWeight(1)
      Stack({ alignContent: Alignment.Center }) {
        this.buildEditorIcon('more', '#344054', 15)
      }
      .width(38)
      .height(38)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#D8E0EA' })
      .borderRadius(14)
      .onClick(() => {
        this.toggleRailMenu();
      })
      Stack({ alignContent: Alignment.Center }) {
        this.buildEditorIcon(this.railToggleIconKind(), '#162033', 15)
      }
      .width(38)
      .height(38)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#D8E0EA' })
      .borderRadius(14)
      .onClick(() => {
        this.setRailCollapsed(!this.railCollapsed);
      })
    }
    .width('100%')
    .padding(6)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#DCE5EE' })
    .borderRadius(18)
  }

  @Builder
  private buildCanvasActionGroup(): void {
    if (this.railCollapsed) {
      Column({ space: 10 }) {
        this.buildRailActionStrip()
        if (this.showRailMenu) {
          this.buildRailMenu()
        }
      }
      .width(172)
      .position({ x: Math.max(18, this.writingViewportWidth - 188), y: 18 })
    }
  }

  @Builder
  private buildPageHud(): void {
    if (this.showPageHud || this.showPageJumpInput) {
      Column({ space: 8 }) {
        if (this.showPageJumpInput) {
          Row({ space: 8 }) {
            TextInput({ text: this.pageJumpDraft, placeholder: `${this.activePageIndex + 1}` })
              .width(72)
              .height(36)
              .textAlign(TextAlign.Center)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .onChange((value: string) => {
                this.pageJumpDraft = value.replace(/[^0-9]/g, '');
              })
            Button('前往')
              .height(36)
              .enabled(this.pageJumpTargetIndex() >= 0)
              .backgroundColor('#162033')
              .fontColor('#FFFFFF')
              .fontSize(11)
              .padding({ left: 12, right: 12 })
              .borderRadius(12)
              .onClick(async () => {
                await this.jumpToDraftPage();
              })
          }
        } else {
          Button(this.pageHudLabel())
            .height(38)
            .padding({ left: 14, right: 14 })
            .backgroundColor('#FFFFFF')
            .fontColor('#162033')
            .fontSize(12)
            .borderRadius(14)
            .onClick(() => {
              this.openPageJumpInput();
            })
        }
      }
      .padding(8)
      .backgroundColor('#FFFFFFE8')
      .border({ width: 1, color: '#DCE5EE' })
      .borderRadius(18)
      .position({
        x: Math.max(20, this.writingViewportWidth - (this.showPageJumpInput ? 168 : 132) - 20),
        y: Math.max(92, this.writingViewportHeight - 86)
      })
    }
  }

  @Builder
  private buildPageEmbeddedOverlayLayer(pageIndex: number): void {
    ForEach(this.pageEmbeddedBlocksAt(pageIndex), (block: EmbeddedOverlayDraft) => {
      Column({ space: 6 }) {
        Text(block.kind.toUpperCase())
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Text(this.embeddedBlockPlainText(block))
          .fontSize(12)
          .fontColor('#344054')
          .lineHeight(18)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width(this.embeddedBlockPixelWidth(pageIndex, block))
      .height(this.embeddedBlockPixelHeight(pageIndex, block))
      .padding(12)
      .backgroundColor('#FFFCF3')
      .border({ width: 1, color: '#E9D7A5' })
      .borderRadius(16)
      .opacity(0.96)
      .position({
        x: this.embeddedBlockPixelX(pageIndex, block),
        y: this.embeddedBlockPixelY(pageIndex, block)
      })
    }, (block: EmbeddedOverlayDraft): string => `embedded-${pageIndex}-${block.id}`)
  }

  @Builder
  private buildEmbeddedSelectionOverlay(pageIndex: number): void {
    if (this.embedPlacementArmed && this.isSelectedPageIndex(pageIndex)) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor('#01000000')
          .gesture(
            PanGesture({ fingers: 1, distance: 0 })
              .onActionStart((event) => {
                this.beginEmbeddedSelection(event as Object, pageIndex);
              })
              .onActionUpdate((event) => {
                this.updateEmbeddedSelection(event as Object);
              })
              .onActionEnd(() => {
                this.finishEmbeddedSelection();
              })
          )
        if (this.embedSelectionVisible && this.embedSelectionPageId === this.pageKeyAt(pageIndex)) {
          Row()
            .width(this.embedSelectionWidth)
            .height(this.embedSelectionHeight)
            .border({ width: 2, color: '#0F766E' })
            .backgroundColor('#160F766E')
            .borderRadius(14)
            .position({ x: this.embedSelectionX, y: this.embedSelectionY })
          Text('Drag a rectangle on the active page.')
            .fontSize(12)
            .fontColor('#0F766E')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#CFE7DF' })
            .borderRadius(14)
            .position({ x: 18, y: 18 })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildWritingPageFallback(pageIndex: number): void {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pagePreviewSnapshotAt(pageIndex) !== undefined) {
        PreviewThumbnail({
          previewSnapshot: this.pagePreviewSnapshotAt(pageIndex) as DocumentPreviewSnapshot,
          fallbackSummary: '',
          thumbnailWidth: this.renderedWritingPageWidth(pageIndex),
          thumbnailHeight: this.renderedWritingPageHeight(pageIndex)
        })
      } else {
        Column({ space: 8 }) {
          Text(this.pagePlaceholderTitle(pageIndex))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#162033')
            .margin({ top: 18, left: 18, right: 18 })
            .width('100%')
          Text(this.pagePlaceholderDetail(pageIndex))
            .fontSize(12)
            .fontColor('#667085')
            .margin({ left: 18, right: 18 })
            .width('100%')
          Column({ space: 8 }) {
            ForEach(this.pagePreviewFallbackBlocks(pageIndex), (block: MarkdownPreviewBlock, blockIndex: number) => {
              Text(block.type === 'list' ? `- ${block.text}` : block.text)
                .fontSize(block.type === 'heading' ? 15 : 13)
                .fontWeight(block.type === 'heading' ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(block.type === 'heading' ? '#162033' : '#475467')
                .lineHeight(block.type === 'heading' ? 22 : 20)
                .maxLines(blockIndex === 0 ? 4 : 3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }, (_: MarkdownPreviewBlock, blockIndex: number): string => `page-fallback-${pageIndex}-${blockIndex}`)
          }
          .margin({ left: 18, right: 18, top: 8 })
          .width(this.renderedWritingPageWidth(pageIndex) - 36)
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#FFFDF8')
        .alignItems(HorizontalAlign.Start)
      }
      this.buildPageEmbeddedOverlayLayer(pageIndex)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildContinuousWritingPage(pageIndex: number): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width(this.renderedWritingPageWidth(pageIndex))
        .height(this.renderedWritingPageHeight(pageIndex))
        .backgroundColor('#FFFEFC')
        .border({
          width: this.isSelectedPageIndex(pageIndex) ? 1.5 : 1,
          color: this.isSelectedPageIndex(pageIndex) ? '#C8D6E4' : '#E4EBF2'
        })
        .borderRadius(18)
      if (this.isSelectedPageIndex(pageIndex)) {
        this.buildPageMotionLayer()
        this.buildPageEmbeddedOverlayLayer(pageIndex)
        this.buildEmbeddedSelectionOverlay(pageIndex)
      } else {
        this.buildWritingPageFallback(pageIndex)
      }
    }
    .width(this.renderedWritingPageWidth(pageIndex))
    .height(this.renderedWritingPageHeight(pageIndex))
    .position({ x: this.pageCardOffsetX(pageIndex), y: this.pageCardOffsetY(pageIndex) })
  }

  @Builder
  private buildContinuousWritingViewport(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#EEF2F8')
      ForEach(this.pageIndexes(), (pageIndex: number) => {
        this.buildContinuousWritingPage(pageIndex)
      }, (pageIndex: number): string => `writing-page-${this.pageKeyAt(pageIndex)}`)
      if (!this.showTracePanel) {
        Row() {
          this.buildBottomHint()
        }
        .position({ x: 18, y: Math.max(18, this.writingViewportHeight - 58) })
      }
      if (this.showTracePanel) {
        Row() {
          this.buildTracePanel()
        }
        .position({ x: 18, y: Math.max(92, this.writingViewportHeight - 260) })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_, newValue) => {
      this.updateWritingViewportSize(newValue);
    })
    .gesture(
      GestureGroup(
        GestureMode.Parallel,
        LongPressGesture({ repeat: false, duration: 600 })
          .onAction(() => {
            if (!this.embedPlacementArmed) {
              this.toggleTracePanel();
            }
          }),
        PanGesture({ fingers: 1, distance: this.canHandleSingleFingerSurfaceGesture() ? 0 : 100000 })
          .onActionStart(() => {
            this.handleViewportPanStart();
          })
          .onActionUpdate((event) => {
            if (this.shouldHandleSimulatorFingerWritingGesture()) {
              this.updateSimulatorFingerGesture(event as Object);
              return;
            }
            this.updateViewportPan(event as Object, 1);
          })
          .onActionEnd(async (event) => {
            if (this.simulatorFingerGestureActive || this.shouldHandleSimulatorFingerWritingGesture()) {
              this.finishSimulatorFingerGesture(event as Object);
              return;
            }
            await this.finishViewportPan(1);
          }),
        PanGesture({ fingers: 2, distance: this.canTwoFingerPanViewport() ? 0 : 100000 })
          .onActionStart(() => {
            this.handleViewportPanStart();
          })
          .onActionUpdate((event) => {
            this.updateViewportPan(event as Object, 2);
          })
          .onActionEnd(async () => {
            await this.finishViewportPan(2);
          }),
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.handleViewportPinchStart();
          })
          .onActionUpdate((event) => {
            this.updateViewportPinch(event as Object);
          })
          .onActionEnd(async () => {
            await this.finishViewportPinch();
          })
      )
    )
  }

  @Builder
  private buildInspectorModal(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#660B1F33')
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(this.previewMode === 'preview' ? '页面预览' : '源码')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#162033')
          Blank()
            .layoutWeight(1)
          Button('预览')
            .height(34)
            .backgroundColor(this.previewMode === 'preview' ? '#162033' : '#FFFFFF')
            .fontColor(this.previewMode === 'preview' ? '#FFFFFF' : '#162033')
            .fontSize(12)
            .borderRadius(12)
            .onClick(() => {
              this.previewMode = 'preview';
            })
          Button('源码')
            .height(34)
            .backgroundColor(this.previewMode === 'source' ? '#162033' : '#FFFFFF')
            .fontColor(this.previewMode === 'source' ? '#FFFFFF' : '#162033')
            .fontSize(12)
            .borderRadius(12)
            .onClick(() => {
              this.previewMode = 'source';
            })
          Button('关闭')
            .height(34)
            .backgroundColor('#F3F6FB')
            .fontColor('#162033')
            .fontSize(12)
            .borderRadius(12)
            .onClick(() => {
              this.closeInspector();
            })
        }
        if (this.previewMode === 'preview') {
          this.buildPreviewDrawerBody()
        } else {
          this.buildSourceDrawerBody()
        }
      }
      .width(EDITOR_INSPECTOR_WIDTH)
      .height(Math.max(420, this.writingViewportHeight - 96))
      .padding(18)
      .backgroundColor('#FFFFFF')
      .borderRadius(26)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildEmbeddedComposerModal(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#660B1F33')
      Column({ space: 16 }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text('插入图文 / 公式')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#162033')
            Text('左侧输入，右侧实时预览。')
              .fontSize(12)
              .fontColor('#667085')
          }
          .layoutWeight(1)
          Button('取消')
            .height(36)
            .padding({ left: 14, right: 14 })
            .backgroundColor('#FFFFFF')
            .fontColor('#344054')
            .fontSize(12)
            .border({ width: 1, color: '#D0D5DD' })
            .borderRadius(12)
            .onClick(() => {
              this.cancelEmbeddedComposer();
            })
          Text('预览')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#162033')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor('#EEF2F6')
            .borderRadius(12)
          Button('完成')
            .height(36)
            .padding({ left: 14, right: 14 })
            .backgroundColor('#162033')
            .fontColor('#FFFFFF')
            .fontSize(12)
            .borderRadius(12)
            .enabled(this.embeddedComposerText.trim().length > 0)
            .onClick(async () => {
              await this.commitEmbeddedComposer();
            })
        }
        if (this.shouldUseWideComposerLayout()) {
          Row({ space: 14 }) {
            Column({ space: 8 }) {
              Text('输入')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#162033')
                .width('100%')
              TextArea({
                text: this.embeddedComposerText,
                placeholder: EDITOR_WORKSPACE_COPY.sourcePlaceholder
              })
                .layoutWeight(1)
                .backgroundColor('#FFFFFF')
                .border({ width: 1, color: '#D0D5DD' })
                .borderRadius(18)
                .padding(16)
                .onChange((value: string) => {
                  this.embeddedComposerText = value;
                  this.embeddedComposerPreviewVersion += 1;
                })
            }
            .layoutWeight(1)
            .height('100%')
            .padding(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(18)
            Column({ space: 8 }) {
              Text('实时预览')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#162033')
                .width('100%')
              this.buildEmbeddedComposerPreview()
            }
            .layoutWeight(1)
            .height('100%')
            .padding(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(18)
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          Column({ space: 12 }) {
            Column({ space: 8 }) {
              Text('输入')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#162033')
                .width('100%')
              TextArea({
                text: this.embeddedComposerText,
                placeholder: EDITOR_WORKSPACE_COPY.sourcePlaceholder
              })
                .height(176)
                .backgroundColor('#FFFFFF')
                .border({ width: 1, color: '#D0D5DD' })
                .borderRadius(18)
                .padding(16)
                .onChange((value: string) => {
                  this.embeddedComposerText = value;
                  this.embeddedComposerPreviewVersion += 1;
                })
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(18)
            Column({ space: 8 }) {
              Text('实时预览')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#162033')
                .width('100%')
              this.buildEmbeddedComposerPreview()
            }
            .width('100%')
            .layoutWeight(1)
            .padding(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(18)
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width(this.embeddedComposerModalWidth())
      .height(Math.max(520, this.writingViewportHeight - 88))
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(28)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildModernPageRailItem(pageIndex: number): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildPageRailPreviewCard(pageIndex)
        Stack({ alignContent: Alignment.Center }) {
          this.buildEditorIcon('bookmark', this.isPageBookmarked(pageIndex) ? '#FFFFFF' : '#344054', 14)
        }
          .height(28)
          .width(28)
          .backgroundColor(this.isPageBookmarked(pageIndex) ? '#16324F' : '#FFFFFF')
          .border({ width: 1, color: this.isPageBookmarked(pageIndex) ? '#16324F' : '#D8E0EA' })
          .borderRadius(10)
          .position({ x: PAGE_RAIL_THUMBNAIL_WIDTH - 36, y: 8 })
          .onClick(async () => {
            await this.toggleBookmarkForPage(pageIndex);
          })
        Stack({ alignContent: Alignment.Center }) {
          this.buildEditorIcon('more', '#475467', 15)
        }
          .width(28)
          .height(28)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#D8E0EA' })
          .borderRadius(10)
          .position({ x: 8, y: PAGE_RAIL_THUMBNAIL_HEIGHT - 36 })
          .onClick(async () => {
            await this.togglePageMenu(pageIndex);
          })
      }
      Row() {
        Text(`第${pageIndex + 1}页`)
          .fontSize(11)
          .fontWeight(this.isSelectedPageIndex(pageIndex) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.isSelectedPageIndex(pageIndex) ? '#0F766E' : '#475467')
        Blank()
          .layoutWeight(1)
        if (this.pageHasNotes(pageIndex)) {
          Text('笔记')
            .fontSize(10)
            .fontColor('#667085')
        }
      }
      .width(PAGE_RAIL_THUMBNAIL_WIDTH)
      if (this.isPageMenuOpen(pageIndex)) {
        this.buildPageMenu(pageIndex)
      }
    }
    .width('100%')
    .padding({ top: 2, bottom: 10 })
    .alignItems(HorizontalAlign.Center)
    .onClick(async () => {
      await this.focusPageInViewport(pageIndex);
    })
  }

  @Builder
  private buildModernPageRail(): void {
    if (!this.railCollapsed) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 10 }) {
          this.buildRailActionStrip()
          if (this.showRailMenu) {
            this.buildRailMenu()
          }
          TextInput({ text: this.pageSearchText, placeholder: '搜索页面' })
            .width('100%')
            .height(34)
            .backgroundColor('#FFFFFF')
            .fontSize(12)
            .borderRadius(12)
            .onChange((value: string) => {
              this.pageSearchText = value;
            })
          Column({ space: 6 }) {
            Button(this.pageRailFilterLabel())
              .height(32)
              .width('100%')
              .padding({ left: 12, right: 12 })
              .backgroundColor('#FFFFFF')
              .fontColor('#344054')
              .fontSize(11)
              .borderRadius(12)
              .onClick(() => {
                this.toggleRailFilterMenu();
              })
            if (this.showRailFilterMenu) {
              Column({ space: 4 }) {
                ForEach(PAGE_RAIL_FILTER_OPTIONS, (filter: PageRailFilter) => {
                  Button(this.pageRailFilterLabel(filter))
                    .width('100%')
                    .height(30)
                    .backgroundColor(this.pageRailFilter === filter ? '#162033' : '#FFFFFF')
                    .fontColor(this.pageRailFilter === filter ? '#FFFFFF' : '#344054')
                    .fontSize(11)
                    .borderRadius(10)
                    .onClick(() => {
                      this.applyRailFilter(filter);
                    })
                }, (filter: PageRailFilter): string => `rail-filter-${filter}`)
              }
              .width('100%')
              .padding(6)
              .backgroundColor('#FFFFFFF6')
              .border({ width: 1, color: '#D8E0EA' })
              .borderRadius(14)
            }
          }
          .width('100%')
          Scroll() {
            Column({ space: 6 }) {
              ForEach(this.filteredPageIndexes(), (pageIndex: number) => {
                this.buildModernPageRailItem(pageIndex)
              }, (pageIndex: number): string => `modern-page-rail-${this.pageKeyAt(pageIndex)}`)
            }
            .width('100%')
            .padding({ top: 6, bottom: 20 })
          }
          .layoutWeight(1)
        }
        .width(EDITOR_PAGE_RAIL_WIDTH)
        .height('100%')
        .padding({ top: 12, right: 10, bottom: 10, left: 10 })
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#D8E0EA' })
        .borderRadius(18)
        if (this.canAddRealPages()) {
          Button('多选')
            .height(30)
            .padding({ left: 10, right: 10 })
            .backgroundColor('#162033')
            .fontColor('#FFFFFF')
            .fontSize(10)
            .borderRadius(12)
            .position({ x: EDITOR_PAGE_RAIL_WIDTH - 58, y: -8 })
            .onClick(() => {
              this.noteUnsupportedMenuAction('多选');
            })
        }
      }
    }
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
        Row({ space: this.railCollapsed ? 0 : 8 }) {
          Stack({ alignContent: Alignment.TopStart }) {
            this.buildContinuousWritingViewport()
            this.buildFloatingBackButton()
            this.buildFloatingToolbarChrome()
            this.buildCanvasActionGroup()
            this.buildPageHud()
            if (this.showInspectorDrawer) {
              this.buildInspectorModal()
            }
            if (this.showEmbeddedComposer) {
              this.buildEmbeddedComposerModal()
            }
          }
          .layoutWeight(1)
          .height('100%')
          .backgroundColor('#EEF3F8')
          .borderRadius(22)
          if (!this.railCollapsed) {
            this.buildModernPageRail()
          }
        }
        .width('100%')
        .height('100%')
        .padding(8)
        .backgroundColor('#E8EEF5')
      }
    }
  }
}

