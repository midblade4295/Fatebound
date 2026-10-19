The champions' paintings (0.31.187, Kevin: "When clicking on a champion, make a customized window for them that pops up
that is themed around them ... Use art and effects that match each characters lore").

ElevenLabs gpt-image-2, 9:16 at 1K (720 x 1280), medium quality, one take each; the Market banner
(godot/assets/ui/v2/art_shop.webp) as the style reference; flow "Fatebound champions 0.31.187". 18 x 420 = 7,554 credits.
prompts.json has each one's whole prompt (and its generation id). The shared parts:

  A tall painted backdrop for a fantasy mobile game's champion profile screen, in the same painterly style, rich colour
  and lighting as the reference market banner (polished Supercell-style painting). Do not copy the reference's market
  stall or its scene. Scene: <his place>. Seen from the front at eye level. Composition: in the middle of the picture,
  from about a third to two thirds of the way down, a clear open patch of ground in the centre, empty and softly lit,
  where a champion will stand; the scene frames it at the sides and above. The bottom third of the picture falls into
  deep, calm shadow with no details. No characters, no people, no creatures, no animals, no text or lettering.

Each one's place (his story: godot/scripts/meta/champions.gd):
  knight       Sir Aldric Vane          a stone bridge to a castle gate at dawn, blue-and-silver banners, a misty gorge
  barbarian    Hroth Bearcloak          a mountain clan's camp at night: a bonfire, a longhouse with bear totems, snow
  rogue        Wren Ashveil             an outlaws' hideout in a misty green forest: roots, rope bridges, a lantern
  ranger       Kestrel Finn             a sunny archery meadow at a forest's edge: targets, a watchtower, hills
  mage         Elara Flintwick          a fire mage's tower study at night: books, a star window, a blazing hearth
  priest       Brother Cael Sunward     a sunlit white-and-gold cathedral nave, a golden sun disc
  crusader     Lord Gideon Hale         a holy order's fortress courtyard at sunrise, golden sigils in the flagstones
  berserker    Ulfgar Blackmaw          a battlefield after the battle under a blood-red sunset, a torn black banner
  assassin     Vesper Nightshade        city rooftops at night under a crescent moon, red lanterns, red ribbons
  sniper       Hollis Thorne            a hunter's lodge on a cliff above a misty autumn valley
  archmage     Theron Starweave         a mountaintop observatory: a brass telescope, a sky of stars, a meteor
  necromancer  Silas Graves             a misty moonlit graveyard, a crypt glowing green
  golem        Gorrak Stoneheart        an ancient mountain ruin: glowing blue runes, moss, a waterfall, floating stones
  dragoon      Kael Wyrmlance           a cliff-top aerie above a sea of clouds at sunset, torn red banners, a great nest
  duelist      Rafael Montclair         a palace terrace set for a duel: marble, red curtains, a chandelier, rose petals
  stormcaller  Torvald Stormcrown       a storm-swept peak: a ring of rune stones, lightning, rain
  musketeer    Armand Belleroc          a harbour fort at sunset: cannons, tall ships, blue-and-gold flags
  druid        Elowen Thornbloom        an enchanted grove: a giant glowing tree, standing stones, fireflies, flowers

godot/tools/build_champion_art.py writes the game's copies: godot/assets/ui/champions/<hid>.webp (the window's backdrop)
and cards/<hid>.webp (the Locker card's 3:4 crop round the open ground).
