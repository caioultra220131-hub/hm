import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DOCUMENT_MODE_LABELS,
  DOCUMENT_TYPE_LABELS,
  DocumentCreatePayload,
  DocumentMode,
  DocumentRecord,
  DocumentType,
  FolderRecord,
  LibraryHomeData,
  LibraryQuery,
  RenderBackend,
  RENDER_BACKEND_LABELS,
  TagRecord,
  TrashItemVM
} from '../models/NoteModels';
import { PreviewThumbnail } from '../components/PreviewThumbnail';
import { DocumentLibraryService } from '../services/DocumentLibraryService';

const DOMAIN: number = 0xFF00;
const LOG_TAG: string = 'NativeNoteIndex';

type LibraryViewMode = 'home' | 'favorites' | 'trash';

interface DocumentBadgeVM {
  key: string;
  label: string;
  backgroundColor: string;
  fontColor: string;
}

function formatTime(timestamp: number): string {
  const date: Date = new Date(timestamp);
  const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
  const day: string = `${date.getDate()}`.padStart(2, '0');
  const hour: string = `${date.getHours()}`.padStart(2, '0');
  const minute: string = `${date.getMinutes()}`.padStart(2, '0');
  return `${month}-${day} ${hour}:${minute}`;
}

interface IndexCopy {
  untitledNote: string;
  openLibraryError: string;
  libraryTitle: string;
  searchPlaceholder: string;
  documentTitlePlaceholder: string;
  createDocument: string;
  home: string;
  allDocuments: string;
  favorites: string;
  viewFavorites: string;
  trash: string;
  openTrash: string;
  folders: string;
  allFolders: string;
  tags: string;
  allTags: string;
  documents: string;
  restore: string;
  deleteForever: string;
  open: string;
  unfavorite: string;
  details: string;
  delete: string;
  createPanelTitle: string;
  create: string;
  detailsPanelTitle: string;
  saveTitle: string;
  moveToFolder: string;
  libraryHomeTitle: string;
  libraryHomeDescription: string;
  deletePanelTitle: string;
  moveToTrash: string;
  cancel: string;
  previewReady: string;
  previewError: string;
  previewFallback: string;
  guidePlain: string;
  guideLined: string;
  guideGrid: string;
  guideDotted: string;
  guideCornell: string;
  guideWeekly: string;
  updatedAtPrefix: string;
}

const INDEX_COPY: IndexCopy = {
  untitledNote: '未命名笔记',
  openLibraryError: '无法打开本地资料库。',
  libraryTitle: '笔记库',
  searchPlaceholder: '搜索标题、标签、文件夹或摘要',
  documentTitlePlaceholder: '文档标题',
  createDocument: '新建文档',
  home: '首页',
  allDocuments: '全部文档',
  favorites: '收藏',
  viewFavorites: '查看收藏',
  trash: '回收站',
  openTrash: '打开回收站',
  folders: '文件夹',
  allFolders: '全部文件夹',
  tags: '标签',
  allTags: '全部标签',
  documents: '文档',
  restore: '恢复',
  deleteForever: '彻底删除',
  open: '打开',
  unfavorite: '取消收藏',
  details: '详情',
  delete: '删除',
  createPanelTitle: '新建文档',
  create: '创建',
  detailsPanelTitle: '文档详情',
  saveTitle: '保存标题',
  moveToFolder: '移动到文件夹',
  libraryHomeTitle: '笔记库首页',
  libraryHomeDescription: '管理本地优先的文档、收藏、标签、最近访问和回收站。',
  deletePanelTitle: '删除文档',
  moveToTrash: '移入回收站',
  cancel: '取消',
  previewReady: '预览已生成',
  previewError: '预览异常',
  previewFallback: '预览占位',
  guidePlain: '空白',
  guideLined: '横线',
  guideGrid: '网格',
  guideDotted: '点阵',
  guideCornell: '康奈尔',
  guideWeekly: '周计划',
  updatedAtPrefix: '更新于'
};

@Entry
@Component
struct Index {
  private readonly appContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private libraryService?: DocumentLibraryService;

