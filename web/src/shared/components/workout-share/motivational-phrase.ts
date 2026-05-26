const phrases = [
  "Consistência gera evolução.",
  "Cada treino é uma vitória.",
  "O corpo alcança o que a mente acredita.",
  "Progresso, não perfeição.",
  "Mais forte a cada repetição.",
  "Hoje melhor que ontem.",
  "Resultados aparecem para quem não desiste.",
  "Seu único limite é você mesmo.",
];

const volumePhrases: Array<{ minKg: number; phrase: string }> = [
  { minKg: 3000, phrase: "Você levantou o equivalente a um carro." },
  { minKg: 2000, phrase: "Você levantou o equivalente a uma motocicleta." },
  { minKg: 1000, phrase: "Você levantou o equivalente a um piano de cauda." },
  { minKg: 500,  phrase: "Você levantou o equivalente a um touro adulto." },
  { minKg: 200,  phrase: "Você levantou o equivalente a um homem adulto." },
  { minKg: 0,    phrase: "Cada kg conta. Continue assim!" },
];

export function getMotivationalPhrase(volumeKg: number): string {
  const match = volumePhrases.find((p) => volumeKg >= p.minKg);
  return match?.phrase ?? phrases[Math.floor(Math.random() * phrases.length)];
}

export function getRandomPhrase(): string {
  return phrases[Math.floor(Math.random() * phrases.length)];
}
