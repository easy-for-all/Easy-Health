import { NextRequest, NextResponse } from "next/server";

const PUBLIC_PATHS = ["/", "/login", "/sign-up", "/terms", "/privacy", "/forgot-password", "/reset-password"];
const AUTH_REDIRECT_PATHS = ["/login", "/sign-up"];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isPublic = PUBLIC_PATHS.some((p) =>
    p === "/" ? pathname === "/" : pathname.startsWith(p)
  );
  const isAuthRedirect = AUTH_REDIRECT_PATHS.some((p) =>
    pathname.startsWith(p)
  );
  const sessionCookie = request.cookies.get("_easy_health_session");

  if (!isPublic && !sessionCookie) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  if (isAuthRedirect && sessionCookie) {
    return NextResponse.redirect(new URL("/profile", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next|favicon.ico|public).*)"],
};
