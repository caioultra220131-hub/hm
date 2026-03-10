import { describe, expect, it } from '@ohos/hypium';
import { PreviewAdapterService } from '../main/ets/services/PreviewAdapterService';
import { buildNativePageContractFromMetadata } from '../main/ets/models/NativeNoteContracts';
import { DocumentMode, DocumentType, RenderBackend } from '../main/ets/models/NoteModels';

export default function previewAdapterServiceTest() {
  describe('previewAdapterServiceTest', () => {
    it('nativePageContractFromMetadataStaysStable', 0, () => {
      const blankContract = buildNativePageContractFromMetadata({
        pageTemplateId: 'blank',
        pageSizeId: 'letter_optimized',
        paperBackgroundId: 'plain_white'
      });
      expect(blankContract.pageTemplateId).assertEqual('blank');
      expect(blankContract.guideKind).assertEqual('plain');
      expect(blankContract.widthPt).assertEqual(612.283);
      expect(blankContract.heightPt).assertEqual(790.866);
      expect(blankContract.fill).assertEqual('#FFFFFF');
      expect(blankContract.accent).assertEqual('#D0D5DD');
      expect(blankContract.primitives.length > 0).assertEqual(true);

      const cornellContract = buildNativePageContractFromMetadata({
        pageTemplateId: 'cornell',
        pageSizeId: 'letter_optimized',
        paperBackgroundId: 'plain_white'
      });
      expect(cornellContract.cornell !== undefined).assertEqual(true);

      const weeklyContract = buildNativePageContractFromMetadata({
        pageTemplateId: 'weekly_planner',
        pageSizeId: 'a5',
        paperBackgroundId: 'warm_cream'
      });
      expect(weeklyContract.guideKind).assertEqual('weekly');
      expect(weeklyContract.weekly !== undefined).assertEqual(true);
    });

    it('previewAdapterNormalizesLegacySummaryPreview', 0, () => {
      const adapter = new PreviewAdapterService();
      const snapshot = adapter.normalizeRequestPreviewRenderPayload(
        JSON.stringify({
          generatedAt: 100,
          summary: 'legacy summary',
          previewLabel: 'legacy label',
          type: 'blank'
        }),
        {
          documentType: DocumentType.BLANK,
          documentMode: DocumentMode.PAGED,
          renderBackend: RenderBackend.OPEN_GLES,
          pageMetadata: {
            pageTemplateId: 'blank',
            pageSizeId: 'letter_optimized',
            paperBackgroundId: 'plain_white'
          },
          generatedAt: 200,
          fallbackSummary: 'markdown fallback',
          fallbackPreviewLabel: 'paged/opengles',
          fallbackPageIndex: 0
        }
      );

      expect(snapshot.schemaVersion).assertEqual(2);
      expect(snapshot.previewSchemaVersion).assertEqual(0);
      expect(snapshot.summary).assertEqual('markdown fallback');
      expect(snapshot.nativeSummary).assertEqual('legacy summary');
      expect(snapshot.source).assertEqual('markdown');
      expect(snapshot.previewStatus).assertEqual('fallback');
      expect(snapshot.targetMode).assertEqual('summary-only');
      expect(snapshot.pageContract.pageTemplateId).assertEqual('blank');
      expect(snapshot.pageIds.length > 0).assertEqual(true);
    });

    it('previewAdapterPreservesStructuredNativePayload', 0, () => {
      const adapter = new PreviewAdapterService();
      const snapshot = adapter.normalizeRequestPreviewRenderPayload(
        {
          previewSchemaVersion: 3,
          status: 'ready',
          targetMode: 'native-layout',
          pageIndex: 2,
          pageId: 'page-2',
          summary: 'native summary',
          layout: {
            pageCount: 1,
            pages: [
              {
                pageId: 'page-2',
                pageIndex: 2,
                backgroundId: 'warm_cream',
                guideKind: 'weekly'
              }
            ]
          },
          layers: ['ink', 'transient'],
          targetBounds: {
            minX: 1,
            minY: 2,
            maxX: 3,
            maxY: 4
          },
          checkpointCount: 5,
          objectCount: 8,
          raster: {
            mimeType: 'image/png',
            base64: 'abc',
            width: 320,
            height: 180
          },
          pageContract: {
            pageId: 'page-2',
            pageTemplateId: 'weekly_planner',
            pageSizeId: 'a5',
            paperBackgroundId: 'warm_cream',
            guideKind: 'weekly',
            widthPt: 419.528,
            heightPt: 595.276,
            fill: '#FAF3E0',
            accent: '#E1C89B',
            fillColor: '#FAF3E0',
            accentColor: '#E1C89B',
            guide: {
              guideKind: 'weekly',
              contentBounds: {
                x: 0.05,
                y: 0.14,
                width: 0.90,
                height: 0.79
              }
            },
            primitives: [
              {
                id: 'divider-1',
                kind: 'divider',
                x: 0.05,
                y: 0.73,
                width: 0.90,
                height: 0.002
              }
            ],
            weekly: {
              headerHeight: 0.08,
              dayColumnCount: 7,
              weekGridTop: 0.14,
              weekGridHeight: 0.56,
              dayColumnWidth: 0.128,
              notesTop: 0.77,
              notesHeight: 0.16,
              noteRuleSpacing: 0.045
            }
          },
          extraField: 'kept'
        },
        {
          documentType: DocumentType.BLANK,
          documentMode: DocumentMode.PAGED,
          renderBackend: RenderBackend.OPEN_GLES,
          pageMetadata: {
            pageTemplateId: 'weekly_planner',
            pageSizeId: 'a5',
            paperBackgroundId: 'warm_cream'
          },
          generatedAt: 300,
          fallbackSummary: 'markdown fallback',
          fallbackPreviewLabel: 'paged/opengles',
          fallbackPageIndex: 0
        }
      );

      expect(snapshot.previewSchemaVersion).assertEqual(3);
      expect(snapshot.source).assertEqual('native');
      expect(snapshot.previewStatus).assertEqual('ready');
      expect(snapshot.summary).assertEqual('markdown fallback');
      expect(snapshot.nativeSummary).assertEqual('native summary');
      expect(snapshot.pageContract.guideKind).assertEqual('weekly');
      expect(snapshot.pageContract.weekly !== undefined).assertEqual(true);
      expect(snapshot.raster?.base64).assertEqual('abc');
      expect(snapshot.layout?.pageCount).assertEqual(1);
      expect(snapshot.extension?.['extraField']).assertEqual('kept');
    });
  });
}
