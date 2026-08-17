import { Suspense, useEffect, useMemo } from "react";
import { NextIntlClientProvider } from "next-intl";
import { ThemeProvider } from "@/features/theme/theme-context";
import { AuthProvider } from "@/features/auth/auth-context";
import { ToastProvider } from "@/shared/components/ui/toast-provider";
import AppLayout from "@/app/(app)/layout";
import { setInternalNavigator } from "@/shared/lib/app-navigation";
import { NativeRouter, useNativeRouter } from "./router/router-context";
import { NATIVE_FALLBACK_ROUTE, NATIVE_ROUTE_PATTERNS, routeFor } from "./routes";
import messages from "../../messages/pt-BR.json";

// Shell do bundle nativo.
//
// Reproduz a árvore de providers do RootLayout do Next SEM as partes que só
// existem com servidor (getLocale/getMessages) e sem as tags <Script> de GTM e
// Clarity — no nativo o caminho de analytics é o Firebase via bridge, e injetar
// script remoto num app empacotado é exatamente o que a App Store 2.5.2 olha
// com desconfiança.
//
// Não é um segundo produto: as telas, o layout do app, o design system e os
// providers são os mesmos módulos que a Web usa.

// O catálogo pt-BR entra estático no bundle. O seletor de idioma é uma feature
// de perfil na Web; trazer a troca dinâmica para cá é trabalho de outro PR e
// não faz parte da prova do bundle local.
const LOCALE = "pt-BR";

function RouteOutlet() {
  const { pattern, pathname } = useNativeRouter();
  const route = routeFor(pattern);

  if (!route) {
    // Inalcançável na prática: o roteador já resolve para o fallback antes de
    // chegar aqui. Existe para que uma tabela mal editada falhe visivelmente.
    return <div style={{ padding: 24 }}>Rota não encontrada: {pathname}</div>;
  }

  const Page = route.component;
  const content = <Page {...({} as Record<string, never>)} />;

  return (
    <Suspense fallback={<BootSplash />}>
      {route.layout === "app" ? <AppLayout>{content}</AppLayout> : content}
    </Suspense>
  );
}

// Mostrado enquanto o chunk da rota carrega. Assets locais, sem rede: é o que
// faz a UI aparecer no cold start antes de qualquer resposta da API.
function BootSplash() {
  return (
    <div
      style={{
        minHeight: "100svh",
        display: "grid",
        placeItems: "center",
        background: "var(--bg)",
        color: "var(--text)",
      }}
    >
      <span style={{ opacity: 0.6, fontSize: 14 }}>Carregando…</span>
    </div>
  );
}

// Liga o roteador client-side ao adapter de navegação, para que o código
// compartilhado (auth-context, wizard, push) navegue sem tocar em
// window.location — que num bundle local pediria um documento inexistente.
function NavigationBridge({ children }: { children: React.ReactNode }) {
  const router = useNativeRouter();

  useEffect(() => {
    setInternalNavigator((path, mode) => {
      if (mode === "replace") router.replace(path);
      else router.push(path);
    });
    return () => setInternalNavigator(null);
  }, [router]);

  return <>{children}</>;
}

export function NativeAppShell({ initialPath }: { initialPath: string }) {
  const patterns = useMemo(() => NATIVE_ROUTE_PATTERNS, []);

  return (
    <NativeRouter
      patterns={patterns}
      fallback={NATIVE_FALLBACK_ROUTE}
      initialPath={initialPath}
    >
      <NavigationBridge>
        <NextIntlClientProvider locale={LOCALE} messages={messages}>
          <ThemeProvider>
            <AuthProvider>
              <ToastProvider>
                <RouteOutlet />
              </ToastProvider>
            </AuthProvider>
          </ThemeProvider>
        </NextIntlClientProvider>
      </NavigationBridge>
    </NativeRouter>
  );
}
