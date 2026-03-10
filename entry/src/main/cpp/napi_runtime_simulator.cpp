#include "note_engine_runtime.h"

#include "hilog/log.h"

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

constexpr unsigned int kLogDomain = 0x3201;
constexpr const char* kLogTag = "NoteEngine";
constexpr const char* kUnsupportedSimulatorStatus = "unsupported-simulator";
constexpr const char* kWeakNativeShellStubReason = "x86_64-simulator-uses-weak-native-shell";
constexpr const char* kPrimaryPageId = "page-0";
constexpr const char* kLegacyCoordinateSpace = "legacy-surface";
constexpr const char* kStatsFallbackTargetMode = "stats-fallback";
constexpr int kPreviewSchemaVersion = 0;
constexpr int kPrimaryPageIndex = 0;

struct SimulatorDocumentSession {
    std::string documentId;
    std::string packagePath;
    std::string openConfigJson;
    int checkpointCount = 0;
    std::vector<std::string> pages;
    std::string activePageId;
};

struct SimulatorEngineState {
    std::string engineId;
    std::string configJson;
    std::string activeDocumentId;
    std::string activeTool = "pen";
    std::string activeBackend = "opengles";
    std::string activeMode = "paged";
    std::string activeColor = "#1D2736";
    std::string lastInkTool = "pen";
    std::string xComponentId;
    std::string surfaceId;
    int width = 0;
    int height = 0;
    double density = 1.0;
    bool predictionEnabled = true;
    bool pressureEnabled = true;
    bool shapeRecognitionEnabled = true;
    std::string lastCommittedStrokeType = "none";
    std::string lastInputTracePath;
    std::string lastInputTraceStatus = "idle";
    size_t lastInputTraceSampleCount = 0;
    std::unordered_map<std::string, SimulatorDocumentSession> documents;
};

std::string EscapeJsonString(const std::string& input)
{
    std::ostringstream builder;
    for (char c : input) {
        switch (c) {
            case '\\':
                builder << "\\\\";
                break;
            case '"':
                builder << "\\\"";
                break;
            case '\n':
                builder << "\\n";
                break;
            case '\r':
                builder << "\\r";
                break;
            case '\t':
                builder << "\\t";
                break;
            default:
                builder << c;
                break;
        }
    }
    return builder.str();
}

std::string ExtractJsonStringValue(const std::string& json, const std::string& key, const std::string& defaultValue)
{
    const std::string needle = "\"" + key + "\"";
    const size_t keyPosition = json.find(needle);
    if (keyPosition == std::string::npos) {
        return defaultValue;
    }

    const size_t colonPosition = json.find(':', keyPosition + needle.size());
    if (colonPosition == std::string::npos) {
        return defaultValue;
    }

    const size_t valueStart = json.find('"', colonPosition + 1);
    if (valueStart == std::string::npos) {
        return defaultValue;
    }

    const size_t valueEnd = json.find('"', valueStart + 1);
    if (valueEnd == std::string::npos || valueEnd <= valueStart) {
        return defaultValue;
    }

    return json.substr(valueStart + 1, valueEnd - valueStart - 1);
}

std::string ExtractJsonArrayBody(const std::string& text, const std::string& key)
{
    const std::string keyToken = "\"" + key + "\"";
    const size_t keyIndex = text.find(keyToken);
    if (keyIndex == std::string::npos) {
        return "";
    }

    const size_t arrayStart = text.find('[', keyIndex + keyToken.size());
    if (arrayStart == std::string::npos) {
        return "";
    }

    int bracketDepth = 0;
    bool inString = false;
    for (size_t index = arrayStart; index < text.size(); ++index) {
        const char character = text[index];
        if (character == '"' && (index == 0 || text[index - 1] != '\\')) {
            inString = !inString;
            continue;
        }
        if (inString) {
            continue;
        }
        if (character == '[') {
            bracketDepth += 1;
        } else if (character == ']') {
            bracketDepth -= 1;
            if (bracketDepth == 0) {
                return text.substr(arrayStart + 1, index - arrayStart - 1);
            }
        }
    }
    return "";
}

