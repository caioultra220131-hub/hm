import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { IconKey, IconSemanticDefinition, ICON_SEMANTICS } from '../models/AppIconKeys';
import {
  AppSettings,
  AppSettingsInput,
  ApplicationSettingsInput,
  BrushSettingsInput,
  createDefaultAppSettings,
  DocumentSettingsInput,
  EditorSettingsInput,
  getDocumentPageMetadataFromSettings,
  HOME_SORT_ORDER_OPTIONS,
  LineWidthPreset,
  normalizeAppSettings,
  PressureCurvePreset,
  SettingsShellItem,
  SettingsShellOption,
  SettingsShellSection,
  TRASH_RETENTION_OPTIONS
} from '../models/AppSettingsModels';
import {
  BLANK_PAGE_TEMPLATES,
  BlankPageTemplateDefinition,
  PAGE_SIZE_DEFINITIONS,
  PageSizeDefinition,
  PAPER_BACKGROUND_DEFINITIONS,
  PaperBackgroundDefinition,
  ResolvedDocumentPageMetadata
} from '../models/BlankPageTemplates';
import { DocumentMode, RenderBackend, ToolType } from '../models/NoteModels';

interface StoredSettingsEnvelope {
  schemaVersion?: number;
  settings?: AppSettingsInput;
  brush?: BrushSettingsInput;
  editor?: EditorSettingsInput;
  document?: DocumentSettingsInput;
  application?: ApplicationSettingsInput;
}

export const APP_SETTINGS_SCHEMA_VERSION: number = 1;

class AppSettingsBootstrapError extends Error {
  stage: string;
  op: string;
  path: string;
  settingsRoot: string;
  settingsPath: string;
  filesDir: string;
  filesDirState: string;
  settingsRootState: string;
  code: number;
  detail: string;

  constructor(
    stage: string,
    op: string,
    path: string,
    settingsRoot: string,
    settingsPath: string,
    filesDir: string,
    filesDirState: string,
    settingsRootState: string,
    code: number,
    detail: string
  ) {
    super(detail);
    this.stage = stage;
    this.op = op;
    this.path = path;
    this.settingsRoot = settingsRoot;
    this.settingsPath = settingsPath;
    this.filesDir = filesDir;
    this.filesDirState = filesDirState;
    this.settingsRootState = settingsRootState;
    this.code = code;
    this.detail = detail;
  }
}

export class AppSettingsService {
  private static instance: AppSettingsService | undefined;
  private static initPromise: Promise<AppSettingsService> | undefined;

  private readonly context: common.UIAbilityContext;
  private readonly settingsRoot: string;
  private readonly settingsPath: string;

