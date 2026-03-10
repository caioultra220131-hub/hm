# Native Note B 线程回归准备

本文件聚焦 B 线程当前可直接接入的回归材料，不修改运行时代码。

## 回归包

- `fixtures/native-note/preview-store-regression/missing`
- `fixtures/native-note/preview-store-regression/corrupt`
- `fixtures/native-note/preview-store-regression/legacy-summary-only`
- `fixtures/native-note/preview-store-regression/richer-payload`

## 回归点与预期

| 回归点 | 用例包 | 关注代码路径 | 预期 |
| --- | --- | --- | --- |
| `preview.json` 缺失 | `missing` | `readPreviewPayloadText -> normalizeRequestPreviewRenderPayload(undefined)` | 首页不崩，卡片走 fallback |
| `preview.json` 损坏 | `corrupt` | `readPreviewPayloadText -> JSON 读取失败 -> 空串 fallback` | 首页不崩，卡片走 fallback |
| `preview.json` 旧格式 | `legacy-summary-only` | `PreviewAdapterService` 兼容旧字段 | 卡片至少能走 vector fallback，badge 不异常 |
| `preview.json` richer payload | `richer-payload` | `PreviewAdapterService` 读取 `raster/layout/pageContract/extension` | 首页优先走 raster，summary 和 badge 正常 |
| 首页 raster/vector fallback | 全部 case | `PreviewThumbnail` | 优先 raster，其次 vector，最后 summary/fallback |
| `previewSummary` 搜索不退化 | 全部 case | `DocumentLibraryService.listDocuments` | 搜索仍只依赖数据库中的 `previewSummary` |

## 轻量命令

先校验预览回归包：

```bash
node ./scripts/validate-preview-store-regression.mjs
```

再检查 assembleHap smoke 前置条件：

```bash
node ./scripts/check-assemble-hap-smoke-prereqs.mjs
```

## assembleHap smoke 准备

只做准备，不在这里触发正式集成构建。

准备项：

1. 确认 `DEVECO_SDK_HOME` 和 `JAVA_HOME` 已设置且路径有效。
2. 确认根工程和 `entry` 模块的 `hvigorfile.ts` 与 `build-profile.json5` 存在。
3. 确认 simulator smoke 目标产物路径为 `entry/build/simulator/outputs/simulator/entry-simulator-unsigned.hap`。
4. 检查 `.hvigor/outputs/build-logs/build.log` 的最近一次结果。

备注：

- 当前工程日志里已经出现过 `Invalid value of 'DEVECO_SDK_HOME'` 的失败记录。
- `entry-default-unsigned.hap` 是 device/arm64 产物，在当前 x86_64 模拟器上会因为 ABI mismatch 安装失败。
- B 线程 simulator smoke 应以 `:entry:simulator@...` 任务链和 `entry-simulator-unsigned.hap` 作为产物位置基线。
