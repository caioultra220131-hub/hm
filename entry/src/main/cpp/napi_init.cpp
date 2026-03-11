#include "note_engine_runtime.h"
#include "napi/native_api.h"
#include "hilog/log.h"
#include "ace/xcomponent/native_interface_xcomponent.h"
#include "EGL/egl.h"
#include "GLES3/gl3.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {
constexpr unsigned int kLogDomain = 0x3201;
constexpr const char* kLogTag = "NoteEngine";
constexpr const char* kPrimaryPageId = "page-0";
constexpr const char* kLegacyCoordinateSpace = "legacy-surface";
constexpr const char* kStatsFallbackTargetMode = "stats-fallback";
constexpr const char* kPdfPageNodeIdPrefix = "pdf-page-";
constexpr const char* kPdfFragmentNodeIdPrefix = "pdf-fragment-";
constexpr int kPreviewSchemaVersion = 0;
constexpr int kPrimaryPageIndex = 0;
constexpr size_t kMaxTrackedStrokeSamples = 48;
constexpr size_t kMaxUndoDepth = 20;
constexpr float kMinPredictionSpeedPxPerMs = 0.05f;
constexpr float kPi = 3.1415926535f;
constexpr int64_t kPredictionStableHorizonsMs[2] = { 4, 8 };
constexpr int64_t kPredictionUnstableHorizonsMs[2] = { 2, 4 };
constexpr float kPredictionStableMaxDistancePx = 26.0f;
constexpr float kPredictionUnstableMaxDistancePx = 12.0f;
constexpr float kPredictionMinSegmentDtMs = 2.0f;
constexpr float kPredictionMaxSegmentDtMs = 10.0f;
constexpr float kPredictionMaxSegmentDistancePx = 22.0f;
constexpr float kPredictionSpeedJumpThreshold = 2.2f;
constexpr float kPredictionAngleThresholdDegrees = 55.0f;
constexpr float kPredictionRollbackDistancePx = 6.0f;
constexpr float kPredictionRollbackBlend = 0.35f;
constexpr int64_t kStylusToggleDoubleTapWindowMs = 350;

void RegisterXComponentFromExports(napi_env env, napi_value exports);

enum class PressureCurvePreset {
    kNatural,
    kSoft,
    kFirm
};

struct InkPointSnapshot {
    float x = 0.0f;
    float y = 0.0f;
    float windowX = 0.0f;
    float windowY = 0.0f;
    float displayX = 0.0f;
    float displayY = 0.0f;
    float force = 0.0f;
    float tiltX = 0.0f;
    float tiltY = 0.0f;
    double rollAngle = 0.0;
    bool hasRollAngle = false;
    int64_t timeStamp = 0;
    int32_t pointerId = -1;
    bool historical = false;
    bool predicted = false;
    std::string toolType = "unknown";
};

enum class InputSampleType {
    kTouch,
    kUiTouch,
    kKey
};

struct InputSample {
    InputSampleType type = InputSampleType::kTouch;
    int64_t sequence = 0;
    int64_t timeStamp = 0;
    int32_t pointerId = -1;
    int32_t activePointerCount = 0;
    int32_t action = -1;
    int32_t keyCode = KEY_UNKNOWN;
    int32_t sourceType = -1;
    int32_t toolCode = 0;
    int32_t uiSourceType = 0;
    int32_t uiHistoryCount = 0;
    bool historical = false;
    bool batchTerminal = true;
    bool zeroPointReset = false;
    bool hasRollAngle = false;
    std::string toolType = "unknown";
    std::string sourceLabel = "unknown";
    InkPointSnapshot point;
    float pressure = 0.0f;
    float tiltX = 0.0f;
    float tiltY = 0.0f;
    double rollAngle = 0.0;
};

struct InputStrokeTrace {
    int version = 1;
    int64_t recordedAt = 0;
    std::string engineId;
    std::string documentId;
    std::string xComponentId;
    std::vector<InputSample> samples;
};

struct InputTraceRecorderState {
    bool active = false;
    std::string outputPath;
    int64_t nextSequence = 1;
    InputStrokeTrace trace;
};

struct StrokeRenderObject {
    std::string objectId;
    std::vector<InkPointSnapshot> points;
    std::string tool = "pen";
    std::string colorHex = "#1D2736";
    std::string shapeType = "freehand";
    bool selected = false;
};

struct PageContractDescriptor {
    double widthPt = 0.0;
    double heightPt = 0.0;
    std::string paperBackgroundId = "paper";
    std::string guideKind = "plain";
};

struct PageDescriptor {
    std::string pageId;
    int order = 0;
    std::string pageKind = "blank";
    std::string sourceAttachmentId;
    int sourcePageIndex = -1;
    PageContractDescriptor contract;
};

struct DocumentSession {
    std::string documentId;
    std::string packagePath;
    std::string openConfigJson;
    int checkpointCount = 0;
    bool pageAware = false;
    std::vector<std::string> pages;
    std::vector<PageDescriptor> pageDescriptors;
    std::string activePageId;
    std::unordered_map<std::string, std::vector<StrokeRenderObject>> pageStrokes;
};

struct RenderVertex {
    GLfloat x = 0.0f;
    GLfloat y = 0.0f;
    GLfloat r = 0.0f;
    GLfloat g = 0.0f;
    GLfloat b = 0.0f;
    GLfloat a = 1.0f;
};

struct GlRendererState {
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLConfig config = nullptr;
    GLuint program = 0;
    GLuint vbo = 0;
    void* nativeWindow = nullptr;
    bool ready = false;
};

struct SurfaceTelemetry {
    std::string xComponentId;
    std::string boundEngineId;
    OH_NativeXComponent* component = nullptr;
    void* window = nullptr;
    bool callbacksRegistered = false;
    bool uiInputCallbackRegistered = false;
    bool keyCallbackRegistered = false;
    bool surfaceReady = false;
    bool stylusActive = false;
    bool multitouchGestureActive = false;
    uint64_t width = 0;
    uint64_t height = 0;
    double offsetX = 0.0;
    double offsetY = 0.0;
    int surfaceCreateCount = 0;
    int surfaceChangeCount = 0;
    int surfaceDestroyCount = 0;
    int touchEventCount = 0;
    int uiTouchEventCount = 0;
    int keyEventCount = 0;
    int stylusEventCount = 0;
    int fingerEventCount = 0;
    int palmRejectedCount = 0;
    int activePointerCount = 0;
    int32_t activeStylusPointerId = -1;
    int64_t lastEventTime = 0;
    int64_t lastKeyEventTime = 0;
    int32_t lastKeyCode = -1;
    int32_t lastKeyAction = -1;
    int32_t lastKeySourceType = -1;
    int32_t lastUiAction = -1;
    int32_t lastUiToolType = 0;
    int32_t lastUiSourceType = 0;
    size_t lastHistoricalCount = 0;
    size_t lastUiHistoryCount = 0;
    size_t predictedPointCount = 0;
    float lastPressure = 0.0f;
    float lastTiltX = 0.0f;
    float lastTiltY = 0.0f;
    double lastRollAngle = 0.0;
    std::string lastTouchAction = "unknown";
    std::string lastToolType = "unknown";
    std::string lastSourceType = "unknown";
    std::vector<InkPointSnapshot> strokeSamples;
    std::vector<InkPointSnapshot> predictedSamples;
    std::vector<InkPointSnapshot> previousPredictedSamples;
    bool stylusSessionOwned = false;
    bool selectionDragActive = false;
    bool selectionSnapshotCaptured = false;
    float selectionLastX = 0.0f;
    float selectionLastY = 0.0f;
    GlRendererState gl;
};

struct EngineState {
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
    bool doubleTapSwitchEnabled = true;
    PressureCurvePreset pressureCurvePreset = PressureCurvePreset::kNatural;
    int32_t lastStylusToggleKeyCode = KEY_UNKNOWN;
    int64_t lastStylusToggleTimeMs = 0;
    int nextObjectCounter = 1;
    std::unordered_map<std::string, DocumentSession> documents;
    std::vector<StrokeRenderObject> committedStrokes;
    std::vector<std::vector<StrokeRenderObject>> undoSnapshots;
    std::vector<std::vector<StrokeRenderObject>> redoSnapshots;
    std::string lastCommittedStrokeType = "none";
    InputTraceRecorderState inputTraceRecorder;
    std::string lastInputTracePath;
    std::string lastInputTraceStatus = "idle";
    size_t lastInputTraceSampleCount = 0;
    bool inputReplayActive = false;
};

std::string TouchActionToString(OH_NativeXComponent_TouchEventType action)
{
    switch (action) {
        case OH_NATIVEXCOMPONENT_DOWN:
            return "down";
        case OH_NATIVEXCOMPONENT_MOVE:
            return "move";
        case OH_NATIVEXCOMPONENT_UP:
            return "up";
        case OH_NATIVEXCOMPONENT_CANCEL:
            return "cancel";
        default:
            return "unknown";
    }
}

std::string ToolTypeToString(OH_NativeXComponent_TouchPointToolType toolType)
{
    switch (toolType) {
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_FINGER:
            return "finger";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_PEN:
            return "pen";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_RUBBER:
            return "rubber";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_BRUSH:
            return "brush";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_PENCIL:
            return "pencil";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_AIRBRUSH:
            return "airbrush";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_MOUSE:
            return "mouse";
        case OH_NATIVEXCOMPONENT_TOOL_TYPE_LENS:
            return "lens";
        default:
            return "unknown";
    }
}

std::string SourceToolToString(OH_NativeXComponent_TouchEvent_SourceTool toolType)
{
    switch (toolType) {
        case OH_NATIVEXCOMPONENT_SOURCETOOL_FINGER:
            return "finger";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_PEN:
            return "pen";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_RUBBER:
            return "rubber";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_BRUSH:
            return "brush";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_PENCIL:
            return "pencil";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_AIRBRUSH:
            return "airbrush";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_MOUSE:
            return "mouse";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_LENS:
            return "lens";
        case OH_NATIVEXCOMPONENT_SOURCETOOL_TOUCHPAD:
            return "touchpad";
        default:
            return "unknown";
    }
}

std::string EventSourceToString(OH_NativeXComponent_EventSourceType sourceType)
{
    switch (sourceType) {
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_MOUSE:
            return "mouse";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_TOUCHSCREEN:
            return "touchscreen";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_TOUCHPAD:
            return "touchpad";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_JOYSTICK:
            return "joystick";
        case OH_NATIVEXCOMPONENT_SOURCE_TYPE_KEYBOARD:
            return "keyboard";
        default:
            return "unknown";
    }
}

std::string UiInputToolTypeToString(int32_t toolType)
{
    switch (toolType) {
        case UI_INPUT_EVENT_TOOL_TYPE_FINGER:
            return "finger";
        case UI_INPUT_EVENT_TOOL_TYPE_PEN:
            return "pen";
        case UI_INPUT_EVENT_TOOL_TYPE_MOUSE:
            return "mouse";
        case UI_INPUT_EVENT_TOOL_TYPE_TOUCHPAD:
            return "touchpad";
        case UI_INPUT_EVENT_TOOL_TYPE_JOYSTICK:
            return "joystick";
        default:
            return "unknown";
    }
}

std::string UiInputSourceTypeToString(int32_t sourceType)
{
    switch (sourceType) {
        case UI_INPUT_EVENT_SOURCE_TYPE_MOUSE:
            return "mouse";
        case UI_INPUT_EVENT_SOURCE_TYPE_TOUCH_SCREEN:
            return "touchscreen";
        default:
            return "unknown";
    }
}

std::string InputSampleTypeToString(InputSampleType type)
{
    switch (type) {
        case InputSampleType::kUiTouch:
            return "ui-touch";
        case InputSampleType::kKey:
            return "key";
        case InputSampleType::kTouch:
        default:
            return "touch";
    }
}

InputSampleType ParseInputSampleType(const std::string& type)
{
    if (type == "ui-touch") {
        return InputSampleType::kUiTouch;
    }
    if (type == "key") {
        return InputSampleType::kKey;
    }
    return InputSampleType::kTouch;
}

bool IsStylusTool(const std::string& toolType)
{
    return toolType == "pen" || toolType == "pencil" || toolType == "rubber";
}

