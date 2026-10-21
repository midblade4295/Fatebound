The social media kit's key art (Kevin: "Give me social media package that has banner and icon", after 0.31.200).

key_art.png        the art the kit is made from (2048 x 1152): the icon's Knight and Barbarian clash sword on axe over the
                   logo's ice-and-fire rift, the gold crown above them, the Mage and the Archer charging in from the ice
                   side, the Necromancer and the Musketeer from the fire side, a castle on each.
key_art_take1.png  the other take (the same scene, the clash a little closer); unused.

Both: gpt-image-2, 16:9, 2K, medium quality, with the app icon (art_sources/app_icon/icon.png), Home's champions' camp
painting (godot/assets/ui/v2/bg_camp.webp) and the title logo as references; 1,944 ElevenLabs credits for the two. On the
flow "Fatebound app icon (5v5)" (sNGLKqkKPx0Jv89JIHVM), node "Social key art 16:9" (lYLq0SjVODAxZjD6u3Jr). The prompt:

  Wide key art for the social media banners of "Fatebound", a fantasy 5v5 hero battle game, in exactly the painted style
  of the reference images: the game's icon (a chibi knight in blue steel armour with a red plume and a blue shield
  clashing sword on axe with a bearded barbarian in a bear-skin hood, over a jagged white-hot lightning rift, icy blue on
  the knight's side and fire red-orange on the barbarian's, a golden jewelled crown above), the painting of the game's
  champions (the other chibi heroes: a mage in a starry blue hat, a red-haired archer, a hooded necromancer with green
  flames, a musketeer with a plumed hat) and the title logo (its colours and crown). The scene: the icon's knight and
  barbarian clash at about two thirds of the way across the picture, sparks bursting where the sword meets the axe, the
  lightning rift running from top to bottom behind them; behind the knight his team charges in from the icy blue side
  (the mage casting blue light, the archer drawing her bow), behind the barbarian the other team pours in from the fiery
  side (the necromancer, the musketeer), smaller and further back; the golden crown hovers above the clash. The left
  third of the picture is calmer: icy blue mist, glittering frost and the castle of the blue side far off, room for a
  title to sit over it. Keep every face and the crown in the middle band of the picture (between a quarter and three
  quarters of its height); the top and bottom quarters only sky, sparks, embers and ground. Painted right to the edges,
  no border, no frame. No text, no letters, no logo.

(The model put the clash in the middle instead, so the title goes top centre where the crown is: the kit's script paints
the art's crown out under the title, which has a crown of its own.)

godot/tools/build_social_kit.py makes the kit (godot/store-listing/social) from key_art.png and the app icon:

    cd godot && python3 tools/build_social_kit.py --out store-listing/social

If key_art.png is ever replaced, check the crown outline (CROWN) and the rift (ART_RIFT, CROWN_RIFT) in that script.
