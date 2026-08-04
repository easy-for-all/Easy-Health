"use client";

import { useEffect, useState } from "react";
import { getInstallationId } from "@/shared/lib/analytics/installation";
import {
  DEFAULT_VARIANT,
  recordAssignment,
  resolveVariant,
  type PostOnboardingVariant,
} from "./android-post-onboarding-gate";

export interface PostOnboardingVariantState {
  // false até a decisão estar tomada. Quem consome PRECISA segurar o render do
  // fim do onboarding até aqui: montar com o default e trocar depois mostraria
  // "crie sua conta" antes de abrir o app, que é o tratamento errado.
  ready: boolean;
  variant: PostOnboardingVariant;
  eligible: boolean;
}

const PENDING: PostOnboardingVariantState = { ready: false, variant: DEFAULT_VARIANT, eligible: false };
const NOT_IN_EXPERIMENT: PostOnboardingVariantState = { ready: true, variant: DEFAULT_VARIANT, eligible: false };

// A variante do experimento de fim de onboarding, resolvida uma vez por
// montagem. É assíncrona por um motivo só: no app nativo o installation_id vive
// em @capacitor/preferences e ainda pode não ter sido lido no primeiro paint.
// Tudo depois disso é síncrono e determinístico.
export function useAndroidPostOnboardingVariant({
  authenticated,
  enabled = true,
}: {
  authenticated: boolean;
  // Permite ao chamador não entrar no experimento de jeito nenhum (ex.: a Web,
  // que nem chega a este fluxo). Inelegível não persiste e não emite nada.
  enabled?: boolean;
}): PostOnboardingVariantState {
  const [state, setState] = useState<PostOnboardingVariantState>(PENDING);

  useEffect(() => {
    if (!enabled || authenticated) {
      setState(NOT_IN_EXPERIMENT);
      return;
    }

    // Entrar no experimento volta o estado para indeciso. `enabled` costuma
    // virar true só depois da hidratação, e sem este reset a página leria
    // `ready: true` com a variante default por um render — tempo suficiente
    // para renderizar o gate de conta para alguém sorteado em open_app.
    setState(PENDING);

    let active = true;

    void (async () => {
      // Resolve o id antes de decidir. Falhar aqui não é motivo para tratar:
      // sem identidade estável não há como manter a variante entre sessões.
      await getInstallationId().catch(() => undefined);
      if (!active) return;

      // resolveVariant é síncrona e grava no localStorage antes de retornar, então
      // o segundo efeito do StrictMode já lê `assigned: false` e não regrava nada.
      const decision = resolveVariant({ authenticated });
      if (decision.assigned) recordAssignment(decision.variant);

      setState({ ready: true, variant: decision.variant, eligible: decision.eligible });
    })();

    return () => {
      active = false;
    };
  }, [authenticated, enabled]);

  return state;
}
