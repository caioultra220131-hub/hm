import { IconKey } from './AppIconKeys';

export type TemplatePrimitiveType =
  'horizontal_lines' |
  'grid' |
  'dots' |
  'divider' |
  'header' |
  'sidebar' |
  'label';

export interface TemplateBounds {
  x: number;
  y: number;
  width: number;
  height: number;
  unit: 'ratio';
}

export interface TemplatePrimitive {
  id: string;
  type: TemplatePrimitiveType;
  bounds: TemplateBounds;
  strokeColor?: string;
  fillColor?: string;
  strokeWidth?: number;
  opacity?: number;
  spacingX?: number;
  spacingY?: number;
  dotRadius?: number;
  text?: string;
  metadata?: Record<string, string | number | boolean>;
}

export interface BlankPageTemplateDefinition {
  id: string;
  title: string;
  description: string;
  iconKey: IconKey;
  recommendedPageSizeId: string;
  recommendedPaperBackgroundId: string;
  layout: TemplatePrimitive[];
}

export interface PageSizeDefinition {
  id: string;
  title: string;
  description: string;
  width: number;
  height: number;
  unit: 'mm';
  iconKey: IconKey;
}

export interface PaperBackgroundDefinition {
  id: string;
  title: string;
  description: string;
  fillColor: string;
  accentColor: string;
  surfaceStyle: 'flat' | 'soft-tint';
  iconKey: IconKey;
}

export interface DocumentPageMetadata {
  pageTemplateId?: string;
  pageSizeId?: string;
  paperBackgroundId?: string;
}

export interface ResolvedDocumentPageMetadata {
  pageTemplateId: string;
  pageSizeId: string;
  paperBackgroundId: string;
}

export const PAGE_SIZE_DEFINITIONS: PageSizeDefinition[] = [
  {
    id: 'letter_optimized',
    title: 'Letter optimized',
    description: 'US letter tuned for the current note layout defaults.',
    width: 216,
    height: 279,
    unit: 'mm',
    iconKey: IconKey.PAGE_SIZE_LETTER_OPTIMIZED
  },
  {
    id: 'a4',
    title: 'A4',
    description: 'International A4 page size.',
    width: 210,
    height: 297,
    unit: 'mm',
    iconKey: IconKey.PAGE_SIZE_A4
  },
  {
    id: 'a5',
    title: 'A5',
    description: 'Compact A5 notebook page size.',
    width: 148,
    height: 210,
    unit: 'mm',
    iconKey: IconKey.PAGE_SIZE_A5
  }
];

export const PAPER_BACKGROUND_DEFINITIONS: PaperBackgroundDefinition[] = [
  {
    id: 'plain_white',
    title: 'Plain white',
    description: 'Neutral paper tone for general note-taking.',
    fillColor: '#FFFFFF',
    accentColor: '#D0D5DD',
    surfaceStyle: 'flat',
    iconKey: IconKey.BACKGROUND_PLAIN_WHITE
  },
  {
    id: 'warm_cream',
    title: 'Warm cream',
    description: 'Warm paper tone for planner and journal templates.',
    fillColor: '#FAF3E0',
    accentColor: '#E1C89B',
    surfaceStyle: 'soft-tint',
    iconKey: IconKey.BACKGROUND_WARM_CREAM
  },
  {
    id: 'soft_gray',
    title: 'Soft gray',
    description: 'Muted page tone with lower contrast.',
    fillColor: '#F5F6F8',
    accentColor: '#C7CDD8',
    surfaceStyle: 'soft-tint',
    iconKey: IconKey.BACKGROUND_SOFT_GRAY
  }
];

export const DEFAULT_DOCUMENT_PAGE_METADATA: ResolvedDocumentPageMetadata = {
  pageTemplateId: 'blank',
  pageSizeId: 'letter_optimized',
  paperBackgroundId: 'plain_white'
};

