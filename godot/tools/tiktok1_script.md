# Fatebound TikTok 1 -- "The King's snack"

Kevin: "I want a short CGI video that will make people on tiktok want to watch right off the bat. Something that could get
a lot of views on tiktok" -- picked "King's snack" (a comedy loop) at about 15 s.

A vertical 9:16 short (1080 x 1920, 30 fps, -14 LUFS, 14.05 s) built to hold a scroller from the first frame and to loop.
The caption **"POV: you're the boss in a 5v5"** is on screen from the first frame through every shot (TikTok's style, high
in the frame, clear of the app's tabs, buttons and caption):
- **0.0 s** -- the hook: an extreme close-up of the round King, napkin tucked in, happily biting a giant turkey leg.
- **1.27 s** -- BOOM: the throne hall's doors blow in off-screen; light, dust and splinters hit him; he freezes mid-chew.
- **3.4 s** -- his point of view, past his own crown: the five heroes (knight, barbarian, mage, archer, priest) charge at
  him down the red carpet through the dust (quickened 1.25x so it reads as a charge).
- **6.4 s** -- caught: frozen, his crown slides off and clangs (~7.1 s), one huge GULP (~7.9 s), his eyes dart, a nervous
  beat, then a sheepish grin with a bead of sweat as he offers them the turkey leg (~10.6 s).
- **12.15 s** -- the game's title slams in (12.31 s) over his blurred offer -- trailer 8's cue B hitting with the game's
  title slam -- then 5V5 HERO BATTLES and "Not actual gameplay footage".
- **14.05 s** -- the loop: straight back to him happily biting, so a viewer sees the start again before they've scrolled.

## How it was made
The shots are AI video (ElevenLabs flow "Fatebound TikTok 1 (King's snack)", CyljrhTEJWMnaZtlqT3D; Veo 3.1 Fast, 9:16 at
720p, their own sound effects), each started from a vertical keyframe (gpt-image-2.5-sunburst) made from trailer 9's own
frames of the King (shots 2 and 14) and of the five heroes in the breach (shot 13, the archer's bow lowered), so they match
trailer 9. Cut and mixed by tools/tiktok1_edit.py (--clean: no caption, for TikTok's own text).

| shot | keyframes | video | used |
|---|---|---|---|
| v1 the bite, BOOM | K1 (the King mid-bite) | 6 s | 0.0-3.4 s |
| v2 the charge (his POV) | K2 (the five in the breach, past his crown) | 4 s | 0.0-3.75 s at 1.25x |
| v3 caught, GULP, the offer | K3 take a (start) -> K4 take a (end: no crown, sheepish, offering) | 6 s | 0.0-5.75 s |

The first v3 (start frame only) lost the crown and then grew it back at ~2.7 s, and the King scowled and kept eating
instead of offering; it was re-shot between a start and an end frame (K4), which pins where he ends up.

Credits (ElevenLabs): keyframes 3,566 (one K1 take was blocked by the image filter and still charged 675), videos 14,543
(v1, v2, the first v3), K4 866 (two takes), the v3 re-shoot 5,453 -- about 24,430 in all.

## Posting notes
- Post the captioned version; keep the in-app caption short and add a question to pull comments, e.g. "would you share
  your snack?" or "which hero are you?". Hashtags along the lines of #gaming #indiegame #mobilegame #moba.
- Use the video's own sound (the BOOM, the clang and the GULP are the joke); a trending sound can go under it at low
  volume in the app.
- The first frame is the thumbnail TikTok shows in the profile grid: the King mid-bite with the caption.
- The clean version is for TikTok's own text tool (or a different caption) -- put the text high, away from the buttons.
