/* ============================================================
   EasyHealth Pro — Coach EasyHealth (dados do agente)
   Pool de exercícios alternativos por grupo muscular +
   configuração de contexto do agente.
   ============================================================ */
window.EH = window.EH || {};

/* ------------------------------------------------------------
   POOL DE ALTERNATIVAS
   Cada candidato é um exercício "pronto pra entrar" na execução.
   tag → motivo curado que aparece no card:
     fav    = está nos favoritos do Marcus
     foco   = mesmo estímulo do exercício atual
     equip  = encaixa no equipamento / local
     leve   = menor exigência articular
   ------------------------------------------------------------ */
EH.altPool = {
  peito: [
    { id: 'p1', name: 'Supino inclinado com halteres', muscle: 'peito', glyph: 'dumbbell', sets: 4, reps: '8–10', prev: 18, suggest: 20, best: 22, tag: 'foco', why: 'Mesmo padrão de empurrar, com mais amplitude na porção superior do peito.' },
    { id: 'p2', name: 'Crucifixo na máquina (peck deck)', muscle: 'peito', glyph: 'layers', sets: 3, reps: '12', prev: 35, suggest: 38, best: 42, tag: 'leve', why: 'Isola o peito poupando ombro e punho — bom se o supino estiver pesando na articulação.' },
    { id: 'p3', name: 'Flexão de braço', muscle: 'peito', glyph: 'body', sets: 4, reps: '12–15', prev: 0, suggest: 0, best: 0, bodyweight: true, tag: 'equip', why: 'Zero equipamento. Mantém o volume de peito se a barra estiver ocupada.' },
    { id: 'p4', name: 'Supino reto na máquina', muscle: 'peito', glyph: 'layers', sets: 4, reps: '10', prev: 40, suggest: 42, best: 46, tag: 'foco', why: 'Trajetória guiada — permite chegar perto da falha com segurança sozinho.' }
  ],
  costas: [
    { id: 'c1', name: 'Remada baixa no cabo', muscle: 'costas', glyph: 'layers', sets: 4, reps: '10–12', prev: 40, suggest: 42, best: 46, tag: 'foco', why: 'Mesma puxada horizontal da remada curvada, com tensão contínua e menos carga na lombar.' },
    { id: 'c2', name: 'Puxada alta pegada neutra', muscle: 'costas', glyph: 'layers', sets: 3, reps: '10–12', prev: 45, suggest: 47, best: 50, tag: 'fav', why: 'Variação do seu favorito (Puxada alta) com pegada mais confortável pro ombro.' },
    { id: 'c3', name: 'Remada cavalinho (T-bar)', muscle: 'costas', glyph: 'dumbbell', sets: 4, reps: '8–10', prev: 30, suggest: 32, best: 36, tag: 'foco', why: 'Foco no meio das costas e espessura — boa progressão de carga.' },
    { id: 'c4', name: 'Remada unilateral com halter', muscle: 'costas', glyph: 'dumbbell', sets: 3, reps: '10 cada', prev: 26, suggest: 28, best: 30, tag: 'leve', why: 'Trabalha um lado por vez e poupa a lombar — corrige assimetrias.' }
  ],
  ombro: [
    { id: 'o1', name: 'Elevação lateral com halteres', muscle: 'ombro', glyph: 'dumbbell', sets: 4, reps: '12–15', prev: 8, suggest: 9, best: 10, tag: 'foco', why: 'Isola a porção lateral do ombro — ótimo pra dar largura sem sobrecarregar.' },
    { id: 'o2', name: 'Desenvolvimento na máquina', muscle: 'ombro', glyph: 'layers', sets: 3, reps: '10–12', prev: 30, suggest: 32, best: 36, tag: 'leve', why: 'Mesmo padrão do desenvolvimento, guiado e mais seguro pra ir à falha.' },
    { id: 'o3', name: 'Desenvolvimento Arnold', muscle: 'ombro', glyph: 'dumbbell', sets: 3, reps: '10', prev: 12, suggest: 12, best: 14, tag: 'foco', why: 'Recruta as três porções do ombro numa amplitude maior.' }
  ],
  core: [
    { id: 'k1', name: 'Abdominal na roda', muscle: 'core', glyph: 'body', sets: 3, reps: '8–10', prev: 0, suggest: 0, best: 0, bodyweight: true, tag: 'foco', why: 'Anti-extensão intenso — trabalha o core inteiro como a prancha, com mais estímulo.' },
    { id: 'k2', name: 'Elevação de pernas suspenso', muscle: 'core', glyph: 'body', sets: 3, reps: '12', prev: 0, suggest: 0, best: 0, bodyweight: true, tag: 'foco', why: 'Foco no abdômen inferior, mantém o padrão de estabilização da prancha.' },
    { id: 'k3', name: 'Prancha lateral', muscle: 'core', glyph: 'body', sets: 3, reps: '30s cada', prev: 0, suggest: 0, best: 0, bodyweight: true, tag: 'equip', why: 'Sem equipamento, foca os oblíquos — complementa a rotação que você já fazia.' }
  ],
  perna: [
    { id: 'l1', name: 'Leg press 45°', muscle: 'perna', glyph: 'layers', sets: 4, reps: '10–12', prev: 120, suggest: 125, best: 140, tag: 'foco', why: 'Permite carga alta com a coluna apoiada — boa pra hipertrofia de quadríceps.' },
    { id: 'l2', name: 'Cadeira extensora', muscle: 'perna', glyph: 'layers', sets: 3, reps: '12–15', prev: 45, suggest: 48, best: 55, tag: 'leve', why: 'Isola o quadríceps poupando o joelho — útil pra finalizar sem sobrecarga axial.' },
    { id: 'l3', name: 'Afundo com halteres', muscle: 'perna', glyph: 'dumbbell', sets: 3, reps: '10 cada', prev: 14, suggest: 16, best: 20, tag: 'foco', why: 'Unilateral, corrige desequilíbrios e recruta glúteo junto.' }
  ],
  posterior: [
    { id: 'g1', name: 'Stiff com halteres', muscle: 'posterior', glyph: 'dumbbell', sets: 4, reps: '10', prev: 20, suggest: 22, best: 26, tag: 'foco', why: 'Alonga e fortalece posterior de coxa e glúteo — padrão de dobradiça de quadril.' },
    { id: 'g2', name: 'Mesa flexora', muscle: 'posterior', glyph: 'layers', sets: 3, reps: '12', prev: 35, suggest: 38, best: 42, tag: 'leve', why: 'Isola os isquiotibiais com baixa exigência de estabilização.' }
  ]
};

