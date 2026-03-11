import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';

export interface PickedPdfImportAsset {
  sourceUri: string;
  sourceDisplayName: string;
  sourceMimeType: string;
  sourceByteSize: number;
}

const PDF_FILE_FILTERS: string[] = ['PDF|.pdf'];
const PDF_MIME_TYPE: string = 'application/pdf';
const FALLBACK_PDF_NAME: string = 'imported.pdf';

export class PdfImportService {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async pickSinglePdf(): Promise<PickedPdfImportAsset | null> {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const selectedUris: string[] = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: PDF_FILE_FILTERS
    });
    if (!Array.isArray(selectedUris) || selectedUris.length === 0) {
      return null;
    }
    const sourceUri: string = selectedUris[0];
    return {
      sourceUri,
      sourceDisplayName: this.readDisplayName(sourceUri),
      sourceMimeType: PDF_MIME_TYPE,
      sourceByteSize: this.readByteSize(sourceUri)
    };
  }

  private readDisplayName(sourceUri: string): string {
    try {
      const resolvedName: string = new fileUri.FileUri(sourceUri).name;
      if (resolvedName.trim().length > 0) {
        return resolvedName.trim();
      }
    } catch (_) {
      // Fall back to the URI tail when the provider does not expose a friendly file name.
    }
    const uriTail: string = sourceUri.split('/').pop() ?? '';
    return uriTail.trim().length > 0 ? uriTail.trim() : FALLBACK_PDF_NAME;
  }

  private readByteSize(sourceUri: string): number {
    const statCandidates: string[] = [sourceUri];
    try {
      const sourcePath: string = new fileUri.FileUri(sourceUri).path;
      if (sourcePath.trim().length > 0 && !statCandidates.includes(sourcePath)) {
        statCandidates.push(sourcePath.trim());
      }
    } catch (_) {
      // Keep the original picker URI when no local path can be derived.
    }
    for (let index = 0; index < statCandidates.length; index += 1) {
      try {
        return Math.max(0, fileIo.statSync(statCandidates[index]).size);
      } catch (_) {
        continue;
      }
    }
    return 0;
  }
}
