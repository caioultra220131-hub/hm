import { IconKey } from './AppIconKeys';
import {
  DEFAULT_DOCUMENT_PAGE_METADATA,
  ResolvedDocumentPageMetadata,
  resolveDocumentPageMetadata
} from './BlankPageTemplates';
import { DocumentMode, PALETTE_COLORS, RenderBackend, ToolType } from './NoteModels';

export enum PressureCurvePreset {
  NATURAL = 'natural',
  SOFT = 'soft',
  FIRM = 'firm'
}

export enum HomeSortOrder {
  UPDATED_DESC = 'updated_desc',
  CREATED_DESC = 'created_desc',
  OPENED_DESC = 'opened_desc',
  TITLE_ASC = 'title_asc'
}

export enum TrashRetentionPolicy {
  MANUAL = 'manual',
  DAYS_7 = '7d',
  DAYS_30 = '30d',
  DAYS_90 = '90d'
}

export interface PressureCurvePoint {
  input: number;
  output: number;
}

export interface LineWidthPreset {
  id: string;
  title: string;
  description: string;
  width: number;
}

export interface BrushSettings {
  defaultTool: ToolType;
  defaultColor: string;
  recentColors: string[];
  defaultLineWidthPresetId: string;
  lineWidthPresets: LineWidthPreset[];
  pressureEnabled: boolean;
  pressureCurvePreset: PressureCurvePreset;
  pressureCurvePoints: PressureCurvePoint[];
}

export interface EditorSettings {
  predictionTailEnabled: boolean;
  shapeCorrectionEnabled: boolean;
  palmRejectionEnabled: boolean;
  defaultDocumentMode: DocumentMode;
  defaultRenderBackend: RenderBackend;
}

export interface DocumentSettings {
  defaultTemplateId: string;
  defaultPageSizeId: string;
  paperBackgroundId: string;
}

export interface ApplicationSettings {
  homeSortOrder: HomeSortOrder;
  showRecentDocuments: boolean;
  trashRetentionPolicy: TrashRetentionPolicy;
}

export interface AppSettings {
  brush: BrushSettings;
  editor: EditorSettings;
  document: DocumentSettings;
  application: ApplicationSettings;
}

export interface BrushSettingsInput {
  defaultTool?: ToolType;
  defaultColor?: string;
  recentColors?: string[];
  defaultLineWidthPresetId?: string;
  lineWidthPresets?: LineWidthPreset[];
  pressureEnabled?: boolean;
  pressureCurvePreset?: PressureCurvePreset;
  pressureCurvePoints?: PressureCurvePoint[];
}

export interface EditorSettingsInput {
  predictionTailEnabled?: boolean;
  shapeCorrectionEnabled?: boolean;
  palmRejectionEnabled?: boolean;
  defaultDocumentMode?: DocumentMode;
  defaultRenderBackend?: RenderBackend;
}

export interface DocumentSettingsInput {
  defaultTemplateId?: string;
  defaultPageSizeId?: string;
  paperBackgroundId?: string;
}

export interface ApplicationSettingsInput {
  homeSortOrder?: HomeSortOrder;
  showRecentDocuments?: boolean;
  trashRetentionPolicy?: TrashRetentionPolicy;
}

export interface AppSettingsInput {
  brush?: BrushSettingsInput;
  editor?: EditorSettingsInput;
  document?: DocumentSettingsInput;
  application?: ApplicationSettingsInput;
}

export type SettingsPrimitiveValue = string | number | boolean;

export interface SettingsShellOption {
  value: SettingsPrimitiveValue;
  label: string;
  description: string;
  iconKey?: IconKey;
}

export interface SettingsShellItem {
  key: string;
  title: string;
  description: string;
  iconKey: IconKey;
  controlType: string;
  value: SettingsPrimitiveValue | string[];
  options?: SettingsShellOption[];
}

export interface SettingsShellSection {
  key: string;
  title: string;
  description: string;
  iconKey: IconKey;
  items: SettingsShellItem[];
}

export const BRUSH_RECENT_COLOR_LIMIT: number = 7;

export const DEFAULT_LINE_WIDTH_PRESETS: LineWidthPreset[] = [
  { id: 'small', title: 'Small', description: 'Compact writing width for dense notes.', width: 2.4 },
  { id: 'medium', title: 'Medium', description: 'Balanced default width for everyday writing.', width: 3.2 },
  { id: 'large', title: 'Large', description: 'Thicker width for emphasis and diagrams.', width: 5.6 }
];