std::string ReadXComponentId(OH_NativeXComponent* component)
{
    if (component == nullptr) {
        return "";
    }
    char idBuffer[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    uint64_t idSize = sizeof(idBuffer);
    if (OH_NativeXComponent_GetXComponentId(component, idBuffer, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        return "";
    }
    idBuffer[sizeof(idBuffer) - 1] = '\0';
    return std::string(idBuffer);
}

void RefreshSurfaceGeometry(SurfaceTelemetry& telemetry)
{
    if (telemetry.component == nullptr || telemetry.window == nullptr) {
        return;
    }

    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(telemetry.component, telemetry.window, &width, &height) ==
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        telemetry.width = width;
        telemetry.height = height;
    }

    double offsetX = 0.0;
    double offsetY = 0.0;
    if (OH_NativeXComponent_GetXComponentOffset(telemetry.component, telemetry.window, &offsetX, &offsetY) ==
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        telemetry.offsetX = offsetX;
        telemetry.offsetY = offsetY;
    }
}

void TrimStrokeSamples(std::vector<InkPointSnapshot>& samples)
{
    if (samples.size() <= kMaxTrackedStrokeSamples) {
        return;
    }
    const size_t overflow = samples.size() - kMaxTrackedStrokeSamples;
    samples.erase(samples.begin(), samples.begin() + static_cast<long long>(overflow));
}

float Clamp01(float value)
{
    return std::clamp(value, 0.0f, 1.0f);
}

float LerpFloat(float start, float end, float t)
{
    return start + (end - start) * t;
}

struct Vec2f {
    float x = 0.0f;
    float y = 0.0f;
};

InkPointSnapshot LerpInkPoint(const InkPointSnapshot& start, const InkPointSnapshot& end, float t);

float VecLength(const Vec2f& value)
{
    return std::hypot(value.x, value.y);
}

Vec2f ScaleVec(const Vec2f& value, float scale)
{
    return { value.x * scale, value.y * scale };
}

Vec2f AddVec(const Vec2f& a, const Vec2f& b)
{
    return { a.x + b.x, a.y + b.y };
}

Vec2f NormalizeVec(const Vec2f& value)
{
    const float length = VecLength(value);
    if (length <= 0.0001f) {
        return {};
    }
    return { value.x / length, value.y / length };
}

float DotVec(const Vec2f& a, const Vec2f& b)
{
    return a.x * b.x + a.y * b.y;
}

Vec2f Perpendicular(const Vec2f& value)
{
    return { -value.y, value.x };
}

Vec2f ClampVectorLength(Vec2f value, float maxLength)
{
    const float length = VecLength(value);
    if (length <= maxLength || length <= 0.0001f) {
        return value;
    }
    const float scale = maxLength / length;
    return ScaleVec(value, scale);
}

float DistanceBetweenVec(const Vec2f& a, const Vec2f& b)
{
    return std::hypot(a.x - b.x, a.y - b.y);
}

Vec2f PointPosition(const InkPointSnapshot& point)
{
    return { point.x, point.y };
}

float PressureCurveValue(PressureCurvePreset preset, float input)
{
    static constexpr std::array<std::array<Vec2f, 4>, 3> kCurves = { {
        { Vec2f { 0.0f, 0.18f }, Vec2f { 0.35f, 0.42f }, Vec2f { 0.7f, 0.76f }, Vec2f { 1.0f, 1.0f } },
        { Vec2f { 0.0f, 0.24f }, Vec2f { 0.25f, 0.48f }, Vec2f { 0.6f, 0.82f }, Vec2f { 1.0f, 1.0f } },
        { Vec2f { 0.0f, 0.12f }, Vec2f { 0.45f, 0.30f }, Vec2f { 0.8f, 0.66f }, Vec2f { 1.0f, 1.0f } },
    } };

    size_t presetIndex = 0;
    switch (preset) {
        case PressureCurvePreset::kSoft:
            presetIndex = 1;
            break;
        case PressureCurvePreset::kFirm:
            presetIndex = 2;
            break;
        case PressureCurvePreset::kNatural:
        default:
            presetIndex = 0;
            break;
    }

    const float clampedInput = Clamp01(input);
    const std::array<Vec2f, 4>& controlPoints = kCurves[presetIndex];
    if (clampedInput <= controlPoints.front().x) {
        return controlPoints.front().y;
    }
    if (clampedInput >= controlPoints.back().x) {
        return controlPoints.back().y;
    }

    for (size_t index = 1; index < controlPoints.size(); ++index) {
        const Vec2f& start = controlPoints[index - 1];
        const Vec2f& end = controlPoints[index];
        if (clampedInput > end.x) {
            continue;
        }
        const float span = std::max(0.0001f, end.x - start.x);
        const float t = (clampedInput - start.x) / span;
        return LerpFloat(start.y, end.y, t);
    }

    return controlPoints.back().y;
}

bool ToolRemembersInkState(const std::string& tool)
{
    return tool == "pen" || tool == "pencil" || tool == "highlighter";
}

bool IsStylusLikeKeySource(int32_t sourceType)
{
    return sourceType != static_cast<int32_t>(OH_NATIVEXCOMPONENT_SOURCE_TYPE_KEYBOARD);
}

void ApplyToolSelection(EngineState& engine, const std::string& tool)
{
    if (ToolRemembersInkState(tool)) {
        engine.lastInkTool = tool;
    }
    engine.activeTool = tool;
}

bool ToggleStylusTool(EngineState& engine)
{
    if (engine.activeTool == "eraser") {
        ApplyToolSelection(engine, engine.lastInkTool.empty() ? "pen" : engine.lastInkTool);
        return true;
    }

    if (ToolRemembersInkState(engine.activeTool)) {
        engine.lastInkTool = engine.activeTool;
        engine.activeTool = "eraser";
        return true;
    }

    if (engine.activeTool == "lasso" || engine.activeTool == "hand") {
        engine.activeTool = "eraser";
        return true;
    }

    return false;
}

PressureCurvePreset ParsePressureCurvePreset(const std::string& configJson)
{
    if (configJson.find("\"pressureCurvePreset\":\"soft\"") != std::string::npos) {
        return PressureCurvePreset::kSoft;
    }
    if (configJson.find("\"pressureCurvePreset\":\"firm\"") != std::string::npos) {
        return PressureCurvePreset::kFirm;
    }
    return PressureCurvePreset::kNatural;
}

std::vector<InkPointSnapshot> BuildPredictionTail(const std::vector<InkPointSnapshot>& realSamples,
    const std::vector<InkPointSnapshot>& previousPredictedSamples)
{
    if (realSamples.size() < 2) {
        return {};
    }

    struct VelocitySample {
        Vec2f velocity;
        float speed = 0.0f;
    };

    const InkPointSnapshot& last = realSamples.back();
    std::vector<VelocitySample> segments;
    segments.reserve(3);

    for (size_t index = realSamples.size() - 1; index > 0 && segments.size() < 3; --index) {
        const InkPointSnapshot& end = realSamples[index];
        const InkPointSnapshot& start = realSamples[index - 1];
        const float deltaTimeMs = std::clamp(
            static_cast<float>(end.timeStamp - start.timeStamp), kPredictionMinSegmentDtMs, kPredictionMaxSegmentDtMs);
        Vec2f delta = { end.x - start.x, end.y - start.y };
        delta = ClampVectorLength(delta, kPredictionMaxSegmentDistancePx);
        Vec2f velocity = ScaleVec(delta, 1.0f / deltaTimeMs);
        const float speed = VecLength(velocity);
        if (speed < kMinPredictionSpeedPxPerMs) {
            continue;
        }
        segments.push_back({ velocity, speed });
    }

    if (segments.empty()) {
        return {};
    }

    static constexpr float kVelocityWeights[3] = { 0.55f, 0.30f, 0.15f };
    Vec2f fusedVelocity {};
    float totalWeight = 0.0f;
    for (size_t index = 0; index < segments.size(); ++index) {
        fusedVelocity = AddVec(fusedVelocity, ScaleVec(segments[index].velocity, kVelocityWeights[index]));
        totalWeight += kVelocityWeights[index];
    }
    if (totalWeight > 0.0f) {
        fusedVelocity = ScaleVec(fusedVelocity, 1.0f / totalWeight);
    }

    const float fusedSpeed = VecLength(fusedVelocity);
    if (fusedSpeed < kMinPredictionSpeedPxPerMs) {
        return {};
    }

    bool unstable = false;
    if (segments.size() >= 2) {
        const Vec2f newestDirection = NormalizeVec(segments[0].velocity);
        const Vec2f olderDirection = NormalizeVec(segments[1].velocity);
        if (VecLength(newestDirection) > 0.0f && VecLength(olderDirection) > 0.0f) {
            const float cosine = std::clamp(DotVec(newestDirection, olderDirection), -1.0f, 1.0f);
            const float angleDegrees = std::acos(cosine) * (180.0f / kPi);
            unstable = angleDegrees > kPredictionAngleThresholdDegrees;
        }

        if (!unstable && segments[1].speed > kMinPredictionSpeedPxPerMs) {
            const float speedRatio = std::max(segments[0].speed, segments[1].speed) /
                std::max(kMinPredictionSpeedPxPerMs, std::min(segments[0].speed, segments[1].speed));
            unstable = speedRatio > kPredictionSpeedJumpThreshold;
        }
    }

    const int64_t* horizons = unstable ? kPredictionUnstableHorizonsMs : kPredictionStableHorizonsMs;
    const float maxDistance = unstable ? kPredictionUnstableMaxDistancePx : kPredictionStableMaxDistancePx;

    auto createPredictedPoint = [&](int64_t horizonMs) {
        InkPointSnapshot predicted = last;
        Vec2f offset = ScaleVec(fusedVelocity, static_cast<float>(horizonMs));
        offset = ClampVectorLength(offset, maxDistance);
        if (unstable) {
            offset = ScaleVec(offset, 0.65f);
        }
        predicted.x = last.x + offset.x;
        predicted.y = last.y + offset.y;
        predicted.windowX = last.windowX + offset.x;
        predicted.windowY = last.windowY + offset.y;
        predicted.displayX = last.displayX + offset.x;
        predicted.displayY = last.displayY + offset.y;
        predicted.timeStamp = last.timeStamp + horizonMs;
        predicted.force = std::clamp(last.force * 0.96f, 0.0f, 1.0f);
        predicted.historical = false;
        predicted.predicted = true;
        predicted.hasRollAngle = last.hasRollAngle;
        return predicted;
    };

    std::vector<InkPointSnapshot> nextTail = {
        createPredictedPoint(horizons[0]),
        createPredictedPoint(horizons[1])
    };

    if (previousPredictedSamples.empty()) {
        return nextTail;
    }

    const size_t limit = std::min(nextTail.size(), previousPredictedSamples.size());
    for (size_t index = 0; index < limit; ++index) {
        InkPointSnapshot blendSource = previousPredictedSamples[index];
        if (unstable) {
            blendSource = LerpInkPoint(last, blendSource, 0.45f);
        }
        const float distance = DistanceBetweenVec(PointPosition(nextTail[index]), PointPosition(blendSource));
        if (distance > kPredictionRollbackDistancePx) {
            nextTail[index] = LerpInkPoint(blendSource, nextTail[index], kPredictionRollbackBlend);
        }
    }

    return nextTail;
}

struct RgbaColor {
    float r = 0.0f;
    float g = 0.0f;
    float b = 0.0f;
    float a = 1.0f;
};

int HexValue(char value)
{
    if (value >= '0' && value <= '9') {
        return value - '0';
    }
    if (value >= 'a' && value <= 'f') {
        return value - 'a' + 10;
    }
    if (value >= 'A' && value <= 'F') {
        return value - 'A' + 10;
    }
    return 0;
}

RgbaColor ParseColorHex(const std::string& hexColor, float alphaOverride = -1.0f)
{
    std::string normalized = hexColor;
    if (!normalized.empty() && normalized.front() == '#') {
        normalized.erase(normalized.begin());
    }
    if (normalized.size() != 6 && normalized.size() != 8) {
        return { 0.1137f, 0.1529f, 0.2118f, alphaOverride >= 0.0f ? alphaOverride : 1.0f };
    }

    auto parseByte = [&](size_t offset) {
        return HexValue(normalized[offset]) * 16 + HexValue(normalized[offset + 1]);
    };

    const float red = static_cast<float>(parseByte(0)) / 255.0f;
    const float green = static_cast<float>(parseByte(2)) / 255.0f;
    const float blue = static_cast<float>(parseByte(4)) / 255.0f;
    float alpha = 1.0f;
    if (normalized.size() == 8) {
        alpha = static_cast<float>(parseByte(6)) / 255.0f;
    }
    if (alphaOverride >= 0.0f) {
        alpha = alphaOverride;
    }
    return { red, green, blue, alpha };
}

InkPointSnapshot LerpInkPoint(const InkPointSnapshot& start, const InkPointSnapshot& end, float t)
{
    InkPointSnapshot point = start;
    point.x = start.x + (end.x - start.x) * t;
    point.y = start.y + (end.y - start.y) * t;
    point.windowX = start.windowX + (end.windowX - start.windowX) * t;
    point.windowY = start.windowY + (end.windowY - start.windowY) * t;
    point.displayX = start.displayX + (end.displayX - start.displayX) * t;
    point.displayY = start.displayY + (end.displayY - start.displayY) * t;
    point.force = start.force + (end.force - start.force) * t;
    point.tiltX = start.tiltX + (end.tiltX - start.tiltX) * t;
    point.tiltY = start.tiltY + (end.tiltY - start.tiltY) * t;
    point.rollAngle = start.rollAngle + (end.rollAngle - start.rollAngle) * static_cast<double>(t);
    point.hasRollAngle = start.hasRollAngle || end.hasRollAngle;
    point.timeStamp = start.timeStamp + static_cast<int64_t>(static_cast<float>(end.timeStamp - start.timeStamp) * t);
    point.pointerId = end.pointerId;
    point.historical = start.historical || end.historical;
    point.predicted = start.predicted || end.predicted;
    point.toolType = end.toolType.empty() ? start.toolType : end.toolType;
    return point;
}

InkPointSnapshot QuadraticInkPoint(
    const InkPointSnapshot& start, const InkPointSnapshot& control, const InkPointSnapshot& end, float t)
{
    const InkPointSnapshot first = LerpInkPoint(start, control, t);
    const InkPointSnapshot second = LerpInkPoint(control, end, t);
    return LerpInkPoint(first, second, t);
}

std::vector<InkPointSnapshot> BuildSmoothedStroke(const std::vector<InkPointSnapshot>& inputSamples)
{
    if (inputSamples.size() < 3) {
        return inputSamples;
    }

    std::vector<InkPointSnapshot> smoothed;
    smoothed.reserve(inputSamples.size() * 4);
    smoothed.push_back(inputSamples.front());

    for (size_t index = 1; index + 1 < inputSamples.size(); ++index) {
        InkPointSnapshot curveStart = LerpInkPoint(inputSamples[index - 1], inputSamples[index], 0.5f);
        InkPointSnapshot curveEnd = LerpInkPoint(inputSamples[index], inputSamples[index + 1], 0.5f);
        if (index == 1) {
            curveStart = inputSamples.front();
        }
        if (index + 1 == inputSamples.size() - 1) {
            curveEnd = inputSamples.back();
        }
        for (int subdivision = 1; subdivision <= 4; ++subdivision) {
            smoothed.push_back(QuadraticInkPoint(
                curveStart, inputSamples[index], curveEnd, static_cast<float>(subdivision) / 4.0f));
        }
    }

    if (smoothed.empty() || smoothed.back().timeStamp != inputSamples.back().timeStamp) {
        smoothed.push_back(inputSamples.back());
    }
    return smoothed;
}

bool ToolProducesInk(const std::string& tool)
{
    return tool == "pen" || tool == "pencil" || tool == "highlighter";
}

bool ToolErasesObjects(const std::string& tool)
{
    return tool == "eraser";
}

bool ToolUsesLassoSelection(const std::string& tool)
{
    return tool == "lasso";
}

bool ToolMovesSelection(const std::string& tool)
{
    return tool == "hand";
}

float ComputeStrokeWidthPx(const EngineState& engine, const std::string& tool, const InkPointSnapshot& point,
    bool predicted)
{
    float baseWidth = 3.2f;
    if (tool == "pencil") {
        baseWidth = 4.2f;
    } else if (tool == "highlighter") {
        baseWidth = 18.0f;
    }

    float width = baseWidth;
    if (engine.pressureEnabled && (tool == "pen" || tool == "pencil")) {
        const float rawPressure = Clamp01(point.force > 0.0f ? point.force : 0.55f);
        const float curvedPressure = PressureCurveValue(engine.pressureCurvePreset, rawPressure);
        width = baseWidth * (0.38f + curvedPressure * 1.22f);
    }

    if (predicted) {
        width *= 0.92f;
    }
    return std::clamp(width, 1.2f, tool == "highlighter" ? 28.0f : 16.0f);
}

RgbaColor ResolveStrokeColor(const std::string& tool, const std::string& colorHex, bool predicted)
{
    float alpha = 1.0f;
    if (tool == "highlighter") {
        alpha = 0.22f;
    } else if (tool == "pencil") {
        alpha = 0.88f;
    }
    if (predicted) {
        alpha *= 0.42f;
    }
    return ParseColorHex(colorHex, alpha);
}

RgbaColor WithAlpha(const RgbaColor& color, float alpha)
{
    RgbaColor tinted = color;
    tinted.a = Clamp01(alpha);
    return tinted;
}

float ToNdcX(float x, float width)
{
    return width <= 0.0f ? 0.0f : (x / width) * 2.0f - 1.0f;
}

float ToNdcY(float y, float height)
{
    return height <= 0.0f ? 0.0f : 1.0f - (y / height) * 2.0f;
}

RenderVertex MakeVertex(float x, float y, const RgbaColor& color, float surfaceWidth, float surfaceHeight)
{
    return { ToNdcX(x, surfaceWidth), ToNdcY(y, surfaceHeight), color.r, color.g, color.b, color.a };
}

RenderVertex MakeVertex(const Vec2f& point, const RgbaColor& color, float surfaceWidth, float surfaceHeight)
{
    return MakeVertex(point.x, point.y, color, surfaceWidth, surfaceHeight);
}

void AddTriangle(std::vector<RenderVertex>& vertices, const RenderVertex& a, const RenderVertex& b, const RenderVertex& c)
{
    vertices.push_back(a);
    vertices.push_back(b);
    vertices.push_back(c);
}

void AddRect(std::vector<RenderVertex>& vertices, float left, float top, float right, float bottom,
    const RgbaColor& color, float surfaceWidth, float surfaceHeight)
{
    const RenderVertex v0 = MakeVertex(left, top, color, surfaceWidth, surfaceHeight);
    const RenderVertex v1 = MakeVertex(right, top, color, surfaceWidth, surfaceHeight);
    const RenderVertex v2 = MakeVertex(left, bottom, color, surfaceWidth, surfaceHeight);
    const RenderVertex v3 = MakeVertex(right, bottom, color, surfaceWidth, surfaceHeight);
    AddTriangle(vertices, v0, v2, v1);
    AddTriangle(vertices, v1, v2, v3);
}

void AddOutlineRect(std::vector<RenderVertex>& vertices, float left, float top, float right, float bottom,
    float thickness, const RgbaColor& color, float surfaceWidth, float surfaceHeight)
{
    AddRect(vertices, left, top, right, top + thickness, color, surfaceWidth, surfaceHeight);
    AddRect(vertices, left, bottom - thickness, right, bottom, color, surfaceWidth, surfaceHeight);
    AddRect(vertices, left, top, left + thickness, bottom, color, surfaceWidth, surfaceHeight);
    AddRect(vertices, right - thickness, top, right, bottom, color, surfaceWidth, surfaceHeight);
}

void AddGradientStripSegment(std::vector<RenderVertex>& vertices, const InkPointSnapshot& start,
    const InkPointSnapshot& end, const Vec2f& normal, float startOffsetA, float startOffsetB,
    float endOffsetA, float endOffsetB, const RgbaColor& colorA, const RgbaColor& colorB,
    float surfaceWidth, float surfaceHeight)
{
    const Vec2f startOuter = { start.x + normal.x * startOffsetA, start.y + normal.y * startOffsetA };
    const Vec2f startInner = { start.x + normal.x * startOffsetB, start.y + normal.y * startOffsetB };
    const Vec2f endOuter = { end.x + normal.x * endOffsetA, end.y + normal.y * endOffsetA };
    const Vec2f endInner = { end.x + normal.x * endOffsetB, end.y + normal.y * endOffsetB };

    const RenderVertex a = MakeVertex(startOuter, colorA, surfaceWidth, surfaceHeight);
    const RenderVertex b = MakeVertex(startInner, colorB, surfaceWidth, surfaceHeight);
    const RenderVertex c = MakeVertex(endOuter, colorA, surfaceWidth, surfaceHeight);
    const RenderVertex d = MakeVertex(endInner, colorB, surfaceWidth, surfaceHeight);
    AddTriangle(vertices, a, b, c);
    AddTriangle(vertices, c, b, d);
}

void AddStripSegment(std::vector<RenderVertex>& vertices, const InkPointSnapshot& start, const InkPointSnapshot& end,
    float halfStart, float halfEnd, const RgbaColor& color, float surfaceWidth, float surfaceHeight)
{
    const Vec2f tangent = NormalizeVec({ end.x - start.x, end.y - start.y });
    if (VecLength(tangent) <= 0.0f) {
        return;
    }
    const Vec2f normal = Perpendicular(tangent);
    AddGradientStripSegment(vertices, start, end, normal, halfStart, -halfStart, halfEnd, -halfEnd,
        color, color, surfaceWidth, surfaceHeight);
}

float ComputeTiltMagnitude(const InkPointSnapshot& point)
{
    return Clamp01(std::hypot(point.tiltX, point.tiltY) / 60.0f);
}

Vec2f ResolvePencilAxis(const InkPointSnapshot& start, const InkPointSnapshot& end)
{
    const Vec2f tiltAxis = NormalizeVec({
        (start.tiltX + end.tiltX) * 0.5f,
        (start.tiltY + end.tiltY) * 0.5f
    });
    const bool hasRollAngle = start.hasRollAngle || end.hasRollAngle;
    if (!hasRollAngle) {
        return tiltAxis;
    }

    const float rollAngle = static_cast<float>((start.rollAngle + end.rollAngle) * 0.5);
    const Vec2f rollAxis = { std::cos(rollAngle), std::sin(rollAngle) };
    Vec2f combined = ScaleVec(rollAxis, 0.7f);
    if (VecLength(tiltAxis) > 0.0f) {
        combined = AddVec(combined, ScaleVec(tiltAxis, 0.3f));
    }
    const Vec2f normalized = NormalizeVec(combined);
    return VecLength(normalized) > 0.0f ? normalized : NormalizeVec(rollAxis);
}

void AddPencilStripSegment(std::vector<RenderVertex>& vertices, const InkPointSnapshot& start,
    const InkPointSnapshot& end, const EngineState& engine, const std::string& colorHex, bool predicted,
    float surfaceWidth, float surfaceHeight)
{
    const Vec2f tangent = NormalizeVec({ end.x - start.x, end.y - start.y });
    if (VecLength(tangent) <= 0.0f) {
        return;
    }

    const float startTilt = ComputeTiltMagnitude(start);
    const float endTilt = ComputeTiltMagnitude(end);
    const float tiltMagnitude = (startTilt + endTilt) * 0.5f;
    const float startBaseHalf = ComputeStrokeWidthPx(engine, "pencil", start, predicted) * 0.5f;
    const float endBaseHalf = ComputeStrokeWidthPx(engine, "pencil", end, predicted) * 0.5f;
    const RgbaColor baseColor = ResolveStrokeColor("pencil", colorHex, predicted);

    if (tiltMagnitude < 0.18f) {
        AddStripSegment(vertices, start, end, startBaseHalf, endBaseHalf, baseColor, surfaceWidth, surfaceHeight);
        return;
    }

    Vec2f axis = ResolvePencilAxis(start, end);
    if (VecLength(axis) <= 0.0f) {
        axis = Perpendicular(tangent);
    }
    Vec2f normal = NormalizeVec(Perpendicular(tangent));
    if (VecLength(normal) <= 0.0f) {
        normal = axis;
    }

    const float alignment = DotVec(normal, axis);
    const float heavySign = alignment >= 0.0f ? 1.0f : -1.0f;
    normal = ScaleVec(normal, heavySign);

    const float widthMultiplier = LerpFloat(1.0f, 2.4f, tiltMagnitude);
    const float startFullWidth = std::max(1.0f, ComputeStrokeWidthPx(engine, "pencil", start, predicted) * widthMultiplier);
    const float endFullWidth = std::max(1.0f, ComputeStrokeWidthPx(engine, "pencil", end, predicted) * widthMultiplier);

    const auto featherBoundary = [](float fullWidth) { return -fullWidth * 0.5f + fullWidth * 0.20f; };
    const auto coreBoundary = [&](float fullWidth) { return featherBoundary(fullWidth) + fullWidth * 0.35f; };
    const auto outerBoundary = [](float fullWidth) { return fullWidth * 0.5f; };

    const RgbaColor coreColor = WithAlpha(baseColor, baseColor.a * 0.82f);
    const float shadowAlpha = LerpFloat(0.42f, 0.62f, tiltMagnitude) * baseColor.a;
    const RgbaColor shadowInner = WithAlpha(baseColor, shadowAlpha);
    const RgbaColor shadowOuter = WithAlpha(baseColor, shadowAlpha * 0.55f);
    const float featherAlpha = LerpFloat(0.12f, 0.28f, tiltMagnitude) * baseColor.a;
    const RgbaColor featherInner = WithAlpha(baseColor, featherAlpha);
    const RgbaColor featherOuter = WithAlpha(baseColor, 0.0f);

    AddGradientStripSegment(vertices, start, end, normal,
        -startFullWidth * 0.5f, featherBoundary(startFullWidth),
        -endFullWidth * 0.5f, featherBoundary(endFullWidth),
        featherOuter, featherInner, surfaceWidth, surfaceHeight);
    AddGradientStripSegment(vertices, start, end, normal,
        featherBoundary(startFullWidth), coreBoundary(startFullWidth),
        featherBoundary(endFullWidth), coreBoundary(endFullWidth),
        coreColor, coreColor, surfaceWidth, surfaceHeight);
    AddGradientStripSegment(vertices, start, end, normal,
        coreBoundary(startFullWidth), outerBoundary(startFullWidth),
        coreBoundary(endFullWidth), outerBoundary(endFullWidth),
        shadowInner, shadowOuter, surfaceWidth, surfaceHeight);
}

void AddPencilPointStamp(std::vector<RenderVertex>& vertices, const InkPointSnapshot& point, const EngineState& engine,
    const std::string& colorHex, bool predicted, float surfaceWidth, float surfaceHeight)
{
    const float tiltMagnitude = ComputeTiltMagnitude(point);
    if (tiltMagnitude < 0.18f) {
        const float radius = ComputeStrokeWidthPx(engine, "pencil", point, predicted) * 0.5f;
        AddRect(vertices, point.x - radius, point.y - radius, point.x + radius, point.y + radius,
            ResolveStrokeColor("pencil", colorHex, predicted), surfaceWidth, surfaceHeight);
        return;
    }

    Vec2f normal = ResolvePencilAxis(point, point);
    if (VecLength(normal) <= 0.0f) {
        normal = { 0.0f, 1.0f };
    }
    normal = NormalizeVec(normal);
    const Vec2f tangent = NormalizeVec(Perpendicular(normal));
    const float baseWidth = ComputeStrokeWidthPx(engine, "pencil", point, predicted);
    const float fullWidth = std::max(1.0f, baseWidth * LerpFloat(1.0f, 2.4f, tiltMagnitude));
    const float halfLength = std::max(baseWidth * 0.65f, 1.2f);

    InkPointSnapshot start = point;
    InkPointSnapshot end = point;
    start.x -= tangent.x * halfLength;
    start.y -= tangent.y * halfLength;
    end.x += tangent.x * halfLength;
    end.y += tangent.y * halfLength;

    const RgbaColor baseColor = ResolveStrokeColor("pencil", colorHex, predicted);
    const RgbaColor coreColor = WithAlpha(baseColor, baseColor.a * 0.82f);
    const float shadowAlpha = LerpFloat(0.42f, 0.62f, tiltMagnitude) * baseColor.a;
    const RgbaColor shadowInner = WithAlpha(baseColor, shadowAlpha);
    const RgbaColor shadowOuter = WithAlpha(baseColor, shadowAlpha * 0.55f);
    const float featherAlpha = LerpFloat(0.12f, 0.28f, tiltMagnitude) * baseColor.a;
    const RgbaColor featherInner = WithAlpha(baseColor, featherAlpha);
    const RgbaColor featherOuter = WithAlpha(baseColor, 0.0f);
    const float featherEdge = -fullWidth * 0.5f + fullWidth * 0.20f;
    const float coreEdge = featherEdge + fullWidth * 0.35f;

    AddGradientStripSegment(vertices, start, end, normal,
        -fullWidth * 0.5f, featherEdge,
        -fullWidth * 0.5f, featherEdge,
        featherOuter, featherInner, surfaceWidth, surfaceHeight);
    AddGradientStripSegment(vertices, start, end, normal,
        featherEdge, coreEdge,
        featherEdge, coreEdge,
        coreColor, coreColor, surfaceWidth, surfaceHeight);
    AddGradientStripSegment(vertices, start, end, normal,
        coreEdge, fullWidth * 0.5f,
        coreEdge, fullWidth * 0.5f,
        shadowInner, shadowOuter, surfaceWidth, surfaceHeight);
}

void AddStrokeMesh(std::vector<RenderVertex>& vertices, const std::vector<InkPointSnapshot>& sourcePoints,
    const EngineState& engine, const std::string& tool, const std::string& colorHex, bool predicted,
    float surfaceWidth, float surfaceHeight)
{
    if (sourcePoints.empty()) {
        return;
    }

    const std::vector<InkPointSnapshot> points = BuildSmoothedStroke(sourcePoints);
    if (points.size() == 1) {
        const float radius = ComputeStrokeWidthPx(engine, tool, points.front(), predicted) * 0.5f;
        AddRect(vertices, points.front().x - radius, points.front().y - radius,
            points.front().x + radius, points.front().y + radius,
            ResolveStrokeColor(tool, colorHex, predicted), surfaceWidth, surfaceHeight);
        return;
    }

    for (size_t index = 1; index < points.size(); ++index) {
        const InkPointSnapshot& start = points[index - 1];
        const InkPointSnapshot& end = points[index];
        const float dx = end.x - start.x;
        const float dy = end.y - start.y;
        const float length = std::hypot(dx, dy);
        if (length < 0.001f) {
            continue;
        }

        const float nx = -dy / length;
        const float ny = dx / length;
        const float halfStart = ComputeStrokeWidthPx(engine, tool, start, predicted) * 0.5f;
        const float halfEnd = ComputeStrokeWidthPx(engine, tool, end, predicted) * 0.5f;
        const RgbaColor color = ResolveStrokeColor(tool, colorHex, predicted);
        AddGradientStripSegment(vertices, start, end, { nx, ny }, halfStart, -halfStart, halfEnd, -halfEnd,
            color, color, surfaceWidth, surfaceHeight);
    }
}

void AddPencilStrokeMesh(std::vector<RenderVertex>& vertices, const std::vector<InkPointSnapshot>& sourcePoints,
    const EngineState& engine, const std::string& colorHex, bool predicted, float surfaceWidth, float surfaceHeight)
{
    if (sourcePoints.empty()) {
        return;
    }

    const std::vector<InkPointSnapshot> points = BuildSmoothedStroke(sourcePoints);
    if (points.size() == 1) {
        AddPencilPointStamp(vertices, points.front(), engine, colorHex, predicted, surfaceWidth, surfaceHeight);
        return;
    }

    for (size_t index = 1; index < points.size(); ++index) {
        const InkPointSnapshot& start = points[index - 1];
        const InkPointSnapshot& end = points[index];
        if (DistanceBetweenVec(PointPosition(start), PointPosition(end)) < 0.001f) {
            continue;
        }
        AddPencilStripSegment(vertices, start, end, engine, colorHex, predicted, surfaceWidth, surfaceHeight);
    }
}

void AddToolStrokeMesh(std::vector<RenderVertex>& vertices, const std::vector<InkPointSnapshot>& sourcePoints,
    const EngineState& engine, const std::string& tool, const std::string& colorHex, bool predicted,
    float surfaceWidth, float surfaceHeight)
{
    if (tool == "pencil") {
        AddPencilStrokeMesh(vertices, sourcePoints, engine, colorHex, predicted, surfaceWidth, surfaceHeight);
        return;
    }
    AddStrokeMesh(vertices, sourcePoints, engine, tool, colorHex, predicted, surfaceWidth, surfaceHeight);
}

void AddInfiniteGrid(std::vector<RenderVertex>& vertices, float surfaceWidth, float surfaceHeight)
{
    const RgbaColor minor = ParseColorHex("#D8E0EB", 0.70f);
    const RgbaColor major = ParseColorHex("#B9C5D6", 0.86f);
    for (int x = 0; x <= static_cast<int>(surfaceWidth); x += 48) {
        const bool isMajor = x % 240 == 0;
        const float thickness = isMajor ? 1.6f : 0.8f;
        AddRect(vertices, static_cast<float>(x) - thickness * 0.5f, 0.0f,
            static_cast<float>(x) + thickness * 0.5f, surfaceHeight,
            isMajor ? major : minor, surfaceWidth, surfaceHeight);
    }
    for (int y = 0; y <= static_cast<int>(surfaceHeight); y += 48) {
        const bool isMajor = y % 240 == 0;
        const float thickness = isMajor ? 1.6f : 0.8f;
        AddRect(vertices, 0.0f, static_cast<float>(y) - thickness * 0.5f,
            surfaceWidth, static_cast<float>(y) + thickness * 0.5f,
            isMajor ? major : minor, surfaceWidth, surfaceHeight);
    }
}

float DistancePointToSegmentSquared(float px, float py, float ax, float ay, float bx, float by)
{
    const float abx = bx - ax;
    const float aby = by - ay;
    const float lengthSquared = abx * abx + aby * aby;
    if (lengthSquared <= 0.0001f) {
        const float dx = px - ax;
        const float dy = py - ay;
        return dx * dx + dy * dy;
    }

    const float t = std::clamp(((px - ax) * abx + (py - ay) * aby) / lengthSquared, 0.0f, 1.0f);
    const float closestX = ax + abx * t;
    const float closestY = ay + aby * t;
    const float dx = px - closestX;
    const float dy = py - closestY;
    return dx * dx + dy * dy;
}

bool EraseNearestStroke(std::vector<StrokeRenderObject>& strokes, const InkPointSnapshot& point)
{
    int eraseIndex = -1;
    float bestDistance = 22.0f * 22.0f;
    for (size_t strokeIndex = 0; strokeIndex < strokes.size(); ++strokeIndex) {
        const std::vector<InkPointSnapshot>& points = strokes[strokeIndex].points;
        for (size_t index = 1; index < points.size(); ++index) {
            const float distance = DistancePointToSegmentSquared(
                point.x, point.y, points[index - 1].x, points[index - 1].y, points[index].x, points[index].y);
            if (distance < bestDistance) {
                bestDistance = distance;
                eraseIndex = static_cast<int>(strokeIndex);
            }
        }
    }

    if (eraseIndex < 0) {
        return false;
    }
    strokes.erase(strokes.begin() + eraseIndex);
    return true;
}

struct StrokeBounds {
    float minX = 0.0f;
    float minY = 0.0f;
    float maxX = 0.0f;
    float maxY = 0.0f;
};

float DistanceBetween(const InkPointSnapshot& a, const InkPointSnapshot& b)
{
    return std::hypot(b.x - a.x, b.y - a.y);
}

StrokeBounds ComputeStrokeBounds(const std::vector<InkPointSnapshot>& points)
{
    StrokeBounds bounds;
    if (points.empty()) {
        return bounds;
    }

    bounds.minX = bounds.maxX = points.front().x;
    bounds.minY = bounds.maxY = points.front().y;
    for (const InkPointSnapshot& point : points) {
        bounds.minX = std::min(bounds.minX, point.x);
        bounds.minY = std::min(bounds.minY, point.y);
        bounds.maxX = std::max(bounds.maxX, point.x);
        bounds.maxY = std::max(bounds.maxY, point.y);
    }
    return bounds;
}

float ComputePathLength(const std::vector<InkPointSnapshot>& points)
{
    float pathLength = 0.0f;
    for (size_t index = 1; index < points.size(); ++index) {
        pathLength += DistanceBetween(points[index - 1], points[index]);
    }
    return pathLength;
}

InkPointSnapshot MakeShapePoint(const InkPointSnapshot& seed, float x, float y, int64_t timestamp)
{
    InkPointSnapshot point = seed;
    point.x = x;
    point.y = y;
    point.windowX = x;
    point.windowY = y;
    point.timeStamp = timestamp;
    point.historical = false;
    point.predicted = false;
    return point;
}

std::vector<InkPointSnapshot> BuildCanonicalLinePoints(const std::vector<InkPointSnapshot>& points)
{
    if (points.size() < 2) {
        return points;
    }

    const InkPointSnapshot& first = points.front();
    const InkPointSnapshot& last = points.back();
    float dx = last.x - first.x;
    float dy = last.y - first.y;
    const float length = std::hypot(dx, dy);
    if (length <= 0.001f) {
        return { first, last };
    }

    const float angle = std::atan2(dy, dx) * 180.0f / kPi;
    const float snapTargets[] = { -180.0f, -135.0f, -90.0f, -45.0f, 0.0f, 45.0f, 90.0f, 135.0f, 180.0f };
    float snappedAngle = angle;
    float bestDelta = 360.0f;
    for (float candidate : snapTargets) {
        const float delta = std::abs(angle - candidate);
        if (delta < bestDelta) {
            bestDelta = delta;
            snappedAngle = candidate;
        }
    }

    InkPointSnapshot snappedLast = last;
    if (bestDelta <= 10.0f) {
        const float radian = snappedAngle * kPi / 180.0f;
        snappedLast.x = first.x + std::cos(radian) * length;
        snappedLast.y = first.y + std::sin(radian) * length;
        snappedLast.windowX = snappedLast.x;
        snappedLast.windowY = snappedLast.y;
        snappedLast.displayX = snappedLast.x;
        snappedLast.displayY = snappedLast.y;
    }
    return { first, snappedLast };
}

std::vector<InkPointSnapshot> BuildCanonicalRectanglePoints(
    const StrokeBounds& bounds, const InkPointSnapshot& seed, int64_t timestamp)
{
    return {
        MakeShapePoint(seed, bounds.minX, bounds.minY, timestamp),
        MakeShapePoint(seed, bounds.maxX, bounds.minY, timestamp + 1),
        MakeShapePoint(seed, bounds.maxX, bounds.maxY, timestamp + 2),
        MakeShapePoint(seed, bounds.minX, bounds.maxY, timestamp + 3),
        MakeShapePoint(seed, bounds.minX, bounds.minY, timestamp + 4)
    };
}

std::vector<InkPointSnapshot> BuildCanonicalTrianglePoints(
    const StrokeBounds& bounds, const InkPointSnapshot& seed, int64_t timestamp)
{
    const float centerX = (bounds.minX + bounds.maxX) * 0.5f;
    return {
        MakeShapePoint(seed, centerX, bounds.minY, timestamp),
        MakeShapePoint(seed, bounds.maxX, bounds.maxY, timestamp + 1),
        MakeShapePoint(seed, bounds.minX, bounds.maxY, timestamp + 2),
        MakeShapePoint(seed, centerX, bounds.minY, timestamp + 3)
    };
}

std::vector<InkPointSnapshot> BuildCanonicalEllipsePoints(
    const StrokeBounds& bounds, const InkPointSnapshot& seed, int64_t timestamp)
{
    std::vector<InkPointSnapshot> points;
    points.reserve(25);
    const float centerX = (bounds.minX + bounds.maxX) * 0.5f;
    const float centerY = (bounds.minY + bounds.maxY) * 0.5f;
    const float radiusX = std::max(8.0f, (bounds.maxX - bounds.minX) * 0.5f);
    const float radiusY = std::max(8.0f, (bounds.maxY - bounds.minY) * 0.5f);
    for (int step = 0; step <= 24; ++step) {
        const float t = (static_cast<float>(step) / 24.0f) * 2.0f * kPi;
        points.push_back(MakeShapePoint(
            seed, centerX + std::cos(t) * radiusX, centerY + std::sin(t) * radiusY, timestamp + step));
    }
    return points;
}

std::vector<InkPointSnapshot> BuildCanonicalArrowPoints(
    const InkPointSnapshot& start, const InkPointSnapshot& tip, const InkPointSnapshot& wing, int64_t timestamp)
{
    const float shaftDx = tip.x - start.x;
    const float shaftDy = tip.y - start.y;
    const float shaftLength = std::hypot(shaftDx, shaftDy);
    if (shaftLength <= 0.001f) {
        return { start, tip };
    }

    const float axisX = (start.x - tip.x) / shaftLength;
    const float axisY = (start.y - tip.y) / shaftLength;
    const float wingDx = wing.x - tip.x;
    const float wingDy = wing.y - tip.y;
    const float projection = wingDx * axisX + wingDy * axisY;
    const float mirroredDx = 2.0f * projection * axisX - wingDx;
    const float mirroredDy = 2.0f * projection * axisY - wingDy;
    const InkPointSnapshot mirroredWing = MakeShapePoint(tip, tip.x + mirroredDx, tip.y + mirroredDy, timestamp + 4);

    return {
        MakeShapePoint(start, start.x, start.y, timestamp),
        MakeShapePoint(tip, tip.x, tip.y, timestamp + 1),
        MakeShapePoint(wing, wing.x, wing.y, timestamp + 2),
        MakeShapePoint(tip, tip.x, tip.y, timestamp + 3),
        mirroredWing
    };
}

std::vector<InkPointSnapshot> DownsampleStrokePoints(const std::vector<InkPointSnapshot>& inputPoints, bool closed)
{
    if (inputPoints.size() <= 2) {
        return inputPoints;
    }

    std::vector<InkPointSnapshot> simplified;
    simplified.reserve(inputPoints.size());
    simplified.push_back(inputPoints.front());

    for (size_t index = 1; index < inputPoints.size(); ++index) {
        if (DistanceBetween(simplified.back(), inputPoints[index]) >= 14.0f) {
            simplified.push_back(inputPoints[index]);
        }
    }

    if (!closed && DistanceBetween(simplified.back(), inputPoints.back()) > 0.1f) {
        simplified.push_back(inputPoints.back());
    }
    if (closed && simplified.size() > 2 && DistanceBetween(simplified.front(), simplified.back()) < 10.0f) {
        simplified.pop_back();
    }
    return simplified;
}

std::vector<InkPointSnapshot> ExtractStrokeCorners(const std::vector<InkPointSnapshot>& inputPoints, bool closed)
{
    std::vector<InkPointSnapshot> simplified = DownsampleStrokePoints(inputPoints, closed);
    std::vector<InkPointSnapshot> corners;
    if (simplified.size() < 3) {
        return corners;
    }

    const size_t pointCount = simplified.size();
    const size_t endIndex = closed ? pointCount : pointCount - 1;
    for (size_t index = closed ? 0 : 1; index < endIndex; ++index) {
        const InkPointSnapshot& previous = simplified[(index + pointCount - 1) % pointCount];
        const InkPointSnapshot& current = simplified[index];
        const InkPointSnapshot& next = simplified[(index + 1) % pointCount];
        const float ax = current.x - previous.x;
        const float ay = current.y - previous.y;
        const float bx = next.x - current.x;
        const float by = next.y - current.y;
        const float lengthA = std::hypot(ax, ay);
        const float lengthB = std::hypot(bx, by);
        if (lengthA < 8.0f || lengthB < 8.0f) {
            continue;
        }

        const float cosine = std::clamp((ax * bx + ay * by) / (lengthA * lengthB), -1.0f, 1.0f);
        const float angle = std::acos(cosine) * 180.0f / kPi;
        if (angle <= 132.0f) {
            if (corners.empty() || DistanceBetween(corners.back(), current) > 18.0f) {
                corners.push_back(current);
            }
        }
    }
    return corners;
}

float ComputeAverageEdgeDistance(const std::vector<InkPointSnapshot>& points, const StrokeBounds& bounds)
{
    if (points.empty()) {
        return 0.0f;
    }

    float totalDistance = 0.0f;
    for (const InkPointSnapshot& point : points) {
        totalDistance += std::min(
            std::min(std::abs(point.x - bounds.minX), std::abs(point.x - bounds.maxX)),
            std::min(std::abs(point.y - bounds.minY), std::abs(point.y - bounds.maxY)));
    }
    return totalDistance / static_cast<float>(points.size());
}

float ComputeEllipseDeviation(const std::vector<InkPointSnapshot>& points, const StrokeBounds& bounds)
{
    const float radiusX = std::max(1.0f, (bounds.maxX - bounds.minX) * 0.5f);
    const float radiusY = std::max(1.0f, (bounds.maxY - bounds.minY) * 0.5f);
    const float centerX = (bounds.minX + bounds.maxX) * 0.5f;
    const float centerY = (bounds.minY + bounds.maxY) * 0.5f;

    float totalDeviation = 0.0f;
    for (const InkPointSnapshot& point : points) {
        const float normalized = std::sqrt(
            std::pow((point.x - centerX) / radiusX, 2.0f) +
            std::pow((point.y - centerY) / radiusY, 2.0f));
        totalDeviation += std::abs(1.0f - normalized);
    }
    return totalDeviation / static_cast<float>(points.size());
}

bool IsLineLike(const std::vector<InkPointSnapshot>& points)
{
    if (points.size() < 2) {
        return false;
    }

    const float directDistance = DistanceBetween(points.front(), points.back());
    const float pathLength = ComputePathLength(points);
    if (directDistance < 40.0f || pathLength < 50.0f || directDistance <= 0.001f) {
        return false;
    }

    float maxDeviation = 0.0f;
    for (const InkPointSnapshot& point : points) {
        maxDeviation = std::max(maxDeviation, std::sqrt(DistancePointToSegmentSquared(
            point.x, point.y, points.front().x, points.front().y, points.back().x, points.back().y)));
    }
    return pathLength / directDistance <= 1.10f && maxDeviation <= std::max(14.0f, directDistance * 0.09f);
}

StrokeRenderObject BuildStrokeObject(
    const std::vector<InkPointSnapshot>& points, const std::string& tool, const std::string& colorHex,
    const std::string& shapeType);

bool TryBuildArrowStroke(const std::vector<InkPointSnapshot>& inputPoints, const std::string& tool,
    const std::string& colorHex, StrokeRenderObject& stroke)
{
    if (inputPoints.size() < 5) {
        return false;
    }

    size_t tipIndex = 1;
    float maxDistanceFromStart = 0.0f;
    for (size_t index = 1; index + 1 < inputPoints.size(); ++index) {
        const float distance = DistanceBetween(inputPoints.front(), inputPoints[index]);
        if (distance > maxDistanceFromStart) {
            maxDistanceFromStart = distance;
            tipIndex = index;
        }
    }

    if (tipIndex < 2 || tipIndex >= inputPoints.size() - 1) {
        return false;
    }

    std::vector<InkPointSnapshot> shaftPoints(inputPoints.begin(), inputPoints.begin() + static_cast<long long>(tipIndex + 1));
    if (!IsLineLike(shaftPoints)) {
        return false;
    }

    const InkPointSnapshot& start = inputPoints.front();
    const InkPointSnapshot& tip = inputPoints[tipIndex];
    const InkPointSnapshot& wing = inputPoints.back();
    const float shaftLength = DistanceBetween(start, tip);
    const float wingLength = DistanceBetween(tip, wing);
    if (shaftLength < 60.0f || wingLength < 12.0f || wingLength > shaftLength * 0.42f) {
        return false;
    }

    const float shaftX = (tip.x - start.x) / std::max(shaftLength, 0.001f);
    const float shaftY = (tip.y - start.y) / std::max(shaftLength, 0.001f);
    const float backwardX = -shaftX;
    const float backwardY = -shaftY;
    const float normalizedWingX = (wing.x - tip.x) / std::max(wingLength, 0.001f);
    const float normalizedWingY = (wing.y - tip.y) / std::max(wingLength, 0.001f);
    const float cosine = std::clamp(
        backwardX * normalizedWingX + backwardY * normalizedWingY, -1.0f, 1.0f);
    const float headAngle = std::acos(cosine) * 180.0f / kPi;
    if (headAngle < 18.0f || headAngle > 78.0f) {
        return false;
    }

    stroke = BuildStrokeObject(
        BuildCanonicalArrowPoints(start, tip, wing, start.timeStamp), tool, colorHex, "arrow");
    return true;
}

StrokeRenderObject BuildStrokeObject(
    const std::vector<InkPointSnapshot>& points, const std::string& tool, const std::string& colorHex,
    const std::string& shapeType)
{
    StrokeRenderObject stroke;
    stroke.points = points;
    stroke.tool = tool;
    stroke.colorHex = colorHex;
    stroke.shapeType = shapeType;
    return stroke;
}

std::string GenerateStrokeObjectId(EngineState& engine)
{
    const std::string prefix = engine.activeDocumentId.empty() ? engine.engineId : engine.activeDocumentId;
    const std::string objectId = prefix + "-stroke-" + std::to_string(engine.nextObjectCounter);
    engine.nextObjectCounter += 1;
    return objectId;
}

void EnsureStrokeObjectIds(EngineState& engine)
{
    for (const StrokeRenderObject& stroke : engine.committedStrokes) {
        if (stroke.objectId.empty()) {
            continue;
        }
        const size_t dashIndex = stroke.objectId.rfind('-');
        if (dashIndex == std::string::npos || dashIndex + 1 >= stroke.objectId.size()) {
            continue;
        }
        try {
            const int nextCandidate = std::stoi(stroke.objectId.substr(dashIndex + 1)) + 1;
            engine.nextObjectCounter = std::max(engine.nextObjectCounter, nextCandidate);
        } catch (...) {
        }
    }
    for (StrokeRenderObject& stroke : engine.committedStrokes) {
        if (stroke.objectId.empty()) {
            stroke.objectId = GenerateStrokeObjectId(engine);
        }
    }
}

void ClearStrokeSelection(std::vector<StrokeRenderObject>& strokes)
{
    for (StrokeRenderObject& stroke : strokes) {
        stroke.selected = false;
    }
}

bool HasSelectedStroke(const std::vector<StrokeRenderObject>& strokes)
{
    for (const StrokeRenderObject& stroke : strokes) {
        if (stroke.selected) {
            return true;
        }
    }
    return false;
}

bool EraseStrokeSegments(const StrokeRenderObject& source, const InkPointSnapshot& point, float radius,
    std::vector<StrokeRenderObject>& output)
{
    const float radiusSquared = radius * radius;
    bool pointRemoved = false;
    std::vector<InkPointSnapshot> chunk;
    chunk.reserve(source.points.size());

    for (const InkPointSnapshot& sample : source.points) {
        const float dx = sample.x - point.x;
        const float dy = sample.y - point.y;
        const bool inside = (dx * dx + dy * dy) <= radiusSquared;
        if (inside) {
            pointRemoved = true;
            if (chunk.size() > 1) {
                StrokeRenderObject stroke = source;
                stroke.points = chunk;
                stroke.selected = false;
                output.push_back(std::move(stroke));
            }
            chunk.clear();
            continue;
        }
        chunk.push_back(sample);
    }

    if (chunk.size() > 1) {
        StrokeRenderObject stroke = source;
        stroke.points = chunk;
        stroke.selected = false;
        output.push_back(std::move(stroke));
    }
    return pointRemoved;
}

bool EraseWithHybridStrategy(std::vector<StrokeRenderObject>& strokes, const InkPointSnapshot& point)
{
    constexpr float kObjectEraseRadius = 22.0f;
    constexpr float kSegmentEraseRadius = 18.0f;

    bool changed = false;
    std::vector<StrokeRenderObject> updated;
    updated.reserve(strokes.size());

    for (const StrokeRenderObject& stroke : strokes) {
        bool hit = false;
        for (size_t index = 1; index < stroke.points.size(); ++index) {
            const float distance = DistancePointToSegmentSquared(
                point.x, point.y, stroke.points[index - 1].x, stroke.points[index - 1].y, stroke.points[index].x, stroke.points[index].y);
            if (distance <= kObjectEraseRadius * kObjectEraseRadius) {
                hit = true;
                break;
            }
        }

        if (!hit && stroke.points.size() == 1) {
            const float dx = stroke.points.front().x - point.x;
            const float dy = stroke.points.front().y - point.y;
            hit = (dx * dx + dy * dy) <= kObjectEraseRadius * kObjectEraseRadius;
        }

        if (!hit) {
            updated.push_back(stroke);
            continue;
        }

        changed = true;
        if (stroke.shapeType != "freehand" || stroke.points.size() < 6) {
            continue;
        }

        if (!EraseStrokeSegments(stroke, point, kSegmentEraseRadius, updated)) {
            continue;
        }
    }

    if (changed) {
        strokes = std::move(updated);
    }
    return changed;
}

StrokeBounds ComputeSelectedBounds(const std::vector<StrokeRenderObject>& strokes)
{
    StrokeBounds bounds {};
    bool initialized = false;
    for (const StrokeRenderObject& stroke : strokes) {
        if (!stroke.selected || stroke.points.empty()) {
            continue;
        }
        const StrokeBounds strokeBounds = ComputeStrokeBounds(stroke.points);
        if (!initialized) {
            bounds = strokeBounds;
            initialized = true;
            continue;
        }
        bounds.minX = std::min(bounds.minX, strokeBounds.minX);
        bounds.minY = std::min(bounds.minY, strokeBounds.minY);
        bounds.maxX = std::max(bounds.maxX, strokeBounds.maxX);
        bounds.maxY = std::max(bounds.maxY, strokeBounds.maxY);
    }
    return bounds;
}

bool IsPointInsideBounds(const StrokeBounds& bounds, float x, float y, float padding)
{
    return x >= bounds.minX - padding && x <= bounds.maxX + padding &&
        y >= bounds.minY - padding && y <= bounds.maxY + padding;
}

InkPointSnapshot ComputeStrokeCentroid(const StrokeRenderObject& stroke)
{
    InkPointSnapshot centroid = stroke.points.empty() ? InkPointSnapshot {} : stroke.points.front();
    if (stroke.points.empty()) {
        return centroid;
    }

    float totalX = 0.0f;
    float totalY = 0.0f;
    for (const InkPointSnapshot& point : stroke.points) {
        totalX += point.x;
        totalY += point.y;
    }
    const float count = static_cast<float>(stroke.points.size());
    centroid.x = totalX / count;
    centroid.y = totalY / count;
    centroid.windowX = centroid.x;
    centroid.windowY = centroid.y;
    return centroid;
}

bool IsPointInPolygon(const std::vector<InkPointSnapshot>& polygon, float x, float y)
{
    if (polygon.size() < 3) {
        return false;
    }

    bool inside = false;
    size_t previous = polygon.size() - 1;
    for (size_t current = 0; current < polygon.size(); ++current) {
        const InkPointSnapshot& a = polygon[current];
        const InkPointSnapshot& b = polygon[previous];
        const bool intersect = ((a.y > y) != (b.y > y)) &&
            (x < (b.x - a.x) * (y - a.y) / std::max(0.001f, b.y - a.y) + a.x);
        if (intersect) {
            inside = !inside;
        }
        previous = current;
    }
    return inside;
}

size_t SelectStrokesByLasso(
    std::vector<StrokeRenderObject>& strokes, const std::vector<InkPointSnapshot>& polygon)
{
    ClearStrokeSelection(strokes);
    size_t selectedCount = 0;
    for (StrokeRenderObject& stroke : strokes) {
        const InkPointSnapshot centroid = ComputeStrokeCentroid(stroke);
        stroke.selected = IsPointInPolygon(polygon, centroid.x, centroid.y);
        if (stroke.selected) {
            selectedCount += 1;
        }
    }
    return selectedCount;
}

void MoveSelectedStrokes(std::vector<StrokeRenderObject>& strokes, float dx, float dy)
{
    if (std::abs(dx) < 0.001f && std::abs(dy) < 0.001f) {
        return;
    }

    for (StrokeRenderObject& stroke : strokes) {
        if (!stroke.selected) {
            continue;
        }
        for (InkPointSnapshot& point : stroke.points) {
            point.x += dx;
            point.y += dy;
            point.windowX += dx;
            point.windowY += dy;
            point.displayX += dx;
            point.displayY += dy;
        }
    }
}

StrokeRenderObject ApplyShapeRecognition(
    const std::vector<InkPointSnapshot>& inputPoints, const std::string& tool, const std::string& colorHex, bool enabled)
{
    if (inputPoints.empty()) {
        return BuildStrokeObject(inputPoints, tool, colorHex, "freehand");
    }
    if (!enabled || inputPoints.size() < 4) {
        return BuildStrokeObject(inputPoints, tool, colorHex, "freehand");
    }

    const StrokeBounds bounds = ComputeStrokeBounds(inputPoints);
    const float width = bounds.maxX - bounds.minX;
    const float height = bounds.maxY - bounds.minY;
    const float diagonal = std::hypot(width, height);
    const float pathLength = ComputePathLength(inputPoints);
    const bool closed = DistanceBetween(inputPoints.front(), inputPoints.back()) <= std::max(18.0f, diagonal * 0.18f);
    const InkPointSnapshot& seed = inputPoints.front();
    const int64_t timestamp = seed.timeStamp;

    if (!closed) {
        StrokeRenderObject arrowStroke;
        if (TryBuildArrowStroke(inputPoints, tool, colorHex, arrowStroke)) {
            return arrowStroke;
        }
    }

    if (!closed && IsLineLike(inputPoints)) {
        return BuildStrokeObject(BuildCanonicalLinePoints(inputPoints), tool, colorHex, "line");
    }

    if (!closed || width < 22.0f || height < 22.0f || pathLength < 80.0f) {
        return BuildStrokeObject(inputPoints, tool, colorHex, "freehand");
    }

    const std::vector<InkPointSnapshot> corners = ExtractStrokeCorners(inputPoints, true);
    const float edgeDistance = ComputeAverageEdgeDistance(inputPoints, bounds);
    const float ellipseDeviation = ComputeEllipseDeviation(inputPoints, bounds);
    const float aspectRatio = width > height ? width / std::max(height, 1.0f) : height / std::max(width, 1.0f);
    const float rectangleThreshold = std::min(width, height) * 0.16f;

    // 中文注释：先识别圆/椭圆，避免圆形被角点噪声误判为多边形。
    if (corners.size() <= 2 && ellipseDeviation < 0.23f) {
        const std::string shapeType = aspectRatio <= 1.18f ? "circle" : "ellipse";
        return BuildStrokeObject(BuildCanonicalEllipsePoints(bounds, seed, timestamp), tool, colorHex, shapeType);
    }

    // 中文注释：矩形判定使用“角点数量 + 点到包围盒边缘距离”双条件，避免普通手写误吸附。
    if (corners.size() >= 4 && corners.size() <= 6 && edgeDistance <= rectangleThreshold) {
        return BuildStrokeObject(BuildCanonicalRectanglePoints(bounds, seed, timestamp), tool, colorHex, "rectangle");
    }

    if (corners.size() >= 3 && corners.size() <= 4) {
        return BuildStrokeObject(BuildCanonicalTrianglePoints(bounds, seed, timestamp), tool, colorHex, "triangle");
    }

    return BuildStrokeObject(inputPoints, tool, colorHex, "freehand");
}

void PushUndoSnapshot(EngineState& engine)
{
    engine.undoSnapshots.push_back(engine.committedStrokes);
    if (engine.undoSnapshots.size() > kMaxUndoDepth) {
        engine.undoSnapshots.erase(engine.undoSnapshots.begin());
    }
    engine.redoSnapshots.clear();
}

void RefreshLastCommittedStrokeType(EngineState& engine)
{
    engine.lastCommittedStrokeType = engine.committedStrokes.empty()
        ? "none"
        : engine.committedStrokes.back().shapeType;
}

std::string EscapeJsonString(const std::string& input)
{
    std::string escaped;
    escaped.reserve(input.size() + 8);
    for (char character : input) {
        switch (character) {
            case '\\':
                escaped += "\\\\";
                break;
            case '"':
                escaped += "\\\"";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\r':
                escaped += "\\r";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                escaped += character;
                break;
        }
    }
    return escaped;
}

std::string ReadTextFile(const std::string& path)
{
    std::ifstream input(path, std::ios::in | std::ios::binary);
    if (!input.is_open()) {
        return "";
    }
    std::ostringstream buffer;
    buffer << input.rdbuf();
    return buffer.str();
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

bool IsJsonWhitespace(char character)
{
    return character == ' ' || character == '\t' || character == '\n' || character == '\r';
}

size_t SkipJsonWhitespace(const std::string& text, size_t index)
{
    while (index < text.size() && IsJsonWhitespace(text[index])) {
        ++index;
    }
    return index;
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

std::string ExtractJsonStringValue(const std::string& objectText, const std::string& key, const std::string& fallback)
{
    const std::string keyToken = "\"" + key + "\"";
    const size_t keyIndex = objectText.find(keyToken);
    if (keyIndex == std::string::npos) {
        return fallback;
    }

    size_t cursor = objectText.find(':', keyIndex + keyToken.size());
    if (cursor == std::string::npos) {
        return fallback;
    }
    cursor = SkipJsonWhitespace(objectText, cursor + 1);
    if (cursor >= objectText.size() || objectText[cursor] != '"') {
        return fallback;
    }

    std::string value;
    for (size_t index = cursor + 1; index < objectText.size(); ++index) {
        const char character = objectText[index];
        if (character == '"' && objectText[index - 1] != '\\') {
            return value;
        }
        if (character == '\\' && index + 1 < objectText.size()) {
            const char next = objectText[index + 1];
            switch (next) {
                case 'n':
                    value.push_back('\n');
                    break;
                case 'r':
                    value.push_back('\r');
                    break;
                case 't':
                    value.push_back('\t');
                    break;
                default:
                    value.push_back(next);
                    break;
            }
            ++index;
            continue;
        }
        value.push_back(character);
    }
    return fallback;
}

double ExtractJsonNumberValue(const std::string& objectText, const std::string& key, double fallback)
{
    const std::string keyToken = "\"" + key + "\"";
    const size_t keyIndex = objectText.find(keyToken);
    if (keyIndex == std::string::npos) {
        return fallback;
    }

    size_t cursor = objectText.find(':', keyIndex + keyToken.size());
    if (cursor == std::string::npos) {
        return fallback;
    }
    cursor = SkipJsonWhitespace(objectText, cursor + 1);
    size_t end = cursor;
    while (end < objectText.size()) {
        const char character = objectText[end];
        if ((character >= '0' && character <= '9') || character == '-' || character == '+' ||
            character == '.' || character == 'e' || character == 'E') {
            ++end;
            continue;
        }
        break;
    }
    if (end <= cursor) {
        return fallback;
    }

    try {
        return std::stod(objectText.substr(cursor, end - cursor));
    } catch (...) {
        return fallback;
    }
}

bool ExtractJsonBoolValue(const std::string& objectText, const std::string& key, bool fallback)
{
    const std::string keyToken = "\"" + key + "\"";
    const size_t keyIndex = objectText.find(keyToken);
    if (keyIndex == std::string::npos) {
        return fallback;
    }

    size_t cursor = objectText.find(':', keyIndex + keyToken.size());
    if (cursor == std::string::npos) {
        return fallback;
    }
    cursor = SkipJsonWhitespace(objectText, cursor + 1);
    if (objectText.compare(cursor, 4, "true") == 0) {
        return true;
    }
    if (objectText.compare(cursor, 5, "false") == 0) {
        return false;
    }
    return fallback;
}

std::string SerializeInputTraceJson(const InputStrokeTrace& trace)
{
    std::ostringstream builder;
    builder << "{\n"
            << "  \"version\": " << trace.version << ",\n"
            << "  \"recordedAt\": " << trace.recordedAt << ",\n"
            << "  \"engineId\": \"" << EscapeJsonString(trace.engineId) << "\",\n"
            << "  \"documentId\": \"" << EscapeJsonString(trace.documentId) << "\",\n"
            << "  \"xComponentId\": \"" << EscapeJsonString(trace.xComponentId) << "\",\n"
            << "  \"sampleCount\": " << trace.samples.size() << ",\n"
            << "  \"samples\": [";
    for (size_t index = 0; index < trace.samples.size(); ++index) {
        const InputSample& sample = trace.samples[index];
        if (index > 0) {
            builder << ",";
        }
        builder << "\n    {"
                << "\"sequence\": " << sample.sequence
                << ", \"type\": \"" << EscapeJsonString(InputSampleTypeToString(sample.type)) << "\""
                << ", \"timeStamp\": " << sample.timeStamp
                << ", \"pointerId\": " << sample.pointerId
                << ", \"activePointerCount\": " << sample.activePointerCount
                << ", \"action\": " << sample.action
                << ", \"keyCode\": " << sample.keyCode
                << ", \"sourceType\": " << sample.sourceType
                << ", \"toolCode\": " << sample.toolCode
                << ", \"uiSourceType\": " << sample.uiSourceType
                << ", \"uiHistoryCount\": " << sample.uiHistoryCount
                << ", \"historical\": " << (sample.historical ? "true" : "false")
                << ", \"batchTerminal\": " << (sample.batchTerminal ? "true" : "false")
                << ", \"zeroPointReset\": " << (sample.zeroPointReset ? "true" : "false")
                << ", \"hasRollAngle\": " << (sample.hasRollAngle ? "true" : "false")
                << ", \"toolType\": \"" << EscapeJsonString(sample.toolType) << "\""
                << ", \"sourceLabel\": \"" << EscapeJsonString(sample.sourceLabel) << "\""
                << ", \"x\": " << std::fixed << std::setprecision(3) << sample.point.x
                << ", \"y\": " << std::fixed << std::setprecision(3) << sample.point.y
                << ", \"windowX\": " << std::fixed << std::setprecision(3) << sample.point.windowX
                << ", \"windowY\": " << std::fixed << std::setprecision(3) << sample.point.windowY
                << ", \"displayX\": " << std::fixed << std::setprecision(3) << sample.point.displayX
                << ", \"displayY\": " << std::fixed << std::setprecision(3) << sample.point.displayY
                << ", \"force\": " << std::fixed << std::setprecision(4) << sample.point.force
                << ", \"tiltX\": " << std::fixed << std::setprecision(3) << sample.point.tiltX
                << ", \"tiltY\": " << std::fixed << std::setprecision(3) << sample.point.tiltY
                << ", \"rollAngle\": " << std::fixed << std::setprecision(4) << sample.point.rollAngle
                << ", \"pressure\": " << std::fixed << std::setprecision(4) << sample.pressure
                << ", \"uiTiltX\": " << std::fixed << std::setprecision(3) << sample.tiltX
                << ", \"uiTiltY\": " << std::fixed << std::setprecision(3) << sample.tiltY
                << ", \"uiRollAngle\": " << std::fixed << std::setprecision(4) << sample.rollAngle
                << "}";
    }
    builder << "\n  ]\n}";
    return builder.str();
}

InputStrokeTrace DeserializeInputTraceJson(const std::string& jsonText)
{
    InputStrokeTrace trace;
    trace.version = static_cast<int>(ExtractJsonNumberValue(jsonText, "version", 1));
    trace.recordedAt = static_cast<int64_t>(ExtractJsonNumberValue(jsonText, "recordedAt", 0));
    trace.engineId = ExtractJsonStringValue(jsonText, "engineId", "");
    trace.documentId = ExtractJsonStringValue(jsonText, "documentId", "");
    trace.xComponentId = ExtractJsonStringValue(jsonText, "xComponentId", "");

    const std::string samplesArray = ExtractJsonArrayBody(jsonText, "samples");
    for (const std::string& sampleObjectText : SplitTopLevelJsonObjects(samplesArray)) {
        InputSample sample;
        sample.sequence = static_cast<int64_t>(ExtractJsonNumberValue(sampleObjectText, "sequence", 0));
        sample.type = ParseInputSampleType(ExtractJsonStringValue(sampleObjectText, "type", "touch"));
        sample.timeStamp = static_cast<int64_t>(ExtractJsonNumberValue(sampleObjectText, "timeStamp", 0));
        sample.pointerId = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "pointerId", -1));
        sample.activePointerCount = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "activePointerCount", 0));
        sample.action = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "action", -1));
        sample.keyCode = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "keyCode", KEY_UNKNOWN));
        sample.sourceType = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "sourceType", -1));
        sample.toolCode = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "toolCode", 0));
        sample.uiSourceType = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "uiSourceType", 0));
        sample.uiHistoryCount = static_cast<int32_t>(ExtractJsonNumberValue(sampleObjectText, "uiHistoryCount", 0));
        sample.historical = ExtractJsonBoolValue(sampleObjectText, "historical", false);
        sample.batchTerminal = ExtractJsonBoolValue(sampleObjectText, "batchTerminal", true);
        sample.zeroPointReset = ExtractJsonBoolValue(sampleObjectText, "zeroPointReset", false);
        sample.hasRollAngle = ExtractJsonBoolValue(sampleObjectText, "hasRollAngle", false);
        sample.toolType = ExtractJsonStringValue(sampleObjectText, "toolType", "unknown");
        sample.sourceLabel = ExtractJsonStringValue(sampleObjectText, "sourceLabel", "unknown");
        sample.point.pointerId = sample.pointerId;
        sample.point.timeStamp = sample.timeStamp;
        sample.point.historical = sample.historical;
        sample.point.toolType = sample.toolType;
        sample.point.x = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "x", 0.0));
        sample.point.y = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "y", 0.0));
        sample.point.windowX = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "windowX", sample.point.x));
        sample.point.windowY = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "windowY", sample.point.y));
        sample.point.displayX = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "displayX", sample.point.x));
        sample.point.displayY = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "displayY", sample.point.y));
        sample.point.force = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "force", 0.0));
        sample.point.tiltX = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "tiltX", 0.0));
        sample.point.tiltY = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "tiltY", 0.0));
        sample.point.rollAngle = ExtractJsonNumberValue(sampleObjectText, "rollAngle", 0.0);
        sample.point.hasRollAngle = sample.hasRollAngle;
        sample.pressure = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "pressure", sample.point.force));
        sample.tiltX = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "uiTiltX", sample.point.tiltX));
        sample.tiltY = static_cast<float>(ExtractJsonNumberValue(sampleObjectText, "uiTiltY", sample.point.tiltY));
        sample.rollAngle = ExtractJsonNumberValue(sampleObjectText, "uiRollAngle", sample.point.rollAngle);
        trace.samples.push_back(sample);
    }

    return trace;
}

