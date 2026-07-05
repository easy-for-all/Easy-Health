"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";

interface DeleteAccountModalProps {
  onClose: () => void;
  onSignOut: () => Promise<void>;
}

export function DeleteAccountModal({ onClose, onSignOut }: DeleteAccountModalProps) {
  const router = useRouter();
  const [confirmText, setConfirmText] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const isConfirmed = confirmText === "EXCLUIR";

  async function handleDelete() {
    if (!isConfirmed) return;
    setLoading(true);
    setError("");
    try {
      await api.delete("/api/v1/auth/account");
      await onSignOut();
      router.replace("/login");
    } catch {
      setError("Erro ao excluir conta. Tente novamente ou contate suporte@easyhealth.com.br");
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/50" onClick={onClose}>
      <div
        className="w-full rounded-t-2xl bg-white px-5 pb-10 pt-5 dark:bg-gray-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-gray-200" />

        <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100">
          <span className="text-2xl">⚠️</span>
        </div>

        <h2 className="mb-2 text-lg font-bold text-gray-900 dark:text-gray-50">Excluir Conta</h2>

        <p className="mb-3 text-sm text-gray-600 dark:text-gray-400">
          Esta ação é irreversível. Ao excluir sua conta, seu acesso será removido e seus dados
          pessoais serão apagados conforme permitido por lei. Alguns registros mínimos poderão ser
          mantidos para cumprimento de obrigações legais, fiscais, auditoria, antifraude ou
          comprovação de pagamentos.
        </p>

        <p className="mb-5 text-sm font-medium text-red-600 dark:text-red-400">
          Este e-mail (e a conta Google associada, se houver) não poderá ser usado para criar uma
          nova conta no EasyHealth.
        </p>

        <p className="mb-2 text-sm font-medium text-gray-700">
          Para confirmar, digite <strong>EXCLUIR</strong> no campo abaixo:
        </p>
        <input
          type="text"
          value={confirmText}
          onChange={(e) => setConfirmText(e.target.value)}
          placeholder="EXCLUIR"
          className="mb-4 w-full rounded-xl border border-gray-200 px-4 py-3 text-sm focus:border-red-400 focus:outline-none"
        />

        {error && (
          <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{error}</p>
        )}

        <div className="flex gap-3">
          <button
            onClick={onClose}
            className="flex-1 rounded-xl border border-gray-200 py-3 text-sm font-semibold text-gray-600"
          >
            Cancelar
          </button>
          <button
            onClick={handleDelete}
            disabled={!isConfirmed || loading}
            className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-semibold text-white disabled:opacity-40"
          >
            {loading ? "Excluindo..." : "Excluir minha conta"}
          </button>
        </div>
      </div>
    </div>
  );
}
