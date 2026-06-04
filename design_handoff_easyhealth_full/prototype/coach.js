/* ============================================================
   EasyHealth Pro — Coach EasyHealth (agente conversacional)
   Folha que sobe, IA real (window.claude), contexto por tela,
   troca de exercício aplicada direto na execução.
   ============================================================ */
(function () {
  var I = EH.icon;
  var $ = function (id) { return document.getElementById(id); };

  var ICON_CLOSE = '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>';
  var ICON_SEND = '<svg viewBox="0 0 24 24"><path d="M5 12h13M12 5l7 7-7 7"/></svg>';

  /* ---------- estado ---------- */
  var sheet, scrim, body, input, sendBtn, quick, ctxBar;
  var history = [];          // {role, text} dos turnos reais
  var busy = false;
  var lastAlts = null;       // alternativas mostradas por último (p/ aplicar)

  /* ---------- montagem ---------- */
  function el(html) { var d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstChild; }

  function build() {
    scrim = $('coach-scrim'); sheet = $('coach-sheet');
    body = $('coach-body'); input = $('coach-text'); sendBtn = $('coach-send');
    quick = $('coach-quick'); ctxBar = $('coach-ctx');
    if (!sheet) return false;

    $('coach-close').addEventListener('click', close);
    scrim.addEventListener('click', close);
    sendBtn.addEventListener('click', function () { submit(); });
    input.addEventListener('input', autosize);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
    });
    return true;
  }
  function autosize() {
    input.style.height = 'auto';
    input.style.height = Math.min(92, input.scrollHeight) + 'px';
    sendBtn.disabled = !input.value.trim() || busy;
  }

  /* ---------- abrir / fechar ---------- */
  function currentScreen() {
    var s = document.querySelector('.screen.active');
    return s ? s.dataset.screen : 'dashboard';
  }
  function open(opts) {
    opts = opts || {};
    scrim.classList.add('show');
    sheet.classList.add('show');
    renderContextBadge();
    renderQuick();
    if (opts.intent === 'swap') {
      addMe('Quero outra opção pra esse exercício.');
      setTimeout(function () { askSwap(); }, 240);
    } else if (!history.length && !body.children.length) {
      greet();
    }
    setTimeout(function () { if (!opts.intent) input.focus(); scrollDown(); }, 360);
  }
  function close() {
    scrim.classList.remove('show');
    sheet.classList.remove('show');
    input.blur();
  }
  EH.openCoach = open;

  /* ---------- saudação por contexto ---------- */
  function greet() {
    var sc = currentScreen();
    var ctx = EH.execContext && EH.execContext();
    var msg;
    if (sc === 'exec' && ctx) {
      msg = 'Você está no <b>' + ctx.exercise.name + '</b>. Posso trocar por uma alternativa, ajustar a carga ou explicar a execução. O que precisa?';
    } else if (sc.indexOf('create') === 0 || sc === 'generating') {
      msg = 'Bora montar seu treino. Me diz seu objetivo, tempo disponível e o que quer focar — eu ajusto a estrutura pra você.';
    } else {
      msg = 'Sou seu Coach. Posso montar o treino de hoje, sugerir trocas, ler sua evolução ou tirar dúvidas de execução. Manda a real.';
    }
    addAI(msg);
  }

  /* ---------- ações rápidas por tela ---------- */
  function renderQuick() {
    var sc = currentScreen();
    var ctx = EH.execContext && EH.execContext();
    var chips;
    if (sc === 'exec' && ctx) {
      chips = [
        { t: 'Outra opção pra esse exercício', ic: 'swap', act: 'swap' },
        { t: 'Tá pesado demais', ic: 'flame', send: 'O ' + ctx.exercise.name + ' está pesado demais hoje. O que faço com a carga e as reps?' },
        { t: 'Como executar certo?', ic: 'info', send: 'Me explica a execução correta do ' + ctx.exercise.name + ' em 3 pontos.' }
      ];
    } else if (sc.indexOf('create') === 0 || sc === 'generating' || sc === 'plan' || sc === 'day') {
      chips = [
        { t: 'Treino de 30 min', ic: 'clock', send: 'Monta um treino eficiente de 30 minutos pra hoje, focado no meu objetivo.' },
        { t: 'Foca em peito hoje', ic: 'dumbbell', send: 'Quero focar em peito hoje. Que exercícios e séries você sugere?' },
        { t: 'Sem equipamento', ic: 'home', send: 'Hoje não tenho equipamento. Como adapto o treino?' }
      ];
    } else {
      chips = [
        { t: 'Como tá minha evolução?', ic: 'trendUp', send: 'Resumo da minha evolução nas últimas semanas, com base no meu perfil.' },
        { t: 'Treino de hoje', ic: 'bolt', send: 'O que eu treino hoje e por quê?' },
        { t: 'O que treino amanhã?', ic: 'calendar', send: 'O que está previsto pro meu treino de amanhã?' }
      ];
    }
    quick.innerHTML = chips.map(function (c, i) {
      return '<button class="coach-chip" data-qi="' + i + '">' + I(c.ic) + ' ' + c.t + '</button>';
    }).join('');
    quick._chips = chips;
  }
  document.addEventListener('click', function (e) {
    var c = e.target.closest('.coach-chip'); if (!c) return;
    var chip = quick._chips[parseInt(c.dataset.qi, 10)];
    if (!chip) return;
    if (chip.act === 'swap') { addMe('Quero outra opção pra esse exercício.'); askSwap(); }
    else if (chip.send) { addMe(chip.t); ask(chip.send); }
  });

  function renderContextBadge() {
    var ctx = EH.execContext && EH.execContext();
    if (ctx) {
      ctxBar.classList.add('show');
      ctxBar.innerHTML = '<span class="cdot"></span> Em foco: <b>' + ctx.exercise.name + '</b> · ' + ctx.exercise.muscle;
    } else {
      ctxBar.classList.remove('show'); ctxBar.innerHTML = '';
    }
  }

  /* ---------- render de mensagens ---------- */
  function fmt(t) {
    t = t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    t = t.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
    var parts = t.split(/\n{2,}/).map(function (p) { return '<p>' + p.replace(/\n/g, '<br>') + '</p>'; });
    return parts.join('');
  }
  function addAI(htmlText) {
    var m = el('<div class="coach-msg ai"><span class="coach-orb sm" aria-hidden="true"></span>' +
      '<div class="coach-bubble">' + fmt(htmlText) + '</div></div>');
    body.appendChild(m); scrollDown(); return m;
  }
  function addMe(text) {
    var m = el('<div class="coach-msg me"><div class="coach-bubble"></div></div>');
    m.querySelector('.coach-bubble').textContent = text;
    body.appendChild(m); scrollDown();
  }
  function addTyping() {
    var m = el('<div class="coach-msg ai" id="coach-typing"><span class="coach-orb sm think" aria-hidden="true"></span>' +
      '<div class="coach-bubble"><span class="typing"><i></i><i></i><i></i></span></div></div>');
    body.appendChild(m); scrollDown(); return m;
  }
  function rmTyping() { var t = $('coach-typing'); if (t) t.remove(); }
  function scrollDown() { requestAnimationFrame(function () { body.scrollTop = body.scrollHeight + 200; }); }

  /* ---------- envio manual ---------- */
  function submit() {
    var text = input.value.trim(); if (!text || busy) return;
    input.value = ''; autosize();
    addMe(text);
    // intenção de troca direto da caixa de texto (só na execução)
    var ctx = EH.execContext && EH.execContext();
    if (ctx && isSwapIntent(text)) { askSwap(); return; }
    ask(text);
  }
  function isSwapIntent(t) {
    t = t.toLowerCase();
    return /(outr[ao]\s+(op[çc][ãa]o|exerc|alternativa)|trocar?|substitu|alternativ|outro\s+exerc|n[ãa]o\s+gostei|enjoei)/.test(t);
  }

  /* ============================================================
     FLUXO DE TROCA DE EXERCÍCIO (cards aplicáveis)
     ============================================================ */
  function askSwap() {
    var ctx = EH.execContext && EH.execContext();
    if (!ctx) { ask('Quero uma alternativa pra um exercício.'); return; }
    var alts = EH.alternativesFor(ctx.exercise);
    lastAlts = alts;
    setBusy(true);
    var typing = addTyping();
    var prompt = buildSwapPrompt(ctx.exercise, alts);
    callAI(prompt).then(function (intro) {
      rmTyping();
      addAI(intro || introFallback(ctx.exercise));
      renderAltCards(alts);
      setBusy(false);
    }).catch(function () {
      rmTyping();
      addAI(introFallback(ctx.exercise));
      renderAltCards(alts);
      setBusy(false);
    });
  }
  function introFallback(exr) {
    return 'Separei 3 opções que mantêm o foco em <b>' + exr.muscle + '</b> e fazem sentido pro seu histórico. Toque numa pra trocar na hora — a tabela de séries se ajusta sozinha.';
  }
  function renderAltCards(alts) {
    var wrap = el('<div class="coach-msg ai"><span class="coach-orb sm" aria-hidden="true" style="visibility:hidden"></span><div class="alt-stack" id="alt-' + Date.now() + '"></div></div>');
    var stack = wrap.querySelector('.alt-stack');
    alts.forEach(function (a, i) {
      var tagCls = a.tag === 'fav' ? 'atag fav' : 'atag';
      var load = a.bodyweight ? 'peso corporal' : a.suggest + 'kg sugerido';
      var card = el(
        '<button class="alt-card" data-alt="' + a.id + '" style="animation-delay:' + (i * 0.06) + 's">' +
          '<span class="athumb">' + I(a.glyph || 'dumbbell') + '</span>' +
          '<span class="ainfo">' +
            '<span class="an">' + a.name + '</span>' +
            '<span class="areason">' + a.why + '</span>' +
            '<span class="ameta"><span class="' + tagCls + '">' + (EH.tagLabel[a.tag] || 'Sugestão') + '</span>' +
            '<span class="aload">' + a.sets + '×' + a.reps + ' · ' + load + '</span></span>' +
          '</span>' +
          '<span class="aapply">' + I('plus') + '</span>' +
        '</button>'
      );
      stack.appendChild(card);
    });
    body.appendChild(wrap); scrollDown();
  }
  document.addEventListener('click', function (e) {
    var card = e.target.closest('.alt-card'); if (!card || card.classList.contains('applied')) return;
    if (!lastAlts) return;
    var alt = lastAlts.filter(function (a) { return a.id === card.dataset.alt; })[0];
    if (!alt) return;
    var applied = EH.applySwap && EH.applySwap(alt);
    if (!applied) { addAI('Só consigo aplicar a troca durante um treino ativo. Abra a execução e tente de novo.'); return; }
    // marca o card escolhido e neutraliza os demais
    var stack = card.parentNode;
    stack.querySelectorAll('.alt-card').forEach(function (c) {
      if (c === card) { c.classList.add('applied'); c.querySelector('.aapply').innerHTML = I('check'); }
      else { c.style.opacity = '.45'; c.style.pointerEvents = 'none'; }
    });
    renderContextBadge();
    var load = alt.bodyweight ? 'peso corporal' : alt.suggest + 'kg sugerido';
    var conf = addAI('Feito ✅ Troquei por <b>' + alt.name + '</b> (' + load + '). Já atualizei a tabela de séries na tela.');
    var actions = el('<div style="margin-top:9px"><button class="btn btn-primary sm" id="coach-backtrain">Ver na tela do treino →</button></div>');
    conf.querySelector('.coach-bubble').appendChild(actions);
    scrollDown();
  });
  document.addEventListener('click', function (e) {
    if (e.target.closest('#coach-backtrain')) close();
  });

  /* botões que abrem o Coach com intenção (ex.: "Trocar" na execução) */
  document.addEventListener('click', function (e) {
    var t = e.target.closest('[data-coach]'); if (!t) return;
    var intent = t.getAttribute('data-coach');
    open(intent === 'swap' ? { intent: 'swap' } : {});
  });

  /* ============================================================
     CHAMADA À IA
     ============================================================ */
  function setBusy(b) { busy = b; sendBtn.disabled = b || !input.value.trim(); }

  function ask(text) {
    setBusy(true);
    var typing = addTyping();
    history.push({ role: 'user', text: text });
    callAI(buildChatPrompt(text)).then(function (ans) {
      rmTyping();
      ans = ans || 'Não consegui responder agora. Pode reformular?';
      history.push({ role: 'assistant', text: ans });
      addAI(ans);
      setBusy(false);
    }).catch(function () {
      rmTyping();
      var fb = fallbackAnswer(text);
      addAI(fb);
      setBusy(false);
    });
  }

  function persona() {
    return 'Você é o Coach EasyHealth, um personal trainer de IA dentro de um app de musculação. ' +
      'Tom técnico e objetivo, focado em dados e progressão de carga. Português do Brasil. ' +
      'Responda em no máximo 3 frases curtas e práticas. Cite carga, repetições, séries ou descanso quando ajudar. ' +
      'No máximo 1 emoji. Nada de títulos ou listas longas. Não invente lesões nem dados clínicos. ' +
      'Use **negrito** só pra destacar o essencial.\n\nPerfil do aluno: ' + EH.coachProfile();
  }
  function transcript() {
    return history.slice(-6).map(function (m) {
      return (m.role === 'user' ? 'Aluno' : 'Coach') + ': ' + m.text;
    }).join('\n');
  }
  function buildChatPrompt(text) {
    var ctx = EH.execContext && EH.execContext();
    var ctxLine = ctx ? '\nContexto: o aluno está executando "' + ctx.exercise.name + '" (' + ctx.exercise.muscle + '), série ' + ctx.set + ' de ' + ctx.exercise.sets + '.' : '\nTela atual: ' + currentScreen() + '.';
    return persona() + ctxLine + '\n\nConversa até agora:\n' + transcript() +
      '\n\nResponda à última mensagem do aluno de forma direta.';
  }
  function buildSwapPrompt(exr, alts) {
    var names = alts.map(function (a) { return a.name; }).join('; ');
    return persona() +
      '\n\nO aluno pediu uma ALTERNATIVA ao exercício "' + exr.name + '" (' + exr.muscle + '). ' +
      'O app vai mostrar estes cards logo abaixo da sua resposta: ' + names + '. ' +
      'Escreva APENAS 1 frase curta apresentando as opções e por que elas mantêm o estímulo — ' +
      'NÃO liste nem numere os exercícios, eles já aparecem nos cards.';
  }

  function callAI(prompt) {
    if (window.claude && typeof window.claude.complete === 'function') {
      return window.claude.complete({ messages: [{ role: 'user', content: prompt }] })
        .then(function (r) { return (typeof r === 'string' ? r : (r && r.text) || '').trim(); });
    }
    // sem API (preview offline) → resposta simulada coerente
    return new Promise(function (res) { setTimeout(function () { res(''); }, 650); });
  }

  /* ---------- respostas de reserva (offline) ---------- */
  function fallbackAnswer(text) {
    var ctx = EH.execContext && EH.execContext();
    if (ctx && /pesad|dif[íi]cil|n[ãa]o\s+aguent/.test(text.toLowerCase())) {
      return 'Tira <b>2kg</b> e busca fechar as reps com técnica limpa. Se ainda travar, reduz pra 8 reps e mantém o descanso de 75s — progressão é constância, não heroísmo.';
    }
    if (/execu|t[ée]cnic|como\s+faz/.test(text.toLowerCase()) && ctx) {
      return 'No <b>' + ctx.exercise.name + '</b>: pegada na largura dos ombros, desça controlando 2s, sem travar a lombar, e empurre expirando. Foque na contração, não no peso.';
    }
    if (/evolu|progress|carga/.test(text.toLowerCase())) {
      return 'Nas últimas 6 semanas seu supino subiu <b>+25%</b> e a aderência está em 88%. O ponto fraco é perna e core — o próximo ciclo vai pesar mais aí pra equilibrar.';
    }
    return 'Boa pergunta. Pra te dar a melhor resposta com dados, ative a conexão da IA — mas em geral: foque em **constância**, progressão gradual de carga e descanso de 60–90s entre séries pesadas.';
  }

  /* ---------- boot ---------- */
  function boot() {
    build();
    var fab = $('fab');
    if (fab) { fab.removeAttribute('data-toast'); fab.addEventListener('click', function () { open(); }); }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