std::vector<std::string> SplitTopLevelJsonObjects(const std::string& arrayBody)
{
    std::vector<std::string> objects;
    int braceDepth = 0;
    int bracketDepth = 0;
    bool inString = false;
    size_t objectStart = std::string::npos;

    for (size_t index = 0; index < arrayBody.size(); ++index) {
        const char character = arrayBody[index];
        if (character == '"' && (index == 0 || arrayBody[index - 1] != '\\')) {
            inString = !inString;
            continue;
        }
        if (inString) {
            continue;
        }
        if (character == '[') {
            bracketDepth += 1;
        } else if (character == ']') {
            bracketDepth -= 1;
        } else if (character == '{') {
            if (braceDepth == 0 && bracketDepth == 0) {
                objectStart = index;
            }
            braceDepth += 1;
        } else if (character == '}') {
            braceDepth -= 1;
            if (braceDepth == 0 && objectStart != std::string::npos) {
                objects.push_back(arrayBody.substr(objectStart, index - objectStart + 1));
                objectStart = std::string::npos;
            }
        }
    }
    return objects;
}

std::string ExtractJsonObjectText(const std::string& text, const std::string& key)
{
    const std::string keyToken = "\"" + key + "\"";
    const size_t keyIndex = text.find(keyToken);
    if (keyIndex == std::string::npos) {
        return "";
    }

    const size_t colonPosition = text.find(':', keyIndex + keyToken.size());
    if (colonPosition == std::string::npos) {
        return "";
    }

    const size_t objectStart = text.find('{', colonPosition + 1);
    if (objectStart == std::string::npos) {
        return "";
    }

    int braceDepth = 0;
    bool inString = false;
    for (size_t index = objectStart; index < text.size(); ++index) {
        const char character = text[index];
        if (character == '"' && (index == 0 || text[index - 1] != '\\')) {
            inString = !inString;
            continue;
        }
        if (inString) {
            continue;
        }
        if (character == '{') {
            braceDepth += 1;
        } else if (character == '}') {
            braceDepth -= 1;
            if (braceDepth == 0) {
                return text.substr(objectStart, index - objectStart + 1);
            }
        }
    }
    return "";
}

std::vector<std::string> DeserializePageIdsFromOpenConfig(const std::string& configJson)
{
    std::vector<std::string> pageIds;
    const std::string pagesArray = ExtractJsonArrayBody(configJson, "pages");
    for (const std::string& pageObjectText : SplitTopLevelJsonObjects(pagesArray)) {
        const std::string pageId = ExtractJsonStringValue(pageObjectText, "id", "");
        if (pageId.empty()) {
            return {};
        }
        if (std::find(pageIds.begin(), pageIds.end(), pageId) != pageIds.end()) {
            return {};
        }
        pageIds.push_back(pageId);
    }
    return pageIds;
}

std::string ResolveCompatPageIdFromOpenConfig(const std::string& configJson)
{
    const std::string pageContractText = ExtractJsonObjectText(configJson, "pageContract");
    const std::string pageIdFromContract = ExtractJsonStringValue(pageContractText, "pageId", "");
    if (!pageIdFromContract.empty()) {
        return pageIdFromContract;
    }

    const std::string activePageId = ExtractJsonStringValue(configJson, "activePageId", "");
    if (!activePageId.empty()) {
        return activePageId;
    }

    const std::vector<std::string> pageIds = DeserializePageIdsFromOpenConfig(configJson);
    if (!pageIds.empty()) {
        return pageIds.front();
    }
    return kPrimaryPageId;
}

void InitializeCompatibilityPageSession(const std::string& configJson, SimulatorDocumentSession& session)
{
    const std::string pageId = ResolveCompatPageIdFromOpenConfig(configJson);
    session.pages = { pageId };
    session.activePageId = pageId;
}

