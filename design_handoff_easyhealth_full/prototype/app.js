/* ============================================================
   EasyHealth — app.js
   Roteador de telas + interações do protótipo
   ============================================================ */
(function () {
  var vp = document.getElementById('viewport');
  var tabbar = document.getElementById('tabbar');
  var fab = document.getElementById('fab');
  var toast = document.getElementById('toast');
  var screens = {};
  document.querySelectorAll('.screen').forEach(function (s) { screens[s.dataset.screen] = s; });

  var current = null;

  function show(name, opts) {
    opts = opts || {};
    var next = screens[name];
    if (!next) return;
    if (current) current.classList.remove('active');
    next.classList.add('active');
    next.scrollTop = 0;
    current = next;

    // chrome (tabbar + fab) visibility
    var chrome = next.dataset.chrome;
    var showChrome = chrome === 'full';
    tabbar.style.display = showChrome ? 'flex' : 'none';
    fab.style.display = (showChrome || name === 'active') ? 'grid' : 'none';

    // active tab highlight
    var tab = next.dataset.tab;
    tabbar.querySelectorAll('.tab').forEach(function (t) {
      t.classList.toggle('on', t.dataset.tabGo === tab);
    });

    // update hash without scroll jump
    if (!opts.noHash) history.replaceState(null, '', '#' + name);

    // per-screen hooks
    if (name === 'generating') runGenerating();
    if (name === 'done') fireConfetti();
    if (name === 'active') resetActive();
  }

  // ---- navigation via [data-go] ----
  document.addEventListener('click', function (e) {
    var go = e.target.closest('[data-go]');
    if (go) { show(go.dataset.go); return; }

    var tabGo = e.target.closest('[data-tab-go]');
    if (tabGo) { show(tabGo.dataset.target); return; }

    var tg = e.target.closest('[data-toast]');
    if (tg) { showToast(tg.dataset.toast); }

    var mt = e.target.closest('[data-mode-toggle]');
    if (mt && window.EHTheme) { window.EHTheme.toggleMode(); }
  });

  // ---- single / multi select option groups ----
  document.addEventListener('click', function (e) {
    var opt = e.target.closest('[data-val]');
    if (!opt) return;
    var single = opt.closest('[data-single]');
    var multi = opt.closest('[data-multi]');
    if (single) {
      single.querySelectorAll('[data-val]').forEach(function (o) { o.classList.remove('sel'); });
      opt.classList.add('sel');
    } else if (multi) {
      opt.classList.toggle('sel');
    }
  });

  // ---- sliders ----
  function bindSlider(id, vId, unit) {
    var el = document.getElementById(id), out = document.getElementById(vId);
    if (!el || !out) return;
    el.addEventListener('input', function () { out.innerHTML = el.value + '<em>' + unit + '</em>'; });
  }
  bindSlider('age', 'age-v', 'anos');
  bindSlider('wt', 'wt-v', 'kg');
  bindSlider('ht', 'ht-v', 'cm');

  // ---- toast ----
  var toastT;
  function showToast(msg) {
    toast.textContent = msg;
    toast.classList.add('show');
    clearTimeout(toastT);
    toastT = setTimeout(function () { toast.classList.remove('show'); }, 2200);
  }

  // ---- generating sequence ----
  function runGenerating() {
    var lines = document.querySelectorAll('#gen-steps .gen-ln');
    lines.forEach(function (l) { l.classList.remove('active', 'complete'); });
    var i = 0;
    function step() {
      if (i > 0) lines[i - 1].classList.add('complete');
      if (i >= lines.length) { setTimeout(function () { show('dashboard'); }, 450); return; }
      lines[i].classList.add('active');
      i++;
      setTimeout(step, 620);
    }
    step();
  }

  // ---- confetti ----
  function fireConfetti() {
    var c = document.getElementById('confetti');
    if (!c) return;
    c.innerHTML = '';
    var colors = ['#bff13d', '#2f6bff', '#ff6a3d', '#ffd23d', '#9b6bff', '#3ddc91'];
    for (var i = 0; i < 36; i++) {
      var s = document.createElement('i');
      s.style.left = Math.random() * 100 + '%';
      s.style.background = colors[i % colors.length];
      s.style.animationDelay = (Math.random() * 0.5) + 's';
      s.style.transform = 'rotate(' + (Math.random() * 360) + 'deg)';
      c.appendChild(s);
    }
  }

  // ---- detail screen: render exercise list ----
  var EXERCISES = [
    { n: 'Bench Press', m: 'chest', s: '4 séries · 10 reps' },
    { n: 'Clock Push-Up', m: 'chest', s: '4 séries · 10 reps' },
    { n: 'Chin-Up', m: 'back', s: '4 séries · 10 reps' },
    { n: 'Hyperextensions', m: 'back', s: '4 séries · 10 reps' },
    { n: 'Band Good Morning', m: 'legs', s: '4 séries · 10 reps' },
    { n: 'Good Morning (Pull)', m: 'legs', s: '4 séries · 10 reps' }
  ];
  function renderDetail() {
    var host = document.getElementById('detail-ex');
    if (!host) return;
    host.innerHTML = EXERCISES.map(function (ex) {
      return '<div class="wkt-row" style="margin-bottom:11px">' +
        '<div class="ex-photo" style="width:54px;height:54px;border-radius:11px;flex:none"><div class="ph"><svg viewBox="0 0 24 24" style="width:22px;height:22px"><path d="M6 8v8M18 8v8M3 10h3M18 10h3M6 12h12"/></svg></div></div>' +
        '<div class="info"><b style="font-size:15px">' + ex.n + '</b>' +
        '<div class="tags"><span class="tag-chip muscle">' + ex.m + '</span><span class="tag-chip">' + ex.s + '</span></div>' +
        '<div style="display:flex;gap:8px;margin-top:8px"><span class="ex-actions" style="display:contents"></span></div></div>' +
        '<span class="link" style="font-size:12.5px;align-self:flex-start">Trocar</span></div>';
    }).join('');
  }
  renderDetail();

  // ---- active workout: counters + set progression ----
  var state = { sets: 4, reps: 10, cur: 1, exIdx: 1 };
  function resetActive() {
    state = { sets: 4, reps: 10, cur: 1, exIdx: 1 };
    syncActive();
  }
  function syncActive() {
    setText('c-sets', state.sets);
    setText('c-reps', state.reps);
    setText('c-cur', state.cur);
    setText('ex-count', state.exIdx + '/6');
    var btn = document.getElementById('set-done');
    if (btn) btn.textContent = 'Feito — série ' + state.cur + '/' + state.sets;
    var bar = document.getElementById('ex-bar');
    if (bar) bar.style.width = (state.exIdx / 6 * 100) + '%';
  }
  function setText(id, v) { var el = document.getElementById(id); if (el) el.textContent = v; }

  document.addEventListener('click', function (e) {
    var inc = e.target.closest('[data-inc]'), dec = e.target.closest('[data-dec]');
    if (inc) { state[inc.dataset.inc] = Math.min(20, state[inc.dataset.inc] + 1); syncActive(); }
    if (dec) { var k = dec.dataset.dec; state[k] = Math.max(1, state[k] - 1); syncActive(); }
  });

  var EX_NAMES = ['Bench Press', 'Clock Push-Up', 'Chin-Up', 'Hyperextensions', 'Band Good Morning', 'Good Morning (Pull)'];
  var setBtn = document.getElementById('set-done');
  if (setBtn) {
    setBtn.addEventListener('click', function () {
      if (state.cur < state.sets) {
        state.cur++;
        syncActive();
        showToast('Série registrada · descanse 75s ⏱');
      } else if (state.exIdx < 6) {
        state.exIdx++; state.cur = 1;
        var nm = EX_NAMES[state.exIdx - 1];
        setText('ex-name', nm);
        syncActive();
        showToast('Próximo: ' + nm);
        if (current) current.scrollTop = 0;
      } else {
        show('done');
      }
    });
  }

  // ---- live clock in active timer ----
  var sec = 5;
  setInterval(function () {
    if (current && current.dataset.screen === 'active') {
      sec++;
      var m = String(Math.floor(sec / 60)).padStart(2, '0');
      var s = String(sec % 60).padStart(2, '0');
      setText('ex-clock', '⏱ ' + m + ':' + s);
    }
  }, 1000);

  // ---- appearance label sync ----
  window.addEventListener('themechange', function (e) {
    var lab = document.getElementById('appearance-label');
    if (lab) lab.textContent = e.detail.mode === 'dark' ? '☾ Modo escuro' : '☀ Modo claro';
  });

  // ---- statusbar time ----
  function tick() {
    var d = new Date();
    setText('sb-time', d.getHours() + ':' + String(d.getMinutes()).padStart(2, '0'));
  }
  tick(); setInterval(tick, 30000);

  // ---- boot: route from hash ----
  var initial = (location.hash || '').replace('#', '');
  var startMap = { onboarding: 'ob-goal', signup: 'ob-goal' };
  initial = startMap[initial] || initial;
  if (!screens[initial]) initial = 'dashboard';
  show(initial, { noHash: true });
})();
