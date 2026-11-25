# Drums of War audio sources

Every file in this folder was generated with ElevenLabs (ElevenCreative flow "Drums of War sounds") for this
project on 2026-11-25, then cut and converted locally with ffmpeg/numpy. Nothing here is a recording or a
third-party sample.

- Sound effects: model `eleven_text_to_sound_v3` (ElevenLabs Sound Effects v3), default settings
  (prompt influence 0.3, loop off), 4 takes per prompt.
- Music: model `eleven_music_v2_5` (ElevenLabs Music v2.5), default settings, 4 takes.
- Output format: OGG Vorbis, 44.1 kHz. Effects are mono at quality 5; music is stereo at quality 4.
  All files have leading silence trimmed, a 25 Hz high-pass (effects only), a 20 ms fade-out and are
  peak-normalised to about -1.5 dBFS.

Takes were chosen without listening, from measurements only (duration, peak, silence, clipping, onset counts,
pitch tracking). "Take" is the position among the four variations returned for the prompt.

| File | Take used | Prompt |
|---|---|---|
| `volley_1.ogg` | 3 | Ragged volley of five or six black-powder muskets firing almost together, quick crackle then a short tail, punchy, dry, close-mic, no reverb, 1.2 seconds |
| `volley_2.ogg` | 4 | (same prompt as `volley_1`) |
| `cannon.ogg` | 1 | Single 1860s field cannon firing, deep boom with a short rolling tail, dry, outdoor close-mic, no reverb, 1.5 seconds |
| `canister.ogg` | 1 | Cannon firing grapeshot at close range, heavy boom with a sharp scattering hiss of small shot, dry, no reverb, 1.2 seconds |
| `redoubt_gun.ogg` | 1 | Small light cannon shot, tight punchy thump with a very short tail, dry, no reverb, 0.9 seconds |
| `charge.ogg` | 3 | Short bright cavalry bugle call over galloping horse hooves, lively, dry, no reverb, 2 seconds |
| `repelled.ogg` | 1 | Startled horses whinnying and skidding to a halt on dirt, comic, dry, no reverb, 1.2 seconds |
| `rout.ogg` | 1 | A handful of men yelping in comic cartoon panic, wordless, boots running away, dry, no reverb, 1.5 seconds |
| `rally.ogg` | 3 | Crisp military snare drum roll ending in a short wordless cheer from a few men, dry, no reverb, 1.5 seconds |
| `square.ogg` | 2, 3, 4, 1 (edited) | Sharp military snare drum tattoo, rat-a-tat-tat, crisp, close-mic, dry, no reverb, 0.8 seconds |
| `deploy.ogg` | 1 | Soldiers' boots stamping to attention with a small equipment rattle, dry, no reverb, 0.5 seconds |
| `order.ogg` | 1 (edited) | Short two-note bugle call, bright brass, dry, no reverb, 0.7 seconds |
| `card_select.ogg` | 2 (excerpt) | Soft paper playing card flick, close-mic, dry, 0.2 seconds |
| `destroyed.ogg` | 4 | Small wooden building collapsing, timbers cracking then a dusty thump, dry, no reverb, 1.8 seconds |
| `overtime.ogg` | 1 | Urgent accelerating military snare drum roll, speeding up to a tight buzz, dry, no reverb, 2 seconds |
| `victory.ogg` | 3 | Jaunty triumphant fife and snare drum fanfare, short bright victory sting, dry, 4 seconds |
| `defeat.ogg` | 1 | Slow deflating fife phrase drooping downward over a muffled drum, comic sad-trombone feel, dry, 3 seconds |
| `music_battle.ogg` | 4 (loop cut) | Instrumental only, no vocals. Upbeat playful 1860s fife-and-snare-drum marching tune, bright piccolo fife melody over crisp rudimental snare and a light bass drum, moderate march tempo around 110 BPM, steady energy throughout with no intro build or fade-out so it loops cleanly, dry crisp production, 30 seconds. |
| `victory_alt_fife.ogg` | music take 4 (excerpt) | (same prompt as `music_battle`) |

