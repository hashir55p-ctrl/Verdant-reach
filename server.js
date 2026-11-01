// Verdant Reach online server — zero dependencies. Serves the game and relays
// player positions + voice-chat signalling between people in the same room code.
const http = require('http'), fs = require('fs'), path = require('path');
const PORT = process.env.PORT || 3000, PUB = __dirname, HIDDEN = new Set(['server.js','package.json','README.md','package-lock.json']), MAX = 8;
const MIME = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json','.webmanifest':'application/manifest+json','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon'};
const rooms = new Map(); // code -> Map(id -> {res, p, s})
const clean = (v, n) => String(v || '').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, n);
function sse(res, obj) { res.write('data: ' + JSON.stringify(obj) + '\n\n'); }
function others(room, id, obj) { for (const [k, c] of room) if (k !== id) sse(c.res, obj); }

function events(req, res, q) {
  const code = clean(q.get('room'), 16), id = clean(q.get('id'), 12);
  let prof = {}; try { prof = JSON.parse(q.get('p') || '{}'); } catch (e) {}
  if (!code || !id) { res.writeHead(400); return res.end(); }
  res.writeHead(200, {'Content-Type':'text/event-stream','Cache-Control':'no-cache, no-transform','Connection':'keep-alive','X-Accel-Buffering':'no'});
  let room = rooms.get(code); if (!room) rooms.set(code, room = new Map());
  const old = room.get(id);
  if (!old && room.size >= MAX) { sse(res, {t:'full'}); return res.end(); }
  if (old) { try { old.res.end(); } catch (e) {} }
  const me = { res, p: prof, s: null };
  room.set(id, me);
  sse(res, {t:'welcome', players: [...room].filter(([k]) => k !== id).map(([k, c]) => ({id: k, p: c.p, s: c.s}))});
  others(room, id, {t:'join', id, p: prof});
  const ka = setInterval(() => res.write(': ka\n\n'), 15000);
  req.on('close', () => {
    clearInterval(ka);
    if (room.get(id) === me) { room.delete(id); others(room, id, {t:'leave', id}); if (!room.size) rooms.delete(code); }
  });
}

function send(req, res, q) {
  const code = clean(q.get('room'), 16), id = clean(q.get('id'), 12);
  let body = '';
  req.on('data', d => { body += d; if (body.length > 8192) req.destroy(); });
  req.on('end', () => {
    res.writeHead(204); res.end();
    const room = rooms.get(code); if (!room || !room.has(id)) return;
    let m; try { m = JSON.parse(body); } catch (e) { return; }
    if (m.t === 's' && Array.isArray(m.s) && m.s.length >= 4) {
      const s = m.s.slice(0, 9).map(Number); room.get(id).s = s; others(room, id, {t:'s', id, s});
    } else if (m.t === 'ev') {
      const d = m.d && JSON.stringify(m.d).length < 600 ? m.d : null; if (!d) return;
      const to = m.to ? clean(m.to, 12) : '';
      if (to) { const t = room.get(to); if (t) sse(t.res, {t:'ev', from: id, d}); }
      else others(room, id, {t:'ev', from: id, d});
    } else if (m.t === 'sig') {
      const to = clean(m.to, 12), t = room.get(to);
      if (t) sse(t.res, {t:'sig', from: id, to, d: m.d});
    }
  });
}

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x'), p = u.pathname;
  if (p === '/events') return events(req, res, u.searchParams);
  if (p === '/send' && req.method === 'POST') return send(req, res, u.searchParams);
  if (p === '/healthz') { res.writeHead(200); return res.end('ok'); }
  const f = path.normalize(path.join(PUB, p === '/' ? 'index.html' : p));
  if (!f.startsWith(PUB) || HIDDEN.has(path.basename(f)) || path.dirname(f) !== PUB) { res.writeHead(403); return res.end(); }
  fs.readFile(f, (e, d) => {
    if (e) { res.writeHead(404); return res.end('Not found'); }
    res.writeHead(200, {'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': p === '/sw.js' ? 'no-cache' : 'public, max-age=300'});
    res.end(d);
  });
}).listen(PORT, () => console.log('Verdant Reach online on :' + PORT));
