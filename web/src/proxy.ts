import { type NextRequest, NextResponse } from "next/server";

const PUBLIC_PATHS = [
  "/", "/login", "/sign-up", "/terms", "/privacy", "/forgot-password",
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
