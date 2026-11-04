# Verdant Reach (Godot test)

A first Godot 4 test: realistic island (terrain, water, forest, rocks, grass),
day/night sky, and an explorer with hand-animated walk/run/jump.
No art files: everything is made in code.

## Open it in Xogot (iPad)
1. Unzip `verdant-godot.zip` in the Files app (tap the zip).
2. Open Xogot, choose Import / Open project, and pick the folder that contains `project.godot`.
3. Press Play.

## Controls
- Touch: left side = move stick, right side = drag to look, JUMP and RUN buttons.
- Keyboard: WASD, Shift run, Space jump, Q/E or arrows turn camera.

## Files
- `main.gd`  everything (world, player, controls) in one file. If Xogot asks for a scene: New Scene -> 3D Scene, attach main.gd to the root, save as main.tscn.



## Character (chars/)
- `chars/Verdant_Reach_Male_Explorer.glb` and `..._Female_...glb` are split into named body parts. `main.gd` hangs those parts on the walk/run/jump pivots.
- Tap STYLE (top right) to pick Male/Female and colours for skin, hair, top, pants, boots, eyes, scarf and backpack. Saved in user://look.cfg.

## Assets (assets/)
`assets/*.glb` is the starter asset pack (broadleaf and palm trees, bushes, rocks, cabin, cave). Models are Z-up so `_load_merged` rotates them to Y-up. The bridge, river and waterfall pieces are not used yet.

## Real-looking nature (assets/, generated from your maple/cypress textures, Quixel grass and animal models)
- `tree_maple_*.glb` (4 colours) and `tree_cypress_*.glb`: trunk + branches + leaf cards, built from the supplied bark/leaf/needle textures. They replace the ball and cone trees.
- `grass_*.glb`, `flower_*.glb`, `clover.glb`: real grass blades (thinned), placed per 40 m cell in `_build_meadow` (visible within 62 m).
- `animal_bull.glb` (decimated from 486k to 37k tris), `animal_skunk.glb`, `animal_egret.glb` (flying in circles), `animal_carp.glb` (swimming).
- Not used: Desert field (313 MB), the .blend files, FBX/OBJ trees (200 MB each), Fur Setting.

## Rigged characters (chars/char_boy.glb, char_girl.glb)
Built from Boy2.blend / FantasyGirl.blend (static T-pose meshes, 487k/498k verts, textures not packed): decimated to ~42k verts, auto-rigged (hips, spine, chest, neck, head, upperarm/forearm L/R, thigh/shin/foot L/R, weights by distance to bone segments) and exported as skinned GLB. `Player._apply_rig` copies the proxy-pivot animation onto the bones. Put the original textures in chars/ as Boy_02_basecolor.jpg, Boy_02_normal.jpg, Boy_02_roughness.jpg (and FantasyGirl_01_*).

## Online (friends + voice)
- Tap ONLINE (top left), type a name and a room code (or New room), tap Join. Friends use the same code.
- Needs the Verdant Reach server (Render) running the new server.js. The free server can take up to a minute to wake.
- Voice: Project Settings > Audio > Driver > Enable Input must be ON (then restart). The MIC button mutes you.
