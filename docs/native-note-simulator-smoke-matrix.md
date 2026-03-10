# Native Note 模拟器 Smoke 矩阵

当前活跃测试线程：`simulator-smoke`

## 覆盖范围

| 用例 ID | 范围 | 入口 | 主要观测点 | 当前状态 |
| --- | --- | --- | --- | --- |
| SIM-INSTALL-01 | HAP 安装与启动 | `hdc install` / `aa start` | HAP 可安装，应用可被 Ability Manager 拉起 | passed via `entry-simulator-unsigned.hap`; `entry-default-unsigned.hap` failed ABI mismatch |
| SIM-HOME-01 | 首页文档流 | 首页 | 种子文档、CRUD、收藏、标签、回收站、预览卡片、搜索、打开文档 | failed (`Failed to open the local library.`) |
| SIM-EDITOR-01 | 编辑器基础流 | 编辑页 | source/preview 切换、Markdown 编辑、保存、返回首页、preview merge 不崩 | blocked by SIM-HOME-01 |
| SIM-STUB-01 | simulator-stub 弱 native 行为 | 编辑页 native 区域 | banner 显示、trace 按钮禁用、runtimeProfile/stubReason/capability 文本 | blocked by SIM-HOME-01 |
| SIM-X86-01 | x86_64 placeholder fixture | `fixtures/native-note/simulator-preview` / `fixtures/native-note/simulator-scene` | 若 A 提供占位输出则可解析、可归档、可断言；否则跳过 | skipped-no-x86-placeholder |

## 固定观测入口

- 模拟器验收 HAP：`entry/build/simulator/outputs/simulator/entry-simulator-unsigned.hap`
- 对照 HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- 模拟器前置检查：`scripts/check-simulator-smoke-prereqs.mjs`
- 可选 x86_64 fixture 校验：`scripts/validate-simulator-placeholder-fixtures.mjs`
- 模拟器 case 索引：`fixtures/native-note/simulator-smoke/index.json`
- 首页布局抓取：`tmp/myapp-layout-v2.json`
- 首页截图：`tmp/myapp-home-v2.png`

## 当前执行结论

- `entry-simulator-unsigned.hap` 已安装并成功拉起 `EntryAbility`。
- `entry-default-unsigned.hap` 不能作为当前 `x86_64` 官方模拟器的验收产物，安装会报 ABI mismatch。
- 首页已通过 `uitest dumpLayout` 与截图确认失败，错误文本为 `Failed to open the local library.`。
- 编辑器与 simulator-stub 验证不是单独失败，而是被首页库初始化失败阻塞。
