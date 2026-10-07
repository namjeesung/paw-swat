/* PAW Toy adapter. Official SDK contracts and offline test provenance:
   docs/v0.12.1/TOY-RANKING.md. No cloud saves or synthetic public rows.
   Board mapping and score encoding are persistent protocol: do not change them
   on an existing Toy without creating a new ranking season/protocol. */
(function (root) {
  'use strict';
  if (root.pawToy) return;
  const BOARDS = Object.freeze({ easy: 1, normal: 2, hard: 3, insane: 4 });
  const SCORE_BASE = 16777215;
  const cache = new Map(), flights = new Map(), submissions = new Map();
  const tickets = new Map();
  let nextTicket = 0, sdkPromise = null, profileCache = null;
  let blockedUntil = 0, rateFailures = 0;
  function failure(error) {
    const type = error && error.type;
    const code = error && error.code;
    if (code === 307044 || code === '307044') {
      rateFailures = Math.min(rateFailures + 1, 5);
      blockedUntil = Date.now() + Math.min(30000, 1000 * Math.pow(2, rateFailures));
      return { error: 'toy_rate_limited', retry_after: Math.ceil((blockedUntil - Date.now()) / 1000) };
    }
    if (type === 'not_logged_in' || code === -101) return { error: 'not_logged_in' };
    if (type === 'timeout') return { error: 'toy_timeout' };
    if (type === 'unsupported') return { error: 'toy_unavailable' };
    return { error: type === 'user_denied' ? 'toy_cancelled' : 'toy_network' };
  }
  function checkCooldown() {
    return Date.now() < blockedUntil ? { error: 'toy_rate_limited', retry_after: Math.ceil((blockedUntil - Date.now()) / 1000) } : null;
  }
  async function sdk() {
    if (root.toy) return root.toy;
    if (!sdkPromise) sdkPromise = new Promise((resolve, reject) => {
      // Load the official runtime, never a mock fallback or custom account.
      const script = root.document.createElement('script');
      script.src = 'https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js';
      script.async = true;
      script.onload = () => root.toy ? resolve(root.toy) : reject({ type: 'unsupported' });
      script.onerror = () => { sdkPromise = null; reject({ type: 'network_error' }); };
      root.document.head.appendChild(script);
    });
    return sdkPromise;
  }
  function bounded(promise, milliseconds = 12000) {
    let timer;
    return Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject({ type: 'timeout' }), milliseconds);
    })]).finally(() => clearTimeout(timer));
  }
  function boardOf(p) { return BOARDS[p.difficulty]; }
  function timeToScore(ms) {
    if (!Number.isInteger(ms) || ms < 1 || ms > SCORE_BASE) throw new Error('invalid_time');
    return SCORE_BASE - ms;
  }
  function scoreToTime(score) {
    if (!Number.isInteger(score) || score < 0 || score >= SCORE_BASE) throw new Error('invalid_score');
    return SCORE_BASE - score;
  }
  function normalizeProfile(raw) {
    // The current SDK wraps HTTP profile as {data:{face,uname,toyOpenId}};
    // official reference also documents the direct {nickname,avatar,...} shape.
    const p = raw && raw.data && typeof raw.data === 'object' ? raw.data : raw;
    if (!p || typeof p !== 'object') throw new Error('bad_profile');
    const nickname = typeof p.nickname === 'string' ? p.nickname : p.uname;
    const avatar = typeof p.avatar === 'string' ? p.avatar : p.face;
    if (typeof nickname !== 'string' || !nickname) throw new Error('bad_profile');
    // Do not expose toyOpenId in public UI, logs or analytics.
    return { nickname, avatar: typeof avatar === 'string' ? avatar : '' };
  }
  async function profile(force) {
    if (force) cache.clear();
    if (!force && profileCache) return Object.assign({ cached: true }, profileCache);
    const cooldown = checkCooldown(); if (cooldown) return cooldown;
    if (flights.has('profile')) return flights.get('profile');
    const task = (async () => {
      try {
        const api = await bounded(sdk());
        const raw = await bounded(api.getUserProfile());
        try { profileCache = normalizeProfile(raw); } catch (_) { return { error: 'toy_bad_response' }; }
        return profileCache;
      } catch (e) { profileCache = null; return failure(e); }
      finally { flights.delete('profile'); }
    })();
    flights.set('profile', task); return task;
  }
  async function board(p) {
    const id = boardOf(p); if (!id) return { error: 'toy_bad_response' };
    if (!p.force && cache.has(id)) return Object.assign({}, cache.get(id), { cached: true });
    const cooldown = checkCooldown(); if (cooldown) return cooldown;
    const key = 'board:' + id; if (flights.has(key)) return flights.get(key);
    const task = (async () => {
      try {
        const api = await bounded(sdk());
        const raw = await bounded(api.getRankList({ board: id, period: 'all', limit: Math.min(50, p.limit || 50) }));
        if (!Array.isArray(raw)) return { error: 'toy_bad_response' };
        const entries = [];
        try {
          for (const row of raw) {
            if (!row || !Number.isInteger(row.rank) || row.rank < 1 || typeof row.nickname !== 'string') throw new Error('bad_row');
            entries.push({ rank: row.rank, nickname: row.nickname, avatar: typeof row.avatar === 'string' ? row.avatar : '', time_ms: scoreToTime(row.score), me: false });
          }
        } catch (_) { return { error: 'toy_bad_response' }; }
        // Public rows do not contain a UID or Toy open ID. Only a confirmed own
        // rank may highlight our row; never compare nickname or invent IDs.
        let my = null;
        try { my = await bounded(api.getMyRank({ board: id, period: 'all' })); }
        catch (e) { if (e && e.code === 307044) failure(e); }
        if (my && my.ranked === true && Number.isInteger(my.rank) && Number.isInteger(my.score)) {
          const matching = entries.filter(row => row.rank === my.rank && row.time_ms === SCORE_BASE - my.score);
          if (matching.length === 1) matching[0].me = true;
        }
        const result = { entries, cached: false };
        cache.set(id, result); return result;
      } catch (e) { return failure(e); }
      finally { flights.delete(key); }
    })();
    flights.set(key, task); return task;
  }
  async function submit(p) {
    const id = boardOf(p); let score;
    if (!id || typeof p.run_id !== 'string') return { error: 'toy_bad_response' };
    try { score = timeToScore(p.time_ms); } catch (_) { return { error: 'toy_invalid_time' }; }
    const key = p.run_id;
    const previous = submissions.get(key);
    if (previous) {
      if (previous.board !== id || previous.score !== score) return { error: 'toy_bad_response' };
      if (previous.success) return previous.success;
      if (previous.promise) return previous.promise;
    }
    const cooldown = checkCooldown(); if (cooldown) return cooldown;
    const state = previous || { board: id, score, promise: null, success: null };
    submissions.set(key, state);
    state.promise = (async () => {
      try {
        const api = await bounded(sdk());
        // Do not time out / resend an outstanding submit: official SDK may be
        // waiting for a login dialog. All retries join this same promise.
        const result = await api.submitScore({ board: id, score });
        if (!result || !Number.isInteger(result.score) || result.score < score || result.score >= SCORE_BASE) return { error: 'toy_bad_response' };
        state.success = { ok: true, provider: 'toy', best_ms: scoreToTime(result.score) };
        cache.delete(id);
        return state.success;
      } catch (e) { return failure(e); }
      finally { state.promise = null; }
    })();
    return state.promise;
  }
  root.pawToy = {
    start(op, json) {
      const ticket = String(++nextTicket);
      let p; try { p = JSON.parse(json); } catch (_) { tickets.set(ticket, JSON.stringify({ error: 'toy_bad_response' })); return ticket; }
      let work;
      if (op === 'profile') work = profile(Boolean(p.force));
      else if (op === 'board') work = board(p);
      else if (op === 'submit') work = submit(p);
      else work = Promise.resolve({ error: 'toy_bad_response' });
      Promise.resolve(work).then(result => tickets.set(ticket, JSON.stringify(result)), e => tickets.set(ticket, JSON.stringify(failure(e))));
      return ticket;
    },
    poll(ticket) {
      const value = tickets.get(String(ticket));
      if (value === undefined) return '';
      tickets.delete(String(ticket)); return value;
    }
  };
})(window);