bool InitializePageAwareSessionFromOpenConfig(const std::string& configJson, SimulatorDocumentSession& session)
{
    const std::vector<std::string> pageIds = DeserializePageIdsFromOpenConfig(configJson);
    const std::string activePageId = ExtractJsonStringValue(configJson, "activePageId", "");
    if (pageIds.empty() || activePageId.empty()) {
        return false;
    }
    if (std::find(pageIds.begin(), pageIds.end(), activePageId) == pageIds.end()) {
        return false;
    }
    session.pages = pageIds;
    session.activePageId = activePageId;
    return true;
}

bool IsBlankDocumentSession(const SimulatorDocumentSession& session)
{
    return ExtractJsonStringValue(session.openConfigJson, "documentType", "blank") == "blank";
}

bool SupportsPageAwareEditing(const SimulatorEngineState& engine, const SimulatorDocumentSession& session)
{
    return engine.activeMode == "paged" && IsBlankDocumentSession(session);
}

std::string ResolveSessionActivePageId(const SimulatorDocumentSession& session)
{
    if (!session.activePageId.empty() &&
        std::find(session.pages.begin(), session.pages.end(), session.activePageId) != session.pages.end()) {
        return session.activePageId;
    }
    if (!session.pages.empty()) {
        return session.pages.front();
    }
    return kPrimaryPageId;
}

int FindPageIndex(const std::vector<std::string>& pageIds, const std::string& pageId)
{
    const auto iterator = std::find(pageIds.begin(), pageIds.end(), pageId);
    if (iterator == pageIds.end()) {
        return -1;
    }
    return static_cast<int>(std::distance(pageIds.begin(), iterator));
}

std::vector<std::string> BuildReportedPageIds(const SimulatorEngineState& engine, const SimulatorDocumentSession& session)
{
    const std::string activePageId = ResolveSessionActivePageId(session);
    if (SupportsPageAwareEditing(engine, session)) {
        if (!session.pages.empty()) {
            return session.pages;
        }
        return { activePageId };
    }
    return { activePageId };
}

void AppendPageEntry(std::ostringstream& builder, const std::string& pageId, int pageIndex)
{
    builder << "{"
            << "\"pageId\":\"" << EscapeJsonString(pageId) << "\","
            << "\"pageIndex\":" << pageIndex
            << "}";
}

void AppendPageEntries(std::ostringstream& builder, const std::vector<std::string>& pageIds)
{
    builder << "[";
    for (size_t index = 0; index < pageIds.size(); ++index) {
        if (index > 0) {
            builder << ",";
        }
        AppendPageEntry(builder, pageIds[index], static_cast<int>(index));
    }
    builder << "]";
}

void AppendPreviewLayoutField(std::ostringstream& builder, const std::vector<std::string>& pageIds, const std::string& mode)
{
    builder << "\"layout\":{"
            << "\"mode\":\"" << EscapeJsonString(mode) << "\","
            << "\"pageCount\":" << pageIds.size() << ","
            << "\"pages\":";
    AppendPageEntries(builder, pageIds);
    builder << "}";
}

void AppendScenePageFields(std::ostringstream& builder, const std::vector<std::string>& pageIds, const std::string& mode)
{
    builder << "\"pages\":";
    AppendPageEntries(builder, pageIds);
    builder << ",\"layout\":{"
            << "\"mode\":\"" << EscapeJsonString(mode) << "\","
            << "\"pageCount\":" << pageIds.size() << ","
            << "\"pages\":";
    AppendPageEntries(builder, pageIds);
    builder << "}";
}

void AppendPreviewLayerFields(std::ostringstream& builder, bool includeInkLayer)
{
    builder << "\"layers\":";
    if (includeInkLayer) {
        builder << "[\"ink\"]";
        return;
    }
    builder << "[]";
}

