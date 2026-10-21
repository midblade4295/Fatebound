# Fatebound: Siege — Google Play store listing

## App name (max 30) — 16 characters
Fatebound: Siege

## Short description (max 80) — 73 characters
Storm castles, steal hats and rescue your Oracle in chaotic 16v16 sieges!

## Full description (max 4000) — 1878 characters
Your Oracle has been kidnapped. Rude. Grab a hat, rally your team and storm the enemy castle to bring her home!

Fatebound: Siege is a chaotic medieval team battle for 16 vs 16 players. Break down the gates, carry your Oracle out of the enemy dungeon and get her back to your throne. Three rescues wins the match. Meanwhile, the other team is trying to do the exact same thing to you.

THE HAT MAKES THE HERO
Everyone starts as a humble Villager. Walk into a hat shop and become a hero:
• Knight: raise your shield and protect everyone standing behind you
• Barbarian: smash gates, then upgrade to Berserker and whirlwind through crowds
• Rogue: lunge in for the quick strike
• Ranger: rain down volleys of arrows
• Mage: blast groups apart with an arcane nova
• Priest: heal allies with a holy beam and a sanctuary
• Worker: chop wood, mine stone, repair gates and build ladders
Fall in battle and your hat drops where you stood. Anyone can pick it up. Yes, even the enemy.

SIEGE LIKE YOU MEAN IT
• Break the gates or build ladders over the walls to get into the enemy castle
• Carry your Oracle home together. The heavier she is, the more hands it takes
• Feed the enemy's captive cake to make her heavier. Delicious sabotage.
• Capture outposts to earn wood and stone and to respawn closer to the action
• Spend resources at the workshop on reinforced gates, better armor and catapults
• Upgrade each hat shop to unlock the Paladin, Berserker, Assassin, Sniper, Archmage and High Priest

PLAY YOUR WAY
• Jump into online 16 vs 16 battles
• Or play offline against bots, anytime
• Learn the ropes with the Royal Herald's funny, hands-on tutorial

MAKE IT YOURS
• Unlock skins, weapons, titles and bundles
• Level up the Siege Pass and complete daily and weekly challenges
• Everything you unlock is cosmetic. No pay-to-win.

The Oracle is waiting. Probably bored. Go get her!

---

## Graphics (`../graphics/`)
| File | Use | Size |
|---|---|---|
| `phone_screenshots/01_teamfight.png` … `08_tutorial.png` | Google Play phone screenshots, in this order | 1080 × 1920 (9:16) |
| `feature_graphic_1024x500.png` | Google Play feature graphic (required) | 1024 × 500 |
| `app_store/iphone_6_9in/01_teamfight.png` … `09_chest.png` | App Store iPhone 6.9" screenshots, in this order | 1320 × 2868 |
| `app_store/ipad_13in/01_teamfight.png` … `09_chest.png` | App Store iPad 13" screenshots, in this order | 2048 × 2732 |

Captions, in order: 5V5 HERO BATTLES · 18 CHAMPIONS · TOPPLE THEIR KING · SLAY THE GRAVE WYRM · 36 OUTFITS ·
BUILD YOUR CLAN · SQUAD UP · LEARN FROM THE HERALD (· OPEN CHESTS, App Store only: Play takes 8)

Every image is a real render of build 0.31.199 (the 5v5; the HUD as it plays, or the game's own engine with a camera of
its own). Regenerate with `godot/tools/store4_match.gd`, `store4_app.gd` and `store4_compose.py` (`../README_FOR_AI.md`
section 5). **The text above is still the 16 vs 16 Siege game's: rewrite it for the 5v5 before publishing.**

## Check before publishing
- **In-app purchases:** the text doesn't mention prices. If gems or the premium pass will be sold for
  real money, Play shows "In-app purchases" automatically once billing products exist; keep the
  "No pay-to-win" line true (shop items are cosmetic today).
- **Ads:** the text makes no claim either way; declare ads truthfully in the Play Console.
- **Data safety / privacy policy:** online play connects to the Siege server (player name, match
  inputs); Play requires a privacy policy URL and a Data safety form.
- **Content rating:** cartoon fantasy violence; fill in the IARC questionnaire accordingly.
- **App icon:** a 512 × 512 icon is required separately (not in this folder).
