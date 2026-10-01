# Fatebound — tutorial voiceover script

Narrator: **the Royal Herald** — pompous, theatrical, a little tired of it all, fond of the recruit
despite himself. Dry comic timing: let the punchline land after a tiny pause.

Recorded (0.19.3): Kevin's ElevenLabs read, split with `tools/vo_split.py FULL_READ.mp3` (re-run it
after a re-record; it checks every cut before writing). Or drop a single recording in as `<id>.ogg`
(or `.wav` / `.mp3`). The game plays it with the line automatically; lines without a file just show
the text. Generated from `scripts/siege/tutorial.gd` (STEPS) — edit the lines there, then regenerate.

| # | ID | When | Line |
|---|---|---|---|
| 1 | `t_intro_1` | intro | Ah, a new recruit! Welcome to Fatebound. I'm the Royal Herald. I announce things. Loudly. It's a living. |
| 2 | `t_intro_2` | intro | Across that field, the enemy is holding our King hostage. We'd like him back. He does the ruling. And the waving. |
| 3 | `t_move_1` | move — before the task | First things first: walking. Drag your thumb on the left side of the screen. Yes, like that. No, the other left. |
| 4 | `t_move_done` | move — after the task | Magnificent. You've mastered the ancient art of 'going places'. The bards will sing of it. Briefly. |
| 5 | `t_hat_1` | hat — before the task | Right now you're a Villager. Villagers are brave, loyal, and hit like a wet sock. |
| 6 | `t_hat_2` | hat — before the task | See the Barracks? That's the Knight's hat shop. Walk up to its door. In this kingdom the hat makes the hero. Don't ask me why. I just read the scrolls. |
| 7 | `t_hat_done` | hat — after the task | A Knight! Look at you. Positively shiny. Try not to lose that hat. You'll see why in a moment. |
| 8 | `t_attack_1` | attack — before the task | A training dummy awaits in the courtyard. It volunteered. Well. 'Volunteered'. Walk up to it and tap ATTACK, or hold ATTACK to keep whacking. |
| 9 | `t_attack_done` | attack — after the task | Excellent violence. The dummy has filed a complaint. It will be ignored. |
| 10 | `t_dodge_1` | dodge — before the task | Now the most important skill in any war: not being where the sword is. Tap DODGE. |
| 11 | `t_dodge_done` | dodge — after the task | Nimble! Cowardly, some might say. I prefer 'tactically absent'. |
| 12 | `t_block_1` | block — before the task | Every class has an ability. Knights have a very large shield. Hold ABILITY to raise it: it stops everything from the front, even for friends hiding behind you. |
| 13 | `t_block_done` | block — after the task | A wall with legs! Your allies will adore you. Mostly they'll adore standing behind you. |
| 14 | `t_hats_1` | hats | A word of warning. When you fall in battle, your hat falls too, and anyone can pick it up. Friend or foe. Yes, even the enemy. Fashion is cruel. |
| 15 | `t_hats_2` | hats | You'll come back as a Villager. Grab a hat off the ground or run home to a hat shop. Sneak into the enemy castle and you can even use theirs. Rude, but legal. |
| 16 | `t_ws_1` | workshop — before the task | Next: the workshop. Follow the arrow, and mind the barrels. |
| 17 | `t_ws_done` | workshop — after the task | Workers bring wood and stone here. Spend it on stronger gates, better armor and catapults. Walls don't build themselves. Believe me, I asked. |
| 18 | `t_ws_worker` | workshop — after the task | Want to be a Worker? Take tools here. Workers chop trees, mine rocks, repair gates and build ladders. Glamorous? No. Essential? Also no. Just kidding. Very essential. |
| 19 | `t_up_1` | upgrade — before the task | The treasury has kindly 'found' some materials for you. Go back to the Barracks and press UPGRADE. |
| 20 | `t_up_done` | upgrade — after the task | Paladin hats! Every hat from that shop is fancier now. Upgrades are bought at each hat shop, not the workshop. The workshop is still sulking about it. |
| 21 | `t_rampart_1` | rampart | One more trick for defending. See the walkway on our front wall? Take its stairs up, and your arrows fly right over the wall. Archers adore it. The enemy does not. |
| 22 | `t_out_1` | outpost — before the task | See that tower up on the ledge? That's an outpost. Stand in its ring to capture it. Capturing is mostly standing around looking important. You're a natural. |
| 23 | `t_out_done` | outpost — after the task | It's ours! We can respawn here, workers can drop resources off here, and it earns us wood and stone. Passive income. The true magic. |
| 24 | `t_goal_1` | goal | Now, the actual point of Fatebound. The enemy's dungeon is down a flight of stairs inside their castle, behind their gates. Our King is in there, behind bars. Probably complaining. |
| 25 | `t_goal_2` | goal | Break a gate down, and Barbarians are marvellous at that, or have a Worker build a ladder over the wall. Then smash his cell open, grab him and carry him home to his throne. |
| 26 | `t_goal_3` | goal | Rescue him three times and we win. They're trying to do the exact same thing to us, so leave a few friends at home. Trust issues are healthy here. |
| 27 | `t_cake_1` | fish — before the task | But first, a dirty trick. See the river? It's full of fish. Stand on the bank and press ACTION to cast your line. Patience. Fish are not known for their punctuality. |
| 28 | `t_cake_took` | fish — after the task | A fish! Magnificent. Now, we have a guest in OUR dungeon: the enemy's King. He looks peckish. |
| 29 | `t_feed_1` | feed — before the task | Our dungeon is down the stairs, and the cell door opens for friends. Bring him that fish and press ACTION to feed him. Every bite makes him heavier. Delicious sabotage. |
| 30 | `t_feed_done` | feed — after the task | He said thank you! Is it tactically brilliant? Yes. Is it ethically questionable? Also yes. Welcome to Fatebound. |
| 31 | `t_rescue_1` | shortcut | Right. Let's get OUR King back. Normally you'd march over, smash a gate and fight your way in. Today I've arranged a shortcut. Don't ask how. Royal paperwork. |
| 32 | `t_grab_1` | grab — before the task | Here we are. Their gate is, ahem, 'mysteriously broken'. So is his cell door. Go down to their dungeon, find our King and press ACTION to lift him. |
| 33 | `t_grab_done` | grab — after the task | Got him! You're slower while carrying. Heavier Kings need friends to help lift, which is exactly why we feed THEIRS so much fish. |
| 34 | `t_carry_1` | carry — before the task | Now carry him all the way home to his throne. Follow the arrow. And don't drop him. He will never let you forget it. |
| 35 | `t_carry_done` | carry — after the task | RESCUED! That's one! Rescue him three times and the match is ours. The crowd goes mild. |
| 36 | `t_end_1` | end | That's everything! Well. Not everything. But everything I was paid to say. |
| 37 | `t_end_2` | end | Go forth, recruit. Fatebound awaits. Win glory, rescue the King, and please, try to keep your hat on. |
