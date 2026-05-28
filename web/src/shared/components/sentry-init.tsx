"use client";

import { useEffect } from "react";
import { initSentry } from "@/shared/lib/sentry";

export function SentryInit() {
  useEffect(() => {
    initSentry();
  }, []);

  return null;
}
