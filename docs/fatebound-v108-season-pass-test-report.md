# Fatebound v108 — Season Pass fix and runtime tests

Build: `108-season-pass-modal-copy-fix`  
Base: `fatebound-v107-tested-ui-fix.html`  
Output: `fatebound-v108-season-pass-fix.html`  
SHA-256: `91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8`

## Reproduced defect

On the full v107 HTML in Chromium, Home had computed z-index **8**, while the
Season Pass overlay had z-index **5**. At several points inside the visible pass,
`elementFromPoint()` returned an element inside Home instead. The baseline
screenshot reproduced the user's pass-behind-Home report.

## Changes

The pass alone now has an explicit modal layer above game/menu content.
Its reward list and expandable guide scroll within the panel; Close and Premium
remain in a fixed footer. The existing level-up overlay remains above the pass,
so Premium hero-level rewards can be collected before returning to the pass.

Reward labels show **Fate**, **raid tokens**, stored chests and equipped-weapon
shards rather than exposing legacy storage key names. The internal `energy` key,
balances, reward amounts, Premium price and grant functions remain unchanged.

The guide describes the rules present in v107:
- Five Focus-spending rolls are required for eligible completed-battle rewards;
  victory gives 10 Season Points and defeat gives 5.
- Champion and Charger can add 5 and 3 points respectively.
- A completed daily quest grants 3 points. Raid contribution can award 1, 1, 1
  and 2 points across the four boss milestones.
- Fate is persistent currency, not battle Focus or spell charges. Wars/raids
  have no Fate entry cost.
- Premium costs 180 raid tokens for the current season and adds its track at
  already-reached tiers. It does not consume Season Points or skip tiers.
- Ten tiers end at 1,000 points. Season Points, claim records and Premium access
  reset with the season; already collected rewards are retained.

The heading now shows progress to the next tier, an accurate overall tier count,
remaining season time and the number of available claims. Claim refreshes preserve
scroll position. The two Close controls and Escape return focus to the opener.
Keyboard containment is attached only to the pass element; there is no new
document-wide input gate, MutationObserver, polling repair or save migration.

## Runtime results

22 checks passed. These run against the full HTML, not a stripped mock.

| Check | Result | Evidence |
| --- | --- | --- |
| Modal layering | PASS | Reproduced v107 Home z-index 8 over pass z-index 5; v108 pass z-index 400 receives all 15 viewport hit tests. |
| Rules guide and touch scrolling | PASS | Guide expands; emulated touch swipe moves pass scroller to 255px; footer remains visible. |
| Last tier reachable | PASS | Tier 10 can be scrolled into view; Close and Premium remain anchored on screen. |
| Close restores active menu | PASS | Opening and closing from Home/Guild preserves the underlying screen and never creates a split-screen layout. |
| Fate reward and duplicate protection | PASS | +20 Fate claimed through touch; Focus and Season Points unchanged; a repeated stale claim event gives no second reward. |
| Insufficient Premium currency | PASS | Shows an inline missing-token message; no tokens spent and Free track remains available. |
| Premium activation | PASS | One touch spends exactly 180 raid tokens; repeated old-button event does not spend again, and Season Points stay at 300. |
| Retroactive Premium reward | PASS | Premium tier 1 adds +100 Fate and +300 gold while retaining the previously collected Free reward. |
| Token/shard rewards | PASS | Premium tier 2 adds 15 raid tokens and 10 steel shards, matching the equipped weapon. |
| Level-up from Premium | PASS | Level reward opens above the pass, +1 hero level and its +3 Fate collect correctly, then the pass remains usable. |
| Last-tier rewards and scroll retention | PASS | Free tier 10 adds 3 stored chests and 10 equipped-weapon shards; Season Points remain 1,000 and the pass stays near the claimed row. |
| Weapon/title rewards | PASS | Premium tier 4 grants the existing weapon and title without changing the pass reward definitions. |
| Six viewport layouts | PASS | Modal, Premium and Close fit at 360×640, 393×744, 412×915, 768×1024, 1280×800 and 640×360; scroller stays usable, no horizontal/document overflow. |
| Keyboard/accessibility | PASS | Dialog is labelled; Tab wraps locally; Escape closes and returns focus to the opener. No document-wide capture gate added. |
| Pass over all menus | PASS | Opened and closed over Shop, Hero, Guild, Friends and Home; each keeps exactly its own active screen. |
| Home animation after modal activity | PASS | Canvas portrait still changes frames after reward claims and repeated open/close/menu switches. |
| Save compatibility across document reload | PASS | Premium access, collected rewards, points, hero level and balances persist; session format stays at 106, no new migration/reset. |
| Battle start and menu lock | PASS | Battle opens after pass activity; Home navigation remains hidden, and Season Pass cannot open during a live match. |
| Five complete battle rolls | PASS | Five touch-triggered throws settle, apply damage and increment Focus-spending roll count after using the pass. |
| Spell and map regression | PASS | Barrage applies damage; Map opens, its header scrolls to a tower, and tapping the map tower returns to battle. |
| Battle reward claim then pass | PASS | Results progress through the existing highlights stage to Claim & Home; expected Season Points arrive once and menus/pass work afterward. |
| Second battle | PASS | A second live battle starts after completion, reward collection, pass open/close and menu use. |

## Source preservation

- season thresholds and reward definitions: unchanged / verified.
- reward-granting logic: unchanged / verified.
- all other inline JavaScript blocks: unchanged / verified.
- battle session compatibility 106: unchanged / verified.
- all 103 large embedded asset blocks: unchanged / verified.

18 inline JavaScript blocks passed Node parsing. Only the main script
block containing the pass helpers/rendering changed; all other script blocks,
including the working observer fix, are byte-for-byte identical to v107.

The only other edits are the build marker, pass dialog accessibility attributes,
the level-up reward's visible Fate label and pass-scoped layout CSS.
No new assets or fonts were bundled.

## Test environment and limits

Tests ran in installed desktop Chromium with Playwright mobile/touch emulation,
not on a physical Android phone. Viewports checked: 360×640, 393×744, 412×915,
768×1024, 1280×800 and 640×360.

The container prohibits navigation to external/local origins. The full supplied
HTML was executed in an isolated document with an in-memory localStorage test
adapter. A second document restored the test save to check persistence. This
does not modify or access the user's real save. External font/network requests
were blocked; online account or multiplayer services were not tested.

Points and tokens were staged only in the browser test fixture to exercise
locked, unlocked and Premium tiers. Dice faces were deterministic for the five
battle rolls, and match deadlines were advanced for completion testing. None
of these fixtures, balances, deterministic odds or deadline overrides appear in
the delivered HTML.

The regression harness initially selected map-header buttons (which scroll to
towers) instead of map tower hit regions, and attempted Claim before the
existing result sequence reached its reward stage. The completed checks used
a real touch on the map tower and the visible Continue/Claim controls. No game
code was changed to bypass either existing flow.

Uncaught game JavaScript errors in completed runs: **0**. Game-console errors:
**0**. Browser navigation-policy errors during initial harness setup were not
game errors.

This focused update does not claim to retest the entire training course, every
spell effect or all online systems.
