"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { PlanCreationFlow } from "@/features/plan-creation/plan-creation-flow";
import { useAuth } from "@/features/auth/auth-context";
import { loadDraft } from "@/features/plan-creation/draft";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import { useIsHydrated, useIsNativePlatform } from "@/shared/lib/platform";
import { useAndroidPostOnboardingVariant } from "@/features/experiments/use-android-post-onboarding-variant";
import { exposeOnce, trackDestinationSelected } from "@/features/experiments/android-post-onboarding-gate";

// Único ponto de controle do onboarding. No Android o wizard roda ANTES da conta
// existir, então esta página precisa responder cinco perguntas antes de montar
// qualquer coisa: existe rascunho, existe sessão, é nativo, qual a variante do
// experimento, e o que fazer no fim.
//
//  rascunho | sessão | nativo | variante     | ação
//  ---------|--------|--------|--------------|-----------------------------------
//    sim    |  sim   |   —    |      —       | retoma e gera direto (volta do cadastro)
//    sim    |  não   |  sim   |      —       | continua o wizard onde parou
//    não    |  não   |  sim   | account_gate | wizard do zero, cadastro no fim
//    não    |  não   |  sim   | open_app     | wizard do zero, gera sem conta
//    não    |  não   |  não   |      —       | Web segue protegida: vai para /login
//    não    |  sim   |   —    |      —       | comportamento de sempre
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

  const baseReady = hydrated && !loading;
  // Só existe onboarding pré-auth no app nativo. Na Web o fluxo continua sendo
  // landing → cadastro → onboarting autenticado, e o guard abaixo garante isso.
  const preAuth = baseReady && !user && isNative;
  const blocked = baseReady && !user && !isNative;

  // O experimento decide o que acontece no FIM do wizard, mas a decisão precisa
  // estar pronta antes do COMEÇO: montar com a variante default e trocar depois
  // mostraria o gate de conta a quem foi sorteado para abrir o app.
  const variant = useAndroidPostOnboardingVariant({ authenticated: !!user, enabled: preAuth });
  const ready = baseReady && (!preAuth || variant.ready);
  const openApp = preAuth && variant.eligible && variant.variant === "open_app";

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
      // open_app não pede a conta aqui: a geração segue pelo modo anônimo e o
      // cadastro continua disponível no perfil, no 4º plano e no CTA de salvar.
      onRequireAuth={preAuth && !openApp ? () => router.push("/sign-up?from=onboarding") : undefined}
      // O resumo é o degrau comum: as duas variantes o veem, e é ele que separa
      // "desistiu das perguntas" de "viu o plano e recusou o que veio depois".
      withPreview={preAuth}
      // Só open_app gera sem conta. Em account_gate o wizard nem chega a gerar
      // aqui: ele entrega para /sign-up e a geração acontece depois, logada.
      submitMode={openApp ? "anonymous" : "authenticated"}
      autoGenerate={!!user && hadDraft}
      onBeforeFinish={(mode) => {
        if (!preAuth || !variant.eligible) return;
        // Aqui, e não na montagem da página nem no resumo: é neste ponto que a
        // variante muda o que acontece. Exposição sem bifurcação real infla o
        // denominador de todas as taxas do painel.
        exposeOnce(variant.variant);
        trackDestinationSelected(variant.variant, { onboarding_flow: mode });
      }}
      onDone={(_plan, mode) => {
        trackEvent(EVENTS.ONBOARDING_COMPLETED);
        trackOnboardingEvent("onboarding_completed", { onboardingFlow: mode });
        router.push(openApp ? "/plano/pronto" : "/workouts/ready");
      }}
    />
  );
}
