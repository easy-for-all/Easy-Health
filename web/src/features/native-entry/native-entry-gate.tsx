"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { useIsHydrated, useIsNativePlatform } from "@/shared/lib/platform";
import { NativeEntryLoading } from "./native-entry-loading";
import { NativeEntryScreen } from "./native-entry-screen";

export function NativeEntryGate() {
  const router = useRouter();
  const { user, loading } = useAuth();
  const hydrated = useIsHydrated();
  const isNative = useIsNativePlatform();

  useEffect(() => {
    if (!hydrated || loading) return;
    if (!isNative) {
      router.replace("/");
      return;
    }
    if (user) router.replace("/dashboard");
  }, [hydrated, isNative, loading, router, user]);

  if (!hydrated || loading || !isNative || user) return <NativeEntryLoading />;

  return <NativeEntryScreen />;
}