export const BLANK_PAGE_TEMPLATES: BlankPageTemplateDefinition[] = [
  {
    id: 'blank',
    title: 'Blank',
    description: 'An empty page with no guide marks.',
    iconKey: IconKey.TEMPLATE_BLANK,
    recommendedPageSizeId: 'letter_optimized',
    recommendedPaperBackgroundId: 'plain_white',
    layout: [
      {
        id: 'blank-safe-area',
        type: 'header',
        bounds: { x: 0.04, y: 0.03, width: 0.92, height: 0.94, unit: 'ratio' },
        strokeColor: '#E5E7EB',
        strokeWidth: 0.5,
        opacity: 0.2
      }
    ]
  },
  {
    id: 'lined',
    title: 'Lined',
    description: 'A ruled notebook page with horizontal guides.',
    iconKey: IconKey.TEMPLATE_LINED,
    recommendedPageSizeId: 'letter_optimized',
    recommendedPaperBackgroundId: 'plain_white',
    layout: [
      {
        id: 'lined-rules',
        type: 'horizontal_lines',
        bounds: { x: 0.08, y: 0.10, width: 0.84, height: 0.82, unit: 'ratio' },
        strokeColor: '#A7C0E8',
        strokeWidth: 1,
        spacingY: 0.05,
        opacity: 0.95
      },
      {
        id: 'lined-margin',
        type: 'divider',
        bounds: { x: 0.16, y: 0.08, width: 0.002, height: 0.84, unit: 'ratio' },
        strokeColor: '#F2A9B7',
        strokeWidth: 1,
        opacity: 0.9
      }
    ]
  },
  {
    id: 'grid',
    title: 'Grid',
    description: 'A square grid page for diagrams and calculations.',
    iconKey: IconKey.TEMPLATE_GRID,
    recommendedPageSizeId: 'letter_optimized',
    recommendedPaperBackgroundId: 'plain_white',
    layout: [
      {
        id: 'grid-mesh',
        type: 'grid',
        bounds: { x: 0.08, y: 0.08, width: 0.84, height: 0.84, unit: 'ratio' },
        strokeColor: '#A7B9E2',
        strokeWidth: 1,
        spacingX: 0.05,
        spacingY: 0.05,
        opacity: 0.95
      }
    ]
  },
  {
    id: 'dotted',
    title: 'Dotted',
    description: 'A dot matrix page for light structure and sketching.',
    iconKey: IconKey.TEMPLATE_DOTTED,
    recommendedPageSizeId: 'letter_optimized',
    recommendedPaperBackgroundId: 'plain_white',
    layout: [
      {
        id: 'dot-grid',
        type: 'dots',
        bounds: { x: 0.08, y: 0.08, width: 0.84, height: 0.84, unit: 'ratio' },
        fillColor: '#90A8D3',
        spacingX: 0.05,
        spacingY: 0.05,
        dotRadius: 1.5,
        opacity: 0.9
      }
    ]
  },
  {
    id: 'cornell',
    title: 'Cornell',
    description: 'A Cornell note layout with cue, note, and summary zones.',
    iconKey: IconKey.TEMPLATE_CORNELL,
    recommendedPageSizeId: 'letter_optimized',
    recommendedPaperBackgroundId: 'plain_white',
    layout: [
      {
        id: 'cornell-header',
        type: 'header',
        bounds: { x: 0.06, y: 0.05, width: 0.88, height: 0.08, unit: 'ratio' },
        strokeColor: '#C8D2E3',
        strokeWidth: 1,
        opacity: 0.75
      },
      {
        id: 'cornell-cue-divider',
        type: 'divider',
        bounds: { x: 0.30, y: 0.15, width: 0.002, height: 0.60, unit: 'ratio' },
        strokeColor: '#BAC4D8',
        strokeWidth: 1,
        opacity: 0.95
      },
      {
        id: 'cornell-summary-divider',
        type: 'divider',
        bounds: { x: 0.06, y: 0.76, width: 0.88, height: 0.002, unit: 'ratio' },
        strokeColor: '#BAC4D8',
        strokeWidth: 1,
        opacity: 0.95
      },
      {
        id: 'cornell-notes-rules',
        type: 'horizontal_lines',
        bounds: { x: 0.32, y: 0.17, width: 0.60, height: 0.56, unit: 'ratio' },
        strokeColor: '#D4DCE9',
        strokeWidth: 1,
        spacingY: 0.06,
        opacity: 0.85
      },
      {
        id: 'cornell-cue-rules',
        type: 'horizontal_lines',
        bounds: { x: 0.08, y: 0.17, width: 0.18, height: 0.56, unit: 'ratio' },
        strokeColor: '#D4DCE9',
        strokeWidth: 1,
        spacingY: 0.10,
        opacity: 0.8
      }
    ]
  },
  {
    id: 'weekly_planner',
    title: 'Weekly planner',
    description: 'A seven-column planner with a notes zone.',
    iconKey: IconKey.TEMPLATE_WEEKLY_PLANNER,
    recommendedPageSizeId: 'letter_optimized',
    recommendedPaperBackgroundId: 'warm_cream',
    layout: [
      {
        id: 'planner-header',
        type: 'header',
        bounds: { x: 0.05, y: 0.04, width: 0.90, height: 0.08, unit: 'ratio' },
        strokeColor: '#D8C8A3',
        strokeWidth: 1,
        opacity: 0.8
      },
      {
        id: 'planner-week-grid',
        type: 'grid',
        bounds: { x: 0.05, y: 0.14, width: 0.90, height: 0.56, unit: 'ratio' },
        strokeColor: '#D8C8A3',
        strokeWidth: 1,
        spacingX: 0.128,
        spacingY: 0.12,
        opacity: 0.9
      },
      {
        id: 'planner-notes-divider',
        type: 'divider',
        bounds: { x: 0.05, y: 0.73, width: 0.90, height: 0.002, unit: 'ratio' },
        strokeColor: '#D8C8A3',
        strokeWidth: 1,
        opacity: 0.9
      },
      {
        id: 'planner-notes-rules',
        type: 'horizontal_lines',
        bounds: { x: 0.07, y: 0.77, width: 0.86, height: 0.16, unit: 'ratio' },
        strokeColor: '#E5D7B7',
        strokeWidth: 1,
        spacingY: 0.045,
        opacity: 0.85
      }
    ]
  }
];

