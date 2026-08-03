"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { PlanCreationFlow } from "@/features/plan-creation/plan-creation-flow";
import { useAuth } from "@/features/auth/auth-context";
import { loadDraft } from "@/features/plan-creation/draft";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import { useIsHydrated, useIsNativePlatform } from "@/shared/lib/platform";

// Único ponto de controle do onboarding. No Android o wizard roda ANTES da conta
// existir, então esta página precisa responder quatro perguntas antes de montar
// qualquer coisa: existe rascunho, existe sessão, é nativo, e o que fazer no fim.
//
//  rascunho | sessão | nativo | ação
//  ---------|--------|--------|----------------------------------------------
//    sim    |  sim   |   —    | retoma e gera direto (volta do cadastro)
//    sim    |  não   |  sim   | continua o wizard onde parou
//    não    |  não   |  sim   | wizard do zero, cadastro no fim
//    não    |  não   |  não   | Web segue protegida: vai para /login
//    não    |  sim   |   —    | comportamento de sempre
export default function OnboardingPage() {
  const router = useRouter();
  const { user, loading } = useAuth();
  // Lido uma vez, antes de o wizard consumir e limpar o rascunho: depois da
  // geração ele não existe mais, e a decisão de retomar precisa ser estável.
  const [hadDraft] = useState(() => !!loadDraft());
  // O wizard retoma o rascunho local já na inicialização do estado, e localStorage
  // não existe no servidor. Montá-lo só depois da hidratação faz o primeiro render
  // dele acontecer uma vez só, no cliente, em vez de divergir do HTML prerenderizado.
  const hydrated = useIsHydrated();
  // A MESMA detecção que a tela de entrada usa. Se as duas discordarem, o app
  // manda a pessoa para um fluxo e depois a trata como se fosse do outro.
  const isNative = useIsNativePlatform();

  const ready = hydrated && !loading;
  // Só existe onboarding pré-auth no app nativo. Na Web o fluxo continua sendo
  // landing → cadastro → onboarting autenticado, e o guard abaixo garante isso.
  const preAuth = ready && !user && isNative;
  const blocked = ready && !user && !isNative;

  useEffect(() => {
    if (!blocked) return;
    router.replace("/login");
  }, [blocked, router]);

  useEffect(() => {
    if (!ready || blocked) return;
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
    trackOnboardingEvent("onboarding_started", { stepName: "choose_flow" });
  }, [ready, blocked]);

  // Volta do cadastro com respostas no dispositivo. Sem este evento, um cadastro
  // que veio do onboarding pré-auth fica idêntico no funil a um que começou do zero.
  useEffect(() => {
    if (!ready || !user || !hadDraft) return;
    const draft = loadDraft();
    if (!draft) return;
    trackEvent("onboarding_draft_resumed", { onboarding_flow: draft.mode, step_id: draft.stepId });
    // A atribuição do fluxo vive em users.onboarding_flow e é escrita pelo
    // endpoint autenticado, que não existia quando a escolha foi feita.
    trackOnboardingEvent("onboarding_flow_selected", { onboardingFlow: draft.mode });
  }, [ready, user, hadDraft]);

  if (!ready || blocked) return null;

  return (
    <PlanCreationFlow
      entryMode="onboarding"
      initialProfile={null}
      onRequireAuth={preAuth ? () => router.push("/sign-up?from=onboarding") : undefined}
      autoGenerate={!!user && hadDraft}
      onDone={(_plan, mode) => {
        trackEvent(EVENTS.ONBOARDING_COMPLETED);
        trackOnboardingEvent("onboarding_completed", { onboardingFlow: mode });
        router.push("/workouts/ready");
      }}
    />
  );
}