std::string SerializeStrokesJson(const std::vector<StrokeRenderObject>& strokes)
{
    std::ostringstream builder;
    builder << "{\n  \"version\": 2,\n  \"strokes\": [";
    for (size_t strokeIndex = 0; strokeIndex < strokes.size(); ++strokeIndex) {
        const StrokeRenderObject& stroke = strokes[strokeIndex];
        if (strokeIndex > 0) {
            builder << ",";
        }
        builder << "\n    {\n"
                << "      \"objectId\": \"" << EscapeJsonString(stroke.objectId) << "\",\n"
                << "      \"tool\": \"" << EscapeJsonString(stroke.tool) << "\",\n"
                << "      \"colorHex\": \"" << EscapeJsonString(stroke.colorHex) << "\",\n"
                << "      \"shapeType\": \"" << EscapeJsonString(stroke.shapeType) << "\",\n"
                << "      \"points\": [";
        for (size_t pointIndex = 0; pointIndex < stroke.points.size(); ++pointIndex) {
            const InkPointSnapshot& point = stroke.points[pointIndex];
            if (pointIndex > 0) {
                builder << ",";
            }
            builder << "\n        {"
                    << "\"x\": " << std::fixed << std::setprecision(3) << point.x
                    << ", \"y\": " << std::fixed << std::setprecision(3) << point.y
                    << ", \"force\": " << std::fixed << std::setprecision(4) << point.force
                    << ", \"tiltX\": " << std::fixed << std::setprecision(3) << point.tiltX
                    << ", \"tiltY\": " << std::fixed << std::setprecision(3) << point.tiltY
                    << ", \"rollAngle\": " << std::fixed << std::setprecision(4) << point.rollAngle
                    << ", \"timeStamp\": " << point.timeStamp
                    << ", \"toolType\": \"" << EscapeJsonString(point.toolType) << "\"}";
        }
        builder << "\n      ]\n    }";
    }
    builder << "\n  ],\n  \"predictions\": []\n}";
    return builder.str();
}

