# Thread Work Automation

This project provides a Windows PowerShell automation script that opens one target thread, waits 5 seconds, and then sends the configured command. When an executor thread is supplied, the script appends `<executor> finish` to the message.

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

With the example above, the script clicks thread `H` and sends:

```text
work run, A finish
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
- report only success or failure of that execution

## Config

- `TargetThreadName`: default target thread, for example `H`.
- `ExecutorThreadName`: optional executor/source thread name. If set to `A`, the final message becomes `work run, A finish`.
- `WindowTitleRegex`: optional regex used to limit the search to one top-level window.
- `Message`: text to send after opening the thread.

## Notes

- The script uses Windows UI Automation first and falls back to a direct click at the element center.
- After opening the thread, it tries to locate the most likely input control near the bottom of the active window.
- If the target thread cannot be found, the script exits with an error.
