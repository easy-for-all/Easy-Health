import { api } from "@/shared/lib/api";
import { getCachedInstallationId } from "@/shared/lib/analytics/context";
import { trackEvent } from "@/shared/lib/analytics";
import { clearAnonymousSession, currentAnonymousToken } from "./anonymous-session";

// Um claim perdido é DADO perdido — plano e treinos que a pessoa já fez —, ao
// contrário de um evento perdido, que só custa uma linha de relatório. Por isso
// existe um marcador persistido: se a chamada não completar no cadastro, a
// próxima montagem do app tenta de novo.
const PENDING_KEY = "eh_anon_claim_pending";

export type ClaimStatus = "claimed" | "already_claimed" | "conflict" | "nothing_to_claim" | "failed";

function markPending(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PENDING_KEY, "1");
  } catch {
    /* sem marcador, resta o retry da próxima chamada explícita */
  }
}

function clearPending(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(PENDING_KEY);
  } catch {
    /* nada a limpar */
  }
}

export function hasPendingClaim(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(PENDING_KEY) === "1";
  } catch {
    return false;
  }
}

// Reivindica para a conta recém-criada o que a instalação produziu antes dela.
// Chamado logo após signUp/signIn e no retorno do Google.
//
// Não bloqueia nem levanta: o cadastro já aconteceu e não pode ser desfeito por
// uma falha aqui.
export async function claimAnonymousData(): Promise<ClaimStatus> {
  const token = currentAnonymousToken();
  if (!token || !getCachedInstallationId()) {
    clearPending();
    return "nothing_to_claim";
  }

  markPending();

  try {
    const response = await api.post<{ status: string; plans_claimed?: number; sessions_claimed?: number }>(
      "/api/v1/anonymous/claim",
      { anonymous_token: token },
    );

    const status = (response?.status ?? "failed") as ClaimStatus;

    if (status === "claimed" || status === "already_claimed" || status === "nothing_to_claim") {
      clearPending();
      // O token não vale mais depois do claim (o backend o recusa com
      // session_claimed); guardá-lo só produziria 401 a cada abertura.
      clearAnonymousSession();
    }

    if (status === "claimed") {
      trackEvent("anonymous_workouts_claim_succeeded", {
        plans_claimed: response.plans_claimed,
        sessions_claimed: response.sessions_claimed,
      });
    }

    // Conflito é PERMANENTE: o aparelho é de outra conta e repetir dá o mesmo
    // resultado. Manter o marcador faria o app tentar para sempre.
    if (status === "conflict") {
      clearPending();
      clearAnonymousSession();
      trackEvent("anonymous_workouts_claim_failed", { reason: "conflict" });
    }

    return status;
  } catch {
    // Rede/servidor: recuperável, o marcador fica para a próxima montagem.
    return "failed";
  }
}

// Retenta um claim que ficou pendente de uma sessão anterior.
export async function retryPendingClaim(): Promise<void> {
  if (!hasPendingClaim()) return;

  await claimAnonymousData();
}