std::vector<StrokeRenderObject> DeserializeStrokesJson(const std::string& jsonText)
{
    std::vector<StrokeRenderObject> strokes;
    const std::string strokesArray = ExtractJsonArrayBody(jsonText, "strokes");
    if (strokesArray.empty()) {
        return strokes;
    }

    for (const std::string& strokeObjectText : SplitTopLevelJsonObjects(strokesArray)) {
        StrokeRenderObject stroke;
        stroke.objectId = ExtractJsonStringValue(strokeObjectText, "objectId", "");
        stroke.tool = ExtractJsonStringValue(strokeObjectText, "tool", "pen");
        stroke.colorHex = ExtractJsonStringValue(strokeObjectText, "colorHex", "#1D2736");
        stroke.shapeType = ExtractJsonStringValue(strokeObjectText, "shapeType", "freehand");

        const std::string pointsArray = ExtractJsonArrayBody(strokeObjectText, "points");
        for (const std::string& pointObjectText : SplitTopLevelJsonObjects(pointsArray)) {
            InkPointSnapshot point;
            point.x = static_cast<float>(ExtractJsonNumberValue(pointObjectText, "x", 0.0));
            point.y = static_cast<float>(ExtractJsonNumberValue(pointObjectText, "y", 0.0));
            point.windowX = point.x;
            point.windowY = point.y;
            point.displayX = point.x;
            point.displayY = point.y;
            point.force = static_cast<float>(ExtractJsonNumberValue(pointObjectText, "force", 0.5));
            point.tiltX = static_cast<float>(ExtractJsonNumberValue(pointObjectText, "tiltX", 0.0));
            point.tiltY = static_cast<float>(ExtractJsonNumberValue(pointObjectText, "tiltY", 0.0));
            point.rollAngle = ExtractJsonNumberValue(pointObjectText, "rollAngle", 0.0);
            point.hasRollAngle = std::abs(point.rollAngle) > 0.0001;
            point.timeStamp = static_cast<int64_t>(ExtractJsonNumberValue(pointObjectText, "timeStamp", 0.0));
            point.toolType = ExtractJsonStringValue(pointObjectText, "toolType", stroke.tool);
            stroke.points.push_back(point);
        }

        if (!stroke.points.empty()) {
            strokes.push_back(stroke);
        }
    }

    return strokes;
}

std::string BuildStrokesFilePath(const DocumentSession& session)
{
    return session.packagePath + "/strokes.json";
}

bool PersistDocumentStrokes(const DocumentSession& session, const std::vector<StrokeRenderObject>& strokes)
{
    if (session.packagePath.empty()) {
        return false;
    }
    return WriteTextFile(BuildStrokesFilePath(session), SerializeStrokesJson(strokes));
}

std::vector<StrokeRenderObject> LoadDocumentStrokes(const DocumentSession& session)
{
    if (session.packagePath.empty()) {
        return {};
    }
    return DeserializeStrokesJson(ReadTextFile(BuildStrokesFilePath(session)));
}

std::string ExtractJsonObjectText(const std::string& text, const std::string& key)
{
    const std::string keyToken = "\"" + key + "\"";
    const size_t keyIndex = text.find(keyToken);
    if (keyIndex == std::string::npos) {
        return "";
    }

    size_t cursor = text.find(':', keyIndex + keyToken.size());
    if (cursor == std::string::npos) {
        return "";
    }
    cursor = SkipJsonWhitespace(text, cursor + 1);
    if (cursor >= text.size() || text[cursor] != '{') {
        return "";
    }

    int braceDepth = 0;
    bool inString = false;
    for (size_t index = cursor; index < text.size(); ++index) {
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
                return text.substr(cursor, index - cursor + 1);
            }
        }
    }
    return "";
}

std::vector<PageDescriptor> DeserializePageDescriptorsFromOpenConfig(const std::string& configJson);
std::vector<std::string> BuildPageIdsFromDescriptors(const std::vector<PageDescriptor>& descriptors);

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

