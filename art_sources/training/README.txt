The Honor of Kings style training's voice (0.31.217).
Kevin (a 12-minute recording of Honor of Kings' two training matches): "Here is how I want the training to go in
fatebound. The helper will be another character and voiced by the herald." Asked which hero helps -> "Dragoon": Kael
Wyrmlance, the Dragoon ("Last Rider of Skyreach"), fights beside you and talks you through it in the Herald's voice.

All ElevenLabs, one flow: "elyaqnE7abxbAcSkvy9Y" (https://elevenlabs.io/app/flows/elyaqnE7abxbAcSkvy9Y).
eleven_v4, the Herald's voice ("Edward - British, Dark, Low", goT3UYdM9bhm0n2lmKQx -- the tutorial's, the match calls'
and the kill banners'), two takes a line, the prompt the line as written. 2,443 characters, 4,886 credits for both takes.
Take 1 used for every line.

script.json   the 58 lines: [id, audio tag (none), the line]. scripts/siege/training.gd's captions are these lines word
              for word (tests/training_test.gd checks).
                k1_*   the first training (one lane, Kael beside you: moving, attacking, the first skill, levels, the
                       combo, the ultimate, quick-buy, the towers, the King)
                b_*    Kael's speech bubbles ("Well done!", "Watch out!" ...)
                k2_*   the second training (a 5v5 on the Rift: the map tour, the lane roles, the tower lesson, HOME, the
                       shop, the King)
vo/<id>.mp3   take 1 of each

godot/tools/build_tutorial_assets.py training makes the game's files from these:
  assets/vo/training/<id>.ogg     silence trimmed, -16 LUFS, mono vorbis (as the tutorial's)
