/* ============================================================
   EasyHealth Pro — roteador + render + interações
   ============================================================ */
(function () {
  var I = EH.icon;
  var $ = function (id) { return document.getElementById(id); };
  var html = function (id, s) { var el = $(id); if (el) el.innerHTML = s; };

  /* -------- hidratar ícones [data-ic] -------- */
  function hydrateIcons(root) {
    (root || document).querySelectorAll('[data-ic]').forEach(function (el) {
      if (el.dataset.icDone) return;
      el.innerHTML = I(el.dataset.ic);
      el.dataset.icDone = '1';
      el.style.display = el.style.display || 'inline-flex';
    });
  }

  /* ============================================================
     ROTEADOR
     ============================================================ */
  var screens = {};
  document.querySelectorAll('.screen').forEach(function (s) { screens[s.dataset.screen] = s; });
  var current = null;
  var tabbar = $('tabbar'), fab = $('fab'), toast = $('toast');

  function show(name, opts) {
    opts = opts || {};
    var next = screens[name];
    if (!next) return;
    if (current) current.classList.remove('active');
    next.classList.add('active');
    next.scrollTop = 0;
    current = next;

    var chrome = next.dataset.chrome === 'full';
    tabbar.style.display = chrome ? 'flex' : 'none';
    // o Coach também fica disponível durante a execução do treino
    var showFab = chrome || name === 'exec';
    fab.style.display = showFab ? 'inline-flex' : 'none';
    fab.classList.toggle('on-exec', name === 'exec');

    var tab = next.dataset.tab;
    tabbar.querySelectorAll('.tab').forEach(function (t) { t.classList.toggle('on', t.dataset.tab === tab); });

    if (!opts.noHash) history.replaceState(null, '', '#' + name);

    if (name === 'generating') runGenerating();
    if (name === 'done') fireConfetti();
    if (name === 'exec') resetExec();
  }
  EH.show = show;

  /* -------- navegação global -------- */
  document.addEventListener('click', function (e) {
    var go = e.target.closest('[data-go]');
    if (go) { show(go.dataset.go); return; }
    var tab = e.target.closest('[data-target]');
    if (tab && tab.classList.contains('tab')) { show(tab.dataset.target); return; }
    var tg = e.target.closest('[data-toast]');
    if (tg) { showToast(tg.dataset.toast); }
  });

  /* -------- single / multi select -------- */
  document.addEventListener('click', function (e) {
    var opt = e.target.closest('[data-val]');
    if (!opt) return;
    var single = opt.closest('[data-single]'), multi = opt.closest('[data-multi]');
    if (single) {
      // ao escolher um método manual, desmarca o "IA decide"
      if (single.id === 'cm-methods') { var a = $('cm-auto'); if (a) { a.classList.remove('sel'); } }
      single.querySelectorAll('[data-val]').forEach(function (o) { o.classList.remove('sel'); });
      opt.classList.add('sel');
    } else if (multi) {
      opt.classList.toggle('sel');
    }
  });
  // botão "IA decide" reseta métodos manuais
  document.addEventListener('click', function (e) {
    if (e.target.closest('#cm-auto')) {
      $('cm-auto').classList.add('sel');
      var m = $('cm-methods'); if (m) m.querySelectorAll('[data-val]').forEach(function (o) { o.classList.remove('sel'); });
    }
  });

  /* -------- toast -------- */
  var toastT;
  function showToast(msg) {
    toast.textContent = msg; toast.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(function () { toast.classList.remove('show'); }, 2200);
  }

  /* ============================================================
     ÍCONES FIXOS
     ============================================================ */
  function fillIcons() {
    $('db-avatar').innerHTML = I('user');
    html('ic-brain', I('sparkles', 'x'));
    html('ic-flame', '<span style="color:var(--hot)">' + I('flame') + '</span>');
    html('ex-brain', I('sparkles'));
    html('dy-brain', I('sparkles'));
    html('done-brain', I('sparkles'));
    html('pd-brain', I('sparkles'));
    html('pr-brain', I('sparkles'));
    $('fab-ic').innerHTML = I('sparkles');
    html('cm-auto-ic', I('sparkles'));
    html('cm-auto-chk', I('check'));
    $('dy-fav').innerHTML = I('heart');
    $('dy-dup').innerHTML = I('copy');
    html('ex-clock-ic', I('clock'));
    $('ex-fav').innerHTML = I('heart');
    html('done-ic', '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" style="width:32px;height:32px"><path d="M20 6L9 17l-5-5"/></svg>');
    html('fv-ic', I('heart'));
    html('db-ready', I('bolt') + ' Pronto pra treinar');
    html('cg-arr', I('arrowR', 'inl'));
    html('ct-spark', I('sparkles', 'inl'));
    html('pl-pill', I('sparkles') + ' IA');
    html('hi-pill', I('sparkles') + ' Insights');
    html('pd-pill', I('sparkles') + ' IA');
    // back buttons
    ['cg-back', 'cp-back', 'cm-back', 'ct-back', 'dy-back', 'pd-back'].forEach(function (id) {
      var el = $(id); if (el) el.innerHTML = I('chevL', 'inl') + ' Voltar';
    });
    $('db-start').innerHTML = I('play') + ' Começar agora';
    $('db-create').innerHTML = I('refresh') + ' Refazer plano com a IA';
    $('pl-redo').innerHTML = I('refresh') + ' Refazer';
    $('dy-reorder').innerHTML = I('reorder') + ' Reorganizar';
    html('dy-add-ic', I('plus', 'inl'));
    // inline icon sizing
    document.querySelectorAll('svg.inl, svg.x').forEach(function (s) { s.style.width = '16px'; s.style.height = '16px'; s.style.verticalAlign = '-3px'; });
    // tab + small data-ic icons
    hydrateIcons();
    document.querySelectorAll('.tabbar .ti svg, .eachip svg, .metric .mk svg, .mtrend svg, .reason .ri svg, .in-plan-flag svg, .list-card .lic svg').forEach(function (s) {});
  }

  /* ============================================================
     DASHBOARD
     ============================================================ */
  function renderDashboard() {
    // week dots (S T Q Q S S D), 3 done, today=domingo(last)
    var days = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    var done = [true, true, false, true, false, false, false];
    var today = 6;
    html('db-week', days.map(function (d, i) {
      var cls = 'dot' + (done[i] ? ' done' : '') + (i === today ? ' today' : '');
      return '<div class="d"><span class="' + cls + '">' + (done[i] ? I('check') : '') + '</span><small>' + d + '</small></div>';
    }).join(''));

    html('db-insight', 'Bom te ver! Ontem você mandou bem no Lower. Hoje é <b>Upper · Força</b> — mantenha a carga do supino e tente <b>+1 repetição</b>. Você está a 1 treino da meta da semana.');

    // hoje + próximos
    var list = [
      { label: 'A', name: 'Upper · Força', sub: 'Hoje · 6 exercícios', go: 'day', muscles: ['peito', 'costas', 'ombro'], rest: false },
      { label: 'B', name: 'Lower · Força', sub: 'Amanhã · 5 exercícios', go: 'plan', muscles: ['quadríceps', 'posterior'], rest: false },
      { label: '·', name: 'Descanso ativo', sub: 'Qua · mobilidade 15 min', go: 'plan', muscles: [], rest: true }
    ];
    html('db-today-list', list.map(function (w) {
      return '<button class="wkt" data-go="' + w.go + '">' +
        '<span class="badge' + (w.rest ? ' rest' : '') + '">' + w.label + '</span>' +
        '<span class="info"><b>' + w.name + '</b><span class="sub">' + w.sub + '</span>' +
        (w.muscles.length ? '<span class="tags">' + w.muscles.map(function (m) { return '<span class="tag-chip muscle">' + m + '</span>'; }).join('') + '</span>' : '') +
        '</span><span class="gochev">' + I('chevR') + '</span></button>';
    }).join(''));
  }

  /* ============================================================
     CRIAR TREINO — opções
     ============================================================ */
  function optHTML(icon, title, sub, sel) {
    return '<button class="opt' + (sel ? ' sel' : '') + '" data-val="' + title + '">' +
      '<span class="oicon">' + I(icon) + '</span>' +
      '<span class="otxt"><b>' + title + '</b>' + (sub ? '<small>' + sub + '</small>' : '') + '</span>' +
      '<span class="chk">' + I('check') + '</span></button>';
  }
  function gridOptHTML(icon, title, sel) {
    return '<button class="opt' + (sel ? ' sel' : '') + '" data-val="' + title + '">' +
      '<span class="oicon">' + I(icon) + '</span>' +
      '<span class="otxt"><b>' + title + '</b></span>' +
      '<span class="chk">' + I('check') + '</span></button>';
  }
  function renderCreate() {
    html('cg-opts',
      optHTML('flame', 'Emagrecimento', 'Reduzir gordura corporal') +
      optHTML('dumbbell', 'Hipertrofia', 'Ganhar massa muscular', true) +
      optHTML('heart', 'Condicionamento', 'Fôlego e resistência') +
      optHTML('refresh', 'Recomposição', 'Perder gordura e ganhar músculo') +
      optHTML('shield', 'Saúde geral', 'Qualidade de vida') +
      optHTML('body', 'Mobilidade', 'Flexibilidade e articulações') +
      optHTML('bolt', 'Força', 'Levantar mais peso')
    );
    html('cp-place',
      optHTML('building', 'Academia', 'Aparelhos, barras e halteres', true) +
      optHTML('home', 'Casa', 'Pouco ou nenhum equipamento') +
      optHTML('tree', 'Ar livre', 'Parques, ruas e quadras')
    );
    html('cp-equip',
      gridOptHTML('dumbbell', 'Halteres', true) +
      gridOptHTML('band', 'Elásticos') +
      gridOptHTML('layers', 'Máquinas', true) +
      gridOptHTML('bike', 'Esteira / bike') +
      gridOptHTML('body', 'Sem equipamento') +
      gridOptHTML('zap', 'Kettlebell')
    );
    html('cm-methods',
      gridOptHTML('refresh', 'Tradicional') +
      gridOptHTML('layers', 'Full Body') +
      gridOptHTML('grid', 'ABC') +
      gridOptHTML('shuffle', 'Push/Pull/Legs') +
      gridOptHTML('bolt', 'Circuito') +
      gridOptHTML('body', 'Calistenia') +
      gridOptHTML('heart', 'Cardio') +
      gridOptHTML('rotate', 'Mobilidade')
    );
  }

  /* sliders */
  function bindSlider(id, vId, unit) {
    var el = $(id), out = $(vId); if (!el || !out) return;
    el.addEventListener('input', function () { out.innerHTML = el.value + '<em>' + unit + '</em>'; });
  }

  /* ============================================================
     GERANDO
     ============================================================ */
  function runGenerating() {
    var lines = document.querySelectorAll('#gen-steps .gen-ln');
    lines.forEach(function (l) { l.classList.remove('active', 'complete'); });
    var i = 0;
    (function step() {
      if (i > 0) lines[i - 1].classList.add('complete');
      if (i >= lines.length) { setTimeout(function () { show('plan'); }, 480); return; }
      lines[i].classList.add('active'); i++;
      setTimeout(step, 640);
    })();
  }

  /* ============================================================
     PLANO GERADO
     ============================================================ */
  function renderPlan() {
    var reasons = [
      { ic: 'layers', t: 'Escolhi <b>Upper / Lower</b> porque você quer hipertrofia treinando <b>4x por semana</b> — é a divisão que melhor distribui o volume nesse ritmo.' },
      { ic: 'heart', t: 'Mantive seus favoritos: <b>Supino reto</b> e <b>Puxada alta</b> entraram com prioridade no plano.' },
      { ic: 'trendUp', t: 'Seu histórico mostra evolução boa em peito e costas, então foquei em <b>progressão de carga</b> nesses grupos.' },
      { ic: 'shield', t: 'Como seu último Lower ficou incompleto, comecei com <b>volume moderado nas pernas</b> e subo aos poucos.' },
      { ic: 'calendar', t: 'Revisão automática em <b>6 semanas</b> — ou antes, se seu desempenho mudar bastante.' }
    ];
    html('pl-reasons', reasons.map(function (r) {
      return '<div class="reason"><span class="ri">' + I(r.ic) + '</span><div class="rt">' + r.t + '</div></div>';
    }).join(''));

    html('pl-week', EH.plan.days.map(function (d, idx) {
      return '<button class="daypill' + (idx === 0 ? ' sel' : '') + (d.rest ? ' rest' : '') + '" ' + (d.rest ? '' : 'data-go="day"') + '>' +
        '<div class="dn">' + d.short + '</div><div class="dl">' + d.label + '</div>' +
        '<div class="dm">' + (d.rest ? 'off' : d.exCount + ' ex') + '</div></button>';
    }).join(''));

    html('pl-days', EH.plan.days.filter(function (d) { return !d.rest || d.exCount > 0; }).map(function (d) {
      var muscles = d.focus.split(' · ');
      return '<button class="wkt" ' + (d.rest ? 'data-toast="Atividade leve de recuperação"' : 'data-go="day"') + '>' +
        '<span class="badge' + (d.rest ? ' rest' : '') + '">' + d.label + '</span>' +
        '<span class="info"><b>' + d.name + '</b><span class="sub">' + d.short + (d.rest ? '' : ' · ' + d.exCount + ' exercícios') + '</span>' +
        '<span class="tags">' + muscles.map(function (m) { return '<span class="tag-chip' + (d.rest ? '' : ' muscle') + '">' + m + '</span>'; }).join('') + '</span>' +
        '</span><span class="gochev">' + I('chevR') + '</span></button>';
    }).join(''));
  }

  /* ============================================================
     DETALHE DO DIA
     ============================================================ */
  function renderDay() {
    html('dy-note', 'Comece pelos compostos pesados (supino e remada) enquanto está descansado. O <b>core fica no fim</b> de propósito — não quero ele cansado antes dos grandes.');
    html('dy-ex', EH.dayExercises.map(function (ex, i) {
      return '<div class="exrow">' +
        '<div class="ethumb media-ph"><svg class="mglyph" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" style="width:22px;height:22px;margin:auto;position:absolute;inset:0">' + (EH._icons[ex.glyph] || EH._icons.dumbbell) + '</svg></div>' +
        '<div class="einfo"><b>' + ex.name + '</b><div class="es">' + ex.sets + ' séries · ' + ex.reps + (ex.bodyweight ? '' : ' · ' + ex.suggest + 'kg sugerido') + '</div>' +
        '<div class="chip-row" style="margin-top:6px"><span class="tag-chip muscle">' + ex.muscle + '</span>' + (ex.fav ? '<span class="tag-chip" style="color:var(--hot)">❤ favorito</span>' : '') + '</div></div>' +
        '<button class="efav' + (ex.fav ? ' on' : '') + '" data-favtoggle aria-label="Favoritar">' + I('heart') + '</button>' +
        '</div>';
    }).join(''));
  }

  /* favoritar inline */
  document.addEventListener('click', function (e) {
    var f = e.target.closest('[data-favtoggle]');
    if (f) { f.classList.toggle('on'); showToast(f.classList.contains('on') ? 'Adicionado aos favoritos ❤️' : 'Removido dos favoritos'); }
  });

  /* ============================================================
     EXECUÇÃO
     ============================================================ */
  var ex = { idx: 0, set: 1, load: 22, reps: 10, sec: 0, timer: null };
  var EXLIST = EH.dayExercises;
  function resetExec() {
    ex.idx = 0; ex.set = 1; ex.sec = 0;
    loadExercise(0); startClock();
  }
  function loadExercise(i) {
    var e = EXLIST[i]; ex.idx = i; ex.set = 1;
    ex.load = e.suggest; ex.reps = parseInt(e.reps, 10) || 10;
    $('ex-count').textContent = 'Exercício ' + (i + 1) + ' de ' + EXLIST.length;
    $('ex-name').textContent = e.name;
    $('ex-bar').style.width = ((i) / EXLIST.length * 100 + 8) + '%';
    $('ex-prev').textContent = e.bodyweight ? 'Peso corporal' : e.prev + ' kg';
    $('ex-sug').textContent = e.bodyweight ? '40s' : e.suggest + ' kg';
    $('ex-sug-tip').textContent = e.bodyweight ? 'segure firme' : (e.suggest > e.prev ? '+' + (e.suggest - e.prev) + 'kg · progressão' : 'mantenha e busque +1 rep');
    $('ex-map').querySelector('svg') && $('ex-map').querySelector('svg').remove();
    $('ex-map').insertAdjacentHTML('afterbegin', EH.bodyMap(e.muscle));
    $('ex-map-lab').textContent = e.muscle.toUpperCase();
    $('ex-media-lab').textContent = 'GIF · ' + e.name.toLowerCase();
    syncLoad(); renderSets();
  }
  function syncLoad() { $('ex-load').textContent = ex.load; $('ex-reps').textContent = ex.reps; }

  /* -------- hooks p/ o Coach EasyHealth -------- */
  EH.execContext = function () {
    if (!current || current.dataset.screen !== 'exec') return null;
    return { idx: ex.idx, total: EXLIST.length, exercise: EXLIST[ex.idx], set: ex.set };
  };
  EH.applySwap = function (alt) {
    if (!current || current.dataset.screen !== 'exec') return null;
    var old = EXLIST[ex.idx];
    // preserva o id/posição, herda os dados do novo exercício
    EXLIST[ex.idx] = Object.assign({}, alt, { id: old.id, fav: alt.fav != null ? alt.fav : false });
    loadExercise(ex.idx);
    showToast('Exercício trocado por ' + alt.name);
    return EXLIST[ex.idx];
  };
  function renderSets() {
    var e = EXLIST[ex.idx];
    var out = '';
    for (var s = 1; s <= e.sets; s++) {
      var cls = s < ex.set ? 'done' : (s === ex.set ? 'cur' : '');
      out += '<div class="set-line ' + cls + '"><span class="sn">' + s + '</span>' +
        '<span class="sval">' + (e.bodyweight ? ex.reps + 's' : ex.load + 'kg <em>× ' + ex.reps + '</em>') + '</span>' +
        (s < ex.set ? '<span class="sdone">' + I('check') + '</span>' : '') + '</div>';
    }
    html('ex-sets', out);
    var btn = $('set-done');
    if (ex.set > e.sets) btn.textContent = (ex.idx < EXLIST.length - 1) ? 'Próximo exercício →' : 'Finalizar treino →';
    else btn.textContent = 'Concluir série ' + ex.set + ' de ' + e.sets;
  }
  // steppers
  document.addEventListener('click', function (e2) {
    var inc = e2.target.closest('[data-inc]'), dec = e2.target.closest('[data-dec]');
    if (inc) { var k = inc.dataset.inc; ex[k] = Math.min(k === 'load' ? 300 : 30, ex[k] + (k === 'load' ? 2 : 1)); syncLoad(); renderSets(); }
    if (dec) { var k2 = dec.dataset.dec; ex[k2] = Math.max(k2 === 'load' ? 0 : 1, ex[k2] - (k2 === 'load' ? 2 : 1)); syncLoad(); renderSets(); }
  });
  // set done → progress / rest  (handler único)
  $('set-done').addEventListener('click', function () {
    var e = EXLIST[ex.idx];
    if (ex.set <= e.sets) {
      // concluindo a série atual
      ex.set++;
      renderSets();
      if (ex.set <= e.sets) { openRest(); }           // ainda há séries → descanso
      else { showToast('Exercício concluído 💪'); }    // foi a última série
    } else {
      // botão em estado "avançar"
      if (ex.idx < EXLIST.length - 1) { loadExercise(ex.idx + 1); if (current) current.scrollTop = 0; }
      else { show('done'); }
    }
  });

  /* rest timer */
  var restT, restLeft = 75;
  function openRest() {
    restLeft = 75; $('rest-sheet').classList.add('show');
    drawRestRing();
    clearInterval(restT);
    restT = setInterval(function () {
      restLeft--; drawRestRing();
      if (restLeft <= 0) { closeRest(); }
    }, 1000);
  }
  function drawRestRing() {
    var pct = Math.max(0, restLeft) / 75 * 100;
    var holder = $('rest-ring'), svg = holder.querySelector('svg');
    var ringHtml = EH.ring(pct, 200, 10, 'var(--primary)');
    if (svg) svg.outerHTML = ringHtml; else holder.insertAdjacentHTML('afterbegin', ringHtml);
    var t = $('rest-time'); if (t) t.textContent = Math.max(0, restLeft);
  }
  function closeRest() { clearInterval(restT); $('rest-sheet').classList.remove('show'); }
  $('rest-skip').addEventListener('click', closeRest);
  $('rest-add').addEventListener('click', function () { restLeft += 20; drawRestRing(); });

  function startClock() {
    clearInterval(ex.timer); ex.sec = 0;
    ex.timer = setInterval(function () {
      if (!current || current.dataset.screen !== 'exec') return;
      ex.sec++;
      var m = String(Math.floor(ex.sec / 60)).padStart(2, '0'), s = String(ex.sec % 60).padStart(2, '0');
      var cl = $('ex-clock'); if (cl) cl.innerHTML = I('clock') + ' ' + m + ':' + s;
    }, 1000);
  }

  /* ============================================================
     CONCLUÍDO
     ============================================================ */
  function renderDone() {
    var rows = [
      { n: 'Supino reto com barra', d: '22kg · 10,10,9,9 · ↑ carga' },
      { n: 'Remada curvada', d: '32kg · 10,10,10,8' },
      { n: 'Desenvolvimento de ombro', d: '14kg · 12,11,10' },
      { n: 'Puxada alta', d: '47kg · 12,12,11' }
    ];
    html('done-summary', rows.map(function (r, i) {
      return '<div style="display:flex;justify-content:space-between;align-items:center;padding:13px 0;' + (i < rows.length - 1 ? 'border-bottom:1px solid var(--border)' : '') + '">' +
        '<div><b style="font-size:14.5px">' + r.n + '</b><div class="dim" style="font-size:12px;margin-top:2px">' + r.d + '</div></div></div>';
    }).join(''));
  }
  function fireConfetti() {
    var c = $('confetti'); if (!c) return; c.innerHTML = '';
    var cols = ['var(--primary)', 'var(--good)', 'var(--warn)', 'var(--hot)', 'var(--cool)'];
    for (var i = 0; i < 40; i++) {
      var s = document.createElement('i');
      s.style.left = Math.random() * 100 + '%';
      s.style.background = cols[i % cols.length];
      s.style.animationDelay = (Math.random() * 0.6) + 's';
      s.style.transform = 'rotate(' + (Math.random() * 360) + 'deg)';
      c.appendChild(s);
    }
  }

  /* ============================================================
     PROGRESSO / HISTÓRICO
     ============================================================ */
  function renderHistory() {
    // bars
    var max = Math.max.apply(null, EH.weeklyFreq);
    html('hi-bars', EH.weeklyFreq.map(function (v, i) {
      var h = (v / max * 100);
      var muted = i < EH.weeklyFreq.length - 2 ? '' : '';
      return '<div class="bar"><div class="bcol' + (i === EH.weeklyFreq.length - 1 ? '' : ' ') + '" style="height:' + h + '%"></div><div class="blab">' + EH.weekLabels[i] + '</div></div>';
    }).join(''));
    // balance
    html('hi-balance', EH.muscleBalance.map(function (b) {
      return '<div class="mb"><span class="mbn">' + b.m + '</span><span class="mbt"><i class="' + (b.low ? 'low' : '') + '" style="width:' + b.v + '%"></i></span><span class="mbv">' + b.v + '</span></div>';
    }).join(''));
    // loads
    html('hi-loads', EH.loadProgress.map(function (l, i) {
      return '<button class="exprog" data-go="progress-detail" data-load="' + i + '">' +
        '<span class="epi"><b>' + l.name + '</b><span class="epm">' + l.muscle + ' · melhor ' + l.best + 'kg</span></span>' +
        '<span class="epspark">' + EH.sparkline(l.series, 72, 36) + '</span>' +
        '<span class="epval"><b>' + l.last + '<small style="font-size:12px;color:var(--text-dim)">kg</small></b><span>+' + l.deltaPct + '%</span></span>' +
        '</button>';
    }).join(''));
    // timeline
    var doneCount = EH.history.filter(function (h) { return h.done; }).length;
    $('hi-done').textContent = doneCount;
    $('hi-skip').textContent = EH.history.length - doneCount;
    html('hi-timeline', EH.history.map(function (h) {
      return '<div class="tl-item"><span class="tdot ' + (h.done ? 'done' : 'skip') + '">' + I(h.done ? 'check' : 'clock') + '</span>' +
        '<div class="tbody"><div class="tt"><b>' + h.name + '</b><span class="tdate">' + h.date + '</span></div>' +
        '<div class="tmeta">' + h.meta + '</div></div></div>';
    }).join(''));
  }
  // pane tabs
  document.addEventListener('click', function (e) {
    var b = e.target.closest('#hi-tabs button'); if (!b) return;
    $('hi-tabs').querySelectorAll('button').forEach(function (x) { x.classList.remove('on'); });
    b.classList.add('on');
    var pane = b.dataset.pane;
    document.querySelectorAll('[data-pane-body]').forEach(function (p) { p.style.display = p.dataset.paneBody === pane ? 'flex' : 'none'; });
  });
  // open load detail
  document.addEventListener('click', function (e) {
    var l = e.target.closest('[data-load]'); if (!l) return;
    renderProgressDetail(EH.loadProgress[parseInt(l.dataset.load, 10)]);
  });
  function renderProgressDetail(d) {
    if (!d) d = EH.loadProgress[0];
    $('pd-muscle').textContent = d.muscle.toUpperCase();
    $('pd-name').textContent = d.name;
    $('pd-last').textContent = d.last;
    $('pd-cur').innerHTML = d.last + '<small> kg</small>';
    $('pd-best').innerHTML = d.best + '<small> kg</small>';
    $('pd-delta').textContent = '+' + d.deltaPct + '%';
    html('pd-chart', EH.lineChart(d.series, 320, 150));
    html('pd-suggest', 'Na última vez você fez <b>' + d.last + 'kg</b>. Hoje tente <b>manter ' + d.last + 'kg e buscar 1 repetição a mais</b> em cada série. Se sair fácil, subimos pra ' + (d.last + 2) + 'kg no próximo.');
  }

  /* ============================================================
     FAVORITOS
     ============================================================ */
  function renderFavorites() {
    html('fv-ex', EH.favExercises.map(function (f) {
      return '<div class="wkt">' +
        '<span class="badge">' + I(f.glyph) + '</span>' +
        '<span class="info"><b>' + f.name + '</b><span class="tags" style="margin-top:6px"><span class="tag-chip muscle">' + f.muscle + '</span>' +
        (f.inPlan ? '<span class="in-plan-flag">' + I('check') + ' no plano atual</span>' : '') + '</span></span>' +
        '<button class="fav on" data-favtoggle>' + I('heart') + '</button></div>';
    }).join(''));
    // badge icons sizing
    document.querySelectorAll('#fv-ex .badge svg').forEach(function (s) { s.style.width = '20px'; s.style.height = '20px'; });
    html('fv-wk', EH.favWorkouts.map(function (w) {
      return '<button class="wkt" data-go="day"><span class="badge">' + I('layers') + '</span>' +
        '<span class="info"><b>' + w.name + '</b><span class="sub">' + w.meta + '</span>' +
        '<span class="tags" style="margin-top:6px">' + w.tags.map(function (t) { return '<span class="tag-chip">' + t + '</span>'; }).join('') + '</span></span>' +
        '<button class="fav on" data-favtoggle>' + I('heart') + '</button></button>';
    }).join(''));
    document.querySelectorAll('#fv-wk .badge svg').forEach(function (s) { s.style.width = '20px'; s.style.height = '20px'; });
  }

  /* ============================================================
     PERFIL
     ============================================================ */
  function renderProfile() {
    var p = EH.profile;
    html('pr-ring', EH.ring(p.readiness, 78, 7) + '<div class="rlabel"><b>' + p.readiness + '</b><span>pronto</span></div>');
    var dna = [
      { k: 'Objetivo', v: p.goal }, { k: 'Método', v: p.method }, { k: 'Nível', v: p.level },
      { k: 'Frequência', v: p.days + 'x / semana' }, { k: 'Local', v: p.place },
      { k: 'Idade · peso · altura', v: p.age + 'a · ' + p.weight + 'kg · ' + p.height + 'cm' }
    ];
    html('pr-dna', dna.map(function (a) {
      return '<div class="attr"><span class="ak">' + a.k + '</span><span class="av2"><span class="pip"></span>' + a.v + '</span></div>';
    }).join(''));
    var items = [
      { ic: 'globe', t: 'Idioma', v: '🇧🇷 Português' },
      { ic: 'moon', t: 'Aparência', v: 'Escuro' },
      { ic: 'card', t: 'Assinatura', v: 'Pro · ativa' },
      { ic: 'shield', t: 'Privacidade', v: '' },
      { ic: 'mail', t: 'Fale conosco', v: '' }
    ];
    html('pr-list', items.map(function (it) {
      return '<button class="li" data-toast="' + it.t + '"><span class="lic">' + I(it.ic) + '</span><span class="lt">' + it.t + '</span><span class="lv">' + it.v + '</span><span class="lic">' + I('chevR') + '</span></button>';
    }).join(''));
  }

  /* ============================================================
     RELÓGIO STATUS BAR
     ============================================================ */
  function tick() { var d = new Date(); $('sb-time').textContent = d.getHours() + ':' + String(d.getMinutes()).padStart(2, '0'); }

  /* ============================================================
     BOOT
     ============================================================ */
  fillIcons();
  renderDashboard();
  renderCreate();
  renderPlan();
  renderDay();
  renderHistory();
  renderProgressDetail(EH.loadProgress[0]);
  renderFavorites();
  renderProfile();
  renderDone();
  bindSlider('ct-days', 'ct-days-v', 'dias');
  bindSlider('ct-min', 'ct-min-v', 'min');
  hydrateIcons();
  tick(); setInterval(tick, 30000);

  var initial = (location.hash || '').replace('#', '');
  if (!screens[initial]) initial = 'dashboard';
  show(initial, { noHash: true });
})();
