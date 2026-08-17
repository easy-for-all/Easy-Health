import { Preferences } from "@capacitor/preferences";

// Bearer token opaco emitido pelo Rails (ver MobileSession no backend), usado
// pelos shells nativos que carregam os assets do próprio bundle.
//
// Por que isto existe: com bundle local a origem passa a ser
// capacitor://localhost, e o cookie de sessão do Devise é SameSite=Lax — ele
// não viaja em requisição cross-site para api.easyhealth.art. Abrir para
// SameSite=None não resolveria mesmo assim, porque o WKWebView bloqueia cookie
// de terceiros. Então o app nativo autentica por header.
//
// NÃO se aplica ao shell remoto do Android, que carrega easyhealth.art e
// portanto é same-site com a API. Lá o cookie continua sendo o caminho, e
// pedir um token seria criar superfície de XSS sem ganho nenhum.
const STORAGE_KEY = "eh_mobile_session";

// O build nativo de bundle local liga esta flag. É deliberadamente build-time
// e não uma heurística de runtime: "o cookie funciona aqui?" não é algo que dê
// para descobrir com segurança depois que a primeira requisição já falhou.
export function usesMobileSessionAuth(): boolean {
  return process.env.NEXT_PUBLIC_NATIVE_LOCAL_BUNDLE === "true";
}

// api.ts monta os headers de forma síncrona, e o Preferences é assíncrono —
// mesmo problema que installation.ts resolve com um cache em memória. O valor
// é lido do disco uma vez no boot e mantido aqui.
let cachedToken: string | null = null;
let primed = false;

export function getCachedMobileSessionToken(): string | null {
  return cachedToken;
}

// Chamado no boot, antes da primeira requisição autenticada. Idempotente.
export async function primeMobileSessionToken(): Promise<void> {
  if (primed || !usesMobileSessionAuth()) return;

  try {
    const { value } = await Preferences.get({ key: STORAGE_KEY });
    cachedToken = value || null;
  } catch {
    // Falha de leitura não é motivo para apagar o que está gravado: o usuário
    // cai numa tela de login, mas o token continua lá para a próxima tentativa.
    cachedToken = null;
  } finally {
    primed = true;
  }
}

export async function storeMobileSessionToken(token: string): Promise<void> {
  if (!usesMobileSessionAuth() || !token) return;

  cachedToken = token;
  primed = true;
  try {
    await Preferences.set({ key: STORAGE_KEY, value: token });
  } catch {
    // Segue em memória: a sessão vale para este launch mesmo sem persistir.
  }
}

export async function clearMobileSessionToken(): Promise<void> {
  cachedToken = null;
  primed = true;
  try {
    await Preferences.remove({ key: STORAGE_KEY });
  } catch {
    // Ignorado de propósito: o servidor já revogou. Um token órfão no disco
    // não autentica mais nada.
  }
}

// Header de opt-in. Sem ele o servidor não emite token — é o que mantém o
// bundle web normal fora deste caminho.
export function mobileSessionIssueHeader(): Record<string, string> {
  return usesMobileSessionAuth() ? { "X-EasyHealth-Mobile-Session": "1" } : {};
}

// Lê o token de uma resposta de login e o persiste. Sem token na resposta
// (web, ou shell remoto), não faz nada.
export async function captureMobileSessionToken(payload: unknown): Promise<void> {
  if (!usesMobileSessionAuth() || typeof payload !== "object" || payload === null) return;

  const token = (payload as { mobile_session_token?: unknown }).mobile_session_token;
  if (typeof token === "string" && token) await storeMobileSessionToken(token);
}

// Exposto só para teste — o cache de módulo sobrevive entre exemplos.
export function __resetMobileSessionCacheForTests(): void {
  cachedToken = null;
  primed = false;
}
