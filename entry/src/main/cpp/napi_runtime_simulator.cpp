#include "note_engine_runtime.h"

#include "hilog/log.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <fstream>
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
constexpr const char* kPdfPageNodeIdPrefix = "pdf-page-";
constexpr const char* kPdfFragmentNodeIdPrefix = "pdf-fragment-";
constexpr int kPreviewSchemaVersion = 0;
constexpr int kPrimaryPageIndex = 0;

struct SimulatorPageContractDescriptor {
    double widthPt = 0.0;
    double heightPt = 0.0;
    std::string paperBackgroundId = "paper";
    std::string guideKind = "plain";
};

struct SimulatorPageDescriptor {
    std::string pageId;
    int order = 0;
    std::string pageKind = "blank";
    std::string sourceAttachmentId;
    int sourcePageIndex = -1;
    SimulatorPageContractDescriptor contract;
};

struct SimulatorDocumentSession {
    std::string documentId;
    std::string packagePath;
    std::string openConfigJson;
    int checkpointCount = 0;
    bool pageAware = false;
    std::vector<std::string> pages;
    std::vector<SimulatorPageDescriptor> pageDescriptors;
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

std::vector<SimulatorPageDescriptor> DeserializePageDescriptorsFromOpenConfig(const std::string& configJson);
std::vector<std::string> BuildPageIdsFromDescriptors(const std::vector<SimulatorPageDescriptor>& descriptors);

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

    const std::vector<std::string> pageIds = BuildPageIdsFromDescriptors(
        DeserializePageDescriptorsFromOpenConfig(configJson));
    if (!pageIds.empty()) {
        return pageIds.front();
    }
    return kPrimaryPageId;
}

double ExtractJsonNumberValue(const std::string& json, const std::string& key, double defaultValue)
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

    size_t valueStart = colonPosition + 1;
    while (valueStart < json.size() && std::isspace(static_cast<unsigned char>(json[valueStart]))) {
        valueStart += 1;
    }
    size_t valueEnd = valueStart;
    while (valueEnd < json.size()) {
        const char character = json[valueEnd];
        if (!(std::isdigit(static_cast<unsigned char>(character)) || character == '.' || character == '-' || character == '+')) {
            break;
        }
        valueEnd += 1;
    }
    if (valueEnd <= valueStart) {
        return defaultValue;
    }
    try {
        return std::stod(json.substr(valueStart, valueEnd - valueStart));
    } catch (...) {
        return defaultValue;
    }
}

std::string InferCompatPageKindFromOpenConfig(const std::string& configJson)
{
    const std::string documentType = ExtractJsonStringValue(configJson, "documentType", "blank");
    if (documentType == "pdf") {
        return "pdf";
    }
    if (documentType == "hybrid") {
        return "pdf-fragment";
    }
    return "blank";
}

std::string NormalizePageKind(const std::string& pageKind, const std::string& fallback)
{
    if (pageKind == "blank" || pageKind == "pdf" || pageKind == "pdf-fragment") {
        return pageKind;
    }
    return fallback;
}

bool IsPdfPageKind(const std::string& pageKind)
{
    return pageKind == "pdf" || pageKind == "pdf-fragment";
}

bool IsFullPagePdfKind(const std::string& pageKind)
{
    return pageKind == "pdf";
}

std::string ExtractPageContractTextFromOpenConfig(const std::string& configJson, const std::string& pageId)
{
    const std::string pageContractsText = ExtractJsonObjectText(configJson, "pageContracts");
    if (!pageContractsText.empty()) {
        const std::string specificContractText = ExtractJsonObjectText(pageContractsText, pageId);
        if (!specificContractText.empty()) {
            return specificContractText;
        }
    }

    const std::string activePageId = ExtractJsonStringValue(configJson, "activePageId", "");
    if (activePageId.empty() || activePageId == pageId) {
        return ExtractJsonObjectText(configJson, "pageContract");
    }
    return "";
}

