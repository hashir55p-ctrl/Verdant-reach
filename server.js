// Verdant Reach online server — zero dependencies. Serves the game and relays
// player positions + voice-chat signalling between people in the same room code.
const http = require('http'), fs = require('fs'), path = require('path');
const PORT = process.env.PORT || 3000, PUB = __dirname, HIDDEN = new Set(['server.js','package.json','README.md','package-lock.json','accounts.json']), MAX = 8;
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


/* ---------- Google sign-in (optional): set GOOGLE_CLIENT_ID on the host ---------- */
const crypto = require('crypto'), https = require('https');
const GCID = process.env.GOOGLE_CLIENT_ID || '', DB_FILE = path.join(process.env.DATA_DIR || __dirname, 'accounts.json');
let DB = {secret: crypto.randomBytes(24).toString('hex'), users: {}};
try { DB = Object.assign(DB, JSON.parse(fs.readFileSync(DB_FILE, 'utf8'))); } catch (e) {}
let dbT = null; const saveDB = () => { clearTimeout(dbT); dbT = setTimeout(() => fs.writeFile(DB_FILE, JSON.stringify(DB), () => {}), 800); };
saveDB();
const b64u = b => Buffer.from(b).toString('base64url');
const mkTok = sub => { const b = b64u(JSON.stringify({s: sub, e: Date.now() + 90 * 864e5})); return b + '.' + crypto.createHmac('sha256', DB.secret).update(b).digest('base64url'); };
function tokUser(req) {
  const h = (req.headers.authorization || '').replace(/^Bearer /, ''), [b, sg] = h.split('.');
  if (!b || !sg) return null;
  const ok = crypto.createHmac('sha256', DB.secret).update(b).digest('base64url');
  if (sg.length !== ok.length || !crypto.timingSafeEqual(Buffer.from(sg), Buffer.from(ok))) return null;
  try { const t = JSON.parse(Buffer.from(b, 'base64url')); return t.e > Date.now() && DB.users[t.s] ? t.s : null; } catch (e) { return null; }
}
let certs = {t: 0, keys: []};
function getCerts(cb) {
  if (Date.now() - certs.t < 36e5 && certs.keys.length) return cb(null, certs.keys);
  https.get('https://www.googleapis.com/oauth2/v3/certs', r => { let d = ''; r.on('data', c => d += c); r.on('end', () => { try { certs = {t: Date.now(), keys: JSON.parse(d).keys || []}; cb(null, certs.keys); } catch (e) { cb(e); } }); }).on('error', cb);
}
function verifyGoogle(tok, cb) {
  const parts = String(tok).split('.'); if (parts.length !== 3) return cb(new Error('bad token'));
  let h, pl; try { h = JSON.parse(Buffer.from(parts[0], 'base64url')); pl = JSON.parse(Buffer.from(parts[1], 'base64url')); } catch (e) { return cb(e); }
  getCerts((err, keys) => {
    if (err) return cb(err);
    const k = keys.find(x => x.kid === h.kid); if (!k || h.alg !== 'RS256') return cb(new Error('no key'));
    const ok = crypto.verify('RSA-SHA256', Buffer.from(parts[0] + '.' + parts[1]), crypto.createPublicKey({key: k, format: 'jwk'}), Buffer.from(parts[2], 'base64url'));
    if (!ok || pl.aud !== GCID || !/^(https:\/\/)?accounts\.google\.com$/.test(pl.iss) || pl.exp * 1000 < Date.now() || !pl.sub) return cb(new Error('invalid'));
    cb(null, pl);
  });
}
function jsonBody(req, res, fn) {
  let b = ''; req.on('data', d => { b += d; if (b.length > 20000) req.destroy(); });
  req.on('end', () => { let m; try { m = JSON.parse(b || '{}'); } catch (e) { m = {}; } fn(m); });
}
const out = (res, code, o) => { res.writeHead(code, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'}); res.end(JSON.stringify(o)); };
const pub = u => ({name: u.name, picture: u.picture, profile: u.profile || null, bag: u.bag || null});
function auth(req, res, p) {
  if (p === '/auth/config') return out(res, 200, {clientId: GCID});
  if (p === '/auth/google' && req.method === 'POST') return jsonBody(req, res, m => {
    if (!GCID) return out(res, 503, {error: 'not configured'});
    verifyGoogle(m.credential, (e, pl) => {
      if (e) return out(res, 401, {error: 'invalid'});
      const u = DB.users[pl.sub] || (DB.users[pl.sub] = {created: Date.now()});
      u.name = String(pl.name || pl.given_name || 'Player').slice(0, 20); u.picture = String(pl.picture || '').slice(0, 300); u.last = Date.now(); saveDB();
      out(res, 200, Object.assign({token: mkTok(pl.sub)}, pub(u)));
    });
  });
  const sub = tokUser(req); if (!sub) return out(res, 401, {error: 'signed out'});
  const u = DB.users[sub];
  if (p === '/auth/me') return out(res, 200, pub(u));
  if (p === '/auth/save' && req.method === 'POST') return jsonBody(req, res, m => {
    if (m.profile && typeof m.profile === 'object') u.profile = m.profile;
    if (m.bag && typeof m.bag === 'object' && JSON.stringify(m.bag).length < 4000) u.bag = m.bag;
    saveDB(); out(res, 200, {ok: true});
  });
  out(res, 404, {});
}

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x'), p = u.pathname;
  if (p.startsWith('/auth/')) return auth(req, res, p);
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