void AppendCanonicalPreviewFields(std::ostringstream& builder, const std::string& engineId,
    const std::string& documentId, const std::string& pageId, int pageIndex, int width, int height,
    int checkpointCount, size_t strokeCount, size_t shapeCount, size_t objectCount, const std::string& mode,
    const std::vector<std::string>& pageIds, bool includeInkLayer)
{
    builder << "\"status\":\"ready\","
            << "\"previewSchemaVersion\":" << kPreviewSchemaVersion << ","
            << "\"engineId\":\"" << EscapeJsonString(engineId) << "\","
            << "\"documentId\":\"" << EscapeJsonString(documentId) << "\","
            << "\"pageIndex\":" << pageIndex << ","
            << "\"pageId\":\"" << EscapeJsonString(pageId) << "\","
            << "\"targetMode\":\"" << kStatsFallbackTargetMode << "\","
            << "\"coordinateSpace\":\"" << kLegacyCoordinateSpace << "\","
            << "\"width\":" << width << ","
            << "\"height\":" << height << ","
            << "\"strokeCount\":" << strokeCount << ","
            << "\"shapeCount\":" << shapeCount << ","
            << "\"checkpointCount\":" << checkpointCount << ","
            << "\"objectCount\":" << objectCount << ",";
    AppendPreviewLayoutField(builder, pageIds, mode);
    builder << ",";
    AppendPreviewLayerFields(builder, includeInkLayer);
}

void AppendCanonicalSceneFields(std::ostringstream& builder, const std::string& engineId,
    const std::string& documentId, const std::string& title, const std::string& documentType,
    const std::string& mode, const std::string& backend, int checkpointCount, size_t objectCount,
    const std::vector<std::string>& pageIds)
{
    builder << "\"status\":\"ready\","
            << "\"version\":1,"
            << "\"engineId\":\"" << EscapeJsonString(engineId) << "\","
            << "\"documentId\":\"" << EscapeJsonString(documentId) << "\","
            << "\"title\":\"" << EscapeJsonString(title) << "\","
            << "\"documentType\":\"" << EscapeJsonString(documentType) << "\","
            << "\"mode\":\"" << EscapeJsonString(mode) << "\","
            << "\"backend\":\"" << EscapeJsonString(backend) << "\","
            << "\"coordinateSpace\":\"" << kLegacyCoordinateSpace << "\","
            << "\"checkpointCount\":" << checkpointCount << ","
            << "\"objectCount\":" << objectCount << ",";
    AppendScenePageFields(builder, pageIds, mode);
}

void AppendCapabilityFields(std::ostringstream& builder, const std::string& runtimeMode,
    bool supportsStylusHardware, bool supportsTraceRecording, bool supportsNativeCanvas,
    bool previewRenderSupported, bool sceneExportSupported, const std::string& stubReason)
{
    builder << "\"runtimeMode\":\"" << EscapeJsonString(runtimeMode) << "\","
            << "\"supportsStylusHardware\":" << (supportsStylusHardware ? "true" : "false") << ","
            << "\"supportsTraceRecording\":" << (supportsTraceRecording ? "true" : "false") << ","
            << "\"supportsNativeCanvas\":" << (supportsNativeCanvas ? "true" : "false") << ","
            << "\"previewRenderSupported\":" << (previewRenderSupported ? "true" : "false") << ","
            << "\"sceneExportSupported\":" << (sceneExportSupported ? "true" : "false") << ","
            << "\"stubReason\":\"" << EscapeJsonString(stubReason) << "\"";
}

class SimulatorNoteEngineRuntime : public NoteEngineRuntime {
public:
    static SimulatorNoteEngineRuntime& Get()
    {
        static SimulatorNoteEngineRuntime instance;
        return instance;
    }

    std::string CreateEngine(const std::string& configJson) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        ++engineCounter_;

