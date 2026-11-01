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
- Avatars are built from primitive geometry in `makeAvatar(pf)`. A player profile is a small object (`n`, `g`, `sk`, `ha`, `st`, `tp`, `tc`, `bt`, `bc`, `sh`, `gl`, `bp`, `bd`, `bl`, `ht`) sanitised by `cleanProf`; add new fields to `DEF`/`LEN` there so old saved profiles and remote peers stay valid.
- Player state is sent about 10 times a second as `[x, y, z, yaw, hours, t0, gestureId]`; the server keeps the first 7 entries. The host (smallest `t0`) controls time of day.
- Voice is a WebRTC audio mesh signalled through the same relay (`sig` messages). Remote volume falls off with distance.
- After changing `index.html`, commit; Render redeploys automatically. Installed copies may need to be closed and reopened to pick up the new version.

## Ideas not built yet
Map ping / "meet here", follow-a-friend, text chat, collectibles, hide and seek, weather, saved rooms, TURN server for voice on strict networks.