  @State private loading: boolean = true;
  @State private errorMessage: string = '';
  @State private homeData: LibraryHomeData = {
    recent: [],
    favorites: [],
    allDocuments: [],
    trash: [],
    folders: [],
    tags: [],
    sections: []
  };
  @State private viewMode: LibraryViewMode = 'home';
  @State private activeFolderId: string = 'all';
  @State private activeTagId: string = 'all';
  @State private searchText: string = '';
  @State private selectedDocumentId: string = '';
  @State private renameDraft: string = '';
  @State private showCreatePanel: boolean = false;
  @State private createTitle: string = INDEX_COPY.untitledNote;
  @State private createType: DocumentType = DocumentType.BLANK;
  @State private createMode: DocumentMode = DocumentMode.PAGED;
  @State private createBackend: RenderBackend = RenderBackend.OPEN_GLES;
  @State private createFolderId: string = 'inbox';
  @State private showDeletePanel: boolean = false;
  @State private deleteTargetId: string = '';

  aboutToAppear(): void {
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    try {
      this.libraryService = await DocumentLibraryService.getInstance(this.appContext);
      await this.reload();
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, 'bootstrap failed: %{public}s', JSON.stringify(error));
      this.errorMessage = INDEX_COPY.openLibraryError;
    } finally {
      this.loading = false;
    }
  }

  private selectedDocument(): DocumentRecord | undefined {
    return this.homeData.allDocuments.find((doc) => doc.id === this.selectedDocumentId);
  }

  private currentDocuments(): DocumentRecord[] {
    return this.viewMode === 'favorites' ? this.homeData.favorites : this.homeData.allDocuments;
  }

  private previewStatusBadge(doc: DocumentRecord): DocumentBadgeVM {
    switch (doc.previewSnapshot?.previewStatus) {
      case 'ready':
        return {
          key: 'preview-ready',
          label: INDEX_COPY.previewReady,
          backgroundColor: '#EAF6EE',
          fontColor: '#1A7F37'
        };
      case 'error':
        return {
          key: 'preview-error',
          label: INDEX_COPY.previewError,
          backgroundColor: '#FDECEC',
          fontColor: '#B42318'
        };
      default:
        return {
          key: 'preview-fallback',
          label: INDEX_COPY.previewFallback,
          backgroundColor: '#EEF2F6',
          fontColor: '#475467'
        };
    }
  }

  private guideBadge(doc: DocumentRecord): DocumentBadgeVM | undefined {
    const guideKind: string = doc.previewSnapshot?.pageContract.guideKind ?? '';
    switch (guideKind) {
      case 'plain':
        return {
          key: 'guide-plain',
          label: INDEX_COPY.guidePlain,
          backgroundColor: '#F4F7FB',
          fontColor: '#344054'
        };
      case 'lined':
        return {
          key: 'guide-lined',
          label: INDEX_COPY.guideLined,
          backgroundColor: '#EEF4FF',
          fontColor: '#1D4ED8'
        };
      case 'grid':
        return {
          key: 'guide-grid',
          label: INDEX_COPY.guideGrid,
          backgroundColor: '#EEF4FF',
          fontColor: '#1D4ED8'
        };
      case 'dotted':
        return {
          key: 'guide-dotted',
          label: INDEX_COPY.guideDotted,
          backgroundColor: '#EEF4FF',
          fontColor: '#1D4ED8'
        };
      case 'cornell':
        return {
          key: 'guide-cornell',
          label: INDEX_COPY.guideCornell,
          backgroundColor: '#FFF4E8',
          fontColor: '#B54708'
        };
      case 'weekly':
        return {
          key: 'guide-weekly',
          label: INDEX_COPY.guideWeekly,
          backgroundColor: '#FFF4E8',
          fontColor: '#B54708'
        };
      default:
        return undefined;
    }
  }

  private documentBadges(doc: DocumentRecord): DocumentBadgeVM[] {
    const badges: DocumentBadgeVM[] = [
      {
        key: `type-${doc.documentType}`,
        label: DOCUMENT_TYPE_LABELS[doc.documentType],
        backgroundColor: '#EEF2FF',
        fontColor: '#3448C5'
      },
      {
        key: `mode-${doc.documentMode}`,
        label: DOCUMENT_MODE_LABELS[doc.documentMode],
        backgroundColor: '#F2F4F7',
        fontColor: '#475467'
      },
      this.previewStatusBadge(doc)
    ];
    const guideBadge: DocumentBadgeVM | undefined = this.guideBadge(doc);
    if (guideBadge !== undefined) {
      badges.push(guideBadge);
    }
    return badges;
  }

  private async reload(): Promise<void> {
    if (!this.libraryService) {
      return;
    }
    this.loading = true;
    const query: LibraryQuery = {
      searchText: this.searchText,
      folderId: this.activeFolderId === 'all' ? null : this.activeFolderId,
      tagId: this.activeTagId === 'all' ? null : this.activeTagId,
      favoritesOnly: this.viewMode === 'favorites',
      includeTrashed: false
    };
    this.homeData = await this.libraryService.getHomeSections(query);
    if (this.selectedDocumentId.length > 0 && !this.selectedDocument()) {
      this.selectedDocumentId = '';
      this.renameDraft = '';
    }
    this.loading = false;
  }

  private pickDocument(doc: DocumentRecord): void {
    this.selectedDocumentId = doc.id;
    this.renameDraft = doc.title;
    this.showCreatePanel = false;
  }

  private async openDocument(doc: DocumentRecord): Promise<void> {
    if (!this.libraryService) {
      return;
    }
    await this.libraryService.openDocumentById(doc.id);
    router.pushUrl({ url: 'pages/EditorWorkspace', params: { documentId: doc.id } });
  }

  private async toggleFavorite(doc: DocumentRecord): Promise<void> {
    if (!this.libraryService) {
      return;
    }
    await this.libraryService.toggleFavorite(doc.id);
    await this.reload();
  }

  private async createDocument(): Promise<void> {
    if (!this.libraryService) {
      return;
    }
    const payload: DocumentCreatePayload = {
      title: this.createTitle.trim().length > 0 ? this.createTitle.trim() : INDEX_COPY.untitledNote,
      documentType: this.createType,
      documentMode: this.createMode,
      renderBackend: this.createBackend,
      folderId: this.createFolderId
    };
    await this.libraryService.createDocument(payload);
    this.showCreatePanel = false;
    this.createTitle = INDEX_COPY.untitledNote;
    await this.reload();
  }

  private async saveRename(): Promise<void> {
    if (!this.libraryService || this.selectedDocumentId.length === 0) {
      return;
    }
    await this.libraryService.renameDocument(this.selectedDocumentId, this.renameDraft);
    await this.reload();
  }

  private async moveSelected(folderId: string): Promise<void> {
    if (!this.libraryService || this.selectedDocumentId.length === 0) {
      return;
    }
    await this.libraryService.moveDocument(this.selectedDocumentId, folderId);
    await this.reload();
  }

  private async toggleTag(tagId: string): Promise<void> {
    if (!this.libraryService || this.selectedDocumentId.length === 0) {
      return;
    }
    const doc: DocumentRecord | undefined = this.selectedDocument();
    if (!doc) {
      return;
    }
    const tags: string[] = doc.tags.map((tag) => tag.id);
    const nextTags: string[] = tags.includes(tagId) ? tags.filter((id) => id !== tagId) : [...tags, tagId];
    await this.libraryService.assignTags(doc.id, nextTags);
    await this.reload();
  }

  private requestDelete(docId: string): void {
    this.deleteTargetId = docId;
    this.showDeletePanel = true;
  }

  private async deleteDocument(mode: 'trash' | 'purge'): Promise<void> {
    if (!this.libraryService || this.deleteTargetId.length === 0) {
      return;
    }
    await this.libraryService.deleteDocument(this.deleteTargetId, mode);
    this.showDeletePanel = false;
    this.deleteTargetId = '';
    this.selectedDocumentId = '';
    await this.reload();
  }

  private async restoreDocument(docId: string): Promise<void> {
    if (!this.libraryService) {
      return;
    }
    await this.libraryService.restoreDocument(docId);
    await this.reload();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        Column() {
          Text(INDEX_COPY.libraryTitle)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#162033')
          TextInput({ text: this.searchText, placeholder: INDEX_COPY.searchPlaceholder })
            .height(42)
            .margin({ top: 16, bottom: 16 })
            .backgroundColor('#FFFFFF')
            .onChange((value: string) => {
              this.searchText = value;
              this.reload();
            })
          Button(INDEX_COPY.createDocument)
            .width('100%')
            .height(42)
            .backgroundColor('#162033')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.showCreatePanel = true;
              this.selectedDocumentId = '';
            })
          Button(this.viewMode === 'home' ? INDEX_COPY.home : INDEX_COPY.allDocuments)
            .width('100%')
            .height(36)
            .margin({ top: 10 })
            .backgroundColor(this.viewMode === 'home' ? '#DCE6FF' : '#FFFFFF')
            .fontColor('#162033')
            .onClick(() => {
              this.viewMode = 'home';
              this.reload();
            })
          Button(this.viewMode === 'favorites' ? INDEX_COPY.favorites : INDEX_COPY.viewFavorites)
            .width('100%')
            .height(36)
            .margin({ top: 8 })
            .backgroundColor(this.viewMode === 'favorites' ? '#FFE8C7' : '#FFFFFF')
            .fontColor('#162033')
            .onClick(() => {
              this.viewMode = 'favorites';
              this.reload();
            })
          Button(this.viewMode === 'trash' ? INDEX_COPY.trash : INDEX_COPY.openTrash)
            .width('100%')
            .height(36)
            .margin({ top: 8, bottom: 18 })
            .backgroundColor(this.viewMode === 'trash' ? '#FFD8D8' : '#FFFFFF')
            .fontColor('#162033')
            .onClick(() => {
              this.viewMode = 'trash';
              this.reload();
            })

          Text(INDEX_COPY.folders)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })
          Button(INDEX_COPY.allFolders)
            .width('100%')
            .height(34)
            .backgroundColor(this.activeFolderId === 'all' ? '#162033' : '#FFFFFF')
            .fontColor(this.activeFolderId === 'all' ? '#FFFFFF' : '#162033')
            .onClick(() => {
              this.activeFolderId = 'all';
              this.reload();
            })
          ForEach(this.homeData.folders, (folder: FolderRecord) => {
            Button(folder.title)
              .width('100%')
              .height(34)
              .margin({ top: 8 })
              .backgroundColor(this.activeFolderId === folder.id ? folder.color : '#FFFFFF')
              .fontColor(this.activeFolderId === folder.id ? '#FFFFFF' : '#162033')
              .onClick(() => {
                this.activeFolderId = folder.id;
                this.viewMode = 'home';
                this.reload();
              })
          }, (folder: FolderRecord): string => folder.id)

          Text(INDEX_COPY.tags)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 18, bottom: 8 })
          Button(INDEX_COPY.allTags)
            .width('100%')
            .height(34)
            .backgroundColor(this.activeTagId === 'all' ? '#162033' : '#FFFFFF')
            .fontColor(this.activeTagId === 'all' ? '#FFFFFF' : '#162033')
            .onClick(() => {
              this.activeTagId = 'all';
              this.reload();
            })
          ForEach(this.homeData.tags, (tag: TagRecord) => {
            Button(tag.title)
              .width('100%')
              .height(34)
              .margin({ top: 8 })
              .backgroundColor(this.activeTagId === tag.id ? tag.color : '#FFFFFF')
              .fontColor(this.activeTagId === tag.id ? '#FFFFFF' : '#162033')
              .onClick(() => {
                this.activeTagId = tag.id;
                this.viewMode = 'home';
                this.reload();
              })
          }, (tag: TagRecord): string => tag.id)
        }
        .width(250)
        .height('100%')
        .padding(20)
        .backgroundColor('#F4F7FB')

        Column() {
          Text(this.viewMode === 'trash' ? INDEX_COPY.trash : INDEX_COPY.documents)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#162033')
          if (this.loading) {
            LoadingProgress()
              .width(32)
              .height(32)
              .margin({ top: 24 })
          } else if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor('#B42318')
              .margin({ top: 18 })
          } else if (this.viewMode === 'trash') {
            Scroll() {
              Column() {
                ForEach(this.homeData.trash, (item: TrashItemVM) => {
                  Row() {
                    Column() {
                      Text(item.title)
                        .fontSize(18)
                        .fontWeight(FontWeight.Medium)
                      Text(item.summary)
                        .fontSize(12)
                        .fontColor('#667085')
                        .margin({ top: 6 })
                        .maxLines(2)
                    }
                    .layoutWeight(1)
                    Row() {
                      Button(INDEX_COPY.restore)
                        .height(34)
                        .backgroundColor('#EEF7F2')
                        .fontColor('#1A7F37')
                        .onClick(() => {
                          this.restoreDocument(item.id);
                        })
                      Button(INDEX_COPY.deleteForever)
                        .height(34)
                        .margin({ left: 8 })
                        .backgroundColor('#FDECEC')
                        .fontColor('#B42318')
                        .onClick(() => {
                          this.deleteTargetId = item.id;
                          this.deleteDocument('purge');
                        })
                    }
                  }
                  .width('100%')
                  .padding(18)
                  .margin({ top: 16 })
                  .backgroundColor('#FFFFFF')
                  .borderRadius(20)
                }, (item: TrashItemVM): string => item.id)
              }
            }
            .layoutWeight(1)
          } else {
            Scroll() {
              Column() {
                ForEach(this.currentDocuments(), (doc: DocumentRecord) => {
                  Column() {
                    Row({ space: 16 }) {
                      PreviewThumbnail({
                        previewSnapshot: doc.previewSnapshot,
                        fallbackSummary: doc.previewSummary,
                        thumbnailWidth: 124,
                        thumbnailHeight: 168
                      })
                      Column() {
                        Text(doc.title)
                          .fontSize(20)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#162033')
                        Row({ space: 8 }) {
                          ForEach(this.documentBadges(doc), (badge: DocumentBadgeVM) => {
                            Text(badge.label)
                              .fontSize(11)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(badge.fontColor)
                              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                              .backgroundColor(badge.backgroundColor)
                              .borderRadius(999)
                          }, (badge: DocumentBadgeVM): string => badge.key)
                        }
                        .margin({ top: 10 })
                        Text(doc.previewSummary)
                          .fontSize(13)
                          .fontColor('#475467')
                          .margin({ top: 12 })
                          .maxLines(4)
                        Text(`${RENDER_BACKEND_LABELS[doc.renderBackend]} · ${INDEX_COPY.updatedAtPrefix} ${formatTime(doc.updatedAt)}`)
                          .fontSize(12)
                          .fontColor('#98A2B3')
                          .margin({ top: 10 })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    Row() {
                      Button(INDEX_COPY.open)
                        .height(34)
                        .backgroundColor('#162033')
                        .fontColor('#FFFFFF')
                        .onClick(() => {
                          this.openDocument(doc);
                        })
                      Button(doc.isFavorite ? INDEX_COPY.unfavorite : INDEX_COPY.favorites)
                        .height(34)
                        .margin({ left: 8 })
                        .backgroundColor('#F2F5FA')
                        .fontColor('#162033')
                        .onClick(() => {
                          this.toggleFavorite(doc);
                        })
                      Button(INDEX_COPY.details)
                        .height(34)
                        .margin({ left: 8 })
                        .backgroundColor('#F2F5FA')
                        .fontColor('#162033')
                        .onClick(() => {
                          this.pickDocument(doc);
                        })
                      Button(INDEX_COPY.delete)
                        .height(34)
                        .margin({ left: 8 })
                        .backgroundColor('#FDECEC')
                        .fontColor('#B42318')
                        .onClick(() => {
                          this.requestDelete(doc.id);
                        })
                    }
                    .margin({ top: 14 })
                  }
                  .width('100%')
                  .padding(18)
                  .margin({ top: 18 })
                  .backgroundColor(this.selectedDocumentId === doc.id ? '#EEF4FF' : '#FFFFFF')
                  .borderRadius(22)
                  .onClick(() => {
                    this.pickDocument(doc);
                  })
                }, (doc: DocumentRecord) => doc.id)
              }
            }
            .layoutWeight(1)
          }
        }
        .layoutWeight(1)
        .height('100%')
        .padding(24)
        .backgroundColor('#F7F9FC')

        Column() {
          if (this.showCreatePanel) {
            Text(INDEX_COPY.createPanelTitle)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#162033')
            TextInput({ text: this.createTitle, placeholder: INDEX_COPY.documentTitlePlaceholder })
              .height(42)
              .margin({ top: 16 })
              .backgroundColor('#FFFFFF')
              .onChange((value: string) => {
                this.createTitle = value;
              })
            Row() {
              ForEach([DocumentType.BLANK, DocumentType.PDF, DocumentType.HYBRID], (type: DocumentType) => {
                Button(DOCUMENT_TYPE_LABELS[type])
                  .height(34)
                  .margin({ top: 16, right: 8 })
                  .backgroundColor(this.createType === type ? '#162033' : '#FFFFFF')
                  .fontColor(this.createType === type ? '#FFFFFF' : '#162033')
                  .onClick(() => {
                    this.createType = type;
                  })
              }, (type: DocumentType) => type)
            }
            Row() {
              ForEach([DocumentMode.PAGED, DocumentMode.INFINITE], (mode: DocumentMode) => {
                Button(DOCUMENT_MODE_LABELS[mode])
                  .height(34)
                  .margin({ top: 12, right: 8 })
                  .backgroundColor(this.createMode === mode ? '#162033' : '#FFFFFF')
                  .fontColor(this.createMode === mode ? '#FFFFFF' : '#162033')
                  .onClick(() => {
                    this.createMode = mode;
                  })
              }, (mode: DocumentMode) => mode)
            }
            Row() {
              ForEach([RenderBackend.OPEN_GLES, RenderBackend.SKIA], (backend: RenderBackend) => {
                Button(RENDER_BACKEND_LABELS[backend])
                  .height(34)
                  .margin({ top: 12, right: 8 })
                  .backgroundColor(this.createBackend === backend ? '#162033' : '#FFFFFF')
                  .fontColor(this.createBackend === backend ? '#FFFFFF' : '#162033')
                  .onClick(() => {
                    this.createBackend = backend;
                  })
              }, (backend: RenderBackend) => backend)
            }
            Text(INDEX_COPY.folders)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 18, bottom: 8 })
            ForEach(this.homeData.folders, (folder: FolderRecord) => {
              Button(folder.title)
                .width('100%')
                .height(34)
                .margin({ top: 8 })
                .backgroundColor(this.createFolderId === folder.id ? folder.color : '#FFFFFF')
                .fontColor(this.createFolderId === folder.id ? '#FFFFFF' : '#162033')
                .onClick(() => {
                  this.createFolderId = folder.id;
                })
            }, (folder: FolderRecord): string => folder.id)
            Button(INDEX_COPY.create)
              .width('100%')
              .height(40)
              .margin({ top: 18 })
              .backgroundColor('#162033')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.createDocument();
              })
          } else if (this.selectedDocument()) {
            Text(INDEX_COPY.detailsPanelTitle)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#162033')
            TextInput({ text: this.renameDraft, placeholder: INDEX_COPY.documentTitlePlaceholder })
              .height(42)
              .margin({ top: 16 })
              .backgroundColor('#FFFFFF')
              .onChange((value: string) => {
                this.renameDraft = value;
              })
            Button(INDEX_COPY.saveTitle)
              .width('100%')
              .height(38)
              .margin({ top: 12 })
              .backgroundColor('#F2F5FA')
              .fontColor('#162033')
              .onClick(() => {
                this.saveRename();
              })
            Text(INDEX_COPY.moveToFolder)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 18, bottom: 8 })
            ForEach(this.homeData.folders, (folder: FolderRecord) => {
              Button(folder.title)
                .width('100%')
                .height(34)
                .margin({ top: 8 })
                .backgroundColor(this.selectedDocument()?.folderId === folder.id ? folder.color : '#FFFFFF')
                .fontColor(this.selectedDocument()?.folderId === folder.id ? '#FFFFFF' : '#162033')
                .onClick(() => {
                  this.moveSelected(folder.id);
                })
            }, (folder: FolderRecord): string => folder.id)
            Text(INDEX_COPY.tags)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 18, bottom: 8 })
            ForEach(this.homeData.tags, (tag: TagRecord) => {
              Button(tag.title)
                .width('100%')
                .height(34)
                .margin({ top: 8 })
                .backgroundColor(this.selectedDocument()?.tags.some((item: TagRecord) => item.id === tag.id) ? tag.color : '#FFFFFF')
                .fontColor(this.selectedDocument()?.tags.some((item: TagRecord) => item.id === tag.id) ? '#FFFFFF' : '#162033')
                .onClick(() => {
                  this.toggleTag(tag.id);
                })
            }, (tag: TagRecord): string => tag.id)
          } else {
            Text(INDEX_COPY.libraryHomeTitle)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#162033')
            Text(INDEX_COPY.libraryHomeDescription)
              .fontSize(13)
              .fontColor('#667085')
              .margin({ top: 12 })
          }
        }
        .width(320)
        .height('100%')
        .padding(20)
        .backgroundColor('#F4F7FB')
      }
      .width('100%')
      .height('100%')

      if (this.showDeletePanel) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
          Column() {
            Text(INDEX_COPY.deletePanelTitle)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#162033')
            Button(INDEX_COPY.moveToTrash)
              .width('100%')
              .height(40)
              .margin({ top: 18 })
              .backgroundColor('#162033')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.deleteDocument('trash');
              })
            Button(INDEX_COPY.deleteForever)
              .width('100%')
              .height(40)
              .margin({ top: 10 })
              .backgroundColor('#FDECEC')
              .fontColor('#B42318')
              .onClick(() => {
                this.deleteDocument('purge');
              })
            Button(INDEX_COPY.cancel)
              .width('100%')
              .height(40)
              .margin({ top: 10 })
              .backgroundColor('#F2F5FA')
              .fontColor('#162033')
              .onClick(() => {
                this.showDeletePanel = false;
                this.deleteTargetId = '';
              })
          }
          .width(340)
          .padding(24)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
        }
        .width('100%')
        .height('100%')
      }
    }
    .backgroundColor('#EEF2F8')
  }
}
