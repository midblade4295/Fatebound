The 5v5 tutorial's voice, the Herald's portrait and the recall's sounds (0.31.181).
Kevin: "Now create a tutorial walking player through the basics of a match. Things like how buying works, economy in
game, trying not to die because feeds enemy team economy. Benefits of building up team economy with minions and
jungling ect ect. Make it voiced and make it humorous and sarcastic" -- and "Also add a teleport back to castle
mechanic" (HOME, siege_sim.gd _recall).

All ElevenLabs, one flow: "SUPUWoyCwgxpNctEW4qW" (https://elevenlabs.io/app/flows/SUPUWoyCwgxpNctEW4qW).
5,026 credits (~$0.92) in all.

script.json   the 33 lines: [id, audio tag (spoken direction, not shown), the line]. scripts/siege/tutorial.gd's captions
              are these lines word for word (tests/tutorial_test.gd checks).
vo/<id>.mp3   eleven_v4, the Herald's voice ("Edward - British, Dark, Low", goT3UYdM9bhm0n2lmKQx -- his match calls
              and the kill banners' calls), one take a line, the prompt the line (with "[dry]" before t5_intro_1 and
              "[sighs]" before t5_die_2). 4,140 credits, 5 min 30 s in all.
eleven/herald_<take>.png
              gpt-image-2, 1K, two takes (840 credits), the "Fatebound hero style reference" (the hero figurines) wired
              in as a reference. Take 1 used. Prompt: "Head-and-shoulders portrait of the Royal Herald, a new character
              made in exactly the style of the reference figurines: a chunky stylised 3D toy figure with a big head,
              smooth soft clay-like shading, simple rounded features, small dark eyes. He is a lanky, self-important
              royal herald in his fifties: a floppy royal-blue velvet cap with a long white plume, a thin curled
              moustache, one eyebrow raised and heavy half-lidded eyes giving a dry, unimpressed, sarcastic look, a
              faint smirk. A royal-blue and gold tabard with a small gold crown emblem, a white ruffled collar, a rolled
              parchment scroll tucked under one arm and a slim brass herald's trumpet with a little blue banner over his
              shoulder. Facing three-quarters toward the viewer, centred, looking at the viewer. Soft studio lighting.
              Plain flat pure white background (#FFFFFF), no shadow on the background, no text, no frame."
sfx/recall_start_<take>.mp3   eleven_text_to_sound_v2, 2 s, influence 0.5: "Fantasy video game teleport channel
              starting: a soft magical shimmer of rising glassy chimes and a gentle airy whoosh swirling upward, bright
              and clear, no music" (take 2 used: a clear rising sweep; take 1 a denser hiss)
sfx/recall_done_<take>.mp3    1.5 s: "Fantasy video game teleport arrival: a quick bright magical swoosh into a soft
              sparkling pop and a short twinkling shimmer tail, no music" (take 2 used: it lands at once; take 1
              swells for 0.3 s first)
              (the four: 23 credits)

godot/tools/build_tutorial_assets.py makes the game's files from these:
  assets/vo/tutorial/<id>.ogg     trimmed, -16 LUFS, mono vorbis
  assets/ui/tutorial/herald.png   cut out of its white ground
  assets/sounds/recall_start.wav, recall_done.wav
