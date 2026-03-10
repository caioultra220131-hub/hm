# Native Note A 线程回放预备

当前阶段只准备目录、命名和脚本骨架，不锁死最终 trace 字段。

## 目录结构

```text
fixtures/native-note/replay-scenarios/
  scenarios/
    <case-folder>/
      case.json
      recordings/
      expected/
      compare/
```

## 命名规则

- `case-folder` 使用小写 kebab-case。
- `case.json.caseId` 使用稳定 ID，例如 `replay.pressure.paged.pen`。
- `recordings/` 只锁目录，不锁文件名和 trace 后缀。
- `expected/` 先固定三类产物名：
  - `expected.preview.*`
  - `expected.scene.*`
  - `expected.telemetry.*`

## 当前不锁的内容

- trace 文件扩展名
- trace 行格式
- trace 事件字段
- pressure / tilt / roll / prediction / palm 的最终对比字段

## 当前先锁的内容

- 用例目录位置
- `case.json` 元数据入口
- `recordings / expected / compare` 三段式流程
- 预期产物分离：
  - preview snapshot
  - scene snapshot
  - debug telemetry

## 校验命令

```bash
node ./scripts/validate-replay-scenario-layout.mjs
```

## 录制 -> 回放 -> 比对模板

模板目录：

- `fixtures/native-note/replay-scenarios/scenarios/template-basic`

建议流程：

1. A 线程把原始 trace 丢到 `recordings/`。
2. 回放后导出 `scene snapshot`。
3. 回放后导出归一化 `preview snapshot`。
4. 回放后导出 `native debug telemetry`。
5. 在 `compare/` 中记录比对规则和偏差。

## 第二阶段切换条件

等 A 线程完成真实输入录制/回放后，再切到第二阶段：

1. trace schema 校验
2. 真机录制 -> 软件回放
3. pressure / double-tap / palm rejection / prediction 回归
4. native debug telemetry 对比

