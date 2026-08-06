import { getAnalyticsContext, getCachedInstallationId } from "@/shared/lib/analytics/context";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

// Cliente HTTP dos endpoints anônimos.
//
// Separado de shared/lib/api.ts de propósito: aquele cliente manda cookie de
// sessão (`credentials: "include"`) e é usado por toda a Web e o PWA. Acrescentar
// um Authorization anônimo lá faria uma requisição autenticada carregar as duas
// credenciais ao mesmo tempo, e a Web passaria a ter código de um modo que não
// existe para ela. Aqui não vai cookie nenhum — o token é a única credencial.

export class AnonApiError extends Error {
  status: number;
  errorCode?: string;
  reason?: string;

  constructor(message: string, status: number, errorCode?: string, reason?: string) {
    super(message);
    this.name = "AnonApiError";
    this.status = status;
    this.errorCode = errorCode;
    this.reason = reason;
  }

  // O 403 do limite é uma resposta de produto, não uma falha: é a fronteira do
  // que dá para fazer sem conta.
  get isLimitReached(): boolean {
    return this.status === 403;
  }

  // O token expirou ou não vale mais para esta instalação. Renovável.
  get isUnauthorized(): boolean {
    return this.status === 401;
  }
}

const DEFAULT_TIMEOUT_MS = 15_000;
// A geração é síncrona e pode levar até 90s — o mesmo orçamento que o fluxo
// autenticado usa. Um timeout curto aqui transformaria uma geração lenta em
// erro depois de já ter gasto uma das três vagas.
export const GENERATION_TIMEOUT_MS = 120_000;

function headers(token: string): Record<string, string> {
  const context = getAnalyticsContext();
  const out: Record<string, string> = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
  };

  const installationId = getCachedInstallationId();
  if (installationId) out["X-Installation-Id"] = installationId;
  // X-Platform e X-App-Build não são diagnóstico aqui: o backend recusa quem não
  // é Android nativo e quem está abaixo do build mínimo.
  if (context.platform) out["X-Platform"] = context.platform;
  if (context.app_version) out["X-App-Version"] = context.app_version;
  if (context.build_number) out["X-App-Build"] = context.build_number;

  return out;
}

async function parse<T>(res: Response): Promise<T> {
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const payload = data as { error?: string; reason?: string; errors?: string[] };
    const message = payload.error ?? payload.errors?.join(", ") ?? res.statusText ?? "Request failed";
    throw new AnonApiError(message, res.status, payload.error, payload.reason);
  }

  return data as T;
}

export async function anonGet<T>(token: string, path: string, timeout = DEFAULT_TIMEOUT_MS): Promise<T> {
  const res = await fetch(`${API_URL}/api/v1/anonymous${path}`, {
    method: "GET",
    headers: headers(token),
    signal: AbortSignal.timeout(timeout),
  });
  return parse<T>(res);
}

export async function anonPost<T>(
  token: string,
  path: string,
  body: unknown,
  timeout = DEFAULT_TIMEOUT_MS
): Promise<T> {
  const res = await fetch(`${API_URL}/api/v1/anonymous${path}`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(timeout),
  });
  return parse<T>(res);
}

export async function anonPut<T>(token: string, path: string, body: unknown): Promise<T> {
  const res = await fetch(`${API_URL}/api/v1/anonymous${path}`, {
    method: "PUT",
    headers: headers(token),
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(DEFAULT_TIMEOUT_MS),
  });
  return parse<T>(res);
}
