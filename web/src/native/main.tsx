import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { NativeAppShell } from "./app-shell";
import { resolveExternalRoute } from "./router/match";
import { NATIVE_FALLBACK_ROUTE, NATIVE_ROUTE_PATTERNS } from "./routes";
import "@/app/globals.css";

// Entrypoint do bundle nativo. Um único index.html carrega isto; a partir daí
// tudo é roteamento client-side contra o Rails remoto.

// A rota inicial pode vir de fora: cold start por deep link, ou o app sendo
// reaberto numa URL que o WKWebView preservou. Passa pela allowlist antes de
// virar navegação — uma URL arbitrária nunca deve conseguir escolher a tela.
function initialPath(): string {
  const fromLocation = window.location.pathname + window.location.search;
  return resolveExternalRoute(fromLocation, NATIVE_ROUTE_PATTERNS, NATIVE_FALLBACK_ROUTE);
}

// Aplica o tema antes do primeiro paint, como o <script> inline faz no
// RootLayout da Web. Sem isto o app pisca claro antes de virar escuro.
function applyStoredTheme(): void {
  try {
    if (localStorage.getItem("theme") === "dark") {
      document.documentElement.classList.add("dark");
    }
  } catch {
    // Storage indisponível: segue no tema claro.
  }
}

applyStoredTheme();

const container = document.getElementById("root");
if (!container) throw new Error("Native shell: #root not found in index.html");

createRoot(container).render(
  <StrictMode>
    <NativeAppShell initialPath={initialPath()} />
  </StrictMode>
);