SimulatorPageContractDescriptor ParsePageContractDescriptor(const std::string& contractText)
{
    SimulatorPageContractDescriptor descriptor;
    if (contractText.empty()) {
        return descriptor;
    }
    descriptor.widthPt = std::max(0.0, ExtractJsonNumberValue(contractText, "widthPt", 0.0));
    descriptor.heightPt = std::max(0.0, ExtractJsonNumberValue(contractText, "heightPt", 0.0));
    descriptor.paperBackgroundId = ExtractJsonStringValue(contractText, "paperBackgroundId", "paper");
    descriptor.guideKind = ExtractJsonStringValue(contractText, "guideKind", "plain");
    if (descriptor.paperBackgroundId.empty()) {
        descriptor.paperBackgroundId = "paper";
    }
    if (descriptor.guideKind.empty()) {
        descriptor.guideKind = "plain";
    }
    return descriptor;
}

std::vector<SimulatorPageDescriptor> DeserializePageDescriptorsFromOpenConfig(const std::string& configJson)
{
    std::vector<SimulatorPageDescriptor> descriptors;
    const std::string pagesArray = ExtractJsonArrayBody(configJson, "pages");
    const std::string fallbackPageKind = InferCompatPageKindFromOpenConfig(configJson);
    for (const std::string& pageObjectText : SplitTopLevelJsonObjects(pagesArray)) {
        SimulatorPageDescriptor descriptor;
        descriptor.pageId = ExtractJsonStringValue(pageObjectText, "id", "");
        if (descriptor.pageId.empty()) {
            return {};
        }
        if (std::any_of(descriptors.begin(), descriptors.end(), [&](const SimulatorPageDescriptor& existing) {
                return existing.pageId == descriptor.pageId;
            })) {
            return {};
        }
        descriptor.order = static_cast<int>(ExtractJsonNumberValue(
            pageObjectText, "order", static_cast<double>(descriptors.size())));
        descriptor.pageKind = NormalizePageKind(
            ExtractJsonStringValue(pageObjectText, "pageKind", fallbackPageKind),
            fallbackPageKind);
        descriptor.sourceAttachmentId = ExtractJsonStringValue(pageObjectText, "sourceAttachmentId", "");
        descriptor.sourcePageIndex = static_cast<int>(ExtractJsonNumberValue(pageObjectText, "sourcePageIndex", -1));
        descriptor.contract = ParsePageContractDescriptor(
            ExtractPageContractTextFromOpenConfig(configJson, descriptor.pageId));
        descriptors.push_back(descriptor);
    }
    return descriptors;
}

std::vector<std::string> BuildPageIdsFromDescriptors(const std::vector<SimulatorPageDescriptor>& descriptors)
{
    std::vector<std::string> pageIds;
    pageIds.reserve(descriptors.size());
    for (const SimulatorPageDescriptor& descriptor : descriptors) {
        pageIds.push_back(descriptor.pageId);
    }
    return pageIds;
}

const SimulatorPageDescriptor* FindPageDescriptor(const SimulatorDocumentSession& session, const std::string& pageId)
{
    const auto iterator = std::find_if(session.pageDescriptors.begin(), session.pageDescriptors.end(),
        [&](const SimulatorPageDescriptor& descriptor) {
            return descriptor.pageId == pageId;
        });
    if (iterator == session.pageDescriptors.end()) {
        return nullptr;
    }
    return &(*iterator);
}

void ReindexPageDescriptors(SimulatorDocumentSession& session)
{
    for (size_t index = 0; index < session.pageDescriptors.size(); ++index) {
        session.pageDescriptors[index].order = static_cast<int>(index);
    }
}

