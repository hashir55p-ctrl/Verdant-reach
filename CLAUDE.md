# Verdant Reach

A realistic 3D open-world browser game for 2–8 friends: character creator, room-code multiplayer, proximity voice chat, gestures, shared time of day, third-person camera, minimap and full map. Installable as a PWA (landscape).

Live: https://verdant-reach.onrender.com (Render, Node web service, free plan; may take ~30–50 s to wake).

## Layout (flat, repo root)
- `index.html` – the whole game (HTML + CSS + JS in one file). Uses local `three.min.js` (Three.js r128).
- `server.js` – zero-dependency Node server: serves the static files and a room relay over Server-Sent Events (`/events`, `/send`, `/healthz`). 8 players per room.
- `package.json` – `npm start` runs `node server.js`. Render: Build `echo ok`, Start `node server.js`.
- `manifest.webmanifest`, `sw.js`, icons – PWA install support. `sw.js` is network-first with cache fallback and skips `/events` and `/send`.
- `three.min.js` – Three.js r128.

## Rules for changes
- Keep it zero-dependency and flat: no build step, no subfolders (server.js only serves root-level files and hides server.js, package.json, README.md, package-lock.json).
- Avatars are built from primitive geometry in `makeAvatar(pf)`. A player profile is a small object (`n`, `g`, `sk`, `ha`, `st`, `tp`, `tc`, `bt`, `bc`, `sh`, `gl`, `bp`, `bd`, `bl`, `ht`, plus anime fields `sc` scarf, `cp` cloak, `fl` hair flower, `bo` boots, `gv` gloves, `ey` eye colour) sanitised by `cleanProf`; add new fields to `DEF`/`LEN` there so old saved profiles and remote peers stay valid.
- Player state is sent about 10 times a second as `[x, y, z, yaw, hours, t0, gestureId, heldCode]`; the server keeps the first 9 entries. One-off events (item taken, animal picked up, gift given) go as `{t:'ev'}` messages relayed by the server. The host (smallest `t0`) controls time of day.
- Voice is a WebRTC audio mesh signalled through the same relay (`sig` messages). Remote volume is full everywhere by default (menu button "Voice range" switches to nearby-only, where it falls off with distance; `voiceAll` in index.html).
- After changing `index.html`, commit; Render redeploys automatically. Installed copies may need to be closed and reopened to pick up the new version.

## World (v2 big world)
- Island radius `R=520`, terrain `SIZE=1200`. Regions: Sunscar Desert, Mistmarsh swamp, Frostfields (see `DESERT`, `SWAMP`, `FROST`, `zoneW`), two rivers (`RIVERS`), flat building `SITES` (towns, ruins, camp, lighthouse) that `heightAt` flattens.
- `heightRaw` is the terrain; `heightAt` adds the flat sites. Everything in the world must be deterministic (seeded `rand`, `hn`) so all players see the same world; animals and birds move on clock-based loops for the same reason.
- Buildings/props are merged into a few meshes with the `Mesher` class (keep draw calls low for phones). Debug helpers on `window.__verdant`: `fly`, `look`, `dbg`.

## Items, bag, accounts
- Items/fruit/bag module sits just before `extrasTick` in `index.html` (`ITEMS`, `bag`, `grab`, `syncHeld`, `itemGesture`). Small animals (`small:true`) can be picked up. Bag is saved in localStorage `vr.bag`.
- Camp/fish module (after the items module): `buildFire`/`makeCampfire` (3 sticks, 15 min, synced by `ev` fire), `COOK` map, `castNow`/`reelIn` fishing (rod id 29, fish ids 50-57, cooked 60-62), animals log `bag.an`, swimming fish instanced mesh. Sounds: `critter`, `stepSnd`, sea waves in the audio section.
- Optional Google sign-in: set env `GOOGLE_CLIENT_ID` on the host (Web client ID, authorised origin = site URL). `/auth/config`, `/auth/google`, `/auth/me`, `/auth/save` in `server.js`; accounts stored in `accounts.json` (set `DATA_DIR` to a persistent disk; free Render disk is ephemeral).

## Godot version relay (`/ws`)
- `server.js` also speaks WebSocket (hand-written RFC 6455, no dependency) at `/ws?room=CODE&id=ID` for the Godot game in `verdant-godot/` (kept outside this repo). Separate `gRooms` from the SSE web rooms, 8 per room.
- Text frames: client `{t:'p',p:{n,g,look}}` profile, `{t:'s',s:[x,y,z,yaw,swim,grounded,run]}` state; client `{t:'ev',d:{...}}` one-off events (items taken/dropped, animals picked up) relayed as `{t:'ev',id,d}`; server sends `hello` (you, tod, peers), `join`, `p`, `s`, `leave`, `time`, `full`. Binary frames = voice (16 kHz mono mu-law); the server relays them to the others as `[idLen][id][bytes]`.

