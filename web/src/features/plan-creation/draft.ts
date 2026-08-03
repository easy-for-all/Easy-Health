import { buildInitialForm, type CreationMode, type StepId, type WizardFormState } from "./types";

// Rascunho local do wizard de criação de plano.
//
// O wizard vive inteiro em useState: um reload do WebView, uma morte de processo
// ou um gesto de voltar apagavam 6 telas de respostas sem recuperação. Isso já era
// ruim no fluxo autenticado; passa a ser crítico quando o onboarding acontece
// ANTES da conta, porque o app sai para a Activity nativa do Google no meio.
//
// localStorage e não @capacitor/preferences: a escrita acontece a cada passo e
// precisa ser síncrona, e o rascunho NÃO deve sobreviver a uma reinstalação —
// exatamente o oposto do installation_id, que é excluído do Android Auto Backup
// justamente para sobreviver a uma. Mesmo meio de eh_anon_id / eh_consent.
const KEY = "eh_onboarding_draft";

// 24h: tempo suficiente para o usuário sair para autenticar, ser interrompido e
// voltar; curto o bastante para não retomar respostas que já não descrevem a
// pessoa. Passado o prazo o rascunho é apagado na leitura, não só ignorado.
const TTL_MS = 24 * 60 * 60 * 1000;

// Versão do formato. Um rascunho gravado por um build cujo WizardFormState tinha
// outra forma é descartado em vez de hidratar o wizard pela metade.
const VERSION = 1;

export interface PlanCreationDraft {
  mode: CreationMode;
  stepId: StepId;
  form: WizardFormState;
  savedAt: number;
}

interface StoredDraft extends PlanCreationDraft {
  version: number;
}

function hasWindow(): boolean {
  return typeof window !== "undefined";
}

export function saveDraft(draft: Omit<PlanCreationDraft, "savedAt">): void {
  try {
    if (!hasWindow()) return;
    const payload: StoredDraft = { ...draft, savedAt: Date.now(), version: VERSION };
    window.localStorage.setItem(KEY, JSON.stringify(payload));
  } catch {
    /* storage indisponível (modo privado, cota) — perder o rascunho nunca pode quebrar o wizard */
  }
}

export function clearDraft(): void {
  try {
    if (hasWindow()) window.localStorage.removeItem(KEY);
  } catch {
    /* idem */
  }
}

// Retorna o rascunho apenas se ele ainda for utilizável. Qualquer motivo para
// desconfiar — JSON inválido, versão antiga, prazo vencido, forma inesperada —
// resulta em null E na remoção da chave, para que a próxima leitura não repita o
// mesmo trabalho nem deixe lixo para trás.
export function loadDraft(): PlanCreationDraft | null {
  let raw: string | null = null;
  try {
    raw = hasWindow() ? window.localStorage.getItem(KEY) : null;
  } catch {
    return null;
  }
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as Partial<StoredDraft>;
    if (parsed?.version !== VERSION) return discard();
    if (typeof parsed.savedAt !== "number" || Date.now() - parsed.savedAt > TTL_MS) return discard();
    if (parsed.mode !== "quick" && parsed.mode !== "complete") return discard();
    if (typeof parsed.stepId !== "string") return discard();
    if (!parsed.form || typeof parsed.form !== "object") return discard();

    return {
      mode: parsed.mode,
      stepId: parsed.stepId as StepId,
      // Mesclado sobre o formulário inicial: um build que acrescente um campo
      // novo ao WizardFormState lê rascunhos antigos com o default do campo em
      // vez de undefined, que quebraria as telas silenciosamente.
      form: { ...buildInitialForm(), ...parsed.form },
      savedAt: parsed.savedAt,
    };
  } catch {
    return discard();
  }
}

function discard(): null {
  clearDraft();
  return null;
}
