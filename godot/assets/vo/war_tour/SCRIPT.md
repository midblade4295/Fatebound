# Fatebound — war map tour voiceover script

Narrator: **the Royal Herald** (the match tutorial's voice). Lines come from `scripts/app/war_tour.gd` (make_steps);
the tour plays `<id>.ogg` with each line, and a line without a file just shows its text.

Generated 0.31.152 (Kevin: "Go"): ElevenLabs, voice "Edward - British" (goT3UYdM9bhm0n2lmKQx), eleven_v4, one take
each (1,410 credits for the ten). Each levelled to -16 LUFS, limiter -1.5 dB, 10 ms / 60 ms fades, mono 44.1 kHz OGG
Vorbis q5. In the read, "JOIN" was written "join" (so it's said, not spelled).

**Re-record a line when its text changes.** Four say numbers from the code: tour_bars (Map.PTS_CROWN, Map.PTS_LOSS),
tour_take (Map.NEED_OWNED, Map.NEED_NEUTRAL), tour_week (Eco.WAR_WEEK gems), tour_homes (Map.HOME_WORTH, "three").
tests/war_tour_test.gd checks each of them still matches what was read here.

Not recorded: `tour_ready` (the last line for a player in a clan) -- it names the player's house and clan tag.

| ID | Line |
|---|---|
| `tour_intro` | Ah, the war table! Every land in the realm is on it, and three great houses want all of it: the Lions, the Stags and the Ravens. |
| `tour_homes` | Each house has a keep. Most days, keeps can't be touched. But every Sunday is King's Day, and keeps can be stormed. A fallen keep counts as three lands. Guard yours. |
| `tour_land` | A land's colour shows which house holds it. Tap a land to see who holds it, and how close each clan is to taking it. |
| `tour_bars` | Clans fight for their house. Every crown your side wins in a battle adds 50 points to your clan's bar. A lost battle takes 100 away. |
| `tour_take` | The first clan to fill its bar takes the land for its house: 1,000 points for land another house holds, 500 for free land. |
| `tour_links` | You can only attack along the roads, from land your house already holds. A mountain ridge means no road. Plan accordingly. |
| `tour_battles` | Fight as often as you like. Every battle your clan wins moves its bar, started or joined. Defending your house's land holds it, and costs you nothing but sweat. |
| `tour_week` | Every Monday the war ends. The house holding the most land wins the week: everyone in its clans gets a Gold Chest and 50 gems. Then the map is wiped clean for the next one. |
| `tour_hot` | Where's the fighting? Battles burning right now glow on the map and line up under it. Tap JOIN and you're in. No waiting, no paperwork. |
| `tour_clan` | To fight for land, you need a clan. Every house has its own, free and open to all. Or join a players' clan, or start your own. The realm won't conquer itself! |
