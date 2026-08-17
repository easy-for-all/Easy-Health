"use client";

// Adapter de next/navigation para o shell nativo.
//
// O build nativo aliasa "next/navigation" para este módulo (ver
// vite.native.config.ts), então os 51 arquivos que já importam useRouter,
// usePathname, useSearchParams e useParams continuam idênticos. Essa é a razão
// de existir do adapter: a alternativa era reescrever a navegação inteira do
// produto para introduzir uma segunda árvore de rotas.
//
// A auditoria confirmou que a superfície importada é exatamente estes quatro
// hooks — nada de redirect() nem notFound(), que exigiriam semântica de
// servidor que um bundle local não tem.

import { useMemo } from "react";
import { useNativeRouter } from "../router/router-context";

export interface AppRouterInstance {
  push: (href: string) => void;
  replace: (href: string) => void;
  back: () => void;
  forward: () => void;
  refresh: () => void;
  // Sem servidor não há nada para pré-buscar. Existe só para manter a forma do
  // objeto do Next: um componente que chame prefetch não pode quebrar.
  prefetch: (href: string) => void;
}

export function useRouter(): AppRouterInstance {
  const router = useNativeRouter();
  return useMemo(
    () => ({
      push: router.push,
      replace: router.replace,
      back: router.back,
      forward: router.forward,
      refresh: router.refresh,
      prefetch: () => undefined,
    }),
    [router]
  );
}

export function usePathname(): string {
  return useNativeRouter().pathname;
}

export function useSearchParams(): URLSearchParams {
  const { search } = useNativeRouter();
  // Recriado a cada mudança de query, e só então — componentes que colocam o
  // retorno em dependência de efeito não entram em loop.
  return useMemo(() => new URLSearchParams(search), [search]);
}

export function useParams<T extends Record<string, string> = Record<string, string>>(): T {
  return useNativeRouter().params as T;
}
