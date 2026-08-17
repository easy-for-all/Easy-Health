"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { matchRoute, splitPath, type RouteParams } from "./match";

// Roteador client-side do shell nativo.
//
// Escrito à mão em vez de trazer React Router: a superfície que o adapter de
// next/navigation precisa cobrir é pequena (push/replace/back/pathname/
// searchParams/params), e uma dependência nova para isso seria maior que o
// problema. O casamento de rota vive em match.ts e é testado isoladamente.

interface RouterState {
  pathname: string;
  search: string;
  params: RouteParams;
  pattern: string | null;
}

interface RouterValue extends RouterState {
  push: (href: string) => void;
  replace: (href: string) => void;
  back: () => void;
  forward: () => void;
  refresh: () => void;
}

const RouterContext = createContext<RouterValue | null>(null);

export interface NativeRouterProps {
  patterns: string[];
  fallback: string;
  initialPath: string;
  children: ReactNode;
}

export function NativeRouter({ patterns, fallback, initialPath, children }: NativeRouterProps) {
  const [state, setState] = useState<RouterState>(() => resolve(initialPath, patterns, fallback));
  // Bumped by refresh() so consumers that key off the router re-render, which is
  // the closest honest equivalent to Next's server-side refresh in a SPA.
  const [, setNonce] = useState(0);

  const navigate = useCallback(
    (href: string, mode: "push" | "replace") => {
      const next = resolve(href, patterns, fallback);
      const url = `${next.pathname}${next.search}`;
      // O histórico do WebView é o mesmo do navegador; mantê-lo em dia é o que
      // faz o gesto de voltar do iOS e o botão físico do Android funcionarem.
      if (mode === "push") window.history.pushState({}, "", url);
      else window.history.replaceState({}, "", url);
      setState(next);
    },
    [patterns, fallback]
  );

  useEffect(() => {
    function onPopState() {
      setState(resolve(window.location.pathname + window.location.search, patterns, fallback));
    }
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, [patterns, fallback]);

  // Alinha a barra de endereço com a rota resolvida no primeiro render. Sem
  // isto, abrir o app numa rota desconhecida deixaria a URL mentindo sobre
  // onde o usuário realmente está.
  useEffect(() => {
    const current = window.location.pathname + window.location.search;
    const resolved = `${state.pathname}${state.search}`;
    if (current !== resolved) window.history.replaceState({}, "", resolved);
    // Intencionalmente só no mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const value = useMemo<RouterValue>(
    () => ({
      ...state,
      push: (href: string) => navigate(href, "push"),
      replace: (href: string) => navigate(href, "replace"),
      back: () => window.history.back(),
      forward: () => window.history.forward(),
      refresh: () => setNonce((n) => n + 1),
    }),
    [state, navigate]
  );

  return <RouterContext.Provider value={value}>{children}</RouterContext.Provider>;
}

function resolve(href: string, patterns: string[], fallback: string): RouterState {
  const { pathname, search } = splitPath(href || "/");
  const match = matchRoute(patterns, pathname);

  // Rota fora da allowlist cai no fallback em vez de renderizar nada. É o
  // comportamento seguro pedido: nunca navegar para caminho não registrado.
  if (!match) {
    const fb = splitPath(fallback);
    const fbMatch = matchRoute(patterns, fb.pathname);
    return {
      pathname: fb.pathname,
      search: fb.search,
      params: fbMatch?.params ?? {},
      pattern: fbMatch?.pattern ?? null,
    };
  }

  return { pathname, search, params: match.params, pattern: match.pattern };
}

export function useNativeRouter(): RouterValue {
  const ctx = useContext(RouterContext);
  if (!ctx) throw new Error("useNativeRouter must be used inside <NativeRouter>");
  return ctx;
}

// Usado pelos adapters, que precisam funcionar mesmo se algum componente for
// renderizado fora do provider num teste isolado.
export function useOptionalNativeRouter(): RouterValue | null {
  return useContext(RouterContext);
}
