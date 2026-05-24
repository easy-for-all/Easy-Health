"use client";

import Link from "next/link";
import { analytics } from "@/shared/lib/analytics";

export function HeroCta() {
  return (
    <Link
      href="/sign-up"
      onClick={() => analytics.ctaClick("hero")}
      className="w-full rounded-xl bg-primary-500 px-8 py-4 text-base font-semibold text-white hover:bg-primary-600 sm:w-auto"
    >
      Começar grátis — sem cartão
    </Link>
  );
}