/* mapeia músculos próximos pra ter sempre um pool relevante */
EH.muscleAliases = {
  peito: 'peito', costas: 'costas', ombro: 'ombro', core: 'core',
  quadríceps: 'perna', perna: 'perna', glúteo: 'posterior', posterior: 'posterior', braço: 'ombro'
};

/* retorna até 3 candidatos pro músculo, sem repetir o exercício atual */
EH.alternativesFor = function (exercise) {
  var key = (EH.muscleAliases[exercise.muscle] || exercise.muscle);
  var pool = (EH.altPool[key] || EH.altPool.peito).slice();
  var curName = exercise.name.toLowerCase();
  pool = pool.filter(function (p) { return p.name.toLowerCase() !== curName; });
  return pool.slice(0, 3);
};

/* rótulo curto do motivo (tag) */
EH.tagLabel = {
  fav: '❤ Favorito',
  foco: 'Mesmo foco',
  equip: 'Seu equipamento',
  leve: 'Mais leve na articulação'
};

/* ------------------------------------------------------------
   PERFIL RESUMIDO (vai pro prompt da IA)
   ------------------------------------------------------------ */
EH.coachProfile = function () {
  var p = EH.profile;
  return 'Aluno: ' + p.name + ', ' + p.age + ' anos, ' + p.weight + 'kg, ' + p.height + 'cm. ' +
    'Objetivo: ' + p.goal + '. Nível: ' + p.level + '. Método: ' + p.method + '. ' +
    'Treina ' + p.days + 'x/semana na ' + p.place + '. Prontidão hoje: ' + p.readiness + '/100. ' +
    'Favoritos: Supino reto, Puxada alta. Grupos atrasados: pernas e core.';
};
