import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { getDocumentPageMetadataFromSettings } from '../models/AppSettingsModels';
import {
  DEFAULT_DOCUMENT_PAGE_METADATA,
  DocumentPageMetadata,
  ResolvedDocumentPageMetadata,
  resolveDocumentPageMetadata
} from '../models/BlankPageTemplates';
import {
  NATIVE_PRIMARY_PAGE_ID,
  NativePreviewPayload
} from '../models/NativeNoteContracts';
import { DocumentPreviewSnapshot, PreviewNormalizationContext } from '../models/PreviewModels';
import {
  DEFAULT_FOLDERS,
  DEFAULT_TAGS,
  DocumentAttachmentEntry,
  DocumentCreatePayload,
  DocumentManifest,
  DocumentMode,
  DocumentPageEntry,
  DocumentPageKind,
  DocumentRecord,
  DocumentType,
  FolderRecord,
  ImportedDocumentCreatePayload,
  HomeSectionVM,
  LibraryHomeData,
  LibraryQuery,
  RenderBackend,
  TagRecord,
  TrashItemVM
} from '../models/NoteModels';
import { AppSettingsService } from './AppSettingsService';
import { NativeNoteEngine, NativePdfPageCountResult } from './NativeNoteEngine';
import { PreviewAdapterService } from './PreviewAdapterService';
import { IdGenerator } from '../utils/IdGenerator';
import { MarkdownUtils } from '../utils/MarkdownUtils';

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;

interface StrokeSnapshot {
  version: number;
  strokes: Object[];
  predictions: Object[];
}

interface TextBoxesSnapshot {
  version: number;
  markdownText: string;
  items: Object[];
}

interface DocumentPageStoragePaths {
  pageDirPath: string;
  strokesPath: string;
  textBoxesPath: string;
}

interface StoredManifestReadResult {
  status: string;
  manifest: DocumentManifest | null;
  detail: string;
}

interface DocumentRow {
  id: string;
  title: string;
  documentType: DocumentType;
  documentMode: DocumentMode;
  renderBackend: RenderBackend;
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
}

class DocumentLibraryBootstrapError extends Error {
  stage: string;
  op: string;
  path: string;
  documentsRoot: string;
  filesDir: string;
  code: number;
  detail: string;

  constructor(
    stage: string,
    op: string,
    path: string,
    documentsRoot: string,
    filesDir: string,
    code: number,
    detail: string
  ) {
    super(detail);
    this.stage = stage;
    this.op = op;
    this.path = path;
    this.documentsRoot = documentsRoot;
    this.filesDir = filesDir;
    this.code = code;
    this.detail = detail;
  }
}

interface DocumentLibraryCopy {
  defaultPdfSummary: string;
  defaultHybridSummary: string;
  defaultInfiniteSummary: string;
  defaultPagedSummary: string;
  modeLabel: string;
  backendLabel: string;
  filteredResultsTitle: string;
  filteredResultsDescription: string;
  favoriteResultsTitle: string;
  favoriteResultsDescription: string;
  recentTitle: string;
  recentDescription: string;
  favoritesTitle: string;
  favoritesDescription: string;
  allDocumentsTitle: string;
  allDocumentsDescription: string;
}

const SEEDED_DOCUMENTS: DocumentCreatePayload[] = [
  {
    title: '微积分笔记',
    documentType: DocumentType.BLANK,
    documentMode: DocumentMode.PAGED,
    renderBackend: RenderBackend.OPEN_GLES,
    folderId: 'study',
    initialMarkdown: '# 极限与连续\n\n- 重点：epsilon-delta 定义\n- 作业：第 2 章第 3 到 8 题\n\n$$\\lim_{x\\to0}\\frac{\\sin x}{x}=1$$'
  },
  {
    title: 'PDF 批注演示',
    documentType: DocumentType.PDF,
    documentMode: DocumentMode.PAGED,
    renderBackend: RenderBackend.SKIA,
    folderId: 'work',
    initialMarkdown: '# PDF 批注\n\n叠加源 PDF 页面、墨迹层和导出结果。\n\n- 保留页码引用\n- 保持导出标记同步'
  },
  {
    title: '无限画布草稿',
    documentType: DocumentType.HYBRID,
    documentMode: DocumentMode.INFINITE,
    renderBackend: RenderBackend.OPEN_GLES,
    folderId: 'inbox',
    initialMarkdown: '# 灵感池\n\n- 低时延笔迹预测\n- 自动图形修正\n- Markdown 文本框\n- 调色板与标签'
  }
];

const DOCUMENT_LIBRARY_COPY: DocumentLibraryCopy = {
  defaultPdfSummary: '新的 PDF 批注文档，等待源文件与墨迹图层。',
  defaultHybridSummary: '一份可混合空白纸张、文本框、PDF 片段与墨迹对象的混合笔记。',
  defaultInfiniteSummary: '新的无限画布，适合快速头脑风暴与自由草绘。',
  defaultPagedSummary: '新的分页笔记本，适合结构化记录与解题。',
  modeLabel: '模式',
  backendLabel: '后端',
  filteredResultsTitle: '筛选结果',
  filteredResultsDescription: '当前筛选条件命中的文档。',
  favoriteResultsTitle: '收藏结果',
  favoriteResultsDescription: '当前筛选条件下的收藏文档。',
  recentTitle: '最近打开',
  recentDescription: '最近访问过的文档。',
  favoritesTitle: '收藏',
  favoritesDescription: '置顶的学习笔记与常用工作文档。',
  allDocumentsTitle: '全部文档',
  allDocumentsDescription: '当前文件夹与标签范围下可见的全部文档。'
};

const DOCUMENT_PACKAGE_SCHEMA_VERSION_V2: number = 2;
const LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION: number = 1;
const BLANK_PAGE_KIND: DocumentPageKind = 'blank';
const PDF_PAGE_KIND: DocumentPageKind = 'pdf';

/**
 * DocumentLibraryService manages both the metadata database and per-document package folders.
 * The home page only reads cached metadata and never scans large raw document files.
 */
export class DocumentLibraryService {
  private static instance: DocumentLibraryService | undefined;
  private static initPromise: Promise<DocumentLibraryService> | undefined;

  private readonly context: common.UIAbilityContext;
  private readonly documentsRoot: string;
  private readonly storeConfig: relationalStore.StoreConfig = {
    name: 'note_library.db',
    securityLevel: relationalStore.SecurityLevel.S1
  };
  private appSettingsService: AppSettingsService | undefined;
  private readonly nativeNoteEngine: NativeNoteEngine = new NativeNoteEngine();
  private readonly previewAdapter: PreviewAdapterService = new PreviewAdapterService();
  private readonly previewSnapshotCache: Map<string, DocumentPreviewSnapshot> = new Map<string, DocumentPreviewSnapshot>();
  private readonly previewCacheKeyByPath: Map<string, string> = new Map<string, string>();
  private store: relationalStore.RdbStore | undefined;