## Ideas not built yet
Map ping / "meet here", follow-a-friend, text chat, collectibles, hide and seek, weather, saved rooms, TURN server for voice on strict networks.

## Graphics (realism pass)
- Post-processing (`post`, `postBuild`, `postRender`): FXAA, distance mist, god rays, colour grade, vignette, grain. Used in Balanced/Quality only; Performance renders directly.
- Terrain shader: world-space litter/moss/strata, faint distance-faded bump (keep strength low or it moirés). Extra `fill` light + stronger hemi lift shadows.
- Ferns (`rebuildFerns`), props module (logs, stumps, stones, river boulders, own seed 60606), dust motes. Use separate seeded RNGs for new content so existing worlds don't shift.

## Enterable houses
- `house()` builds hollow houses: walls with a door gap and glass windows (`run`/`wbox`), floor, ceiling, ajar door, furniture (bed, table, hearth, cupboard, crates, lantern). Swamp houses are on stilts with a walkable ramp.
- Collision: `HOUSES[].bx` oriented boxes `[lx,lz,hx,hz,isWall]` checked by `houseHit` (in `collide()` and for camera blocking in `camWall`). Floors/ramps: `FLOORS` + `floorAt`, folded into `deckAt`/`groundAt`.
- Interiors use their own RNG `hrng` and burn the old number of `rand()` calls so the rest of the world stays identical. `homeLight` is one warm point light that follows the player inside a house. Grass/ferns skip house footprints (`onHouse`).
- Not enterable yet: lighthouse, windmill, tents, ruins.

## Anime avatars
- `makeAvatar` uses `MeshToonMaterial` with a 4-step gradient (`avGrad`) and an inverted-hull black outline (`avOutline`, built in `avBuilder.flush`, one outline mesh per builder; materials with `userData.noOutline` are skipped; remote outlines hide beyond 42 m).
- Face: big layered eyes in groups `userData.eyes` (blink in `poseAvatar`), blush, tiny nose/mouth. Hair styles Messy/Wavy/Bob use tapered `avSpike`/tube locks. Explorer top = vest + bandolier + belt pouches; Cargo pants, boots, fingerless gloves, scarf, cloak, hair flower, richer backpack.
- Secondary motion: `userData.sec` groups (scarf tails, cloak) sway and trail backwards with speed; walk has bob, hip twist, lean and elbow bend; idle breathing.
- Creator has a Presets tab (Wanderer, Scout, Scholar, Survivor, Nomad, Forestborn, Artisan, Ranger). Keep new profile fields in `DEF`/`LEN` and in `FIELDS`.

## Doors and thrown items
- Doors: one `InstancedMesh` (`doorMesh`), each house has `H.door={a,t,...}`; `setDoor`/`toggleDoor`, swing animated in an `extraTick`, auto-closes after 40 s, event `{k:'door',h,o}`. Closed doors are collision/camera walls (`b[5]` in `houseHit`). Doors show as a Grab candidate ("Open door"/"Close door").
- Throwing: gesture 8 (key T) calls `throwHeld()` → `launch()` projectile (`shots`, gravity, drag, bounces, walls/trees via `shotSolid`, water sinks it). Thrower sends `{k:'thr'}` (others simulate the flight) and `{k:'put'}` when it comes to rest, which creates the pickable item. Aim preview line shows during wind-up.

## 360° view
- Eye button `#orbBtn` (key O) toggles `orb` orbit camera (`setOrbit`, `applyOrbit`): drag rotates around your character, wheel/pinch zooms, auto-spins after 2.5 s idle, any movement exits. Camera stays out of terrain and house walls.

## Crafting
- Fishing rod: 2 Sticks (20) + 1 Vine (30, new item scattered in forests, swamp and river banks with its own RNG 4711) via `craftRod()`; button appears in the bag on Stick/Vine/Rod. Rods can still be found lying near towns.

## Tree chopping, wood and tents
- Items: Axe 31, Log 32, Tent 33 (Stick 20, Vine 30, Stone 21). Generic crafting: `RECIPES` + `craft(id)` (rod = 2 Stick + 1 Vine; axe = 1 Stick + 1 Stone + 1 Vine; tent = 4 Log + 2 Vine). Bag shows a Craft button for any recipe the selected item takes part in.
- Chopping: Swing gesture (7) calls `chopTry()`; each tree has `id`, canopy/trunk instance (`cm/ci`, `tm/ti`). No axe: knocks up to 3 sticks off a tree. With axe: `hp` swings, then `fellTree` (hides instances, moves its `grid` collision entry to 1e9, falling-animation clone meshes, stump) and `spawnDrops` (logs + sticks via `dropItem` + `put` events). Event `{k:'fell',i,fx,fz}`. Trees regrow after ~7 min (`regrow`).
- Tents: `makeTent(uid,x,z,yaw,colour)` pushes a `HOUSES` entry with `tent:true`, `dead` flag (never spliced; every HOUSES loop skips `dead`). Placed with `placeTent()` (bag button), packed with Grab (`packTent`). Events `tent` / `tentx`. Tent and felled-tree state is session-only (late joiners do not see them).

