import {
  DEFAULT_DOCUMENT_PAGE_METADATA,
  DocumentPageMetadata,
  getBlankPageTemplateById,
  getPageSizeById,
  getPaperBackgroundById,
  ResolvedDocumentPageMetadata,
  TemplatePrimitive,
  TemplatePrimitiveType,
  resolveDocumentPageMetadata
} from './BlankPageTemplates';
import { DocumentMode, DocumentPageEntry, DocumentRecord, DocumentType, ToolType } from './NoteModels';

const POINTS_PER_MM: number = 72 / 25.4;
const FALLBACK_PAGE_WIDTH_MM: number = 216;
const FALLBACK_PAGE_HEIGHT_MM: number = 279;
const FALLBACK_FILL_COLOR: string = '#FFFFFF';
const FALLBACK_ACCENT_COLOR: string = '#D0D5DD';

export const NATIVE_PRIMARY_PAGE_ID: string = 'page-0';
export const NATIVE_PLACEHOLDER_PDF_NODE_ID: string = 'pdf-page-0';
export const NATIVE_PAGE_CONTRACT_SCHEMA_VERSION: number = 1;

export type NativeLayerId = 'pdf' | 'ink' | 'transient';
export type NativeGuideKind = 'plain' | 'lined' | 'grid' | 'dotted' | 'cornell' | 'weekly';
export type NativeGuidePrimitiveKind = 'horizontalLines' | 'grid' | 'dots' | 'divider' | 'header' | 'sidebar' | 'label';

export interface NativeRatioBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface NativeGuideContract {
  guideKind: NativeGuideKind;
  contentBounds: NativeRatioBounds;
  spacingX?: number;
  spacingY?: number;
  secondarySpacingY?: number;
  accentLineX?: number;
  dividerX?: number;
  dividerY?: number;
  headerHeight?: number;
  columnCount?: number;
  dotRadius?: number;
}

export interface NativeGuidePrimitive {
  id: string;
  kind: NativeGuidePrimitiveKind;
  x: number;
  y: number;
  width: number;
  height: number;
  stroke?: string;
  fill?: string;
  strokeWidth?: number;
  opacity?: number;
  spacingX?: number;
  spacingY?: number;
  dotRadius?: number;
  text?: string;
  metadata?: Record<string, string | number | boolean>;
}

export interface NativeCornellGuideConfig {
  headerHeight: number;
  cueColumnStart: number;
  cueColumnWidth: number;
  noteColumnStart: number;
  noteColumnWidth: number;
  summaryTop: number;
  summaryHeight: number;
  cueRuleSpacing: number;
  noteRuleSpacing: number;
}

export interface NativeWeeklyGuideConfig {
  headerHeight: number;
  dayColumnCount: number;
  weekGridTop: number;
  weekGridHeight: number;
  dayColumnWidth: number;
  notesTop: number;
  notesHeight: number;
  noteRuleSpacing: number;
}

export interface NativePageContract {
  schemaVersion: number;
  pageId: string;
  pageTemplateId: string;
  pageSizeId: string;
  widthPt: number;
  heightPt: number;
  paperBackgroundId: string;
  fill: string;
  accent: string;
  guideKind: NativeGuideKind;
  primitives: NativeGuidePrimitive[];
  cornell?: NativeCornellGuideConfig;
  weekly?: NativeWeeklyGuideConfig;
  fillColor: string;
  accentColor: string;
  guide: NativeGuideContract;
}

export interface NativeDocumentPageConfig {
  id: string;
  order: number;
  pageKind: string;
  pageTemplateId: string;
  pageSizeId: string;
  paperBackgroundId: string;
  sourceAttachmentId?: string;
  sourcePageIndex?: number;
}

export interface NativeOpenDocumentConfig {
  documentType: string;
  title: string;
  preferredTool: ToolType;
  pageTemplateId: string;
  pageSizeId: string;
  paperBackgroundId: string;
  pageContract: NativePageContract;
  activePageId?: string;
  pages?: NativeDocumentPageConfig[];
  pageContracts?: Record<string, NativePageContract>;
}

