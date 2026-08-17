import { nativeSessionStorage } from "./native-session-storage";

// Bearer token opaco emitido pelo Rails (ver MobileSession no backend), usado
// pelos shells nativos que carregam os assets do próprio bundle.
//
// Por que existe: com bundle local a origem passa a ser capacitor://localhost,
// e o cookie de sessão do Devise é SameSite=Lax — ele não viaja em requisição
// cross-site para a API. Abrir para SameSite=None não resolveria, porque o
// WKWebView bloqueia cookie de terceiros por ITP.
//
// NÃO se aplica ao shell remoto do Android, que carrega easyhealth.art e é
// same-site com a API. Lá o cookie continua sendo o caminho, e pedir um token
// seria criar superfície de XSS sem ganho.
//
// PERSISTÊNCIA: sempre via nativeSessionStorage (Keychain no iOS). Nunca
// localStorage, Preferences ou qualquer coisa legível por JS. Em memória o
// token existe só durante a sessão do app, para o api client montar o header.
const STORAGE_KEY = "eh_mobile_session";

// Build-time e não heurística de runtime: "o cookie funciona aqui?" não é algo
// que dê para descobrir com segurança depois que a primeira requisição falhou.
export function usesMobileSessionAuth(): boolean {
  return process.env.NEXT_PUBLIC_NATIVE_LOCAL_BUNDLE === "true";
}

// api.ts monta headers de forma síncrona e o Keychain é assíncrono — mesmo
// problema que installation.ts resolve com cache em memória.
let cachedToken: string | null = null;
let primed = false;

export function getCachedMobileSessionToken(): string | null {
  return cachedToken;
}

// Chamado no boot, antes da primeira requisição autenticada. Idempotente.
export async function primeMobileSessionToken(): Promise<void> {
  if (primed || !usesMobileSessionAuth()) return;

  try {
    cachedToken = await nativeSessionStorage.get(STORAGE_KEY);
  } catch {
    // Falha de leitura do Keychain não apaga o que está gravado: o usuário cai
    // numa tela de login, mas o token continua lá para a próxima tentativa.
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
    await nativeSessionStorage.set(STORAGE_KEY, token);
  } catch {
    // Segue em memória: a sessão vale para este launch mesmo sem persistir.
  }
}

export async function clearMobileSessionToken(): Promise<void> {
  cachedToken = null;
  primed = true;
  try {
    await nativeSessionStorage.remove(STORAGE_KEY);
  } catch {
    // Ignorado: o servidor já revogou, e um token órfão não autentica nada.
  }
}

// Header de opt-in. Sem ele o servidor não emite token — é o que mantém o
// bundle web fora deste caminho.
export function mobileSessionIssueHeader(): Record<string, string> {
  return usesMobileSessionAuth() ? { "X-EasyHealth-Mobile-Session": "1" } : {};
}

// Lê o token de uma resposta de login e persiste. Sem token na resposta (web,
// ou shell remoto), não faz nada.
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
