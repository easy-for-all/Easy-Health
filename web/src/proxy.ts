import { type NextRequest, NextResponse } from "next/server";

// "Public" here means only "this middleware does not redirect it". Each page is
// still responsible for its own access rules.
//
// /onboarding is the destination of every successful sign-up, and it is reached
// by a client navigation that happens the instant the API answers. The auth
// cookie is set by api.easyhealth.art on a cross-site response, so there is a
// window where this middleware runs on easyhealth.art and does not see
// _eh_auth yet — and it was bouncing the brand-new account straight back to
// /login. The page itself requires a session via AuthProvider, so letting the
// request through costs nothing and closes that race.
const PUBLIC_PATHS = [
  "/", "/login", "/sign-up", "/onboarding", "/terms", "/privacy", "/forgot-password",
  "/reset-password", "/billing/success", "/billing/cancel", "/pricing",
  "/ia-para-treino", "/treino-personalizado", "/emagrecimento",
  "/treino-em-casa", "/analise-de-exames", "/exercicios", "/sobre", "/precos",
];

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const requestId = crypto.randomUUID();

  const isPublic = PUBLIC_PATHS.some((p) =>
    p === "/" ? pathname === "/" : pathname.startsWith(p)
  );
  const sessionCookie = request.cookies.get("_eh_auth") ?? request.cookies.get("_easy_health_session");

  if (!isPublic && !sessionCookie) {
    return withCorrelationHeaders(
      NextResponse.redirect(new URL("/login", request.url)),
      requestId
    );
  }

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("X-Request-Id", requestId);

  return withCorrelationHeaders(
    NextResponse.next({
      request: {
        headers: requestHeaders,
      },
    }),
    requestId
  );
}

function withCorrelationHeaders(response: NextResponse, requestId: string) {
  response.headers.set("X-Request-Id", requestId);
  response.headers.set("X-Correlation-Id", requestId);

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|json|txt|xml|woff2?|ttf|eot)$).*)",
  ],
};
