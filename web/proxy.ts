import { NextRequest, NextResponse } from "next/server";

const PUBLIC_PATHS = [
  "/", "/login", "/sign-up", "/terms", "/privacy", "/forgot-password",
  "/reset-password", "/billing/success", "/billing/cancel", "/pricing",
  "/ia-para-treino", "/treino-personalizado", "/emagrecimento",
  "/treino-em-casa", "/analise-de-exames", "/exercicios", "/sobre", "/precos",
];

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isPublic = PUBLIC_PATHS.some((p) =>
    p === "/" ? pathname === "/" : pathname.startsWith(p)
  );
  const sessionCookie = request.cookies.get("_eh_auth") ?? request.cookies.get("_easy_health_session");

  if (!isPublic && !sessionCookie) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|json|txt|xml|woff2?|ttf|eot)$).*)",
  ],
};