export const PRESSURE_CURVE_PRESETS: Record<string, PressureCurvePoint[]> = {
  [PressureCurvePreset.NATURAL]: [
    { input: 0, output: 0.18 },
    { input: 0.35, output: 0.42 },
    { input: 0.7, output: 0.76 },
    { input: 1, output: 1 }
  ],
  [PressureCurvePreset.SOFT]: [
    { input: 0, output: 0.24 },
    { input: 0.25, output: 0.48 },
    { input: 0.6, output: 0.82 },
    { input: 1, output: 1 }
  ],
  [PressureCurvePreset.FIRM]: [
    { input: 0, output: 0.12 },
    { input: 0.45, output: 0.3 },
    { input: 0.8, output: 0.66 },
    { input: 1, output: 1 }
  ]
};

export const HOME_SORT_ORDER_OPTIONS: SettingsShellOption[] = [
  { value: HomeSortOrder.UPDATED_DESC, label: 'Updated desc', description: 'Newest updates first.' },
  { value: HomeSortOrder.CREATED_DESC, label: 'Created desc', description: 'Newest created documents first.' },
  { value: HomeSortOrder.OPENED_DESC, label: 'Opened desc', description: 'Most recently opened documents first.' },
  { value: HomeSortOrder.TITLE_ASC, label: 'Title asc', description: 'Sort documents by title from A to Z.' }
];

export const TRASH_RETENTION_OPTIONS: SettingsShellOption[] = [
  { value: TrashRetentionPolicy.MANUAL, label: 'Manual', description: 'Keep trash items until explicitly removed.' },
  { value: TrashRetentionPolicy.DAYS_7, label: '7 days', description: 'Purge trash items after seven days.' },
  { value: TrashRetentionPolicy.DAYS_30, label: '30 days', description: 'Purge trash items after thirty days.' },
  { value: TrashRetentionPolicy.DAYS_90, label: '90 days', description: 'Purge trash items after ninety days.' }
];

function clonePressureCurvePoints(points: PressureCurvePoint[]): PressureCurvePoint[] {
  const clonedPoints: PressureCurvePoint[] = [];
  for (const point of points) {
    const clonedPoint: PressureCurvePoint = {
      input: point.input,
      output: point.output
    };
    clonedPoints.push(clonedPoint);
  }
  return clonedPoints;
}

function cloneLineWidthPresets(presets: LineWidthPreset[]): LineWidthPreset[] {
  const clonedPresets: LineWidthPreset[] = [];
  for (const preset of presets) {
    const clonedPreset: LineWidthPreset = {
      id: preset.id,
      title: preset.title,
      description: preset.description,
      width: preset.width
    };
    clonedPresets.push(clonedPreset);
  }
  return clonedPresets;
}

function normalizeTool(value: ToolType | undefined): ToolType {
  const supportedTools: ToolType[] = [
    ToolType.PEN,
    ToolType.PENCIL,
    ToolType.ERASER,
    ToolType.HIGHLIGHTER,
    ToolType.LASSO,
    ToolType.HAND,
    ToolType.TEXT
  ];
  return value && supportedTools.includes(value) ? value : ToolType.PEN;
}

function normalizeRenderBackend(value: RenderBackend | undefined): RenderBackend {
  const supportedBackends: RenderBackend[] = [RenderBackend.OPEN_GLES, RenderBackend.SKIA];
  return value && supportedBackends.includes(value) ? value : RenderBackend.OPEN_GLES;
}

function normalizeDocumentMode(value: DocumentMode | undefined): DocumentMode {
  const supportedModes: DocumentMode[] = [DocumentMode.PAGED, DocumentMode.INFINITE];
  return value && supportedModes.includes(value) ? value : DocumentMode.PAGED;
}

function normalizeHomeSortOrder(value: HomeSortOrder | undefined): HomeSortOrder {
  const supportedSortOrders: HomeSortOrder[] = [
    HomeSortOrder.UPDATED_DESC,
    HomeSortOrder.CREATED_DESC,
    HomeSortOrder.OPENED_DESC,
    HomeSortOrder.TITLE_ASC
  ];
  return value && supportedSortOrders.includes(value) ? value : HomeSortOrder.UPDATED_DESC;
}

function normalizeTrashRetentionPolicy(value: TrashRetentionPolicy | undefined): TrashRetentionPolicy {
  const supportedPolicies: TrashRetentionPolicy[] = [
    TrashRetentionPolicy.MANUAL,
    TrashRetentionPolicy.DAYS_7,
    TrashRetentionPolicy.DAYS_30,
    TrashRetentionPolicy.DAYS_90
  ];
  return value && supportedPolicies.includes(value) ? value : TrashRetentionPolicy.MANUAL;
}

function normalizePressureCurvePreset(value: PressureCurvePreset | undefined): PressureCurvePreset {
  const supportedPresets: PressureCurvePreset[] = [
    PressureCurvePreset.NATURAL,
    PressureCurvePreset.SOFT,
    PressureCurvePreset.FIRM
  ];
  return value && supportedPresets.includes(value) ? value : PressureCurvePreset.NATURAL;
}

