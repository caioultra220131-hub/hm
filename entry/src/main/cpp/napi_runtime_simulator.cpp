#include "note_engine_runtime.h"

#include "hilog/log.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cmath>
#include <fstream>
#include <limits>
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
constexpr const char* kSimulatorPlaceholderSurfaceId = "simulator-placeholder-surface";
constexpr const char* kPrimaryPageId = "page-0";
constexpr const char* kLegacyCoordinateSpace = "legacy-surface";
constexpr const char* kStatsFallbackTargetMode = "stats-fallback";
constexpr const char* kPdfPageNodeIdPrefix = "pdf-page-";
constexpr const char* kPdfFragmentNodeIdPrefix = "pdf-fragment-";
constexpr int kPreviewSchemaVersion = 0;
constexpr int kPrimaryPageIndex = 0;
constexpr double kPi = 3.14159265358979323846;
constexpr double kDefaultBrushWidth = 3.2;
constexpr double kFallbackPageWidthPt = 612.0;
constexpr double kFallbackPageHeightPt = 792.0;
constexpr double kMinSyntheticStrokeWidthPt = 96.0;
constexpr double kMinSyntheticStrokeHeightPt = 42.0;
constexpr const char* kSimulatorStrokeStateFileName = "simulator-strokes.json";
constexpr const char* kPngPreviewMimeType = "image/png";
constexpr double kSimulatorPredictionMinSpeedPtPerMs = 0.08;
constexpr int64_t kSimulatorPredictionStableHorizonsMs[2] = { 4, 8 };
constexpr int64_t kSimulatorPredictionUnstableHorizonsMs[2] = { 2, 4 };
constexpr double kSimulatorPredictionStableMaxDistancePt = 26.0;
constexpr double kSimulatorPredictionUnstableMaxDistancePt = 12.0;
constexpr double kSimulatorPredictionMinSegmentDtMs = 2.0;
constexpr double kSimulatorPredictionMaxSegmentDtMs = 10.0;
constexpr double kSimulatorPredictionMaxSegmentDistancePt = 22.0;
constexpr double kSimulatorPredictionSpeedJumpThreshold = 2.2;
constexpr double kSimulatorPredictionAngleThresholdDegrees = 55.0;
constexpr double kSimulatorPredictionRollbackDistancePt = 6.0;
constexpr double kSimulatorPredictionRollbackBlend = 0.35;
constexpr int64_t kSimulatorPredictionCpuSampleIntervalMs = 750;
constexpr int64_t kSimulatorPredictionCpuCooldownMs = 1500;
constexpr double kSimulatorPredictionCpuBusyThreshold = 0.82;

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

struct SimulatorStrokePoint {
    double x = 0.0;
    double y = 0.0;
    int64_t timeMs = 0;
};

struct SimulatorSyntheticObject {
    std::string id;
    std::string pageId;
    std::string nodeType = "ink-stroke";
    std::string shapeType = "freehand";
    std::string tool = "pen";
    std::string colorHex = "#1D2736";
    double strokeWidth = kDefaultBrushWidth;
    bool closed = false;
    size_t pointCount = 0;
    double minX = 0.0;
    double minY = 0.0;
    double maxX = 0.0;
    double maxY = 0.0;
    std::vector<SimulatorStrokePoint> strokePoints;
};

struct SimulatorSyntheticEdit {
    std::string pageId;
    SimulatorSyntheticObject object;
};

struct SimulatorDocumentSession {
    std::string documentId;
    std::string packagePath;
    std::string openConfigJson;
    int checkpointCount = 0;
    bool hasUnpersistedSyntheticMutation = false;
    bool pageAware = false;
    std::vector<std::string> pages;
    std::vector<SimulatorPageDescriptor> pageDescriptors;
    std::string activePageId;
    int nextSyntheticObjectId = 1;
    std::unordered_map<std::string, std::vector<SimulatorSyntheticObject>> committedObjectsByPage;
    std::vector<SimulatorSyntheticEdit> undoStack;
    std::vector<SimulatorSyntheticEdit> redoStack;
};

struct SimulatorEngineState {
    std::string engineId;
    std::string configJson;
    std::string activeDocumentId;
    std::string activeTool = "pen";
    std::string activeBackend = "opengles";
    std::string activeMode = "paged";
    std::string activeColor = "#1D2736";
    double activeBrushWidth = kDefaultBrushWidth;
    bool fingerWritingEnabled = false;
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
    int touchEventCount = 0;
    int uiTouchEventCount = 0;
    int keyEventCount = 0;
    int stylusEventCount = 0;
    int fingerEventCount = 0;
    int palmRejectedCount = 0;
    int activePointerCount = 0;
    bool stylusActive = false;
    bool multitouchGestureActive = false;
    size_t lastHistoricalCount = 0;
    size_t lastUiHistoryCount = 0;
    size_t predictedPointCount = 0;
    int64_t lastEventTime = 0;
    int64_t lastKeyEventTime = 0;
    int32_t lastKeyCode = -1;
    int32_t lastKeyAction = -1;
    int32_t lastKeySourceType = -1;
    double lastPressure = 0.0;
    double lastTiltX = 0.0;
    double lastTiltY = 0.0;
    double lastRollAngle = 0.0;
    std::string lastTouchAction = "unknown";
    std::string lastToolType = "unknown";
    std::string lastSourceType = "unknown";
    bool simulatorFingerStrokeActive = false;
    double simulatorFingerStrokeStartXRatio = 0.5;
    double simulatorFingerStrokeStartYRatio = 0.5;
    double simulatorFingerStrokeLastXRatio = 0.5;
    double simulatorFingerStrokeLastYRatio = 0.5;
    std::vector<SimulatorStrokePoint> simulatorFingerStrokeRatios;
    std::vector<SimulatorStrokePoint> simulatorPredictedStrokeRatios;
    std::vector<SimulatorStrokePoint> simulatorPreviousPredictedStrokeRatios;
    uint64_t predictionLastCpuTotalTicks = 0;
    uint64_t predictionLastCpuIdleTicks = 0;
    int64_t predictionLastCpuSampleTimeMs = 0;
    int64_t predictionSuppressedUntilMs = 0;
    double predictionCpuBusyRatio = 0.0;
    std::unordered_map<std::string, SimulatorDocumentSession> documents;
};

int64_t CurrentTimeMillis()
{
    const auto now = std::chrono::time_point_cast<std::chrono::milliseconds>(std::chrono::system_clock::now());
    return now.time_since_epoch().count();
}

double ClampUnitRatio(double value)
{
    if (value < 0.0) {
        return 0.0;
    }
    if (value > 1.0) {
        return 1.0;
    }
    return value == value ? value : 0.5;
}

double NormalizeBrushWidth(double width)
{
    return std::isfinite(width) && width > 0.0 ? width : kDefaultBrushWidth;
}

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
const std::vector<SimulatorSyntheticObject>* FindCommittedObjectsForPage(
    const SimulatorDocumentSession& session, const std::string& pageId);

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

std::string ReadBinaryFile(const std::string& path, std::string& contents);

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

double ResolvePageWidth(const SimulatorPageDescriptor* descriptor)
{
    return HasPageBounds(descriptor) ? descriptor->contract.widthPt : kFallbackPageWidthPt;
}

double ResolvePageHeight(const SimulatorPageDescriptor* descriptor)
{
    return HasPageBounds(descriptor) ? descriptor->contract.heightPt : kFallbackPageHeightPt;
}

struct PredictionVec2 {
    double x = 0.0;
    double y = 0.0;
};

double PredictionVecLength(const PredictionVec2& value)
{
    return std::hypot(value.x, value.y);
}

PredictionVec2 ScalePredictionVec(const PredictionVec2& value, double scale)
{
    return { value.x * scale, value.y * scale };
}

PredictionVec2 AddPredictionVec(const PredictionVec2& left, const PredictionVec2& right)
{
    return { left.x + right.x, left.y + right.y };
}

PredictionVec2 NormalizePredictionVec(const PredictionVec2& value)
{
    const double length = PredictionVecLength(value);
    if (length <= std::numeric_limits<double>::epsilon()) {
        return {};
    }
    return ScalePredictionVec(value, 1.0 / length);
}

double DotPredictionVec(const PredictionVec2& left, const PredictionVec2& right)
{
    return left.x * right.x + left.y * right.y;
}

PredictionVec2 ClampPredictionVecLength(const PredictionVec2& value, double maxLength)
{
    const double length = PredictionVecLength(value);
    if (length <= maxLength || length <= std::numeric_limits<double>::epsilon()) {
        return value;
    }
    return ScalePredictionVec(value, maxLength / length);
}

PredictionVec2 StrokePointToPageVec(const SimulatorStrokePoint& point, double pageWidth, double pageHeight)
{
    return { ClampUnitRatio(point.x) * pageWidth, ClampUnitRatio(point.y) * pageHeight };
}

bool TryReadSystemCpuTicks(uint64_t& totalTicks, uint64_t& idleTicks)
{
    std::ifstream file("/proc/stat");
    if (!file.is_open()) {
        return false;
    }
    std::string cpuLabel;
    uint64_t user = 0;
    uint64_t nice = 0;
    uint64_t system = 0;
    uint64_t idle = 0;
    uint64_t iowait = 0;
    uint64_t irq = 0;
    uint64_t softirq = 0;
    uint64_t steal = 0;
    uint64_t guest = 0;
    uint64_t guestNice = 0;
    file >> cpuLabel >> user >> nice >> system >> idle >> iowait >> irq >> softirq >> steal >> guest >> guestNice;
    if (cpuLabel != "cpu") {
        return false;
    }
    idleTicks = idle + iowait;
    totalTicks = user + nice + system + idle + iowait + irq + softirq + steal + guest + guestNice;
    return totalTicks > 0;
}

void ResetSimulatorPrediction(SimulatorEngineState& engine)
{
    engine.simulatorPredictedStrokeRatios.clear();
    engine.simulatorPreviousPredictedStrokeRatios.clear();
    engine.predictedPointCount = 0;
}