void InitializeCompatibilityPageSession(const std::string& configJson, SimulatorDocumentSession& session)
{
    const std::string pageId = ResolveCompatPageIdFromOpenConfig(configJson);
    SimulatorPageDescriptor descriptor;
    descriptor.pageId = pageId;
    descriptor.pageKind = InferCompatPageKindFromOpenConfig(configJson);
    descriptor.contract = ParsePageContractDescriptor(ExtractPageContractTextFromOpenConfig(configJson, pageId));
    session.pageAware = false;
    session.pages = { pageId };
    session.pageDescriptors = { descriptor };
    session.activePageId = pageId;
}

bool InitializePageAwareSessionFromOpenConfig(const std::string& configJson, SimulatorDocumentSession& session)
{
    const std::vector<SimulatorPageDescriptor> pageDescriptors = DeserializePageDescriptorsFromOpenConfig(configJson);
    const std::string activePageId = ExtractJsonStringValue(configJson, "activePageId", "");
    if (pageDescriptors.empty() || activePageId.empty()) {
        return false;
    }
    const std::vector<std::string> pageIds = BuildPageIdsFromDescriptors(pageDescriptors);
    if (std::find(pageIds.begin(), pageIds.end(), activePageId) == pageIds.end()) {
        return false;
    }
    session.pageAware = true;
    session.pages = pageIds;
    session.pageDescriptors = pageDescriptors;
    session.activePageId = activePageId;
    return true;
}

bool SupportsPageAwareEditing(const SimulatorEngineState& engine, const SimulatorDocumentSession& session)
{
    return engine.activeMode == "paged" && session.pageAware && !session.pages.empty();
}

