#include "note_engine_runtime.h"

#include <string>

namespace {

std::string GetStringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::string result(length + 1, '\0');
    size_t copied = 0;
    napi_get_value_string_utf8(env, value, result.data(), result.size(), &copied);
    result.resize(copied);
    return result;
}

int32_t GetIntArg(napi_env env, napi_value value)
{
    int32_t result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

double GetDoubleArg(napi_env env, napi_value value)
{
    double result = 0.0;
    napi_get_value_double(env, value, &result);
    return result;
}

bool GetBoolArg(napi_env env, napi_value value)
{
    bool result = false;
    napi_get_value_bool(env, value, &result);
    return result;
}

napi_value CreateBoolean(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value CreateString(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

} // namespace

EXTERN_C_START

static napi_value CreateEngine(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return CreateString(env, GetNoteEngineRuntime().CreateEngine(argc == 1 ? GetStringArg(env, args[0]) : "{}"));
}

static napi_value OpenDocument(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 4 && GetNoteEngineRuntime().OpenDocument(
        GetStringArg(env, args[0]),
        GetStringArg(env, args[1]),
        GetStringArg(env, args[2]),
        GetStringArg(env, args[3]));
    return CreateBoolean(env, ok);
}

static napi_value AttachXComponent(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 3 && GetNoteEngineRuntime().AttachXComponent(
        GetStringArg(env, args[0]),
        GetStringArg(env, args[1]),
        GetStringArg(env, args[2]));
    return CreateBoolean(env, ok);
}

static napi_value Resize(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 4 && GetNoteEngineRuntime().Resize(
        GetStringArg(env, args[0]),
        GetIntArg(env, args[1]),
        GetIntArg(env, args[2]),
        GetDoubleArg(env, args[3]));
    return CreateBoolean(env, ok);
}

static napi_value SaveCheckpoint(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SaveCheckpoint(
        GetStringArg(env, args[0]),
        GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value RequestPreviewRender(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string response = argc == 5
        ? GetNoteEngineRuntime().RequestPreviewRender(
            GetStringArg(env, args[0]),
            GetStringArg(env, args[1]),
            GetIntArg(env, args[2]),
            GetIntArg(env, args[3]),
            GetIntArg(env, args[4]))
        : R"({"status":"invalid-args"})";
    return CreateString(env, response);
}

static napi_value ExportSceneSnapshot(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string response = argc == 2
        ? GetNoteEngineRuntime().ExportSceneSnapshot(
            GetStringArg(env, args[0]),
            GetStringArg(env, args[1]))
        : R"({"status":"invalid-args"})";
    return CreateString(env, response);
}

static napi_value ReadPdfPageCount(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string response = argc == 1
        ? GetNoteEngineRuntime().ReadPdfPageCount(GetStringArg(env, args[0]))
        : R"({"status":"invalid-args","detail":"pdfPath is required"})";
    return CreateString(env, response);
}

static napi_value SetActivePage(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SetActivePage(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value InsertPage(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 3 && GetNoteEngineRuntime().InsertPage(
        GetStringArg(env, args[0]),
        GetStringArg(env, args[1]),
        GetStringArg(env, args[2]));
    return CreateBoolean(env, ok);
}

static napi_value DeletePage(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().DeletePage(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value SetTool(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SetTool(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value SetFingerWritingEnabled(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 &&
        GetNoteEngineRuntime().SetFingerWritingEnabled(GetStringArg(env, args[0]), GetBoolArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value InjectSimulatorFingerEvent(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 5 && GetNoteEngineRuntime().InjectSimulatorFingerEvent(
        GetStringArg(env, args[0]),
        GetStringArg(env, args[1]),
        GetDoubleArg(env, args[2]),
        GetDoubleArg(env, args[3]),
        GetIntArg(env, args[4]));
    return CreateBoolean(env, ok);
}

static napi_value SetBackend(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SetBackend(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value SetDocumentMode(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SetDocumentMode(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value SetBrushColor(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SetBrushColor(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value SetBrushWidth(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().SetBrushWidth(GetStringArg(env, args[0]), GetDoubleArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value Undo(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 1 && GetNoteEngineRuntime().Undo(GetStringArg(env, args[0]));
    return CreateBoolean(env, ok);
}

static napi_value Redo(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 1 && GetNoteEngineRuntime().Redo(GetStringArg(env, args[0]));
    return CreateBoolean(env, ok);
}

static napi_value StartInputTraceRecording(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string tracePath = argc >= 2 ? GetStringArg(env, args[1]) : "";
    bool ok = argc >= 1 && GetNoteEngineRuntime().StartInputTraceRecording(GetStringArg(env, args[0]), tracePath);
    return CreateBoolean(env, ok);
}

static napi_value StopInputTraceRecording(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string response = argc == 1
        ? GetNoteEngineRuntime().StopInputTraceRecording(GetStringArg(env, args[0]))
        : R"({"status":"invalid-args"})";
    return CreateString(env, response);
}

static napi_value ReplayInputTrace(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string tracePath = argc >= 2 ? GetStringArg(env, args[1]) : "";
    std::string response = argc >= 1
        ? GetNoteEngineRuntime().ReplayInputTrace(GetStringArg(env, args[0]), tracePath)
        : R"({"status":"invalid-args"})";
    return CreateString(env, response);
}

static napi_value DisposeDocument(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 2 && GetNoteEngineRuntime().DisposeDocument(GetStringArg(env, args[0]), GetStringArg(env, args[1]));
    return CreateBoolean(env, ok);
}

static napi_value DisposeEngine(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool ok = argc == 1 && GetNoteEngineRuntime().DisposeEngine(GetStringArg(env, args[0]));
    return CreateBoolean(env, ok);
}

static napi_value GetDebugState(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string response = argc == 1
        ? GetNoteEngineRuntime().GetDebugState(GetStringArg(env, args[0]))
        : R"({"status":"invalid-args"})";
    return CreateString(env, response);
}

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        { "createEngine", nullptr, CreateEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "openDocument", nullptr, OpenDocument, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "attachXComponent", nullptr, AttachXComponent, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "resize", nullptr, Resize, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "saveCheckpoint", nullptr, SaveCheckpoint, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "requestPreviewRender", nullptr, RequestPreviewRender, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "exportSceneSnapshot", nullptr, ExportSceneSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "readPdfPageCount", nullptr, ReadPdfPageCount, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setActivePage", nullptr, SetActivePage, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "insertPage", nullptr, InsertPage, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deletePage", nullptr, DeletePage, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setTool", nullptr, SetTool, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setFingerWritingEnabled", nullptr, SetFingerWritingEnabled, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "injectSimulatorFingerEvent", nullptr, InjectSimulatorFingerEvent, nullptr, nullptr, nullptr,
            napi_default, nullptr },
        { "setBackend", nullptr, SetBackend, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setDocumentMode", nullptr, SetDocumentMode, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setBrushColor", nullptr, SetBrushColor, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setBrushWidth", nullptr, SetBrushWidth, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "undo", nullptr, Undo, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "redo", nullptr, Redo, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startInputTraceRecording", nullptr, StartInputTraceRecording, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopInputTraceRecording", nullptr, StopInputTraceRecording, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "replayInputTrace", nullptr, ReplayInputTrace, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "disposeDocument", nullptr, DisposeDocument, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "disposeEngine", nullptr, DisposeEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getDebugState", nullptr, GetDebugState, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    GetNoteEngineRuntime().RegisterBridgeExports(env, exports);
    return exports;
}

EXTERN_C_END

static napi_module entryModule = {
    1,
    0,
    nullptr,
    Init,
    "entry",
    nullptr,
    { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&entryModule);
}
