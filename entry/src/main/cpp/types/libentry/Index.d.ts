declare const entry: {
  createEngine: (configJson: string) => string;
  openDocument: (engineId: string, documentId: string, packagePath: string, configJson: string) => boolean;
  attachXComponent: (engineId: string, xComponentId: string, surfaceId: string) => boolean;
  resize: (engineId: string, width: number, height: number, density: number) => boolean;
  saveCheckpoint: (engineId: string, documentId: string) => boolean;
  requestPreviewRender: (engineId: string, documentId: string, pageIndex: number, width: number, height: number) => string;
  exportSceneSnapshot: (engineId: string, documentId: string) => string;
  setTool: (engineId: string, tool: string) => boolean;
  setBackend: (engineId: string, backend: string) => boolean;
  setDocumentMode: (engineId: string, mode: string) => boolean;
  setBrushColor: (engineId: string, colorHex: string) => boolean;
  undo: (engineId: string) => boolean;
  redo: (engineId: string) => boolean;
  disposeDocument: (engineId: string, documentId: string) => boolean;
  disposeEngine: (engineId: string) => boolean;
  getDebugState: (engineId: string) => string;
  readPdfPageCount: (pdfPath: string) => string;
};

export default entry;
