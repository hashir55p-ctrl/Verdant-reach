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