bool UpdateSimulatorPredictionCpuBudget(SimulatorEngineState& engine, int64_t nowMs)
{
    if (nowMs - engine.predictionLastCpuSampleTimeMs < kSimulatorPredictionCpuSampleIntervalMs) {
        return nowMs < engine.predictionSuppressedUntilMs;
    }
    uint64_t totalTicks = 0;
    uint64_t idleTicks = 0;
    if (!TryReadSystemCpuTicks(totalTicks, idleTicks)) {
        return nowMs < engine.predictionSuppressedUntilMs;
    }
    if (engine.predictionLastCpuTotalTicks > 0 && totalTicks > engine.predictionLastCpuTotalTicks) {
        const uint64_t totalDelta = totalTicks - engine.predictionLastCpuTotalTicks;
        const uint64_t idleDelta = idleTicks - engine.predictionLastCpuIdleTicks;
        if (totalDelta > 0) {
            const double idleRatio = static_cast<double>(std::min(idleDelta, totalDelta)) /
                static_cast<double>(totalDelta);
            engine.predictionCpuBusyRatio = std::clamp(1.0 - idleRatio, 0.0, 1.0);
            if (engine.predictionCpuBusyRatio >= kSimulatorPredictionCpuBusyThreshold) {
                engine.predictionSuppressedUntilMs = nowMs + kSimulatorPredictionCpuCooldownMs;
            }
        }
    }
    engine.predictionLastCpuTotalTicks = totalTicks;
    engine.predictionLastCpuIdleTicks = idleTicks;
    engine.predictionLastCpuSampleTimeMs = nowMs;
    return nowMs < engine.predictionSuppressedUntilMs;
}

std::vector<SimulatorStrokePoint> BuildSimulatorPredictionTail(
    const std::vector<SimulatorStrokePoint>& realSamples,
    double pageWidth,
    double pageHeight,
    const std::vector<SimulatorStrokePoint>& previousPredictedSamples)
{
    if (realSamples.size() < 2 || pageWidth <= 0.0 || pageHeight <= 0.0) {
        return {};
    }

    struct VelocitySample {
        PredictionVec2 velocity;
        double speed = 0.0;
    };

    const SimulatorStrokePoint& last = realSamples.back();
    std::vector<VelocitySample> segments;
    segments.reserve(3);

    for (size_t index = realSamples.size() - 1; index > 0 && segments.size() < 3; --index) {
        const SimulatorStrokePoint& end = realSamples[index];
        const SimulatorStrokePoint& start = realSamples[index - 1];
        const double deltaTimeMs = std::clamp(
            static_cast<double>(end.timeMs - start.timeMs),
            kSimulatorPredictionMinSegmentDtMs,
            kSimulatorPredictionMaxSegmentDtMs);
        PredictionVec2 delta = {
            (ClampUnitRatio(end.x) - ClampUnitRatio(start.x)) * pageWidth,
            (ClampUnitRatio(end.y) - ClampUnitRatio(start.y)) * pageHeight
        };
        delta = ClampPredictionVecLength(delta, kSimulatorPredictionMaxSegmentDistancePt);
        const PredictionVec2 velocity = ScalePredictionVec(delta, 1.0 / deltaTimeMs);
        const double speed = PredictionVecLength(velocity);
        if (speed < kSimulatorPredictionMinSpeedPtPerMs) {
            continue;
        }
        segments.push_back({ velocity, speed });
    }

    if (segments.empty()) {
        return {};
    }

    static constexpr double kVelocityWeights[3] = { 0.55, 0.30, 0.15 };
    PredictionVec2 fusedVelocity {};
    double totalWeight = 0.0;
    for (size_t index = 0; index < segments.size(); ++index) {
        fusedVelocity = AddPredictionVec(fusedVelocity, ScalePredictionVec(segments[index].velocity, kVelocityWeights[index]));
        totalWeight += kVelocityWeights[index];
    }
    if (totalWeight > 0.0) {
        fusedVelocity = ScalePredictionVec(fusedVelocity, 1.0 / totalWeight);
    }

    const double fusedSpeed = PredictionVecLength(fusedVelocity);
    if (fusedSpeed < kSimulatorPredictionMinSpeedPtPerMs) {
        return {};
    }

    bool unstable = false;
    if (segments.size() >= 2) {
        const PredictionVec2 newestDirection = NormalizePredictionVec(segments[0].velocity);
        const PredictionVec2 olderDirection = NormalizePredictionVec(segments[1].velocity);
        if (PredictionVecLength(newestDirection) > 0.0 && PredictionVecLength(olderDirection) > 0.0) {
            const double cosine = std::clamp(DotPredictionVec(newestDirection, olderDirection), -1.0, 1.0);
            const double angleDegrees = std::acos(cosine) * (180.0 / kPi);
            unstable = angleDegrees > kSimulatorPredictionAngleThresholdDegrees;
        }
        if (!unstable && segments[1].speed > kSimulatorPredictionMinSpeedPtPerMs) {
            const double speedRatio = std::max(segments[0].speed, segments[1].speed) /
                std::max(kSimulatorPredictionMinSpeedPtPerMs, std::min(segments[0].speed, segments[1].speed));
            unstable = speedRatio > kSimulatorPredictionSpeedJumpThreshold;
        }
    }

    const int64_t* horizons = unstable ? kSimulatorPredictionUnstableHorizonsMs : kSimulatorPredictionStableHorizonsMs;
    const double maxDistance = unstable ? kSimulatorPredictionUnstableMaxDistancePt : kSimulatorPredictionStableMaxDistancePt;
    const PredictionVec2 lastPagePosition = StrokePointToPageVec(last, pageWidth, pageHeight);
    auto createPredictedPoint = [&](int64_t horizonMs) {
        PredictionVec2 offset = ScalePredictionVec(fusedVelocity, static_cast<double>(horizonMs));
        offset = ClampPredictionVecLength(offset, maxDistance);
        if (unstable) {
            offset = ScalePredictionVec(offset, 0.65);
        }
        const PredictionVec2 predictedPagePosition = AddPredictionVec(lastPagePosition, offset);
        return SimulatorStrokePoint {
            ClampUnitRatio(predictedPagePosition.x / pageWidth),
            ClampUnitRatio(predictedPagePosition.y / pageHeight),
            last.timeMs + horizonMs
        };
    };

    std::vector<SimulatorStrokePoint> nextTail = {
        createPredictedPoint(horizons[0]),
        createPredictedPoint(horizons[1])
    };

    if (previousPredictedSamples.empty()) {
        return nextTail;
    }

    const size_t limit = std::min(nextTail.size(), previousPredictedSamples.size());
    for (size_t index = 0; index < limit; ++index) {
        PredictionVec2 blendSource = StrokePointToPageVec(previousPredictedSamples[index], pageWidth, pageHeight);
        if (unstable) {
            const PredictionVec2 unstableTarget = StrokePointToPageVec(last, pageWidth, pageHeight);
            blendSource = AddPredictionVec(
                ScalePredictionVec(unstableTarget, 0.55),
                ScalePredictionVec(blendSource, 0.45));
        }
        const PredictionVec2 nextTarget = StrokePointToPageVec(nextTail[index], pageWidth, pageHeight);
        const double distance = PredictionVecLength({
            nextTarget.x - blendSource.x,
            nextTarget.y - blendSource.y
        });
        if (distance > kSimulatorPredictionRollbackDistancePt) {
            const PredictionVec2 blended = AddPredictionVec(
                ScalePredictionVec(blendSource, 1.0 - kSimulatorPredictionRollbackBlend),
                ScalePredictionVec(nextTarget, kSimulatorPredictionRollbackBlend));
            nextTail[index].x = ClampUnitRatio(blended.x / pageWidth);
            nextTail[index].y = ClampUnitRatio(blended.y / pageHeight);
        }
    }

    return nextTail;
}

void UpdateSimulatorPrediction(
    SimulatorEngineState& engine,
    const SimulatorPageDescriptor* descriptor)
{
    engine.simulatorPredictedStrokeRatios.clear();
    engine.predictedPointCount = 0;
    if (!engine.predictionEnabled || !engine.fingerWritingEnabled || !engine.simulatorFingerStrokeActive ||
        descriptor == nullptr) {
        engine.simulatorPreviousPredictedStrokeRatios.clear();
        return;
    }
    const int64_t nowMs = CurrentTimeMillis();
    if (UpdateSimulatorPredictionCpuBudget(engine, nowMs)) {
        engine.simulatorPreviousPredictedStrokeRatios.clear();
        return;
    }
    engine.simulatorPredictedStrokeRatios = BuildSimulatorPredictionTail(
        engine.simulatorFingerStrokeRatios,
        ResolvePageWidth(descriptor),
        ResolvePageHeight(descriptor),
        engine.simulatorPreviousPredictedStrokeRatios);
    engine.predictedPointCount = engine.simulatorPredictedStrokeRatios.size();
    engine.simulatorPreviousPredictedStrokeRatios = engine.simulatorPredictedStrokeRatios;
}

std::string ResolveSyntheticTool(const SimulatorEngineState& engine)
{
    if (engine.activeTool == "pen" ||
        engine.activeTool == "pencil" ||
        engine.activeTool == "highlighter" ||
        engine.activeTool == "text") {
        return engine.activeTool;
    }
    return engine.lastInkTool;
}

std::string ResolveSyntheticShapeType(const std::string& tool)
{
    if (tool == "highlighter") {
        return "highlight-stroke";
    }
    if (tool == "text") {
        return "text-box";
    }
    return "freehand";
}

std::string ResolveSyntheticNodeType(const std::string& tool)
{
    if (tool == "text") {
        return "text-note";
    }
    return "ink-stroke";
}

size_t ResolveSyntheticPointCount(const std::string& tool, int ordinal)
{
    if (tool == "text") {
        return 4;
    }
    if (tool == "highlighter") {
        return static_cast<size_t>(10 + (ordinal % 3) * 2);
    }
    return static_cast<size_t>(16 + (ordinal % 4) * 3);
}

double ResolveSyntheticBrushScale(const SimulatorEngineState& engine)
{
    return std::clamp(NormalizeBrushWidth(engine.activeBrushWidth) / kDefaultBrushWidth, 0.35, 4.0);
}

