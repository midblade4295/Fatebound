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
  assets/ui/tutorial/herald.png   cut out of its white ground (0.31.182: the scroll poses instead, below)
  assets/sounds/recall_start.wav, recall_done.wav

concepts/ (Kevin, on 0.31.181's dialog: "The herald needs to sit higher on the text box. Actually should make it so he
blends into text box seamlessly. Create new herald design concepts" -- then "Remove his horn that's attached to his
neck"): herald_dialog_concepts.jpg, six ways over a real tutorial frame (mock.py makes it; the frame from a 900x2000
render of the tower lesson):
  A rises out of the box (his portrait behind it, the box's edge across his chest)   B a gold medallion on its corner
  C leaning on the box's top edge (C_ledge.png)    D holding the proclamation scroll that is the text box (D_scroll)
  E leaning in from the screen's edge, presenting the box (E_side)    F the Herald and the box painted as one (F_panel)
  gpt-image-2, 1K, one take each, the current portrait and the hero figurines as references: 2,858 credits. Then the
  horn (his trumpet behind his neck) edited out of the portrait (herald_nohorn.png) and D, E, F with
  gpt-image-2.5-sunburst: 1,731 credits. (C never had it.)

poses/ (0.31.182, Kevin: "I like D but also have him doing some funny stuff with the scroll like sometimes he's laying on
top of it and sometimes leaning on it ect"): the Herald with his proclamation scroll eight ways -- each line of the
tutorial is written on it, with the pose that suits it (scripts/siege/tutorial.gd STEPS).
  scroll_blank.png  the scroll alone: concept D with the Herald edited out (gpt-image-2.5-sunburst, 433 credits) --
                    the reference for the rest
  hold.png          concept D, the horn removed (concepts/D_scroll_nohorn.png)
  lying, leaning, sitting (with his tea), peeking, napping, pointing (a pointer stick), hanging (off the right rod):
                    gpt-image-2, 1K, one take each, the hornless portrait and scroll_blank.png as references, 4,583
                    credits; the prompts: "Game UI illustration for a fantasy mobile game, in exactly the style of the
                    reference images: a chunky stylised 3D clay-toy look with smooth soft shading. The exact same Royal
                    Herald as in the first reference image (... he carries no trumpet) and the exact same unrolled
                    parchment scroll as in the second reference image (...). The scroll lies horizontally, flat and
                    facing the viewer, in the lower half of the image, about 80% of the image width, its parchment
                    completely blank. <the pose> Plain flat pure white background (#FFFFFF), no shadow on the
                    background, no text and no writing anywhere." (the poses' own words: on the flow)
godot/tools/build_tutorial_assets.py poses -> assets/ui/tutorial/scroll_<pose>.png (cut out, cropped, 1100 wide) and
scripts/siege/tutorial_poses.gd (each one's size, its parchment, and the biggest clear rectangle of it for the writing).
poses/matte/<pose>.png (0.31.183, Kevin: "There is white showing on most of herald images. Go through each one and make
sure all the white cutout is gone"): birefnet-v2-bg-removal on each pose, its alpha kept (the matte of the Herald; it
keeps the scroll too in hold, leaning, peeking and hanging, and drops it in the rest), 8 x 30 = 242 credits. The cut
takes the Herald from it and the scroll from what isn't white (the build checks no patch of white ground over a few
px is left at the edge).
