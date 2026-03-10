# Native Note 真机验收矩阵

本矩阵只整理真机验收范围、观测点和入口，不修改任何核心实现。

状态：`blocked-by-device`
当前活跃测试线程已切到模拟器 smoke 回归。本矩阵继续保留，等真实设备线程恢复后再继续执行。

## 观测入口

- 编辑页右侧 native debug 文本：
  - `pressure=...`
  - `tilt=..., ...`
  - `roll=...`
  - `stylus=... finger=... palm=...`
  - `history=... predict=...`
  - `tool=... native=...`
- 首页卡片：
  - `Preview ready / Preview fallback / Preview error`
  - 缩略图 `raster -> vector -> fallback` 路径
  - `previewSummary` 摘要和搜索结果

## 覆盖矩阵

| 用例 ID | 范围 | 文档模式 | 设备要求 | 主要观测点 | 结果判定 |
| --- | --- | --- | --- | --- | --- |
| D-INK-01 | 压感轻压/重压 | paged | 真机 + 压感笔 | 笔迹宽度差异，`pressure` 数值变化 | 重压宽于轻压，数值随压力变化 |
| D-INK-02 | tilt/roll 侧锋 | paged | 真机 + 支持 tilt/roll 的笔 | `tilt`/`roll` 变化，铅笔侧锋宽扁效果 | 侧锋变宽，roll 旋转可改变笔锋朝向 |
| D-INK-03 | 双击切笔 | paged | 真机 + 支持笔身双击按键 | `tool=... native=...`、橡皮/墨水切换 | 双击 350ms 窗口内能在橡皮和最近墨水笔之间切换 |
| D-INK-04 | palm rejection | paged | 真机 + 手写笔 | `palm=` 计数、误触是否落墨 | 手掌或第二指触碰不应留下新墨迹 |
| D-INK-05 | prediction 急转弯 | paged | 真机 + 手写笔 | `predict=` 尾巴长度、拐角回滚 | 急转弯时预测尾巴能收敛，不出现明显越界尖刺 |
| D-INK-06 | prediction 高速短抖动 | paged | 真机 + 手写笔 | `predict=`、笔迹尾巴稳定性 | 高速短抖动时尾巴不长期残留、不出现重复折返 |
| D-DOC-01 | paged 重开不跑位 | paged | 真机 | page-0 稳定、scene/preview 边界 | 重开后 page-0 和内容边界稳定 |
| D-DOC-02 | infinite 重开不跑位 | infinite | 真机 | world-space 边界、网格相对位置 | 重开后无限画布内容与网格不漂移 |
| D-LAYER-01 | PDF/HYBRID placeholder 底图层级 | paged / infinite | 真机 | PDF 在 ink 下层 | placeholder 或 PDF fragment 始终在 ink 下层 |
| D-HOME-01 | 首页 preview 卡片显示与 fallback | 首页 | 真机 | badge、raster/vector/fallback | raster 优先，其次 vector，异常时不影响摘要/列表 |

## B 线程回归入口

| 回归点 | 用例包 | 预期 |
| --- | --- | --- |
| `preview.json` 缺失 | `fixtures/native-note/preview-store-regression/missing` | 卡片走 fallback，不拖垮首页加载 |
| `preview.json` 损坏 | `fixtures/native-note/preview-store-regression/corrupt` | 卡片走 fallback，不影响 `previewSummary` 搜索 |
| `preview.json` 旧格式 | `fixtures/native-note/preview-store-regression/legacy-summary-only` | 旧字段仍可被兼容，卡片至少显示 vector fallback |
| `preview.json` richer payload | `fixtures/native-note/preview-store-regression/richer-payload` | raster 优先展示，badge/summary 正常 |
| 首页 raster/vector fallback | 同上四类 case | 卡片分支与 payload 状态一致 |
| `previewSummary` 搜索不退化 | 任一 preview 异常 case | 搜索仍只依赖数据库中的 `previewSummary` |
| assembleHap smoke 准备 | `scripts/check-assemble-hap-smoke-prereqs.mjs` | 先检查环境、日志和目标产物路径，再交给 B 集成跑构建 |

## A 线程预备入口

| 项目 | 产物 | 说明 |
| --- | --- | --- |
| 目录结构 | `fixtures/native-note/replay-scenarios` | 只锁目录和命名，不锁最终 trace 字段 |
| 命名规则 | `docs/native-note-replay-prep.md` | 用例 ID、目录名、产物名约定 |
| 校验脚本骨架 | `scripts/validate-replay-scenario-layout.mjs` | 只检查布局、命名和必备文件 |
| 录制 -> 回放 -> 比对模板 | `fixtures/native-note/replay-scenarios/scenarios/template-basic` | 留待 A 线程接入真实 trace |