export interface NativePreviewBounds {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface NativePreviewPage {
  pageId: string;
  pageIndex: number;
  width?: number;
  height?: number;
  bounds?: NativePreviewBounds;
  backgroundId?: string;
  guideKind?: NativeGuideKind;
}

export interface NativePreviewLayout {
  mode?: string;
  pageCount: number;
  documentBounds?: NativePreviewBounds;
  pages: NativePreviewPage[];
}

export interface NativePreviewPayload {
  status: string;
  previewSchemaVersion: number;
  pageIndex: number;
  pageId?: string;
  targetMode: string;
  coordinateSpace?: string;
  targetBounds?: NativePreviewBounds;
  layout?: NativePreviewLayout;
  layers: NativeLayerId[];
  checkpointCount: number;
  objectCount: number;
}

export interface NativeSceneObjectBounds {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface NativeSceneObject {
  id: string;
  nodeType: string;
  shapeType: string;
  tool: string;
  colorHex: string;
  selected: boolean;
  pointCount: number;
  closed: boolean;
  bounds: NativeSceneObjectBounds;
  layer: NativeLayerId;
  pageIndex?: number | null;
  pageId?: string;
}

export interface NativeSceneSnapshot {
  status: string;
  version: number;
  engineId: string;
  documentId: string;
  title: string;
  documentType: string;
  mode: string;
  backend: string;
  coordinateSpace?: string;
  checkpointCount: number;
  objectCount: number;
  layout?: NativePreviewLayout;
  pages: NativePreviewPage[];
  objects: NativeSceneObject[];
}

export interface NativePreviewRequestSize {
  width: number;
  height: number;
}

function createRatioBounds(x: number, y: number, width: number, height: number): NativeRatioBounds {
  return {
    x,
    y,
    width,
    height
  };
}

function createGuideContract(
  guideKind: NativeGuideKind,
  contentBounds: NativeRatioBounds,
  spacingX?: number,
  spacingY?: number,
  secondarySpacingY?: number,
  accentLineX?: number,
  dividerX?: number,
  dividerY?: number,
  headerHeight?: number,
  columnCount?: number,
  dotRadius?: number
): NativeGuideContract {
  return {
    guideKind,
    contentBounds,
    spacingX,
    spacingY,
    secondarySpacingY,
    accentLineX,
    dividerX,
    dividerY,
    headerHeight,
    columnCount,
    dotRadius
  };
}

const NATIVE_GUIDE_TEMPLATE_CONTRACTS: Map<string, NativeGuideContract> = new Map<string, NativeGuideContract>([
  ['blank', createGuideContract('plain', createRatioBounds(0.04, 0.03, 0.92, 0.94))],
  ['lined', createGuideContract('lined', createRatioBounds(0.08, 0.10, 0.84, 0.82), undefined, 0.05, undefined, 0.16)],
  ['grid', createGuideContract('grid', createRatioBounds(0.08, 0.08, 0.84, 0.84), 0.05, 0.05)],
  ['dotted', createGuideContract('dotted', createRatioBounds(0.08, 0.08, 0.84, 0.84), 0.05, 0.05, undefined, undefined, undefined, undefined, undefined, undefined, 1.5)],
  ['cornell', createGuideContract('cornell', createRatioBounds(0.06, 0.15, 0.88, 0.78), undefined, 0.06, 0.10, undefined, 0.30, 0.76, 0.08)],
  ['weekly_planner', createGuideContract('weekly', createRatioBounds(0.05, 0.14, 0.90, 0.79), 0.128, 0.12, 0.045, undefined, undefined, 0.73, 0.08, 7)]
]);

function cloneRatioBounds(bounds: NativeRatioBounds): NativeRatioBounds {
  return {
    x: bounds.x,
    y: bounds.y,
    width: bounds.width,
    height: bounds.height
  };
}

function cloneGuideContract(source: NativeGuideContract): NativeGuideContract {
  return {
    guideKind: source.guideKind,
    contentBounds: cloneRatioBounds(source.contentBounds),
    spacingX: source.spacingX,
    spacingY: source.spacingY,
    secondarySpacingY: source.secondarySpacingY,
    accentLineX: source.accentLineX,
    dividerX: source.dividerX,
    dividerY: source.dividerY,
    headerHeight: source.headerHeight,
    columnCount: source.columnCount,
    dotRadius: source.dotRadius
  };
}

function mapTemplatePrimitiveKind(type: TemplatePrimitiveType): NativeGuidePrimitiveKind {
  switch (type) {
    case 'horizontal_lines':
      return 'horizontalLines';
    case 'grid':
      return 'grid';
    case 'dots':
      return 'dots';
    case 'divider':
      return 'divider';
    case 'sidebar':
      return 'sidebar';
    case 'label':
      return 'label';
    default:
      return 'header';
  }
}

function toNativeGuidePrimitive(primitive: TemplatePrimitive): NativeGuidePrimitive {
  const normalized: NativeGuidePrimitive = {
    id: primitive.id,
    kind: mapTemplatePrimitiveKind(primitive.type),
    x: primitive.bounds.x,
    y: primitive.bounds.y,
    width: primitive.bounds.width,
    height: primitive.bounds.height
  };
  if (primitive.strokeColor !== undefined) {
    normalized.stroke = primitive.strokeColor;
  }
  if (primitive.fillColor !== undefined) {
    normalized.fill = primitive.fillColor;
  }
  if (primitive.strokeWidth !== undefined) {
    normalized.strokeWidth = primitive.strokeWidth;
  }
  if (primitive.opacity !== undefined) {
    normalized.opacity = primitive.opacity;
  }
  if (primitive.spacingX !== undefined) {
    normalized.spacingX = primitive.spacingX;
  }
  if (primitive.spacingY !== undefined) {
    normalized.spacingY = primitive.spacingY;
  }
  if (primitive.dotRadius !== undefined) {
    normalized.dotRadius = primitive.dotRadius;
  }
  if (primitive.text !== undefined) {
    normalized.text = primitive.text;
  }
  if (primitive.metadata !== undefined) {
    normalized.metadata = primitive.metadata;
  }
  return normalized;
}

function buildNativeGuidePrimitives(pageTemplateId?: string): NativeGuidePrimitive[] {
  const template = getBlankPageTemplateById(pageTemplateId ?? DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId);
  const primitives: NativeGuidePrimitive[] = [];
  (template?.layout ?? []).forEach((primitive) => {
    primitives.push(toNativeGuidePrimitive(primitive));
  });
  return primitives;
}

function buildNativeCornellGuideConfig(): NativeCornellGuideConfig {
  return {
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
}

function buildNativeWeeklyGuideConfig(): NativeWeeklyGuideConfig {
  return {
    headerHeight: 0.08,
    dayColumnCount: 7,
    weekGridTop: 0.14,
    weekGridHeight: 0.56,
    dayColumnWidth: 0.128,
    notesTop: 0.77,
    notesHeight: 0.16,
    noteRuleSpacing: 0.045
  };
}

export function buildPageId(pageIndex: number): string {
  return `page-${Math.max(0, Math.trunc(pageIndex))}`;
}

export function buildDefaultPreviewLayers(documentType: DocumentType): NativeLayerId[] {
  if (documentType === DocumentType.PDF || documentType === DocumentType.HYBRID) {
    return ['pdf', 'ink'];
  }
  return ['ink'];
}

export function buildNativeGuideContract(pageTemplateId?: string): NativeGuideContract {
  const templateId: string = pageTemplateId && pageTemplateId.length > 0
    ? pageTemplateId
    : DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId;
  const contract: NativeGuideContract = NATIVE_GUIDE_TEMPLATE_CONTRACTS.get(templateId) ??
    (NATIVE_GUIDE_TEMPLATE_CONTRACTS.get(DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId) as NativeGuideContract);
  return cloneGuideContract(contract);
}

export function buildNativePageContractFromMetadata(
  metadata: DocumentPageMetadata | ResolvedDocumentPageMetadata | undefined,
  pageId: string = NATIVE_PRIMARY_PAGE_ID
): NativePageContract {
  const resolvedMetadata: DocumentPageMetadata = {
    pageTemplateId: metadata?.pageTemplateId,
    pageSizeId: metadata?.pageSizeId,
    paperBackgroundId: metadata?.paperBackgroundId
  };
  const resolved: ResolvedDocumentPageMetadata = resolveDocumentPageMetadata(
    resolvedMetadata,
    DEFAULT_DOCUMENT_PAGE_METADATA
  );
  const pageSizeId: string = resolved.pageSizeId || 'letter_optimized';
  const paperBackgroundId: string = resolved.paperBackgroundId || DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId;
  const pageSize = getPageSizeById(pageSizeId);
  const paperBackground = getPaperBackgroundById(paperBackgroundId);
  const widthMm: number = pageSize ? pageSize.width : FALLBACK_PAGE_WIDTH_MM;
  const heightMm: number = pageSize ? pageSize.height : FALLBACK_PAGE_HEIGHT_MM;
  const guideContract: NativeGuideContract = buildNativeGuideContract(resolved.pageTemplateId);
  const guideKind: NativeGuideKind = guideContract.guideKind;
  const primitives: NativeGuidePrimitive[] = buildNativeGuidePrimitives(resolved.pageTemplateId);
  const fill: string = paperBackground ? paperBackground.fillColor : FALLBACK_FILL_COLOR;
  const accent: string = paperBackground ? paperBackground.accentColor : FALLBACK_ACCENT_COLOR;

  const contract: NativePageContract = {
    schemaVersion: NATIVE_PAGE_CONTRACT_SCHEMA_VERSION,
    pageId,
    pageTemplateId: resolved.pageTemplateId,
    pageSizeId,
    widthPt: Math.round(widthMm * POINTS_PER_MM * 1000) / 1000,
    heightPt: Math.round(heightMm * POINTS_PER_MM * 1000) / 1000,
    paperBackgroundId,
    fill,
    accent,
    guideKind,
    primitives,
    fillColor: fill,
    accentColor: accent,
    guide: guideContract
  };
  if (guideKind === 'cornell') {
    contract.cornell = buildNativeCornellGuideConfig();
  }
  if (guideKind === 'weekly') {
    contract.weekly = buildNativeWeeklyGuideConfig();
  }
  return contract;
}

export function buildNativePageContract(document: DocumentRecord): NativePageContract {
  return buildNativePageContractFromMetadata({
    pageTemplateId: document.pageTemplateId,
    pageSizeId: document.pageSizeId,
    paperBackgroundId: document.paperBackgroundId
  });
}

function isBlankPagedDocument(document: DocumentRecord): boolean {
  return document.documentType === DocumentType.BLANK && document.documentMode === DocumentMode.PAGED;
}

function supportsBlankPagedRuntime(document: DocumentRecord): boolean {
  return isBlankPagedDocument(document) && document.schemaVersion >= 2;
}

function getOrderedDocumentPages(document: DocumentRecord): DocumentPageEntry[] {
  return [...document.pages].sort((left, right) => left.order - right.order);
}

function resolvePageMetadataForEntry(
  page: DocumentPageEntry | undefined,
  document: DocumentRecord
): DocumentPageMetadata {
  return {
    pageTemplateId: page?.pageTemplateId ?? document.pageTemplateId,
    pageSizeId: page?.pageSizeId ?? document.pageSizeId,
    paperBackgroundId: page?.paperBackgroundId ?? document.paperBackgroundId
  };
}

export function getDocumentActivePage(document: DocumentRecord): DocumentPageEntry | undefined {
  const pages: DocumentPageEntry[] = getOrderedDocumentPages(document);
  if (pages.length === 0) {
    return undefined;
  }
  const exactMatch: DocumentPageEntry | undefined = pages.find((page) => page.id === document.activePageId);
  if (exactMatch !== undefined) {
    return exactMatch;
  }
  return pages[0];
}

export function buildNativePageContractForEntry(
  document: DocumentRecord,
  page: DocumentPageEntry | undefined
): NativePageContract {
  const targetPage: DocumentPageEntry | undefined = page ?? getDocumentActivePage(document);
  const pageId: string = targetPage?.id ?? (document.activePageId.length > 0 ? document.activePageId : NATIVE_PRIMARY_PAGE_ID);
  return buildNativePageContractFromMetadata(
    resolvePageMetadataForEntry(targetPage, document),
    pageId
  );
}

function buildNativeDocumentPageConfig(
  document: DocumentRecord,
  page: DocumentPageEntry
): NativeDocumentPageConfig {
  const resolvedMetadata: ResolvedDocumentPageMetadata = resolveDocumentPageMetadata(
    resolvePageMetadataForEntry(page, document),
    DEFAULT_DOCUMENT_PAGE_METADATA
  );
  return {
    id: page.id,
    order: page.order,
    pageKind: page.pageKind,
    pageTemplateId: resolvedMetadata.pageTemplateId,
    pageSizeId: resolvedMetadata.pageSizeId,
    paperBackgroundId: resolvedMetadata.paperBackgroundId,
    sourceAttachmentId: page.sourceAttachmentId,
    sourcePageIndex: page.sourcePageIndex
  };
}

function buildNativePageContracts(document: DocumentRecord): Record<string, NativePageContract> {
  const pageContracts: Record<string, NativePageContract> = {};
  getOrderedDocumentPages(document).forEach((page) => {
    pageContracts[page.id] = buildNativePageContractForEntry(document, page);
  });
  return pageContracts;
}

export function buildNativeOpenDocumentConfig(
  document: DocumentRecord,
  preferredTool: ToolType
): NativeOpenDocumentConfig {
  const resolved = resolveDocumentPageMetadata({
    pageTemplateId: document.pageTemplateId,
    pageSizeId: document.pageSizeId,
    paperBackgroundId: document.paperBackgroundId
  }, DEFAULT_DOCUMENT_PAGE_METADATA);
  const activePageContract: NativePageContract = buildNativePageContractForEntry(document, undefined);
  const hasRealBlankPagedPages: boolean = supportsBlankPagedRuntime(document) && document.pages.length > 0;
  const config: NativeOpenDocumentConfig = {
    documentType: document.documentType,
    title: document.title,
    preferredTool,
    pageTemplateId: resolved.pageTemplateId,
    pageSizeId: resolved.pageSizeId,
    paperBackgroundId: resolved.paperBackgroundId,
    pageContract: activePageContract
  };
  if (hasRealBlankPagedPages) {
    config.activePageId = activePageContract.pageId;
    config.pages = getOrderedDocumentPages(document).map((page) => buildNativeDocumentPageConfig(document, page));
    config.pageContracts = buildNativePageContracts(document);
  }
  return config;
}

export function buildNativePreviewRequestSize(
  document: DocumentRecord,
  longEdge: number = 640
): NativePreviewRequestSize {
  const pageContract: NativePageContract = buildNativePageContractForEntry(document, undefined);
  const widthRatio: number = Math.max(1, pageContract.widthPt);
  const heightRatio: number = Math.max(1, pageContract.heightPt);
  if (widthRatio >= heightRatio) {
    return {
      width: longEdge,
      height: Math.max(1, Math.round(longEdge * (heightRatio / widthRatio)))
    };
  }
  return {
    width: Math.max(1, Math.round(longEdge * (widthRatio / heightRatio))),
    height: longEdge
  };
}
