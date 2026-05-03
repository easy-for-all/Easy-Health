"use server";

import { cookies } from "next/headers";

const SUPPORTED_LOCALES = ["pt-BR", "en-US"] as const;
type Locale = (typeof SUPPORTED_LOCALES)[number];

export async function setLocale(locale: Locale) {
  if (!SUPPORTED_LOCALES.includes(locale)) return;
  (await cookies()).set("locale", locale, {
    path: "/",
    maxAge: 60 * 60 * 24 * 365,
    sameSite: "lax",
  });
}
