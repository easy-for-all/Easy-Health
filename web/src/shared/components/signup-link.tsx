"use client";

import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";
import { trackSignupSelected } from "@/features/auth/auth-analytics";

// The landing page is a server component, so its "Criar conta" links cannot
// carry an onClick. Without this wrapper signup_selected would count only the
// header and hero CTAs while auth_screen_viewed counted every arrival, and the
// funnel step would look broken instead of merely unattributed.
export function SignupLink({
  children,
  style,
  className,
}: {
  children: ReactNode;
  style?: CSSProperties;
  className?: string;
}) {
  return (
    <Link
      href="/sign-up"
      onClick={() => trackSignupSelected("landing")}
      style={style}
      className={className}
    >
      {children}
    </Link>
  );
}
