import { describe, it, expect } from '@ohos/hypium';
import { ICON_SEMANTICS } from '../main/ets/models/AppIconKeys';
import {
  createDefaultAppSettings,
  normalizeAppSettings,
  TrashRetentionPolicy
} from '../main/ets/models/AppSettingsModels';
import {
  BLANK_PAGE_TEMPLATES,
  DEFAULT_DOCUMENT_PAGE_METADATA,
  PAGE_SIZE_DEFINITIONS,
  PAPER_BACKGROUND_DEFINITIONS,
  resolveDocumentPageMetadata
} from '../main/ets/models/BlankPageTemplates';
import { DocumentMode, PALETTE_COLORS, RenderBackend, ToolType } from '../main/ets/models/NoteModels';

export default function settingsModelsTest() {
  describe('settingsModelsTest', () => {
    it('defaultAppSettingsStayCompatible', 0, () => {
      const settings = createDefaultAppSettings();
      expect(settings.brush.defaultTool).assertEqual(ToolType.PEN);
      expect(settings.brush.defaultColor).assertEqual(PALETTE_COLORS[0]);
      expect(settings.editor.predictionTailEnabled).assertEqual(true);
      expect(settings.editor.shapeCorrectionEnabled).assertEqual(true);
      expect(settings.editor.defaultDocumentMode).assertEqual(DocumentMode.PAGED);
      expect(settings.editor.defaultRenderBackend).assertEqual(RenderBackend.OPEN_GLES);
      expect(settings.application.showRecentDocuments).assertEqual(true);
      expect(settings.application.trashRetentionPolicy).assertEqual(TrashRetentionPolicy.MANUAL);
      expect(settings.document.defaultTemplateId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId);
      expect(settings.document.defaultPageSizeId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId);
      expect(settings.document.paperBackgroundId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId);
    });

    it('normalizeAppSettingsBackfillsMissingFields', 0, () => {
      const settings = normalizeAppSettings({
        brush: {
          defaultColor: '#123456',
          pressureEnabled: false
        },
        editor: {
          predictionTailEnabled: false
        },
        document: {
          defaultTemplateId: 'grid'
        },
        application: {
          trashRetentionPolicy: TrashRetentionPolicy.DAYS_30
        }
      });

      expect(settings.brush.defaultTool).assertEqual(ToolType.PEN);
      expect(settings.brush.defaultColor).assertEqual('#123456');
      expect(settings.brush.pressureEnabled).assertEqual(false);
      expect(settings.editor.predictionTailEnabled).assertEqual(false);
      expect(settings.editor.shapeCorrectionEnabled).assertEqual(true);
      expect(settings.document.defaultTemplateId).assertEqual('grid');
      expect(settings.document.defaultPageSizeId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId);
      expect(settings.document.paperBackgroundId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId);
      expect(settings.application.trashRetentionPolicy).assertEqual(TrashRetentionPolicy.DAYS_30);
      expect(settings.application.showRecentDocuments).assertEqual(true);
    });

    it('templateCatalogAndIconSemanticsAreStable', 0, () => {
      const templateIds: string = BLANK_PAGE_TEMPLATES.map((template) => template.id).join(',');
      expect(BLANK_PAGE_TEMPLATES.length).assertEqual(6);
      expect(templateIds).assertContain('blank');
      expect(templateIds).assertContain('lined');
      expect(templateIds).assertContain('grid');
      expect(templateIds).assertContain('dotted');
      expect(templateIds).assertContain('cornell');
      expect(templateIds).assertContain('weekly_planner');
      expect(PAGE_SIZE_DEFINITIONS.length).assertEqual(3);
      expect(PAPER_BACKGROUND_DEFINITIONS.length).assertEqual(3);
      expect(Boolean(BLANK_PAGE_TEMPLATES.every((template) => template.layout.length > 0))).assertEqual(true);
      expect(Boolean(BLANK_PAGE_TEMPLATES.every((template) => ICON_SEMANTICS[template.iconKey] !== undefined))).assertEqual(true);
    });

    it('documentPageMetadataFallsBackCompatibly', 0, () => {
      const missingFields = resolveDocumentPageMetadata({}, DEFAULT_DOCUMENT_PAGE_METADATA);
      expect(missingFields.pageTemplateId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId);
      expect(missingFields.pageSizeId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId);
      expect(missingFields.paperBackgroundId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId);

      const customFields = resolveDocumentPageMetadata({
        pageTemplateId: 'grid',
        pageSizeId: 'a5',
        paperBackgroundId: 'warm_cream'
      }, DEFAULT_DOCUMENT_PAGE_METADATA);
      expect(customFields.pageTemplateId).assertEqual('grid');
      expect(customFields.pageSizeId).assertEqual('a5');
      expect(customFields.paperBackgroundId).assertEqual('warm_cream');

      const invalidFields = resolveDocumentPageMetadata({
        pageTemplateId: 'missing-template',
        pageSizeId: 'missing-size',
        paperBackgroundId: 'missing-background'
      }, DEFAULT_DOCUMENT_PAGE_METADATA);
      expect(invalidFields.pageTemplateId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageTemplateId);
      expect(invalidFields.pageSizeId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.pageSizeId);
      expect(invalidFields.paperBackgroundId).assertEqual(DEFAULT_DOCUMENT_PAGE_METADATA.paperBackgroundId);
    });
  });
}
