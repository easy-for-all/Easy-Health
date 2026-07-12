"use client";

import { useEffect } from "react";
import { Capacitor, SystemBars, SystemBarsStyle } from "@capacitor/core";
import { usePathname } from "next/navigation";
import { useTheme } from "@/features/theme/theme-context";

const DARK_SURFACE_PREFIXES = ["/sign-up", "/workout"];

export function SystemBarsController() {
  const pathname = usePathname();
  const { theme } = useTheme();

  useEffect(() => {
    if (!Capacitor.isNativePlatform() || Capacitor.getPlatform() !== "android") {
      return;
    }

    const isDarkSurface =
      theme === "dark" || DARK_SURFACE_PREFIXES.some((prefix) => pathname.startsWith(prefix));
    const style = isDarkSurface ? SystemBarsStyle.Dark : SystemBarsStyle.Light;

    void SystemBars.setStyle({ style }).catch(() => undefined);
  }, [pathname, theme]);

  return null;
}
