# Native Note 模拟器 Smoke 手测脚本

## 执行顺序

1. `SIM-STUB-01`
2. `SIM-HOME-01`
3. `SIM-EDITOR-01`
4. `SIM-X86-01`

执行约束

- `SIM-STUB-01` 是首个验收 gate。优先确认 `runtimeProfile=simulator-stub`、banner、capability 和 trace disabled 状态，再继续首页和编辑器流程。
- 如果安装启动正常、`getDebugState()` 正确、stub banner/capability 已对，则后续页面展示和交互异常默认先归 B 线程，不先打到 A 线程。
- `SIM-X86-01` 是非阻塞项；若仍缺 placeholder，结果记为 `skipped-no-x86-placeholder`。

## SIM-STUB-01 simulator-stub 弱 native 行为

前置条件

- 官方模拟器 target 在线。
- 当前 `entry-simulator-unsigned.hap` 已成功安装并可启动。
- 如首页可进入任意文档，先打开编辑页；如首页上游故障导致编辑页不可达，记为 `blocked`，再转做 `SIM-HOME-01`。

操作步骤

1. 观察编辑页 native 区域顶部 banner。
2. 观察 placeholder surface 文案和 debug 文本。
3. 长按 native 区域标题，打开 trace 面板。
4. 观察 `Start Trace`、`Stop Trace`、`Replay Last Trace` 三个按钮状态。

预期结果

- banner 明确提示当前为 simulator smoke mode / weak native shell。
- debug 文本中存在 `runtimeProfile=simulator-stub`、`stubReason=` 和 capability 信息。
- trace 面板可以打开，但三个 trace 按钮全部为禁用态，并明确提示 trace 在 simulator smoke mode 下是 unsupported。
- 长按打开面板不会触发录制，也不会导致页面崩溃。

失败现象

- 未显示 simulator-stub banner 或 debug 状态缺失。
- `runtimeProfile`、`stubReason` 或 capability 文本为空。
- trace 按钮在模拟器下仍可点击触发，或面板没有明确的 unsupported 提示。
- 长按 native 区域导致崩溃、卡死或误触发 trace。

## SIM-HOME-01 首页文档流

前置条件

- 官方模拟器 target 在线。
- 当前 HAP 已成功安装并可启动。
- 应用已进入首页。

操作步骤

1. 观察首页是否出现种子文档卡片。
2. 新建一份文档并确认卡片出现在列表中。
3. 对新文档执行重命名、收藏、添加标签。
4. 将文档移入回收站，再从回收站恢复。
5. 使用标题、标签、文件夹和摘要关键字进行搜索。
6. 点击 `Open` 进入编辑页。

预期结果

- 首页列表正常显示，预览卡片 badge、摘要和按钮可见。
- CRUD、收藏、标签、回收站和搜索路径均不崩溃。
- 搜索结果继续依赖 `previewSummary`，不会因 preview fallback 退化。
- 点击 `Open` 后能进入编辑页。

失败现象

- 首页白屏、崩溃或文档列表为空。
- 创建、重命名、收藏、标签、回收站任一路径报错或卡死。
- 搜索无法命中标题、标签、文件夹或摘要。
- 点击 `Open` 无法进入编辑页。

## SIM-EDITOR-01 编辑器基础流

前置条件

- 应用已从首页打开一份文档。
- `SIM-STUB-01` 已完成或明确记录为阻塞。
- 编辑页正常显示工具栏和 Markdown 区域。

操作步骤

1. 在 `Preview` 和 `Source` 两种模式间来回切换。
2. 在 `Source` 模式修改 Markdown 文本。
3. 点击 `Save`。
4. 点击 `Back to library` 返回首页。
5. 再次打开同一文档。

预期结果

- source/preview 模式切换顺畅。
- Markdown 编辑后可保存并持久化。
- 返回首页不崩溃，再次打开后能看到保存后的内容。
- `saveDocument -> syncNativePreviewSnapshot -> mergeNativePreviewSnapshot` 在模拟器下不崩。

失败现象

- source/preview 切换卡死或内容区域空白。
- 保存时报错、闪退或返回首页后内容丢失。
- 再次打开文档时 Markdown 回退到旧内容。
- 保存后首页卡片或预览摘要异常崩溃。

## SIM-X86-01 x86_64 placeholder 资产

前置条件

- A 线程已提交或说明当前轮次的 `x86_64` placeholder scene/preview 资产状态。

操作步骤

1. 检查 `fixtures/native-note/simulator-preview/` 是否存在 `x86_64` placeholder 输出。
2. 检查 `fixtures/native-note/simulator-scene/` 是否存在 `x86_64` placeholder 输出。
3. 如资产存在，运行对应校验并记录结果；如不存在，直接记状态。

预期结果

- 已提供 placeholder 时，校验通过并可用于后续 smoke 对照。
- 未提供 placeholder 时，状态明确记为 `skipped-no-x86-placeholder`，不阻塞本轮放行。

失败现象

- 目录存在但资产内容不完整或校验失败。
- 资产与脚本契约不一致，无法稳定作为对照输入。
