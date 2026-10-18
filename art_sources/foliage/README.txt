The Rift's trees and bushes (0.31.173, Kevin: "I want better trees and bush models" -- all sixteen picked; "Use meshy
for the models").
summer_a/b.png, enchanted_a/b.png  concept sheets (ElevenLabs gpt-image-2): Summer -- oak, fir, birch, gnarled old tree;
                                   round leafy bush, flowering bush, fern clump, tall grass and reeds. Enchanted -- deep-green
                                   mossy tree, cherry blossom, glowing-fruit tree, autumn tree; red-berry bush, broad-leaf fern
                                   bush, glowing-flower grass, tall grass and reeds.
clean/<name>.png                   each plant redrawn alone on a plain ground by Meshy image-to-image (12 credits each);
                                   bush_berry2.png a higher three-quarter redraw for the berry bush (the first gave a slab).
meshy/<name>.glb                   Meshy image-to-3D (meshy-7.1, 30 credits each): trees at 6000 triangles, bushes and
                                   grasses at 3000 (at 800-2000 Meshy shreds leaves into shards). bush_berry from
                                   clean/bush_berry2.png at 6000 (its berries mostly lost; the fourth try).
                                   The inputs of godot/tools/foliage_prep.py (-> godot/assets/meshy/foliage/<name>.glb):
  tree_oak --height 5.0 --from 0.35       tree_mossy --height 5.0 --from 0.35     tree_fir --height 6.0 --from 0.25
  tree_birch --height 5.4 --from 0.35     tree_gnarled --height 5.0 --from 0.4    tree_blossom --height 4.6 --from 0.35
  tree_glow --height 5.0 --from 0.35 --glow 185,230,0.78,0.15                     tree_autumn --height 4.8 --from 0.35
  bush_round / bush_flower / bush_fern / bush_broadleaf --width 1.0 --tex 512     bush_berry --width 1.0 --tex 512 --tall 0.6
  grass_reeds / grass_tall --height 1.0 --tex 512                                 grass_glow --height 1.0 --tex 512 --glow 190,235,0.65,0.35
tasks/hi/<name>.task               the Meshy task of each model above (python3 godot/tools/meshy_weapon.py wait tasks/hi NAME
                                   fetches it again while Meshy keeps it).
tasks/far/<name>.task              the woods' light copies (assets/meshy/foliage/<tree>_far.glb): Meshy's first takes of
                                   oak, mossy, fir, birch and autumn at 2000 triangles (1.3-1.9k), prepped as their tree
                                   with --tex 512 (not kept here: fetch by task).
tasks/shadow/<name>.task           the trees' shadow copies (<tree>_shadow.glb): Meshy remesh of each model to 1000 triangles
                                   (meshy_weapon.py remesh tasks/hi NAME OUT --poly 1000; 5 credits each), prepped with
                                   --like meshy/<tree>.glb --shadow --tex 16 and the tree's own options (canopy pulled 7 % in,
                                   the trunk the remesh dropped taken back from the model). A remesh loses thin leaves and
                                   blades -- fine for a shadow, not for the plant itself.
Meshy credits for 0.31.173: 1374 (16 redraws + 1 for the berry bush; 16 first takes, 16 kept takes, 3 berry retries;
24 remeshes for the shadow copies and the lighter takes tried and not used).