## Vines, holding hands, geographic map
- Vines (item 30): ~500 per world (RNG 4711 forests/swamp/rivers, RNG 4712 extra 320 + 70 within 150 m of spawn); respawn 60 s after pickup (`takeItem`); swinging at a tree without an axe can drop a vine; felling drops 1-2 vines.
- Hold hands: Grab next to a remote player (`cand.pl`) → `takeHand`; `hand={mode:'lead'|'follow',id}`; event `{k:'hand',l:leader,f:follower,on}` is broadcast so everyone draws the link (`links`, cylinder meshes). Follower is steered toward the leader in `walk()` only when no joystick/keys; they release with the `handBtn` pill, Grab with nothing in reach, or if >16 m away. Leader can also let go.
- Map: `mapGeo` (1024 px, baked from the 512 `mapBase` plus relief shading, 7 m contour lines, shoreline, tree dots, buildings, site rings) is used by minimap and big map. Big map adds 200 m grid, legend, scale bar, tents (dynamic).

## Friends (scanned avatars) and jeeps
- Profile field `fr` (0 = custom, 1-4 = Stany, Renjith, Jesvin, Hashir; in `DEF`/`LEN`, picker field "Real friends" in the Presets tab). `makeAvatar` returns `makeFriend(pf)` when `fr>0`: a rigged GLB (`fr_<name>.glb`, ~1.9 MB, 1024 px texture, loaded on demand and cloned with `SkeletonUtils`). `poseAvatar` is a wrapper: it runs the original `poseAvatar0` on proxy Object3Ds (`userData.legs/arms/up/fore`) and `frPose` copies them to the bones (arms hang 80° from the T-pose). Shared geometry/textures are marked `userData.keep` so `freeRemote` does not dispose them. Needs `GLTFLoader.js` and `SkeletonUtils.js` (three r128 examples, root level).
- Jeeps: `car_body.glb`, `car_wheel.glb`, `car_door.glb` (Slate Studio exports, front = +z in the file, model group is rotated 180°). Three jeeps are placed at deterministic clear spots near spawn (`CARS`). Grab near one to drive (`enterCar`/`exitCar`, Grab or the Exit pill leaves). `stepCar` is a small bicycle-model: engine curve (about 95 km/h), drag, handbrake (Space/Jump), slope gravity, lateral grip with drift, tree/rock/house circles, water and steep-slope blocking, spring ride height, pitch/roll from the terrain. Chase camera in `driveWalk`; engine sound is two oscillators.
- Sync: no events. The state array has a 9th entry `(carId+1)*1000 + 100 + steer*100` while driving (0 otherwise); remote clients move that jeep under the driver (`r.drvCode`) and seat the avatar. A parked car stays where it was left only for the clients that saw it; late joiners see the default spots.

## Driving UI (BGMI style) and rigged fauna
- While driving, `body.drv` hides the walking controls and `#carUI` shows: steer ◀ ▶ (bottom-left), brake/reverse and accelerator pedals plus handbrake (P) and horn (bottom-right), "Get off" under the menu button, and an arc speed gauge. Buttons write to `dui` (multi-touch, pointer capture); keyboard W/S/A/D, arrows, Space (handbrake), H (horn) still work. Brake while rolling forward brakes, when stopped it reverses.
- Fauna module (just before "things to find"): `an_bull.glb`, `an_skunk.glb`, `an_egret.glb`, `an_carp.glb` (Slate meshes, rigged, baked clips). `GF` entries are spawned with `SkeletonUtils.clone` + `AnimationMixer`, driven only by `Date.now()` (same for all players, own RNG 5150): 5 bulls near Willowmere (walk / graze / idle cycle), 6 skunks in forests, 5 egrets that take off, circle, land, wade, strike and preen around shore spots, 14 carp circling in the lake at (125,-60). Not pick-up-able. Debug: `window.__fauna`.

## Swimming, egret flee, Call jeep
- Swimming: `swimSet(av,x,z,sp)` (called next to every `poseAvatar` for you and remotes) blends `U.swim` 0..1 when `heightAt < -0.8`; `swimPose` overrides limbs by speed: front crawl (>3.8), breaststroke, treading water when still; body lean via `av.rotation.x`, height offset via `po.oy`. Local only (derived from position/speed, no sync needed).
- Egret flee: in the egret ground phase of the fauna tick, anyone within 9 m (14 m if running) sets `f.fl`; the bird flies 60 m away, circles back and lands on its scheduled spot (25 s cooldown `f.fcd`). Local visual only.
- `#jeepBtn` ("Call jeep", top buttons) runs `callJeep()`: nearest free jeep is placed 8-18 m ahead on `carClear` ground; the button also shows direction/distance. Jeeps are yellow squares on the minimap and big map. Not synced to other players.
