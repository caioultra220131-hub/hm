export enum IconKey {
  SETTINGS_BRUSH = 'settings.brush',
  SETTINGS_BRUSH_DEFAULT_TOOL = 'settings.brush.defaultTool',
  SETTINGS_BRUSH_DEFAULT_COLOR = 'settings.brush.defaultColor',
  SETTINGS_BRUSH_RECENT_COLORS = 'settings.brush.recentColors',
  SETTINGS_BRUSH_LINE_WIDTH = 'settings.brush.lineWidth',
  SETTINGS_BRUSH_PRESSURE = 'settings.brush.pressure',
  SETTINGS_BRUSH_PRESSURE_CURVE = 'settings.brush.pressureCurve',
  SETTINGS_EDITOR = 'settings.editor',
  SETTINGS_EDITOR_PREDICTION_TAIL = 'settings.editor.predictionTail',
  SETTINGS_EDITOR_SHAPE_CORRECTION = 'settings.editor.shapeCorrection',
  SETTINGS_EDITOR_PALM_REJECTION = 'settings.editor.palmRejection',
  SETTINGS_EDITOR_DOCUMENT_MODE = 'settings.editor.documentMode',
  SETTINGS_EDITOR_RENDER_BACKEND = 'settings.editor.renderBackend',
  SETTINGS_DOCUMENT = 'settings.document',
  SETTINGS_DOCUMENT_TEMPLATE = 'settings.document.template',
  SETTINGS_DOCUMENT_PAGE_SIZE = 'settings.document.pageSize',
  SETTINGS_DOCUMENT_BACKGROUND = 'settings.document.background',
  SETTINGS_APPLICATION = 'settings.application',
  SETTINGS_APPLICATION_HOME_SORT = 'settings.application.homeSort',
  SETTINGS_APPLICATION_RECENT_DOCUMENTS = 'settings.application.recentDocuments',
  SETTINGS_APPLICATION_TRASH_RETENTION = 'settings.application.trashRetention',
  TEMPLATE_BLANK = 'template.blank',
  TEMPLATE_LINED = 'template.lined',
  TEMPLATE_GRID = 'template.grid',
  TEMPLATE_DOTTED = 'template.dotted',
  TEMPLATE_CORNELL = 'template.cornell',
  TEMPLATE_WEEKLY_PLANNER = 'template.weeklyPlanner',
  PAGE_SIZE_LETTER_OPTIMIZED = 'pageSize.letterOptimized',
  PAGE_SIZE_A4 = 'pageSize.a4',
  PAGE_SIZE_A5 = 'pageSize.a5',
  BACKGROUND_PLAIN_WHITE = 'background.plainWhite',
  BACKGROUND_WARM_CREAM = 'background.warmCream',
  BACKGROUND_SOFT_GRAY = 'background.softGray'
}

export interface IconSemanticDefinition {
  key: IconKey;
  label: string;
  semantic: string;
}