function templateExists(templateId: string): boolean {
  return BLANK_PAGE_TEMPLATES.some((template) => template.id === templateId);
}

function pageSizeExists(pageSizeId: string): boolean {
  return PAGE_SIZE_DEFINITIONS.some((pageSize) => pageSize.id === pageSizeId);
}

function paperBackgroundExists(backgroundId: string): boolean {
  return PAPER_BACKGROUND_DEFINITIONS.some((background) => background.id === backgroundId);
}

export function resolveDocumentPageMetadata(
  metadata: DocumentPageMetadata | undefined,
  fallback: ResolvedDocumentPageMetadata = DEFAULT_DOCUMENT_PAGE_METADATA
): ResolvedDocumentPageMetadata {
  const pageTemplateId: string = metadata?.pageTemplateId && templateExists(metadata.pageTemplateId)
    ? metadata.pageTemplateId
    : fallback.pageTemplateId;
  const pageSizeId: string = metadata?.pageSizeId && pageSizeExists(metadata.pageSizeId)
    ? metadata.pageSizeId
    : fallback.pageSizeId;
  const paperBackgroundId: string = metadata?.paperBackgroundId && paperBackgroundExists(metadata.paperBackgroundId)
    ? metadata.paperBackgroundId
    : fallback.paperBackgroundId;

  return {
    pageTemplateId,
    pageSizeId,
    paperBackgroundId
  };
}

export function getBlankPageTemplateById(templateId: string): BlankPageTemplateDefinition | undefined {
  return BLANK_PAGE_TEMPLATES.find((template) => template.id === templateId);
}

export function getPageSizeById(pageSizeId: string): PageSizeDefinition | undefined {
  return PAGE_SIZE_DEFINITIONS.find((pageSize) => pageSize.id === pageSizeId);
}

export function getPaperBackgroundById(backgroundId: string): PaperBackgroundDefinition | undefined {
  return PAPER_BACKGROUND_DEFINITIONS.find((background) => background.id === backgroundId);
}