        SimulatorEngineState state;
        state.engineId = "engine-" + std::to_string(engineCounter_);
        state.configJson = configJson;
        state.predictionEnabled = configJson.find("\"enablePrediction\":true") != std::string::npos;
        state.pressureEnabled = configJson.find("\"enablePressureForPen\":true") != std::string::npos;
        state.shapeRecognitionEnabled = configJson.find("\"enableShapeDetection\":true") != std::string::npos;
        if (configJson.find("skia") != std::string::npos) {
            state.activeBackend = "skia";
        }
        if (configJson.find("infinite") != std::string::npos) {
            state.activeMode = "infinite";
        }
        engines_[state.engineId] = state;
        OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, kLogTag,
            "Create simulator engine %{public}s", state.engineId.c_str());
        return state.engineId;
    }

    bool OpenDocument(const std::string& engineId, const std::string& documentId,
        const std::string& packagePath, const std::string& configJson) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }

        SimulatorDocumentSession session;
        session.documentId = documentId;
        session.packagePath = packagePath;
        session.openConfigJson = configJson;
        const bool initializedPageAwareSession = engine->activeMode == "paged" &&
            IsBlankDocumentSession(session) &&
            InitializePageAwareSessionFromOpenConfig(configJson, session);
        if (!initializedPageAwareSession) {
            InitializeCompatibilityPageSession(configJson, session);
        }
        engine->documents[documentId] = session;
        engine->activeDocumentId = documentId;
        return true;
    }

    bool AttachXComponent(const std::string& engineId, const std::string& xComponentId, const std::string& surfaceId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->xComponentId = xComponentId;
        engine->surfaceId = surfaceId;
        return true;
    }

    bool Resize(const std::string& engineId, int width, int height, double density) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->width = width;
        engine->height = height;
        engine->density = density;
        return true;
    }

    bool SaveCheckpoint(const std::string& engineId, const std::string& documentId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        auto iterator = engine->documents.find(documentId);
        if (iterator == engine->documents.end()) {
            return false;
        }
        iterator->second.checkpointCount += 1;
        return true;
    }

    std::string RequestPreviewRender(const std::string& engineId, const std::string& documentId,
        int pageIndex, int width, int height) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        auto iterator = engine->documents.find(documentId);
        if (iterator == engine->documents.end()) {
            return R"({"status":"missing-document"})";
        }
        const std::string activePageId = ResolveSessionActivePageId(iterator->second);
        const std::vector<std::string> reportedPageIds = BuildReportedPageIds(*engine, iterator->second);
        const int activePageIndex = std::max(0, FindPageIndex(reportedPageIds, activePageId));

        std::ostringstream builder;
        builder << "{"
                ;
        AppendCanonicalPreviewFields(builder, engineId, documentId, activePageId, activePageIndex, width, height,
            iterator->second.checkpointCount, 0, 0, 0, engine->activeMode, reportedPageIds, false);
        builder
                << "}";
        return builder.str();
    }

    std::string ExportSceneSnapshot(const std::string& engineId, const std::string& documentId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        auto iterator = engine->documents.find(documentId);
        if (iterator == engine->documents.end()) {
            return R"({"status":"missing-document"})";
        }

        const std::vector<std::string> reportedPageIds = BuildReportedPageIds(*engine, iterator->second);
        std::ostringstream builder;
        builder << "{"
                ;
        AppendCanonicalSceneFields(builder, engine->engineId, iterator->second.documentId,
            ExtractJsonStringValue(iterator->second.openConfigJson, "title", ""),
            ExtractJsonStringValue(iterator->second.openConfigJson, "documentType", "blank"),
            engine->activeMode, engine->activeBackend, iterator->second.checkpointCount, 0, reportedPageIds);
        builder << ","
                << "\"objects\":[]"
                << "}";
        return builder.str();
    }

    bool SetActivePage(const std::string& engineId, const std::string& pageId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }
        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end() || !SupportsPageAwareEditing(*engine, iterator->second)) {
            return false;
        }
        if (FindPageIndex(iterator->second.pages, pageId) < 0) {
            return false;
        }
        iterator->second.activePageId = pageId;
        return true;
    }

    bool InsertPage(const std::string& engineId, const std::string& afterPageId, const std::string& pageConfigJson) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }
        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end() || !SupportsPageAwareEditing(*engine, iterator->second)) {
            return false;
        }

        auto afterIterator = std::find(iterator->second.pages.begin(), iterator->second.pages.end(), afterPageId);
        if (afterIterator == iterator->second.pages.end()) {
            return false;
        }
        const std::string newPageId = ExtractJsonStringValue(pageConfigJson, "pageId", "");
        if (newPageId.empty() || FindPageIndex(iterator->second.pages, newPageId) >= 0) {
            return false;
        }
        iterator->second.pages.insert(afterIterator + 1, newPageId);
        iterator->second.activePageId = newPageId;
        return true;
    }

    bool DeletePage(const std::string& engineId, const std::string& pageId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }
        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end() || !SupportsPageAwareEditing(*engine, iterator->second)) {
            return false;
        }

        auto pageIterator = std::find(iterator->second.pages.begin(), iterator->second.pages.end(), pageId);
        if (pageIterator == iterator->second.pages.end() || iterator->second.pages.size() <= 1) {
            return false;
        }

        const bool deletingActivePage = ResolveSessionActivePageId(iterator->second) == pageId;
        const int deleteIndex = static_cast<int>(std::distance(iterator->second.pages.begin(), pageIterator));
        std::string nextActivePageId = ResolveSessionActivePageId(iterator->second);
        if (deletingActivePage) {
            if (deleteIndex + 1 < static_cast<int>(iterator->second.pages.size())) {
                nextActivePageId = iterator->second.pages[deleteIndex + 1];
            } else {
                nextActivePageId = iterator->second.pages[deleteIndex - 1];
            }
        }

        iterator->second.pages.erase(pageIterator);
        iterator->second.activePageId = nextActivePageId;
        return true;
    }

    bool SetTool(const std::string& engineId, const std::string& tool) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        if (tool == "pen" || tool == "pencil" || tool == "highlighter") {
            engine->lastInkTool = tool;
        }
        engine->activeTool = tool;
        return true;
    }

    bool SetBackend(const std::string& engineId, const std::string& backend) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->activeBackend = backend;
        return true;
    }

    bool SetDocumentMode(const std::string& engineId, const std::string& mode) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->activeMode = mode;
        return true;
    }

    bool SetBrushColor(const std::string& engineId, const std::string& colorHex) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->activeColor = colorHex;
        return true;
    }

    bool Undo(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (FindEngineLocked(engineId) == nullptr) {
            return false;
        }
        return false;
    }

    bool Redo(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (FindEngineLocked(engineId) == nullptr) {
            return false;
        }
        return false;
    }

    bool StartInputTraceRecording(const std::string& engineId, const std::string& tracePath) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->lastInputTracePath = tracePath;
        engine->lastInputTraceStatus = kUnsupportedSimulatorStatus;
        engine->lastInputTraceSampleCount = 0;
        return false;
    }

    std::string StopInputTraceRecording(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        engine->lastInputTraceStatus = kUnsupportedSimulatorStatus;
        engine->lastInputTraceSampleCount = 0;
        return R"({"status":"unsupported-simulator"})";
    }

    std::string ReplayInputTrace(const std::string& engineId, const std::string& tracePath) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        engine->lastInputTracePath = tracePath.empty() ? engine->lastInputTracePath : tracePath;
        engine->lastInputTraceStatus = kUnsupportedSimulatorStatus;
        engine->lastInputTraceSampleCount = 0;
        return R"({"status":"unsupported-simulator"})";
    }

    bool DisposeDocument(const std::string& engineId, const std::string& documentId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->documents.erase(documentId);
        if (engine->activeDocumentId == documentId) {
            engine->activeDocumentId.clear();
        }
        return true;
    }

    bool DisposeEngine(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return engines_.erase(engineId) > 0;
    }

    std::string GetDebugState(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }

        int checkpointCount = 0;
        std::string activePageId = kPrimaryPageId;
        int activePageIndex = 0;
        size_t pageCount = 1;
        if (!engine->activeDocumentId.empty()) {
            auto iterator = engine->documents.find(engine->activeDocumentId);
            if (iterator != engine->documents.end()) {
                checkpointCount = iterator->second.checkpointCount;
                activePageId = ResolveSessionActivePageId(iterator->second);
                const std::vector<std::string> reportedPageIds = BuildReportedPageIds(*engine, iterator->second);
                activePageIndex = std::max(0, FindPageIndex(reportedPageIds, activePageId));
                pageCount = std::max<size_t>(1, reportedPageIds.size());
            }
        }

        std::ostringstream builder;
        builder << "{"
                << "\"engineId\":\"" << EscapeJsonString(engine->engineId) << "\","
                << "\"activeDocumentId\":\"" << EscapeJsonString(engine->activeDocumentId) << "\","
                << "\"activePageId\":\"" << EscapeJsonString(activePageId) << "\","
                << "\"activePageIndex\":" << activePageIndex << ","
                << "\"pageCount\":" << pageCount << ","
                << "\"activeTool\":\"" << EscapeJsonString(engine->activeTool) << "\","
                << "\"activeBackend\":\"" << EscapeJsonString(engine->activeBackend) << "\","
                << "\"activeMode\":\"" << EscapeJsonString(engine->activeMode) << "\","
                << "\"activeColor\":\"" << EscapeJsonString(engine->activeColor) << "\","
                << "\"xComponentId\":\"" << EscapeJsonString(engine->xComponentId) << "\","
                << "\"surfaceId\":\"" << EscapeJsonString(engine->surfaceId) << "\","
                << "\"checkpointCount\":" << checkpointCount << ","
                << "\"committedStrokeCount\":0,"
                << "\"undoDepth\":0,"
                << "\"redoDepth\":0,"
                << "\"lastCommittedStrokeType\":\"" << EscapeJsonString(engine->lastCommittedStrokeType) << "\","
                << "\"predictionEnabled\":" << (engine->predictionEnabled ? "true" : "false") << ","
                << "\"pressureEnabled\":" << (engine->pressureEnabled ? "true" : "false") << ","
                << "\"shapeRecognitionEnabled\":" << (engine->shapeRecognitionEnabled ? "true" : "false") << ","
                << "\"inputTraceRecording\":false,"
                << "\"inputReplayActive\":false,"
                << "\"inputTraceStatus\":\"" << EscapeJsonString(engine->lastInputTraceStatus) << "\","
                << "\"inputTracePath\":\"" << EscapeJsonString(engine->lastInputTracePath) << "\","
                << "\"inputTraceSampleCount\":" << engine->lastInputTraceSampleCount << ",";
        AppendCapabilityFields(builder, "simulator-stub", false, false, false, true, true, kWeakNativeShellStubReason);
        builder << ","
                << "\"surfaceReady\":false,"
                << "\"surfaceWidth\":" << engine->width << ","
                << "\"surfaceHeight\":" << engine->height << ","
                << "\"surfaceOffsetX\":0,"
                << "\"surfaceOffsetY\":0,"
                << "\"touchEventCount\":0,"
                << "\"uiTouchEventCount\":0,"
                << "\"keyEventCount\":0,"
                << "\"stylusEventCount\":0,"
                << "\"fingerEventCount\":0,"
                << "\"palmRejectedCount\":0,"
                << "\"activePointerCount\":0,"
                << "\"stylusActive\":false,"
                << "\"multitouchGestureActive\":false,"
                << "\"lastHistoricalCount\":0,"
                << "\"lastUiHistoryCount\":0,"
                << "\"predictedPointCount\":0,"
                << "\"lastEventTime\":0,"
                << "\"lastPressure\":0,"
                << "\"lastTiltX\":0,"
                << "\"lastTiltY\":0,"
                << "\"lastRollAngle\":0,"
                << "\"lastTouchAction\":\"unknown\","
                << "\"lastToolType\":\"unknown\","
                << "\"lastSourceType\":\"unknown\","
                << "\"lastKeyCode\":-1,"
                << "\"lastKeyAction\":-1,"
                << "\"lastKeySourceType\":-1,"
                << "\"lastKeyEventTime\":0"
                << "}";
        return builder.str();
    }

    void RegisterBridgeExports(napi_env, napi_value) override
    {
    }

private:
    SimulatorEngineState* FindEngineLocked(const std::string& engineId)
    {
        auto iterator = engines_.find(engineId);
        if (iterator == engines_.end()) {
            return nullptr;
        }
        return &iterator->second;
    }

    std::mutex mutex_;
    int engineCounter_ = 0;
    std::unordered_map<std::string, SimulatorEngineState> engines_;
};

} // namespace

NoteEngineRuntime& GetNoteEngineRuntime()
{
    return SimulatorNoteEngineRuntime::Get();
}