export const ICON_SEMANTICS: Record<string, IconSemanticDefinition> = {
  [IconKey.SETTINGS_BRUSH]: {
    key: IconKey.SETTINGS_BRUSH,
    label: 'Brush settings',
    semantic: 'Controls the default brush behavior and ink feel.'
  },
  [IconKey.SETTINGS_BRUSH_DEFAULT_TOOL]: {
    key: IconKey.SETTINGS_BRUSH_DEFAULT_TOOL,
    label: 'Default tool',
    semantic: 'Selects the tool that should be active when a document opens.'
  },
  [IconKey.SETTINGS_BRUSH_DEFAULT_COLOR]: {
    key: IconKey.SETTINGS_BRUSH_DEFAULT_COLOR,
    label: 'Default color',
    semantic: 'Sets the default brush color for new sessions.'
  },
  [IconKey.SETTINGS_BRUSH_RECENT_COLORS]: {
    key: IconKey.SETTINGS_BRUSH_RECENT_COLORS,
    label: 'Recent colors',
    semantic: 'Tracks the short list of recently used ink colors.'
  },
  [IconKey.SETTINGS_BRUSH_LINE_WIDTH]: {
    key: IconKey.SETTINGS_BRUSH_LINE_WIDTH,
    label: 'Line width presets',
    semantic: 'Provides stable preset widths for the brush family.'
  },
  [IconKey.SETTINGS_BRUSH_PRESSURE]: {
    key: IconKey.SETTINGS_BRUSH_PRESSURE,
    label: 'Pressure switch',
    semantic: 'Toggles stylus pressure response for supported brush tools.'
  },
  [IconKey.SETTINGS_BRUSH_PRESSURE_CURVE]: {
    key: IconKey.SETTINGS_BRUSH_PRESSURE_CURVE,
    label: 'Pressure curve',
    semantic: 'Describes how stylus pressure maps to stroke width.'
  },
  [IconKey.SETTINGS_EDITOR]: {
    key: IconKey.SETTINGS_EDITOR,
    label: 'Editor settings',
    semantic: 'Controls editor defaults and input correction switches.'
  },
  [IconKey.SETTINGS_EDITOR_PREDICTION_TAIL]: {
    key: IconKey.SETTINGS_EDITOR_PREDICTION_TAIL,
    label: 'Prediction tail',
    semantic: 'Controls whether the editor shows predicted tail samples.'
  },
  [IconKey.SETTINGS_EDITOR_SHAPE_CORRECTION]: {
    key: IconKey.SETTINGS_EDITOR_SHAPE_CORRECTION,
    label: 'Shape correction',
    semantic: 'Controls automatic shape correction for committed strokes.'
  },
  [IconKey.SETTINGS_EDITOR_PALM_REJECTION]: {
    key: IconKey.SETTINGS_EDITOR_PALM_REJECTION,
    label: 'Palm rejection',
    semantic: 'Controls accidental touch filtering while writing.'
  },
  [IconKey.SETTINGS_EDITOR_DOCUMENT_MODE]: {
    key: IconKey.SETTINGS_EDITOR_DOCUMENT_MODE,
    label: 'Default document mode',
    semantic: 'Selects the default document canvas mode.'
  },
  [IconKey.SETTINGS_EDITOR_RENDER_BACKEND]: {
    key: IconKey.SETTINGS_EDITOR_RENDER_BACKEND,
    label: 'Default render backend',
    semantic: 'Selects the default rendering backend for new documents.'
  },
  [IconKey.SETTINGS_DOCUMENT]: {
    key: IconKey.SETTINGS_DOCUMENT,
    label: 'Document settings',
    semantic: 'Controls defaults for new blank-page documents.'
  },
  [IconKey.SETTINGS_DOCUMENT_TEMPLATE]: {
    key: IconKey.SETTINGS_DOCUMENT_TEMPLATE,
    label: 'Default template',
    semantic: 'Selects the default blank page template for new documents.'
  },
  [IconKey.SETTINGS_DOCUMENT_PAGE_SIZE]: {
    key: IconKey.SETTINGS_DOCUMENT_PAGE_SIZE,
    label: 'Page size',
    semantic: 'Selects the default page size for paged documents.'
  },
  [IconKey.SETTINGS_DOCUMENT_BACKGROUND]: {
    key: IconKey.SETTINGS_DOCUMENT_BACKGROUND,
    label: 'Paper background',
    semantic: 'Selects the default paper background style.'
  },
  [IconKey.SETTINGS_APPLICATION]: {
    key: IconKey.SETTINGS_APPLICATION,
    label: 'Application settings',
    semantic: 'Controls library-level display and retention defaults.'
  },
  [IconKey.SETTINGS_APPLICATION_HOME_SORT]: {
    key: IconKey.SETTINGS_APPLICATION_HOME_SORT,
    label: 'Home sorting',
    semantic: 'Controls how documents are sorted on the home surface.'
  },
  [IconKey.SETTINGS_APPLICATION_RECENT_DOCUMENTS]: {
    key: IconKey.SETTINGS_APPLICATION_RECENT_DOCUMENTS,
    label: 'Recent documents',
    semantic: 'Controls whether recent documents are shown by default.'
  },
  [IconKey.SETTINGS_APPLICATION_TRASH_RETENTION]: {
    key: IconKey.SETTINGS_APPLICATION_TRASH_RETENTION,
    label: 'Trash retention',
    semantic: 'Controls how long deleted items should remain in the trash.'
  },
  [IconKey.TEMPLATE_BLANK]: {
    key: IconKey.TEMPLATE_BLANK,
    label: 'Blank template',
    semantic: 'Represents a plain empty sheet template.'
  },
  [IconKey.TEMPLATE_LINED]: {
    key: IconKey.TEMPLATE_LINED,
    label: 'Lined template',
    semantic: 'Represents a standard horizontal ruled page template.'
  },
  [IconKey.TEMPLATE_GRID]: {
    key: IconKey.TEMPLATE_GRID,
    label: 'Grid template',
    semantic: 'Represents a square grid page template.'
  },
  [IconKey.TEMPLATE_DOTTED]: {
    key: IconKey.TEMPLATE_DOTTED,
    label: 'Dotted template',
    semantic: 'Represents a dot matrix note-taking template.'
  },
  [IconKey.TEMPLATE_CORNELL]: {
    key: IconKey.TEMPLATE_CORNELL,
    label: 'Cornell template',
    semantic: 'Represents a Cornell note-taking page layout.'
  },
  [IconKey.TEMPLATE_WEEKLY_PLANNER]: {
    key: IconKey.TEMPLATE_WEEKLY_PLANNER,
    label: 'Weekly planner template',
    semantic: 'Represents a weekly planning page layout.'
  },
  [IconKey.PAGE_SIZE_LETTER_OPTIMIZED]: {
    key: IconKey.PAGE_SIZE_LETTER_OPTIMIZED,
    label: 'Letter optimized',
    semantic: 'Represents the optimized US letter page size.'
  },
  [IconKey.PAGE_SIZE_A4]: {
    key: IconKey.PAGE_SIZE_A4,
    label: 'A4',
    semantic: 'Represents the A4 page size.'
  },
  [IconKey.PAGE_SIZE_A5]: {
    key: IconKey.PAGE_SIZE_A5,
    label: 'A5',
    semantic: 'Represents the A5 page size.'
  },
  [IconKey.BACKGROUND_PLAIN_WHITE]: {
    key: IconKey.BACKGROUND_PLAIN_WHITE,
    label: 'Plain white',
    semantic: 'Represents a neutral bright paper background.'
  },
  [IconKey.BACKGROUND_WARM_CREAM]: {
    key: IconKey.BACKGROUND_WARM_CREAM,
    label: 'Warm cream',
    semantic: 'Represents a warm paper tone for long reading sessions.'
  },
  [IconKey.BACKGROUND_SOFT_GRAY]: {
    key: IconKey.BACKGROUND_SOFT_GRAY,
    label: 'Soft gray',
    semantic: 'Represents a muted paper background with lower contrast.'
  }
};

export function getIconSemanticDefinition(key: IconKey): IconSemanticDefinition {
  return ICON_SEMANTICS[key];
}
