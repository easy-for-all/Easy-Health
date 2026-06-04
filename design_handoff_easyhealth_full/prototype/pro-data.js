/* ============================================================
   EasyHealth Pro — dados do protótipo + ícones + gráficos
   ============================================================ */
window.EH = window.EH || {};

/* ---------- ÍCONES (stroke, herda currentColor) ---------- */
EH.icon = function (name, cls) {
  var p = EH._icons[name] || '';
  return '<svg class="' + (cls || '') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + p + '</svg>';
};
EH._icons = {
  dumbbell: '<path d="M6.5 6.5v11M17.5 6.5v11M3 9v6M21 9v6M6.5 12h11"/>',
  flame: '<path d="M12 3c1 3 4 4.5 4 8a4 4 0 0 1-8 0c0-1.5.7-2.5 1.3-3.2C10 9 11 7 12 3z"/><path d="M12 21a5 5 0 0 0 5-5c0-2-1-3.2-2-4 .2 2.5-1.5 3.5-3 3.5"/>',
  target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.4" fill="currentColor"/>',
  home: '<path d="M4 11l8-7 8 7"/><path d="M6 10v9h12v-9"/>',
  tree: '<path d="M12 3a5 5 0 0 1 4 8 4 4 0 0 1-1 7H9a4 4 0 0 1-1-7 5 5 0 0 1 4-8z"/><path d="M12 14v7"/>',
  building: '<rect x="5" y="3" width="14" height="18" rx="1.5"/><path d="M9 7h2M13 7h2M9 11h2M13 11h2M9 15h2M13 15h2"/>',
  band: '<path d="M4 8c4-4 12-4 16 0M4 16c4 4 12 4 16 0" /><circle cx="4" cy="12" r="1.6"/><circle cx="20" cy="12" r="1.6"/>',
  bike: '<circle cx="6" cy="17" r="3.5"/><circle cx="18" cy="17" r="3.5"/><path d="M6 17l4-7h5l3 7M10 10l-1-3h3"/>',
  body: '<circle cx="12" cy="5" r="2.5"/><path d="M12 7.5v7M12 9l-4 2M12 9l4 2M12 14.5l-3 6M12 14.5l3 6"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  layers: '<path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 13l9 5 9-5"/>',
  refresh: '<path d="M3 12a9 9 0 0 1 15-6.7L21 8M21 12a9 9 0 0 1-15 6.7L3 16"/><path d="M21 4v4h-4M3 20v-4h4"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="16" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  bolt: '<path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>',
  heart: '<path d="M12 20s-7-4.4-9.3-8.6C1 8 2.5 4.5 6 4.5c2 0 3.2 1.2 4 2.3.8-1.1 2-2.3 4-2.3 3.5 0 5 3.5 3.3 6.9C19 15.6 12 20 12 20z"/>',
  check: '<path d="M20 6L9 17l-5-5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevR: '<path d="M9 6l6 6-6 6"/>',
  chevL: '<path d="M15 6l-6 6 6 6"/>',
  arrowR: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  sparkles: '<path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6L12 3z"/><path d="M19 14l.7 1.9L21.6 17l-1.9.7L19 19.6l-.7-1.9L16.4 17l1.9-.7L19 14z"/>',
  brain: '<path d="M9 4a2.5 2.5 0 0 0-2.5 2.5A2.5 2.5 0 0 0 5 11a2.5 2.5 0 0 0 1.5 4.5A2.5 2.5 0 0 0 9 20a2 2 0 0 0 3-1.7V5.7A2 2 0 0 0 9 4z"/><path d="M15 4a2.5 2.5 0 0 1 2.5 2.5A2.5 2.5 0 0 1 19 11a2.5 2.5 0 0 1-1.5 4.5A2.5 2.5 0 0 1 15 20a2 2 0 0 1-3-1.7"/>',
  play: '<path d="M7 5l12 7-12 7V5z" fill="currentColor" stroke="none"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  swap: '<path d="M7 4L3 8l4 4M3 8h13M17 20l4-4-4-4M21 16H8"/>',
  reorder: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
  edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/>',
  trash: '<path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M5 21c0-4 3-6.5 7-6.5s7 2.5 7 6.5"/>',
  card: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 10h18"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>',
  chart: '<path d="M4 19V5M4 19h16M8 16v-5M12 16V8M16 16v-8"/>',
  moon: '<path d="M21 12.8A8.5 8.5 0 1 1 11.2 3a6.5 6.5 0 0 0 9.8 9.8z"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.5 2.5 15 0 18M12 3c-2.5 2.5-2.5 15 0 18"/>',
  shield: '<path d="M12 3l7 3v6c0 4-3 7-7 9-4-2-7-5-7-9V6l7-3z"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>',
  trendUp: '<path d="M3 17l6-6 4 4 8-8M21 7v5M21 7h-5"/>',
  shuffle: '<path d="M16 3h5v5M21 3l-7 7M8 21H3v-5M3 21l7-7M21 16v5h-5M14 14l7 7M3 3l7 7"/>',
  scale: '<path d="M12 3v18M5 7h14M5 7l-2 6a3 3 0 0 0 6 0L5 7zM19 7l-2 6a3 3 0 0 0 6 0l-4-6z"/>',
  zap: '<path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>',
  rotate: '<path d="M21 2v6h-6"/><path d="M3 12a9 9 0 0 1 15-6.7L21 8"/><path d="M3 22v-6h6"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16"/>'
};

/* ---------- PERFIL ---------- */
EH.profile = {
  name: 'Marcus', initial: 'M', email: 'marcus@email.com',
  goal: 'Hipertrofia', level: 'Intermediário', method: 'Upper / Lower',
  days: 4, age: 30, weight: 75, height: 175, place: 'Academia',
  readiness: 82
};

