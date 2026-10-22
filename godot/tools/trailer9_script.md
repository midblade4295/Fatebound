# Fatebound trailer 9 -- the CGI trailer

Kevin: "Was thinking of doing a full trailer with cgi"; after the test shot: "I love the quality. Do it except don't have
any voice lines. I want the trailer to tell the story like how world of Warcraft trailers are" / "Just have music and
sound effects".

A 76-second cinematic with no narration: the story told in pictures, music and sound effects. Every shot is AI video
(ElevenLabs flow "Fatebound trailer 9 (CGI)", Veo 3.1 Fast, 1280 x 720 at 24 fps, sound effects generated with it),
started from a cinematic keyframe (gpt-image-2.5-sunburst) made from the game's own pictures -- the champion renders
(tools/social_champions.gd), the King, the Rift, the charge, the breach, the Wyrm (art_sources/trailer9/refs, public so
the flow can fetch them) -- with the Grave Wyrm test frame as the style reference for all of them, so the champions stay
on-model and every shot shares one look. The score is four cues made for the cut (tools/trailer9_vo/raw, ElevenLabs
Music v2.5); the title is the game's own, trailer 8's title run with its cue B. "Not actual gameplay footage" sits at the
foot of the title card: it's for social media and YouTube; the store pages keep trailer 8, the real game.

Cut and mixed by tools/trailer9_edit.py (the shots, trimmed; each shot's own sound levelled; the score placed on the
cut; the title; -14 LUFS, a limiter at 0.82).

## The story
| Time | Shot | Sound |
|---|---|---|
| 0:00 | Dawn: a slow crane over the misty Rift, our blue castle near, theirs red on the far hill (v01) | wind, birds; the dawn cue, a lone horn |
| 0:07 | Their King on his enormous cushioned throne, a turkey leg, a contented wiggle (v02) | the bite, the chewing |
| 0:12.5 | Sir Aldric on our battlements: his shield with its three old cracks; he looks across at their castle (v03) | the strap, the wind; the cue swells |
| 0:18.3 | Hroth blows the war horn; birds burst from the wall (v04) | THE HORN -- the battle cue's drums |
| 0:21.9 | Our five charge out of the gate at the lens (v05) | footsteps, battle cries |
| 0:26.9 | Their five charge through the river (v06) | splashing, stone steps |
| 0:28.8 | Aldric and the Berserker, blade to blade in the ford (v07) | steel |
| 0:33.3 | Elara's ring of fire throws the Assassin (v08) | the blast |
| 0:35.9 | Gorrak's landslide; Hroth dives clear (v09) | rock and water |
| 0:39.1 | The ground shakes; green light from the hills; they stop and stare (v10) | the music drops away; the rumble |
| 0:44.6 | The Grave Wyrm rears, stalks forward and roars, soul-fire filling the frame (v11, the test shot) | the dark cue's hit on THE ROAR |
| 0:52.6 | Aldric holds its soul-fire back with his cracked shield, the Priest's light round him; then stands, shield raised (v12) | the heroic cue |
| 0:57.4 | Their throne hall's doors burst in; our five walk through (v13) | |
| 1:02.4 | The King, mid-bite, sees them. His crown slides off. Gulp. (v14) | the music stops dead; the gulp |
| 1:08.5 | Black; lightning; the game's FATEBOUND title slams in; 5V5 HERO BATTLES; "Not actual gameplay footage" | cue B, the lightning, the title slam |
| 1:16.1 | end | |

Trims: their charge ends before the golem loses his shape (1.9 s); the ring of fire before the Assassin does in the
smoke (2.6 s); Aldric's stand is two pieces of its shot (0-3 s, 6.2-8 s), skipping where the Mage grows a shield.

## Credits (ElevenLabs)
| | Credits |
|---|---|
| The test shot (2 keyframes, 1 video) | 8,137 |
| 13 keyframes, 2 takes each (the more references, the dearer: 675-1,887 a take) | 27,736 |
| 13 videos (Veo 3.1 Fast: 8 s 7,271, 6 s 5,453, 4 s 3,636) | 71,708 |
| The score: 4 cues, 2 takes each | 2,370 |
| **In all** | **109,951** |
Four of the videos waited on Kevin's top-up (the plan's cap, 341,106, was reached mid-run).
