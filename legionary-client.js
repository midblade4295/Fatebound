/* Fatebound Play build trigger */
/* Fatebound → SSH host https://136-113-125-3.sslip.io/fatebound */
(function () {
  const SERVER = (window.LEGIONARY_SERVER || "https://136-113-125-3.sslip.io/fatebound").replace(/\/$/, "");
  const PLAYER_ID_KEY = "shardfall.playerId";
  const SAVE_KEY = "fatebound-save";
  const OLD_SAVE_KEY = "dice-skirmish-save";

  window.Legionary = { ready: false, uid: null, playerId: null, lastError: null, server: SERVER };

  function playerId() {
    let id = null;
    try { id = localStorage.getItem(PLAYER_ID_KEY); } catch (e) {}
    if (!id) {
      const abc = "23456789ABCDEFGHJKMNPQRSTVWXYZ";
      const block = (n) =>
        Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => abc[b % abc.length]).join("");
      id = "SF-" + block(4) + "-" + block(4);
      try { localStorage.setItem(PLAYER_ID_KEY, id); } catch (e) {}
    }
    return id;
  }

  function localSaveRaw() {
    try {
      return localStorage.getItem(SAVE_KEY) || localStorage.getItem(OLD_SAVE_KEY);
    } catch (e) {
      return null;
    }
  }

  async function serverPull(pid) {
    const res = await fetch(SERVER + "/api/save?playerId=" + encodeURIComponent(pid), { cache: "no-store" });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error("server GET " + res.status);
    const j = await res.json();
    return j && j.save ? j.save : null;
  }

  async function serverPush(pid, raw) {
    if (!raw) return false;
    const res = await fetch(SERVER + "/api/save", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ playerId: pid, save: raw }),
    });
    if (!res.ok) throw new Error("server POST " + res.status);
    return true;
  }

  async function boot() {
    const pid = playerId();
    window.Legionary.playerId = pid;
    window.Legionary.ready = true;
    try {
      const cloud = await serverPull(pid);
      const raw = localSaveRaw();
      if (cloud && !raw) {
        localStorage.setItem(SAVE_KEY, typeof cloud === "string" ? cloud : JSON.stringify(cloud));
      }
    } catch (e) {
      window.Legionary.lastError = String(e && e.message ? e.message : e);
    }
    async function pushCloud() {
      try { await serverPush(pid, localSaveRaw()); } catch (e) {
        window.Legionary.lastError = String(e && e.message ? e.message : e);
      }
    }
    let t = null;
    const orig = localStorage.setItem.bind(localStorage);
    localStorage.setItem = function (k, v) {
      orig(k, v);
      if (k === SAVE_KEY || k === OLD_SAVE_KEY) {
        clearTimeout(t);
        t = setTimeout(pushCloud, 1500);
      }
    };
    pushCloud();
  }

  boot().catch((e) => {
    window.Legionary.lastError = String(e && e.message ? e.message : e);
  });
})();
