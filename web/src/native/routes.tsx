import { lazy, type ComponentType, type LazyExoticComponent } from "react";

// Tabela de rotas do shell nativo — e, por consequência, a allowlist.
//
// Cada entrada aponta para O MESMO componente de página que o Next renderiza.
// Nada é copiado: `src/app/**/page.tsx` continua sendo a única implementação de
// cada tela, e este arquivo apenas diz quais delas o app nativo conhece.
//
// Rotas dinâmicas ficam como padrão ([id]), não como arquivos. Não existe — nem
// pode existir — um HTML por recurso dentro do IPA: /users/1, /users/2, ... é
// infinito. O id vira parâmetro e quem resolve é o Rails, em runtime.
//
// lazy() por rota para que o cold start carregue só o chunk da tela inicial;
// num shell local isso é a diferença entre abrir na hora e esperar o bundle
// inteiro parsear.

export type RouteLayout = "app" | "bare";

export interface NativeRoute {
  pattern: string;
  layout: RouteLayout;
  component: LazyExoticComponent<ComponentType<Record<string, never>>>;
}

const page = (loader: () => Promise<{ default: ComponentType<never> }>) =>
  lazy(loader as () => Promise<{ default: ComponentType<Record<string, never>> }>);

export const NATIVE_ROUTES: NativeRoute[] = [
  // Sem sessão
  { pattern: "/login", layout: "bare", component: page(() => import("@/app/login/page")) },
  { pattern: "/sign-up", layout: "bare", component: page(() => import("@/app/sign-up/page")) },
  { pattern: "/forgot-password", layout: "bare", component: page(() => import("@/app/forgot-password/page")) },
  { pattern: "/onboarding", layout: "bare", component: page(() => import("@/app/onboarding/page")) },

  // App autenticado
  { pattern: "/", layout: "app", component: page(() => import("@/app/(app)/dashboard/page")) },
  { pattern: "/dashboard", layout: "app", component: page(() => import("@/app/(app)/dashboard/page")) },
  { pattern: "/workouts", layout: "app", component: page(() => import("@/app/(app)/workouts/page")) },
  { pattern: "/workouts/ready", layout: "app", component: page(() => import("@/app/(app)/workouts/ready/page")) },
  { pattern: "/workout/today", layout: "app", component: page(() => import("@/app/(app)/workout/today/page")) },
  { pattern: "/workout/quick", layout: "app", component: page(() => import("@/app/(app)/workout/quick/page")) },
  { pattern: "/plan", layout: "app", component: page(() => import("@/app/(app)/plan/page")) },
  { pattern: "/history", layout: "app", component: page(() => import("@/app/(app)/history/page")) },
  { pattern: "/favorites", layout: "app", component: page(() => import("@/app/(app)/favorites/page")) },
  { pattern: "/profile", layout: "app", component: page(() => import("@/app/(app)/profile/page")) },
  { pattern: "/settings", layout: "app", component: page(() => import("@/app/(app)/settings/page")) },
  { pattern: "/billing", layout: "app", component: page(() => import("@/app/(app)/billing/page")) },
  { pattern: "/community", layout: "app", component: page(() => import("@/app/(app)/community/page")) },
  { pattern: "/users", layout: "app", component: page(() => import("@/app/(app)/users/page")) },

  // Dinâmicas — a prova de que o roteamento client-side resolve id em runtime.
  { pattern: "/users/[id]", layout: "app", component: page(() => import("@/app/(app)/users/[id]/page")) },
  { pattern: "/community/[id]", layout: "app", component: page(() => import("@/app/(app)/community/[id]/page")) },
];

export const NATIVE_ROUTE_PATTERNS = NATIVE_ROUTES.map((r) => r.pattern);

// Para onde vai qualquer coisa que não esteja na allowlist. "/" é seguro porque
// o AuthProvider decide entre dashboard e login a partir da sessão real.
export const NATIVE_FALLBACK_ROUTE = "/";

export function routeFor(pattern: string | null): NativeRoute | null {
  if (!pattern) return null;
  return NATIVE_ROUTES.find((r) => r.pattern === pattern) ?? null;
}