double LerpDouble(double start, double end, double t)
{
    return start + (end - start) * t;
}

std::vector<SimulatorStrokePoint> BuildSyntheticStrokePointsFromBounds(
    double minX, double minY, double maxX, double maxY, size_t pointCount, int ordinal)
{
    const size_t resolvedPointCount = std::max<size_t>(4, pointCount);
    const double width = std::max(1.0, maxX - minX);
    const double height = std::max(1.0, maxY - minY);
    const double centerY = minY + height * 0.5;
    const double primaryAmplitude = std::max(2.0, height * 0.28);
    const double secondaryAmplitude = std::max(1.0, height * 0.10);
    std::vector<SimulatorStrokePoint> points;
    points.reserve(resolvedPointCount);
    for (size_t index = 0; index < resolvedPointCount; ++index) {
        const double t = resolvedPointCount <= 1 ? 0.0 : static_cast<double>(index) / static_cast<double>(resolvedPointCount - 1);
        const double x = minX + width * t;
        const double wave = std::sin((t * 1.4 + ordinal * 0.11) * kPi);
        const double bend = std::sin((t * 2.2 + ordinal * 0.07) * kPi);
        const double y = std::clamp(
            centerY + wave * primaryAmplitude + bend * secondaryAmplitude,
            minY,
            maxY);
        points.push_back({ x, y });
    }
    return points;
}

std::vector<SimulatorStrokePoint> BuildHighlighterStrokePointsFromBounds(
    double minX, double minY, double maxX, double maxY, int ordinal)
{
    const double height = std::max(1.0, maxY - minY);
    const double centerY = minY + height * 0.5 + std::sin(ordinal * 0.17) * height * 0.08;
    return {
        { minX, centerY - height * 0.08 },
        { LerpDouble(minX, maxX, 0.32), centerY + height * 0.06 },
        { LerpDouble(minX, maxX, 0.68), centerY - height * 0.04 },
        { maxX, centerY + height * 0.05 }
    };
}

std::vector<SimulatorStrokePoint> BuildTextBoxStrokePointsFromBounds(
    double minX, double minY, double maxX, double maxY)
{
    return {
        { minX, minY },
        { maxX, minY },
        { maxX, maxY },
        { minX, maxY },
        { minX, minY }
    };
}

std::vector<SimulatorStrokePoint> BuildGestureStrokePoints(
    double startX, double startY, double endX, double endY, size_t pointCount, int ordinal)
{
    const size_t resolvedPointCount = std::max<size_t>(4, pointCount);
    const double deltaX = endX - startX;
    const double deltaY = endY - startY;
    const double length = std::hypot(deltaX, deltaY);
    const double normalX = length > 0.001 ? -deltaY / length : 0.0;
    const double normalY = length > 0.001 ? deltaX / length : 1.0;
    const double arc = std::max(6.0, length * 0.08) * ((ordinal % 2 == 0) ? 1.0 : -1.0);
    std::vector<SimulatorStrokePoint> points;
    points.reserve(resolvedPointCount);
    for (size_t index = 0; index < resolvedPointCount; ++index) {
        const double t = resolvedPointCount <= 1 ? 0.0 : static_cast<double>(index) / static_cast<double>(resolvedPointCount - 1);
        const double influence = std::sin(t * kPi);
        points.push_back({
            LerpDouble(startX, endX, t) + normalX * arc * influence,
            LerpDouble(startY, endY, t) + normalY * arc * influence
        });
    }
    return points;
}

void UpdateSyntheticBoundsFromStrokePoints(SimulatorSyntheticObject& object,
    const SimulatorPageDescriptor* descriptor, double brushWidth)
{
    if (object.strokePoints.empty()) {
        return;
    }
    const double pageWidth = ResolvePageWidth(descriptor);
    const double pageHeight = ResolvePageHeight(descriptor);
    double minX = object.strokePoints.front().x;
    double minY = object.strokePoints.front().y;
    double maxX = object.strokePoints.front().x;
    double maxY = object.strokePoints.front().y;
    for (const SimulatorStrokePoint& point : object.strokePoints) {
        minX = std::min(minX, point.x);
        minY = std::min(minY, point.y);
        maxX = std::max(maxX, point.x);
        maxY = std::max(maxY, point.y);
    }
    const double padding = std::max(brushWidth * 0.75, 1.5);
    object.minX = std::clamp(minX - padding, 0.0, pageWidth);
    object.minY = std::clamp(minY - padding, 0.0, pageHeight);
    object.maxX = std::clamp(maxX + padding, 0.0, pageWidth);
    object.maxY = std::clamp(maxY + padding, 0.0, pageHeight);
}

