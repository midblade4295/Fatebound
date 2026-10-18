The 5v5's menus in paint (0.31.175, Kevin: "Use eleven or meshy to make these menus better looking and more high
quality" -- the hero picker and the in-match shop). ElevenLabs gpt-image-2, medium quality, two takes each (_a, _b);
flow "Fatebound menus 0.31.175". 3,103 credits in all (the icon sheets 812 each at 2K, the hall 396 each, the armory
344 each -- the style references count toward the price).

icons_a.png, icons_b.png  3:2, 2K. Style references: the menus' own icons (godot/assets/ui/v2/icons/swords.png,
                          crown.png). godot/tools/build_menu_icons.py cuts the picked take of each icon (PICK there).
backdrop_a.png, _b.png    2:1, 1K: the champions' hall behind the picked hero (a used). Style reference: the Market
                          banner (godot/assets/ui/v2/art_shop.webp).
shop_a.png, _b.png        3:1, 1K: the keep's armory over the shop (a used). Same style reference.

Prompts:

icons -- Game UI asset sheet for a fantasy mobile game's item shop and hero select. Draw every icon in exactly the style
of the two reference icons: glossy chunky 3D-cartoon objects with a bold dark-brown outline, bright specular highlights,
rich saturated colours, like Clash Royale menu icons. Do not draw the reference icons themselves.
Layout: a landscape sprite sheet of 24 separate icons in an exact grid of 6 columns and 4 rows, evenly spaced, each icon
centred in its own cell with generous empty space around it, all on one plain flat pure white background (#FFFFFF). No
tiles, no frames, no boxes, no cast shadows on the background, and absolutely no text, letters or numbers anywhere.
Row 1 (basic items, simple and clean): (1) a steel long sword with a gold crossguard, pointing up-right; (2) a big
faceted red ruby crystal; (3) a short dagger with a leather-wrapped grip; (4) a pair of brown leather boots; (5) a blue
spell book with gold corners and a glowing rune on its cover; (6) a white vampire fang with a drop of red blood at its tip.
Row 2: (1) a small glowing green healing bead on a cord; (2) a padded quilted cloth armor vest; then the big items,
grander and more ornate with a soft golden glow: (3) golden winged swift boots; (4) a crimson greatsword with a red gem
in the hilt, dripping red; (5) a huge leather belt with a big gold buckle set with a ruby; (6) a ghostly purple-silver
blade trailing violet mist.
Row 3: (1) an ornate gold staff topped with a glowing purple crystal; (2) a green-and-gold breastplate covered in thorny
spikes; (3) a golden reliquary radiating warm holy light; (4) a pile of shiny gold coins; (5) a golden padlock; (6) a
small leather pouch spilling gold coins.
Row 4 (role badges: each a round metal badge filled with its own colour, a gold rim, and a bold white-and-gold symbol
in the middle): (1) blue badge with a big kite shield; (2) red badge with a crossed sword and axe; (3) purple badge with
a dagger over a crescent moon; (4) orange badge with a magic staff and a fiery orb; (5) green badge with a drawn bow and
arrow; (6) yellow badge with a heart under a golden halo.

backdrop -- A painted backdrop for a fantasy mobile game's hero select screen, in the same painterly style, palette and
warm lighting as the reference market banner (polished Supercell-style painting). Do not copy the reference's market
stall. Scene: a grand champions' hall inside a castle keep, seen from the front at eye level. In the left third, a round
stone dais with a gold rim, lit by a soft warm spotlight from above, empty and ready for a hero to stand on. Behind it,
carved stone pillars hung with blue-and-gold banners on the left and red-and-gold banners on the right, torches glowing
on the walls, a few drifting golden motes. The right half is calmer: a darker stone wall in soft shadow, with no bright
details, leaving room for text. No characters, no people, no creatures, no text or lettering.

shop -- A wide painted header banner for a fantasy mobile game's in-battle shop, in the same painterly style, palette and
warm lighting as the reference market banner (polished Supercell-style painting), but a different scene. Scene, seen
straight on: the armory inside a castle keep. A sturdy wooden counter across the bottom with stacks of gold coins, a
brass scale and a few glowing potion bottles (red, green, blue) on it; behind it, a stone wall with wooden racks of
swords, axes, spears and magic staffs, round shields with blue-and-gold heraldry, shelves of potions, hanging lanterns
giving a warm glow, a blue-and-gold banner at each end. Busy at the sides and calmer in the middle. No people, no text
or lettering.