function normalizeRecentColors(colors: string[] | undefined): string[] {
  const normalized: string[] = [];
  const sourceColors: string[] = Array.isArray(colors) ? colors : PALETTE_COLORS.slice(0, BRUSH_RECENT_COLOR_LIMIT);
  for (const color of sourceColors) {
    if (typeof color !== 'string' || color.length === 0 || normalized.includes(color)) {
      continue;
    }
    normalized.push(color);
    if (normalized.length >= BRUSH_RECENT_COLOR_LIMIT) {
      break;
    }
  }
  return normalized.length > 0 ? normalized : PALETTE_COLORS.slice(0, BRUSH_RECENT_COLOR_LIMIT);
}

function normalizeLineWidthPresets(presets: LineWidthPreset[] | undefined): LineWidthPreset[] {
  if (!Array.isArray(presets) || presets.length === 0) {
    return cloneLineWidthPresets(DEFAULT_LINE_WIDTH_PRESETS);
  }
  const normalized: LineWidthPreset[] = [];
  for (const preset of presets) {
    if (
      typeof preset?.id !== 'string' ||
      preset.id.length === 0 ||
      typeof preset?.title !== 'string' ||
      preset.title.length === 0 ||
      typeof preset?.description !== 'string' ||
      preset.description.length === 0 ||
      typeof preset?.width !== 'number' ||
      !Number.isFinite(preset.width) ||
      preset.width <= 0
    ) {
      continue;
    }
    normalized.push({
      id: preset.id,
      title: preset.title,
      description: preset.description,
      width: preset.width
    });
  }
  if (normalized.length === 0) {
    return cloneLineWidthPresets(DEFAULT_LINE_WIDTH_PRESETS);
  }

  const sortedWidths: number[] = normalized
    .map((preset) => preset.width)
    .sort((left, right) => left - right);
  const middleIndex: number = Math.floor((sortedWidths.length - 1) / 2);
  const defaultSlots: LineWidthPreset[] = cloneLineWidthPresets(DEFAULT_LINE_WIDTH_PRESETS);

  const resolveWidth = (preferredIds: string[], fallbackWidth: number): number => {
    for (const preferredId of preferredIds) {
      const matchedPreset: LineWidthPreset | undefined = normalized.find((preset) => preset.id === preferredId);
      if (matchedPreset) {
        return matchedPreset.width;
      }
    }
    return fallbackWidth;
  };

  const smallWidth: number = resolveWidth(['small', 'fine'], sortedWidths[0] ?? defaultSlots[0].width);
  const mediumWidth: number = resolveWidth(['medium'], sortedWidths[middleIndex] ?? defaultSlots[1].width);
  const largeWidth: number = resolveWidth(['large', 'bold', 'marker'], sortedWidths[sortedWidths.length - 1] ?? defaultSlots[2].width);

  return [
    {
      id: 'small',
      title: defaultSlots[0].title,
      description: defaultSlots[0].description,
      width: smallWidth
    },
    {
      id: 'medium',
      title: defaultSlots[1].title,
      description: defaultSlots[1].description,
      width: mediumWidth
    },
    {
      id: 'large',
      title: defaultSlots[2].title,
      description: defaultSlots[2].description,
      width: largeWidth
    }
  ];
}

function normalizeLineWidthPresetId(
  presetId: string | undefined,
  presets: LineWidthPreset[]
): string {
  if (typeof presetId === 'string' && presets.some((preset) => preset.id === presetId)) {
    return presetId;
  }
  return presets.some((preset) => preset.id === 'medium') ? 'medium' : presets[0].id;
}

function normalizePressureCurvePoints(
  points: PressureCurvePoint[] | undefined,
  preset: PressureCurvePreset
): PressureCurvePoint[] {
  if (!Array.isArray(points) || points.length === 0) {
    return clonePressureCurvePoints(PRESSURE_CURVE_PRESETS[preset]);
  }
  const normalized: PressureCurvePoint[] = [];
  for (const point of points) {
    if (
      typeof point?.input !== 'number' ||
      !Number.isFinite(point.input) ||
      typeof point?.output !== 'number' ||
      !Number.isFinite(point.output)
    ) {
      continue;
    }
    normalized.push({
      input: Math.min(Math.max(point.input, 0), 1),
      output: Math.min(Math.max(point.output, 0), 1)
    });
  }
  return normalized.length > 0 ? normalized : clonePressureCurvePoints(PRESSURE_CURVE_PRESETS[preset]);
}