  private constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.documentsRoot = `${this.context.filesDir}/documents`;
  }

  static async getInstance(context: common.UIAbilityContext): Promise<DocumentLibraryService> {
    if (DocumentLibraryService.instance) {
      return DocumentLibraryService.instance;
    }
    if (!DocumentLibraryService.initPromise) {
      DocumentLibraryService.initPromise = (async () => {
        const service: DocumentLibraryService = new DocumentLibraryService(context);
        await service.initialize();
        DocumentLibraryService.instance = service;
        return service;
      })();
    }
    return DocumentLibraryService.initPromise;
  }

  async listFolders(): Promise<FolderRecord[]> {
    await this.ensureStore();
    const resultSet = await this.store!.querySql(
      'SELECT id, title, parent_id, color, sort_order FROM folders ORDER BY sort_order ASC, title ASC'
    );
    const folders: FolderRecord[] = [];
    while (resultSet.goToNextRow()) {
      folders.push({
        id: resultSet.getString(0),
        title: resultSet.getString(1),
        parentId: resultSet.isColumnNull(2) ? null : resultSet.getString(2),
        color: resultSet.getString(3),
        sortOrder: resultSet.getLong(4)
      });
    }
    resultSet.close();
    return folders;
  }

  async listTags(): Promise<TagRecord[]> {
    await this.ensureStore();
    const resultSet = await this.store!.querySql(
      'SELECT id, title, color FROM tags ORDER BY title ASC'
    );
    const tags: TagRecord[] = [];
    while (resultSet.goToNextRow()) {
      tags.push({
        id: resultSet.getString(0),
        title: resultSet.getString(1),
        color: resultSet.getString(2)
      });
    }
    resultSet.close();
    return tags;
  }

  async listDocuments(query: LibraryQuery = {}): Promise<DocumentRecord[]> {
    await this.ensureStore();
    const folders: FolderRecord[] = await this.listFolders();
    const tags: TagRecord[] = await this.listTags();
    const folderMap: Map<string, FolderRecord> = new Map<string, FolderRecord>();
    const tagMap: Map<string, TagRecord> = new Map<string, TagRecord>();

    folders.forEach((folder) => folderMap.set(folder.id, folder));
    tags.forEach((tag) => tagMap.set(tag.id, tag));

    let sql: string = `
      SELECT d.id, d.title, d.document_type, d.document_mode, d.render_backend, d.folder_id,
             d.package_path, d.manifest_path, d.preview_path, d.preview_summary,
             d.cover_page, d.cover_version, IFNULL(f.is_favorite, 0), IFNULL(f.is_pinned, 0),
             d.is_trashed, d.created_at, d.updated_at, d.opened_at, d.trashed_at
      FROM documents d
      LEFT JOIN favorites_or_flags f ON f.doc_id = d.id
      WHERE d.is_trashed = ?
    `;
    const args: relationalStore.ValueType[] = [query.includeTrashed ? 1 : 0];

    if (query.folderId && query.folderId !== 'all') {
      sql += ' AND d.folder_id = ?';
      args.push(query.folderId);
    }
    if (query.favoritesOnly) {
      sql += ' AND IFNULL(f.is_favorite, 0) = 1';
    }
    sql += ' ORDER BY d.updated_at DESC';

    const resultSet = await this.store!.querySql(sql, args);
    const rows: DocumentRow[] = [];
    while (resultSet.goToNextRow()) {
      rows.push({
        id: resultSet.getString(0),
        title: resultSet.getString(1),
        documentType: resultSet.getString(2) as DocumentType,
        documentMode: resultSet.getString(3) as DocumentMode,
        renderBackend: resultSet.getString(4) as RenderBackend,
        folderId: resultSet.isColumnNull(5) ? null : resultSet.getString(5),
        packagePath: resultSet.getString(6),
        manifestPath: resultSet.getString(7),
        previewPath: resultSet.getString(8),
        previewSummary: resultSet.getString(9),
        coverPage: resultSet.getLong(10),
        coverVersion: resultSet.getLong(11),
        isFavorite: resultSet.getLong(12) === 1,
        isPinned: resultSet.getLong(13) === 1,
        isTrashed: resultSet.getLong(14) === 1,
        createdAt: resultSet.getLong(15),
        updatedAt: resultSet.getLong(16),
        openedAt: resultSet.getLong(17),
        trashedAt: resultSet.getLong(18)
      });
    }
    resultSet.close();

    const tagLookup: Map<string, TagRecord[]> = await this.loadDocumentTags(
      rows.map((row) => row.id),
      tagMap
    );
    let documents: DocumentRecord[] = rows.map((row) => this.toDocumentRecord(row, tagLookup.get(row.id) ?? []));

    if (query.tagId && query.tagId !== 'all') {
      documents = documents.filter((doc) => doc.tags.some((tag) => tag.id === query.tagId));
    }

    const keyword: string = (query.searchText ?? '').trim().toLowerCase();
    if (keyword.length > 0) {
      documents = documents.filter((doc) => {
        const folderTitle: string = doc.folderId ? (folderMap.get(doc.folderId)?.title ?? '') : '';
        const tagTitleText: string = doc.tags.map((tag) => tag.title).join(' ');
        const haystack: string = `${doc.title} ${doc.previewSummary} ${folderTitle} ${tagTitleText}`.toLowerCase();
        return haystack.includes(keyword);
      });
    }

    if (documents.length === 0) {
      return documents;
    }

    const enrichedDocuments: DocumentRecord[] = await Promise.all(
      documents.map((doc: DocumentRecord) => this.enrichDocumentRecord(doc))
    );
    return enrichedDocuments;
  }

  async getHomeSections(query: LibraryQuery = {}): Promise<LibraryHomeData> {
    const folders: FolderRecord[] = await this.listFolders();
    const tags: TagRecord[] = await this.listTags();
    const allDocuments: DocumentRecord[] = await this.listDocuments(query);
    const favorites: DocumentRecord[] = allDocuments.filter((doc) => doc.isFavorite);
    const recent: DocumentRecord[] = [...allDocuments]
      .sort((left, right) => right.openedAt - left.openedAt)
      .slice(0, 6);
    const trash: TrashItemVM[] = (await this.listDocuments({
      includeTrashed: true,
      searchText: query.searchText
    })).map((doc: DocumentRecord): TrashItemVM => {
      const item: TrashItemVM = {
        id: doc.id,
        title: doc.title,
        deletedAt: doc.trashedAt,
        summary: doc.previewSummary
      };
      return item;
    });

    const hasFilter: boolean = Boolean(
      (query.searchText ?? '').trim().length > 0 ||
      (query.folderId && query.folderId !== 'all') ||
      (query.tagId && query.tagId !== 'all') ||
      query.favoritesOnly
    );

    const sections: HomeSectionVM[] = hasFilter
      ? [{
        key: 'filtered',
        title: query.favoritesOnly ? DOCUMENT_LIBRARY_COPY.favoriteResultsTitle : DOCUMENT_LIBRARY_COPY.filteredResultsTitle,
        description: query.favoritesOnly
          ? DOCUMENT_LIBRARY_COPY.favoriteResultsDescription
          : DOCUMENT_LIBRARY_COPY.filteredResultsDescription,
        documents: allDocuments
      }]
      : [
        {
          key: 'recent',
          title: DOCUMENT_LIBRARY_COPY.recentTitle,
          description: DOCUMENT_LIBRARY_COPY.recentDescription,
          documents: recent
        },
        {
          key: 'favorites',
          title: DOCUMENT_LIBRARY_COPY.favoritesTitle,
          description: DOCUMENT_LIBRARY_COPY.favoritesDescription,
          documents: favorites
        },
        {
          key: 'all',
          title: DOCUMENT_LIBRARY_COPY.allDocumentsTitle,
          description: DOCUMENT_LIBRARY_COPY.allDocumentsDescription,
          documents: allDocuments
        }
      ];

    return {
      recent,
      favorites,
      allDocuments,
      trash,
      folders,
      tags,
      sections
    };
  }

  async createDocument(payload: DocumentCreatePayload): Promise<DocumentRecord> {
    try {
      await this.ensureStore();
      const now: number = Date.now();
      const documentId: string = IdGenerator.document();
      const packagePath: string = `${this.documentsRoot}/${documentId}`;
      const manifestPath: string = `${packagePath}/manifest.json`;
      const previewPath: string = `${packagePath}/preview.json`;
      const createPayloadCompat: DocumentPageMetadata = {
        pageTemplateId: payload.pageTemplateId,
        pageSizeId: payload.pageSizeId,
        paperBackgroundId: payload.paperBackgroundId
      };
      const compatFields: ResolvedDocumentPageMetadata = await this.resolveDocumentCompatFields(createPayloadCompat);

      this.ensureDir(this.documentsRoot);
      this.ensureDir(packagePath);
      this.ensureDir(`${packagePath}/attachments`);

      const previewSummary: string = payload.previewSummary ??
        MarkdownUtils.preview(payload.initialMarkdown ?? this.defaultSummary(payload));
      const isBlankPagedDocument: boolean = this.isBlankPagedPayload(payload);
      const initialPageEntry: DocumentPageEntry | undefined = isBlankPagedDocument
        ? await this.createDocumentPageEntry({
          id: NATIVE_PRIMARY_PAGE_ID,
          order: 0,
          pageKind: BLANK_PAGE_KIND,
          pageTemplateId: compatFields.pageTemplateId,
          pageSizeId: compatFields.pageSizeId,
          paperBackgroundId: compatFields.paperBackgroundId
        })
        : undefined;

      const manifest: DocumentManifest = {
        id: documentId,
        title: payload.title,
        documentType: payload.documentType,
        documentMode: payload.documentMode,
        renderBackend: payload.renderBackend,
        schemaVersion: isBlankPagedDocument ? DOCUMENT_PACKAGE_SCHEMA_VERSION_V2 : LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION,
        activePageId: initialPageEntry?.id ?? '',
        pages: initialPageEntry ? [initialPageEntry] : [],
        pageTemplateId: initialPageEntry?.pageTemplateId ?? compatFields.pageTemplateId,
        pageSizeId: initialPageEntry?.pageSizeId ?? compatFields.pageSizeId,
        paperBackgroundId: initialPageEntry?.paperBackgroundId ?? compatFields.paperBackgroundId,
        folderId: payload.folderId,
        coverPage: 0,
        coverVersion: 1,
        isFavorite: false,
        isTrashed: false,
        createdAt: now,
        updatedAt: now,
        openedAt: now,
        trashedAt: 0,
        attachments: [],
        tags: [],
        previewSummary
      };

      this.writeJsonFile(manifestPath, manifest);
      if (initialPageEntry) {
        this.writeJsonFile(
          this.getPageStoragePaths(packagePath, initialPageEntry.id).strokesPath,
          this.createEmptyStrokeSnapshot()
        );
        this.writeJsonFile(
          this.getPageStoragePaths(packagePath, initialPageEntry.id).textBoxesPath,
          this.createEmptyTextBoxesSnapshot(payload.initialMarkdown ?? this.defaultMarkdown(payload))
        );
      } else {
        this.writeJsonFile(`${packagePath}/strokes.json`, this.createEmptyStrokeSnapshot());
        this.writeJsonFile(
          `${packagePath}/text-boxes.json`,
          this.createEmptyTextBoxesSnapshot(payload.initialMarkdown ?? this.defaultMarkdown(payload))
        );
      }
      const previewSnapshot: DocumentPreviewSnapshot = this.previewAdapter.normalizeRequestPreviewRenderPayload(
        undefined,
        this.buildPreviewNormalizationContext(
          payload.documentType,
          payload.documentMode,
          payload.renderBackend,
          compatFields,
          previewSummary,
          `${payload.documentMode}/${payload.renderBackend}`,
          now
        )
      );
      this.writeJsonFile(previewPath, previewSnapshot);

      await this.store!.executeSql(
        `INSERT INTO documents (
           id, title, document_type, document_mode, render_backend, folder_id,
           package_path, manifest_path, preview_path, preview_summary,
           cover_page, cover_version, is_trashed, created_at, updated_at, opened_at, trashed_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          documentId,
          payload.title,
          payload.documentType,
          payload.documentMode,
          payload.renderBackend,
          payload.folderId,
          packagePath,
          manifestPath,
          previewPath,
          previewSummary,
          0,
          1,
          0,
          now,
          now,
          now,
          0
        ]
      );
      await this.store!.executeSql(
        'INSERT INTO favorites_or_flags (doc_id, is_favorite, is_pinned) VALUES (?, ?, ?)',
        [documentId, 0, 0]
      );
      await this.store!.executeSql(
        'INSERT INTO recent_visits (doc_id, visited_at) VALUES (?, ?)',
        [documentId, now]
      );
      return this.requireDocument(documentId);
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.createDocument', 'bootstrap', this.documentsRoot, error as Object);
    }
  }

  async createImportedDocument(payload: ImportedDocumentCreatePayload): Promise<DocumentRecord> {
    await this.ensureStore();
    const now: number = Date.now();
    const documentId: string = IdGenerator.document();
    const attachmentId: string = IdGenerator.document('attachment');
    const packagePath: string = `${this.documentsRoot}/${documentId}`;
    const manifestPath: string = `${packagePath}/manifest.json`;
    const previewPath: string = `${packagePath}/preview.json`;
    const attachmentRelativePath: string = this.buildImportedAttachmentRelativePath(attachmentId);
    const attachmentPath: string = `${packagePath}/${attachmentRelativePath}`;
    let packageCreated: boolean = false;
    let insertedDocumentRow: boolean = false;
    let insertedFlagsRow: boolean = false;
    let insertedRecentRow: boolean = false;

    try {
      const compatFields: ResolvedDocumentPageMetadata = await this.resolveDocumentCompatFields({
        pageTemplateId: payload.pageTemplateId,
        pageSizeId: payload.pageSizeId,
        paperBackgroundId: payload.paperBackgroundId
      });
      this.ensureDir(this.documentsRoot);
      this.ensureDir(packagePath);
      packageCreated = true;
      this.ensureDir(`${packagePath}/attachments`);
      this.copyBinaryFile(payload.sourceUri, attachmentPath);
      const pageCountResult: NativePdfPageCountResult | null = this.nativeNoteEngine.readPdfPageCount(attachmentPath);
      const normalizedPageCount: number = this.requireImportedPdfPageCount(pageCountResult, attachmentPath);
      const attachmentEntry: DocumentAttachmentEntry = this.buildImportedAttachmentEntry(
        attachmentId,
        payload.sourceDisplayName,
        payload.sourceMimeType,
        attachmentRelativePath,
        payload.sourceByteSize,
        now,
        normalizedPageCount
      );
      const pages: DocumentPageEntry[] = await this.buildImportedPdfPages(
        normalizedPageCount,
        compatFields,
        attachmentEntry.id
      );
      const previewSummary: string = this.defaultSummary({
        title: payload.title,
        documentType: payload.documentType,
        documentMode: DocumentMode.PAGED,
        renderBackend: payload.renderBackend,
        folderId: payload.folderId
      });

      this.initializePagedPageStorage(packagePath, pages);

      const manifest: DocumentManifest = {
        id: documentId,
        title: payload.title,
        documentType: payload.documentType,
        documentMode: DocumentMode.PAGED,
        renderBackend: payload.renderBackend,
        schemaVersion: DOCUMENT_PACKAGE_SCHEMA_VERSION_V2,
        activePageId: pages[0]?.id ?? '',
        pages,
        pageTemplateId: compatFields.pageTemplateId,
        pageSizeId: compatFields.pageSizeId,
        paperBackgroundId: compatFields.paperBackgroundId,
        folderId: payload.folderId,
        coverPage: pages[0]?.order ?? 0,
        coverVersion: 1,
        isFavorite: false,
        isTrashed: false,
        createdAt: now,
        updatedAt: now,
        openedAt: now,
        trashedAt: 0,
        attachments: [attachmentEntry],
        tags: [],
        previewSummary
      };

      this.writeJsonFile(manifestPath, manifest);
      const previewSnapshot: DocumentPreviewSnapshot = this.previewAdapter.normalizeRequestPreviewRenderPayload(
        undefined,
        this.buildPreviewNormalizationContext(
          payload.documentType,
          DocumentMode.PAGED,
          payload.renderBackend,
          compatFields,
          previewSummary,
          `${DocumentMode.PAGED}/${payload.renderBackend}`,
          now,
          0
        )
      );
      this.writeJsonFile(previewPath, previewSnapshot);

      await this.store!.executeSql(
        `INSERT INTO documents (
           id, title, document_type, document_mode, render_backend, folder_id,
           package_path, manifest_path, preview_path, preview_summary,
           cover_page, cover_version, is_trashed, created_at, updated_at, opened_at, trashed_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          documentId,
          payload.title,
          payload.documentType,
          DocumentMode.PAGED,
          payload.renderBackend,
          payload.folderId,
          packagePath,
          manifestPath,
          previewPath,
          previewSummary,
          manifest.coverPage,
          manifest.coverVersion,
          0,
          now,
          now,
          now,
          0
        ]
      );
      insertedDocumentRow = true;
      await this.store!.executeSql(
        'INSERT INTO favorites_or_flags (doc_id, is_favorite, is_pinned) VALUES (?, ?, ?)',
        [documentId, 0, 0]
      );
      insertedFlagsRow = true;
      await this.store!.executeSql(
        'INSERT INTO recent_visits (doc_id, visited_at) VALUES (?, ?)',
        [documentId, now]
      );
      insertedRecentRow = true;
      return this.requireDocument(documentId);
    } catch (error) {
      await this.cleanupFailedImportedDocument(
        documentId,
        packagePath,
        packageCreated,
        insertedDocumentRow,
        insertedFlagsRow,
        insertedRecentRow
      );
      throw this.wrapFileError('DocumentLibraryService.createImportedDocument', 'import', packagePath, error as Object);
    }
  }

  private buildImportedAttachmentRelativePath(attachmentId: string): string {
    return `attachments/${attachmentId}.pdf`;
  }

  private requireImportedPdfPageCount(result: NativePdfPageCountResult | null, pdfPath: string): number {
    if (result === null) {
      throw new Error(`readPdfPageCount returned invalid payload for ${pdfPath}`);
    }
    if (result.status !== 'ok') {
      const detail: string = result.detail && result.detail.length > 0 ? `: ${result.detail}` : '';
      throw new Error(`readPdfPageCount failed with status ${result.status}${detail}`);
    }
    const pageCount: number = Math.trunc(result.pageCount ?? 0);
    if (!Number.isFinite(pageCount) || pageCount <= 0) {
      throw new Error(`readPdfPageCount returned invalid pageCount ${pageCount} for ${pdfPath}`);
    }
    return pageCount;
  }

  private buildImportedAttachmentEntry(
    attachmentId: string,
    sourceDisplayName: string,
    sourceMimeType: string,
    relativePath: string,
    sourceByteSize: number,
    importedAt: number,
    pageCount: number
  ): DocumentAttachmentEntry {
    return {
      id: attachmentId,
      kind: 'pdf',
      displayName: sourceDisplayName,
      mimeType: sourceMimeType.length > 0 ? sourceMimeType : 'application/pdf',
      relativePath,
      byteSize: Math.max(0, Math.trunc(sourceByteSize)),
      importedAt,
      pageCount: Math.max(1, Math.trunc(pageCount))
    };
  }

  private async buildImportedPdfPages(
    pageCount: number,
    compatFields: ResolvedDocumentPageMetadata,
    attachmentId: string
  ): Promise<DocumentPageEntry[]> {
    const pages: DocumentPageEntry[] = [];
    for (let pageIndex: number = 0; pageIndex < pageCount; pageIndex += 1) {
      pages.push(await this.createDocumentPageEntry({
        id: `page-${pageIndex}`,
        order: pageIndex,
        pageKind: PDF_PAGE_KIND,
        pageTemplateId: compatFields.pageTemplateId,
        pageSizeId: compatFields.pageSizeId,
        paperBackgroundId: compatFields.paperBackgroundId,
        sourceAttachmentId: attachmentId,
        sourcePageIndex: pageIndex
      }));
    }
    return pages;
  }

  private initializePagedPageStorage(packagePath: string, pages: DocumentPageEntry[]): void {
    this.ensureDir(`${packagePath}/pages`);
    pages.forEach((page: DocumentPageEntry) => {
      const storagePaths: DocumentPageStoragePaths = this.getPageStoragePaths(packagePath, page.id);
      this.writeJsonFile(storagePaths.strokesPath, this.createEmptyStrokeSnapshot());
      this.writeJsonFile(storagePaths.textBoxesPath, this.createEmptyTextBoxesSnapshot(''));
    });
  }

  private copyBinaryFile(sourceReference: string, targetPath: string): void {
    try {
      const parentPath: string = this.getParentPath(targetPath);
      if (parentPath.length > 0) {
        this.ensureDir(parentPath);
      }
      const sourceCandidates: string[] = this.buildBinaryCopySourceCandidates(sourceReference);
      const targetCandidates: string[] = this.buildBinaryCopyTargetCandidates(targetPath);
      let lastError: Object | null = null;
      for (let sourceIndex = 0; sourceIndex < sourceCandidates.length; sourceIndex += 1) {
        const sourceCandidate: string = sourceCandidates[sourceIndex];
        for (let targetIndex = 0; targetIndex < targetCandidates.length; targetIndex += 1) {
          const targetCandidate: string = targetCandidates[targetIndex];
          try {
            fileIo.copyFileSync(sourceCandidate, targetCandidate);
            return;
          } catch (error) {
            lastError = error as Object;
            this.removeFileIfExists(targetPath);
          }
        }
      }
      for (let sourceIndex = 0; sourceIndex < sourceCandidates.length; sourceIndex += 1) {
        const sourceCandidate: string = sourceCandidates[sourceIndex];
        for (let targetIndex = 0; targetIndex < targetCandidates.length; targetIndex += 1) {
          const targetCandidate: string = targetCandidates[targetIndex];
          try {
            this.copyBinaryFileByStream(sourceCandidate, targetCandidate);
            return;
          } catch (error) {
            lastError = error as Object;
            this.removeFileIfExists(targetPath);
          }
        }
      }
      throw this.wrapFileError(
        'DocumentLibraryService.copyBinaryFile',
        'copyFileSync',
        targetPath,
        lastError ?? new Error(`copyFileSync failed for ${sourceReference}`)
      );
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.copyBinaryFile', 'copyFileSync', targetPath, error as Object);
    }
  }

  private buildBinaryCopySourceCandidates(sourceReference: string): string[] {
    const candidates: string[] = [sourceReference];
    const resolvedSourcePath: string = this.tryResolveUriToPath(sourceReference);
    if (resolvedSourcePath.length > 0 && !candidates.includes(resolvedSourcePath)) {
      candidates.push(resolvedSourcePath);
    }
    return candidates;
  }

  private buildBinaryCopyTargetCandidates(targetPath: string): string[] {
    const candidates: string[] = [targetPath];
    try {
      const targetUri: string = fileUri.getUriFromPath(targetPath);
      if (targetUri.length > 0 && !candidates.includes(targetUri)) {
        candidates.push(targetUri);
      }
    } catch (_) {
      // Fall back to the plain sandbox path when URI conversion is unavailable.
    }
    return candidates;
  }

  private tryResolveUriToPath(uriOrPath: string): string {
    try {
      const resolvedPath: string = new fileUri.FileUri(uriOrPath).path;
      return resolvedPath.trim();
    } catch (_) {
      return '';
    }
  }

  private copyBinaryFileByStream(sourceReference: string, targetReference: string): void {
    let sourceStream: fileIo.Stream | undefined;
    let targetStream: fileIo.Stream | undefined;
    try {
      sourceStream = fileIo.createStreamSync(sourceReference, 'r');
      targetStream = fileIo.createStreamSync(targetReference, 'w');
      const chunkBuffer: ArrayBuffer = new ArrayBuffer(64 * 1024);
      while (true) {
        const bytesRead: number = sourceStream.readSync(chunkBuffer);
        if (bytesRead <= 0) {
          break;
        }
        targetStream.writeSync(chunkBuffer, {
          offset: 0,
          length: bytesRead
        });
      }
      targetStream.flushSync();
    } finally {
      try {
        targetStream?.closeSync();
      } catch (_) {
        // Ignore close errors during cleanup.
      }
      try {
        sourceStream?.closeSync();
      } catch (_) {
        // Ignore close errors during cleanup.
      }
    }
  }

  private async cleanupFailedImportedDocument(
    documentId: string,
    packagePath: string,
    packageCreated: boolean,
    insertedDocumentRow: boolean,
    insertedFlagsRow: boolean,
    insertedRecentRow: boolean
  ): Promise<void> {
    if (insertedRecentRow) {
      await this.deleteImportedDocumentRow('recent_visits', documentId, 'doc_id');
    }
    if (insertedFlagsRow) {
      await this.deleteImportedDocumentRow('favorites_or_flags', documentId, 'doc_id');
    }
    if (insertedDocumentRow) {
      await this.deleteImportedDocumentRow('documents', documentId, 'id');
    }
    if (packageCreated) {
      try {
        this.removeRecursively(packagePath);
      } catch (_) {
        return;
      }
    }
  }

  private async deleteImportedDocumentRow(tableName: string, documentId: string, keyColumn: string): Promise<void> {
    if (!this.store) {
      return;
    }
    try {
      await this.store.executeSql(`DELETE FROM ${tableName} WHERE ${keyColumn} = ?`, [documentId]);
    } catch (_) {
      return;
    }
  }

  async createFolder(title: string, color: string = '#4C7DFF'): Promise<FolderRecord> {
    await this.ensureStore();
    const folder: FolderRecord = {
      id: IdGenerator.folder(),
      title,
      parentId: null,
      color,
      sortOrder: Date.now()
    };
    await this.store!.executeSql(
      'INSERT INTO folders (id, title, parent_id, color, sort_order) VALUES (?, ?, ?, ?, ?)',
      [folder.id, folder.title, folder.parentId, folder.color, folder.sortOrder]
    );
    return folder;
  }

  async createTag(title: string, color: string = '#4C7DFF'): Promise<TagRecord> {
    await this.ensureStore();
    const tag: TagRecord = {
      id: IdGenerator.tag(),
      title,
      color
    };
    await this.store!.executeSql(
      'INSERT INTO tags (id, title, color) VALUES (?, ?, ?)',
      [tag.id, tag.title, tag.color]
    );
    return tag;
  }

  async renameDocument(documentId: string, title: string): Promise<DocumentRecord> {
    await this.ensureStore();
    const now: number = Date.now();
    await this.store!.executeSql(
      'UPDATE documents SET title = ?, updated_at = ? WHERE id = ?',
      [title, now, documentId]
    );
    await this.updateManifest(documentId, (manifest) => {
      manifest.title = title;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async moveDocument(documentId: string, folderId: string | null): Promise<DocumentRecord> {
    await this.ensureStore();
    const now: number = Date.now();
    await this.store!.executeSql(
      'UPDATE documents SET folder_id = ?, updated_at = ? WHERE id = ?',
      [folderId, now, documentId]
    );
    await this.updateManifest(documentId, (manifest) => {
      manifest.folderId = folderId;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async deleteDocument(documentId: string, mode: 'trash' | 'purge'): Promise<void> {
    await this.ensureStore();
    const doc: DocumentRecord = await this.requireDocument(documentId);
    if (mode === 'trash') {
      const now: number = Date.now();
      await this.store!.executeSql(
        'UPDATE documents SET is_trashed = 1, trashed_at = ?, updated_at = ? WHERE id = ?',
        [now, now, documentId]
      );
      await this.updateManifest(documentId, (manifest) => {
        manifest.isTrashed = true;
        manifest.trashedAt = now;
        manifest.updatedAt = now;
      });
      return;
    }

    this.removeRecursively(doc.packagePath);
    await this.store!.executeSql('DELETE FROM document_tags WHERE doc_id = ?', [documentId]);
    await this.store!.executeSql('DELETE FROM favorites_or_flags WHERE doc_id = ?', [documentId]);
    await this.store!.executeSql('DELETE FROM recent_visits WHERE doc_id = ?', [documentId]);
    await this.store!.executeSql('DELETE FROM documents WHERE id = ?', [documentId]);
  }

  async restoreDocument(documentId: string): Promise<DocumentRecord> {
    await this.ensureStore();
    const now: number = Date.now();
    await this.store!.executeSql(
      'UPDATE documents SET is_trashed = 0, trashed_at = 0, updated_at = ? WHERE id = ?',
      [now, documentId]
    );
    await this.updateManifest(documentId, (manifest) => {
      manifest.isTrashed = false;
      manifest.trashedAt = 0;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async toggleFavorite(documentId: string): Promise<DocumentRecord> {
    await this.ensureStore();
    const resultSet = await this.store!.querySql(
      'SELECT is_favorite FROM favorites_or_flags WHERE doc_id = ?',
      [documentId]
    );
    let currentFavorite: boolean = false;
    if (resultSet.goToNextRow()) {
      currentFavorite = resultSet.getLong(0) === 1;
    }
    resultSet.close();

    const nextValue: number = currentFavorite ? 0 : 1;
    await this.store!.executeSql(
      'UPDATE favorites_or_flags SET is_favorite = ? WHERE doc_id = ?',
      [nextValue, documentId]
    );
    await this.updateManifest(documentId, (manifest) => {
      manifest.isFavorite = nextValue === 1;
      manifest.updatedAt = Date.now();
    });
    return this.requireDocument(documentId);
  }

  async assignTags(documentId: string, tagIds: string[]): Promise<DocumentRecord> {
    await this.ensureStore();
    const allTags: TagRecord[] = await this.listTags();
    const selectedTags: TagRecord[] = allTags.filter((tag) => tagIds.includes(tag.id));

    await this.store!.executeSql('DELETE FROM document_tags WHERE doc_id = ?', [documentId]);
    for (const tagId of tagIds) {
      await this.store!.executeSql(
        'INSERT INTO document_tags (doc_id, tag_id) VALUES (?, ?)',
        [documentId, tagId]
      );
    }
    await this.updateManifest(documentId, (manifest) => {
      manifest.tags = selectedTags;
      manifest.updatedAt = Date.now();
    });
    return this.requireDocument(documentId);
  }

  async openDocumentById(documentId: string): Promise<DocumentRecord> {
    await this.ensureStore();
    const now: number = Date.now();
    await this.store!.executeSql(
      'UPDATE documents SET opened_at = ?, updated_at = ? WHERE id = ?',
      [now, now, documentId]
    );
    await this.store!.executeSql(
      'INSERT OR REPLACE INTO recent_visits (doc_id, visited_at) VALUES (?, ?)',
      [documentId, now]
    );
    await this.updateManifest(documentId, (manifest) => {
      manifest.openedAt = now;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async refreshPreview(documentId: string): Promise<DocumentRecord> {
    await this.ensureStore();
    const doc: DocumentRecord = await this.requireDocument(documentId);
    const markdownText: string = this.readDocumentMarkdown(doc, doc.activePageId);
    const summary: string = MarkdownUtils.preview(markdownText || doc.previewSummary);
    const now: number = Date.now();
    const previewSnapshot: DocumentPreviewSnapshot = this.buildPreviewSnapshot(doc, summary, now);
    const coverPage: number = this.resolveCoverPage(doc.pages, doc.activePageId, doc.coverPage);

    await this.store!.executeSql(
      'UPDATE documents SET preview_summary = ?, cover_page = ?, updated_at = ? WHERE id = ?',
      [previewSnapshot.summary, coverPage, now, documentId]
    );
    this.writeJsonFile(doc.previewPath, previewSnapshot);
    if (this.supportsPagedDocumentStorage(doc)) {
      await this.updateSchemaV2PagedManifest(documentId, (manifest) => {
        manifest.previewSummary = previewSnapshot.summary;
        manifest.coverPage = coverPage;
        manifest.updatedAt = now;
      });
    } else {
      await this.updateManifest(documentId, (manifest) => {
        manifest.previewSummary = previewSnapshot.summary;
        manifest.coverPage = coverPage;
        manifest.updatedAt = now;
      });
    }
    this.invalidatePreviewSnapshotCache(doc.previewPath);
    return this.requireDocument(documentId);
  }

  async mergeNativePreviewSnapshot(
    documentId: string,
    nativePreview: NativePreviewPayload | null
  ): Promise<DocumentRecord> {
    await this.ensureStore();
    const doc: DocumentRecord = await this.requireDocument(documentId);
    this.writeJsonFile(doc.previewPath, this.buildPreviewSnapshot(doc, doc.previewSummary, Date.now(), nativePreview));
    this.invalidatePreviewSnapshotCache(doc.previewPath);
    return this.requireDocument(documentId);
  }

  async getDocumentMarkdown(documentId: string, pageId?: string): Promise<string> {
    const doc: DocumentRecord = await this.requireDocument(documentId);
    return this.readDocumentMarkdown(doc, pageId);
  }

  async prepareBlankPagedDocumentForSave(documentId: string): Promise<DocumentRecord> {
    return this.ensureBlankPagedDocumentV2(documentId);
  }

  async confirmBlankPagedSaveCompleted(documentId: string, expectedActivePageId: string): Promise<DocumentRecord> {
    const doc: DocumentRecord = await this.requireDocument(documentId);
    const manifestReadResult: StoredManifestReadResult = await this.readStoredManifestResultWithRetry(doc.manifestPath);
    if (manifestReadResult.status !== 'ok' || manifestReadResult.manifest === null) {
      throw new Error(
        `Blank paged save verification failed: ${manifestReadResult.status} for ${documentId} at ${doc.manifestPath}` +
          `${manifestReadResult.detail.length > 0 ? ` | ${manifestReadResult.detail}` : ''}`
      );
    }
    const manifest: DocumentManifest = manifestReadResult.manifest;
    const storedSchemaVersion: number = manifest.schemaVersion ?? LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION;
    if (storedSchemaVersion !== DOCUMENT_PACKAGE_SCHEMA_VERSION_V2) {
      throw new Error(`Blank paged save verification failed: stored schemaVersion=${storedSchemaVersion} for ${documentId}`);
    }
    const normalizedManifest: DocumentManifest = await this.applyManifestCompatDefaults(manifest);
    if (normalizedManifest.schemaVersion !== DOCUMENT_PACKAGE_SCHEMA_VERSION_V2) {
      throw new Error(
        `Blank paged save verification failed: schemaVersion=${normalizedManifest.schemaVersion} for ${documentId}`
      );
    }

    if (expectedActivePageId.length > 0 && normalizedManifest.pages.length > 0) {
      const resolvedManifestActivePageId: string = this.resolveActivePageId(
        normalizedManifest.pages,
        normalizedManifest.activePageId
      );
      if (resolvedManifestActivePageId !== expectedActivePageId) {
        throw new Error(
          `Blank paged save verification failed: activePageId=${resolvedManifestActivePageId}, expected=${expectedActivePageId}`
        );
      }
    }

    const reloadedDocument: DocumentRecord = await this.requireDocument(documentId);
    if (reloadedDocument.schemaVersion !== DOCUMENT_PACKAGE_SCHEMA_VERSION_V2) {
      throw new Error(
        `Blank paged save verification failed: reloaded schemaVersion=${reloadedDocument.schemaVersion} for ${documentId}`
      );
    }
    if (expectedActivePageId.length > 0 && reloadedDocument.pages.length > 0) {
      const resolvedDocumentActivePageId: string = this.resolveActivePageId(
        reloadedDocument.pages,
        reloadedDocument.activePageId
      );
      if (resolvedDocumentActivePageId !== expectedActivePageId) {
        throw new Error(
          `Blank paged save verification failed: reloaded activePageId=${resolvedDocumentActivePageId}, expected=${expectedActivePageId}`
        );
      }
    }
    return reloadedDocument;
  }

  async saveDocumentMarkdown(
    documentId: string,
    markdownText: string,
    pageId?: string,
    refreshPreview: boolean = true
  ): Promise<DocumentRecord> {
    let doc: DocumentRecord = await this.requireDocument(documentId);
    if (this.isBlankPagedDocument(doc.documentType, doc.documentMode)) {
      doc = await this.ensureBlankPagedDocumentV2(documentId);
    }
    if (this.supportsPagedDocumentStorage(doc)) {
      const targetPageId: string = this.resolveTargetPageId(doc, pageId);
      const textBoxesPath: string = this.getPageStoragePaths(doc.packagePath, targetPageId).textBoxesPath;
      const snapshot: TextBoxesSnapshot = this.readTextBoxesSnapshot(textBoxesPath);
      snapshot.markdownText = markdownText;
      this.writeJsonFile(textBoxesPath, snapshot);
      return refreshPreview ? this.refreshPreview(documentId) : this.requireDocument(documentId);
    }

    const textBoxesPath: string = `${doc.packagePath}/text-boxes.json`;
    const snapshot: TextBoxesSnapshot = this.readTextBoxesSnapshot(textBoxesPath);
    snapshot.markdownText = markdownText;
    this.writeJsonFile(textBoxesPath, snapshot);
    return refreshPreview ? this.refreshPreview(documentId) : this.requireDocument(documentId);
  }

  async setDocumentActivePage(documentId: string, activePageId: string): Promise<DocumentRecord> {
    let doc: DocumentRecord = await this.requireDocument(documentId);
    if (this.isBlankPagedDocument(doc.documentType, doc.documentMode)) {
      doc = await this.ensureBlankPagedDocumentV2(documentId);
    }
    if (!this.supportsPagedDocumentStorage(doc)) {
      return doc;
    }

    const activePage: DocumentPageEntry | undefined = doc.pages.find((page) => page.id === activePageId);
    if (activePage === undefined) {
      return doc;
    }

    const now: number = Date.now();
    await this.store!.executeSql(
      'UPDATE documents SET cover_page = ?, updated_at = ? WHERE id = ?',
      [activePage.order, now, documentId]
    );
    await this.updateSchemaV2PagedManifest(documentId, (manifest) => {
      manifest.activePageId = activePageId;
      manifest.coverPage = activePage.order;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async addBlankPage(documentId: string): Promise<DocumentRecord> {
    let doc: DocumentRecord = await this.requireDocument(documentId);
    if (!this.isBlankPagedDocument(doc.documentType, doc.documentMode)) {
      return doc;
    }

    doc = await this.ensureBlankPagedDocumentV2(documentId);
    const newPageEntry: DocumentPageEntry = await this.createDocumentPageEntry({
      id: this.buildNextPageId(doc.pages),
      order: doc.pages.length,
      pageKind: BLANK_PAGE_KIND,
      pageTemplateId: doc.pageTemplateId,
      pageSizeId: doc.pageSizeId,
      paperBackgroundId: doc.paperBackgroundId
    });
    const storagePaths: DocumentPageStoragePaths = this.getPageStoragePaths(doc.packagePath, newPageEntry.id);
    this.writeJsonFile(storagePaths.strokesPath, this.createEmptyStrokeSnapshot());
    this.writeJsonFile(storagePaths.textBoxesPath, this.createEmptyTextBoxesSnapshot(''));

    const now: number = Date.now();
    await this.updateBlankPagedManifest(documentId, (manifest) => {
      manifest.pages = [...manifest.pages, newPageEntry];
      manifest.activePageId = newPageEntry.id;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async deleteBlankPage(documentId: string, pageId: string): Promise<DocumentRecord> {
    let doc: DocumentRecord = await this.requireDocument(documentId);
    if (!this.isBlankPagedDocument(doc.documentType, doc.documentMode) || doc.pages.length <= 1) {
      return doc;
    }

    doc = await this.ensureBlankPagedDocumentV2(documentId);
    const targetIndex: number = doc.pages.findIndex((page) => page.id === pageId);
    if (targetIndex < 0 || doc.pages.length <= 1) {
      return doc;
    }

    const remainingPages: DocumentPageEntry[] = doc.pages.filter((page) => page.id !== pageId);
    const nextActiveIndex: number = Math.min(targetIndex, remainingPages.length - 1);
    const nextActivePageId: string = remainingPages[nextActiveIndex].id;
    this.removeRecursively(this.getPageStoragePaths(doc.packagePath, pageId).pageDirPath);

    const now: number = Date.now();
    await this.updateBlankPagedManifest(documentId, (manifest) => {
      manifest.pages = manifest.pages.filter((page) => page.id !== pageId);
      manifest.activePageId = nextActivePageId;
      manifest.updatedAt = now;
    });
    return this.requireDocument(documentId);
  }

  async captureRuntimePageStrokes(documentId: string, pageId: string): Promise<void> {
    let doc: DocumentRecord = await this.requireDocument(documentId);
    if (this.isBlankPagedDocument(doc.documentType, doc.documentMode)) {
      doc = await this.ensureBlankPagedDocumentV2(documentId);
    }
    if (!this.supportsPagedDocumentStorage(doc)) {
      return;
    }

    const legacyStrokesPath: string = `${doc.packagePath}/strokes.json`;
    if (!this.exists(legacyStrokesPath)) {
      return;
    }
    const targetPath: string = this.getPageStoragePaths(doc.packagePath, pageId).strokesPath;
    this.copyTextFile(legacyStrokesPath, targetPath);
    this.removeFileIfExists(legacyStrokesPath);
  }

  async stagePageStrokesForRuntime(documentId: string, pageId: string): Promise<void> {
    let doc: DocumentRecord = await this.requireDocument(documentId);
    if (this.isBlankPagedDocument(doc.documentType, doc.documentMode)) {
      doc = await this.ensureBlankPagedDocumentV2(documentId);
    }
    if (!this.supportsPagedDocumentStorage(doc)) {
      return;
    }

    const sourcePath: string = this.getPageStoragePaths(doc.packagePath, pageId).strokesPath;
    const runtimePath: string = `${doc.packagePath}/strokes.json`;
    if (this.exists(sourcePath)) {
      this.copyTextFile(sourcePath, runtimePath);
      return;
    }
    if (!this.exists(runtimePath)) {
      this.writeJsonFile(runtimePath, this.createEmptyStrokeSnapshot());
    }
  }

  private mirrorBlankPagedActivePageToLegacyRoot(document: DocumentRecord): void {
    const activePageId: string = document.pages.some((page) => page.id === document.activePageId)
      ? document.activePageId
      : (document.pages[0]?.id ?? '');
    if (activePageId.length === 0) {
      return;
    }
    const activePageStorage: DocumentPageStoragePaths = this.getPageStoragePaths(document.packagePath, activePageId);
    const legacyTextBoxesPath: string = `${document.packagePath}/text-boxes.json`;
    const legacyStrokesPath: string = `${document.packagePath}/strokes.json`;
    if (this.exists(activePageStorage.textBoxesPath)) {
      this.copyTextFile(activePageStorage.textBoxesPath, legacyTextBoxesPath);
    }
    if (this.exists(activePageStorage.strokesPath)) {
      this.copyTextFile(activePageStorage.strokesPath, legacyStrokesPath);
    }
  }

  async updateDocumentPresentation(documentId: string, mode: DocumentMode, backend: RenderBackend): Promise<DocumentRecord> {
    await this.ensureStore();
    const doc: DocumentRecord = await this.requireDocument(documentId);
    if (this.isBlankPagedDocument(doc.documentType, doc.documentMode) && mode !== DocumentMode.PAGED) {
      this.mirrorBlankPagedActivePageToLegacyRoot(doc);
    }
    const now: number = Date.now();
    await this.store!.executeSql(
      'UPDATE documents SET document_mode = ?, render_backend = ?, updated_at = ? WHERE id = ?',
      [mode, backend, now, documentId]
    );
    if (this.isBlankPagedDocument(doc.documentType, doc.documentMode)) {
      await this.updateBlankPagedManifest(documentId, (manifest) => {
        manifest.documentMode = mode;
        manifest.renderBackend = backend;
        manifest.updatedAt = now;
      });
    } else {
      await this.updateManifest(documentId, (manifest) => {
        manifest.documentMode = mode;
        manifest.renderBackend = backend;
        manifest.updatedAt = now;
      });
    }
    return this.requireDocument(documentId);
  }

  private async initialize(): Promise<void> {
    try {
      this.ensureDir(this.documentsRoot);
      await this.ensureStore();
      await this.ensureSchema();
      await this.seedDefaults();
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.initialize', 'bootstrap', this.documentsRoot, error as Object);
    }
  }

  private async ensureStore(): Promise<void> {
    if (!this.store) {
      this.store = await relationalStore.getRdbStore(this.context, this.storeConfig);
    }
  }

  private async ensureSchema(): Promise<void> {
    await this.store!.executeSql(`
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        document_type TEXT NOT NULL,
        document_mode TEXT NOT NULL,
        render_backend TEXT NOT NULL,
        folder_id TEXT,
        package_path TEXT NOT NULL,
        manifest_path TEXT NOT NULL,
        preview_path TEXT NOT NULL,
        preview_summary TEXT NOT NULL,
        cover_page INTEGER NOT NULL DEFAULT 0,
        cover_version INTEGER NOT NULL DEFAULT 1,
        is_trashed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        opened_at INTEGER NOT NULL,
        trashed_at INTEGER NOT NULL DEFAULT 0
      )
    `);
    await this.store!.executeSql(`
      CREATE TABLE IF NOT EXISTS folders (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        parent_id TEXT,
        color TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      )
    `);
    await this.store!.executeSql(`
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        color TEXT NOT NULL
      )
    `);
    await this.store!.executeSql(`
      CREATE TABLE IF NOT EXISTS document_tags (
        doc_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (doc_id, tag_id)
      )
    `);
    await this.store!.executeSql(`
      CREATE TABLE IF NOT EXISTS favorites_or_flags (
        doc_id TEXT PRIMARY KEY,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
    `);
    await this.store!.executeSql(`
      CREATE TABLE IF NOT EXISTS recent_visits (
        doc_id TEXT PRIMARY KEY,
        visited_at INTEGER NOT NULL
      )
    `);
  }

  private async seedDefaults(): Promise<void> {
    try {
      if (await this.countRows('folders') === 0) {
        for (const folder of DEFAULT_FOLDERS) {
          await this.store!.executeSql(
            'INSERT INTO folders (id, title, parent_id, color, sort_order) VALUES (?, ?, ?, ?, ?)',
            [folder.id, folder.title, folder.parentId, folder.color, folder.sortOrder]
          );
        }
      }

      if (await this.countRows('tags') === 0) {
        for (const tag of DEFAULT_TAGS) {
          await this.store!.executeSql(
            'INSERT INTO tags (id, title, color) VALUES (?, ?, ?)',
            [tag.id, tag.title, tag.color]
          );
        }
      }

      if (await this.countRows('documents') !== 0) {
        return;
      }

      for (const payload of SEEDED_DOCUMENTS) {
        const document: DocumentRecord = await this.createDocument(payload);
        if (payload.documentType === DocumentType.BLANK) {
          await this.assignTags(document.id, ['tag-class', 'tag-math']);
          await this.toggleFavorite(document.id);
        } else if (payload.documentType === DocumentType.PDF) {
          await this.assignTags(document.id, ['tag-pdf']);
        } else {
          await this.assignTags(document.id, ['tag-draft']);
        }
      }
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.seedDefaults', 'bootstrap', this.documentsRoot, error as Object);
    }
  }

  private async countRows(tableName: string): Promise<number> {
    const resultSet = await this.store!.querySql(`SELECT COUNT(*) FROM ${tableName}`);
    let count: number = 0;
    if (resultSet.goToNextRow()) {
      count = resultSet.getLong(0);
    }
    resultSet.close();
    return count;
  }

  private async requireDocument(documentId: string): Promise<DocumentRecord> {
    await this.ensureStore();
    const resultSet = await this.store!.querySql(
      `SELECT d.id, d.title, d.document_type, d.document_mode, d.render_backend, d.folder_id,
              d.package_path, d.manifest_path, d.preview_path, d.preview_summary,
              d.cover_page, d.cover_version, IFNULL(f.is_favorite, 0), IFNULL(f.is_pinned, 0),
              d.is_trashed, d.created_at, d.updated_at, d.opened_at, d.trashed_at
       FROM documents d
       LEFT JOIN favorites_or_flags f ON f.doc_id = d.id
       WHERE d.id = ?
       LIMIT 1`,
      [documentId]
    );

    let row: DocumentRow | undefined;
    if (resultSet.goToNextRow()) {
      row = {
        id: resultSet.getString(0),
        title: resultSet.getString(1),
        documentType: resultSet.getString(2) as DocumentType,
        documentMode: resultSet.getString(3) as DocumentMode,
        renderBackend: resultSet.getString(4) as RenderBackend,
        folderId: resultSet.isColumnNull(5) ? null : resultSet.getString(5),
        packagePath: resultSet.getString(6),
        manifestPath: resultSet.getString(7),
        previewPath: resultSet.getString(8),
        previewSummary: resultSet.getString(9),
        coverPage: resultSet.getLong(10),
        coverVersion: resultSet.getLong(11),
        isFavorite: resultSet.getLong(12) === 1,
        isPinned: resultSet.getLong(13) === 1,
        isTrashed: resultSet.getLong(14) === 1,
        createdAt: resultSet.getLong(15),
        updatedAt: resultSet.getLong(16),
        openedAt: resultSet.getLong(17),
        trashedAt: resultSet.getLong(18)
      };
    }
    resultSet.close();

    if (!row) {
      throw new Error(`Document not found: ${documentId}`);
    }

    const allTags: TagRecord[] = await this.listTags();
    const tagMap: Map<string, TagRecord> = new Map<string, TagRecord>();
    allTags.forEach((tag: TagRecord) => tagMap.set(tag.id, tag));
    const tagLookup: Map<string, TagRecord[]> = await this.loadDocumentTags([row.id], tagMap);
    const document: DocumentRecord = this.toDocumentRecord(row, tagLookup.get(row.id) ?? []);
    return this.enrichDocumentRecord(document);
  }

  private async enrichDocumentRecord(document: DocumentRecord): Promise<DocumentRecord> {
    const normalizedManifest: DocumentManifest | null = await this.readNormalizedManifest(document.manifestPath, false);
    const compatFields: ResolvedDocumentPageMetadata = normalizedManifest
      ? {
        pageTemplateId: normalizedManifest.pageTemplateId as string,
        pageSizeId: normalizedManifest.pageSizeId as string,
        paperBackgroundId: normalizedManifest.paperBackgroundId as string
      }
      : await this.getDefaultDocumentPageMetadata();
    const normalizedPages: DocumentPageEntry[] = normalizedManifest?.pages ?? [];
    const normalizedActivePageId: string = normalizedManifest?.activePageId ?? '';
    const normalizedCoverPage: number = normalizedManifest?.coverPage ?? document.coverPage;
    const normalizedAttachments: DocumentAttachmentEntry[] = normalizedManifest?.attachments ?? [];
    const normalizedDocument: DocumentRecord = {
      id: document.id,
      title: document.title,
      documentType: document.documentType,
      documentMode: document.documentMode,
      renderBackend: document.renderBackend,
      previewSnapshot: document.previewSnapshot,
      schemaVersion: normalizedManifest?.schemaVersion ?? LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION,
      activePageId: normalizedActivePageId,
      pageCount: normalizedPages.length,
      pages: normalizedPages,
      pageTemplateId: compatFields.pageTemplateId,
      pageSizeId: compatFields.pageSizeId,
      paperBackgroundId: compatFields.paperBackgroundId,
      folderId: document.folderId,
      packagePath: document.packagePath,
      manifestPath: document.manifestPath,
      previewPath: document.previewPath,
      previewSummary: normalizedManifest?.previewSummary ?? document.previewSummary,
      coverPage: normalizedCoverPage,
      coverVersion: document.coverVersion,
      isFavorite: document.isFavorite,
      isPinned: document.isPinned,
      isTrashed: document.isTrashed,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      openedAt: document.openedAt,
      trashedAt: document.trashedAt,
      attachments: normalizedAttachments,
      tags: document.tags
    };
    const previewSnapshot: DocumentPreviewSnapshot = this.resolveDocumentPreviewSnapshot(normalizedDocument, compatFields);
    return {
      id: normalizedDocument.id,
      title: normalizedDocument.title,
      documentType: normalizedDocument.documentType,
      documentMode: normalizedDocument.documentMode,
      renderBackend: normalizedDocument.renderBackend,
      previewSnapshot,
      schemaVersion: normalizedDocument.schemaVersion,
      activePageId: normalizedDocument.activePageId,
      pageCount: normalizedDocument.pageCount,
      pages: normalizedDocument.pages,
      pageTemplateId: normalizedDocument.pageTemplateId,
      pageSizeId: normalizedDocument.pageSizeId,
      paperBackgroundId: normalizedDocument.paperBackgroundId,
      folderId: normalizedDocument.folderId,
      packagePath: normalizedDocument.packagePath,
      manifestPath: normalizedDocument.manifestPath,
      previewPath: normalizedDocument.previewPath,
      previewSummary: normalizedDocument.previewSummary,
      coverPage: normalizedDocument.coverPage,
      coverVersion: normalizedDocument.coverVersion,
      isFavorite: normalizedDocument.isFavorite,
      isPinned: normalizedDocument.isPinned,
      isTrashed: normalizedDocument.isTrashed,
      createdAt: normalizedDocument.createdAt,
      updatedAt: normalizedDocument.updatedAt,
      openedAt: normalizedDocument.openedAt,
      trashedAt: normalizedDocument.trashedAt,
      attachments: normalizedDocument.attachments,
      tags: normalizedDocument.tags
    };
  }

  private async loadDocumentTags(docIds: string[], tagMap: Map<string, TagRecord>): Promise<Map<string, TagRecord[]>> {
    const lookup: Map<string, TagRecord[]> = new Map<string, TagRecord[]>();
    if (docIds.length === 0) {
      return lookup;
    }

    const placeholders: string = docIds.map(() => '?').join(', ');
    const resultSet = await this.store!.querySql(
      `SELECT doc_id, tag_id FROM document_tags WHERE doc_id IN (${placeholders})`,
      docIds
    );
    while (resultSet.goToNextRow()) {
      const docId: string = resultSet.getString(0);
      const tagId: string = resultSet.getString(1);
      const tag: TagRecord | undefined = tagMap.get(tagId);
      if (!tag) {
        continue;
      }
      const bucket: TagRecord[] = lookup.get(docId) ?? [];
      bucket.push(tag);
      lookup.set(docId, bucket);
    }
    resultSet.close();
    return lookup;
  }

  private toDocumentRecord(
    row: DocumentRow,
    tags: TagRecord[],
    compatFields?: ResolvedDocumentPageMetadata
  ): DocumentRecord {
    return {
      id: row.id,
      title: row.title,
      documentType: row.documentType,
      documentMode: row.documentMode,
      renderBackend: row.renderBackend,
      previewSnapshot: undefined,
      schemaVersion: LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION,
      activePageId: '',
      pageCount: 0,
      pages: [],
      pageTemplateId: compatFields?.pageTemplateId,
      pageSizeId: compatFields?.pageSizeId,
      paperBackgroundId: compatFields?.paperBackgroundId,
      folderId: row.folderId,
      packagePath: row.packagePath,
      manifestPath: row.manifestPath,
      previewPath: row.previewPath,
      previewSummary: row.previewSummary,
      coverPage: row.coverPage,
      coverVersion: row.coverVersion,
      isFavorite: row.isFavorite,
      isPinned: row.isPinned,
      isTrashed: row.isTrashed,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      openedAt: row.openedAt,
      trashedAt: row.trashedAt,
      attachments: [],
      tags
    };
  }

  private defaultSummary(payload: DocumentCreatePayload): string {
    switch (payload.documentType) {
      case DocumentType.PDF:
        return DOCUMENT_LIBRARY_COPY.defaultPdfSummary;
      case DocumentType.HYBRID:
        return DOCUMENT_LIBRARY_COPY.defaultHybridSummary;
      default:
        return payload.documentMode === DocumentMode.INFINITE
          ? DOCUMENT_LIBRARY_COPY.defaultInfiniteSummary
          : DOCUMENT_LIBRARY_COPY.defaultPagedSummary;
    }
  }

  private defaultMarkdown(payload: DocumentCreatePayload): string {
    return `# ${payload.title}\n\n${this.defaultSummary(payload)}\n\n- ${DOCUMENT_LIBRARY_COPY.modeLabel}：${payload.documentMode}\n- ${DOCUMENT_LIBRARY_COPY.backendLabel}：${payload.renderBackend}`;
  }

  private buildPreviewSnapshot(
    document: DocumentRecord,
    summary: string,
    generatedAt: number,
    nativePreview?: NativePreviewPayload | null
  ): DocumentPreviewSnapshot {
    const resolvedMetadata: ResolvedDocumentPageMetadata = resolveDocumentPageMetadata(
      {
        pageTemplateId: document.pageTemplateId,
        pageSizeId: document.pageSizeId,
        paperBackgroundId: document.paperBackgroundId
      },
      DEFAULT_DOCUMENT_PAGE_METADATA
    );
    const rawPayload: string | Object | null | undefined = nativePreview ?? this.readPreviewPayloadText(document.previewPath);
    return this.previewAdapter.normalizeRequestPreviewRenderPayload(
      rawPayload,
      this.buildPreviewNormalizationContext(
        document.documentType,
        document.documentMode,
        document.renderBackend,
        resolvedMetadata,
        summary,
        `${document.documentMode}/${document.renderBackend}`,
        generatedAt,
        this.resolvePreviewFallbackPageIndex(document)
      )
    );
  }

  private resolveDocumentPreviewSnapshot(
    document: DocumentRecord,
    pageMetadata: ResolvedDocumentPageMetadata
  ): DocumentPreviewSnapshot {
    const cacheKey: string = this.buildPreviewSnapshotCacheKey(document.previewPath, document.updatedAt, document.coverVersion);
    const cachedSnapshot: DocumentPreviewSnapshot | undefined = this.previewSnapshotCache.get(cacheKey);
    if (cachedSnapshot !== undefined) {
      return cachedSnapshot;
    }

    const rawPayload: string = this.readPreviewPayloadText(document.previewPath);
    const snapshot: DocumentPreviewSnapshot = this.previewAdapter.normalizeRequestPreviewRenderPayload(
      rawPayload.length > 0 ? rawPayload : undefined,
      this.buildPreviewNormalizationContext(
        document.documentType,
        document.documentMode,
        document.renderBackend,
        pageMetadata,
        document.previewSummary,
        `${document.documentMode}/${document.renderBackend}`,
        document.updatedAt,
        this.resolvePreviewFallbackPageIndex(document)
      )
    );
    this.storePreviewSnapshotCache(document.previewPath, cacheKey, snapshot);
    return snapshot;
  }

  private buildPreviewSnapshotCacheKey(previewPath: string, updatedAt: number, coverVersion: number): string {
    return `${previewPath}::${updatedAt}::${coverVersion}`;
  }

  private storePreviewSnapshotCache(previewPath: string, cacheKey: string, snapshot: DocumentPreviewSnapshot): void {
    const previousKey: string | undefined = this.previewCacheKeyByPath.get(previewPath);
    if (previousKey !== undefined && previousKey !== cacheKey) {
      this.previewSnapshotCache.delete(previousKey);
    }
    this.previewCacheKeyByPath.set(previewPath, cacheKey);
    this.previewSnapshotCache.set(cacheKey, snapshot);
  }

  private invalidatePreviewSnapshotCache(previewPath: string): void {
    const cacheKey: string | undefined = this.previewCacheKeyByPath.get(previewPath);
    if (cacheKey === undefined) {
      return;
    }
    this.previewCacheKeyByPath.delete(previewPath);
    this.previewSnapshotCache.delete(cacheKey);
  }

  private readPreviewPayloadText(previewPath: string): string {
    if (!this.exists(previewPath)) {
      return '';
    }
    try {
      return fileIo.readTextSync(previewPath);
    } catch (_) {
      return '';
    }
  }

  private createEmptyStrokeSnapshot(): StrokeSnapshot {
    return {
      version: 1,
      strokes: [],
      predictions: []
    };
  }

  private createEmptyTextBoxesSnapshot(markdownText: string): TextBoxesSnapshot {
    return {
      version: 1,
      markdownText,
      items: []
    };
  }

  private readTextBoxesSnapshot(path: string): TextBoxesSnapshot {
    if (!this.exists(path)) {
      return this.createEmptyTextBoxesSnapshot('');
    }
    try {
      return JSON.parse(fileIo.readTextSync(path)) as TextBoxesSnapshot;
    } catch (_) {
      return this.createEmptyTextBoxesSnapshot('');
    }
  }

  private isBlankPagedPayload(payload: DocumentCreatePayload): boolean {
    return payload.documentType === DocumentType.BLANK && payload.documentMode === DocumentMode.PAGED;
  }

  private isBlankPagedDocument(documentType: DocumentType, documentMode: DocumentMode): boolean {
    return documentType === DocumentType.BLANK && documentMode === DocumentMode.PAGED;
  }

  private isBlankPagedManifest(documentType: DocumentType, documentMode: DocumentMode): boolean {
    return documentType === DocumentType.BLANK && documentMode === DocumentMode.PAGED;
  }

  private supportsSchemaV2PagedManifest(manifest: DocumentManifest): boolean {
    return manifest.documentMode === DocumentMode.PAGED &&
      (manifest.schemaVersion ?? LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION) >= DOCUMENT_PACKAGE_SCHEMA_VERSION_V2;
  }

  private supportsPagedDocumentStorage(document: DocumentRecord): boolean {
    return document.documentMode === DocumentMode.PAGED &&
      document.schemaVersion >= DOCUMENT_PACKAGE_SCHEMA_VERSION_V2 &&
      document.pages.length > 0;
  }

  private resolveTargetPageId(document: DocumentRecord, pageId?: string): string {
    if (!this.supportsPagedDocumentStorage(document)) {
      return '';
    }
    if (pageId !== undefined && document.pages.some((page) => page.id === pageId)) {
      return pageId;
    }
    if (document.activePageId.length > 0 && document.pages.some((page) => page.id === document.activePageId)) {
      return document.activePageId;
    }
    return document.pages[0]?.id ?? NATIVE_PRIMARY_PAGE_ID;
  }

  private getPageStoragePaths(packagePath: string, pageId: string): DocumentPageStoragePaths {
    const pageDirPath: string = `${packagePath}/pages/${pageId}`;
    return {
      pageDirPath,
      strokesPath: `${pageDirPath}/strokes.json`,
      textBoxesPath: `${pageDirPath}/text-boxes.json`
    };
  }

  private resolvePreviewFallbackPageIndex(document: DocumentRecord): number {
    if (!this.supportsPagedDocumentStorage(document)) {
      return Math.max(0, document.coverPage);
    }
    return this.resolveCoverPage(
      document.pages,
      this.resolveTargetPageId(document, document.activePageId),
      document.coverPage
    );
  }

  private readDocumentMarkdown(document: DocumentRecord, pageId?: string): string {
    let textBoxesPath: string = `${document.packagePath}/text-boxes.json`;
    if (this.supportsPagedDocumentStorage(document)) {
      const pageTextBoxesPath: string = this.getPageStoragePaths(
        document.packagePath,
        this.resolveTargetPageId(document, pageId)
      ).textBoxesPath;
      textBoxesPath = this.exists(pageTextBoxesPath) ? pageTextBoxesPath : textBoxesPath;
    }
    if (!this.exists(textBoxesPath)) {
      return '';
    }
    const parsed: JsonMap = JSON.parse(fileIo.readTextSync(textBoxesPath)) as JsonMap;
    return String(parsed['markdownText'] ?? '');
  }

  private async updateManifest(documentId: string, updater: (manifest: DocumentManifest) => void): Promise<void> {
    const doc: DocumentRecord = await this.requireDocument(documentId);
    const manifest: DocumentManifest | null = this.readStoredManifest(doc.manifestPath);
    if (manifest === null) {
      return;
    }
    updater(manifest);
    this.writeJsonFile(doc.manifestPath, manifest);
  }

  private async updateBlankPagedManifest(documentId: string, updater: (manifest: DocumentManifest) => void): Promise<void> {
    const doc: DocumentRecord = await this.requireDocument(documentId);
    let manifest: DocumentManifest | null = this.readStoredManifest(doc.manifestPath);
    if (manifest === null) {
      return;
    }
    manifest = await this.applyManifestCompatDefaults(manifest);
    if (!this.isBlankPagedManifest(manifest.documentType, manifest.documentMode)) {
      return;
    }
    manifest.schemaVersion = DOCUMENT_PACKAGE_SCHEMA_VERSION_V2;
    updater(manifest);
    const manifestFallbackMetadata: ResolvedDocumentPageMetadata = {
      pageTemplateId: manifest.pageTemplateId ?? DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId,
      pageSizeId: manifest.pageSizeId ?? DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId,
      paperBackgroundId: manifest.paperBackgroundId ?? DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId
    };
    manifest.pages = await this.normalizeDocumentPages(
      manifest.pages,
      manifestFallbackMetadata,
      true
    );
    manifest.attachments = this.normalizeDocumentAttachments(manifest.attachments);
    manifest.activePageId = this.resolveActivePageId(manifest.pages, manifest.activePageId);
    manifest.coverPage = this.resolveCoverPage(manifest.pages, manifest.activePageId, manifest.coverPage);
    this.applyActivePageMirrorToManifest(manifest);
    this.writeJsonFile(doc.manifestPath, manifest);
    await this.store!.executeSql(
      'UPDATE documents SET cover_page = ?, updated_at = ? WHERE id = ?',
      [manifest.coverPage, manifest.updatedAt, documentId]
    );
  }

  private async updateSchemaV2PagedManifest(documentId: string, updater: (manifest: DocumentManifest) => void): Promise<void> {
    const doc: DocumentRecord = await this.requireDocument(documentId);
    let manifest: DocumentManifest | null = this.readStoredManifest(doc.manifestPath);
    if (manifest === null) {
      return;
    }
    manifest = await this.applyManifestCompatDefaults(manifest);
    if (!this.supportsSchemaV2PagedManifest(manifest)) {
      return;
    }
    manifest.schemaVersion = DOCUMENT_PACKAGE_SCHEMA_VERSION_V2;
    updater(manifest);
    const manifestFallbackMetadata: ResolvedDocumentPageMetadata = {
      pageTemplateId: manifest.pageTemplateId ?? DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId,
      pageSizeId: manifest.pageSizeId ?? DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId,
      paperBackgroundId: manifest.paperBackgroundId ?? DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId
    };
    manifest.pages = await this.normalizeDocumentPages(
      manifest.pages,
      manifestFallbackMetadata,
      this.isBlankPagedManifest(manifest.documentType, manifest.documentMode)
    );
    manifest.attachments = this.normalizeDocumentAttachments(manifest.attachments);
    manifest.activePageId = this.resolveActivePageId(manifest.pages, manifest.activePageId);
    manifest.coverPage = this.resolveCoverPage(manifest.pages, manifest.activePageId, manifest.coverPage);
    if (manifest.pages.length > 0) {
      this.applyActivePageMirrorToManifest(manifest);
    }
    this.writeJsonFile(doc.manifestPath, manifest);
    await this.store!.executeSql(
      'UPDATE documents SET cover_page = ?, updated_at = ? WHERE id = ?',
      [manifest.coverPage, manifest.updatedAt, documentId]
    );
  }

  private async getAppSettingsService(): Promise<AppSettingsService> {
    if (!this.appSettingsService) {
      this.appSettingsService = await AppSettingsService.getInstance(this.context);
    }
    return this.appSettingsService;
  }

  private async getDefaultDocumentPageMetadata(): Promise<ResolvedDocumentPageMetadata> {
    const settingsService: AppSettingsService = await this.getAppSettingsService();
    const settings = await settingsService.getSettings();
    return getDocumentPageMetadataFromSettings(settings);
  }

  private async resolveDocumentCompatFields(
    input: DocumentPageMetadata | undefined
  ): Promise<ResolvedDocumentPageMetadata> {
    const defaults: ResolvedDocumentPageMetadata = await this.getDefaultDocumentPageMetadata();
    return resolveDocumentPageMetadata(input, defaults);
  }

  private buildPreviewNormalizationContext(
    documentType: DocumentType,
    documentMode: DocumentMode,
    renderBackend: RenderBackend,
    pageMetadata: ResolvedDocumentPageMetadata,
    fallbackSummary: string,
    fallbackPreviewLabel: string,
    generatedAt: number,
    fallbackPageIndex: number = 0
  ): PreviewNormalizationContext {
    return {
      documentType,
      documentMode,
      renderBackend,
      pageMetadata,
      generatedAt,
      fallbackSummary,
      fallbackPreviewLabel,
      fallbackPageIndex
    };
  }

  private readStoredManifest(manifestPath: string): DocumentManifest | null {
    const manifestReadResult: StoredManifestReadResult = this.readStoredManifestResult(manifestPath);
    return manifestReadResult.status === 'ok' ? manifestReadResult.manifest : null;
  }

  private readStoredManifestResult(manifestPath: string): StoredManifestReadResult {
    if (!this.exists(manifestPath)) {
      return {
        status: 'missing',
        manifest: null,
        detail: ''
      };
    }

    let rawManifestText: string = '';
    try {
      rawManifestText = fileIo.readTextSync(manifestPath);
    } catch (error) {
      return {
        status: 'read_failed',
        manifest: null,
        detail: this.describeManifestReadFailure(manifestPath, error as Object)
      };
    }

    try {
      return {
        status: 'ok',
        manifest: JSON.parse(rawManifestText) as DocumentManifest,
        detail: ''
      };
    } catch (error) {
      return {
        status: 'parse_failed',
        manifest: null,
        detail: this.describeManifestParseFailure(manifestPath, rawManifestText, error as Object)
      };
    }
  }

  private async readStoredManifestResultWithRetry(manifestPath: string): Promise<StoredManifestReadResult> {
    const retryDelaysMs: number[] = [0, 12, 24, 48, 96];
    let latestResult: StoredManifestReadResult = this.readStoredManifestResult(manifestPath);
    for (let index: number = 0; index < retryDelaysMs.length; index += 1) {
      if (index > 0) {
        await this.waitForDuration(retryDelaysMs[index]);
        latestResult = this.readStoredManifestResult(manifestPath);
      }
      if (latestResult.status === 'ok' || !this.isTransientManifestReadStatus(latestResult.status)) {
        return latestResult;
      }
    }
    return latestResult;
  }

  private isTransientManifestReadStatus(status: string): boolean {
    return status === 'read_failed' || status === 'parse_failed';
  }

  private async waitForDuration(delayMs: number): Promise<void> {
    if (delayMs <= 0) {
      return;
    }
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), delayMs);
    });
  }

  private describeManifestReadFailure(manifestPath: string, error: Object): string {
    const code: number = this.readErrorCode(error);
    return `read failed code=${code} detail=${error} path=${manifestPath}`;
  }

  private describeManifestParseFailure(manifestPath: string, rawManifestText: string, error: Object): string {
    const code: number = this.readErrorCode(error);
    const snippetLength: number = Math.min(rawManifestText.length, 120);
    const snippet: string = rawManifestText.slice(0, snippetLength).replace(/\s+/g, ' ');
    return `parse failed code=${code} detail=${error} path=${manifestPath} raw=${snippet}`;
  }

  private async readNormalizedManifest(
    manifestPath: string,
    _persistIfChanged: boolean
  ): Promise<DocumentManifest | null> {
    const manifest: DocumentManifest | null = this.readStoredManifest(manifestPath);
    if (manifest === null) {
      return null;
    }
    return this.applyManifestCompatDefaults(manifest);
  }

  private async applyManifestCompatDefaults(manifest: DocumentManifest): Promise<DocumentManifest> {
    const manifestCompat: DocumentPageMetadata = {
      pageTemplateId: manifest.pageTemplateId,
      pageSizeId: manifest.pageSizeId,
      paperBackgroundId: manifest.paperBackgroundId
    };
    const compatFields: ResolvedDocumentPageMetadata = await this.resolveDocumentCompatFields(manifestCompat);
    const normalizedAttachments: DocumentAttachmentEntry[] = this.normalizeDocumentAttachments(manifest.attachments);
    if (this.isBlankPagedManifest(manifest.documentType, manifest.documentMode)) {
      const normalizedPages: DocumentPageEntry[] = await this.normalizeDocumentPages(manifest.pages, compatFields);
      const activePageId: string = this.resolveActivePageId(normalizedPages, manifest.activePageId);
      const normalizedManifest: DocumentManifest = {
        id: manifest.id,
        title: manifest.title,
        documentType: manifest.documentType,
        documentMode: manifest.documentMode,
        renderBackend: manifest.renderBackend,
        schemaVersion: manifest.schemaVersion === DOCUMENT_PACKAGE_SCHEMA_VERSION_V2
          ? DOCUMENT_PACKAGE_SCHEMA_VERSION_V2
          : LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION,
        activePageId,
        pages: normalizedPages,
        pageTemplateId: compatFields.pageTemplateId,
        pageSizeId: compatFields.pageSizeId,
        paperBackgroundId: compatFields.paperBackgroundId,
        folderId: manifest.folderId,
        coverPage: manifest.coverPage ?? 0,
        coverVersion: manifest.coverVersion,
        isFavorite: manifest.isFavorite,
        isTrashed: manifest.isTrashed,
        createdAt: manifest.createdAt,
        updatedAt: manifest.updatedAt,
        openedAt: manifest.openedAt,
        trashedAt: manifest.trashedAt,
        attachments: normalizedAttachments,
        tags: manifest.tags ?? [],
        previewSummary: manifest.previewSummary ?? ''
      };
      this.applyActivePageMirrorToManifest(normalizedManifest);
      return normalizedManifest;
    }

    if (this.supportsSchemaV2PagedManifest(manifest)) {
      const normalizedPages: DocumentPageEntry[] = await this.normalizeDocumentPages(manifest.pages, compatFields, false);
      const activePageId: string = this.resolveActivePageId(normalizedPages, manifest.activePageId);
      const normalizedManifest: DocumentManifest = {
        id: manifest.id,
        title: manifest.title,
        documentType: manifest.documentType,
        documentMode: manifest.documentMode,
        renderBackend: manifest.renderBackend,
        schemaVersion: DOCUMENT_PACKAGE_SCHEMA_VERSION_V2,
        activePageId,
        pages: normalizedPages,
        pageTemplateId: compatFields.pageTemplateId,
        pageSizeId: compatFields.pageSizeId,
        paperBackgroundId: compatFields.paperBackgroundId,
        folderId: manifest.folderId,
        coverPage: this.resolveCoverPage(normalizedPages, activePageId, manifest.coverPage ?? 0),
        coverVersion: manifest.coverVersion,
        isFavorite: manifest.isFavorite,
        isTrashed: manifest.isTrashed,
        createdAt: manifest.createdAt,
        updatedAt: manifest.updatedAt,
        openedAt: manifest.openedAt,
        trashedAt: manifest.trashedAt,
        attachments: normalizedAttachments,
        tags: manifest.tags ?? [],
        previewSummary: manifest.previewSummary ?? ''
      };
      if (normalizedPages.length > 0) {
        this.applyActivePageMirrorToManifest(normalizedManifest);
      }
      return normalizedManifest;
    }

    const normalizedManifest: DocumentManifest = {
      id: manifest.id,
      title: manifest.title,
      documentType: manifest.documentType,
      documentMode: manifest.documentMode,
      renderBackend: manifest.renderBackend,
      schemaVersion: manifest.schemaVersion ?? LEGACY_DOCUMENT_PACKAGE_SCHEMA_VERSION,
      activePageId: '',
      pages: [],
      pageTemplateId: compatFields.pageTemplateId,
      pageSizeId: compatFields.pageSizeId,
      paperBackgroundId: compatFields.paperBackgroundId,
      folderId: manifest.folderId,
      coverPage: manifest.coverPage ?? 0,
      coverVersion: manifest.coverVersion,
      isFavorite: manifest.isFavorite,
      isTrashed: manifest.isTrashed,
      createdAt: manifest.createdAt,
      updatedAt: manifest.updatedAt,
      openedAt: manifest.openedAt,
      trashedAt: manifest.trashedAt,
      attachments: normalizedAttachments,
      tags: manifest.tags ?? [],
      previewSummary: manifest.previewSummary ?? ''
    };
    return normalizedManifest;
  }

  private async normalizeDocumentPages(
    pages: DocumentPageEntry[] | undefined,
    fallbackMetadata: ResolvedDocumentPageMetadata,
    allowSyntheticFallback: boolean = true
  ): Promise<DocumentPageEntry[]> {
    const sourcePages: DocumentPageEntry[] = Array.isArray(pages) && pages.length > 0
      ? [...pages].sort((left, right) => left.order - right.order)
      : (allowSyntheticFallback ? [{
        id: NATIVE_PRIMARY_PAGE_ID,
        order: 0,
        pageKind: BLANK_PAGE_KIND,
        pageTemplateId: fallbackMetadata.pageTemplateId,
        pageSizeId: fallbackMetadata.pageSizeId,
        paperBackgroundId: fallbackMetadata.paperBackgroundId
      }] : []);
    const normalizedPages: DocumentPageEntry[] = [];
    for (let index: number = 0; index < sourcePages.length; index += 1) {
      const sourcePage: DocumentPageEntry = sourcePages[index];
      normalizedPages.push(await this.createDocumentPageEntry({
        id: sourcePage.id && sourcePage.id.length > 0 ? sourcePage.id : this.buildNextPageId(normalizedPages),
        order: index,
        pageKind: sourcePage.pageKind || BLANK_PAGE_KIND,
        pageTemplateId: sourcePage.pageTemplateId ?? fallbackMetadata.pageTemplateId,
        pageSizeId: sourcePage.pageSizeId ?? fallbackMetadata.pageSizeId,
        paperBackgroundId: sourcePage.paperBackgroundId ?? fallbackMetadata.paperBackgroundId,
        sourceAttachmentId: sourcePage.sourceAttachmentId,
        sourcePageIndex: sourcePage.sourcePageIndex
      }));
    }
    return normalizedPages;
  }

  private normalizeDocumentAttachments(attachments: DocumentAttachmentEntry[] | undefined): DocumentAttachmentEntry[] {
    if (!Array.isArray(attachments) || attachments.length === 0) {
      return [];
    }
    return attachments.map((attachment: DocumentAttachmentEntry, index: number) => {
      const fallbackId: string = `attachment-${index}`;
      const attachmentId: string = attachment.id && attachment.id.length > 0 ? attachment.id : fallbackId;
      const normalizedAttachment: DocumentAttachmentEntry = {
        id: attachmentId,
        kind: 'pdf',
        displayName: attachment.displayName ?? '',
        mimeType: attachment.mimeType && attachment.mimeType.length > 0 ? attachment.mimeType : 'application/pdf',
        relativePath: attachment.relativePath && attachment.relativePath.length > 0
          ? attachment.relativePath
          : this.buildImportedAttachmentRelativePath(attachmentId),
        byteSize: Math.max(0, Math.trunc(attachment.byteSize ?? 0)),
        importedAt: Math.max(0, Math.trunc(attachment.importedAt ?? 0)),
        pageCount: Math.max(0, Math.trunc(attachment.pageCount ?? 0))
      };
      return normalizedAttachment;
    });
  }

  private async createDocumentPageEntry(page: DocumentPageEntry): Promise<DocumentPageEntry> {
    const compatFields: ResolvedDocumentPageMetadata = await this.resolveDocumentCompatFields({
      pageTemplateId: page.pageTemplateId,
      pageSizeId: page.pageSizeId,
      paperBackgroundId: page.paperBackgroundId
    });
    return {
      id: page.id,
      order: page.order,
      pageKind: page.pageKind,
      pageTemplateId: compatFields.pageTemplateId,
      pageSizeId: compatFields.pageSizeId,
      paperBackgroundId: compatFields.paperBackgroundId,
      sourceAttachmentId: page.sourceAttachmentId,
      sourcePageIndex: page.sourcePageIndex
    };
  }

  private resolveActivePageId(pages: DocumentPageEntry[], requestedPageId?: string): string {
    const candidatePageId: string = requestedPageId ?? '';
    if (candidatePageId.length > 0 && pages.some((page) => page.id === candidatePageId)) {
      return candidatePageId;
    }
    return pages[0]?.id ?? '';
  }

  private resolveCoverPage(pages: DocumentPageEntry[], activePageId: string, fallbackCoverPage: number): number {
    const activePage: DocumentPageEntry | undefined = pages.find((page) => page.id === activePageId);
    return activePage?.order ?? fallbackCoverPage;
  }

  private applyActivePageMirrorToManifest(manifest: DocumentManifest): void {
    const activePage: DocumentPageEntry | undefined = manifest.pages.find((page) => page.id === manifest.activePageId);
    if (activePage === undefined) {
      return;
    }
    manifest.pageTemplateId = activePage.pageTemplateId;
    manifest.pageSizeId = activePage.pageSizeId;
    manifest.paperBackgroundId = activePage.paperBackgroundId;
    manifest.coverPage = activePage.order;
  }

  private buildNextPageId(pages: DocumentPageEntry[]): string {
    let nextPageIndex: number = 0;
    pages.forEach((page) => {
      const match: RegExpMatchArray | null = page.id.match(/^page-(\d+)$/);
      if (!match) {
        return;
      }
      nextPageIndex = Math.max(nextPageIndex, Number.parseInt(match[1], 10) + 1);
    });
    return `page-${nextPageIndex}`;
  }

  private async ensureBlankPagedDocumentV2(documentId: string): Promise<DocumentRecord> {
    let document: DocumentRecord = await this.requireDocument(documentId);
    if (!this.isBlankPagedDocument(document.documentType, document.documentMode)) {
      return document;
    }

    const storedManifest: DocumentManifest | null = this.readStoredManifest(document.manifestPath);
    if (storedManifest === null) {
      return document;
    }
    const normalizedManifest: DocumentManifest = await this.applyManifestCompatDefaults(storedManifest);
    if (normalizedManifest.schemaVersion === DOCUMENT_PACKAGE_SCHEMA_VERSION_V2) {
      return document;
    }

    const activePageId: string = this.resolveActivePageId(normalizedManifest.pages, normalizedManifest.activePageId);
    const activePageStorage: DocumentPageStoragePaths = this.getPageStoragePaths(document.packagePath, activePageId);
    const legacyStrokesPath: string = `${document.packagePath}/strokes.json`;
    const legacyTextBoxesPath: string = `${document.packagePath}/text-boxes.json`;

    if (this.exists(legacyStrokesPath)) {
      this.copyTextFile(legacyStrokesPath, activePageStorage.strokesPath);
    } else if (!this.exists(activePageStorage.strokesPath)) {
      this.writeJsonFile(activePageStorage.strokesPath, this.createEmptyStrokeSnapshot());
    }
    if (this.exists(legacyTextBoxesPath)) {
      this.copyTextFile(legacyTextBoxesPath, activePageStorage.textBoxesPath);
    } else if (!this.exists(activePageStorage.textBoxesPath)) {
      this.writeJsonFile(activePageStorage.textBoxesPath, this.createEmptyTextBoxesSnapshot(''));
    }

    normalizedManifest.schemaVersion = DOCUMENT_PACKAGE_SCHEMA_VERSION_V2;
    normalizedManifest.activePageId = activePageId;
    normalizedManifest.updatedAt = Date.now();
    this.applyActivePageMirrorToManifest(normalizedManifest);
    this.writeJsonFile(document.manifestPath, normalizedManifest);
    this.removeFileIfExists(legacyStrokesPath);
    this.removeFileIfExists(legacyTextBoxesPath);
    await this.store!.executeSql(
      'UPDATE documents SET cover_page = ?, updated_at = ? WHERE id = ?',
      [normalizedManifest.coverPage, normalizedManifest.updatedAt, documentId]
    );
    document = await this.requireDocument(documentId);
    return document;
  }

  private ensureDir(path: string): void {
    const normalizedPath: string = this.normalizePath(path);
    if (normalizedPath.length === 0 || this.exists(normalizedPath)) {
      return;
    }
    try {
      fileIo.mkdirSync(normalizedPath, true);
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.ensureDir', 'mkdirSync', normalizedPath, error as Object);
    }
  }

  private normalizePath(path: string): string {
    if (path.length <= 1) {
      return path;
    }
    return path.endsWith('/') ? path.slice(0, -1) : path;
  }

  private getParentPath(path: string): string {
    const normalizedPath: string = this.normalizePath(path);
    const separatorIndex: number = normalizedPath.lastIndexOf('/');
    if (separatorIndex <= 0) {
      return '';
    }
    return normalizedPath.slice(0, separatorIndex);
  }

  private writeJsonFile(path: string, data: Object): void {
    try {
      const parentPath: string = this.getParentPath(path);
      if (parentPath.length > 0) {
        this.ensureDir(parentPath);
      }
      const serializedJson: string = JSON.stringify(data, null, 2);
      if (this.isManifestPath(path)) {
        this.writeJsonFileAtomically(path, serializedJson);
        return;
      }
      let stream: fileIo.Stream;
      try {
        stream = fileIo.createStreamSync(
          path,
          'w'
        );
      } catch (error) {
        throw this.wrapFileError('DocumentLibraryService.writeJsonFile.createStreamSync', 'createStreamSync', path, error as Object);
      }
      try {
        stream.writeSync(serializedJson);
      } catch (error) {
        throw this.wrapFileError('DocumentLibraryService.writeJsonFile.writeSync', 'writeSync', path, error as Object);
      } finally {
        stream.closeSync();
      }
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.writeJsonFile', 'write', path, error as Object);
    }
  }

  private isManifestPath(path: string): boolean {
    return path.endsWith('/manifest.json');
  }

  private writeJsonFileAtomically(path: string, content: string): void {
    const tempPath: string = `${path}.tmp-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    try {
      this.writeTextFile(tempPath, content);
      fileIo.renameSync(tempPath, path);
    } catch (error) {
      this.removeFileIfExists(tempPath);
      throw this.wrapFileError('DocumentLibraryService.writeJsonFileAtomically', 'renameSync', path, error as Object);
    }
  }

  private writeTextFile(path: string, content: string): void {
    try {
      const parentPath: string = this.getParentPath(path);
      if (parentPath.length > 0) {
        this.ensureDir(parentPath);
      }
      let stream: fileIo.Stream;
      try {
        stream = fileIo.createStreamSync(path, 'w');
      } catch (error) {
        throw this.wrapFileError('DocumentLibraryService.writeTextFile.createStreamSync', 'createStreamSync', path, error as Object);
      }
      try {
        stream.writeSync(content);
      } catch (error) {
        throw this.wrapFileError('DocumentLibraryService.writeTextFile.writeSync', 'writeSync', path, error as Object);
      } finally {
        stream.closeSync();
      }
    } catch (error) {
      throw this.wrapFileError('DocumentLibraryService.writeTextFile', 'write', path, error as Object);
    }
  }

  private copyTextFile(sourcePath: string, targetPath: string): void {
    const content: string = fileIo.readTextSync(sourcePath);
    this.writeTextFile(targetPath, content);
  }

  private removeFileIfExists(path: string): void {
    if (!this.exists(path)) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (_) {
      return;
    }
  }

  private wrapFileError(stage: string, op: string, path: string, error: Object): Error {
    if (error instanceof DocumentLibraryBootstrapError || this.isBootstrapError(error)) {
      return error as Error;
    }
    return new DocumentLibraryBootstrapError(
      stage,
      op,
      path,
      this.documentsRoot,
      this.context.filesDir,
      this.readErrorCode(error),
      `${error}`
    );
  }

  private readErrorCode(error: Object): number {
    const rawCode: Object | undefined = (error as Record<string, Object>)['code'];
    return typeof rawCode === 'number' ? rawCode : 0;
  }

  private isBootstrapError(error: Object): boolean {
    const errorMap: Record<string, Object> = error as Record<string, Object>;
    return typeof errorMap['stage'] === 'string' &&
      typeof errorMap['op'] === 'string' &&
      typeof errorMap['path'] === 'string' &&
      typeof errorMap['code'] === 'number' &&
      typeof errorMap['detail'] === 'string';
  }

  private removeRecursively(path: string): void {
    if (!this.exists(path)) {
      return;
    }
    if (!fileIo.statSync(path).isDirectory()) {
      fileIo.unlinkSync(path);
      return;
    }
    fileIo.listFileSync(path).forEach((entryName: string) => this.removeRecursively(`${path}/${entryName}`));
    fileIo.rmdirSync(path);
  }

  private exists(path: string): boolean {
    try {
      fileIo.statSync(path);
      return true;
    } catch {
      return false;
    }
  }
}
