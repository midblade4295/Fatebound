# Fatebound v112 — mobile audio unlock fix

Build: 112-audio-unlock-fix
Parent: 8775923de515caad77a8cdb803aa26868d171226 (v111 UI/audio rollout)

## Reproduced root cause

v111 created/resumed Web Audio during the first gesture, but AudioContext.resume() is asynchronous on mobile browsers. A preview/game cue requested before the state had changed to running was immediately rejected by play(). Desktop Chromium usually resumes quickly enough that the existing preview test passed, masking the Android failure.

The engine also tried only AudioContext with latencyHint; a WebView that rejects constructor options failed silently because initialization errors were swallowed.

## Fix

- First requested cue is held for at most 1.2 seconds while Web Audio unlocks, then flushed when the context reaches running.
- Pending cues are bounded/coalesced and cleared on background/page exit.
- Plain AudioContext() is a fallback when latency-hint options are rejected.
- A one-frame silent priming buffer is started during the gesture.
- Pointer, touch, mouse and keyboard gestures all attempt the same single-context unlock.
- Unmuting and raising volume can re-attempt unlock.
- Sound Studio displays audio-ready/error feedback and gives visible sample-button feedback.
- The first preview click uses the same queue/resume path as gameplay sounds.
- Existing 41 PCM cues, mixer levels, balance110, matchmaking, saves and UI layout are unchanged.

## Tests actually run on the VM

- 44 Node tests passed. New regressions simulate a 30 ms delayed AudioContext.resume() and a browser that rejects constructor options.
- 9 Python web-host tests passed.
- All current inline modules synchronize into the full HTML.
- The full Playwright UI suite could not be rerun on this VM because Playwright/Chromium is not installed. This is not counted as a pass.
- Physical Android audio output must be verified after deployment.

No server restart, save migration, Caddy change, Legionary change, Android build or Play publication is part of this patch.

## Live deployment

The exact v112 HTML was installed atomically at 2026-09-25T15:29:43Z from commit 2a88e04538ab3d21e59f2430a747f6018529fd51. Public HTTP returned 200 and the served bytes matched the audited source plus the existing save-client injection. Arena/web processes were not restarted; balance110, 20-second queue and 20-player capacity remained active. No Caddy, Legionary, save migration, Android or Play change. Physical Android listening is the remaining verification for device audio output.
