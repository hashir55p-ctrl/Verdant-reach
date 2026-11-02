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
- Voice is a WebRTC audio mesh signalled through the same relay (`sig` messages). Remote volume falls off with distance.
- After changing `index.html`, commit; Render redeploys automatically. Installed copies may need to be closed and reopened to pick up the new version.

## World (v2 big world)
- Island radius `R=520`, terrain `SIZE=1200`. Regions: Sunscar Desert, Mistmarsh swamp, Frostfields (see `DESERT`, `SWAMP`, `FROST`, `zoneW`), two rivers (`RIVERS`), flat building `SITES` (towns, ruins, camp, lighthouse) that `heightAt` flattens.
- `heightRaw` is the terrain; `heightAt` adds the flat sites. Everything in the world must be deterministic (seeded `rand`, `hn`) so all players see the same world; animals and birds move on clock-based loops for the same reason.
- Buildings/props are merged into a few meshes with the `Mesher` class (keep draw calls low for phones). Debug helpers on `window.__verdant`: `fly`, `look`, `dbg`.

## Items, bag, accounts
- Items/fruit/bag module sits just before `extrasTick` in `index.html` (`ITEMS`, `bag`, `grab`, `syncHeld`, `itemGesture`). Small animals (`small:true`) can be picked up. Bag is saved in localStorage `vr.bag`.
- Camp/fish module (after the items module): `buildFire`/`makeCampfire` (3 sticks, 15 min, synced by `ev` fire), `COOK` map, `castNow`/`reelIn` fishing (rod id 29, fish ids 50-57, cooked 60-62), animals log `bag.an`, swimming fish instanced mesh. Sounds: `critter`, `stepSnd`, sea waves in the audio section.
- Optional Google sign-in: set env `GOOGLE_CLIENT_ID` on the host (Web client ID, authorised origin = site URL). `/auth/config`, `/auth/google`, `/auth/me`, `/auth/save` in `server.js`; accounts stored in `accounts.json` (set `DATA_DIR` to a persistent disk; free Render disk is ephemeral).

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
