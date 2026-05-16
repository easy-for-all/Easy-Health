export type WarmupItem = {
  label: string;
  duration: string;
  thumbnail: string;
};

const IMG = (id: string) =>
  `https://images.unsplash.com/photo-${id}?w=160&h=120&fit=crop&crop=center&q=75`;

export const WARMUP_BY_TYPE: Record<string, WarmupItem[]> = {
  musculacao: [
    { label: "Rotação de pescoço", duration: "30s cada lado", thumbnail: IMG("1571019613454-c5c5dee9f50b") },
    { label: "Circundução de ombros", duration: "10 círculos", thumbnail: IMG("1517836357463-dcf25c6821e7") },
    { label: "Rotação de quadril", duration: "10 círculos", thumbnail: IMG("1518611012118-696072aa579a") },
    { label: "Agachamento livre (sem peso)", duration: "15 reps", thumbnail: IMG("1576091160399-112ba8d25d1d") },
    { label: "Polichinelo", duration: "30s", thumbnail: IMG("1601422286583-b87f5c45df62") },
  ],
  cardio: [
    { label: "Caminhada lenta", duration: "2 min", thumbnail: IMG("1476480862126-209bfaa8edc8") },
    { label: "Elevação de joelhos no lugar", duration: "30s", thumbnail: IMG("1538805060065-aef8ddab0de2") },
    { label: "Chute para trás (calcanhar ao glúteo)", duration: "30s", thumbnail: IMG("1571019613454-c5c5dee9f50b") },
    { label: "Rotação de tornozelos", duration: "10 cada", thumbnail: IMG("1517836357463-dcf25c6821e7") },
  ],
  corrida: [
    { label: "Caminhada progressiva", duration: "3 min", thumbnail: IMG("1476480862126-209bfaa8edc8") },
    { label: "Elevação de joelhos", duration: "30s", thumbnail: IMG("1538805060065-aef8ddab0de2") },
    { label: "Skipping leve", duration: "30s", thumbnail: IMG("1601422286583-b87f5c45df62") },
    { label: "Alongamento de panturrilha", duration: "20s cada lado", thumbnail: IMG("1544367567-0f2fcb009e0b") },
  ],
  default: [
    { label: "Polichinelo", duration: "30s", thumbnail: IMG("1601422286583-b87f5c45df62") },
    { label: "Rotação de tronco", duration: "10 cada lado", thumbnail: IMG("1518611012118-696072aa579a") },
    { label: "Agachamento livre", duration: "10 reps", thumbnail: IMG("1576091160399-112ba8d25d1d") },
    { label: "Rotação de braços", duration: "10 círculos", thumbnail: IMG("1517836357463-dcf25c6821e7") },
  ],
};

export const COOLDOWN_BY_TYPE: Record<string, WarmupItem[]> = {
  musculacao: [
    { label: "Alongamento de peito (mãos entrelaçadas atrás)", duration: "30s", thumbnail: IMG("1517836357463-dcf25c6821e7") },
    { label: "Alongamento de costas (abraço de joelhos)", duration: "30s", thumbnail: IMG("1544367567-0f2fcb009e0b") },
    { label: "Alongamento de quadríceps", duration: "30s cada lado", thumbnail: IMG("1571019613454-c5c5dee9f50b") },
    { label: "Alongamento de panturrilha", duration: "30s cada lado", thumbnail: IMG("1518611012118-696072aa579a") },
    { label: "Respiração profunda diafragmática", duration: "1 min", thumbnail: IMG("1506629082955-511b1aa562c8") },
  ],
  cardio: [
    { label: "Caminhada lenta para desacelerar", duration: "3 min", thumbnail: IMG("1476480862126-209bfaa8edc8") },
    { label: "Alongamento de quadríceps", duration: "30s cada lado", thumbnail: IMG("1571019613454-c5c5dee9f50b") },
    { label: "Alongamento de panturrilha", duration: "30s cada lado", thumbnail: IMG("1544367567-0f2fcb009e0b") },
    { label: "Respiração profunda", duration: "1 min", thumbnail: IMG("1506629082955-511b1aa562c8") },
  ],
  corrida: [
    { label: "Caminhada para desacelerar", duration: "3 min", thumbnail: IMG("1476480862126-209bfaa8edc8") },
    { label: "Alongamento de IT Band", duration: "30s cada lado", thumbnail: IMG("1517836357463-dcf25c6821e7") },
    { label: "Alongamento de isquiotibiais", duration: "30s", thumbnail: IMG("1544367567-0f2fcb009e0b") },
    { label: "Alongamento de panturrilha", duration: "30s cada lado", thumbnail: IMG("1518611012118-696072aa579a") },
  ],
  default: [
    { label: "Respiração profunda", duration: "1 min", thumbnail: IMG("1506629082955-511b1aa562c8") },
    { label: "Alongamento de pescoço", duration: "20s cada lado", thumbnail: IMG("1571019613454-c5c5dee9f50b") },
    { label: "Alongamento de tronco", duration: "30s", thumbnail: IMG("1517836357463-dcf25c6821e7") },
    { label: "Caminhada leve", duration: "2 min", thumbnail: IMG("1476480862126-209bfaa8edc8") },
  ],
};
