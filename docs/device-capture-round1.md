# Device Capture Round 1

Date: 2026-03-08
Status: `blocked-by-device`

This round reserves the five required real-device trace cases and records the first execution attempt.
No core implementation files were changed.

## Environment Check

- ArkTS trace controls are already present in [EditorWorkspace.ets](/C:/Users/lasrorder/hw/MyApplication/entry/src/main/ets/pages/EditorWorkspace.ets).
- `assembleHap` succeeded on 2026-03-08, so the current branch is buildable for device deployment.
- `hdc list targets` returned `[Empty]` on 2026-03-08.
- No exported raw trace files were found in `Desktop`, `Documents`, `Downloads`, or the workspace for the five required case names.

## Round 1 Case Index

| Trace | Case Folder | Recording | Replay | Saved Result | Recording vs Replay |
| --- | --- | --- | --- | --- | --- |
| `pen_pressure_light_to_heavy` | `fixtures/native-note/replay-scenarios/scenarios/pen-pressure-light-to-heavy` | Blocked by device | Blocked by device | None | Cannot judge |
| `pencil_tilt_shading` | `fixtures/native-note/replay-scenarios/scenarios/pencil-tilt-shading` | Blocked by device | Blocked by device | None | Cannot judge |
| `double_tap_pen_eraser` | `fixtures/native-note/replay-scenarios/scenarios/double-tap-pen-eraser` | Blocked by device | Blocked by device | None | Cannot judge |
| `palm_rejection_with_finger_contact` | `fixtures/native-note/replay-scenarios/scenarios/palm-rejection-with-finger-contact` | Blocked by device | Blocked by device | None | Cannot judge |
| `prediction_fast_zigzag` | `fixtures/native-note/replay-scenarios/scenarios/prediction-fast-zigzag` | Blocked by device | Blocked by device | None | Cannot judge |

## Blockers Observed

1. The active test thread has moved to simulator smoke regression, so real-device capture is intentionally paused.
2. The five round1 cases remain preserved in-place and will resume only when the device thread is re-opened.

## Ready-For-Capture State

- Round 1 case index: [round1-index.json](/C:/Users/lasrorder/hw/MyApplication/fixtures/native-note/replay-scenarios/round1-index.json)
- Replay fixture roots:
  - [pen-pressure-light-to-heavy](/C:/Users/lasrorder/hw/MyApplication/fixtures/native-note/replay-scenarios/scenarios/pen-pressure-light-to-heavy)
  - [pencil-tilt-shading](/C:/Users/lasrorder/hw/MyApplication/fixtures/native-note/replay-scenarios/scenarios/pencil-tilt-shading)
  - [double-tap-pen-eraser](/C:/Users/lasrorder/hw/MyApplication/fixtures/native-note/replay-scenarios/scenarios/double-tap-pen-eraser)
  - [palm-rejection-with-finger-contact](/C:/Users/lasrorder/hw/MyApplication/fixtures/native-note/replay-scenarios/scenarios/palm-rejection-with-finger-contact)
  - [prediction-fast-zigzag](/C:/Users/lasrorder/hw/MyApplication/fixtures/native-note/replay-scenarios/scenarios/prediction-fast-zigzag)

Each case folder already has:

- a `case.json` entry with open trace schema
- a `recordings/` drop location for the raw device export
- an `expected/` location for replay scene, preview, and telemetry outputs
- a `compare/README.md` checklist for the first comparison pass

## Exit Status

Round 1 is preserved but blocked by device.
Recording, replay, and recording-vs-replay comparison remain pending until the real-device thread is explicitly resumed.
