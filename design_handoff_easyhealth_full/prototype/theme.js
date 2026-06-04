/* ============================================================
   EasyHealth — theme.js
   - Lê direção (a/b/c) e modo (light/dark) do localStorage
   - Aplica em <html data-dir data-mode>
   - Injeta um seletor flutuante de revisão (escondível)
   - Persiste a escolha entre todas as páginas
   ============================================================ */
(function () {
  var DIRS = {
    a: { name: "Voltagem", tag: "Atlético · neon", emoji: "⚡" },
    b: { name: "Lumen", tag: "Premium · azul", emoji: "◆" },
    c: { name: "Pulse", tag: "Amigável · vibrante", emoji: "✦" }
  };
  var KEY_DIR = "eh_dir", KEY_MODE = "eh_mode";

  function get(k, d) { try { return localStorage.getItem(k) || d; } catch (e) { return d; } }
  function set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  var dir = get(KEY_DIR, "a");
  var mode = get(KEY_MODE, "dark");
  if (!DIRS[dir]) dir = "a";

  var root = document.documentElement;
  function apply() {
    root.setAttribute("data-dir", dir);
    root.setAttribute("data-mode", mode);
    set(KEY_DIR, dir); set(KEY_MODE, mode);
    window.dispatchEvent(new CustomEvent("themechange", { detail: { dir: dir, mode: mode } }));
    syncUI();
  }

  // expõe para outras páginas / botões internos
  window.EHTheme = {
    get: function () { return { dir: dir, mode: mode }; },
    setDir: function (d) { if (DIRS[d]) { dir = d; apply(); } },
    setMode: function (m) { mode = m; apply(); },
    toggleMode: function () { mode = (mode === "dark" ? "light" : "dark"); apply(); },
    dirs: DIRS
  };

  // ---- seletor flutuante ----
  var bar, dots = {}, modeBtn;
  function buildUI() {
    if (document.getElementById("eh-switcher")) return;
    bar = document.createElement("div");
    bar.id = "eh-switcher";
    bar.innerHTML =
      '<button class="eh-sw-toggle" title="Comparar direções" aria-label="Comparar direções">' +
        '<span class="eh-sw-grip"></span></button>' +
      '<div class="eh-sw-panel">' +
        '<span class="eh-sw-label">Direção</span>' +
        '<div class="eh-sw-dirs">' +
          Object.keys(DIRS).map(function (k) {
            return '<button data-dir="' + k + '" class="eh-sw-dir">' +
              '<b>' + DIRS[k].emoji + ' ' + DIRS[k].name + '</b>' +
              '<small>' + DIRS[k].tag + '</small></button>';
          }).join("") +
        '</div>' +
        '<button class="eh-sw-mode" data-mode>Modo escuro</button>' +
      '</div>';
    document.body.appendChild(bar);

    bar.querySelector(".eh-sw-toggle").addEventListener("click", function () {
      bar.classList.toggle("open");
    });
    bar.querySelectorAll(".eh-sw-dir").forEach(function (b) {
      dots[b.getAttribute("data-dir")] = b;
      b.addEventListener("click", function () { window.EHTheme.setDir(b.getAttribute("data-dir")); });
    });
    modeBtn = bar.querySelector(".eh-sw-mode");
    modeBtn.addEventListener("click", function () { window.EHTheme.toggleMode(); });

    var css = document.createElement("style");
    css.textContent = SWITCHER_CSS;
    document.head.appendChild(css);
    syncUI();
  }

  function syncUI() {
    if (!bar) return;
    Object.keys(dots).forEach(function (k) {
      dots[k].classList.toggle("active", k === dir);
    });
    if (modeBtn) modeBtn.textContent = (mode === "dark" ? "☀ Tema claro" : "☾ Tema escuro");
  }

  var SWITCHER_CSS =
    '#eh-switcher{position:fixed;right:16px;bottom:16px;z-index:9999;font-family:"Hanken Grotesk",system-ui,sans-serif;display:flex;flex-direction:column;align-items:flex-end;gap:10px}' +
    '#eh-switcher .eh-sw-toggle{width:46px;height:46px;border-radius:999px;border:1px solid rgba(255,255,255,.18);background:#15181c;color:#fff;cursor:pointer;display:grid;place-items:center;box-shadow:0 10px 30px rgba(0,0,0,.4);transition:transform .2s}' +
    '#eh-switcher .eh-sw-toggle:hover{transform:translateY(-2px)}' +
    '#eh-switcher .eh-sw-grip{width:16px;height:16px;border-radius:5px;background:conic-gradient(from 0deg,#bff13d,#2f6bff,#ff6a3d,#bff13d)}' +
    '#eh-switcher .eh-sw-panel{display:none;flex-direction:column;gap:8px;background:#15181c;color:#fff;border:1px solid rgba(255,255,255,.14);border-radius:16px;padding:12px;width:210px;box-shadow:0 18px 50px rgba(0,0,0,.5)}' +
    '#eh-switcher.open .eh-sw-panel{display:flex}' +
    '#eh-switcher .eh-sw-label{font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:#8a93a0;font-weight:700}' +
    '#eh-switcher .eh-sw-dirs{display:flex;flex-direction:column;gap:6px}' +
    '#eh-switcher .eh-sw-dir{text-align:left;border:1px solid rgba(255,255,255,.1);background:transparent;color:#cfd6df;border-radius:11px;padding:8px 10px;cursor:pointer;transition:all .15s}' +
    '#eh-switcher .eh-sw-dir b{display:block;font-size:13px;color:#fff;font-weight:700}' +
    '#eh-switcher .eh-sw-dir small{font-size:11px;color:#8a93a0}' +
    '#eh-switcher .eh-sw-dir:hover{border-color:rgba(255,255,255,.28)}' +
    '#eh-switcher .eh-sw-dir.active{background:linear-gradient(90deg,rgba(191,241,61,.16),rgba(47,107,255,.14));border-color:rgba(255,255,255,.4)}' +
    '#eh-switcher .eh-sw-mode{margin-top:2px;border:none;background:rgba(255,255,255,.08);color:#fff;border-radius:11px;padding:9px;cursor:pointer;font-size:12.5px;font-weight:600;font-family:inherit}' +
    '#eh-switcher .eh-sw-mode:hover{background:rgba(255,255,255,.16)}' +
    '@media print{#eh-switcher{display:none}}';

  apply();
  if (document.body) buildUI();
  else document.addEventListener("DOMContentLoaded", buildUI);
})();