## Edits beyond trim and normalise

- `square.ogg`: every generated take was a single snare hit with a decaying buzz. The file sequences four of
  those generated hits (takes 2, 3, 4, then take 1 ringing out) at 0 / 0.13 / 0.20 / 0.33 s to make the tattoo.
- `order.ogg`: every generated take was one sustained note (about 459 Hz). The file plays 0.30 s of take 1 as
  generated, then the same note resampled up a perfect fourth (about 612 Hz) to make the second note.
- `card_select.ogg`: the model's shortest clip is about 0.5 s; this is the 0.24-0.44 s window around the flick.
- `music_battle.ogg`: the 30 s render is cut to 26.18 s (48 beats at 110 BPM, six 8-beat phrases) so that the
  end runs into the start on the beat; the first 40 ms is cross-faded from the audio that followed the cut.
  Enable looping on import in Godot.
- `victory_alt_fife.ogg`: optional extra, not one of the requested files. No victory take contained a fife, so
  this is the first 8-beat phrase of the battle tune as a mono sting, to audition against `victory.ogg`.

## Impact set (second batch)

Generated the same way on the same flow with `eleven_text_to_sound_v3` (default settings, 4 takes per prompt)
and converted with the same rules: mono OGG Vorbis, 44.1 kHz, quality 5, leading silence trimmed, 25 Hz
high-pass, 20 ms fade-out, peak about -1.5 dBFS. Takes were again chosen from measurements only (first-transient
strength, stroke counts, band energy, peak, clipping), not by listening.

| File | Take used | Prompt |
|---|---|---|
| `hit_volley.ogg` | 4, 2, 3, 1 (layered) | Musket balls striking home, three or four hard punchy thuds then a ricochet whine, one man grunting, strong first transient, close-mic, dry, no reverb, 0.7 seconds |
| `hit_shot.ogg` | 2 | Cannonball ploughing into earth, heavy low thump, a spray of dirt and a rolling bounce, strong first transient, close-mic, dry, no reverb, 1 second |
| `hit_structure.ogg` | 1 | Cannonball smashing into timber and sandbags, deep crack of splintering wood then falling debris, strong first transient, close-mic, dry, no reverb, 0.9 seconds |
| `melee.ogg` | 2, 3, 4 (sequenced) | Brief scuffle of bayonets and sabres clashing, two or three sharp metallic clangs with wordless grunts, comic, strong first transient, close-mic, dry, no reverb, 0.9 seconds |
| `cannon_big.ogg` | 4 | Heavy field cannon blast, sharp crack at the front then a huge chest-thumping low boom with deep sub bass and a short tail, close-mic, dry, no reverb, 1.6 seconds |
| `cannon_big_layered.ogg` | `cannon_big` take 4 + `cannon` take 1 | (prompts of `cannon_big` and `cannon`) |
| `charge_hit.ogg` | composite, no prompt of its own | (prompts of `hit_shot`, `hit_structure`, `melee` and `repelled`) |

Edits beyond trim and normalise:

- `hit_volley.ogg`: every take was a single thud with a grunt-like tail. The four generated thuds are layered
  as a ragged cluster at 0 / 0.055 / 0.125 / 0.20 s (take 4 first and ringing out, then takes 2, 3 and 1).
- `melee.ogg`: every take was essentially one clang. Three generated clangs are sequenced at 0 / 0.17 / 0.36 s
  (takes 2, 3, 4).
- `cannon_big.ogg`: take 4 as generated; it had the most energy below 120 Hz of the four takes and no clipping.
- `cannon_big_layered.ogg`: optional extra, not one of the requested files. `cannon_big` with the sub-160 Hz
  body of the original cannon take (take 1, low-passed) added underneath.
- `charge_hit.ogg`: not generated from its own prompt. It is a mix of takes from this project: `hit_shot`
  take 4 (thump) and `hit_structure` take 4 (crack) at 0 s, `melee` takes 3, 4 and 1 (steel) at 0.05 / 0.17 /
  0.30 s, and the first 0.85 s of `repelled` take 3 (horse) from 0.20 s.