std::string EncodeBase64(const std::string& value)
{
    static constexpr char kAlphabet[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string encoded;
    encoded.reserve(((value.size() + 2) / 3) * 4);
    size_t index = 0;
    while (index + 3 <= value.size()) {
        const unsigned int chunk =
            (static_cast<unsigned char>(value[index]) << 16) |
            (static_cast<unsigned char>(value[index + 1]) << 8) |
            static_cast<unsigned char>(value[index + 2]);
        encoded.push_back(kAlphabet[(chunk >> 18) & 0x3F]);
        encoded.push_back(kAlphabet[(chunk >> 12) & 0x3F]);
        encoded.push_back(kAlphabet[(chunk >> 6) & 0x3F]);
        encoded.push_back(kAlphabet[chunk & 0x3F]);
        index += 3;
    }
    const size_t remaining = value.size() - index;
    if (remaining == 1) {
        const unsigned int chunk = static_cast<unsigned char>(value[index]) << 16;
        encoded.push_back(kAlphabet[(chunk >> 18) & 0x3F]);
        encoded.push_back(kAlphabet[(chunk >> 12) & 0x3F]);
        encoded.push_back('=');
        encoded.push_back('=');
    } else if (remaining == 2) {
        const unsigned int chunk =
            (static_cast<unsigned char>(value[index]) << 16) |
            (static_cast<unsigned char>(value[index + 1]) << 8);
        encoded.push_back(kAlphabet[(chunk >> 18) & 0x3F]);
        encoded.push_back(kAlphabet[(chunk >> 12) & 0x3F]);
        encoded.push_back(kAlphabet[(chunk >> 6) & 0x3F]);
        encoded.push_back('=');
    }
    return encoded;
}

double ResolvePreviewStrokeOpacity(const SimulatorSyntheticObject& object)
{
    if (object.tool == "highlighter") {
        return 0.24;
    }
    if (object.tool == "pencil") {
        return 0.88;
    }
    return 1.0;
}

struct PreviewRasterColor {
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
    uint8_t a = 255;
};

int ParseHexNibble(char value)
{
    if (value >= '0' && value <= '9') {
        return value - '0';
    }
    if (value >= 'a' && value <= 'f') {
        return 10 + (value - 'a');
    }
    if (value >= 'A' && value <= 'F') {
        return 10 + (value - 'A');
    }
    return -1;
}

PreviewRasterColor ParsePreviewColor(const std::string& colorHex, uint8_t alpha = 255)
{
    PreviewRasterColor fallback { 0x1D, 0x27, 0x36, alpha };
    size_t start = 0;
    if (!colorHex.empty() && colorHex.front() == '#') {
        start = 1;
    }
    if (colorHex.size() - start < 6) {
        return fallback;
    }
    const int r1 = ParseHexNibble(colorHex[start]);
    const int r2 = ParseHexNibble(colorHex[start + 1]);
    const int g1 = ParseHexNibble(colorHex[start + 2]);
    const int g2 = ParseHexNibble(colorHex[start + 3]);
    const int b1 = ParseHexNibble(colorHex[start + 4]);
    const int b2 = ParseHexNibble(colorHex[start + 5]);
    if (r1 < 0 || r2 < 0 || g1 < 0 || g2 < 0 || b1 < 0 || b2 < 0) {
        return fallback;
    }
    return PreviewRasterColor {
        static_cast<uint8_t>((r1 << 4) | r2),
        static_cast<uint8_t>((g1 << 4) | g2),
        static_cast<uint8_t>((b1 << 4) | b2),
        alpha
    };
}

int ScalePreviewCoordinate(double value, double maxValue, int rasterSize)
{
    if (rasterSize <= 1 || maxValue <= 0.0) {
        return 0;
    }
    const double ratio = std::clamp(value / maxValue, 0.0, 1.0);
    return static_cast<int>(std::lround(ratio * static_cast<double>(rasterSize - 1)));
}

void BlendPreviewPixel(std::vector<uint8_t>& pixels, int rasterWidth, int rasterHeight,
    int x, int y, const PreviewRasterColor& color, double opacity)
{
    if (x < 0 || y < 0 || x >= rasterWidth || y >= rasterHeight) {
        return;
    }
    const double alpha = std::clamp(opacity, 0.0, 1.0) * (static_cast<double>(color.a) / 255.0);
    if (alpha <= 0.0) {
        return;
    }
    const size_t offset = (static_cast<size_t>(y) * static_cast<size_t>(rasterWidth) + static_cast<size_t>(x)) * 4;
    pixels[offset] = static_cast<uint8_t>(std::clamp(
        std::lround(static_cast<double>(color.r) * alpha + static_cast<double>(pixels[offset]) * (1.0 - alpha)),
        0l, 255l));
    pixels[offset + 1] = static_cast<uint8_t>(std::clamp(
        std::lround(static_cast<double>(color.g) * alpha + static_cast<double>(pixels[offset + 1]) * (1.0 - alpha)),
        0l, 255l));
    pixels[offset + 2] = static_cast<uint8_t>(std::clamp(
        std::lround(static_cast<double>(color.b) * alpha + static_cast<double>(pixels[offset + 2]) * (1.0 - alpha)),
        0l, 255l));
    pixels[offset + 3] = 255;
}

void FillPreviewRect(std::vector<uint8_t>& pixels, int rasterWidth, int rasterHeight,
    int minX, int minY, int maxX, int maxY, const PreviewRasterColor& color, double opacity)
{
    const int clampedMinX = std::clamp(std::min(minX, maxX), 0, rasterWidth);
    const int clampedMaxX = std::clamp(std::max(minX, maxX), 0, rasterWidth);
    const int clampedMinY = std::clamp(std::min(minY, maxY), 0, rasterHeight);
    const int clampedMaxY = std::clamp(std::max(minY, maxY), 0, rasterHeight);
    for (int y = clampedMinY; y < clampedMaxY; ++y) {
        for (int x = clampedMinX; x < clampedMaxX; ++x) {
            BlendPreviewPixel(pixels, rasterWidth, rasterHeight, x, y, color, opacity);
        }
    }
}

void DrawPreviewDisc(std::vector<uint8_t>& pixels, int rasterWidth, int rasterHeight,
    double centerX, double centerY, double radius, const PreviewRasterColor& color, double opacity)
{
    const int minX = static_cast<int>(std::floor(centerX - radius));
    const int maxX = static_cast<int>(std::ceil(centerX + radius));
    const int minY = static_cast<int>(std::floor(centerY - radius));
    const int maxY = static_cast<int>(std::ceil(centerY + radius));
    const double radiusSquared = radius * radius;
    for (int y = minY; y <= maxY; ++y) {
        for (int x = minX; x <= maxX; ++x) {
            const double deltaX = (static_cast<double>(x) + 0.5) - centerX;
            const double deltaY = (static_cast<double>(y) + 0.5) - centerY;
            if ((deltaX * deltaX) + (deltaY * deltaY) <= radiusSquared) {
                BlendPreviewPixel(pixels, rasterWidth, rasterHeight, x, y, color, opacity);
            }
        }
    }
}

void DrawPreviewSegment(std::vector<uint8_t>& pixels, int rasterWidth, int rasterHeight,
    double startX, double startY, double endX, double endY, double radius,
    const PreviewRasterColor& color, double opacity)
{
    const double deltaX = endX - startX;
    const double deltaY = endY - startY;
    const int steps = std::max(1, static_cast<int>(std::ceil(std::max(std::abs(deltaX), std::abs(deltaY)) * 1.5)));
    for (int step = 0; step <= steps; ++step) {
        const double t = steps <= 0 ? 0.0 : static_cast<double>(step) / static_cast<double>(steps);
        DrawPreviewDisc(
            pixels,
            rasterWidth,
            rasterHeight,
            LerpDouble(startX, endX, t),
            LerpDouble(startY, endY, t),
            radius,
            color,
            opacity);
    }
}

void DrawPreviewRectOutline(std::vector<uint8_t>& pixels, int rasterWidth, int rasterHeight,
    int minX, int minY, int maxX, int maxY, int thickness,
    const PreviewRasterColor& color, double opacity)
{
    const int resolvedThickness = std::max(1, thickness);
    FillPreviewRect(pixels, rasterWidth, rasterHeight, minX, minY, maxX, minY + resolvedThickness, color, opacity);
    FillPreviewRect(pixels, rasterWidth, rasterHeight, minX, maxY - resolvedThickness, maxX, maxY, color, opacity);
    FillPreviewRect(pixels, rasterWidth, rasterHeight, minX, minY, minX + resolvedThickness, maxY, color, opacity);
    FillPreviewRect(pixels, rasterWidth, rasterHeight, maxX - resolvedThickness, minY, maxX, maxY, color, opacity);
}

void RasterizePreviewObject(std::vector<uint8_t>& pixels, int rasterWidth, int rasterHeight,
    double pageWidth, double pageHeight, const SimulatorSyntheticObject& object)
{
    const double scaleX = pageWidth > 0.0 ? static_cast<double>(rasterWidth) / pageWidth : 1.0;
    const double scaleY = pageHeight > 0.0 ? static_cast<double>(rasterHeight) / pageHeight : 1.0;
    const double strokeScale = std::max(0.5, (scaleX + scaleY) * 0.5);
    const double radius = std::max(0.75, NormalizeBrushWidth(object.strokeWidth) * strokeScale * 0.5);
    const PreviewRasterColor color = ParsePreviewColor(object.colorHex);
    const double opacity = ResolvePreviewStrokeOpacity(object);

    if (object.tool == "text") {
        const int minX = ScalePreviewCoordinate(object.minX, pageWidth, rasterWidth);
        const int minY = ScalePreviewCoordinate(object.minY, pageHeight, rasterHeight);
        const int maxX = ScalePreviewCoordinate(object.maxX, pageWidth, rasterWidth) + 1;
        const int maxY = ScalePreviewCoordinate(object.maxY, pageHeight, rasterHeight) + 1;
        DrawPreviewRectOutline(
            pixels,
            rasterWidth,
            rasterHeight,
            minX,
            minY,
            maxX,
            maxY,
            std::max(1, static_cast<int>(std::lround(radius))),
            color,
            opacity);
        return;
    }

    if (object.strokePoints.empty()) {
        DrawPreviewDisc(
            pixels,
            rasterWidth,
            rasterHeight,
            static_cast<double>(ScalePreviewCoordinate((object.minX + object.maxX) * 0.5, pageWidth, rasterWidth)),
            static_cast<double>(ScalePreviewCoordinate((object.minY + object.maxY) * 0.5, pageHeight, rasterHeight)),
            radius,
            color,
            opacity);
        return;
    }

    for (size_t index = 1; index < object.strokePoints.size(); ++index) {
        DrawPreviewSegment(
            pixels,
            rasterWidth,
            rasterHeight,
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints[index - 1].x, pageWidth, rasterWidth)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints[index - 1].y, pageHeight, rasterHeight)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints[index].x, pageWidth, rasterWidth)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints[index].y, pageHeight, rasterHeight)),
            radius,
            color,
            opacity);
    }
    if (object.strokePoints.size() == 1) {
        DrawPreviewDisc(
            pixels,
            rasterWidth,
            rasterHeight,
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints.front().x, pageWidth, rasterWidth)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints.front().y, pageHeight, rasterHeight)),
            radius,
            color,
            opacity);
    } else if (object.closed) {
        DrawPreviewSegment(
            pixels,
            rasterWidth,
            rasterHeight,
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints.back().x, pageWidth, rasterWidth)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints.back().y, pageHeight, rasterHeight)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints.front().x, pageWidth, rasterWidth)),
            static_cast<double>(ScalePreviewCoordinate(object.strokePoints.front().y, pageHeight, rasterHeight)),
            radius,
            color,
            opacity);
    }
}

void AppendUInt32BigEndian(std::string& output, uint32_t value)
{
    output.push_back(static_cast<char>((value >> 24) & 0xFF));
    output.push_back(static_cast<char>((value >> 16) & 0xFF));
    output.push_back(static_cast<char>((value >> 8) & 0xFF));
    output.push_back(static_cast<char>(value & 0xFF));
}

uint32_t ComputeCrc32(const uint8_t* data, size_t length)
{
    static bool initialized = false;
    static uint32_t table[256];
    if (!initialized) {
        for (uint32_t index = 0; index < 256; ++index) {
            uint32_t value = index;
            for (int bit = 0; bit < 8; ++bit) {
                value = (value & 1u) != 0u ? (0xEDB88320u ^ (value >> 1u)) : (value >> 1u);
            }
            table[index] = value;
        }
        initialized = true;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t index = 0; index < length; ++index) {
        crc = table[(crc ^ data[index]) & 0xFFu] ^ (crc >> 8u);
    }
    return crc ^ 0xFFFFFFFFu;
}

uint32_t ComputeAdler32(const uint8_t* data, size_t length)
{
    constexpr uint32_t kAdlerMod = 65521u;
    uint32_t a = 1u;
    uint32_t b = 0u;
    for (size_t index = 0; index < length; ++index) {
        a = (a + data[index]) % kAdlerMod;
        b = (b + a) % kAdlerMod;
    }
    return (b << 16u) | a;
}

void AppendPngChunk(std::string& png, const char type[4], const std::string& data)
{
    AppendUInt32BigEndian(png, static_cast<uint32_t>(data.size()));
    png.append(type, 4);
    png.append(data);
    std::string crcInput(type, 4);
    crcInput.append(data);
    AppendUInt32BigEndian(
        png,
        ComputeCrc32(reinterpret_cast<const uint8_t*>(crcInput.data()), crcInput.size()));
}

bool ShouldEmitPreviewRaster(const SimulatorPageDescriptor* descriptor, size_t syntheticObjectCount)
{
    return syntheticObjectCount > 0 || (descriptor != nullptr && IsPdfPageKind(descriptor->pageKind));
}

