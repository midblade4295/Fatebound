Kill banner and bounty concepts (for 0.31.180; Kevin: "Make banner in middle of screen when a player kills another
player. It'll show "name" has slain "name"" ... multi-kills, ACE, First Blood, Shutdown, League's bounty system --
"Give me concepts of each banner before implementing").
Phone screens (450 x 1000 logical, 2x) drawn as HTML/SVG over real 5v5 screenshots (0.31.179's HUD), with the game's
fonts (Luckiest Guy, Cinzel Black, Nunito), hero portraits and icons. mock.py makes them (playwright; its a/ folder:
the fonts, portraits, icons and backgrounds copied from godot/assets and a match).
  01_kill            a hero slain: killer and victim portraits on a gold-rimmed ribbon, "Midblade HAS SLAIN Bot Nora"
                     (names in their sides' colours; yours gold)
  02_kill_ally       the same between others (your side's names blue, the enemy's red)
  03_you_slain       you slain: the ribbon on red
  04_first_blood     a crimson swallowtail banner, a blood-drop medallion on crossed swords, FIRST BLOOD over the ribbon
  05_double          DOUBLE KILL in silver over a silver-rimmed banner, two skulls
  06_triple          TRIPLE KILL in gold, small wings, three skulls
  07_quadra          a golden crest: a shield with four skulls and a crown, laurels, QUADRA KILL across it
  08_penta           the biggest crest: rays, wings, laurels, a crown above five skulls, PENTAKILL; the screen's edges
                     tinted gold
  09_ace             ACE on a blue shield with silver wings; the five slain enemies' portraits; who struck the last blow
  10_shutdown        SHUTDOWN in fire over a dark banner, a cracked crown; the bounty paid (+1000: 300 kill + 700 bounty)
  11_bounty_board    the live board: a gold coin badge on a hero's portrait once his bounty is 150 or more (steps of 50)
  all.webp           all of them side by side

The game's art (0.31.180, Kevin: "I want the banner art created by eleven so they look more detailed. I also want
special effects on the kill streak and first blood ones"):
eleven/   ElevenLabs gpt-image-2, 1K, medium, one take each, style references the menus' crown and swords icons; flow
          "Fatebound kill banners 0.31.180". 5,645 credits (~$1.03): the plaques 730, the 2:1 banners 631 each, the
          crests 797 each. godot/tools/build_kill_banners.py cuts them into godot/assets/ui/banners/.
  plaques.png     two name plaques (navy, crimson) with a portrait socket at each end, no text
  first_blood.png crimson swallowtail, blood-drop medallion on crossed swords, "FIRST BLOOD"
  double.png      navy with silver trim and chevrons, two skulls, "DOUBLE KILL"
  triple.png      navy with gold trim and wings, three skulls, "TRIPLE KILL"
  quadra.png      gold-rimmed purple shield, four skulls, a crown, laurels, a crimson ribbon "QUADRA KILL"
  penta.png       jewelled crest, a big crown, five skulls, gold wings, laurels, a purple ribbon "PENTAKILL"
  ace.png         blue shield, silver wings, a star, "ACE"
  shutdown.png    scorched iron, broken gold trim, a cracked crown shedding coins, "SHUTDOWN"
  (Each prompt: "Game UI asset for a fantasy mobile MOBA: the <X> announcement banner, painted in exactly the style of
  the two reference icons: glossy chunky 3D-cartoon objects with a bold dark-brown outline, bright specular highlights
  and rich saturated colours, like Supercell / Clash Royale UI ... EXACT TEXT: <title> -- big chunky bold rounded
  game-title letters ... Plain flat pure white background (#FFFFFF) ... no shadow on the background, no glow, no
  rays, no scene." -- the full prompts are on the flow.)
sfx/      ElevenLabs, two takes each; flow "Fatebound kill banner sounds 0.31.180". ~333 credits: the eight
          eleven_text_to_sound_v2 cues (~120) and the Herald's take (eleven_v4, Edward, 214).
  kb_kill        "A short punchy fantasy video game UI banner slam: a quick metallic whoosh into a solid wood-and-steel
                 thump" (1.2 s)
  kb_first_blood "a deep resonant church-bell strike layered with a sharp sword being drawn and a low boom, then a
                 short ringing tail" (2.5 s)
  kb_double      "two quick ringing steel sword shings followed by a punchy brass stab" (1.5 s)
  kb_triple      "three fast rising steel sword shings into a bright brass hit with a cymbal splash" (1.8 s)
  kb_quadra      "A heroic short brass fanfare hit with pounding war drums and a big cymbal crash" (2.2 s)
  kb_penta       "soaring trumpets, a big choir swell and huge war drums, a celebration heard across the whole
                 battlefield" (4 s)
  kb_shutdown    "A golden crown shattering: a sharp metallic crack and break, then a shower of gold coins" (2.2 s)
  kb_ace         "A bright triumphant war horn call with a big drum hit and shimmering bells" (2.5 s)
  herald_<take>  "First blood!", "Shutdown!", "Ace!" (take 2 used)
          godot/tools/build_kill_sfx.py cuts, layers and levels them into godot/assets/sounds/kb_*.wav and the
          Herald's lines into godot/assets/vo/herald/kb_*.ogg.
