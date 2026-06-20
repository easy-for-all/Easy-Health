import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const internalApiUrl = process.env.NEXT_INTERNAL_API_URL;

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
      `connect-src 'self' https: https://www.google-analytics.com https://googleads.g.doubleclick.net https://*.sentry.io https://*.clarity.ms${process.env.NODE_ENV === "development" ? " http://localhost:*" : ""}`,
      "font-src 'self'",
      "worker-src blob: 'self'",
      "object-src 'none'",
      "frame-ancestors 'none'",
    ].join("; "),
  },
];

const nextConfig = {
  poweredByHeader: false,
  transpilePackages: ["framer-motion", "canvas-confetti", "html-to-image"],

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