bool SupportsBlankPageMutation(const SimulatorEngineState& engine, const SimulatorDocumentSession& session)
{
    if (!SupportsPageAwareEditing(engine, session) || session.pageDescriptors.empty()) {
        return false;
    }
    return std::all_of(session.pageDescriptors.begin(), session.pageDescriptors.end(),
        [](const SimulatorPageDescriptor& descriptor) {
            return descriptor.pageKind == "blank";
        });
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

bool HasPageBounds(const SimulatorPageDescriptor* descriptor)
{
    return descriptor != nullptr && descriptor->contract.widthPt > 0.0 && descriptor->contract.heightPt > 0.0;
}

std::string BuildPageBackgroundId(const SimulatorPageDescriptor* descriptor)
{
    if (descriptor == nullptr) {
        return "";
    }
    if (IsFullPagePdfKind(descriptor->pageKind)) {
        return descriptor->sourcePageIndex >= 0
            ? "pdf/source-" + std::to_string(descriptor->sourcePageIndex)
            : "";
    }
    if (descriptor->contract.paperBackgroundId.empty()) {
        return "";
    }
    return "paper/" + descriptor->contract.paperBackgroundId;
}

void AppendPageBounds(std::ostringstream& builder, const SimulatorPageDescriptor* descriptor)
{
    const double width = descriptor != nullptr ? descriptor->contract.widthPt : 0.0;
    const double height = descriptor != nullptr ? descriptor->contract.heightPt : 0.0;
    builder << "\"bounds\":{"
            << "\"minX\":0,"
            << "\"minY\":0,"
            << "\"maxX\":" << width << ","
            << "\"maxY\":" << height
            << "}";
}

void AppendPageEntry(std::ostringstream& builder, const SimulatorDocumentSession& session,
    const std::string& pageId, int pageIndex)
{
    const SimulatorPageDescriptor* descriptor = FindPageDescriptor(session, pageId);
    builder << "{"
            << "\"pageId\":\"" << EscapeJsonString(pageId) << "\","
            << "\"pageIndex\":" << pageIndex;
    if (HasPageBounds(descriptor)) {
        builder << ",\"width\":" << descriptor->contract.widthPt
                << ",\"height\":" << descriptor->contract.heightPt
                << ",";
        AppendPageBounds(builder, descriptor);
    }
    const std::string backgroundId = BuildPageBackgroundId(descriptor);
    if (!backgroundId.empty()) {
        builder << ",\"backgroundId\":\"" << EscapeJsonString(backgroundId) << "\"";
    }
    if (descriptor != nullptr && !descriptor->contract.guideKind.empty()) {
        builder << ",\"guideKind\":\"" << EscapeJsonString(descriptor->contract.guideKind) << "\"";
    }
    builder << "}";
}

void AppendPageEntries(std::ostringstream& builder, const SimulatorDocumentSession& session,
    const std::vector<std::string>& pageIds)
{
    builder << "[";
    for (size_t index = 0; index < pageIds.size(); ++index) {
        if (index > 0) {
            builder << ",";
        }
        AppendPageEntry(builder, session, pageIds[index], static_cast<int>(index));
    }
    builder << "]";
}

bool TryResolveDocumentBounds(const SimulatorDocumentSession& session, const std::vector<std::string>& pageIds,
    double& maxWidth, double& maxHeight)
{
    maxWidth = 0.0;
    maxHeight = 0.0;
    bool hasBounds = false;
    for (const std::string& pageId : pageIds) {
        const SimulatorPageDescriptor* descriptor = FindPageDescriptor(session, pageId);
        if (!HasPageBounds(descriptor)) {
            continue;
        }
        maxWidth = std::max(maxWidth, descriptor->contract.widthPt);
        maxHeight = std::max(maxHeight, descriptor->contract.heightPt);
        hasBounds = true;
    }
    return hasBounds;
}

void AppendPreviewLayoutField(std::ostringstream& builder, const SimulatorDocumentSession& session,
    const std::vector<std::string>& pageIds, const std::string& mode)
{
    builder << "\"layout\":{"
            << "\"mode\":\"" << EscapeJsonString(mode) << "\","
            << "\"pageCount\":" << pageIds.size();
    double documentWidth = 0.0;
    double documentHeight = 0.0;
    if (TryResolveDocumentBounds(session, pageIds, documentWidth, documentHeight)) {
        builder << ",\"documentBounds\":{"
                << "\"minX\":0,"
                << "\"minY\":0,"
                << "\"maxX\":" << documentWidth << ","
                << "\"maxY\":" << documentHeight
                << "}";
    }
    builder << ",\"pages\":";
    AppendPageEntries(builder, session, pageIds);
    builder << "}";
}

void AppendScenePageFields(std::ostringstream& builder, const SimulatorDocumentSession& session,
    const std::vector<std::string>& pageIds, const std::string& mode)
{
    builder << "\"pages\":";
    AppendPageEntries(builder, session, pageIds);
    builder << ",";
    AppendPreviewLayoutField(builder, session, pageIds, mode);
}

void AppendCanonicalPreviewFields(std::ostringstream& builder, const std::string& engineId,
    const std::string& documentId, const std::string& pageId, int pageIndex, int width, int height,
    int checkpointCount, size_t strokeCount, size_t shapeCount, size_t objectCount, const std::string& mode,
    const SimulatorDocumentSession& session, const std::vector<std::string>& pageIds,
    bool includePdfLayer, bool includeInkLayer)
{
    const SimulatorPageDescriptor* descriptor = FindPageDescriptor(session, pageId);
    builder << "\"status\":\"ready\","
            << "\"previewSchemaVersion\":" << kPreviewSchemaVersion << ","
            << "\"engineId\":\"" << EscapeJsonString(engineId) << "\","
            << "\"documentId\":\"" << EscapeJsonString(documentId) << "\","
            << "\"pageIndex\":" << pageIndex << ","
            << "\"pageId\":\"" << EscapeJsonString(pageId) << "\","
            << "\"targetMode\":\"" << kStatsFallbackTargetMode << "\","
            << "\"coordinateSpace\":\"" << kLegacyCoordinateSpace << "\"";
    if (HasPageBounds(descriptor)) {
        builder << ",\"targetBounds\":{"
                << "\"minX\":0,"
                << "\"minY\":0,"
                << "\"maxX\":" << descriptor->contract.widthPt << ","
                << "\"maxY\":" << descriptor->contract.heightPt
                << "}";
    }
    builder << ","
            << "\"width\":" << width << ","
            << "\"height\":" << height << ","
            << "\"strokeCount\":" << strokeCount << ","
            << "\"shapeCount\":" << shapeCount << ","
            << "\"checkpointCount\":" << checkpointCount << ","
            << "\"objectCount\":" << objectCount << ",";
    AppendPreviewLayoutField(builder, session, pageIds, mode);
    builder << ",\"layers\":[";
    bool wroteLayer = false;
    if (includePdfLayer) {
        builder << "\"pdf\"";
        wroteLayer = true;
    }
    if (includeInkLayer) {
        if (wroteLayer) {
            builder << ",";
        }
        builder << "\"ink\"";
    }
    builder << "]";
}

void AppendCanonicalSceneFields(std::ostringstream& builder, const std::string& engineId,
    const std::string& documentId, const std::string& title, const std::string& documentType,
    const std::string& mode, const std::string& backend, int checkpointCount, size_t objectCount,
    const SimulatorDocumentSession& session, const std::vector<std::string>& pageIds)
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
    AppendScenePageFields(builder, session, pageIds, mode);
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

std::string ReadBinaryFile(const std::string& path, std::string& contents)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream.is_open()) {
        return "file-not-found";
    }
    std::ostringstream buffer;
    buffer << stream.rdbuf();
    if (stream.bad()) {
        contents.clear();
        return "read-failed";
    }
    contents = buffer.str();
    return "";
}