PageContractDescriptor ParsePageContractDescriptor(const std::string& contractText)
{
    PageContractDescriptor descriptor;
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

std::vector<PageDescriptor> DeserializePageDescriptorsFromOpenConfig(const std::string& configJson)
{
    std::vector<PageDescriptor> descriptors;
    const std::string pagesArray = ExtractJsonArrayBody(configJson, "pages");
    const std::string fallbackPageKind = InferCompatPageKindFromOpenConfig(configJson);
    for (const std::string& pageObjectText : SplitTopLevelJsonObjects(pagesArray)) {
        PageDescriptor descriptor;
        descriptor.pageId = ExtractJsonStringValue(pageObjectText, "id", "");
        if (descriptor.pageId.empty()) {
            return {};
        }
        if (std::any_of(descriptors.begin(), descriptors.end(), [&](const PageDescriptor& existing) {
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

std::vector<std::string> BuildPageIdsFromDescriptors(const std::vector<PageDescriptor>& descriptors)
{
    std::vector<std::string> pageIds;
    pageIds.reserve(descriptors.size());
    for (const PageDescriptor& descriptor : descriptors) {
        pageIds.push_back(descriptor.pageId);
    }
    return pageIds;
}

const PageDescriptor* FindPageDescriptor(const DocumentSession& session, const std::string& pageId)
{
    const auto iterator = std::find_if(session.pageDescriptors.begin(), session.pageDescriptors.end(),
        [&](const PageDescriptor& descriptor) {
            return descriptor.pageId == pageId;
        });
    if (iterator == session.pageDescriptors.end()) {
        return nullptr;
    }
    return &(*iterator);
}

void ReindexPageDescriptors(DocumentSession& session)
{
    for (size_t index = 0; index < session.pageDescriptors.size(); ++index) {
        session.pageDescriptors[index].order = static_cast<int>(index);
    }
}

void InitializeCompatibilityPageSession(const std::string& configJson, DocumentSession& session)
{
    const std::string pageId = ResolveCompatPageIdFromOpenConfig(configJson);
    const std::string fallbackPageKind = InferCompatPageKindFromOpenConfig(configJson);
    PageDescriptor descriptor;
    descriptor.pageId = pageId;
    descriptor.pageKind = fallbackPageKind;
    descriptor.contract = ParsePageContractDescriptor(ExtractPageContractTextFromOpenConfig(configJson, pageId));
    session.pageAware = false;
    session.pages = { pageId };
    session.pageDescriptors = { descriptor };
    session.activePageId = pageId;
    session.pageStrokes.clear();
    session.pageStrokes[pageId] = {};
}

bool InitializePageAwareSessionFromOpenConfig(const std::string& configJson, DocumentSession& session)
{
    const std::vector<PageDescriptor> pageDescriptors = DeserializePageDescriptorsFromOpenConfig(configJson);
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
    session.pageStrokes.clear();
    for (const std::string& pageId : pageIds) {
        session.pageStrokes[pageId] = {};
    }
    return true;
}

std::string ResolveSessionActivePageId(const DocumentSession& session)
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

bool SupportsPageAwareEditing(const EngineState& engine, const DocumentSession& session)
{
    return engine.activeMode == "paged" && session.pageAware && !session.pages.empty();
}

bool SupportsBlankPageMutation(const EngineState& engine, const DocumentSession& session)
{
    if (!SupportsPageAwareEditing(engine, session) || session.pageDescriptors.empty()) {
        return false;
    }
    return std::all_of(session.pageDescriptors.begin(), session.pageDescriptors.end(), [](const PageDescriptor& descriptor) {
        return descriptor.pageKind == "blank";
    });
}

std::vector<std::string> BuildReportedPageIds(const EngineState& engine, const DocumentSession& session)
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

void SyncCommittedStrokesToActivePage(EngineState& engine, DocumentSession& session)
{
    const std::string activePageId = ResolveSessionActivePageId(session);
    session.activePageId = activePageId;
    session.pageStrokes[activePageId] = engine.committedStrokes;
}

void LoadCommittedStrokesFromActivePage(EngineState& engine, DocumentSession& session)
{
    const std::string activePageId = ResolveSessionActivePageId(session);
    session.activePageId = activePageId;
    auto iterator = session.pageStrokes.find(activePageId);
    engine.committedStrokes = iterator != session.pageStrokes.end()
        ? iterator->second
        : std::vector<StrokeRenderObject> {};
    EnsureStrokeObjectIds(engine);
    engine.undoSnapshots.clear();
    engine.redoSnapshots.clear();
    RefreshLastCommittedStrokeType(engine);
}

bool SwitchActivePageSession(EngineState& engine, DocumentSession& session, const std::string& pageId)
{
    if (pageId.empty() || FindPageIndex(session.pages, pageId) < 0) {
        return false;
    }
    SyncCommittedStrokesToActivePage(engine, session);
    session.activePageId = pageId;
    LoadCommittedStrokesFromActivePage(engine, session);
    return true;
}

bool IsClosedStrokePath(const StrokeRenderObject& stroke)
{
    if (stroke.points.size() < 3) {
        return false;
    }
    const StrokeBounds bounds = ComputeStrokeBounds(stroke.points);
    const float diagonal = std::hypot(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY);
    return DistanceBetween(stroke.points.front(), stroke.points.back()) <= std::max(12.0f, diagonal * 0.18f);
}

bool HasPageBounds(const PageDescriptor* descriptor)
{
    return descriptor != nullptr && descriptor->contract.widthPt > 0.0 && descriptor->contract.heightPt > 0.0;
}

std::string BuildPageBackgroundId(const PageDescriptor* descriptor)
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

void AppendPageBounds(std::ostringstream& builder, const PageDescriptor* descriptor)
{
    const double width = descriptor != nullptr ? descriptor->contract.widthPt : 0.0;
    const double height = descriptor != nullptr ? descriptor->contract.heightPt : 0.0;
    builder << "\"bounds\":{"
            << "\"minX\":0,"
            << "\"minY\":0,"
            << "\"maxX\":" << std::fixed << std::setprecision(3) << width << ","
            << "\"maxY\":" << std::fixed << std::setprecision(3) << height
            << "}";
}

void AppendPageEntry(std::ostringstream& builder, const DocumentSession& session, const std::string& pageId, int pageIndex)
{
    const PageDescriptor* descriptor = FindPageDescriptor(session, pageId);
    builder << "{"
            << "\"pageId\":\"" << EscapeJsonString(pageId) << "\","
            << "\"pageIndex\":" << pageIndex;
    if (HasPageBounds(descriptor)) {
        builder << ",\"width\":" << std::fixed << std::setprecision(3) << descriptor->contract.widthPt
                << ",\"height\":" << std::fixed << std::setprecision(3) << descriptor->contract.heightPt
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

void AppendPageEntries(std::ostringstream& builder, const DocumentSession& session, const std::vector<std::string>& pageIds)
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

bool TryResolveDocumentBounds(const DocumentSession& session, const std::vector<std::string>& pageIds,
    double& maxWidth, double& maxHeight)
{
    maxWidth = 0.0;
    maxHeight = 0.0;
    bool hasBounds = false;
    for (const std::string& pageId : pageIds) {
        const PageDescriptor* descriptor = FindPageDescriptor(session, pageId);
        if (!HasPageBounds(descriptor)) {
            continue;
        }
        maxWidth = std::max(maxWidth, descriptor->contract.widthPt);
        maxHeight = std::max(maxHeight, descriptor->contract.heightPt);
        hasBounds = true;
    }
    return hasBounds;
}

void AppendPreviewLayoutField(std::ostringstream& builder, const DocumentSession& session,
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
                << "\"maxX\":" << std::fixed << std::setprecision(3) << documentWidth << ","
                << "\"maxY\":" << std::fixed << std::setprecision(3) << documentHeight
                << "}";
    }
    builder << ",\"pages\":";
    AppendPageEntries(builder, session, pageIds);
    builder << "}";
}

void AppendScenePageFields(std::ostringstream& builder, const DocumentSession& session,
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
    const DocumentSession& session, const std::vector<std::string>& pageIds, bool includePdfLayer, bool includeInkLayer)
{
    const PageDescriptor* descriptor = FindPageDescriptor(session, pageId);
    builder << "\"status\":\"ready\","
            << "\"engineId\":\"" << EscapeJsonString(engineId) << "\","
            << "\"previewSchemaVersion\":" << kPreviewSchemaVersion << ","
            << "\"documentId\":\"" << EscapeJsonString(documentId) << "\","
            << "\"pageIndex\":" << pageIndex << ","
            << "\"pageId\":\"" << EscapeJsonString(pageId) << "\","
            << "\"targetMode\":\"" << kStatsFallbackTargetMode << "\","
            << "\"coordinateSpace\":\"" << kLegacyCoordinateSpace << "\"";
    if (HasPageBounds(descriptor)) {
        builder << ",\"targetBounds\":{"
                << "\"minX\":0,"
                << "\"minY\":0,"
                << "\"maxX\":" << std::fixed << std::setprecision(3) << descriptor->contract.widthPt << ","
                << "\"maxY\":" << std::fixed << std::setprecision(3) << descriptor->contract.heightPt
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
    const DocumentSession& session, const std::vector<std::string>& pageIds)
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

std::string BuildSceneSnapshotJson(const EngineState& engine, const DocumentSession& session, int checkpointCount)
{
    const std::string activePageId = ResolveSessionActivePageId(session);
    const std::vector<std::string> reportedPageIds = BuildReportedPageIds(engine, session);
    const int activePageIndex = std::max(0, FindPageIndex(reportedPageIds, activePageId));
    const PageDescriptor* activeDescriptor = FindPageDescriptor(session, activePageId);
    const bool includePdfPlaceholder = activeDescriptor != nullptr && IsPdfPageKind(activeDescriptor->pageKind);
    const size_t objectCount = engine.committedStrokes.size() + (includePdfPlaceholder ? 1 : 0);
    std::ostringstream builder;
    builder << "{"
            ;
    AppendCanonicalSceneFields(builder, engine.engineId, session.documentId,
        ExtractJsonStringValue(session.openConfigJson, "title", ""),
        ExtractJsonStringValue(session.openConfigJson, "documentType", "blank"),
        engine.activeMode, engine.activeBackend, checkpointCount, objectCount, session, reportedPageIds);
    builder << ","
            << "\"objects\":[";

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
        builder << ",\"layer\":\"pdf\"}";
        wroteObject = true;
    }

    for (size_t index = 0; index < engine.committedStrokes.size(); ++index) {
        const StrokeRenderObject& stroke = engine.committedStrokes[index];
        const StrokeBounds bounds = stroke.points.empty() ? StrokeBounds {} : ComputeStrokeBounds(stroke.points);
        if (wroteObject || index > 0) {
            builder << ",";
        }
        builder << "{"
                << "\"id\":\"" << EscapeJsonString(stroke.objectId) << "\","
                << "\"nodeType\":\"ink\","
                << "\"shapeType\":\"" << EscapeJsonString(stroke.shapeType) << "\","
                << "\"tool\":\"" << EscapeJsonString(stroke.tool) << "\","
                << "\"colorHex\":\"" << EscapeJsonString(stroke.colorHex) << "\","
                << "\"selected\":" << (stroke.selected ? "true" : "false") << ","
                << "\"pointCount\":" << stroke.points.size() << ","
                << "\"pageIndex\":" << activePageIndex << ","
                << "\"pageId\":\"" << EscapeJsonString(activePageId) << "\","
                << "\"closed\":" << (IsClosedStrokePath(stroke) ? "true" : "false") << ","
                << "\"bounds\":{"
                << "\"minX\":" << std::fixed << std::setprecision(3) << bounds.minX << ","
                << "\"minY\":" << std::fixed << std::setprecision(3) << bounds.minY << ","
                << "\"maxX\":" << std::fixed << std::setprecision(3) << bounds.maxX << ","
                << "\"maxY\":" << std::fixed << std::setprecision(3) << bounds.maxY
                << "},"
                << "\"layer\":\"ink\""
                << "}";
        wroteObject = true;
    }

    builder << "]}";
    return builder.str();
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

constexpr const char* kVertexShaderSource = R"(#version 300 es
layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec4 aColor;
out vec4 vColor;
void main()
{
    gl_Position = vec4(aPosition, 0.0, 1.0);
    vColor = aColor;
}
)";

constexpr const char* kFragmentShaderSource = R"(#version 300 es
precision mediump float;
in vec4 vColor;
out vec4 fragColor;
void main()
{
    fragColor = vColor;
}
)";

GLuint CompileShader(GLenum shaderType, const char* source)
{
    const GLuint shader = glCreateShader(shaderType);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) {
        return shader;
    }
    glDeleteShader(shader);
    return 0;
}

GLuint CreateProgram()
{
    const GLuint vertexShader = CompileShader(GL_VERTEX_SHADER, kVertexShaderSource);
    const GLuint fragmentShader = CompileShader(GL_FRAGMENT_SHADER, kFragmentShaderSource);
    if (vertexShader == 0 || fragmentShader == 0) {
        if (vertexShader != 0) {
            glDeleteShader(vertexShader);
        }
        if (fragmentShader != 0) {
            glDeleteShader(fragmentShader);
        }
        return 0;
    }

    const GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    GLint linked = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (linked == GL_TRUE) {
        return program;
    }
    glDeleteProgram(program);
    return 0;
}

void DestroyGlRenderer(GlRendererState& renderer)
{
    if (renderer.display != EGL_NO_DISPLAY) {
        eglMakeCurrent(renderer.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (renderer.vbo != 0) {
        glDeleteBuffers(1, &renderer.vbo);
        renderer.vbo = 0;
    }
    if (renderer.program != 0) {
        glDeleteProgram(renderer.program);
        renderer.program = 0;
    }
    if (renderer.surface != EGL_NO_SURFACE) {
        eglDestroySurface(renderer.display, renderer.surface);
        renderer.surface = EGL_NO_SURFACE;
    }
    if (renderer.context != EGL_NO_CONTEXT) {
        eglDestroyContext(renderer.display, renderer.context);
        renderer.context = EGL_NO_CONTEXT;
    }
    if (renderer.display != EGL_NO_DISPLAY) {
        eglTerminate(renderer.display);
        renderer.display = EGL_NO_DISPLAY;
    }
    renderer.nativeWindow = nullptr;
    renderer.ready = false;
}

bool EnsureGlRenderer(SurfaceTelemetry& telemetry)
{
    if (telemetry.window == nullptr || telemetry.width == 0 || telemetry.height == 0) {
        return false;
    }

    GlRendererState& renderer = telemetry.gl;
    if (renderer.display == EGL_NO_DISPLAY) {
        renderer.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (renderer.display == EGL_NO_DISPLAY) {
            return false;
        }
        if (!eglInitialize(renderer.display, nullptr, nullptr)) {
            DestroyGlRenderer(renderer);
            return false;
        }
        eglBindAPI(EGL_OPENGL_ES_API);
        const EGLint configAttributes[] = {
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
            EGL_BLUE_SIZE, 8,
            EGL_GREEN_SIZE, 8,
            EGL_RED_SIZE, 8,
            EGL_ALPHA_SIZE, 8,
            EGL_NONE
        };
        EGLint configCount = 0;
        if (!eglChooseConfig(renderer.display, configAttributes, &renderer.config, 1, &configCount) || configCount < 1) {
            DestroyGlRenderer(renderer);
            return false;
        }
        const EGLint contextAttributes[] = {
            EGL_CONTEXT_CLIENT_VERSION, 3,
            EGL_NONE
        };
        renderer.context = eglCreateContext(renderer.display, renderer.config, EGL_NO_CONTEXT, contextAttributes);
        if (renderer.context == EGL_NO_CONTEXT) {
            DestroyGlRenderer(renderer);
            return false;
        }
    }

    if (renderer.surface == EGL_NO_SURFACE || renderer.nativeWindow != telemetry.window) {
        if (renderer.surface != EGL_NO_SURFACE) {
            eglDestroySurface(renderer.display, renderer.surface);
            renderer.surface = EGL_NO_SURFACE;
        }
        renderer.nativeWindow = telemetry.window;
        renderer.surface = eglCreateWindowSurface(
            renderer.display, renderer.config, reinterpret_cast<EGLNativeWindowType>(telemetry.window), nullptr);
        if (renderer.surface == EGL_NO_SURFACE) {
            DestroyGlRenderer(renderer);
            return false;
        }
    }

    if (!eglMakeCurrent(renderer.display, renderer.surface, renderer.surface, renderer.context)) {
        DestroyGlRenderer(renderer);
        return false;
    }

    if (renderer.program == 0) {
        renderer.program = CreateProgram();
        if (renderer.program == 0) {
            DestroyGlRenderer(renderer);
            return false;
        }
    }
    if (renderer.vbo == 0) {
        glGenBuffers(1, &renderer.vbo);
    }

    glViewport(0, 0, static_cast<GLsizei>(telemetry.width), static_cast<GLsizei>(telemetry.height));
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    renderer.ready = true;
    return true;
}

void DrawVertices(GlRendererState& renderer, const std::vector<RenderVertex>& vertices)
{
    if (vertices.empty()) {
        return;
    }

    glUseProgram(renderer.program);
    glBindBuffer(GL_ARRAY_BUFFER, renderer.vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(RenderVertex) * vertices.size(), vertices.data(), GL_DYNAMIC_DRAW);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(RenderVertex), reinterpret_cast<const void*>(0));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(RenderVertex),
        reinterpret_cast<const void*>(sizeof(GLfloat) * 2));

    glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(vertices.size()));
}

void AppendBackgroundVertices(std::vector<RenderVertex>& vertices, const EngineState& engine,
    float surfaceWidth, float surfaceHeight)
{
    if (engine.activeMode == "paged") {
        AddRect(vertices, 0.0f, 0.0f, surfaceWidth, surfaceHeight,
            ParseColorHex(engine.activeBackend == "skia" ? "#E7EDF5" : "#E9EFF7"), surfaceWidth, surfaceHeight);

        const float safeWidth = surfaceWidth - 96.0f;
        const float safeHeight = surfaceHeight - 48.0f;
        const float pageWidth = std::min(safeWidth, safeHeight / 1.38f);
        const float pageHeight = pageWidth * 1.38f;
        const float left = (surfaceWidth - pageWidth) * 0.5f;
        const float top = (surfaceHeight - pageHeight) * 0.5f;
        AddRect(vertices, left + 12.0f, top + 14.0f, left + pageWidth + 12.0f, top + pageHeight + 14.0f,
            ParseColorHex("#93A3B8", 0.10f), surfaceWidth, surfaceHeight);
        AddRect(vertices, left, top, left + pageWidth, top + pageHeight,
            ParseColorHex("#FFFDF8"), surfaceWidth, surfaceHeight);
        AddRect(vertices, left, top, left + pageWidth, top + 2.0f,
            ParseColorHex("#D5DCE7"), surfaceWidth, surfaceHeight);
        AddRect(vertices, left, top + pageHeight - 2.0f, left + pageWidth, top + pageHeight,
            ParseColorHex("#D5DCE7"), surfaceWidth, surfaceHeight);
        AddRect(vertices, left, top, left + 2.0f, top + pageHeight,
            ParseColorHex("#D5DCE7"), surfaceWidth, surfaceHeight);
        AddRect(vertices, left + pageWidth - 2.0f, top, left + pageWidth, top + pageHeight,
            ParseColorHex("#D5DCE7"), surfaceWidth, surfaceHeight);
    } else {
        AddRect(vertices, 0.0f, 0.0f, surfaceWidth, surfaceHeight,
            ParseColorHex(engine.activeBackend == "skia" ? "#EEF4FB" : "#F4F7FB"), surfaceWidth, surfaceHeight);
        AddInfiniteGrid(vertices, surfaceWidth, surfaceHeight);
    }
}

class NoteEngineRegistry : public NoteEngineRuntime {
public:
    static NoteEngineRegistry& Get()
    {
        static NoteEngineRegistry instance;
        return instance;
    }

    std::string CreateEngine(const std::string& configJson)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        ++engineCounter_;

        EngineState state;
        state.engineId = "engine-" + std::to_string(engineCounter_);
        state.configJson = configJson;
        state.predictionEnabled = configJson.find("\"enablePrediction\":true") != std::string::npos;
        state.pressureEnabled = configJson.find("\"enablePressureForPen\":true") != std::string::npos;
        state.shapeRecognitionEnabled = configJson.find("\"enableShapeDetection\":true") != std::string::npos;
        state.pressureCurvePreset = ParsePressureCurvePreset(configJson);
        if (configJson.find("skia") != std::string::npos) {
            state.activeBackend = "skia";
        }
        if (configJson.find("infinite") != std::string::npos) {
            state.activeMode = "infinite";
        }
        engines_[state.engineId] = state;
        OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, kLogTag, "Create engine %{public}s", state.engineId.c_str());
        return state.engineId;
    }

    bool OpenDocument(const std::string& engineId, const std::string& documentId, const std::string& packagePath,
        const std::string& configJson)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }

        DocumentSession session;
        session.documentId = documentId;
        session.packagePath = packagePath;
        session.openConfigJson = configJson;
        const bool initializedPageAwareSession = engine->activeMode == "paged" &&
            InitializePageAwareSessionFromOpenConfig(configJson, session);
        if (!initializedPageAwareSession) {
            InitializeCompatibilityPageSession(configJson, session);
        }

        const std::string activePageId = ResolveSessionActivePageId(session);
        session.pageStrokes[activePageId] = LoadDocumentStrokes(session);
        engine->documents[documentId] = session;
        engine->activeDocumentId = documentId;
        engine->nextObjectCounter = 1;
        LoadCommittedStrokesFromActivePage(*engine, engine->documents[documentId]);
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            ResetTransientInputStateLocked(*telemetry);
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool AttachXComponent(const std::string& engineId, const std::string& xComponentId, const std::string& surfaceId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }

        engine->xComponentId = xComponentId;
        engine->surfaceId = surfaceId;

        SurfaceTelemetry* telemetry = FindSurfaceLocked(xComponentId);
        if (telemetry != nullptr) {
            telemetry->boundEngineId = engineId;
            RefreshSurfaceGeometry(*telemetry);
            if (telemetry->width > 0 && telemetry->height > 0) {
                engine->width = static_cast<int>(telemetry->width);
                engine->height = static_cast<int>(telemetry->height);
            }
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool Resize(const std::string& engineId, int width, int height, double density)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->width = width;
        engine->height = height;
        engine->density = density;
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool SaveCheckpoint(const std::string& engineId, const std::string& documentId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }

        auto iterator = engine->documents.find(documentId);
        if (iterator == engine->documents.end()) {
            return false;
        }
        EnsureStrokeObjectIds(*engine);
        SyncCommittedStrokesToActivePage(*engine, iterator->second);
        const std::string activePageId = ResolveSessionActivePageId(iterator->second);
        const auto pageIterator = iterator->second.pageStrokes.find(activePageId);
        const std::vector<StrokeRenderObject>& strokesToPersist = pageIterator != iterator->second.pageStrokes.end()
            ? pageIterator->second
            : engine->committedStrokes;
        const bool persisted = PersistDocumentStrokes(iterator->second, strokesToPersist);
        if (persisted) {
            iterator->second.checkpointCount += 1;
        }
        return persisted;
    }

    std::string RequestPreviewRender(const std::string& engineId, const std::string& documentId,
        int pageIndex, int width, int height)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
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
        const auto pageStrokeIterator = iterator->second.pageStrokes.find(targetPageId);
        const std::vector<StrokeRenderObject> emptyStrokes;
        const std::vector<StrokeRenderObject>& targetStrokes = pageStrokeIterator != iterator->second.pageStrokes.end()
            ? pageStrokeIterator->second
            : emptyStrokes;
        const size_t strokeCount = targetStrokes.size();
        size_t shapeCount = 0;
        for (const StrokeRenderObject& stroke : targetStrokes) {
            if (stroke.shapeType != "freehand") {
                shapeCount += 1;
            }
        }
        const PageDescriptor* targetDescriptor = FindPageDescriptor(iterator->second, targetPageId);
        const bool includePdfLayer = targetDescriptor != nullptr && IsPdfPageKind(targetDescriptor->pageKind);
        const bool includeInkLayer = includePdfLayer || strokeCount > 0;
        const size_t objectCount = strokeCount + (includePdfLayer ? 1 : 0);
        std::ostringstream builder;
        builder << "{";
        AppendCanonicalPreviewFields(builder, engineId, documentId, targetPageId, targetPageIndex, width, height,
                iterator->second.checkpointCount, strokeCount, shapeCount, objectCount,
                engine->activeMode, iterator->second, reportedPageIds, includePdfLayer, includeInkLayer);
        builder
                << "}";
        return builder.str();
    }

    std::string ExportSceneSnapshot(const std::string& engineId, const std::string& documentId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        auto iterator = engine->documents.find(documentId);
        if (iterator == engine->documents.end()) {
            return R"({"status":"missing-document"})";
        }
        EnsureStrokeObjectIds(*engine);
        return BuildSceneSnapshotJson(*engine, iterator->second, iterator->second.checkpointCount);
    }

    std::string ReadPdfPageCount(const std::string& pdfPath) override
    {
        return ReadPdfPageCountFromFile(pdfPath);
    }

    bool SetActivePage(const std::string& engineId, const std::string& pageId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }

        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end() || !SupportsPageAwareEditing(*engine, iterator->second)) {
            return false;
        }
        if (!SwitchActivePageSession(*engine, iterator->second, pageId)) {
            return false;
        }
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            ResetTransientInputStateLocked(*telemetry);
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool InsertPage(const std::string& engineId, const std::string& afterPageId, const std::string& pageConfigJson)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }

        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end() || !SupportsBlankPageMutation(*engine, iterator->second)) {
            return false;
        }

        DocumentSession& session = iterator->second;
        auto afterIterator = std::find(session.pages.begin(), session.pages.end(), afterPageId);
        if (afterIterator == session.pages.end()) {
            return false;
        }

        const std::string newPageId = ExtractJsonStringValue(pageConfigJson, "pageId", "");
        if (newPageId.empty() || FindPageIndex(session.pages, newPageId) >= 0) {
            return false;
        }
        PageDescriptor newDescriptor;
        newDescriptor.pageId = newPageId;
        newDescriptor.pageKind = "blank";
        newDescriptor.contract = ParsePageContractDescriptor(pageConfigJson);

        SyncCommittedStrokesToActivePage(*engine, session);
        session.pageStrokes[newPageId] = {};
        const int insertIndex = static_cast<int>(std::distance(session.pages.begin(), afterIterator + 1));
        session.pages.insert(afterIterator + 1, newPageId);
        auto afterDescriptorIterator = std::find_if(session.pageDescriptors.begin(), session.pageDescriptors.end(),
            [&](const PageDescriptor& descriptor) {
                return descriptor.pageId == afterPageId;
            });
        if (afterDescriptorIterator != session.pageDescriptors.end()) {
            session.pageDescriptors.insert(afterDescriptorIterator + 1, newDescriptor);
        } else {
            if (insertIndex >= 0 && insertIndex <= static_cast<int>(session.pageDescriptors.size())) {
                session.pageDescriptors.insert(session.pageDescriptors.begin() + insertIndex, newDescriptor);
            } else {
                session.pageDescriptors.push_back(newDescriptor);
            }
        }
        ReindexPageDescriptors(session);
        session.activePageId = newPageId;
        LoadCommittedStrokesFromActivePage(*engine, session);
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            ResetTransientInputStateLocked(*telemetry);
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool DeletePage(const std::string& engineId, const std::string& pageId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->activeDocumentId.empty()) {
            return false;
        }

        auto iterator = engine->documents.find(engine->activeDocumentId);
        if (iterator == engine->documents.end() || !SupportsBlankPageMutation(*engine, iterator->second)) {
            return false;
        }

        DocumentSession& session = iterator->second;
        auto pageIterator = std::find(session.pages.begin(), session.pages.end(), pageId);
        if (pageIterator == session.pages.end() || session.pages.size() <= 1) {
            return false;
        }

        SyncCommittedStrokesToActivePage(*engine, session);
        const std::string currentActivePageId = ResolveSessionActivePageId(session);
        const bool deletingActivePage = currentActivePageId == pageId;
        const int deleteIndex = static_cast<int>(std::distance(session.pages.begin(), pageIterator));
        std::string nextActivePageId = currentActivePageId;
        if (deletingActivePage) {
            if (deleteIndex + 1 < static_cast<int>(session.pages.size())) {
                nextActivePageId = session.pages[deleteIndex + 1];
            } else {
                nextActivePageId = session.pages[deleteIndex - 1];
            }
        }

        session.pages.erase(pageIterator);
        session.pageDescriptors.erase(std::remove_if(session.pageDescriptors.begin(), session.pageDescriptors.end(),
            [&](const PageDescriptor& descriptor) {
                return descriptor.pageId == pageId;
            }), session.pageDescriptors.end());
        ReindexPageDescriptors(session);
        session.pageStrokes.erase(pageId);
        session.activePageId = nextActivePageId;
        LoadCommittedStrokesFromActivePage(*engine, session);
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            ResetTransientInputStateLocked(*telemetry);
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool SetTool(const std::string& engineId, const std::string& tool)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        ApplyToolSelection(*engine, tool);
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool SetBackend(const std::string& engineId, const std::string& backend)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->activeBackend = backend;
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool SetDocumentMode(const std::string& engineId, const std::string& mode)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->activeMode = mode;
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool SetBrushColor(const std::string& engineId, const std::string& colorHex)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->activeColor = colorHex;
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool Undo(const std::string& engineId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->undoSnapshots.empty()) {
            return false;
        }

        engine->redoSnapshots.push_back(engine->committedStrokes);
        engine->committedStrokes = engine->undoSnapshots.back();
        engine->undoSnapshots.pop_back();
        RefreshLastCommittedStrokeType(*engine);
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool Redo(const std::string& engineId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr || engine->redoSnapshots.empty()) {
            return false;
        }

        engine->undoSnapshots.push_back(engine->committedStrokes);
        if (engine->undoSnapshots.size() > kMaxUndoDepth) {
            engine->undoSnapshots.erase(engine->undoSnapshots.begin());
        }
        engine->committedStrokes = engine->redoSnapshots.back();
        engine->redoSnapshots.pop_back();
        RefreshLastCommittedStrokeType(*engine);
        if (SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId); telemetry != nullptr) {
            RenderSurfaceLocked(*telemetry, engine);
        }
        return true;
    }

    bool DisposeDocument(const std::string& engineId, const std::string& documentId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        engine->documents.erase(documentId);
        if (engine->activeDocumentId == documentId) {
            engine->activeDocumentId.clear();
            engine->committedStrokes.clear();
            engine->undoSnapshots.clear();
            engine->redoSnapshots.clear();
            RefreshLastCommittedStrokeType(*engine);
        }
        return true;
    }

    bool DisposeEngine(const std::string& engineId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto& entry : surfaces_) {
            if (entry.second.boundEngineId == engineId) {
                entry.second.boundEngineId.clear();
            }
        }
        return engines_.erase(engineId) > 0;
    }

    std::string GetDebugState(const std::string& engineId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
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

        SurfaceTelemetry* telemetry = FindSurfaceLocked(engine->xComponentId);
        std::ostringstream builder;
        builder << "{"
                << "\"engineId\":\"" << engine->engineId << "\","
                << "\"activeDocumentId\":\"" << engine->activeDocumentId << "\","
                << "\"activePageId\":\"" << EscapeJsonString(activePageId) << "\","
                << "\"activePageIndex\":" << activePageIndex << ","
                << "\"pageCount\":" << pageCount << ","
                << "\"activeTool\":\"" << engine->activeTool << "\","
                << "\"activeBackend\":\"" << engine->activeBackend << "\","
                << "\"activeMode\":\"" << engine->activeMode << "\","
                << "\"activeColor\":\"" << engine->activeColor << "\","
                << "\"xComponentId\":\"" << engine->xComponentId << "\","
                << "\"surfaceId\":\"" << engine->surfaceId << "\","
                << "\"checkpointCount\":" << checkpointCount << ","
                << "\"committedStrokeCount\":" << engine->committedStrokes.size() << ","
                << "\"undoDepth\":" << engine->undoSnapshots.size() << ","
                << "\"redoDepth\":" << engine->redoSnapshots.size() << ","
                << "\"lastCommittedStrokeType\":\"" << engine->lastCommittedStrokeType << "\","
                << "\"predictionEnabled\":" << (engine->predictionEnabled ? "true" : "false") << ","
                << "\"pressureEnabled\":" << (engine->pressureEnabled ? "true" : "false") << ","
                << "\"shapeRecognitionEnabled\":" << (engine->shapeRecognitionEnabled ? "true" : "false") << ","
                << "\"inputTraceRecording\":" << (engine->inputTraceRecorder.active ? "true" : "false") << ","
                << "\"inputReplayActive\":" << (engine->inputReplayActive ? "true" : "false") << ","
                << "\"inputTraceStatus\":\"" << EscapeJsonString(engine->lastInputTraceStatus) << "\","
                << "\"inputTracePath\":\"" << EscapeJsonString(engine->lastInputTracePath) << "\","
                << "\"inputTraceSampleCount\":" << engine->lastInputTraceSampleCount << ",";
        AppendCapabilityFields(builder, "device-native", true, true, true, true, true, "");

        if (telemetry != nullptr) {
            builder << ",\"surfaceReady\":" << (telemetry->surfaceReady ? "true" : "false")
                    << ",\"surfaceWidth\":" << telemetry->width
                    << ",\"surfaceHeight\":" << telemetry->height
                    << ",\"surfaceOffsetX\":" << telemetry->offsetX
                    << ",\"surfaceOffsetY\":" << telemetry->offsetY
                    << ",\"touchEventCount\":" << telemetry->touchEventCount
                    << ",\"uiTouchEventCount\":" << telemetry->uiTouchEventCount
                    << ",\"keyEventCount\":" << telemetry->keyEventCount
                    << ",\"stylusEventCount\":" << telemetry->stylusEventCount
                    << ",\"fingerEventCount\":" << telemetry->fingerEventCount
                    << ",\"palmRejectedCount\":" << telemetry->palmRejectedCount
                    << ",\"activePointerCount\":" << telemetry->activePointerCount
                    << ",\"stylusActive\":" << (telemetry->stylusActive ? "true" : "false")
                    << ",\"multitouchGestureActive\":" << (telemetry->multitouchGestureActive ? "true" : "false")
                    << ",\"lastHistoricalCount\":" << telemetry->lastHistoricalCount
                    << ",\"lastUiHistoryCount\":" << telemetry->lastUiHistoryCount
                    << ",\"predictedPointCount\":" << telemetry->predictedPointCount
                    << ",\"lastEventTime\":" << telemetry->lastEventTime
                    << ",\"lastPressure\":" << telemetry->lastPressure
                    << ",\"lastTiltX\":" << telemetry->lastTiltX
                    << ",\"lastTiltY\":" << telemetry->lastTiltY
                    << ",\"lastRollAngle\":" << telemetry->lastRollAngle
                    << ",\"lastTouchAction\":\"" << telemetry->lastTouchAction << "\""
                    << ",\"lastToolType\":\"" << telemetry->lastToolType << "\""
                    << ",\"lastSourceType\":\"" << telemetry->lastSourceType << "\""
                    << ",\"lastKeyCode\":" << telemetry->lastKeyCode
                    << ",\"lastKeyAction\":" << telemetry->lastKeyAction
                    << ",\"lastKeySourceType\":" << telemetry->lastKeySourceType
                    << ",\"lastKeyEventTime\":" << telemetry->lastKeyEventTime;
        } else {
            builder << ",\"surfaceReady\":false"
                    << ",\"surfaceWidth\":0"
                    << ",\"surfaceHeight\":0"
                    << ",\"surfaceOffsetX\":0"
                    << ",\"surfaceOffsetY\":0"
                    << ",\"touchEventCount\":0"
                    << ",\"uiTouchEventCount\":0"
                    << ",\"keyEventCount\":0"
                    << ",\"stylusEventCount\":0"
                    << ",\"fingerEventCount\":0"
                    << ",\"palmRejectedCount\":0"
                    << ",\"activePointerCount\":0"
                    << ",\"stylusActive\":false"
                    << ",\"multitouchGestureActive\":false"
                    << ",\"lastHistoricalCount\":0"
                    << ",\"lastUiHistoryCount\":0"
                    << ",\"predictedPointCount\":0"
                    << ",\"lastEventTime\":0"
                    << ",\"lastPressure\":0"
                    << ",\"lastTiltX\":0"
                    << ",\"lastTiltY\":0"
                    << ",\"lastRollAngle\":0"
                    << ",\"lastTouchAction\":\"unknown\""
                    << ",\"lastToolType\":\"unknown\""
                    << ",\"lastSourceType\":\"unknown\""
                    << ",\"lastKeyCode\":-1"
                    << ",\"lastKeyAction\":-1"
                    << ",\"lastKeySourceType\":-1"
                    << ",\"lastKeyEventTime\":0";
        }

        builder << "}";
        return builder.str();
    }

    bool StartInputTraceRecording(const std::string& engineId, const std::string& tracePath)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return false;
        }
        const std::string resolvedPath = !tracePath.empty() ? tracePath : BuildDefaultInputTracePath(*engine);
        if (resolvedPath.empty()) {
            return false;
        }

        engine->inputTraceRecorder.active = true;
        engine->inputTraceRecorder.outputPath = resolvedPath;
        engine->inputTraceRecorder.nextSequence = 1;
        engine->inputTraceRecorder.trace = {};
        engine->inputTraceRecorder.trace.version = 1;
        engine->inputTraceRecorder.trace.recordedAt = 0;
        engine->inputTraceRecorder.trace.engineId = engine->engineId;
        engine->inputTraceRecorder.trace.documentId = engine->activeDocumentId;
        engine->inputTraceRecorder.trace.xComponentId = engine->xComponentId;
        engine->lastInputTracePath = resolvedPath;
        engine->lastInputTraceStatus = "recording";
        engine->lastInputTraceSampleCount = 0;
        return true;
    }

    std::string StopInputTraceRecording(const std::string& engineId)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        if (!engine->inputTraceRecorder.active) {
            return R"({"status":"not-recording"})";
        }

        engine->inputTraceRecorder.active = false;
        engine->inputTraceRecorder.trace.engineId = engine->engineId;
        engine->inputTraceRecorder.trace.documentId = engine->activeDocumentId;
        engine->inputTraceRecorder.trace.xComponentId = engine->xComponentId;
        engine->lastInputTraceSampleCount = engine->inputTraceRecorder.trace.samples.size();
        const bool persisted = WriteTextFile(
            engine->inputTraceRecorder.outputPath, SerializeInputTraceJson(engine->inputTraceRecorder.trace));
        engine->lastInputTraceStatus = persisted ? "recorded" : "record-failed";
        engine->lastInputTracePath = engine->inputTraceRecorder.outputPath;

        std::ostringstream builder;
        builder << "{"
                << "\"status\":\"" << (persisted ? "recorded" : "record-failed") << "\","
                << "\"path\":\"" << EscapeJsonString(engine->lastInputTracePath) << "\","
                << "\"sampleCount\":" << engine->lastInputTraceSampleCount
                << "}";
        return builder.str();
    }

    std::string ReplayInputTrace(const std::string& engineId, const std::string& tracePath)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EngineState* engine = FindEngineLocked(engineId);
        if (engine == nullptr) {
            return R"({"status":"missing-engine"})";
        }
        const std::string resolvedPath = !tracePath.empty() ? tracePath : engine->lastInputTracePath;
        if (resolvedPath.empty()) {
            return R"({"status":"missing-trace-path"})";
        }

        const std::string traceJson = ReadTextFile(resolvedPath);
        if (traceJson.empty()) {
            return R"({"status":"missing-trace"})";
        }

        InputStrokeTrace trace = DeserializeInputTraceJson(traceJson);
        if (trace.samples.empty()) {
            return R"({"status":"empty-trace"})";
        }

        std::stable_sort(trace.samples.begin(), trace.samples.end(), [](const InputSample& left, const InputSample& right) {
            if (left.timeStamp == right.timeStamp) {
                return left.sequence < right.sequence;
            }
            return left.timeStamp < right.timeStamp;
        });

        SurfaceTelemetry& telemetry = EnsureTraceSurfaceLocked(*engine);
        engine->inputReplayActive = true;
        engine->lastInputTraceStatus = "replaying";
        engine->lastInputTracePath = resolvedPath;
        ResetTransientInputStateLocked(telemetry);

        for (const InputSample& sample : trace.samples) {
            ProcessInputSampleLocked(telemetry, engine, sample);
        }

        engine->inputReplayActive = false;
        engine->lastInputTraceStatus = "replayed";
        engine->lastInputTraceSampleCount = trace.samples.size();

        std::ostringstream builder;
        builder << "{"
                << "\"status\":\"replayed\","
                << "\"path\":\"" << EscapeJsonString(resolvedPath) << "\","
                << "\"sampleCount\":" << trace.samples.size()
                << "}";
        return builder.str();
    }

    void RegisterNativeComponent(OH_NativeXComponent* component)
    {
        if (component == nullptr) {
            return;
        }

        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kLogTag, "RegisterNativeComponent missing id");
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.xComponentId = xComponentId;
        telemetry.component = component;

        if (!telemetry.callbacksRegistered) {
            OH_NativeXComponent_RegisterCallback(component, &nativeCallback_);
            telemetry.callbacksRegistered = true;
        }

        if (!telemetry.uiInputCallbackRegistered) {
            OH_NativeXComponent_RegisterUIInputEventCallback(
                component, &NoteEngineRegistry::OnUIInputEvent, ARKUI_UIINPUTEVENT_TYPE_TOUCH);
            telemetry.uiInputCallbackRegistered = true;
        }

        if (!telemetry.keyCallbackRegistered) {
            OH_NativeXComponent_RegisterKeyEventCallback(component, &NoteEngineRegistry::OnKeyEvent);
            telemetry.keyCallbackRegistered = true;
        }

        BindFirstMatchingEngineLocked(telemetry);
        OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, kLogTag,
            "Register native xcomponent %{public}s", xComponentId.c_str());
    }

    void RegisterBridgeExports(napi_env env, napi_value exports) override
    {
        RegisterXComponentFromExports(env, exports);
    }

    static void OnSurfaceCreated(OH_NativeXComponent* component, void* window)
    {
        NoteEngineRegistry::Get().HandleSurfaceCreated(component, window);
    }

    static void OnSurfaceChanged(OH_NativeXComponent* component, void* window)
    {
        NoteEngineRegistry::Get().HandleSurfaceChanged(component, window);
    }

    static void OnSurfaceDestroyed(OH_NativeXComponent* component, void* window)
    {
        NoteEngineRegistry::Get().HandleSurfaceDestroyed(component, window);
    }

    static void OnTouchEvent(OH_NativeXComponent* component, void* window)
    {
        NoteEngineRegistry::Get().HandleTouchEvent(component, window);
    }

    static void OnUIInputEvent(
        OH_NativeXComponent* component, ArkUI_UIInputEvent* event, ArkUI_UIInputEvent_Type type)
    {
        NoteEngineRegistry::Get().HandleUIInputEvent(component, event, type);
    }

    static void OnKeyEvent(OH_NativeXComponent* component, void* /*window*/)
    {
        NoteEngineRegistry::Get().HandleKeyEvent(component);
    }

