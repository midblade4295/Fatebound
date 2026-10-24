# Fatebound — Google Play and App Store listing (0.31.200, the 5v5)

## App name (max 30) — 27 characters
Fatebound: 5v5 Hero Battles

(The Play listing is still "Fatebound: Siege" until this is saved in the Play Console; the game itself is FATEBOUND.)

## Short description (max 80) — 77 characters
Fast 5v5 hero battles! Pick a champion, push the lanes and topple their King.

## Full description (max 4000) — 2238 characters
Their King sits on a very comfortable chair. Knock him off it.

Fatebound is a fast 5v5 hero battle game (a MOBA) made for your phone. Pick a champion, team up with four others, push down three lanes past the enemy towers and topple their King before they topple yours. Every match is a fresh fight of up to 20 minutes.

PICK YOUR CHAMPION
• 18 champions in six roles: tanks, fighters, assassins, mages, marksmen and supports
• Every champion has three abilities, plus an ultimate that unlocks at level 6
• Level up during the match and choose an upgrade card each time
• 12 champions are yours from the start and two more are free each week. Unlock the rest with the gold you win in matches

TAKE THE RIFT
• Three lanes, three towers in each, and two more guarding the King
• Minion waves march down every lane. Land the last hit and the gold is yours
• Clear jungle camps for gold, experience and powerful buffs
• Slay the Grave Wyrm, or bring down the Bone Lord and send him marching for your side
• Buy items in the shop and build them into bigger ones
• Tap HOME to teleport back to your castle and heal up
• Place wards to see through the fog of war
• Every knockout pays, and every death feeds the other team. First Blood, multi-kills, shutdowns and Aces

PLAY YOUR WAY
• Online 5v5 matches, with bots filling any empty seats
• Or play a match against bots whenever you like
• Party up with friends and clanmates, up to five together
• Learn the ropes from the Royal Herald in a funny, fully voiced tutorial

JOIN A CLAN
• Choose your crest and grow your clan's camp from a single tent to a great hall
• Earn clan points in every match for the weekly Clan Chest, and climb the Clan League
• Ask your clan for hero shards, and give yours to clanmates
• Call for players with Looking For Group and jump straight into a party
• Chat with your clan, your party and everyone online

COLLECT AND CUSTOMIZE
• 36 outfits: a set made for every champion with its own weapon, plus the Frostbound line
• Win chests full of gold, gems and hero shards
• Level up the Siege Pass, finish daily orders and champion quests, and win weekly leaderboard prizes
• Outfits are cosmetic only

Your King is counting on you. He's also eating. Mostly eating.

---

## App Store extras
- **Subtitle** (max 30) — 16 characters: 5v5 Hero Battles
- **Promotional text** (max 170) — 149 characters: New: the Royal Herald welcomes every new recruit, clans have their own camps, and 18 champions are ready for the Rift. Team up and topple their King!
- **Keywords** (max 100, commas, no spaces) — 99 characters: `moba,5v5,arena,champions,heroes,lanes,towers,clan,multiplayer,pvp,fantasy,battle,team,strategy,rift`
- **Description**: the full description above (the App Store's limit is 4,000 too).

---

## Graphics (`../graphics/`)
| File | Use | Size |
|---|---|---|
| `phone_screenshots/01_keyart.jpg` … `08_squad.jpg` | Google Play phone screenshots, in this order | 2560 × 1440 (16:9 landscape) |
| `feature_graphic_1024x500.png` | Google Play feature graphic (required) | 1024 × 500 |
| `app_store/iphone_6_9in/01_keyart.jpg` … `08_squad.jpg` | App Store iPhone 6.9" screenshots, in this order | 2868 × 1320 (landscape) |
| `app_store/ipad_13in/01_keyart.jpg` … `08_squad.jpg` | App Store iPad 13" screenshots, in this order | 2732 × 2048 (landscape) |

Headlines, in order (0.31.212, in Clash Royale's manner: a hero, a two-line headline, the game on a phone): the key art
(the heroes and the title) · TEAM UP FOR 5V5 HERO BATTLES · PICK FROM 18 CHAMPIONS · PUSH THE LANES AND TOPPLE THEIR
KING · SLAY THE GRAVE WYRM · DRESS UP IN 36 OUTFITS · BUILD YOUR CLAN · SQUAD UP WITH FRIENDS

The game on each phone is a real render of build 0.31.199 (the HUD as it plays, or the game's own engine with a camera
of its own); the backdrops are the game's world (in-engine, blurred); the big heroes are the game's own characters
rebuilt in more detail than their in-match models (Meshy, from views of those models). Regenerate with
`godot/tools/store4_match.gd`, `store4_app.gd`, `render_app_icon.gd` and `store5_compose.py` (`../README_FOR_AI.md`
section 5). The text above is the 5v5's (0.31.200), every line checked against the game's code (`listing.json` → `game_facts`).

## Check before publishing
- **In-app purchases:** the text doesn't mention prices. If gems or the premium pass will be sold for
  real money, Play shows "In-app purchases" automatically once billing products exist; keep the
  "Outfits are cosmetic only" line true.
- **Ads:** the text makes no claim either way; declare ads truthfully in the Play Console.
- **Data safety / privacy policy:** online play connects to the Siege server (player name, match
  inputs); Play requires a privacy policy URL and a Data safety form.
- **Content rating:** cartoon fantasy violence; fill in the IARC questionnaire accordingly.
- **App icon:** `../graphics/app_icon_512x512.png` (Play) and `../ios/app_icon_1024.png` (App Store), 0.31.200's.