bool HasPdfHeader(const std::string& contents)
{
    return contents.size() >= 5 && contents.compare(0, 5, "%PDF-") == 0;
}

bool ContainsPdfToken(const std::string& contents, const std::string& token)
{
    return contents.find(token) != std::string::npos;
}

bool IsPdfNameCharacter(unsigned char value)
{
    return std::isalnum(value) || value == '-' || value == '_' || value == '.';
}

int CountPdfPageTypeObjects(const std::string& contents)
{
    int count = 0;
    size_t cursor = 0;
    while ((cursor = contents.find("/Type", cursor)) != std::string::npos) {
        size_t valueCursor = cursor + 5;
        while (valueCursor < contents.size() && std::isspace(static_cast<unsigned char>(contents[valueCursor]))) {
            valueCursor += 1;
        }
        if (valueCursor >= contents.size() || contents[valueCursor] != '/') {
            cursor += 5;
            continue;
        }
        valueCursor += 1;
        size_t valueEnd = valueCursor;
        while (valueEnd < contents.size() && IsPdfNameCharacter(static_cast<unsigned char>(contents[valueEnd]))) {
            valueEnd += 1;
        }
        if (contents.substr(valueCursor, valueEnd - valueCursor) == "Page") {
            count += 1;
        }
        cursor = valueEnd;
    }
    return count;
}

std::vector<int> ExtractPdfCountValues(const std::string& contents)
{
    std::vector<int> values;
    size_t cursor = 0;
    while ((cursor = contents.find("/Count", cursor)) != std::string::npos) {
        size_t valueCursor = cursor + 6;
        while (valueCursor < contents.size() && std::isspace(static_cast<unsigned char>(contents[valueCursor]))) {
            valueCursor += 1;
        }
        size_t valueEnd = valueCursor;
        while (valueEnd < contents.size() && std::isdigit(static_cast<unsigned char>(contents[valueEnd]))) {
            valueEnd += 1;
        }
        if (valueEnd > valueCursor) {
            try {
                values.push_back(std::stoi(contents.substr(valueCursor, valueEnd - valueCursor)));
            } catch (...) {
            }
        }
        cursor = valueEnd > cursor ? valueEnd : cursor + 6;
    }
    return values;
}

bool TryReadPdfPageCountWithPlatformReader(const std::string& pdfPath, int& pageCount)
{
    (void) pdfPath;
    (void) pageCount;
    return false;
}