private:
    NoteEngineRegistry()
    {
        nativeCallback_.OnSurfaceCreated = &NoteEngineRegistry::OnSurfaceCreated;
        nativeCallback_.OnSurfaceChanged = &NoteEngineRegistry::OnSurfaceChanged;
        nativeCallback_.OnSurfaceDestroyed = &NoteEngineRegistry::OnSurfaceDestroyed;
        nativeCallback_.DispatchTouchEvent = &NoteEngineRegistry::OnTouchEvent;
    }

    EngineState* FindEngineLocked(const std::string& engineId)
    {
        auto iterator = engines_.find(engineId);
        if (iterator == engines_.end()) {
            return nullptr;
        }
        return &iterator->second;
    }

    SurfaceTelemetry* FindSurfaceLocked(const std::string& xComponentId)
    {
        if (xComponentId.empty()) {
            return nullptr;
        }
        auto iterator = surfaces_.find(xComponentId);
        if (iterator == surfaces_.end()) {
            return nullptr;
        }
        return &iterator->second;
    }

    void BindFirstMatchingEngineLocked(SurfaceTelemetry& telemetry)
    {
        if (!telemetry.boundEngineId.empty()) {
            return;
        }
        for (auto& entry : engines_) {
            if (entry.second.xComponentId == telemetry.xComponentId) {
                telemetry.boundEngineId = entry.second.engineId;
                if (telemetry.width > 0 && telemetry.height > 0) {
                    entry.second.width = static_cast<int>(telemetry.width);
                    entry.second.height = static_cast<int>(telemetry.height);
                }
                return;
            }
        }
    }

    EngineState* FindBoundEngineLocked(const SurfaceTelemetry& telemetry)
    {
        if (telemetry.boundEngineId.empty()) {
            return nullptr;
        }
        return FindEngineLocked(telemetry.boundEngineId);
    }

    void RenderSurfaceLocked(SurfaceTelemetry& telemetry, const EngineState* engine)
    {
        if (engine == nullptr) {
            return;
        }
        if (!EnsureGlRenderer(telemetry)) {
            return;
        }

        const float surfaceWidth = static_cast<float>(telemetry.width);
        const float surfaceHeight = static_cast<float>(telemetry.height);
        std::vector<RenderVertex> vertices;
        vertices.reserve(8192);
        AppendBackgroundVertices(vertices, *engine, surfaceWidth, surfaceHeight);

        for (const StrokeRenderObject& stroke : engine->committedStrokes) {
            AddToolStrokeMesh(vertices, stroke.points, *engine, stroke.tool, stroke.colorHex, false,
                surfaceWidth, surfaceHeight);
        }

        if (ToolProducesInk(engine->activeTool) && !telemetry.strokeSamples.empty()) {
            AddToolStrokeMesh(vertices, telemetry.strokeSamples, *engine, engine->activeTool, engine->activeColor,
                false, surfaceWidth, surfaceHeight);
        }

        if (ToolProducesInk(engine->activeTool) && engine->predictionEnabled &&
            !telemetry.predictedSamples.empty() && !telemetry.strokeSamples.empty()) {
            std::vector<InkPointSnapshot> predictedStroke;
            predictedStroke.reserve(telemetry.predictedSamples.size() + 1);
            predictedStroke.push_back(telemetry.strokeSamples.back());
            predictedStroke.insert(predictedStroke.end(), telemetry.predictedSamples.begin(), telemetry.predictedSamples.end());
            AddToolStrokeMesh(vertices, predictedStroke, *engine, engine->activeTool, engine->activeColor,
                true, surfaceWidth, surfaceHeight);
        }

        if (ToolUsesLassoSelection(engine->activeTool) && !telemetry.strokeSamples.empty()) {
            AddStrokeMesh(vertices, telemetry.strokeSamples, *engine, "pen", "#2A6AFB", true, surfaceWidth, surfaceHeight);
        }

        if (HasSelectedStroke(engine->committedStrokes)) {
            const StrokeBounds selectedBounds = ComputeSelectedBounds(engine->committedStrokes);
            AddOutlineRect(vertices,
                selectedBounds.minX - 10.0f,
                selectedBounds.minY - 10.0f,
                selectedBounds.maxX + 10.0f,
                selectedBounds.maxY + 10.0f,
                2.0f,
                ParseColorHex("#2A6AFB", 0.78f),
                surfaceWidth,
                surfaceHeight);
        }

        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        DrawVertices(telemetry.gl, vertices);
        eglSwapBuffers(telemetry.gl.display, telemetry.gl.surface);
    }

    void HandleSurfaceCreated(OH_NativeXComponent* component, void* window)
    {
        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.xComponentId = xComponentId;
        telemetry.component = component;
        telemetry.window = window;
        telemetry.surfaceReady = true;
        telemetry.surfaceCreateCount += 1;
        RefreshSurfaceGeometry(telemetry);
        if (EngineState* engine = FindBoundEngineLocked(telemetry); engine != nullptr) {
            engine->width = static_cast<int>(telemetry.width);
            engine->height = static_cast<int>(telemetry.height);
            RenderSurfaceLocked(telemetry, engine);
        }
    }

    void HandleSurfaceChanged(OH_NativeXComponent* component, void* window)
    {
        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.xComponentId = xComponentId;
        telemetry.component = component;
        telemetry.window = window;
        telemetry.surfaceReady = true;
        telemetry.surfaceChangeCount += 1;
        RefreshSurfaceGeometry(telemetry);
        if (EngineState* engine = FindBoundEngineLocked(telemetry); engine != nullptr) {
            engine->width = static_cast<int>(telemetry.width);
            engine->height = static_cast<int>(telemetry.height);
            RenderSurfaceLocked(telemetry, engine);
        }
    }

    void HandleSurfaceDestroyed(OH_NativeXComponent* component, void* /*window*/)
    {
        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.surfaceReady = false;
        telemetry.window = nullptr;
        telemetry.surfaceDestroyCount += 1;
        telemetry.stylusActive = false;
        telemetry.multitouchGestureActive = false;
        telemetry.activePointerCount = 0;
        telemetry.predictedPointCount = 0;
        telemetry.predictedSamples.clear();
        telemetry.previousPredictedSamples.clear();
        telemetry.strokeSamples.clear();
        telemetry.selectionDragActive = false;
        telemetry.selectionSnapshotCaptured = false;
        telemetry.stylusSessionOwned = false;
        telemetry.activeStylusPointerId = -1;
        DestroyGlRenderer(telemetry.gl);
    }

    InkPointSnapshot BuildPointFromTouchPoint(OH_NativeXComponent* component, uint32_t pointIndex,
        const OH_NativeXComponent_TouchPoint& point) const
    {
        InkPointSnapshot snapshot;
        snapshot.pointerId = point.id;
        snapshot.x = point.x;
        snapshot.y = point.y;
        snapshot.windowX = point.x;
        snapshot.windowY = point.y;
        snapshot.displayX = point.screenX;
        snapshot.displayY = point.screenY;
        snapshot.force = point.force;
        snapshot.timeStamp = point.timeStamp;

        OH_NativeXComponent_TouchPointToolType toolType = OH_NATIVEXCOMPONENT_TOOL_TYPE_UNKNOWN;
        if (OH_NativeXComponent_GetTouchPointToolType(component, pointIndex, &toolType) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.toolType = ToolTypeToString(toolType);
        }

        float tiltX = 0.0f;
        if (OH_NativeXComponent_GetTouchPointTiltX(component, pointIndex, &tiltX) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.tiltX = tiltX;
        }

        float tiltY = 0.0f;
        if (OH_NativeXComponent_GetTouchPointTiltY(component, pointIndex, &tiltY) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.tiltY = tiltY;
        }

        float windowX = snapshot.windowX;
        if (OH_NativeXComponent_GetTouchPointWindowX(component, pointIndex, &windowX) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.windowX = windowX;
        }

        float windowY = snapshot.windowY;
        if (OH_NativeXComponent_GetTouchPointWindowY(component, pointIndex, &windowY) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.windowY = windowY;
        }

        float displayX = snapshot.displayX;
        if (OH_NativeXComponent_GetTouchPointDisplayX(component, pointIndex, &displayX) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.displayX = displayX;
        }

        float displayY = snapshot.displayY;
        if (OH_NativeXComponent_GetTouchPointDisplayY(component, pointIndex, &displayY) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            snapshot.displayY = displayY;
        }

        return snapshot;
    }

    std::string BuildDefaultInputTracePath(const EngineState& engine) const
    {
        if (!engine.activeDocumentId.empty()) {
            auto iterator = engine.documents.find(engine.activeDocumentId);
            if (iterator != engine.documents.end() && !iterator->second.packagePath.empty()) {
                return iterator->second.packagePath + "/input-trace.json";
            }
        }
        return engine.engineId + "-input-trace.json";
    }

    SurfaceTelemetry& EnsureTraceSurfaceLocked(EngineState& engine)
    {
        if (engine.xComponentId.empty()) {
            engine.xComponentId = "trace-surface-" + engine.engineId;
        }
        SurfaceTelemetry& telemetry = surfaces_[engine.xComponentId];
        telemetry.xComponentId = engine.xComponentId;
        telemetry.boundEngineId = engine.engineId;
        return telemetry;
    }

    void ResetTransientInputStateLocked(SurfaceTelemetry& telemetry)
    {
        telemetry.stylusActive = false;
        telemetry.stylusSessionOwned = false;
        telemetry.activeStylusPointerId = -1;
        telemetry.multitouchGestureActive = false;
        telemetry.activePointerCount = 0;
        telemetry.predictedPointCount = 0;
        telemetry.predictedSamples.clear();
        telemetry.previousPredictedSamples.clear();
        telemetry.strokeSamples.clear();
        telemetry.selectionDragActive = false;
        telemetry.selectionSnapshotCaptured = false;
    }

    void RecordInputSampleLocked(EngineState* engine, const InputSample& sample)
    {
        if (engine == nullptr || !engine->inputTraceRecorder.active || engine->inputReplayActive) {
            return;
        }

        InputSample recordedSample = sample;
        recordedSample.sequence = engine->inputTraceRecorder.nextSequence;
        engine->inputTraceRecorder.nextSequence += 1;
        if (engine->inputTraceRecorder.trace.recordedAt == 0) {
            engine->inputTraceRecorder.trace.recordedAt = recordedSample.timeStamp;
        }
        engine->inputTraceRecorder.trace.samples.push_back(std::move(recordedSample));
        engine->lastInputTraceSampleCount = engine->inputTraceRecorder.trace.samples.size();
    }

    void PushRealSampleLocked(SurfaceTelemetry& telemetry, const InkPointSnapshot& sample)
    {
        telemetry.strokeSamples.push_back(sample);
        TrimStrokeSamples(telemetry.strokeSamples);
    }

    void UpdatePredictionLocked(SurfaceTelemetry& telemetry, const EngineState* engine)
    {
        telemetry.predictedSamples.clear();
        telemetry.predictedPointCount = 0;
        if (engine == nullptr || !engine->predictionEnabled || !telemetry.stylusActive ||
            !telemetry.stylusSessionOwned || !ToolProducesInk(engine->activeTool)) {
            telemetry.previousPredictedSamples.clear();
            return;
        }
        telemetry.predictedSamples = BuildPredictionTail(telemetry.strokeSamples, telemetry.previousPredictedSamples);
        telemetry.predictedPointCount = telemetry.predictedSamples.size();
        telemetry.previousPredictedSamples = telemetry.predictedSamples;
    }

    void ProcessTouchInputSampleLocked(SurfaceTelemetry& telemetry, EngineState* engine, const InputSample& sample)
    {
        if (sample.batchTerminal && !sample.historical) {
            telemetry.touchEventCount += 1;
            telemetry.activePointerCount = sample.activePointerCount;
            telemetry.lastEventTime = sample.timeStamp;
            telemetry.lastTouchAction = sample.action >= 0
                ? TouchActionToString(static_cast<OH_NativeXComponent_TouchEventType>(sample.action))
                : "unknown";
            telemetry.multitouchGestureActive = sample.activePointerCount > 1;
        }

        if (sample.zeroPointReset) {
            telemetry.lastToolType = "unknown";
            telemetry.lastSourceType = sample.sourceLabel.empty() ? "unknown" : sample.sourceLabel;
            ResetTransientInputStateLocked(telemetry);
            return;
        }

        const InkPointSnapshot& currentPoint = sample.point;
        const bool isStylusInput = IsStylusTool(sample.toolType);

        if (!sample.historical) {
            telemetry.lastSourceType = sample.sourceLabel;
            telemetry.lastToolType = sample.toolType;
            telemetry.lastPressure = currentPoint.force;
            telemetry.lastTiltX = currentPoint.tiltX;
            telemetry.lastTiltY = currentPoint.tiltY;
            if (sample.toolType == "finger") {
                telemetry.fingerEventCount += 1;
            } else if (isStylusInput) {
                telemetry.stylusEventCount += 1;
            }
        }

        if (sample.action == OH_NATIVEXCOMPONENT_DOWN && isStylusInput && !sample.historical) {
            telemetry.stylusActive = true;
            telemetry.stylusSessionOwned = true;
            telemetry.activeStylusPointerId = currentPoint.pointerId;
            telemetry.strokeSamples.clear();
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.selectionDragActive = false;
            telemetry.selectionSnapshotCaptured = false;

            if (engine != nullptr &&
                (ToolUsesLassoSelection(engine->activeTool) || ToolMovesSelection(engine->activeTool)) &&
                HasSelectedStroke(engine->committedStrokes)) {
                const StrokeBounds selectedBounds = ComputeSelectedBounds(engine->committedStrokes);
                if (IsPointInsideBounds(selectedBounds, currentPoint.x, currentPoint.y, 18.0f)) {
                    telemetry.selectionDragActive = true;
                    telemetry.selectionLastX = currentPoint.x;
                    telemetry.selectionLastY = currentPoint.y;
                } else if (ToolUsesLassoSelection(engine->activeTool)) {
                    ClearStrokeSelection(engine->committedStrokes);
                }
            } else if (engine != nullptr && ToolProducesInk(engine->activeTool)) {
                ClearStrokeSelection(engine->committedStrokes);
            }
        }

        if (telemetry.stylusSessionOwned && telemetry.activeStylusPointerId >= 0 &&
            currentPoint.pointerId != telemetry.activeStylusPointerId) {
            if (!sample.historical) {
                telemetry.palmRejectedCount += 1;
            }
            if (sample.batchTerminal && engine != nullptr) {
                RenderSurfaceLocked(telemetry, engine);
            }
            return;
        }

        const bool captureStrokeSamples = isStylusInput &&
            engine != nullptr &&
            !telemetry.selectionDragActive &&
            (ToolProducesInk(engine->activeTool) || ToolUsesLassoSelection(engine->activeTool));

        if (captureStrokeSamples) {
            PushRealSampleLocked(telemetry, currentPoint);
        } else if (!sample.historical && isStylusInput && engine != nullptr && ToolErasesObjects(engine->activeTool)) {
            telemetry.strokeSamples.clear();
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.predictedPointCount = 0;
            std::vector<StrokeRenderObject> erasedStrokes = engine->committedStrokes;
            if (EraseWithHybridStrategy(erasedStrokes, currentPoint)) {
                PushUndoSnapshot(*engine);
                PushUndoSnapshot(*engine);
                PushUndoSnapshot(*engine);
                engine->committedStrokes = std::move(erasedStrokes);
                RefreshLastCommittedStrokeType(*engine);
            }
        } else if (!sample.historical && isStylusInput && engine != nullptr && telemetry.selectionDragActive) {
            if (sample.action == OH_NATIVEXCOMPONENT_MOVE) {
                if (!telemetry.selectionSnapshotCaptured) {
                    PushUndoSnapshot(*engine);
                    telemetry.selectionSnapshotCaptured = true;
                }
                const float deltaX = currentPoint.x - telemetry.selectionLastX;
                const float deltaY = currentPoint.y - telemetry.selectionLastY;
                MoveSelectedStrokes(engine->committedStrokes, deltaX, deltaY);
                telemetry.selectionLastX = currentPoint.x;
                telemetry.selectionLastY = currentPoint.y;
            }
        } else if (!sample.historical && !isStylusInput && telemetry.stylusSessionOwned) {
            telemetry.palmRejectedCount += 1;
        }

        if (!sample.batchTerminal) {
            return;
        }

        if (sample.action == OH_NATIVEXCOMPONENT_UP &&
            engine != nullptr &&
            ToolProducesInk(engine->activeTool) &&
            telemetry.strokeSamples.size() > 1) {
            PushUndoSnapshot(*engine);
            StrokeRenderObject stroke = ApplyShapeRecognition(
                telemetry.strokeSamples, engine->activeTool, engine->activeColor, engine->shapeRecognitionEnabled);
            stroke.objectId = GenerateStrokeObjectId(*engine);
            engine->committedStrokes.push_back(stroke);
            RefreshLastCommittedStrokeType(*engine);
        }

        if (sample.action == OH_NATIVEXCOMPONENT_UP &&
            engine != nullptr &&
            ToolUsesLassoSelection(engine->activeTool) &&
            !telemetry.selectionDragActive &&
            telemetry.strokeSamples.size() > 2) {
            SelectStrokesByLasso(engine->committedStrokes, telemetry.strokeSamples);
        }

        if (sample.action == OH_NATIVEXCOMPONENT_UP || sample.action == OH_NATIVEXCOMPONENT_CANCEL) {
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.predictedPointCount = 0;
            telemetry.selectionDragActive = false;
            telemetry.selectionSnapshotCaptured = false;
            if (currentPoint.pointerId == telemetry.activeStylusPointerId) {
                telemetry.stylusActive = false;
                telemetry.stylusSessionOwned = false;
                telemetry.activeStylusPointerId = -1;
            }
            if (!ToolProducesInk(engine != nullptr ? engine->activeTool : "")) {
                telemetry.strokeSamples.clear();
            }
        } else {
            UpdatePredictionLocked(telemetry, engine);
        }

        if (sample.action == OH_NATIVEXCOMPONENT_UP || sample.action == OH_NATIVEXCOMPONENT_CANCEL) {
            telemetry.strokeSamples.clear();
        }
        if (engine != nullptr) {
            RenderSurfaceLocked(telemetry, engine);
        }
    }

    void ProcessUiTouchInputSampleLocked(SurfaceTelemetry& telemetry, EngineState* engine, const InputSample& sample)
    {
        telemetry.uiTouchEventCount += 1;
        telemetry.lastEventTime = sample.timeStamp;
        telemetry.lastUiAction = sample.action;
        telemetry.lastUiToolType = sample.toolCode;
        telemetry.lastUiSourceType = sample.uiSourceType;
        telemetry.lastUiHistoryCount = static_cast<size_t>(sample.uiHistoryCount);
        telemetry.lastSourceType = sample.sourceLabel;
        if (telemetry.lastToolType == "unknown") {
            telemetry.lastToolType = sample.toolType;
        }

        telemetry.activePointerCount = sample.activePointerCount;
        if (sample.activePointerCount > 0) {
            telemetry.lastPressure = sample.pressure;
            telemetry.lastTiltX = sample.tiltX;
            telemetry.lastTiltY = sample.tiltY;
        }

        if (sample.hasRollAngle) {
            telemetry.lastRollAngle = sample.rollAngle;
            if (!telemetry.strokeSamples.empty() && sample.toolCode == UI_INPUT_EVENT_TOOL_TYPE_PEN) {
                telemetry.strokeSamples.back().rollAngle = sample.rollAngle;
                telemetry.strokeSamples.back().hasRollAngle = true;
            }
        }

        if (engine != nullptr && telemetry.stylusActive) {
            RenderSurfaceLocked(telemetry, engine);
        }
    }

    void ProcessKeyInputSampleLocked(SurfaceTelemetry& telemetry, EngineState* engine, const InputSample& sample)
    {
        telemetry.keyEventCount += 1;
        telemetry.lastKeyAction = sample.action;
        telemetry.lastKeyCode = sample.keyCode;
        telemetry.lastKeySourceType = sample.sourceType;
        telemetry.lastKeyEventTime = sample.timeStamp;

        if (engine == nullptr || !engine->doubleTapSwitchEnabled ||
            telemetry.lastKeyAction != static_cast<int32_t>(OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN) ||
            !IsStylusLikeKeySource(telemetry.lastKeySourceType)) {
            return;
        }

        const bool allowUnknownKey = telemetry.lastKeyCode == KEY_UNKNOWN &&
            (telemetry.lastToolType == "pen" || telemetry.lastToolType == "pencil" || telemetry.lastToolType == "rubber");
        if (telemetry.lastKeyCode == KEY_UNKNOWN && !allowUnknownKey) {
            return;
        }

        const bool sameKey = telemetry.lastKeyCode == engine->lastStylusToggleKeyCode;
        const int64_t deltaMs = telemetry.lastKeyEventTime - engine->lastStylusToggleTimeMs;
        if (sameKey && engine->lastStylusToggleTimeMs > 0 && deltaMs > 0 &&
            deltaMs <= kStylusToggleDoubleTapWindowMs) {
            engine->lastStylusToggleTimeMs = 0;
            engine->lastStylusToggleKeyCode = KEY_UNKNOWN;
            if (ToggleStylusTool(*engine)) {
                RenderSurfaceLocked(telemetry, engine);
            }
            return;
        }

        engine->lastStylusToggleKeyCode = telemetry.lastKeyCode;
        engine->lastStylusToggleTimeMs = telemetry.lastKeyEventTime;
    }

    void ProcessInputSampleLocked(SurfaceTelemetry& telemetry, EngineState* engine, const InputSample& sample)
    {
        switch (sample.type) {
            case InputSampleType::kUiTouch:
                ProcessUiTouchInputSampleLocked(telemetry, engine, sample);
                break;
            case InputSampleType::kKey:
                ProcessKeyInputSampleLocked(telemetry, engine, sample);
                break;
            case InputSampleType::kTouch:
            default:
                ProcessTouchInputSampleLocked(telemetry, engine, sample);
                break;
        }
    }

    void HandleTouchEvent(OH_NativeXComponent* component, void* window)
    {
        OH_NativeXComponent_TouchEvent touchEvent {};
        if (OH_NativeXComponent_GetTouchEvent(component, window, &touchEvent) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            return;
        }

        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.xComponentId = xComponentId;
        telemetry.component = component;
        telemetry.window = window;
        telemetry.surfaceReady = true;
        // Touch counters are now updated inside the normalized input pipeline.
        telemetry.activePointerCount = static_cast<int>(touchEvent.numPoints);
        telemetry.lastEventTime = touchEvent.timeStamp;
        telemetry.lastTouchAction = TouchActionToString(touchEvent.type);
        telemetry.multitouchGestureActive = touchEvent.numPoints > 1;
        RefreshSurfaceGeometry(telemetry);

        EngineState* normalizedEngine = FindBoundEngineLocked(telemetry);
        std::vector<InputSample> normalizedSamples;
        if (touchEvent.numPoints == 0) {
            InputSample resetSample;
            resetSample.type = InputSampleType::kTouch;
            resetSample.timeStamp = touchEvent.timeStamp;
            resetSample.activePointerCount = 0;
            resetSample.action = static_cast<int32_t>(touchEvent.type);
            resetSample.zeroPointReset = true;
            resetSample.batchTerminal = true;
            resetSample.sourceLabel = "unknown";
            normalizedSamples.push_back(std::move(resetSample));
        } else {
            uint32_t normalizedPointIndex = 0;
            for (uint32_t index = 0; index < touchEvent.numPoints; ++index) {
                if (touchEvent.touchPoints[index].id == touchEvent.id) {
                    normalizedPointIndex = index;
                    break;
                }
            }

            InkPointSnapshot normalizedCurrentPoint = BuildPointFromTouchPoint(component, normalizedPointIndex,
                touchEvent.touchPoints[normalizedPointIndex]);

            OH_NativeXComponent_EventSourceType normalizedSourceType = OH_NATIVEXCOMPONENT_SOURCE_TYPE_UNKNOWN;
            std::string normalizedSourceLabel = "unknown";
            if (OH_NativeXComponent_GetTouchEventSourceType(
                    component, normalizedCurrentPoint.pointerId, &normalizedSourceType) ==
                OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
                normalizedSourceLabel = EventSourceToString(normalizedSourceType);
            }

            int32_t normalizedHistoricalCount = 0;
            OH_NativeXComponent_HistoricalPoint* normalizedHistoricalPoints = nullptr;
            if (OH_NativeXComponent_GetHistoricalPoints(
                    component, window, &normalizedHistoricalCount, &normalizedHistoricalPoints) ==
                OH_NATIVEXCOMPONENT_RESULT_SUCCESS &&
                normalizedHistoricalCount > 0 &&
                normalizedHistoricalPoints != nullptr) {
                telemetry.lastHistoricalCount = static_cast<size_t>(normalizedHistoricalCount);
                if (IsStylusTool(normalizedCurrentPoint.toolType)) {
                    for (int32_t index = 0; index < normalizedHistoricalCount; ++index) {
                        const OH_NativeXComponent_HistoricalPoint& historicalPoint = normalizedHistoricalPoints[index];
                        if (historicalPoint.id != normalizedCurrentPoint.pointerId) {
                            continue;
                        }

                        InkPointSnapshot historicalSnapshot;
                        historicalSnapshot.pointerId = historicalPoint.id;
                        historicalSnapshot.x = historicalPoint.x;
                        historicalSnapshot.y = historicalPoint.y;
                        historicalSnapshot.windowX = historicalPoint.x;
                        historicalSnapshot.windowY = historicalPoint.y;
                        historicalSnapshot.displayX = historicalPoint.screenX;
                        historicalSnapshot.displayY = historicalPoint.screenY;
                        historicalSnapshot.force = historicalPoint.force;
                        historicalSnapshot.tiltX = historicalPoint.titlX;
                        historicalSnapshot.tiltY = historicalPoint.titlY;
                        historicalSnapshot.timeStamp = historicalPoint.timeStamp;
                        historicalSnapshot.historical = true;
                        historicalSnapshot.toolType = SourceToolToString(historicalPoint.sourceTool);
                        if (historicalSnapshot.toolType == "unknown") {
                            historicalSnapshot.toolType = normalizedCurrentPoint.toolType;
                        }

                        InputSample historicalSample;
                        historicalSample.type = InputSampleType::kTouch;
                        historicalSample.timeStamp = historicalSnapshot.timeStamp;
                        historicalSample.pointerId = historicalSnapshot.pointerId;
                        historicalSample.activePointerCount = static_cast<int32_t>(touchEvent.numPoints);
                        historicalSample.action = static_cast<int32_t>(touchEvent.type);
                        historicalSample.sourceType = static_cast<int32_t>(normalizedSourceType);
                        historicalSample.toolType = historicalSnapshot.toolType;
                        historicalSample.sourceLabel = normalizedSourceLabel;
                        historicalSample.historical = true;
                        historicalSample.batchTerminal = false;
                        historicalSample.point = historicalSnapshot;
                        normalizedSamples.push_back(std::move(historicalSample));
                    }
                }
            } else {
                telemetry.lastHistoricalCount = 0;
            }

            InputSample currentSample;
            currentSample.type = InputSampleType::kTouch;
            currentSample.timeStamp = normalizedCurrentPoint.timeStamp;
            currentSample.pointerId = normalizedCurrentPoint.pointerId;
            currentSample.activePointerCount = static_cast<int32_t>(touchEvent.numPoints);
            currentSample.action = static_cast<int32_t>(touchEvent.type);
            currentSample.sourceType = static_cast<int32_t>(normalizedSourceType);
            currentSample.toolType = normalizedCurrentPoint.toolType;
            currentSample.sourceLabel = normalizedSourceLabel;
            currentSample.batchTerminal = true;
            currentSample.point = normalizedCurrentPoint;
            normalizedSamples.push_back(std::move(currentSample));
        }

        for (const InputSample& sample : normalizedSamples) {
            RecordInputSampleLocked(normalizedEngine, sample);
            ProcessInputSampleLocked(telemetry, normalizedEngine, sample);
        }
        return;

#if 0

        uint32_t activePointIndex = 0;
        for (uint32_t index = 0; index < touchEvent.numPoints; ++index) {
            if (touchEvent.touchPoints[index].id == touchEvent.id) {
                activePointIndex = index;
                break;
            }
        }

        if (touchEvent.numPoints == 0) {
            telemetry.lastToolType = "unknown";
            telemetry.lastSourceType = "unknown";
            telemetry.predictedPointCount = 0;
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.stylusActive = false;
            telemetry.stylusSessionOwned = false;
            telemetry.activeStylusPointerId = -1;
            telemetry.selectionDragActive = false;
            return;
        }

        InkPointSnapshot currentPoint = BuildPointFromTouchPoint(component, activePointIndex,
            touchEvent.touchPoints[activePointIndex]);

        OH_NativeXComponent_EventSourceType sourceType = OH_NATIVEXCOMPONENT_SOURCE_TYPE_UNKNOWN;
        if (OH_NativeXComponent_GetTouchEventSourceType(component, currentPoint.pointerId, &sourceType) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            telemetry.lastSourceType = EventSourceToString(sourceType);
        } else {
            telemetry.lastSourceType = "unknown";
        }

        telemetry.lastToolType = currentPoint.toolType;
        telemetry.lastPressure = currentPoint.force;
        telemetry.lastTiltX = currentPoint.tiltX;
        telemetry.lastTiltY = currentPoint.tiltY;

        bool isStylusInput = IsStylusTool(currentPoint.toolType);
        if (currentPoint.toolType == "finger") {
            telemetry.fingerEventCount += 1;
        } else if (isStylusInput) {
            telemetry.stylusEventCount += 1;
        }

        EngineState* normalizedEngine = FindBoundEngineLocked(telemetry);

        if (touchEvent.type == OH_NATIVEXCOMPONENT_DOWN && isStylusInput) {
            telemetry.stylusActive = true;
            telemetry.stylusSessionOwned = true;
            telemetry.activeStylusPointerId = currentPoint.pointerId;
            telemetry.strokeSamples.clear();
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.selectionDragActive = false;
            telemetry.selectionSnapshotCaptured = false;

            if (engine != nullptr && (ToolUsesLassoSelection(engine->activeTool) || ToolMovesSelection(engine->activeTool)) &&
                HasSelectedStroke(engine->committedStrokes)) {
                const StrokeBounds selectedBounds = ComputeSelectedBounds(engine->committedStrokes);
                if (IsPointInsideBounds(selectedBounds, currentPoint.x, currentPoint.y, 18.0f)) {
                    telemetry.selectionDragActive = true;
                    telemetry.selectionLastX = currentPoint.x;
                    telemetry.selectionLastY = currentPoint.y;
                } else if (ToolUsesLassoSelection(engine->activeTool)) {
                    ClearStrokeSelection(engine->committedStrokes);
                }
            } else if (engine != nullptr && ToolProducesInk(engine->activeTool)) {
                ClearStrokeSelection(engine->committedStrokes);
            }
        }

        if (telemetry.stylusSessionOwned && telemetry.activeStylusPointerId >= 0 &&
            currentPoint.pointerId != telemetry.activeStylusPointerId) {
            telemetry.palmRejectedCount += 1;
            if (engine != nullptr) {
                RenderSurfaceLocked(telemetry, engine);
            }
            return;
        }

        const bool captureStrokeSamples = isStylusInput &&
            engine != nullptr &&
            !telemetry.selectionDragActive &&
            (ToolProducesInk(engine->activeTool) || ToolUsesLassoSelection(engine->activeTool));

        int32_t historicalCount = 0;
        OH_NativeXComponent_HistoricalPoint* historicalPoints = nullptr;
        if (OH_NativeXComponent_GetHistoricalPoints(component, window, &historicalCount, &historicalPoints) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS && historicalCount > 0 && historicalPoints != nullptr) {
            telemetry.lastHistoricalCount = static_cast<size_t>(historicalCount);
            if (captureStrokeSamples) {
                for (int32_t index = 0; index < historicalCount; ++index) {
                    const OH_NativeXComponent_HistoricalPoint& historicalPoint = historicalPoints[index];
                    if (historicalPoint.id != currentPoint.pointerId) {
                        continue;
                    }
                    InkPointSnapshot historicalSnapshot;
                    historicalSnapshot.pointerId = historicalPoint.id;
                    historicalSnapshot.x = historicalPoint.x;
                    historicalSnapshot.y = historicalPoint.y;
                    historicalSnapshot.windowX = historicalPoint.x;
                    historicalSnapshot.windowY = historicalPoint.y;
                    historicalSnapshot.displayX = historicalPoint.screenX;
                    historicalSnapshot.displayY = historicalPoint.screenY;
                    historicalSnapshot.force = historicalPoint.force;
                    historicalSnapshot.tiltX = historicalPoint.titlX;
                    historicalSnapshot.tiltY = historicalPoint.titlY;
                    historicalSnapshot.timeStamp = historicalPoint.timeStamp;
                    historicalSnapshot.historical = true;
                    historicalSnapshot.toolType = SourceToolToString(historicalPoint.sourceTool);
                    if (historicalSnapshot.toolType == "unknown") {
                        historicalSnapshot.toolType = currentPoint.toolType;
                    }
                    PushRealSampleLocked(telemetry, historicalSnapshot);
                }
            }
        } else {
            telemetry.lastHistoricalCount = 0;
        }

        if (captureStrokeSamples) {
            PushRealSampleLocked(telemetry, currentPoint);
        } else if (isStylusInput && engine != nullptr && ToolErasesObjects(engine->activeTool)) {
            telemetry.strokeSamples.clear();
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.predictedPointCount = 0;
            std::vector<StrokeRenderObject> erasedStrokes = engine->committedStrokes;
            if (EraseWithHybridStrategy(erasedStrokes, currentPoint)) {
                // 中文注释：对象擦除属于文档状态变更，先存快照再删，保证撤销栈完整。
                PushUndoSnapshot(*engine);
                // 中文注释：橡皮擦会修改对象集合，先存快照再提交结果，保证撤销栈完整。
                PushUndoSnapshot(*engine);
                PushUndoSnapshot(*engine);
                engine->committedStrokes = std::move(erasedStrokes);
                RefreshLastCommittedStrokeType(*engine);
            }
        } else if (isStylusInput && engine != nullptr && telemetry.selectionDragActive) {
            if (touchEvent.type == OH_NATIVEXCOMPONENT_MOVE) {
                if (!telemetry.selectionSnapshotCaptured) {
                    PushUndoSnapshot(*engine);
                    telemetry.selectionSnapshotCaptured = true;
                }
                const float deltaX = currentPoint.x - telemetry.selectionLastX;
                const float deltaY = currentPoint.y - telemetry.selectionLastY;
                MoveSelectedStrokes(engine->committedStrokes, deltaX, deltaY);
                telemetry.selectionLastX = currentPoint.x;
                telemetry.selectionLastY = currentPoint.y;
            }
        } else if (!isStylusInput && telemetry.stylusSessionOwned) {
            telemetry.palmRejectedCount += 1;
        }

        if (touchEvent.type == OH_NATIVEXCOMPONENT_UP &&
            engine != nullptr &&
            ToolProducesInk(engine->activeTool) &&
            telemetry.strokeSamples.size() > 1) {
            PushUndoSnapshot(*engine);
            StrokeRenderObject stroke = ApplyShapeRecognition(
                telemetry.strokeSamples, engine->activeTool, engine->activeColor, engine->shapeRecognitionEnabled);
            stroke.objectId = GenerateStrokeObjectId(*engine);
            engine->committedStrokes.push_back(stroke);
            RefreshLastCommittedStrokeType(*engine);
        }

        if (touchEvent.type == OH_NATIVEXCOMPONENT_UP &&
            engine != nullptr &&
            ToolUsesLassoSelection(engine->activeTool) &&
            !telemetry.selectionDragActive &&
            telemetry.strokeSamples.size() > 2) {
            SelectStrokesByLasso(engine->committedStrokes, telemetry.strokeSamples);
        }

        if (touchEvent.type == OH_NATIVEXCOMPONENT_UP || touchEvent.type == OH_NATIVEXCOMPONENT_CANCEL) {
            telemetry.predictedSamples.clear();
            telemetry.previousPredictedSamples.clear();
            telemetry.predictedPointCount = 0;
            telemetry.selectionDragActive = false;
            telemetry.selectionSnapshotCaptured = false;
            if (currentPoint.pointerId == telemetry.activeStylusPointerId) {
                telemetry.stylusActive = false;
                telemetry.stylusSessionOwned = false;
                telemetry.activeStylusPointerId = -1;
            }
            if (!ToolProducesInk(engine != nullptr ? engine->activeTool : "")) {
                telemetry.strokeSamples.clear();
            }
        } else {
            UpdatePredictionLocked(telemetry, engine);
        }

        if (touchEvent.type == OH_NATIVEXCOMPONENT_UP || touchEvent.type == OH_NATIVEXCOMPONENT_CANCEL) {
            telemetry.strokeSamples.clear();
        }
        if (engine != nullptr) {
            RenderSurfaceLocked(telemetry, engine);
        }
#endif
    }

    void HandleUIInputEvent(OH_NativeXComponent* component, ArkUI_UIInputEvent* event, ArkUI_UIInputEvent_Type type)
    {
        if (component == nullptr || event == nullptr || type != ARKUI_UIINPUTEVENT_TYPE_TOUCH) {
            return;
        }

        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.xComponentId = xComponentId;
        telemetry.component = component;
        EngineState* normalizedEngine = FindBoundEngineLocked(telemetry);

        const uint32_t normalizedPointerCount = OH_ArkUI_PointerEvent_GetPointerCount(event);
        InputSample normalizedSample;
        normalizedSample.type = InputSampleType::kUiTouch;
        normalizedSample.timeStamp = OH_ArkUI_UIInputEvent_GetEventTime(event);
        normalizedSample.activePointerCount = static_cast<int32_t>(normalizedPointerCount);
        normalizedSample.action = OH_ArkUI_UIInputEvent_GetAction(event);
        normalizedSample.toolCode = OH_ArkUI_UIInputEvent_GetToolType(event);
        normalizedSample.uiSourceType = OH_ArkUI_UIInputEvent_GetSourceType(event);
        normalizedSample.uiHistoryCount = static_cast<int32_t>(OH_ArkUI_PointerEvent_GetHistorySize(event));
        normalizedSample.sourceLabel = UiInputSourceTypeToString(normalizedSample.uiSourceType);
        normalizedSample.toolType = UiInputToolTypeToString(normalizedSample.toolCode);
        if (normalizedPointerCount > 0) {
            normalizedSample.pressure = OH_ArkUI_PointerEvent_GetPressure(event, 0);
            normalizedSample.tiltX = OH_ArkUI_PointerEvent_GetTiltX(event, 0);
            normalizedSample.tiltY = OH_ArkUI_PointerEvent_GetTiltY(event, 0);
        }

        double normalizedRollAngle = 0.0;
        if (OH_ArkUI_PointerEvent_GetRollAngle(event, &normalizedRollAngle) == ARKUI_ERROR_CODE_NO_ERROR) {
            normalizedSample.rollAngle = normalizedRollAngle;
            normalizedSample.hasRollAngle = true;
        }

        RecordInputSampleLocked(normalizedEngine, normalizedSample);
        ProcessInputSampleLocked(telemetry, normalizedEngine, normalizedSample);
        return;

#if 0

        telemetry.uiTouchEventCount += 1;
        telemetry.lastEventTime = OH_ArkUI_UIInputEvent_GetEventTime(event);
        telemetry.lastUiAction = OH_ArkUI_UIInputEvent_GetAction(event);
        telemetry.lastUiToolType = OH_ArkUI_UIInputEvent_GetToolType(event);
        telemetry.lastUiSourceType = OH_ArkUI_UIInputEvent_GetSourceType(event);
        telemetry.lastUiHistoryCount = OH_ArkUI_PointerEvent_GetHistorySize(event);
        telemetry.lastSourceType = UiInputSourceTypeToString(telemetry.lastUiSourceType);
        if (telemetry.lastToolType == "unknown") {
            telemetry.lastToolType = UiInputToolTypeToString(telemetry.lastUiToolType);
        }

        const uint32_t pointerCount = OH_ArkUI_PointerEvent_GetPointerCount(event);
        telemetry.activePointerCount = static_cast<int>(pointerCount);
        if (pointerCount > 0) {
            telemetry.lastPressure = OH_ArkUI_PointerEvent_GetPressure(event, 0);
            telemetry.lastTiltX = OH_ArkUI_PointerEvent_GetTiltX(event, 0);
            telemetry.lastTiltY = OH_ArkUI_PointerEvent_GetTiltY(event, 0);
        }

        double rollAngle = 0.0;
        if (OH_ArkUI_PointerEvent_GetRollAngle(event, &rollAngle) == ARKUI_ERROR_CODE_NO_ERROR) {
            telemetry.lastRollAngle = rollAngle;
            if (!telemetry.strokeSamples.empty() && telemetry.lastUiToolType == UI_INPUT_EVENT_TOOL_TYPE_PEN) {
                telemetry.strokeSamples.back().rollAngle = rollAngle;
                telemetry.strokeSamples.back().hasRollAngle = true;
            }
        }

        if (EngineState* engine = FindBoundEngineLocked(telemetry); engine != nullptr && telemetry.stylusActive) {
            RenderSurfaceLocked(telemetry, engine);
        }
#endif
    }

    void HandleKeyEvent(OH_NativeXComponent* component)
    {
        if (component == nullptr) {
            return;
        }

        OH_NativeXComponent_KeyEvent* keyEvent = nullptr;
        if (OH_NativeXComponent_GetKeyEvent(component, &keyEvent) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS ||
            keyEvent == nullptr) {
            return;
        }

        const std::string xComponentId = ReadXComponentId(component);
        if (xComponentId.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        SurfaceTelemetry& telemetry = surfaces_[xComponentId];
        telemetry.xComponentId = xComponentId;
        telemetry.component = component;
        EngineState* normalizedEngine = FindBoundEngineLocked(telemetry);

        OH_NativeXComponent_KeyAction normalizedAction = OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN;
        OH_NativeXComponent_GetKeyEventAction(keyEvent, &normalizedAction);
        OH_NativeXComponent_KeyCode normalizedKeyCode = KEY_UNKNOWN;
        OH_NativeXComponent_GetKeyEventCode(keyEvent, &normalizedKeyCode);
        OH_NativeXComponent_EventSourceType normalizedSourceType = OH_NATIVEXCOMPONENT_SOURCE_TYPE_UNKNOWN;
        OH_NativeXComponent_GetKeyEventSourceType(keyEvent, &normalizedSourceType);
        int64_t normalizedTimeStamp = 0;
        OH_NativeXComponent_GetKeyEventTimestamp(keyEvent, &normalizedTimeStamp);

        InputSample normalizedSample;
        normalizedSample.type = InputSampleType::kKey;
        normalizedSample.timeStamp = normalizedTimeStamp;
        normalizedSample.action = static_cast<int32_t>(normalizedAction);
        normalizedSample.keyCode = static_cast<int32_t>(normalizedKeyCode);
        normalizedSample.sourceType = static_cast<int32_t>(normalizedSourceType);
        normalizedSample.sourceLabel = EventSourceToString(normalizedSourceType);
        RecordInputSampleLocked(normalizedEngine, normalizedSample);
        ProcessInputSampleLocked(telemetry, normalizedEngine, normalizedSample);
        return;

#if 0

        telemetry.keyEventCount += 1;

        OH_NativeXComponent_KeyAction action = OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN;
        if (OH_NativeXComponent_GetKeyEventAction(keyEvent, &action) == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            telemetry.lastKeyAction = static_cast<int32_t>(action);
        }

        OH_NativeXComponent_KeyCode keyCode = KEY_UNKNOWN;
        if (OH_NativeXComponent_GetKeyEventCode(keyEvent, &keyCode) == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            telemetry.lastKeyCode = static_cast<int32_t>(keyCode);
        }

        OH_NativeXComponent_EventSourceType sourceType = OH_NATIVEXCOMPONENT_SOURCE_TYPE_UNKNOWN;
        if (OH_NativeXComponent_GetKeyEventSourceType(keyEvent, &sourceType) == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            telemetry.lastKeySourceType = static_cast<int32_t>(sourceType);
        }

        int64_t timeStamp = 0;
        if (OH_NativeXComponent_GetKeyEventTimestamp(keyEvent, &timeStamp) == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
            telemetry.lastKeyEventTime = timeStamp;
        }

        EngineState* engine = FindBoundEngineLocked(telemetry);
        if (engine == nullptr || !engine->doubleTapSwitchEnabled ||
            telemetry.lastKeyAction != static_cast<int32_t>(OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN) ||
            !IsStylusLikeKeySource(telemetry.lastKeySourceType)) {
            return;
        }

        const bool allowUnknownKey = telemetry.lastKeyCode == KEY_UNKNOWN &&
            (telemetry.lastToolType == "pen" || telemetry.lastToolType == "pencil" || telemetry.lastToolType == "rubber");
        if (telemetry.lastKeyCode == KEY_UNKNOWN && !allowUnknownKey) {
            return;
        }

        const bool sameKey = telemetry.lastKeyCode == engine->lastStylusToggleKeyCode;
        const int64_t deltaMs = telemetry.lastKeyEventTime - engine->lastStylusToggleTimeMs;
        if (sameKey && engine->lastStylusToggleTimeMs > 0 && deltaMs > 0 &&
            deltaMs <= kStylusToggleDoubleTapWindowMs) {
            engine->lastStylusToggleTimeMs = 0;
            engine->lastStylusToggleKeyCode = KEY_UNKNOWN;
            if (ToggleStylusTool(*engine)) {
                RenderSurfaceLocked(telemetry, engine);
            }
            return;
        }

        engine->lastStylusToggleKeyCode = telemetry.lastKeyCode;
        engine->lastStylusToggleTimeMs = telemetry.lastKeyEventTime;
#endif
    }

    std::mutex mutex_;
    int engineCounter_ = 0;
    std::unordered_map<std::string, EngineState> engines_;
    std::unordered_map<std::string, SurfaceTelemetry> surfaces_;
    OH_NativeXComponent_Callback nativeCallback_ {};
};

void RegisterXComponentFromExports(napi_env env, napi_value exports)
{
    bool hasNativeXComponent = false;
    if (napi_has_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &hasNativeXComponent) != napi_ok ||
        !hasNativeXComponent) {
        return;
    }

    napi_value nativeXComponentValue = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &nativeXComponentValue) != napi_ok) {
        return;
    }

    void* nativePointer = nullptr;
    if (napi_unwrap(env, nativeXComponentValue, &nativePointer) != napi_ok || nativePointer == nullptr) {
        return;
    }

    NoteEngineRegistry::Get().RegisterNativeComponent(
        reinterpret_cast<OH_NativeXComponent*>(nativePointer));
}

} // namespace

NoteEngineRuntime& GetNoteEngineRuntime()
{
    return NoteEngineRegistry::Get();
}