export function createDefaultAppSettings(): AppSettings {
  return {
    brush: {
      defaultTool: ToolType.PEN,
      defaultColor: PALETTE_COLORS[0],
      recentColors: PALETTE_COLORS.slice(0, BRUSH_RECENT_COLOR_LIMIT),
      defaultLineWidthPresetId: 'medium',
      lineWidthPresets: cloneLineWidthPresets(DEFAULT_LINE_WIDTH_PRESETS),
      pressureEnabled: true,
      pressureCurvePreset: PressureCurvePreset.NATURAL,
      pressureCurvePoints: clonePressureCurvePoints(PRESSURE_CURVE_PRESETS[PressureCurvePreset.NATURAL])
    },
    editor: {
      predictionTailEnabled: true,
      shapeCorrectionEnabled: true,
      palmRejectionEnabled: true,
      defaultDocumentMode: DocumentMode.PAGED,
      defaultRenderBackend: RenderBackend.OPEN_GLES
    },
    document: {
      defaultTemplateId: DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId,
      defaultPageSizeId: DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId,
      paperBackgroundId: DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId
    },
    application: {
      homeSortOrder: HomeSortOrder.UPDATED_DESC,
      showRecentDocuments: true,
      trashRetentionPolicy: TrashRetentionPolicy.MANUAL
    }
  };
}

export function normalizeAppSettings(input: AppSettingsInput | undefined | null): AppSettings {
  const defaults: AppSettings = createDefaultAppSettings();
  const brushInput: BrushSettingsInput | undefined = input?.brush;
  const editorInput: EditorSettingsInput | undefined = input?.editor;
  const applicationInput: ApplicationSettingsInput | undefined = input?.application;
  const resolvedDocumentMetadata: ResolvedDocumentPageMetadata = resolveDocumentPageMetadata(
    {
      pageTemplateId: input?.document?.defaultTemplateId,
      pageSizeId: input?.document?.defaultPageSizeId,
      paperBackgroundId: input?.document?.paperBackgroundId
    },
    {
      pageTemplateId: defaults.document.defaultTemplateId,
      pageSizeId: defaults.document.defaultPageSizeId,
      paperBackgroundId: defaults.document.paperBackgroundId
    }
  );
  const lineWidthPresets: LineWidthPreset[] = normalizeLineWidthPresets(brushInput?.lineWidthPresets);
  const pressureCurvePreset: PressureCurvePreset = normalizePressureCurvePreset(brushInput?.pressureCurvePreset);

  return {
    brush: {
      defaultTool: normalizeTool(brushInput?.defaultTool),
      defaultColor: typeof brushInput?.defaultColor === 'string' && brushInput.defaultColor.length > 0
        ? brushInput.defaultColor
        : defaults.brush.defaultColor,
      recentColors: normalizeRecentColors(brushInput?.recentColors),
      defaultLineWidthPresetId: normalizeLineWidthPresetId(brushInput?.defaultLineWidthPresetId, lineWidthPresets),
      lineWidthPresets,
      pressureEnabled: typeof brushInput?.pressureEnabled === 'boolean'
        ? brushInput.pressureEnabled
        : defaults.brush.pressureEnabled,
      pressureCurvePreset,
      pressureCurvePoints: normalizePressureCurvePoints(brushInput?.pressureCurvePoints, pressureCurvePreset)
    },
    editor: {
      predictionTailEnabled: typeof editorInput?.predictionTailEnabled === 'boolean'
        ? editorInput.predictionTailEnabled
        : defaults.editor.predictionTailEnabled,
      shapeCorrectionEnabled: typeof editorInput?.shapeCorrectionEnabled === 'boolean'
        ? editorInput.shapeCorrectionEnabled
        : defaults.editor.shapeCorrectionEnabled,
      palmRejectionEnabled: typeof editorInput?.palmRejectionEnabled === 'boolean'
        ? editorInput.palmRejectionEnabled
        : defaults.editor.palmRejectionEnabled,
      defaultDocumentMode: normalizeDocumentMode(editorInput?.defaultDocumentMode),
      defaultRenderBackend: normalizeRenderBackend(editorInput?.defaultRenderBackend)
    },
    document: {
      defaultTemplateId: resolvedDocumentMetadata.pageTemplateId,
      defaultPageSizeId: resolvedDocumentMetadata.pageSizeId,
      paperBackgroundId: resolvedDocumentMetadata.paperBackgroundId
    },
    application: {
      homeSortOrder: normalizeHomeSortOrder(applicationInput?.homeSortOrder),
      showRecentDocuments: typeof applicationInput?.showRecentDocuments === 'boolean'
        ? applicationInput.showRecentDocuments
        : defaults.application.showRecentDocuments,
      trashRetentionPolicy: normalizeTrashRetentionPolicy(applicationInput?.trashRetentionPolicy)
    }
  };
}

export function getDocumentPageMetadataFromSettings(settings: AppSettings): ResolvedDocumentPageMetadata {
  return {
    pageTemplateId: settings.document.defaultTemplateId,
    pageSizeId: settings.document.defaultPageSizeId,
    paperBackgroundId: settings.document.paperBackgroundId
  };
}
