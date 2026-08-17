import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/postcss";
import path from "path";

// Build do bundle nativo (iOS). Gera assets estáticos locais que vão dentro do
// IPA — sem servidor Next em runtime e sem server.url.
//
// Por que Vite e não `next build`: o app tem seis segmentos dinâmicos de id não
// limitado (/users/[id], /community/[id], ...), e `output: "export"` exige
// generateStaticParams com conjunto fechado para cada um. Inventar ids seria
// mentira, e a alternativa correta num app é resolver rota em runtime — que é o
// que este bundle faz.
//
// O truque que mantém isto barato: os aliases abaixo. Os 51 arquivos que
// importam next/navigation e os 49 que importam next/link continuam idênticos;
// quem muda é a implementação por trás do import. Sem eles, seria preciso
// reescrever a navegação inteira do produto.
export default defineConfig({
  root: path.resolve(__dirname, "src/native"),
  // Caminhos relativos: o WebView serve de capacitor://localhost, e um bundle
  // com URLs absolutas de asset quebraria fora da raiz.
  base: "./",
  plugins: [react()],
  css: {
    postcss: { plugins: [tailwindcss()] },
  },
  resolve: {
    alias: [
      { find: "next/navigation", replacement: path.resolve(__dirname, "src/native/adapters/navigation.ts") },
      { find: "next/link", replacement: path.resolve(__dirname, "src/native/adapters/link.tsx") },
      { find: "next/image", replacement: path.resolve(__dirname, "src/native/adapters/image.tsx") },
      // Mesmo stub que o next.config.ts usa: os pacotes @capacitor-firebase/*
      // importam o SDK JS do Firebase estaticamente na implementação web, mas
      // no nativo quem responde é a bridge e o SDK JS nunca roda. Sem isto o
      // bundle tenta resolver um peer opcional que não está instalado.
      { find: "firebase/analytics", replacement: path.resolve(__dirname, "src/shared/lib/analytics/firebase-web-stub.ts") },
      { find: "firebase/performance", replacement: path.resolve(__dirname, "src/shared/lib/analytics/firebase-web-stub.ts") },
      { find: "@", replacement: path.resolve(__dirname, "src") },
    ],
  },
  define: {
    // NEXT_PUBLIC_* é inlinado pelo Next no build da Web; aqui precisa ser
    // inlinado explicitamente. NATIVE_LOCAL_BUNDLE é o que liga o caminho de
    // MobileSession — ver mobile-session.ts.
    "process.env.NEXT_PUBLIC_NATIVE_LOCAL_BUNDLE": JSON.stringify("true"),
    "process.env.NEXT_PUBLIC_API_URL": JSON.stringify(
      process.env.NEXT_PUBLIC_API_URL ?? "https://api.easyhealth.art"
    ),
    "process.env.NEXT_PUBLIC_FRONTEND_URL": JSON.stringify(
      process.env.NEXT_PUBLIC_FRONTEND_URL ?? "https://easyhealth.art"
    ),
    "process.env.NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID": JSON.stringify(
      process.env.NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID ?? ""
    ),
    "process.env.NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED": JSON.stringify(
      process.env.NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED ?? "true"
    ),
    "process.env.NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED": JSON.stringify(
      process.env.NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED ?? "false"
    ),
    "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV ?? "production"),
  },
  build: {
    outDir: path.resolve(__dirname, "out-native"),
    emptyOutDir: true,
    sourcemap: false,
    target: "es2020",
  },
});
