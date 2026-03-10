import { ResolvedDocumentPageMetadata } from './BlankPageTemplates';
import { NativeLayerId, NativePageContract, NativePreviewBounds, NativePreviewLayout } from './NativeNoteContracts';
import { DocumentMode, DocumentType, RenderBackend } from './NoteModels';

export const DOCUMENT_PREVIEW_SCHEMA_VERSION: number = 2;

export type DocumentPreviewSource = 'markdown' | 'native' | 'hybrid';
export type DocumentPreviewStatus = 'fallback' | 'ready' | 'error';

export interface PreviewRasterAsset {
  mimeType: string;
  base64?: string;
  uri?: string;
  width?: number;
  height?: number;
}

export interface DocumentPreviewSnapshot {
  schemaVersion: number;
  previewSchemaVersion: number;
  generatedAt: number;
  summary: string;
  nativeSummary?: string;
  previewLabel: string;
  type: DocumentType;
  source: DocumentPreviewSource;
  previewStatus: DocumentPreviewStatus;
  status: string;
  targetMode: string;
  coverPageId?: string;
  pageIds: string[];
  layers: NativeLayerId[];
  coordinateSpace?: string;
  targetBounds?: NativePreviewBounds;
  layout?: NativePreviewLayout;
  checkpointCount?: number;
  objectCount?: number;
  pageIndex: number;
  documentMode?: DocumentMode;
  renderBackend?: RenderBackend;
  nativeStatus?: string;
  renderWidth?: number;
  renderHeight?: number;
  raster?: PreviewRasterAsset;
  pageContract: NativePageContract;
  errorMessage?: string;
  extension?: Record<string, Object | string | number | boolean | null>;
}

export interface PreviewNormalizationContext {
  documentType: DocumentType;
  documentMode: DocumentMode;
  renderBackend: RenderBackend;
  pageMetadata: ResolvedDocumentPageMetadata;
  generatedAt: number;
  fallbackSummary: string;
  fallbackPreviewLabel: string;
  fallbackPageIndex?: number;
}
