"use client";

import { useState } from "react";
import { api } from "@/shared/lib/api";

const DATA_OPTIONS = [
  { key: "workout_sessions", label: "Treinos realizados", description: "Histórico de sessões de treino" },
  { key: "workout_plans",    label: "Treinos criados",    description: "Planos e dias de treino" },
  { key: "user_media",       label: "Fotos e exames",     description: "Imagens e documentos enviados" },
  { key: "health_data_points", label: "Dados de saúde",   description: "Métricas extraídas de exames" },
  { key: "health_profile_optional", label: "Perfil físico", description: "Peso, altura, idade, objetivo e nível" },
] as const;

type DataKey = (typeof DATA_OPTIONS)[number]["key"];

interface CleanDataModalProps {
  onClose: () => void;
  onSuccess: () => void;
}

export function CleanDataModal({ onClose, onSuccess }: CleanDataModalProps) {
  const [selected, setSelected] = useState<Set<DataKey>>(new Set());
  const [confirming, setConfirming] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  function toggle(key: DataKey) {
    setSelected((prev) => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });
  }

  async function handleConfirm() {
    if (selected.size === 0) return;
    setLoading(true);
    setError("");
    try {
      await api.delete("/api/v1/profile/data", { data_types: Array.from(selected) });
      onSuccess();
      onClose();
    } catch {
      setError("Erro ao limpar dados. Tente novamente.");
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/50" onClick={onClose}>
      <div
        className="w-full rounded-t-2xl bg-white px-5 pb-10 pt-5 dark:bg-gray-900"
        style={{ paddingBottom: "max(40px, var(--safe-area-bottom))" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-gray-200" />

        <h2 className="mb-2 text-lg font-bold text-gray-900 dark:text-gray-50">Limpar Meus Dados</h2>
        <p className="mb-5 text-sm text-gray-500 dark:text-gray-400">
          Selecione quais dados deseja apagar. Sua conta, assinatura e dados de pagamento não serão
          afetados.
        </p>

        <div className="mb-5 space-y-2">
          {DATA_OPTIONS.map((opt) => (
            <button
              key={opt.key}
              onClick={() => toggle(opt.key)}
              className={`flex w-full items-center gap-3 rounded-xl border px-4 py-3 text-left transition ${
                selected.has(opt.key)
                  ? "border-primary-400 bg-primary-50"
                  : "border-gray-200 bg-white"
              }`}
            >
              <span
                className={`flex h-5 w-5 shrink-0 items-center justify-center rounded border-2 text-xs ${
                  selected.has(opt.key)
                    ? "border-primary-500 bg-primary-500 text-white"
                    : "border-gray-300"
                }`}
              >
                {selected.has(opt.key) && "✓"}
              </span>
              <div>
                <p className="text-sm font-semibold text-gray-800">{opt.label}</p>
                <p className="text-xs text-gray-400">{opt.description}</p>
              </div>
            </button>
          ))}
        </div>

        {confirming ? (
          <div className="mb-4 rounded-xl bg-orange-50 p-4">
            <p className="text-sm text-orange-800 font-medium mb-3">
              Essa ação apagará os dados selecionados e não poderá ser desfeita. Deseja continuar?
            </p>
            {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
            <div className="flex gap-3">
              <button
                onClick={() => setConfirming(false)}
                className="flex-1 rounded-xl border border-gray-200 py-2.5 text-sm font-semibold text-gray-600"
              >
                Voltar
              </button>
              <button
                onClick={handleConfirm}
                disabled={loading}
                className="flex-1 rounded-xl bg-orange-500 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
              >
                {loading ? "Apagando..." : "Confirmar exclusão"}
              </button>
            </div>
          </div>
        ) : (
          <div className="flex gap-3">
            <button
              onClick={onClose}
              className="flex-1 rounded-xl border border-gray-200 py-3 text-sm font-semibold text-gray-600"
            >
              Cancelar
            </button>
            <button
              onClick={() => setConfirming(true)}
              disabled={selected.size === 0}
              className="flex-1 rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-40"
            >
              Limpar selecionados ({selected.size})
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
