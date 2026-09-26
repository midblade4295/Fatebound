# Conversion coverage and boundaries

| Source feature | Native implementation | Verification |
|---|---|---|
| Source tables / starting save | content.gd, v114-content.json | Extracted from pinned HTML SHA; schema normalization tests |
| Wallet/Fate/login/levels | progression.gd, progress_store.gd | Daily overflow/cap, level rewards, atomic rollback/reload |
| Hero/gear/forging/relics | progression.gd + pages.gd | Exact costs, locks, perks, actual buy/forge controls |
| Season/quests | progression.gd + pages.gd | Claim dedup, imported numeric IDs, old-season receipt test |
| Persistent loot/gifts | progression.gd + solo_campaign.gd | Chest carry/claim, ×3/jackpot, card choice, partial returns |
| Training | training.gd | All33 native lesson actions; permanent save unchanged |
| Solo Company40 | solo_campaign.gd | Five complete class-varied simulated matches and mid-match restore |
| Equalized arena practice20 | arena_local.gd | All216 roll outcomes +3 full seeded matches compared with JS |
| Daily boss raid21 | raid.gd | Start/attempt guard, armor/parry, kill rewards, end/no-repay |
| Guild Company/WarRoom | pages.gd | Native caret insertion/preservation, saved local send/navigation |
| Real online guild | pages.gd + game_api.gd | Create/route/claim/history/leave through local server |
| Online battle | main.gd/full_client.gd + game_api.gd | Existing authoritative server; public full-client report separately |
| Legacy solo migration | legacy_import.gd | Compatible active snapshot HP/Focus/tower/control/reward preservation |
| Save files/cloud | progress_store.gd + game_api.gd | Export/parser/invalid payload, private local cloud roundtrip |
| Native menus/layout | pages.gd/full_client.gd | 72 menu/window combinations +6 battle sizes; visible text checks |
| Artwork/audio | battlefield.gd/dice_strip.gd/native_audio.gd | Original pixel/cue provenance; actual Godot renderer screenshots |

## Not asserted

- Pixel-identical browser CSS or JavaScript random-sort ordering.
- Fully skinned 3D character/environment conversion.
- Automatic transfer of a different browser/Android package's private bearer token.
- A newly networked version of the original device-local company chat/daily boss.
- Physical Android or speaker playback, carrier metering, device thermal/load data.
- A production account/security overhaul or a Google Play release.

The source's final-push rewards, tiers, quest requirements and disabled purchases
are retained. Native UI presentation and input timing are documented in README.
A full set of accessible native systems is not a promise that every possible
save, phone, network failure or combat state has been exhaustively tested.