std::string BuildPreviewPng(const SimulatorDocumentSession& session, const std::string& pageId,
    const SimulatorPageDescriptor* descriptor, int width, int height)
{
    const double pageWidth = ResolvePageWidth(descriptor);
    const double pageHeight = ResolvePageHeight(descriptor);
    const int rasterWidth = std::max(1, width > 0 ? width : static_cast<int>(std::lround(pageWidth)));
    const int rasterHeight = std::max(1, height > 0 ? height : static_cast<int>(std::lround(pageHeight)));
    std::vector<uint8_t> pixels(static_cast<size_t>(rasterWidth) * static_cast<size_t>(rasterHeight) * 4u, 255u);
    if (descriptor != nullptr && IsPdfPageKind(descriptor->pageKind)) {
        const PreviewRasterColor borderColor = ParsePreviewColor("#CBD5E1");
        FillPreviewRect(pixels, rasterWidth, rasterHeight, 0, 0, rasterWidth, 1, borderColor, 1.0);
        FillPreviewRect(pixels, rasterWidth, rasterHeight, 0, rasterHeight - 1, rasterWidth, rasterHeight, borderColor, 1.0);
        FillPreviewRect(pixels, rasterWidth, rasterHeight, 0, 0, 1, rasterHeight, borderColor, 1.0);
        FillPreviewRect(pixels, rasterWidth, rasterHeight, rasterWidth - 1, 0, rasterWidth, rasterHeight, borderColor, 1.0);
    }
    const std::vector<SimulatorSyntheticObject>* objects = FindCommittedObjectsForPage(session, pageId);
    if (objects != nullptr) {
        for (const SimulatorSyntheticObject& object : *objects) {
            RasterizePreviewObject(pixels, rasterWidth, rasterHeight, pageWidth, pageHeight, object);
        }
    }

    std::string rawImage;
    const size_t rowStride = static_cast<size_t>(rasterWidth) * 4u;
    rawImage.reserve((rowStride + 1u) * static_cast<size_t>(rasterHeight));
    for (int y = 0; y < rasterHeight; ++y) {
        rawImage.push_back('\0');
        rawImage.append(
            reinterpret_cast<const char*>(pixels.data() + static_cast<size_t>(y) * rowStride),
            rowStride);
    }

    std::string zlibStream;
    zlibStream.push_back(static_cast<char>(0x78));
    zlibStream.push_back(static_cast<char>(0x01));
    size_t cursor = 0;
    while (cursor < rawImage.size()) {
        const uint16_t blockLength = static_cast<uint16_t>(std::min<size_t>(65535u, rawImage.size() - cursor));
        const bool isFinalBlock = cursor + blockLength >= rawImage.size();
        zlibStream.push_back(static_cast<char>(isFinalBlock ? 0x01 : 0x00));
        zlibStream.push_back(static_cast<char>(blockLength & 0xFFu));
        zlibStream.push_back(static_cast<char>((blockLength >> 8u) & 0xFFu));
        const uint16_t invertedLength = static_cast<uint16_t>(~blockLength);
        zlibStream.push_back(static_cast<char>(invertedLength & 0xFFu));
        zlibStream.push_back(static_cast<char>((invertedLength >> 8u) & 0xFFu));
        zlibStream.append(rawImage.data() + cursor, blockLength);
        cursor += blockLength;
    }
    AppendUInt32BigEndian(
        zlibStream,
        ComputeAdler32(reinterpret_cast<const uint8_t*>(rawImage.data()), rawImage.size()));

    std::string png;
    static constexpr unsigned char kPngSignature[8] = {
        0x89u, 0x50u, 0x4Eu, 0x47u, 0x0Du, 0x0Au, 0x1Au, 0x0Au
    };
    png.append(reinterpret_cast<const char*>(kPngSignature), sizeof(kPngSignature));
    std::string ihdr;
    AppendUInt32BigEndian(ihdr, static_cast<uint32_t>(rasterWidth));
    AppendUInt32BigEndian(ihdr, static_cast<uint32_t>(rasterHeight));
    ihdr.push_back(static_cast<char>(8));
    ihdr.push_back(static_cast<char>(6));
    ihdr.push_back(static_cast<char>(0));
    ihdr.push_back(static_cast<char>(0));
    ihdr.push_back(static_cast<char>(0));
    AppendPngChunk(png, "IHDR", ihdr);
    AppendPngChunk(png, "IDAT", zlibStream);
    AppendPngChunk(png, "IEND", std::string());
    return png;
}

std::vector<SimulatorSyntheticObject>& AccessCommittedObjectsForPage(
    SimulatorDocumentSession& session, const std::string& pageId)
{
    return session.committedObjectsByPage[pageId];
}

const std::vector<SimulatorSyntheticObject>* FindCommittedObjectsForPage(
    const SimulatorDocumentSession& session, const std::string& pageId)
{
    const auto iterator = session.committedObjectsByPage.find(pageId);
    if (iterator == session.committedObjectsByPage.end()) {
        return nullptr;
    }
    return &iterator->second;
}

size_t CountCommittedObjectsForPage(const SimulatorDocumentSession& session, const std::string& pageId)
{
    const std::vector<SimulatorSyntheticObject>* objects = FindCommittedObjectsForPage(session, pageId);
    return objects == nullptr ? 0 : objects->size();
}

size_t CountCommittedObjects(const SimulatorDocumentSession& session)
{
    size_t count = 0;
    for (const auto& entry : session.committedObjectsByPage) {
        count += entry.second.size();
    }
    return count;
}

size_t CountCommittedObjectsForPages(
    const SimulatorDocumentSession& session, const std::vector<std::string>& pageIds)
{
    size_t count = 0;
    for (const std::string& pageId : pageIds) {
        count += CountCommittedObjectsForPage(session, pageId);
    }
    return count;
}

void RemoveCommittedObjectById(std::vector<SimulatorSyntheticObject>& objects, const std::string& objectId)
{
    objects.erase(std::remove_if(objects.begin(), objects.end(),
        [&](const SimulatorSyntheticObject& object) {
            return object.id == objectId;
        }), objects.end());
}

void RemoveHistoryEntriesForPage(std::vector<SimulatorSyntheticEdit>& edits, const std::string& pageId)
{
    edits.erase(std::remove_if(edits.begin(), edits.end(),
        [&](const SimulatorSyntheticEdit& edit) {
            return edit.pageId == pageId;
        }), edits.end());
}

void RefreshLastCommittedStrokeType(SimulatorEngineState& engine, const SimulatorDocumentSession& session)
{
    if (!session.undoStack.empty()) {
        engine.lastCommittedStrokeType = session.undoStack.back().object.shapeType;
        return;
    }
    for (const std::string& pageId : session.pages) {
        const std::vector<SimulatorSyntheticObject>* objects = FindCommittedObjectsForPage(session, pageId);
        if (objects != nullptr && !objects->empty()) {
            engine.lastCommittedStrokeType = objects->back().shapeType;
            return;
        }
    }
    engine.lastCommittedStrokeType = "none";
}

SimulatorSyntheticObject BuildSyntheticObject(
    const SimulatorEngineState& engine, SimulatorDocumentSession& session, const std::string& pageId)
{
    const SimulatorPageDescriptor* descriptor = FindPageDescriptor(session, pageId);
    const double pageWidth = ResolvePageWidth(descriptor);
    const double pageHeight = ResolvePageHeight(descriptor);
    const std::string tool = ResolveSyntheticTool(engine);
    const int ordinal = session.nextSyntheticObjectId;
    const double brushWidth = NormalizeBrushWidth(engine.activeBrushWidth);
    const double brushScale = ResolveSyntheticBrushScale(engine);

    const double width = std::min(
        pageWidth * 0.66,
        std::max(kMinSyntheticStrokeWidthPt * std::sqrt(brushScale), pageWidth * 0.28 * std::sqrt(brushScale)));
    const double heightBase = (tool == "highlighter" ? pageHeight * 0.055 : pageHeight * 0.10) * brushScale;
    const double height = std::min(pageHeight * 0.28, std::max(kMinSyntheticStrokeHeightPt * brushScale, heightBase));
    const double originX = std::min(
        std::max(18.0, pageWidth * (0.10 + 0.09 * ((ordinal - 1) % 5))),
        std::max(18.0, pageWidth - width - 18.0));
    const double originY = std::min(
        std::max(24.0, pageHeight * (0.12 + 0.10 * ((ordinal - 1) % 6))),
        std::max(24.0, pageHeight - height - 24.0));

    SimulatorSyntheticObject object;
    object.id = "synthetic-" + pageId + "-" + std::to_string(session.nextSyntheticObjectId++);
    object.pageId = pageId;
    object.nodeType = ResolveSyntheticNodeType(tool);
    object.shapeType = ResolveSyntheticShapeType(tool);
    object.tool = tool;
    object.colorHex = engine.activeColor;
    object.strokeWidth = brushWidth;
    object.closed = tool == "text";
    object.pointCount = ResolveSyntheticPointCount(tool, ordinal);
    object.minX = originX;
    object.minY = originY;
    object.maxX = std::min(pageWidth, originX + width);
    object.maxY = std::min(pageHeight, originY + height);
    if (tool == "text") {
        object.strokePoints = BuildTextBoxStrokePointsFromBounds(
            object.minX, object.minY, object.maxX, object.maxY);
    } else if (tool == "highlighter") {
        object.strokePoints = BuildHighlighterStrokePointsFromBounds(
            object.minX, object.minY, object.maxX, object.maxY, ordinal);
    } else {
        object.strokePoints = BuildSyntheticStrokePointsFromBounds(
            object.minX, object.minY, object.maxX, object.maxY, object.pointCount, ordinal);
    }
    object.pointCount = object.strokePoints.size();
    UpdateSyntheticBoundsFromStrokePoints(object, descriptor, brushWidth);
    return object;
}

