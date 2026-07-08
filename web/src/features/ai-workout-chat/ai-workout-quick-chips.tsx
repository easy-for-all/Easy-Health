"use client";

const CHIPS: { label: string; text: string }[] = [
  { label: "Ganhar massa", text: "Meu objetivo é ganhar massa muscular" },
  { label: "Emagrecer", text: "Meu objetivo é emagrecer" },
  { label: "Treinar em casa", text: "Quero treinar em casa" },
  { label: "Academia", text: "Vou treinar na academia" },
  { label: "Pouco tempo", text: "Tenho pouco tempo disponível para treinar" },
  { label: "Dor ou limitação", text: "Tenho uma dor ou limitação física" },
  { label: "Iniciante", text: "Sou iniciante no treino" },
  { label: "Avançado", text: "Já tenho experiência avançada com treino" },
];

export function AiWorkoutQuickChips({ onSelect, disabled }: { onSelect: (text: string) => void; disabled?: boolean }) {
  return (
    <div className="coach-quick">
      {CHIPS.map((chip) => (
        <button
          key={chip.label}
          type="button"
          className="coach-chip"
          onClick={() => onSelect(chip.text)}
          disabled={disabled}
        >
          {chip.label}
        </button>
      ))}
    </div>
  );
}
