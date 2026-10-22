# Fatebound trailer 9 -- the CGI trailer

Kevin: "Was thinking of doing a full trailer with cgi"; after the test shot: "I love the quality. Do it except don't have
any voice lines. I want the trailer to tell the story like how world of Warcraft trailers are" / "Just have music and
sound effects".

A 68-second cinematic with no narration: the story told in pictures, music and sound effects. Every shot is AI video
(ElevenLabs flow "Fatebound trailer 9 (CGI)", Veo 3.1 Fast -- the duel close-up full Veo 3.1 -- 1280 x 720 at 24 fps,
sound effects generated with it), started from a cinematic keyframe (gpt-image-2.5-sunburst) made from the game's own
pictures -- the champion renders (tools/social_champions.gd), the King, the Rift, the charge, the breach, the Wyrm
(art_sources/trailer9/refs, public so the flow can fetch them) -- with the Grave Wyrm test frame as the style reference
for all of them, so the champions stay on-model and every shot shares one look. The score is four cues made for the cut
(tools/trailer9_vo/raw, ElevenLabs Music v2.5); the title is the game's own, trailer 8's title run with its cue B. "Not
actual gameplay footage" sits at the foot of the title card: it's for social media and YouTube; the store pages keep
trailer 8, the real game.

Cut and mixed by tools/trailer9_edit.py (the shots, trimmed; each shot's own sound levelled; the score placed on the
cut; the title; -14 LUFS, a limiter at 0.82).

## The story
| Time | Shot | Sound |
|---|---|---|
| 0:00 | Dawn: a slow crane over the misty Rift, our blue castle near, theirs red on the far hill (v01) | wind, birds; the dawn cue, a lone horn |
| 0:07 | Their King on his enormous cushioned throne, a turkey leg, a contented wiggle (v02) | the bite, the chewing |
| 0:12.5 | Sir Aldric on our battlements: his shield with its three old cracks; he looks across at their castle (v03) | the strap, the wind; the cue swells |
| 0:18.3 | Hroth blows the war horn, its blast misting from the bell; birds burst from the wall (v04) | THE HORN -- the battle cue's drums |
| 0:21.4 | Our five charge out of the gate at the lens (v05) | footsteps, battle cries |
| 0:26.4 | Their five charge through the river (v06) | splashing, stone steps |
| 0:28.3 | Aldric and the Berserker in the ford, blades locked, close (v07) | grinding steel |
| 0:32.1 | Elara's ring of fire throws the Assassin (v08) | the blast |
| 0:34.7 | Gorrak's landslide; Hroth dives clear (v09) | rock and water |
| 0:37.9 | The ground shakes; Aldric and the Berserker, backs to us, face the green light rising from the hills (v10) | the music drops away; the rumble; the dark cue creeps in |
| 0:40.9 | The Grave Wyrm rears, stalks forward and roars, soul-fire filling the frame (v11, the test shot) | the dark cue's hit on THE ROAR |
| 0:48.9 | Aldric holds its soul-fire back with his cracked shield, the Priest's light round him (v12) | the heroic cue |
| 0:50.4 | The fire spent, he stands, sword raised, Elara and the Priest beside him (v12b) | |
| 0:53.2 | Their throne hall's doors burst in; our five walk through (v13) | |
| 0:58.2 | The King, mid-bite, sees them (v14); closer: his crown pops off. Gulp. | the music stops dead; the crown; the gulp; cue B swells |
| 1:02.3 | Straight into the game's FATEBOUND title flying in and slamming; 5V5 HERO BATTLES; "Not actual gameplay footage" | cue B's hit on the title slam |
| 1:08.1 | end | |

Trims: the horn from just before its blast (0.9-4.0 s); their charge ends before the golem loses his shape (1.9 s); the
ring of fire before the Assassin does in the smoke (2.6 s); the shaking from 1.0 s (after the knight's sword slips out of
sight) to 4.0 s (before it comes back); the block ends before the knight turns (1.45 s); the stand before the mage's
crystal fades (2.8 s); the breach from 0.6 s (the Priest's staff already in his hand); the King without his second bite
(0-2.4 s, then 4.0-5.75 s pushed in 1.25x).

## The rework (Kevin, from his screenshots)
"The wizard shouldn't be holding a shield. The archer is walking with a bow that knocked. The barbarian spawns a sword
when fighting knight and knight does weird animation during scene. The knight and barbarian should be looking towards the
green glow instead of away. When barbarian blows horn the smoke doesn't come out of horn." / "Also the end scene with king
needs a better flow along with game title coming in".
- v04: re-shot, the mist comes from the horn's bell.
- v07: a close-up of the locked blades from a new keyframe on full Veo 3.1 (two Veo 3.1 Fast takes of the wide duel
  still grew swords and morphed the knight's shield and plume): two swords and the shield hold for all 4 s.
- v10: a new keyframe from behind them, facing the green column.
- v12: re-shot block (the Priest young, no beard), then v12b, a new stand (new keyframe: the mage holds only her staff).
- v13: a new keyframe with the archer's bow lowered and no arrow.
- The ending: the King's second bite is gone (cut in closer for the crown and the gulp), no black and no lightning before
  the title: the logo flies in straight after the gulp, cue B swelling under his stare and hitting on the slam.

## Credits (ElevenLabs)
| | Credits |
|---|---|
| The test shot (2 keyframes, 1 video) | 8,137 |
| 13 keyframes, 2 takes each (the more references, the dearer: 675-1,887 a take) | 27,736 |
| 13 videos (Veo 3.1 Fast: 8 s 7,271, 6 s 5,453, 4 s 3,636) | 71,708 |
| The score: 4 cues, 2 takes each | 2,370 |
| The rework: 4 keyframes, 2 takes each, and 7 videos (below) | 48,424 |
| **In all** | **158,375** |

The rework: keyframes k10 2 x 1,160, k13 2 x 433, k07 2 x 1,160, k12b 2 x 1,160 (7,826); videos v04 3,636, v07 (wide,
not used) 5,453, v12 7,271, v10 5,453, v13 5,453, v07 close-up (full Veo 3.1, 4 s) 9,695, v12b 3,636 (40,597; the
duel's wide re-take and v12's second half aren't in the cut).
Four of the first videos waited on Kevin's top-up (the plan's cap, 341,106, was reached mid-run).
