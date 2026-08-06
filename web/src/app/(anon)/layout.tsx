"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { useIsHydrated, useIsNativePlatform } from "@/shared/lib/platform";
import "@/shared/components/ui/ui.css";

// O modo anônimo mora FORA do grupo (app).
//
// Aquele layout monta WorkoutSessionProvider, CoachProvider, TrialBanner,
// BottomNav e CoachFab — todos partem de que existe usuário — e as páginas
// dentro dele passam por UpgradeGate, que decide pelo billing_status. Ensinar o
// gate a tolerar anônimo espalharia a decisão de paywall por uma superfície que
// não deveria conhecê-la; separar os layouts mantém cada um com uma pergunta só.
export default function AnonLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { user, loading } = useAuth();
  const hydrated = useIsHydrated();
  const isNative = useIsNativePlatform();

  const ready = hydrated && !loading;
  // Web e PWA não têm modo anônimo, e quem já tem conta tem o app inteiro:
  // deixar um usuário logado aqui mostraria a versão reduzida do produto.
  const blocked = ready && (!isNative || !!user);

  useEffect(() => {
    if (!blocked) return;
    router.replace(user ? "/dashboard" : "/login");
  }, [blocked, user, router]);

  if (!ready || blocked) return null;

  return (
    <div
      style={{
        minHeight: "100svh",
        background: "var(--bg)",
        color: "var(--text)",
        paddingTop: "var(--safe-area-top)",
        paddingRight: "var(--safe-area-right)",
        paddingBottom: "calc(var(--safe-area-bottom) + 24px)",
        paddingLeft: "var(--safe-area-left)",
      }}
    >
      {children}
    </div>
  );
}
