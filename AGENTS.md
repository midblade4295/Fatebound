# Fatebound agent instructions

Read `GROKBOT_HANDOFF.md` and `fatebound-source.json` before changing the game.

The user-approved baseline is HTML v108 (`108-season-pass-modal-copy-fix`), imported exactly as `fatebound.html` on `main`. Use current `origin/main`, not an older Grok branch, an archived restore payload, a v94–v107 attachment, or a stripped debug page. The v108 source is 36,175,422 bytes and SHA-256 `91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8`.

Fetch first, inspect the working tree, and create a fresh task-specific branch. Preserve local work; no force-push or hard reset. Do not edit the same branch concurrently with another agent. Do not blindly resolve the large HTML's conflicts by replacing the whole file from an old branch.

Preserve the idempotent DOM-observer fix, hidden-Home layout, one-active-screen navigation, five-minute battle navigation lock, four spells, full embedded assets, training, and Season Pass layering/copy. Do not add global input-swallowing gates, history-lock loops or save-reset migrations as a routine repair. Keep save key `fatebound-save` and battle-session compatibility 106 unless an explicitly required, tested migration is approved.

After authorized code edits, update the source manifest/checksum to the newly tested source in the same commit; retain the immutable v108 hash in the historical handoff/report. Test actual touch interactions through menus, pass rewards, battle start/completion/reward claim and a second battle. Syntax parsing alone is insufficient; distinguish tests actually run from prior reports and disclose device/network limits.

`fatebound.html` is the only editable game source. The Android asset is copied from it by the existing build workflow. HTML build numbers and Android versionCodes are separate. Do not reuse consumed Play versionCodes or replace the upload key. Do not publish a Play release or change the Legionary game/deployment unless explicitly requested.

`SOURCE-RESTORE.md` and `patches/` contain historical operations. Do not rerun restore/apply workflows to roll back the current source. The branch-restricted v108 import workflow is a one-time transport mechanism, not a feature-development workflow.