SimulatorSyntheticObject BuildSyntheticObjectFromGesture(const SimulatorEngineState& engine,
    SimulatorDocumentSession& session, const std::string& pageId,
    double startXRatio, double startYRatio, double endXRatio, double endYRatio)
{
    const SimulatorPageDescriptor* descriptor = FindPageDescriptor(session, pageId);
    const double pageWidth = ResolvePageWidth(descriptor);
    const double pageHeight = ResolvePageHeight(descriptor);
    const std::string tool = ResolveSyntheticTool(engine);
    const int ordinal = session.nextSyntheticObjectId;
    const double brushWidth = NormalizeBrushWidth(engine.activeBrushWidth);
    const double brushScale = ResolveSyntheticBrushScale(engine);
    const double normalizedStartX = ClampUnitRatio(startXRatio);
    const double normalizedStartY = ClampUnitRatio(startYRatio);
    const double normalizedEndX = ClampUnitRatio(endXRatio);
    const double normalizedEndY = ClampUnitRatio(endYRatio);
    const double anchorMinX = std::min(normalizedStartX, normalizedEndX) * pageWidth;
    const double anchorMaxX = std::max(normalizedStartX, normalizedEndX) * pageWidth;
    const double anchorMinY = std::min(normalizedStartY, normalizedEndY) * pageHeight;
    const double anchorMaxY = std::max(normalizedStartY, normalizedEndY) * pageHeight;
    const double widthBase = std::max(
        kMinSyntheticStrokeWidthPt * std::sqrt(brushScale),
        (tool == "highlighter" ? pageWidth * 0.20 : pageWidth * 0.16) * std::sqrt(brushScale));
    const double heightBase = std::max(
        kMinSyntheticStrokeHeightPt * brushScale,
        (tool == "highlighter" ? pageHeight * 0.045 : pageHeight * 0.09) * brushScale);
    const double width = std::min(
        pageWidth * 0.66,
        std::max(widthBase, (anchorMaxX - anchorMinX) + brushWidth * 4.0));
    const double height = std::min(
        pageHeight * 0.28,
        std::max(heightBase, (anchorMaxY - anchorMinY) + brushWidth * 6.0));
    const double originX = std::clamp(anchorMinX, 18.0, std::max(18.0, pageWidth - width - 18.0));
    const double originY = std::clamp(anchorMinY, 24.0, std::max(24.0, pageHeight - height - 24.0));

    SimulatorSyntheticObject object;
    object.id = "synthetic-" + pageId + "-" + std::to_string(session.nextSyntheticObjectId++);
    object.pageId = pageId;
    object.nodeType = ResolveSyntheticNodeType(tool);
    object.shapeType = ResolveSyntheticShapeType(tool);
    object.tool = tool;
    object.colorHex = engine.activeColor;
    object.strokeWidth = brushWidth;
    object.closed = tool == "text";
    object.pointCount = ResolveSyntheticPointCount(tool, ordinal);
    object.minX = originX;
    object.minY = originY;
    object.maxX = std::min(pageWidth, originX + width);
    object.maxY = std::min(pageHeight, originY + height);
    const double gestureEndX = std::clamp(anchorMaxX, 0.0, pageWidth);
    const double gestureEndY = std::clamp(anchorMaxY, 0.0, pageHeight);
    const double gestureStartX = std::clamp(anchorMinX, 0.0, pageWidth);
    const double gestureStartY = std::clamp(anchorMinY, 0.0, pageHeight);
    if (tool == "text") {
        object.strokePoints = BuildTextBoxStrokePointsFromBounds(
            gestureStartX, gestureStartY, gestureEndX, gestureEndY);
    } else if (tool == "highlighter") {
        object.strokePoints = BuildGestureStrokePoints(
            gestureStartX, (gestureStartY + gestureEndY) * 0.5,
            gestureEndX, (gestureStartY + gestureEndY) * 0.5,
            std::max<size_t>(4, object.pointCount / 2), ordinal);
    } else {
        object.strokePoints = BuildGestureStrokePoints(
            gestureStartX, gestureStartY, gestureEndX, gestureEndY, object.pointCount, ordinal);
    }
    object.pointCount = object.strokePoints.size();
    UpdateSyntheticBoundsFromStrokePoints(object, descriptor, brushWidth);
    return object;
}

bool CommitSyntheticCheckpoint(SimulatorEngineState& engine, SimulatorDocumentSession& session)
{
    const std::string pageId = ResolveSessionActivePageId(session);
    if (pageId.empty()) {
        return false;
    }
    SimulatorSyntheticObject object = BuildSyntheticObject(engine, session, pageId);
    AccessCommittedObjectsForPage(session, pageId).push_back(object);
    session.undoStack.push_back({ pageId, object });
    session.redoStack.clear();
    session.hasUnpersistedSyntheticMutation = true;
    engine.lastCommittedStrokeType = object.shapeType;
    return true;
}

std::vector<SimulatorStrokePoint> BuildGesturePagePoints(const std::vector<SimulatorStrokePoint>& ratioPoints,
    double pageWidth, double pageHeight)
{
    std::vector<SimulatorStrokePoint> pagePoints;
    pagePoints.reserve(ratioPoints.size());
    for (const SimulatorStrokePoint& point : ratioPoints) {
        pagePoints.push_back({
            ClampUnitRatio(point.x) * pageWidth,
            ClampUnitRatio(point.y) * pageHeight
        });
    }
    return pagePoints;
}

bool CommitSyntheticGestureStroke(SimulatorEngineState& engine, SimulatorDocumentSession& session,
    double startXRatio, double startYRatio, double endXRatio, double endYRatio,
    const std::vector<SimulatorStrokePoint>* gesturePoints)
{
    const std::string pageId = ResolveSessionActivePageId(session);
    if (pageId.empty()) {
        return false;
    }
    SimulatorSyntheticObject object = BuildSyntheticObjectFromGesture(
        engine, session, pageId, startXRatio, startYRatio, endXRatio, endYRatio);
    if (gesturePoints != nullptr && !gesturePoints->empty()) {
        const SimulatorPageDescriptor* descriptor = FindPageDescriptor(session, pageId);
        object.strokePoints = BuildGesturePagePoints(
            *gesturePoints,
            ResolvePageWidth(descriptor),
            ResolvePageHeight(descriptor));
        object.pointCount = object.strokePoints.size();
        UpdateSyntheticBoundsFromStrokePoints(object, descriptor, object.strokeWidth);
    }
    AccessCommittedObjectsForPage(session, pageId).push_back(object);
    session.undoStack.push_back({ pageId, object });
    session.redoStack.clear();
    session.hasUnpersistedSyntheticMutation = true;
    engine.lastCommittedStrokeType = object.shapeType;
    return true;
}

bool UndoSyntheticCheckpoint(SimulatorEngineState& engine, SimulatorDocumentSession& session)
{
    if (session.undoStack.empty()) {
        return false;
    }
    const SimulatorSyntheticEdit edit = session.undoStack.back();
    session.undoStack.pop_back();
    RemoveCommittedObjectById(AccessCommittedObjectsForPage(session, edit.pageId), edit.object.id);
    session.redoStack.push_back(edit);
    session.hasUnpersistedSyntheticMutation = true;
    RefreshLastCommittedStrokeType(engine, session);
    return true;
}

bool RedoSyntheticCheckpoint(SimulatorEngineState& engine, SimulatorDocumentSession& session)
{
    if (session.redoStack.empty()) {
        return false;
    }
    const SimulatorSyntheticEdit edit = session.redoStack.back();
    session.redoStack.pop_back();
    AccessCommittedObjectsForPage(session, edit.pageId).push_back(edit.object);
    session.undoStack.push_back(edit);
    session.hasUnpersistedSyntheticMutation = true;
    engine.lastCommittedStrokeType = edit.object.shapeType;
    return true;
}

void AppendSimulatorFingerStrokeRatioPoint(SimulatorEngineState& engine, double xRatio, double yRatio)
{
    const double normalizedX = ClampUnitRatio(xRatio);
    const double normalizedY = ClampUnitRatio(yRatio);
    const int64_t timeMs = CurrentTimeMillis();
    if (!engine.simulatorFingerStrokeRatios.empty()) {
        const SimulatorStrokePoint& previous = engine.simulatorFingerStrokeRatios.back();
        const double deltaX = previous.x - normalizedX;
        const double deltaY = previous.y - normalizedY;
        if (std::hypot(deltaX, deltaY) < 0.0025) {
            engine.simulatorFingerStrokeRatios.back() = { normalizedX, normalizedY, timeMs };
            return;
        }
    }
    engine.simulatorFingerStrokeRatios.push_back({ normalizedX, normalizedY, timeMs });
}

void ResetSimulatorFingerStroke(SimulatorEngineState& engine)
{
    engine.simulatorFingerStrokeActive = false;
    engine.simulatorFingerStrokeStartXRatio = engine.simulatorFingerStrokeLastXRatio;
    engine.simulatorFingerStrokeStartYRatio = engine.simulatorFingerStrokeLastYRatio;
    engine.simulatorFingerStrokeRatios.clear();
    ResetSimulatorPrediction(engine);
    engine.activePointerCount = 0;
    engine.multitouchGestureActive = false;
}

