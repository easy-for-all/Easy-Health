import { getCachedInstallationId, isNativeApp } from "@/shared/lib/analytics/context";
import { getInstallationId } from "@/shared/lib/analytics/installation";
import { AnonApiError } from "./anon-api";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

// O token da sessão anônima.
//
// Guardado em localStorage e não em @capacitor/preferences, ao contrário do
// installation_id. Aquele PRECISA sobreviver a um restore errado sem ser
// reaproveitado, e por isso fica fora do Android Auto Backup. Este dura 24h e
// carrega o hash da instalação a que pertence: um token restaurado de outro
// aparelho é recusado pelo servidor com installation_mismatch e simplesmente
// re-emitido. Nada a proteger, nada a perder.
const TOKEN_KEY = "eh_anon_session";

export interface StoredToken {
  token: string;
  expires_at: string;
  installation_id: string;
}

export interface MintedSession {
  token: string;
  expires_at: string;
  plans_remaining: number;
}

// Renova antes de expirar de fato: um token que vence no meio de uma geração de
// 90s desperdiça uma das três vagas da pessoa.
const RENEW_MARGIN_MS = 10 * 60 * 1000;

function read(): StoredToken | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(TOKEN_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StoredToken>;
    if (!parsed.token || !parsed.expires_at || !parsed.installation_id) return null;
    return parsed as StoredToken;
  } catch {
    return null;
  }
}

function write(value: StoredToken): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(TOKEN_KEY, JSON.stringify(value));
  } catch {
    // Sem persistência o token é re-emitido a cada abertura. Custa uma
    // requisição, não corretude.
  }
}

export function clearAnonymousSession(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* nada a limpar */
  }
}

function usable(stored: StoredToken | null, installationId: string): boolean {
  if (!stored) return false;
  if (stored.installation_id !== installationId) return false;
  return Date.parse(stored.expires_at) - Date.now() > RENEW_MARGIN_MS;
}

async function mint(installationId: string): Promise<MintedSession> {
  const res = await fetch(`${API_URL}/api/v1/anonymous/sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Installation-Id": installationId,
      "X-Platform": "android",
    },
    body: JSON.stringify({ installation_id: installationId }),
    signal: AbortSignal.timeout(15_000),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const payload = data as { error?: string; reason?: string };
    throw new AnonApiError(payload.error ?? "anonymous_session_failed", res.status, payload.error, payload.reason);
  }

  return data as MintedSession;
}

// Devolve um token utilizável, emitindo um novo se necessário.
//
// Só Android nativo: na Web e no PWA o modo anônimo não existe, e pedir um token
// ali criaria a expectativa de um fluxo que não vai funcionar.
export async function ensureAnonymousSession(): Promise<string | null> {
  if (!isNativeApp()) return null;

  const installationId = getCachedInstallationId() ?? (await getInstallationId().catch(() => undefined));
  if (!installationId) return null;

  const stored = read();
  if (usable(stored, installationId)) return stored!.token;

  try {
    const minted = await mint(installationId);
    write({ token: minted.token, expires_at: minted.expires_at, installation_id: installationId });
    return minted.token;
  } catch {
    // Modo anônimo desligado, build antigo, instalação já vinculada: todos
    // levam ao mesmo lugar do ponto de vista do cliente — não dá para seguir
    // sem conta, então o fluxo com conta é o que resta.
    clearAnonymousSession();
    return null;
  }
}

// Token já emitido, sem ida à rede. Para quem só precisa saber se há uma sessão
// anônima em curso (guards de rota, decisão de render).
export function currentAnonymousToken(): string | null {
  const installationId = getCachedInstallationId();
  if (!installationId) return null;

  const stored = read();
  return stored && stored.installation_id === installationId ? stored.token : null;
}
