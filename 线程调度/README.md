# Thread Work Automation

This project provides a Windows PowerShell automation script that wakes a Codex thread by clicking a fixed composer coordinate and then sending the configured command. When an executor thread is supplied, the script appends `<executor> finish` to the message.

## Run

Use the thread name from the config:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-thread-work.ps1
```

Override the target thread directly from the command line:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-thread-work.ps1 -ThreadName "A"
```

Specify both the target thread and the executor thread:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-thread-work.ps1 -ThreadName "H" -ExecutorThreadName "A"
```

Use the stable logical thread prefix such as `B`, not a volatile visible label:

```powershell
& 'C:\Users\lasrorder\hw\MyApplication\run-thread-work.ps1' -ThreadName 'B' -ExecutorThreadName 'H' -WindowTitleRegex '^Codex$'
```

With the example above, the script clicks the configured composer coordinate for thread `B` and sends:

```text
work run, H finish
```

## Agent Behavior

Thread agents should execute the wake-up command themselves after writing task or result files.

They should not stop at:
- printing a PowerShell command for the user
- asking the user to manually switch threads
- waiting for a human to trigger the already-known wake-up step

They should instead:
- request desktop-automation permission if the environment requires it
- run `run-thread-work.ps1` directly
- check the child process `ExitCode`
- inspect `tmp/thread-work-last.log` when the wake-up script fails
- report only success or failure of that execution

## Config

- `TargetThreadName`: default target thread, for example `H`.
- `ExecutorThreadName`: optional executor/source thread name. If set to `A`, the final message becomes `work run, A finish`.
- `Message`: text to send after opening the thread.
- `ThreadTargets`: optional per-thread coordinate map. Each entry can define absolute `X` / `Y` pixels, normalized full-screen `XRatio` / `YRatio`, or a window rectangle via `LeftRatio` / `TopRatio` / `WidthRatio` / `HeightRatio`. Rectangle entries can also override `ComposerXRatio` / `ComposerYRatio` per thread.
- `ComposerClickXRatio`: click position inside the target window rectangle on the X axis. Default `0.470`.
- `ComposerClickYRatio`: click position inside the target window rectangle on the Y axis. Default `0.800`.
- `WindowTitleRegex`: kept only for backward-compatible callers and ignored in fixed-coordinate mode.
- `SelectionAttempts`: kept only for backward-compatible callers and ignored in fixed-coordinate mode.
- `SelectionTimeoutMs`: kept only for backward-compatible callers and ignored in fixed-coordinate mode.

Example `thread-work.config.json` override:

```json
{
  "ThreadTargets": {
    "H": { "LeftRatio": 0.0, "TopRatio": 0.0, "WidthRatio": 0.5, "HeightRatio": 0.5, "ComposerYRatio": 0.8 },
    "A": { "LeftRatio": 0.5, "TopRatio": 0.0, "WidthRatio": 0.5, "HeightRatio": 0.5, "ComposerYRatio": 0.8 },
    "B": { "LeftRatio": 0.0, "TopRatio": 0.5, "WidthRatio": 0.5, "HeightRatio": 0.5, "ComposerYRatio": 0.84 },
    "T": { "LeftRatio": 0.5, "TopRatio": 0.5, "WidthRatio": 0.5, "HeightRatio": 0.5, "ComposerYRatio": 0.84 },
    "Test": { "LeftRatio": 0.5, "TopRatio": 0.5, "WidthRatio": 0.5, "HeightRatio": 0.5, "ComposerYRatio": 0.84 }
  }
}
```

## Notes

- The default built-in layout assumes a fixed 2x2 Codex window grid: `H` = top-left, `A` = top-right, `B` = bottom-left, `T/Test` = bottom-right.
- The actual click point is resolved from the target window rectangle plus `ComposerClickXRatio` / `ComposerClickYRatio`, and each thread can override those ratios when one window needs a different height than the others.
- Pass stable logical names such as `A`, `B`, `H`, and `Test`. The script no longer reads visible sidebar labels.
- If your window layout changes, override `ThreadTargets` in `thread-work.config.json` instead of editing the script.
- The script allows only one active wake-up run at a time so repeated retries do not overlap UI automation against the same Codex desktop layout.
- It writes step-by-step diagnostics to `tmp/thread-work-last.log`.
- If the target thread has no configured coordinate, the script exits with an error.
