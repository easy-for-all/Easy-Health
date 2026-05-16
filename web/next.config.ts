import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const internalApiUrl = process.env.NEXT_INTERNAL_API_URL;

export default withNextIntl({
  async rewrites() {
    if (!internalApiUrl) return [];
    return [
      {
        source: "/rails/:path*",
        destination: `${internalApiUrl}/rails/:path*`,
      },
    ];
  },
});
