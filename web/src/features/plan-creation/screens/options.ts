import type {
  BodyFocus,
  Equipment,
  FitnessLevel,
  Goal,
  IntensityPreference,
  TrainingLocation,
  TrainingStyle,
} from "@/shared/types/health-profile";

export const GOALS: { value: Goal; label: string; desc: string; icon: string }[] = [
  { value: "lose_weight", label: "Emagrecimento", desc: "Reduzir gordura corporal", icon: "🔥" },
  { value: "gain_muscle", label: "Hipertrofia", desc: "Ganhar massa muscular", icon: "💪" },
  { value: "conditioning", label: "Condicionamento", desc: "Ter mais fôlego e resistência", icon: "🏃" },
  { value: "body_definition", label: "Recomposição", desc: "Definir o corpo, ganhar e perder ao mesmo tempo", icon: "✨" },
  { value: "health_longevity", label: "Saúde geral", desc: "Cuidar do corpo no longo prazo", icon: "❤️" },
  { value: "mobility", label: "Mobilidade", desc: "Mover-se com mais conforto", icon: "🧘" },
  { value: "strength", label: "Força", desc: "Evoluir cargas e capacidade", icon: "🏋️" },
  { value: "safe_return", label: "Voltar com segurança", desc: "Retomar aos poucos", icon: "🛟" },
];

export const LEVELS: { value: FitnessLevel; label: string; desc: string; icon: string }[] = [
  { value: "beginner", label: "Iniciante", desc: "Começando agora ou voltando", icon: "🌱" },
  { value: "intermediate", label: "Intermediário", desc: "Treina com regularidade", icon: "🎯" },
  { value: "advanced", label: "Avançado", desc: "Treino é rotina há anos", icon: "⚡" },
];

export const LOCATIONS: { value: TrainingLocation; label: string; desc: string; icon: string }[] = [
  { value: "full_gym", label: "Academia", desc: "Aparelhos, barras e halteres", icon: "🏋️" },
  { value: "home", label: "Casa", desc: "Pouco ou nenhum equipamento", icon: "🏠" },
  { value: "outdoor", label: "Ar livre", desc: "Parques, ruas e quadras", icon: "🌳" },
  { value: "unknown", label: "Varia", desc: "Depende do dia ou da semana", icon: "🔄" },
];

export const EQUIPMENT: { value: Equipment; label: string }[] = [
  { value: "machine", label: "Máquinas" }, { value: "dumbbell", label: "Halteres" },
  { value: "barbell", label: "Barra" }, { value: "plates", label: "Anilhas" },
  { value: "resistance_band", label: "Elásticos" }, { value: "treadmill", label: "Esteira" },
  { value: "stationary_bike", label: "Bicicleta" }, { value: "rower", label: "Remo" },
  { value: "jump_rope", label: "Corda" }, { value: "bodyweight", label: "Peso corporal apenas" },
  { value: "none", label: "Nenhum" },
];

export const BODY_FOCUS: { value: BodyFocus; label: string }[] = [
  { value: "full_body", label: "Corpo todo" }, { value: "chest", label: "Peito" },
  { value: "back", label: "Costas" }, { value: "legs", label: "Pernas" },
  { value: "abs", label: "Core" }, { value: "arms", label: "Braços" },
  { value: "glutes", label: "Glúteos" }, { value: "shoulders", label: "Ombros" },
  { value: "mobility_posture", label: "Mobilidade/postura" }, { value: "conditioning_cardio", label: "Condicionamento/cardio" },
];

export const TRAINING_STYLES: { value: TrainingStyle; label: string }[] = [
  { value: "traditional_strength", label: "Musculação tradicional" }, { value: "short_sessions", label: "Treinos curtos e objetivos" },
  { value: "cardio", label: "Cardio" }, { value: "functional", label: "Funcional" },
  { value: "calisthenics", label: "Calistenia" }, { value: "mobility", label: "Mobilidade/alongamento" },
  { value: "mixed", label: "Misturado" }, { value: "unknown", label: "Não sei ainda" },
];

export const INTENSITIES: { value: IntensityPreference; label: string }[] = [
  { value: "easy_start", label: "Leve" }, { value: "balanced", label: "Média" },
  { value: "intense", label: "Alta" }, { value: "progressive", label: "Progressiva" },
];

export const LIMITATION_PRESETS = ["Joelho", "Lombar", "Ombro", "Punho", "Pescoço", "Quadril", "Pós-parto", "Retorno de lesão"];
