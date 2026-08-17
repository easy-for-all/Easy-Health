import { isSafeInternalPath } from "@/shared/lib/push-deep-link";

// Casamento de rota para o shell nativo.
//
// Existe porque o bundle iOS é um único index.html: não há um arquivo HTML por
// rota dentro do IPA, e não pode haver — /users/1, /users/2, ... é um conjunto
// infinito. Quem resolve o caminho é este matcher, em runtime, e o id vira
// parâmetro para o componente buscar no Rails.
//
// Reusa isSafeInternalPath de push-deep-link.ts: a regra de "isto é um caminho
// interno seguro?" já existe no projeto e não deve ganhar uma segunda versão.

export type RouteParams = Record<string, string>;

export interface RouteMatch {
  pattern: string;
  params: RouteParams;
}

// Segmento dinâmico no formato do App Router: [id], [token], [code].
const DYNAMIC = /^\[([^\]]+)\]$/;

function segments(path: string): string[] {
  return path.split("/").filter(Boolean);
}

export function matchPattern(pattern: string, pathname: string): RouteParams | null {
  const patternParts = segments(pattern);
  const pathParts = segments(pathname);
  if (patternParts.length !== pathParts.length) return null;

  const params: RouteParams = {};
  for (let i = 0; i < patternParts.length; i++) {
    const expected = patternParts[i];
    const actual = pathParts[i];
    const dynamic = DYNAMIC.exec(expected);

    if (dynamic) {
      // Um segmento dinâmico vazio não é uma rota — /users/ não é /users/[id].
      if (!actual) return null;
      params[dynamic[1]] = decodeURIComponent(actual);
      continue;
    }
    if (expected !== actual) return null;
  }
  return params;
}

// A tabela de rotas É a allowlist. Uma rota que não está registrada não navega,
// mesmo que o caminho pareça inofensivo — é o que impede uma URL vinda de fora
// (deep link, push, clipboard) de virar navegação arbitrária dentro do app.
export function matchRoute(patterns: string[], pathname: string): RouteMatch | null {
  if (!isSafeInternalPath(pathname)) return null;

  const clean = pathname.split("?")[0].split("#")[0];

  // Estáticas antes de dinâmicas: /users/new tem que vencer /users/[id] se as
  // duas existirem, independentemente da ordem em que foram registradas.
  const ordered = [...patterns].sort(
    (a, b) => Number(DYNAMIC.test(a.split("/").pop() ?? "")) - Number(DYNAMIC.test(b.split("/").pop() ?? ""))
  );

  for (const pattern of ordered) {
    const params = matchPattern(pattern, clean);
    if (params) return { pattern, params };
  }
  return null;
}

export function splitPath(url: string): { pathname: string; search: string } {
  const [beforeHash] = url.split("#");
  const queryAt = beforeHash.indexOf("?");
  if (queryAt === -1) return { pathname: beforeHash, search: "" };
  return { pathname: beforeHash.slice(0, queryAt), search: beforeHash.slice(queryAt) };
}

// Ponto de entrada para uma rota vinda DE FORA do app (deep link, push, cold
// start). Nunca devolve caminho não registrado.
export function resolveExternalRoute(
  raw: unknown,
  patterns: string[],
  fallback: string
): string {
  if (typeof raw !== "string" || !raw) return fallback;

  // Aceita tanto "/users/1" quanto "https://easyhealth.art/users/1", que é o
  // formato que um Universal Link entrega. Qualquer outro host é descartado.
  let candidate = raw;
  if (/^https?:\/\//i.test(raw)) {
    try {
      const url = new URL(raw);
      if (!/(^|\.)easyhealth\.art$/i.test(url.hostname)) return fallback;
      candidate = `${url.pathname}${url.search}`;
    } catch {
      return fallback;
    }
  }

  const { pathname, search } = splitPath(candidate);
  if (!matchRoute(patterns, pathname)) return fallback;
  return `${pathname}${search}`;
}
