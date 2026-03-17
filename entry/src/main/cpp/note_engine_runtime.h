#ifndef NOTE_ENGINE_RUNTIME_H
#define NOTE_ENGINE_RUNTIME_H

#include "napi/native_api.h"

#include <string>

class NoteEngineRuntime {
public:
    virtual ~NoteEngineRuntime() = default;

    virtual std::string CreateEngine(const std::string& configJson) = 0;
    virtual bool OpenDocument(const std::string& engineId, const std::string& documentId,
        const std::string& packagePath, const std::string& configJson) = 0;
    virtual bool AttachXComponent(const std::string& engineId, const std::string& xComponentId,
        const std::string& surfaceId) = 0;
    virtual bool Resize(const std::string& engineId, int width, int height, double density) = 0;
    virtual bool SaveCheckpoint(const std::string& engineId, const std::string& documentId) = 0;
    virtual std::string RequestPreviewRender(const std::string& engineId, const std::string& documentId,
        int pageIndex, int width, int height) = 0;
    virtual std::string ExportSceneSnapshot(const std::string& engineId, const std::string& documentId) = 0;
    virtual std::string ReadPdfPageCount(const std::string& pdfPath) = 0;
    virtual bool SetActivePage(const std::string& engineId, const std::string& pageId) = 0;
    virtual bool InsertPage(const std::string& engineId, const std::string& afterPageId,
        const std::string& pageConfigJson) = 0;
    virtual bool DeletePage(const std::string& engineId, const std::string& pageId) = 0;
    virtual bool SetTool(const std::string& engineId, const std::string& tool) = 0;
    virtual bool SetFingerWritingEnabled(const std::string& engineId, bool enabled) = 0;
    virtual bool InjectSimulatorFingerEvent(const std::string& engineId, const std::string& action,
        double pageXRatio, double pageYRatio, int pointerCount) = 0;
    virtual bool SetBackend(const std::string& engineId, const std::string& backend) = 0;
    virtual bool SetDocumentMode(const std::string& engineId, const std::string& mode) = 0;
    virtual bool SetBrushColor(const std::string& engineId, const std::string& colorHex) = 0;
    virtual bool SetBrushWidth(const std::string& engineId, double width) = 0;
    virtual bool Undo(const std::string& engineId) = 0;
    virtual bool Redo(const std::string& engineId) = 0;
    virtual bool StartInputTraceRecording(const std::string& engineId, const std::string& tracePath) = 0;
    virtual std::string StopInputTraceRecording(const std::string& engineId) = 0;
    virtual std::string ReplayInputTrace(const std::string& engineId, const std::string& tracePath) = 0;
    virtual bool DisposeDocument(const std::string& engineId, const std::string& documentId) = 0;
    virtual bool DisposeEngine(const std::string& engineId) = 0;
    virtual std::string GetDebugState(const std::string& engineId) = 0;
    virtual void RegisterBridgeExports(napi_env env, napi_value exports) = 0;
};

NoteEngineRuntime& GetNoteEngineRuntime();

#endif
