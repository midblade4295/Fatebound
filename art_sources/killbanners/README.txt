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