void RecordSimulatorFingerTelemetry(SimulatorEngineState& engine, const std::string& action, int pointerCount)
{
    engine.touchEventCount += 1;
    engine.uiTouchEventCount += 1;
    engine.fingerEventCount += 1;
    engine.activePointerCount = action == "up" || action == "cancel" ? 0 : std::max(1, pointerCount);
    engine.multitouchGestureActive = engine.activePointerCount > 1;
    engine.lastEventTime = CurrentTimeMillis();
    engine.lastTouchAction = action;
    engine.lastToolType = "finger";
    engine.lastSourceType = "finger";
    engine.lastPressure = action == "move" ? 0.42 : (action == "down" ? 0.36 : 0.0);
    engine.lastTiltX = 0.0;
    engine.lastTiltY = 0.0;
    engine.lastRollAngle = 0.0;
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

void AppendSyntheticObjectBounds(std::ostringstream& builder, const SimulatorSyntheticObject& object)
{
    builder << "\"bounds\":{"
            << "\"minX\":" << object.minX << ","
            << "\"minY\":" << object.minY << ","
            << "\"maxX\":" << object.maxX << ","
            << "\"maxY\":" << object.maxY
            << "}";
}

void AppendSyntheticObject(std::ostringstream& builder, const SimulatorSyntheticObject& object, int pageIndex)
{
    builder << "{"
            << "\"id\":\"" << EscapeJsonString(object.id) << "\","
            << "\"nodeType\":\"" << EscapeJsonString(object.nodeType) << "\","
            << "\"shapeType\":\"" << EscapeJsonString(object.shapeType) << "\","
            << "\"tool\":\"" << EscapeJsonString(object.tool) << "\","
            << "\"colorHex\":\"" << EscapeJsonString(object.colorHex) << "\","
            << "\"strokeWidth\":" << object.strokeWidth << ","
            << "\"selected\":false,"
            << "\"pointCount\":" << object.pointCount << ","
            << "\"pageIndex\":" << pageIndex << ","
            << "\"pageId\":\"" << EscapeJsonString(object.pageId) << "\","
            << "\"closed\":" << (object.closed ? "true" : "false") << ",";
    AppendSyntheticObjectBounds(builder, object);
    builder << ",\"points\":[";
    for (size_t pointIndex = 0; pointIndex < object.strokePoints.size(); ++pointIndex) {
        if (pointIndex > 0) {
            builder << ",";
        }
        builder << "{"
                << "\"x\":" << object.strokePoints[pointIndex].x << ","
                << "\"y\":" << object.strokePoints[pointIndex].y
                << "}";
    }
    builder << "],\"layer\":\"ink\""
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

bool WriteTextFile(const std::string& path, const std::string& text)
{
    std::ofstream output(path, std::ios::out | std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
        return false;
    }
    output << text;
    return output.good();
}

std::string BuildSyntheticObjectsFilePath(const SimulatorDocumentSession& session)
{
    return session.packagePath + "/" + kSimulatorStrokeStateFileName;
}

void TrackSyntheticObjectId(SimulatorDocumentSession& session, const std::string& objectId)
{
    const size_t dashIndex = objectId.rfind('-');
    if (dashIndex == std::string::npos || dashIndex + 1 >= objectId.size()) {
        return;
    }
    try {
        session.nextSyntheticObjectId = std::max(session.nextSyntheticObjectId, std::stoi(objectId.substr(dashIndex + 1)) + 1);
    } catch (...) {
    }
}

std::string SerializeSyntheticObjectsJson(const SimulatorDocumentSession& session)
{
    std::ostringstream builder;
    builder << "{\n  \"version\": 1,\n  \"objects\": [";
    bool wroteObject = false;
    for (const std::string& pageId : session.pages) {
        const std::vector<SimulatorSyntheticObject>* objects = FindCommittedObjectsForPage(session, pageId);
        if (objects == nullptr) {
            continue;
        }
        for (const SimulatorSyntheticObject& object : *objects) {
            if (wroteObject) {
                builder << ",";
            }
            builder << "\n    {"
                    << "\"id\":\"" << EscapeJsonString(object.id) << "\","
                    << "\"pageId\":\"" << EscapeJsonString(object.pageId) << "\","
                    << "\"nodeType\":\"" << EscapeJsonString(object.nodeType) << "\","
                    << "\"shapeType\":\"" << EscapeJsonString(object.shapeType) << "\","
                    << "\"tool\":\"" << EscapeJsonString(object.tool) << "\","
                    << "\"colorHex\":\"" << EscapeJsonString(object.colorHex) << "\","
                    << "\"strokeWidth\":" << object.strokeWidth << ","
                    << "\"closed\":" << (object.closed ? "true" : "false") << ","
                    << "\"pointCount\":" << object.pointCount << ","
                    << "\"minX\":" << object.minX << ","
                    << "\"minY\":" << object.minY << ","
                    << "\"maxX\":" << object.maxX << ","
                    << "\"maxY\":" << object.maxY
                    << ",\"points\":[";
            for (size_t pointIndex = 0; pointIndex < object.strokePoints.size(); ++pointIndex) {
                if (pointIndex > 0) {
                    builder << ",";
                }
                builder << "{"
                        << "\"x\":" << object.strokePoints[pointIndex].x << ","
                        << "\"y\":" << object.strokePoints[pointIndex].y
                        << "}";
            }
            builder
                    << "]"
                    << "}";
            wroteObject = true;
        }
    }
    builder << "\n  ]\n}";
    return builder.str();
}

void DeserializeSyntheticObjectsJson(const std::string& jsonText, SimulatorDocumentSession& session)
{
    session.committedObjectsByPage.clear();
    session.nextSyntheticObjectId = 1;
    session.hasUnpersistedSyntheticMutation = false;
    const std::string objectsArray = ExtractJsonArrayBody(jsonText, "objects");
    for (const std::string& objectText : SplitTopLevelJsonObjects(objectsArray)) {
        SimulatorSyntheticObject object;
        object.id = ExtractJsonStringValue(objectText, "id", "");
        object.pageId = ExtractJsonStringValue(objectText, "pageId", ResolveSessionActivePageId(session));
        object.nodeType = ExtractJsonStringValue(objectText, "nodeType", "ink-stroke");
        object.shapeType = ExtractJsonStringValue(objectText, "shapeType", "freehand");
        object.tool = ExtractJsonStringValue(objectText, "tool", "pen");
        object.colorHex = ExtractJsonStringValue(objectText, "colorHex", "#1D2736");
        object.strokeWidth = NormalizeBrushWidth(ExtractJsonNumberValue(objectText, "strokeWidth", kDefaultBrushWidth));
        object.closed = objectText.find("\"closed\":true") != std::string::npos ||
            objectText.find("\"closed\": true") != std::string::npos;
        object.pointCount = static_cast<size_t>(std::max(0.0, ExtractJsonNumberValue(objectText, "pointCount", 0.0)));
        object.minX = ExtractJsonNumberValue(objectText, "minX", 0.0);
        object.minY = ExtractJsonNumberValue(objectText, "minY", 0.0);
        object.maxX = ExtractJsonNumberValue(objectText, "maxX", object.minX);
        object.maxY = ExtractJsonNumberValue(objectText, "maxY", object.minY);
        const std::string pointsArray = ExtractJsonArrayBody(objectText, "points");
        for (const std::string& pointText : SplitTopLevelJsonObjects(pointsArray)) {
            const double x = ExtractJsonNumberValue(
                pointText, "x", std::numeric_limits<double>::quiet_NaN());
            const double y = ExtractJsonNumberValue(
                pointText, "y", std::numeric_limits<double>::quiet_NaN());
            if (std::isfinite(x) && std::isfinite(y)) {
                object.strokePoints.push_back({ x, y });
            }
        }
        if (object.id.empty()) {
            object.id = "synthetic-" + object.pageId + "-" + std::to_string(session.nextSyntheticObjectId);
        }
        if (object.strokePoints.empty()) {
            const int ordinal = session.nextSyntheticObjectId;
            if (object.tool == "text") {
                object.strokePoints = BuildTextBoxStrokePointsFromBounds(
                    object.minX, object.minY, object.maxX, object.maxY);
            } else if (object.tool == "highlighter") {
                object.strokePoints = BuildHighlighterStrokePointsFromBounds(
                    object.minX, object.minY, object.maxX, object.maxY, ordinal);
            } else {
                object.strokePoints = BuildSyntheticStrokePointsFromBounds(
                    object.minX, object.minY, object.maxX, object.maxY, object.pointCount, ordinal);
            }
        }
        if (!object.strokePoints.empty()) {
            object.pointCount = object.strokePoints.size();
            UpdateSyntheticBoundsFromStrokePoints(
                object, FindPageDescriptor(session, object.pageId), object.strokeWidth);
        }
        session.committedObjectsByPage[object.pageId].push_back(object);
        TrackSyntheticObjectId(session, object.id);
    }
}

bool PersistSyntheticObjects(const SimulatorDocumentSession& session)
{
    if (session.packagePath.empty()) {
        return true;
    }
    return WriteTextFile(BuildSyntheticObjectsFilePath(session), SerializeSyntheticObjectsJson(session));
}

void LoadSyntheticObjects(SimulatorDocumentSession& session)
{
    if (session.packagePath.empty()) {
        session.committedObjectsByPage.clear();
        session.nextSyntheticObjectId = 1;
        session.hasUnpersistedSyntheticMutation = false;
        return;
    }
    std::string contents;
    if (!ReadBinaryFile(BuildSyntheticObjectsFilePath(session), contents).empty()) {
        session.committedObjectsByPage.clear();
        session.nextSyntheticObjectId = 1;
        session.hasUnpersistedSyntheticMutation = false;
        return;
    }
    DeserializeSyntheticObjectsJson(contents, session);
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
        LoadSyntheticObjects(session);
        engine->documents[documentId] = session;
        engine->activeDocumentId = documentId;
        RefreshLastCommittedStrokeType(*engine, engine->documents[documentId]);
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
        if (!iterator->second.hasUnpersistedSyntheticMutation) {
            if (!CommitSyntheticCheckpoint(*engine, iterator->second)) {
                return false;
            }
            iterator->second.checkpointCount += 1;
        }
        if (!PersistSyntheticObjects(iterator->second)) {
            return false;
        }
        iterator->second.hasUnpersistedSyntheticMutation = false;
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
        const size_t syntheticObjectCount = CountCommittedObjectsForPage(iterator->second, targetPageId);
        const bool includePdfLayer = targetDescriptor != nullptr && IsPdfPageKind(targetDescriptor->pageKind);
        const bool includeInkLayer = includePdfLayer || syntheticObjectCount > 0;
        const size_t objectCount = syntheticObjectCount + (includePdfLayer ? 1 : 0);

        std::ostringstream builder;
        builder << "{"
                ;
        AppendCanonicalPreviewFields(builder, engineId, documentId, targetPageId, targetPageIndex, width, height,
            iterator->second.checkpointCount, syntheticObjectCount, 0, objectCount,
            engine->activeMode, iterator->second, reportedPageIds,
            includePdfLayer, includeInkLayer);
        if (ShouldEmitPreviewRaster(targetDescriptor, syntheticObjectCount)) {
            const int rasterWidth = std::max(1, width > 0 ? width :
                static_cast<int>(std::lround(ResolvePageWidth(targetDescriptor))));
            const int rasterHeight = std::max(1, height > 0 ? height :
                static_cast<int>(std::lround(ResolvePageHeight(targetDescriptor))));
            const std::string png = BuildPreviewPng(
                iterator->second, targetPageId, targetDescriptor, rasterWidth, rasterHeight);
            const std::string pngBase64 = EncodeBase64(png);
            builder << ",\"raster\":{"
                    << "\"mimeType\":\"" << kPngPreviewMimeType << "\","
                    << "\"base64\":\"" << pngBase64 << "\","
                    << "\"width\":" << rasterWidth << ","
                    << "\"height\":" << rasterHeight
                    << "}";
        }
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
        const size_t objectCount =
            CountCommittedObjectsForPages(iterator->second, reportedPageIds) + (includePdfPlaceholder ? 1 : 0);
        std::ostringstream builder;
        builder << "{"
                ;
        AppendCanonicalSceneFields(builder, engine->engineId, iterator->second.documentId,
            ExtractJsonStringValue(iterator->second.openConfigJson, "title", ""),
            ExtractJsonStringValue(iterator->second.openConfigJson, "documentType", "blank"),
            engine->activeMode, engine->activeBackend, iterator->second.checkpointCount, objectCount,
            iterator->second, reportedPageIds);
        builder << ",\"objects\":[";
        bool wroteObject = false;
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
            wroteObject = true;
        }
        for (const std::string& pageId : reportedPageIds) {
            const std::vector<SimulatorSyntheticObject>* objects =
                FindCommittedObjectsForPage(iterator->second, pageId);
            if (objects == nullptr) {
                continue;
            }
            const int pageIndex = std::max(0, FindPageIndex(reportedPageIds, pageId));
            for (const SimulatorSyntheticObject& object : *objects) {
                if (wroteObject) {
                    builder << ",";
                }
                AppendSyntheticObject(builder, object, pageIndex);
                wroteObject = true;
            }
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
        iterator->second.committedObjectsByPage.erase(pageId);
        RemoveHistoryEntriesForPage(iterator->second.undoStack, pageId);
        RemoveHistoryEntriesForPage(iterator->second.redoStack, pageId);
        ReindexPageDescriptors(iterator->second);
        iterator->second.activePageId = nextActivePageId;
        RefreshLastCommittedStrokeType(*engine, iterator->second);
        PersistSyntheticObjects(iterator->second);
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

    bool SetFingerWritingEnabled(const std::string& engineId, bool enabled) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->fingerWritingEnabled = enabled;
        ResetSimulatorFingerStroke(*engine);
        return true;
    }

    bool InjectSimulatorFingerEvent(const std::string& engineId, const std::string& action,
        double pageXRatio, double pageYRatio, int pointerCount) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }
        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end()) {
            return false;
        }
        const std::string activePageId = ResolveSessionActivePageId(iterator->second);
        const SimulatorPageDescriptor* activeDescriptor = FindPageDescriptor(iterator->second, activePageId);

        const std::string normalizedAction = action == "down" || action == "move" || action == "up" || action == "cancel"
            ? action
            : "";
        if (normalizedAction.empty()) {
            return false;
        }

        const double normalizedX = ClampUnitRatio(pageXRatio);
        const double normalizedY = ClampUnitRatio(pageYRatio);
        RecordSimulatorFingerTelemetry(*engine, normalizedAction, pointerCount);

        if (normalizedAction == "down") {
            engine->simulatorFingerStrokeActive = true;
            engine->simulatorFingerStrokeStartXRatio = normalizedX;
            engine->simulatorFingerStrokeStartYRatio = normalizedY;
            engine->simulatorFingerStrokeLastXRatio = normalizedX;
            engine->simulatorFingerStrokeLastYRatio = normalizedY;
            engine->simulatorFingerStrokeRatios.clear();
            AppendSimulatorFingerStrokeRatioPoint(*engine, normalizedX, normalizedY);
            UpdateSimulatorPrediction(*engine, activeDescriptor);
            return true;
        }

        if (normalizedAction == "move") {
            if (!engine->simulatorFingerStrokeActive) {
                engine->simulatorFingerStrokeActive = true;
                engine->simulatorFingerStrokeStartXRatio = normalizedX;
                engine->simulatorFingerStrokeStartYRatio = normalizedY;
                engine->simulatorFingerStrokeRatios.clear();
                AppendSimulatorFingerStrokeRatioPoint(*engine, normalizedX, normalizedY);
            }
            engine->simulatorFingerStrokeLastXRatio = normalizedX;
            engine->simulatorFingerStrokeLastYRatio = normalizedY;
            AppendSimulatorFingerStrokeRatioPoint(*engine, normalizedX, normalizedY);
            UpdateSimulatorPrediction(*engine, activeDescriptor);
            return true;
        }

        if (normalizedAction == "up") {
            if (!engine->simulatorFingerStrokeActive) {
                engine->simulatorFingerStrokeStartXRatio = normalizedX;
                engine->simulatorFingerStrokeStartYRatio = normalizedY;
                engine->simulatorFingerStrokeRatios.clear();
                AppendSimulatorFingerStrokeRatioPoint(*engine, normalizedX, normalizedY);
            }
            engine->simulatorFingerStrokeLastXRatio = normalizedX;
            engine->simulatorFingerStrokeLastYRatio = normalizedY;
            AppendSimulatorFingerStrokeRatioPoint(*engine, normalizedX, normalizedY);
            const bool committed = engine->fingerWritingEnabled &&
                CommitSyntheticGestureStroke(*engine, iterator->second,
                    engine->simulatorFingerStrokeStartXRatio,
                    engine->simulatorFingerStrokeStartYRatio,
                    engine->simulatorFingerStrokeLastXRatio,
                    engine->simulatorFingerStrokeLastYRatio,
                    &engine->simulatorFingerStrokeRatios);
            const bool persisted = !committed || PersistSyntheticObjects(iterator->second);
            ResetSimulatorFingerStroke(*engine);
            return (committed && persisted) || !engine->fingerWritingEnabled;
        }

        ResetSimulatorFingerStroke(*engine);
        return true;
    }

    std::string GetSimulatorPrediction(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine","suppressed":false,"cpuBusyRatio":0,"points":[]})";
        }
        const bool suppressed = CurrentTimeMillis() < engine->predictionSuppressedUntilMs;
        std::ostringstream builder;
        builder << "{"
                << "\"status\":\"ok\","
                << "\"suppressed\":" << (suppressed ? "true" : "false") << ","
                << "\"cpuBusyRatio\":" << engine->predictionCpuBusyRatio << ","
                << "\"points\":[";
        for (size_t index = 0; index < engine->simulatorPredictedStrokeRatios.size(); ++index) {
            if (index > 0) {
                builder << ",";
            }
            const SimulatorStrokePoint& point = engine->simulatorPredictedStrokeRatios[index];
            builder << "{"
                    << "\"x\":" << ClampUnitRatio(point.x) << ","
                    << "\"y\":" << ClampUnitRatio(point.y)
                    << "}";
        }
        builder << "]}";
        return builder.str();
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

    bool SetBrushWidth(const std::string& engineId, double width) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || !std::isfinite(width) || width <= 0.0) {
            return false;
        }
        engine->activeBrushWidth = width;
        return true;
    }

    bool Undo(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }
        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end()) {
            return false;
        }
        const bool undone = UndoSyntheticCheckpoint(*engine, iterator->second);
        if (undone) {
            PersistSyntheticObjects(iterator->second);
        }
        return undone;
    }

    bool Redo(const std::string& engineId) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        SimulatorEngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }
        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end()) {
            return false;
        }
        const bool redone = RedoSyntheticCheckpoint(*engine, iterator->second);
        if (redone) {
            PersistSyntheticObjects(iterator->second);
        }
        return redone;
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
        size_t committedStrokeCount = 0;
        size_t undoDepth = 0;
        size_t redoDepth = 0;
        if (!engine->activeDocumentId.empty()) {
            auto iterator = engine->documents.find(engine->activeDocumentId);
            if (iterator != engine->documents.end()) {
                checkpointCount = iterator->second.checkpointCount;
                activePageId = ResolveSessionActivePageId(iterator->second);
                const std::vector<std::string> reportedPageIds = BuildReportedPageIds(*engine, iterator->second);
                activePageIndex = std::max(0, FindPageIndex(reportedPageIds, activePageId));
                pageCount = std::max<size_t>(1, reportedPageIds.size());
                committedStrokeCount = CountCommittedObjects(iterator->second);
                undoDepth = iterator->second.undoStack.size();
                redoDepth = iterator->second.redoStack.size();
            }
        }

        const bool surfaceReady = !engine->activeDocumentId.empty() && engine->width > 0 && engine->height > 0;
        const std::string surfaceId = !engine->surfaceId.empty()
            ? engine->surfaceId
            : (surfaceReady ? kSimulatorPlaceholderSurfaceId : "");

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
                << "\"activeBrushWidth\":" << engine->activeBrushWidth << ","
                << "\"fingerWritingEnabled\":" << (engine->fingerWritingEnabled ? "true" : "false") << ","
                << "\"xComponentId\":\"" << EscapeJsonString(engine->xComponentId) << "\","
                << "\"surfaceId\":\"" << EscapeJsonString(surfaceId) << "\","
                << "\"checkpointCount\":" << checkpointCount << ","
                << "\"committedStrokeCount\":" << committedStrokeCount << ","
                << "\"undoDepth\":" << undoDepth << ","
                << "\"redoDepth\":" << redoDepth << ","
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
                << "\"surfaceReady\":" << (surfaceReady ? "true" : "false") << ","
                << "\"surfaceWidth\":" << engine->width << ","
                << "\"surfaceHeight\":" << engine->height << ","
                << "\"surfaceOffsetX\":0,"
                << "\"surfaceOffsetY\":0,"
                << "\"touchEventCount\":" << engine->touchEventCount << ","
                << "\"uiTouchEventCount\":" << engine->uiTouchEventCount << ","
                << "\"keyEventCount\":" << engine->keyEventCount << ","
                << "\"stylusEventCount\":" << engine->stylusEventCount << ","
                << "\"fingerEventCount\":" << engine->fingerEventCount << ","
                << "\"palmRejectedCount\":" << engine->palmRejectedCount << ","
                << "\"activePointerCount\":" << engine->activePointerCount << ","
                << "\"stylusActive\":" << (engine->stylusActive ? "true" : "false") << ","
                << "\"multitouchGestureActive\":" << (engine->multitouchGestureActive ? "true" : "false") << ","
                << "\"lastHistoricalCount\":" << engine->lastHistoricalCount << ","
                << "\"lastUiHistoryCount\":" << engine->lastUiHistoryCount << ","
                << "\"predictedPointCount\":" << engine->predictedPointCount << ","
                << "\"lastEventTime\":" << engine->lastEventTime << ","
                << "\"lastPressure\":" << engine->lastPressure << ","
                << "\"lastTiltX\":" << engine->lastTiltX << ","
                << "\"lastTiltY\":" << engine->lastTiltY << ","
                << "\"lastRollAngle\":" << engine->lastRollAngle << ","
                << "\"lastTouchAction\":\"" << EscapeJsonString(engine->lastTouchAction) << "\","
                << "\"lastToolType\":\"" << EscapeJsonString(engine->lastToolType) << "\","
                << "\"lastSourceType\":\"" << EscapeJsonString(engine->lastSourceType) << "\","
                << "\"lastKeyCode\":" << engine->lastKeyCode << ","
                << "\"lastKeyAction\":" << engine->lastKeyAction << ","
                << "\"lastKeySourceType\":" << engine->lastKeySourceType << ","
                << "\"lastKeyEventTime\":" << engine->lastKeyEventTime
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