  private constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.settingsRoot = `${this.context.filesDir}/settings`;
    this.settingsPath = `${this.settingsRoot}/app-settings.json`;
  }

  static async getInstance(context: common.UIAbilityContext): Promise<AppSettingsService> {
    if (AppSettingsService.instance) {
      return AppSettingsService.instance;
    }
    if (!AppSettingsService.initPromise) {
      AppSettingsService.initPromise = (async () => {
        const service: AppSettingsService = new AppSettingsService(context);
        await service.initialize();
        AppSettingsService.instance = service;
        return service;
      })();
    }
    return AppSettingsService.initPromise;
  }

  async getSettings(): Promise<AppSettings> {
    try {
      this.ensureDir(this.settingsRoot);
      if (!this.exists(this.settingsPath)) {
        const defaults: AppSettings = createDefaultAppSettings();
        this.writeEnvelope(defaults);
        return defaults;
      }

      let parsed: StoredSettingsEnvelope | undefined;
      try {
        parsed = JSON.parse(fileIo.readTextSync(this.settingsPath)) as StoredSettingsEnvelope;
      } catch (_) {
        const defaults: AppSettings = createDefaultAppSettings();
        this.writeEnvelope(defaults);
        return defaults;
      }

      const rawInput: AppSettingsInput = parsed.settings ?? {
        brush: parsed.brush,
        editor: parsed.editor,
        document: parsed.document,
        application: parsed.application
      };
      const normalized: AppSettings = normalizeAppSettings(rawInput);
      const shouldPersist: boolean = parsed.schemaVersion !== APP_SETTINGS_SCHEMA_VERSION ||
        JSON.stringify(rawInput) !== JSON.stringify(normalized);
      if (shouldPersist) {
        this.writeEnvelope(normalized);
      }
      return normalized;
    } catch (error) {
      throw this.wrapFileError('AppSettingsService.getSettings', 'bootstrap', this.settingsPath, error as Object);
    }
  }

  async saveSettings(settings: AppSettingsInput | AppSettings): Promise<AppSettings> {
    const normalized: AppSettings = normalizeAppSettings(settings as AppSettingsInput);
    this.writeEnvelope(normalized);
    return normalized;
  }

  async resetSettings(): Promise<AppSettings> {
    const defaults: AppSettings = createDefaultAppSettings();
    this.writeEnvelope(defaults);
    return defaults;
  }

  getTemplateCatalog(): BlankPageTemplateDefinition[] {
    return BLANK_PAGE_TEMPLATES;
  }

  getPageSizes(): PageSizeDefinition[] {
    return PAGE_SIZE_DEFINITIONS;
  }

  getPaperBackgrounds(): PaperBackgroundDefinition[] {
    return PAPER_BACKGROUND_DEFINITIONS;
  }

  getIconSemantics(): Record<string, IconSemanticDefinition> {
    const semantics: Record<string, IconSemanticDefinition> = {};
    Object.keys(ICON_SEMANTICS).forEach((key: string) => {
      const definition: IconSemanticDefinition = ICON_SEMANTICS[key];
      semantics[key] = {
        key: definition.key,
        label: definition.label,
        semantic: definition.semantic
      };
    });
    return semantics;
  }

  async getSettingsShellModel(): Promise<SettingsShellSection[]> {
    const settings: AppSettings = await this.getSettings();
    const documentDefaults: ResolvedDocumentPageMetadata = getDocumentPageMetadataFromSettings(settings);
    const toolOptions: SettingsShellOption[] = [
      { value: ToolType.PEN, label: 'Pen', description: 'Low-latency ink pen.' },
      { value: ToolType.PENCIL, label: 'Pencil', description: 'Textured pencil strokes.' },
      { value: ToolType.ERASER, label: 'Eraser', description: 'Erase committed strokes.' },
      { value: ToolType.HIGHLIGHTER, label: 'Highlighter', description: 'Wide translucent strokes.' },
      { value: ToolType.LASSO, label: 'Lasso', description: 'Select existing strokes.' },
      { value: ToolType.HAND, label: 'Hand', description: 'Navigate and move selection.' },
      { value: ToolType.TEXT, label: 'Text', description: 'Insert or edit text content.' }
    ];
    const modeOptions: SettingsShellOption[] = [
      { value: DocumentMode.PAGED, label: 'Paged', description: 'Structured pages for notebooks and PDFs.' },
      { value: DocumentMode.INFINITE, label: 'Infinite', description: 'Infinite canvas for brainstorming.' }
    ];
    const backendOptions: SettingsShellOption[] = [
      { value: RenderBackend.OPEN_GLES, label: 'OpenGL ES', description: 'Current default renderer.' },
      { value: RenderBackend.SKIA, label: 'Skia', description: 'Alternative renderer for document drawing.' }
    ];
    const templateOptions: SettingsShellOption[] = this.buildTemplateOptions();
    const pageSizeOptions: SettingsShellOption[] = this.buildPageSizeOptions();
    const backgroundOptions: SettingsShellOption[] = this.buildBackgroundOptions();
    const pressurePresetOptions: SettingsShellOption[] = [
      { value: PressureCurvePreset.NATURAL, label: 'Natural', description: 'Balanced width response.' },
      { value: PressureCurvePreset.SOFT, label: 'Soft', description: 'Build width earlier with less force.' },
      { value: PressureCurvePreset.FIRM, label: 'Firm', description: 'Hold a narrower width until heavier force.' }
    ];

    const brushItems: SettingsShellItem[] = [
      {
        key: 'brush.defaultTool',
        title: 'Default tool',
        description: 'Tool that should be active when a writing session starts.',
        iconKey: IconKey.SETTINGS_BRUSH_DEFAULT_TOOL,
        controlType: 'choice',
        value: settings.brush.defaultTool,
        options: toolOptions
      },
      {
        key: 'brush.defaultColor',
        title: 'Default color',
        description: 'Default color used when a new session starts.',
        iconKey: IconKey.SETTINGS_BRUSH_DEFAULT_COLOR,
        controlType: 'palette',
        value: settings.brush.defaultColor,
        options: this.buildRecentColorOptions(settings.brush.recentColors)
      },
      {
        key: 'brush.recentColors',
        title: 'Recent colors',
        description: 'Short list of recently used colors.',
        iconKey: IconKey.SETTINGS_BRUSH_RECENT_COLORS,
        controlType: 'color-history',
        value: settings.brush.recentColors
      },
      {
        key: 'brush.defaultLineWidthPresetId',
        title: 'Default line width',
        description: 'Default line width preset for brush tools.',
        iconKey: IconKey.SETTINGS_BRUSH_LINE_WIDTH,
        controlType: 'choice',
        value: settings.brush.defaultLineWidthPresetId,
        options: this.buildLineWidthOptions(settings.brush.lineWidthPresets)
      },
      {
        key: 'brush.lineWidthPresets',
        title: 'Line width presets',
        description: 'Current stable preset widths.',
        iconKey: IconKey.SETTINGS_BRUSH_LINE_WIDTH,
        controlType: 'preset-list',
        value: settings.brush.lineWidthPresets.map((preset) => `${preset.id}:${preset.width}`)
      },
      {
        key: 'brush.pressureEnabled',
        title: 'Pressure switch',
        description: 'Enable or disable pressure-sensitive width response.',
        iconKey: IconKey.SETTINGS_BRUSH_PRESSURE,
        controlType: 'toggle',
        value: settings.brush.pressureEnabled
      },
      {
        key: 'brush.pressureCurvePreset',
        title: 'Pressure curve preset',
        description: 'Select the preset pressure curve profile.',
        iconKey: IconKey.SETTINGS_BRUSH_PRESSURE_CURVE,
        controlType: 'choice',
        value: settings.brush.pressureCurvePreset,
        options: pressurePresetOptions
      },
      {
        key: 'brush.pressureCurvePoints',
        title: 'Pressure curve points',
        description: 'Normalized pressure curve control points.',
        iconKey: IconKey.SETTINGS_BRUSH_PRESSURE_CURVE,
        controlType: 'curve',
        value: settings.brush.pressureCurvePoints.map((point) => `${point.input}:${point.output}`)
      }
    ];

    const editorItems: SettingsShellItem[] = [
      {
        key: 'editor.predictionTailEnabled',
        title: 'Prediction tail',
        description: 'Show predicted tail samples while inking.',
        iconKey: IconKey.SETTINGS_EDITOR_PREDICTION_TAIL,
        controlType: 'toggle',
        value: settings.editor.predictionTailEnabled
      },
      {
        key: 'editor.shapeCorrectionEnabled',
        title: 'Shape correction',
        description: 'Enable automatic shape correction for strokes.',
        iconKey: IconKey.SETTINGS_EDITOR_SHAPE_CORRECTION,
        controlType: 'toggle',
        value: settings.editor.shapeCorrectionEnabled
      },
      {
        key: 'editor.palmRejectionEnabled',
        title: 'Palm rejection',
        description: 'Enable accidental touch filtering while writing.',
        iconKey: IconKey.SETTINGS_EDITOR_PALM_REJECTION,
        controlType: 'toggle',
        value: settings.editor.palmRejectionEnabled
      },
      {
        key: 'editor.defaultDocumentMode',
        title: 'Default document mode',
        description: 'Default document mode for new note sessions.',
        iconKey: IconKey.SETTINGS_EDITOR_DOCUMENT_MODE,
        controlType: 'choice',
        value: settings.editor.defaultDocumentMode,
        options: modeOptions
      },
      {
        key: 'editor.defaultRenderBackend',
        title: 'Default render backend',
        description: 'Default renderer for new note sessions.',
        iconKey: IconKey.SETTINGS_EDITOR_RENDER_BACKEND,
        controlType: 'choice',
        value: settings.editor.defaultRenderBackend,
        options: backendOptions
      }
    ];

    const documentItems: SettingsShellItem[] = [
      {
        key: 'document.defaultTemplateId',
        title: 'Default template',
        description: 'Template used when a new blank document is created.',
        iconKey: IconKey.SETTINGS_DOCUMENT_TEMPLATE,
        controlType: 'choice',
        value: documentDefaults.pageTemplateId,
        options: templateOptions
      },
      {
        key: 'document.defaultPageSizeId',
        title: 'Default page size',
        description: 'Default page size for paged documents.',
        iconKey: IconKey.SETTINGS_DOCUMENT_PAGE_SIZE,
        controlType: 'choice',
        value: documentDefaults.pageSizeId,
        options: pageSizeOptions
      },
      {
        key: 'document.paperBackgroundId',
        title: 'Paper background',
        description: 'Default paper background style.',
        iconKey: IconKey.SETTINGS_DOCUMENT_BACKGROUND,
        controlType: 'choice',
        value: documentDefaults.paperBackgroundId,
        options: backgroundOptions
      }
    ];

    const applicationItems: SettingsShellItem[] = [
      {
        key: 'application.homeSortOrder',
        title: 'Home sorting',
        description: 'Default sort order for the document home view.',
        iconKey: IconKey.SETTINGS_APPLICATION_HOME_SORT,
        controlType: 'choice',
        value: settings.application.homeSortOrder,
        options: HOME_SORT_ORDER_OPTIONS
      },
      {
        key: 'application.showRecentDocuments',
        title: 'Show recent documents',
        description: 'Whether recent documents should be visible by default.',
        iconKey: IconKey.SETTINGS_APPLICATION_RECENT_DOCUMENTS,
        controlType: 'toggle',
        value: settings.application.showRecentDocuments
      },
      {
        key: 'application.trashRetentionPolicy',
        title: 'Trash retention',
        description: 'How long deleted documents should remain in trash.',
        iconKey: IconKey.SETTINGS_APPLICATION_TRASH_RETENTION,
        controlType: 'choice',
        value: settings.application.trashRetentionPolicy,
        options: TRASH_RETENTION_OPTIONS
      }
    ];

    return [
      {
        key: 'brush',
        title: 'Brush settings',
        description: 'Default brush tool, width, color, and pressure settings.',
        iconKey: IconKey.SETTINGS_BRUSH,
        items: brushItems
      },
      {
        key: 'editor',
        title: 'Editor settings',
        description: 'Prediction, correction, palm rejection, and document defaults.',
        iconKey: IconKey.SETTINGS_EDITOR,
        items: editorItems
      },
      {
        key: 'document',
        title: 'Document settings',
        description: 'Defaults for new blank-page documents.',
        iconKey: IconKey.SETTINGS_DOCUMENT,
        items: documentItems
      },
      {
        key: 'application',
        title: 'Application settings',
        description: 'Home sorting, recent documents, and trash retention.',
        iconKey: IconKey.SETTINGS_APPLICATION,
        items: applicationItems
      }
    ];
  }

  private async initialize(): Promise<void> {
    try {
      this.ensureDir(this.settingsRoot);
    } catch (error) {
      throw this.wrapFileError('AppSettingsService.initialize', 'bootstrap', this.settingsRoot, error as Object);
    }
  }

  private buildOption(
    value: string | number | boolean,
    label: string,
    description: string,
    iconKey?: IconKey
  ): SettingsShellOption {
    const option: SettingsShellOption = {
      value,
      label,
      description
    };
    if (iconKey !== undefined) {
      option.iconKey = iconKey;
    }
    return option;
  }

  private buildTemplateOptions(): SettingsShellOption[] {
    const options: SettingsShellOption[] = [];
    for (const template of this.getTemplateCatalog()) {
      options.push(this.buildOption(template.id, template.title, template.description, template.iconKey));
    }
    return options;
  }

  private buildPageSizeOptions(): SettingsShellOption[] {
    const options: SettingsShellOption[] = [];
    for (const pageSize of this.getPageSizes()) {
      options.push(this.buildOption(pageSize.id, pageSize.title, pageSize.description, pageSize.iconKey));
    }
    return options;
  }

  private buildBackgroundOptions(): SettingsShellOption[] {
    const options: SettingsShellOption[] = [];
    for (const background of this.getPaperBackgrounds()) {
      options.push(this.buildOption(background.id, background.title, background.description, background.iconKey));
    }
    return options;
  }

  private buildRecentColorOptions(colors: string[]): SettingsShellOption[] {
    const options: SettingsShellOption[] = [];
    for (const color of colors) {
      options.push(this.buildOption(color, color, 'Saved color value.'));
    }
    return options;
  }

  private buildLineWidthOptions(
    presets: LineWidthPreset[]
  ): SettingsShellOption[] {
    const options: SettingsShellOption[] = [];
    for (const preset of presets) {
      options.push(this.buildOption(preset.id, preset.title, preset.description));
    }
    return options;
  }

  private writeEnvelope(settings: AppSettings): void {
    try {
      this.ensureDir(this.settingsRoot);
      const envelope: StoredSettingsEnvelope = {
        schemaVersion: APP_SETTINGS_SCHEMA_VERSION,
        settings
      };
      let stream: fileIo.Stream;
      try {
        stream = fileIo.createStreamSync(
          this.settingsPath,
          'w'
        );
      } catch (error) {
        throw this.wrapFileError('AppSettingsService.writeEnvelope.createStreamSync', 'createStreamSync', this.settingsPath, error as Object);
      }
      try {
        stream.writeSync(JSON.stringify(envelope, null, 2));
      } catch (error) {
        throw this.wrapFileError('AppSettingsService.writeEnvelope.writeSync', 'writeSync', this.settingsPath, error as Object);
      } finally {
        stream.closeSync();
      }
    } catch (error) {
      throw this.wrapFileError('AppSettingsService.writeEnvelope', 'write', this.settingsPath, error as Object);
    }
  }

  private ensureDir(path: string): void {
    const normalizedPath: string = this.normalizePath(path);
    if (normalizedPath.length === 0 || this.exists(normalizedPath)) {
      return;
    }
    try {
      fileIo.mkdirSync(normalizedPath, true);
    } catch (error) {
      throw this.wrapFileError('AppSettingsService.ensureDir', 'mkdirSync', normalizedPath, error as Object);
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

  private wrapFileError(stage: string, op: string, path: string, error: Object): Error {
    const errorMap: Record<string, Object> = error as Record<string, Object>;
    if (error instanceof AppSettingsBootstrapError) {
      return error;
    }
    return new AppSettingsBootstrapError(
      stage,
      op,
      path,
      this.settingsRoot,
      this.settingsPath,
      this.context.filesDir,
      this.describePathState(this.context.filesDir),
      this.describePathState(this.settingsRoot),
      this.readErrorCode(error),
      `${error}`
    );
  }

  private readErrorCode(error: Object): number {
    const rawCode: Object | undefined = (error as Record<string, Object>)['code'];
    return typeof rawCode === 'number' ? rawCode : 0;
  }

  private exists(path: string): boolean {
    try {
      fileIo.statSync(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  private describePathState(path: string): string {
    if (!this.exists(path)) {
      return 'missing';
    }
    try {
      return fileIo.statSync(path).isDirectory() ? 'dir' : 'file';
    } catch (error) {
      return `error:${error}`;
    }
  }
}
