import type { DocumentPreviewSnapshot } from './PreviewModels';

export enum DocumentType {
  BLANK = 'blank',
  PDF = 'pdf',
  HYBRID = 'hybrid'
}

export enum DocumentMode {
  PAGED = 'paged',
  INFINITE = 'infinite'
}

export enum RenderBackend {
  OPEN_GLES = 'opengles',
  SKIA = 'skia'
}

export enum ToolType {
  PEN = 'pen',
  PENCIL = 'pencil',
  ERASER = 'eraser',
  HIGHLIGHTER = 'highlighter',
  LASSO = 'lasso',
  HAND = 'hand',
  TEXT = 'text'
}

export type DocumentPageKind = 'blank' | 'pdf' | 'pdf-fragment';
export type DocumentAttachmentKind = 'pdf';
export type DocumentEmbeddedBlockKind = 'markdown' | 'latex' | 'mixed';

export interface DocumentEmbeddedBlockBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DocumentEmbeddedBlockRenderMeta {
  plainText?: string;
  html?: string;
  estimatedHeight?: number;
  measuredHeight?: number;
  version?: number;
}

export interface DocumentEmbeddedBlock {
  id: string;
  kind: DocumentEmbeddedBlockKind;
  sourceText: string;
  bounds: DocumentEmbeddedBlockBounds;
  renderMeta?: DocumentEmbeddedBlockRenderMeta;
  createdAt?: number;
  updatedAt?: number;
}

export interface FolderRecord {
  id: string;
  title: string;
  parentId: string | null;
  color: string;
  sortOrder: number;
}

export interface FolderNodeVM extends FolderRecord {
  selected: boolean;
  count: number;
}

export interface TagRecord {
  id: string;
  title: string;
  color: string;
}

export interface TagFilterVM extends TagRecord {
  selected: boolean;
  count: number;
}

export interface DocumentPageEntry {
  id: string;
  order: number;
  bookmarked?: boolean;
  pageTemplateId?: string;
  pageSizeId?: string;
  paperBackgroundId?: string;
  pageKind: DocumentPageKind;
  sourceAttachmentId?: string;
  sourcePageIndex?: number;
}

export interface DocumentAttachmentEntry {
  id: string;
  kind: DocumentAttachmentKind;
  displayName: string;
  mimeType: string;
  relativePath: string;
  byteSize: number;
  importedAt: number;
  pageCount: number;
}

export interface DocumentRecord {
  id: string;
  title: string;
  documentType: DocumentType;
  documentMode: DocumentMode;
  renderBackend: RenderBackend;
  previewSnapshot?: DocumentPreviewSnapshot;
  schemaVersion: number;
  activePageId: string;
  pageCount: number;
  pages: DocumentPageEntry[];
  pageTemplateId?: string;
  pageSizeId?: string;
  paperBackgroundId?: string;
  folderId: string | null;
  packagePath: string;
  manifestPath: string;
  previewPath: string;
  previewSummary: string;
  coverPage: number;
  coverVersion: number;
  isFavorite: boolean;
  isPinned: boolean;
  isTrashed: boolean;
  createdAt: number;
  updatedAt: number;
  openedAt: number;
  trashedAt: number;
  attachments: DocumentAttachmentEntry[];
  tags: TagRecord[];
}

export interface DocumentCardVM {
  document: DocumentRecord;
  folderTitle: string;
  tagTitles: string[];
  accentColor: string;
  previewLabel: string;
  previewSnapshot?: DocumentPreviewSnapshot;
}

export interface DocumentManifest {
  id: string;
  title: string;
  documentType: DocumentType;
  documentMode: DocumentMode;
  renderBackend: RenderBackend;
  schemaVersion: number;
  activePageId: string;
  pages: DocumentPageEntry[];
  pageTemplateId?: string;
  pageSizeId?: string;
  paperBackgroundId?: string;
  folderId: string | null;
  coverPage: number;
  coverVersion: number;
  isFavorite: boolean;
  isTrashed: boolean;
  createdAt: number;
  updatedAt: number;
  openedAt: number;
  trashedAt: number;
  attachments: DocumentAttachmentEntry[];
  tags: TagRecord[];
  previewSummary: string;
}

export interface DocumentCreatePayload {
  title: string;
  documentType: DocumentType;
  documentMode: DocumentMode;
  renderBackend: RenderBackend;
  pageTemplateId?: string;
  pageSizeId?: string;
  paperBackgroundId?: string;
  folderId: string | null;
  initialMarkdown?: string;
  previewSummary?: string;
}

export interface ImportedDocumentCreatePayload {
  title: string;
  documentType: DocumentType.PDF | DocumentType.HYBRID;
  renderBackend: RenderBackend;
  folderId: string | null;
  sourceUri: string;
  sourceDisplayName: string;
  sourceMimeType: string;
  sourceByteSize: number;
  pageTemplateId?: string;
  pageSizeId?: string;
  paperBackgroundId?: string;
}

export interface LibraryQuery {
  searchText?: string;
  folderId?: string | null;
  tagId?: string | null;
  favoritesOnly?: boolean;
  includeTrashed?: boolean;
}

export interface HomeSectionVM {
  key: string;
  title: string;
  description: string;
  documents: DocumentRecord[];
}

export interface TrashItemVM {
  id: string;
  title: string;
  deletedAt: number;
  summary: string;
}

export interface LibraryHomeData {
  recent: DocumentRecord[];
  favorites: DocumentRecord[];
  allDocuments: DocumentRecord[];
  trash: TrashItemVM[];
  folders: FolderRecord[];
  tags: TagRecord[];
  sections: HomeSectionVM[];
}

export const DEFAULT_FOLDERS: FolderRecord[] = [
  { id: 'inbox', title: '收件箱', parentId: null, color: '#4C7DFF', sortOrder: 0 },
  { id: 'study', title: '学习', parentId: null, color: '#1DAA6C', sortOrder: 1 },
  { id: 'work', title: '工作', parentId: null, color: '#F18B2B', sortOrder: 2 },
  { id: 'archive', title: '归档', parentId: null, color: '#7F8693', sortOrder: 3 }
];

export const DEFAULT_TAGS: TagRecord[] = [
  { id: 'tag-class', title: '课堂', color: '#4C7DFF' },
  { id: 'tag-pdf', title: 'PDF', color: '#FF6B4A' },
  { id: 'tag-draft', title: '草稿', color: '#A069FF' },
  { id: 'tag-math', title: '公式', color: '#00A3A3' }
];

export const PALETTE_COLORS: string[] = [
  '#1D2736',
  '#0B57D0',
  '#1A9E55',
  '#F18B2B',
  '#D64545',
  '#7A44FF',
  '#00A3A3',
  '#F4C542',
  '#FFFFFF'
];

export const DOCUMENT_TYPE_LABELS: Record<string, string> = {
  [DocumentType.BLANK]: '空白笔记',
  [DocumentType.PDF]: 'PDF 批注',
  [DocumentType.HYBRID]: '混合笔记'
};

export const DOCUMENT_MODE_LABELS: Record<string, string> = {
  [DocumentMode.PAGED]: '分页',
  [DocumentMode.INFINITE]: '无限画布'
};

export const RENDER_BACKEND_LABELS: Record<string, string> = {
  [RenderBackend.OPEN_GLES]: 'OpenGL ES',
  [RenderBackend.SKIA]: 'Skia'
};