/* ---------- PLANO GERADO ---------- */
EH.plan = {
  name: 'Upper / Lower · 4 dias',
  goal: 'Hipertrofia', method: 'Upper / Lower', level: 'Intermediário',
  weeks: 6, perWeek: 4, durMin: 52,
  days: [
    { id: 'd1', short: 'SEG', label: 'A', name: 'Upper · Força', focus: 'Peito · Costas · Ombro', rest: false, exCount: 6 },
    { id: 'd2', short: 'TER', label: 'B', name: 'Lower · Força', focus: 'Quadríceps · Posterior', rest: false, exCount: 5 },
    { id: 'r1', short: 'QUA', label: '·', name: 'Descanso ativo', focus: 'Mobilidade 15 min', rest: true, exCount: 0 },
    { id: 'd3', short: 'QUI', label: 'C', name: 'Upper · Volume', focus: 'Bíceps · Tríceps · Ombro', rest: false, exCount: 6 },
    { id: 'd4', short: 'SEX', label: 'D', name: 'Lower · Volume', focus: 'Glúteo · Core', rest: false, exCount: 5 },
    { id: 'r2', short: 'SÁB', label: '·', name: 'Cardio leve', focus: 'Caminhada 30 min', rest: true, exCount: 1 },
    { id: 'r3', short: 'DOM', label: '·', name: 'Descanso', focus: 'Recuperação total', rest: true, exCount: 0 }
  ]
};

/* exercícios do dia A (Upper · Força) */
EH.dayExercises = [
  { id: 'e1', name: 'Supino reto com barra', muscle: 'peito', sets: 4, reps: '8–10', prev: 20, suggest: 22, best: 24, fav: true, note: 'Favorito · sempre no plano', glyph: 'dumbbell' },
  { id: 'e2', name: 'Remada curvada', muscle: 'costas', sets: 4, reps: '8–10', prev: 30, suggest: 32, best: 34, fav: false, glyph: 'dumbbell' },
  { id: 'e3', name: 'Desenvolvimento de ombro', muscle: 'ombro', sets: 3, reps: '10–12', prev: 14, suggest: 14, best: 16, fav: false, glyph: 'dumbbell' },
  { id: 'e4', name: 'Puxada alta', muscle: 'costas', sets: 3, reps: '10–12', prev: 45, suggest: 47, best: 50, fav: true, note: 'Favorito', glyph: 'dumbbell' },
  { id: 'e5', name: 'Crucifixo inclinado', muscle: 'peito', sets: 3, reps: '12', prev: 12, suggest: 12, best: 14, fav: false, glyph: 'dumbbell' },
  { id: 'e6', name: 'Prancha + Rotação', muscle: 'core', sets: 3, reps: '40s', prev: 0, suggest: 0, best: 0, fav: false, bodyweight: true, glyph: 'body' }
];

/* histórico (timeline) */
EH.history = [
  { name: 'Lower · Força', date: 'Ontem', done: true, meta: '5 exercícios · 48 min · 5.2t volume' },
  { name: 'Upper · Força', date: '2 dias atrás', done: true, meta: '6 exercícios · 54 min · 6.1t volume' },
  { name: 'Upper · Volume', date: '4 dias atrás', done: false, meta: 'Pulado — recuperação muscular' },
  { name: 'Lower · Volume', date: '5 dias atrás', done: true, meta: '5 exercícios · 50 min · 4.8t volume' },
  { name: 'Upper · Força', date: '7 dias atrás', done: true, meta: '6 exercícios · 51 min · 5.9t volume' }
];

/* frequência semanal (treinos por semana, últimas 8) */
EH.weeklyFreq = [3, 4, 2, 4, 3, 4, 4, 3];
EH.weekLabels = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8'];

/* equilíbrio muscular (0–100, % de volume relativo) */
EH.muscleBalance = [
  { m: 'peito', v: 88 }, { m: 'costas', v: 82 }, { m: 'ombro', v: 64 },
  { m: 'braço', v: 71 }, { m: 'perna', v: 38, low: true }, { m: 'core', v: 30, low: true }
];

/* progressão de carga por exercício (kg ao longo do tempo) */
EH.loadProgress = [
  { name: 'Supino reto', muscle: 'peito', series: [16, 18, 18, 20, 20, 22], last: 20, best: 24, deltaPct: 25 },
  { name: 'Agachamento livre', muscle: 'perna', series: [40, 42, 45, 45, 48, 50], last: 48, best: 50, deltaPct: 20 },
  { name: 'Remada curvada', muscle: 'costas', series: [26, 28, 28, 30, 30, 32], last: 30, best: 34, deltaPct: 18 },
  { name: 'Desenvolvimento', muscle: 'ombro', series: [10, 12, 12, 14, 14, 14], last: 14, best: 16, deltaPct: 14 },
  { name: 'Levantamento terra', muscle: 'costas', series: [50, 55, 58, 60, 62, 65], last: 62, best: 65, deltaPct: 24 }
];

/* favoritos */
EH.favExercises = [
  { name: 'Supino reto com barra', muscle: 'peito', inPlan: true, glyph: 'dumbbell' },
  { name: 'Puxada alta', muscle: 'costas', inPlan: true, glyph: 'dumbbell' },
  { name: 'Agachamento livre', muscle: 'perna', inPlan: false, glyph: 'dumbbell' },
  { name: 'Rosca direta', muscle: 'braço', inPlan: false, glyph: 'dumbbell' }
];
EH.favWorkouts = [
  { name: 'Upper · Força', meta: '6 exercícios · ~54 min', tags: ['peito', 'costas'] },
  { name: 'Full Body Express', meta: '5 exercícios · ~32 min', tags: ['full body'] }
];