std::string BuildPdfPageCountResult(const std::string& status, int pageCount, const std::string& detail)
{
    std::ostringstream builder;
    builder << "{\"status\":\"" << EscapeJsonString(status) << "\"";
    if (pageCount >= 0) {
        builder << ",\"pageCount\":" << pageCount;
    }
    if (!detail.empty()) {
        builder << ",\"detail\":\"" << EscapeJsonString(detail) << "\"";
    }
    builder << "}";
    return builder.str();
}

std::string ReadPdfPageCountFromFile(const std::string& pdfPath)
{
    if (pdfPath.empty()) {
        return BuildPdfPageCountResult("invalid-args", -1, "pdfPath is required");
    }

    int platformPageCount = 0;
    if (TryReadPdfPageCountWithPlatformReader(pdfPath, platformPageCount) && platformPageCount > 0) {
        return BuildPdfPageCountResult("ok", platformPageCount, "");
    }

    std::string contents;
    const std::string readStatus = ReadBinaryFile(pdfPath, contents);
    if (!readStatus.empty()) {
        return BuildPdfPageCountResult(readStatus, -1, readStatus == "file-not-found"
            ? "unable to open pdf"
            : "unable to read pdf");
    }
    if (!HasPdfHeader(contents)) {
        return BuildPdfPageCountResult("invalid-pdf", -1, "missing %PDF header");
    }
    if (ContainsPdfToken(contents, "/ObjStm") || ContainsPdfToken(contents, "/XRef")) {
        return BuildPdfPageCountResult("page-count-unavailable", -1, "compressed object streams are not supported by fallback reader");
    }

    const int directPageCount = CountPdfPageTypeObjects(contents);
    if (directPageCount <= 0) {
        return BuildPdfPageCountResult("page-count-unavailable", -1, "unable to find page dictionaries");
    }
    const std::vector<int> pageTreeCounts = ExtractPdfCountValues(contents);
    const auto matchingCount = std::find(pageTreeCounts.begin(), pageTreeCounts.end(), directPageCount);
    const int maxCount = pageTreeCounts.empty()
        ? -1
        : *std::max_element(pageTreeCounts.begin(), pageTreeCounts.end());
    if (matchingCount != pageTreeCounts.end() && maxCount == directPageCount) {
        return BuildPdfPageCountResult("ok", directPageCount, "");
    }
    return BuildPdfPageCountResult(
        "page-count-unavailable",
        -1,
        "conservative fallback could not verify page count");
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
        const std::vector<std::string> reportedPageIds = BuildReportedPageIds(*engine, iterator->second);
        std::string targetPageId = ResolveSessionActivePageId(iterator->second);
        int targetPageIndex = std::max(0, FindPageIndex(reportedPageIds, targetPageId));
        if (SupportsPageAwareEditing(*engine, iterator->second) &&
            pageIndex >= 0 &&
            pageIndex < static_cast<int>(reportedPageIds.size())) {
            targetPageId = reportedPageIds[pageIndex];
            targetPageIndex = pageIndex;
        }
        const SimulatorPageDescriptor* targetDescriptor = FindPageDescriptor(iterator->second, targetPageId);
        const bool includePdfLayer = targetDescriptor != nullptr && IsPdfPageKind(targetDescriptor->pageKind);
        const bool includeInkLayer = includePdfLayer;
        const size_t objectCount = includePdfLayer ? 1 : 0;

        std::ostringstream builder;
        builder << "{"
                ;
        AppendCanonicalPreviewFields(builder, engineId, documentId, targetPageId, targetPageIndex, width, height,
            iterator->second.checkpointCount, 0, 0, objectCount, engine->activeMode, iterator->second, reportedPageIds,
            includePdfLayer, includeInkLayer);
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
        const std::string activePageId = ResolveSessionActivePageId(iterator->second);
        const int activePageIndex = std::max(0, FindPageIndex(reportedPageIds, activePageId));
        const SimulatorPageDescriptor* activeDescriptor = FindPageDescriptor(iterator->second, activePageId);
        const bool includePdfPlaceholder = activeDescriptor != nullptr && IsPdfPageKind(activeDescriptor->pageKind);
        const size_t objectCount = includePdfPlaceholder ? 1 : 0;
        std::ostringstream builder;
        builder << "{"
                ;
        AppendCanonicalSceneFields(builder, engine->engineId, iterator->second.documentId,
            ExtractJsonStringValue(iterator->second.openConfigJson, "title", ""),
            ExtractJsonStringValue(iterator->second.openConfigJson, "documentType", "blank"),
            engine->activeMode, engine->activeBackend, iterator->second.checkpointCount, objectCount,
            iterator->second, reportedPageIds);
        builder << ",\"objects\":[";
        if (includePdfPlaceholder) {
            const std::string placeholderId = IsFullPagePdfKind(activeDescriptor->pageKind)
                ? std::string(kPdfPageNodeIdPrefix) + std::to_string(activePageIndex)
                : std::string(kPdfFragmentNodeIdPrefix) + std::to_string(activePageIndex);
            builder << "{"
                    << "\"id\":\"" << EscapeJsonString(placeholderId) << "\","
                    << "\"nodeType\":\"" << (IsFullPagePdfKind(activeDescriptor->pageKind) ? "pdf-page" : "pdf-fragment") << "\","
                    << "\"shapeType\":\"page\","
                    << "\"tool\":\"pdf\","
                    << "\"colorHex\":\"#FFFFFF\","
                    << "\"selected\":false,"
                    << "\"pointCount\":0,"
                    << "\"pageIndex\":" << activePageIndex << ","
                    << "\"pageId\":\"" << EscapeJsonString(activePageId) << "\","
                    << "\"closed\":true,";
            AppendPageBounds(builder, activeDescriptor);
            builder << ",\"layer\":\"pdf\"";
            builder << "}";
        }
        builder << "]}";
        return builder.str();
    }

    std::string ReadPdfPageCount(const std::string& pdfPath) override
    {
        return ReadPdfPageCountFromFile(pdfPath);
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
        if (iterator == engine->documents.end() || !SupportsBlankPageMutation(*engine, iterator->second)) {
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
        SimulatorPageDescriptor newDescriptor;
        newDescriptor.pageId = newPageId;
        newDescriptor.pageKind = "blank";
        newDescriptor.contract = ParsePageContractDescriptor(pageConfigJson);
        const int insertIndex = static_cast<int>(std::distance(iterator->second.pages.begin(), afterIterator + 1));
        iterator->second.pages.insert(afterIterator + 1, newPageId);
        auto afterDescriptorIterator = std::find_if(iterator->second.pageDescriptors.begin(),
            iterator->second.pageDescriptors.end(), [&](const SimulatorPageDescriptor& descriptor) {
                return descriptor.pageId == afterPageId;
            });
        if (afterDescriptorIterator != iterator->second.pageDescriptors.end()) {
            iterator->second.pageDescriptors.insert(afterDescriptorIterator + 1, newDescriptor);
        } else if (insertIndex >= 0 && insertIndex <= static_cast<int>(iterator->second.pageDescriptors.size())) {
            iterator->second.pageDescriptors.insert(iterator->second.pageDescriptors.begin() + insertIndex, newDescriptor);
        } else {
            iterator->second.pageDescriptors.push_back(newDescriptor);
        }
        ReindexPageDescriptors(iterator->second);
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
        if (iterator == engine->documents.end() || !SupportsBlankPageMutation(*engine, iterator->second)) {
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
        iterator->second.pageDescriptors.erase(std::remove_if(iterator->second.pageDescriptors.begin(),
            iterator->second.pageDescriptors.end(), [&](const SimulatorPageDescriptor& descriptor) {
                return descriptor.pageId == pageId;
            }), iterator->second.pageDescriptors.end());
        ReindexPageDescriptors(iterator->second);
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
