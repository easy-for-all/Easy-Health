import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const internalApiUrl = process.env.NEXT_INTERNAL_API_URL;

// O browser fala com a API cross-origin (api.easyhealth.art), então ela precisa
// estar explicitamente no connect-src. Derivado do mesmo build arg que o client
// usa em runtime para não divergir em staging; o literal é só o fallback de prod.
const apiOrigin = (() => {
  try {
    return new URL(process.env.NEXT_PUBLIC_API_URL ?? "").origin;
  } catch {
    return "https://api.easyhealth.art";
  }
})();

const securityHeaders = [
  // Prevents HTTPS downgrade attacks
  { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
  // Blocks MIME-type sniffing
  { key: "X-Content-Type-Options", value: "nosniff" },
  // Prevents clickjacking
  { key: "X-Frame-Options", value: "DENY" },
  // Controls referrer information sent with requests
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  // Restricts browser features
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  // Isolates browsing context
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  // Obfuscate server identity
  { key: "Server", value: "" },
  // CSP: unsafe-inline required for Next.js hydration; unsafe-eval only in dev (React Turbopack debug)
  {
    key: "Content-Security-Policy",
    value: [
      "default-src 'self'",
      `script-src 'self' 'unsafe-inline'${process.env.NODE_ENV === "development" ? " 'unsafe-eval'" : ""} https://static.cloudflareinsights.com https://www.googletagmanager.com https://www.clarity.ms https://scripts.clarity.ms https://googleads.g.doubleclick.net`,
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https://www.google.com https://www.google.com.br https://*.googletagmanager.com https://googleads.g.doubleclick.net https://c.clarity.ms https://api.easyhealth.art https://*.amazonaws.com",
      // Sem o `https:` genérico que existia aqui: ele liberava QUALQUER host HTTPS
      // e tornava decorativa a allowlist ao lado. A lista abaixo é montada a
      // partir dos destinos realmente usados pelo client.
      [
        "connect-src 'self'",
        apiOrigin,
        // GA4 usa endpoints regionais (region1.google-analytics.com etc.).
        "https://www.google-analytics.com https://*.google-analytics.com",
        "https://www.googletagmanager.com",
        // Conversões do Google Ads.
        "https://googleads.g.doubleclick.net https://www.google.com https://www.google.com.br",
        "https://*.sentry.io",
        "https://*.clarity.ms",
        // Beacon do Cloudflare Web Analytics, injetado na borda (o script já
        // está liberado em script-src).
        "https://cloudflareinsights.com",
        process.env.NODE_ENV === "development" ? "http://localhost:*" : "",
      ]
        .filter(Boolean)
        .join(" "),
      "font-src 'self'",
      "worker-src blob: 'self'",
      "object-src 'none'",
      "frame-ancestors 'none'",
      // Impede que uma <base> injetada reescreva a resolução de URLs relativas.
      "base-uri 'self'",
      // Impede que um form injetado poste para host externo.
      "form-action 'self'",
    ].join("; "),
  },
];

const nextConfig = {
  poweredByHeader: false,
  transpilePackages: ["framer-motion", "canvas-confetti", "html-to-image"],
  // @capacitor-firebase/* web builds statically import the firebase JS SDK, but
  // firebase is a NO-OP on web/PWA by design (GA4 handles web) and native uses
  // the Capacitor bridge. Alias the firebase subpaths to a stub so the build
  // resolves them without shipping the real SDK. See analytics/firebase-web-stub.ts.
  turbopack: {
    resolveAlias: {
      "firebase/analytics": "./src/shared/lib/analytics/firebase-web-stub.ts",
      "firebase/performance": "./src/shared/lib/analytics/firebase-web-stub.ts",
    },
  },
  devIndicators: false as const,
  allowedDevOrigins: ["easyhealth.art"],

  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },

  async rewrites() {
    if (!internalApiUrl) return [];
    return [
      {
        source: "/rails/:path*",
        destination: `${internalApiUrl}/rails/:path*`,
      },
      {
        source: "/exercise-images/db/:path*",
        destination: `${internalApiUrl}/exercise-images/db/:path*`,
      },
      {
        source: "/exercise-images/gifdotreino/:path*",
        destination: `${internalApiUrl}/exercise-images/gifdotreino/:path*`,
      },
    ];
  },
};

export default withNextIntl(nextConfig);
