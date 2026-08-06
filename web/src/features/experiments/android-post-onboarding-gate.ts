import { api } from "@/shared/lib/api";
import { trackEvent, trackOnce } from "@/shared/lib/analytics";
import { getAnalyticsContext, getCachedInstallationId, isNativeApp } from "@/shared/lib/analytics/context";

// A/B do que acontece no fim do onboarding pré-auth do Android.
//
//   account_gate  fluxo atual: resumo → /sign-up → conta → plano
//   open_app      abre a EasyHealth e gera o plano sem conta (modo anônimo)
//
// A decisão é do CLIENTE e é síncrona de propósito. Uma variante que só resolve
// depois de um round trip (ou depois de um hash assíncrono) resolve DEPOIS do
// primeiro render — e piscar entre "crie sua conta" e "abrir o app" mostra o
// tratamento errado para a pessoa antes de mostrar o certo. O backend registra
// a atribuição para dedup e junção; ele não a calcula.
export const EXPERIMENT_KEY = "android_post_onboarding_gate_v1";

export type PostOnboardingVariant = "account_gate" | "open_app";

export const VARIANTS: readonly PostOnboardingVariant[] = ["account_gate", "open_app"];

// O fluxo provado. Todo caminho de inelegibilidade, erro ou dado suspeito
// termina aqui — nunca no tratamento.
export const DEFAULT_VARIANT: PostOnboardingVariant = "account_gate";

const STORE_KEY = "eh_experiments";
const EXPOSED_KEY_PREFIX = "eh_experiments_exposed:";

export interface StoredAssignment {
  variant: PostOnboardingVariant;
  assigned_at: string;
  // Guardado JUNTO com a variante, e não implícito. O diretório do WebView entra
  // no Android Auto Backup, então um restore pode devolver um localStorage que
  // pertence à instalação ANTERIOR. Sem este campo, a instalação nova herdaria a
  // variante da antiga e as duas apareceriam como uma só no painel.
  installation_id: string;
}

export interface VariantDecision {
  variant: PostOnboardingVariant;
  eligible: boolean;
  // true apenas na primeira vez que esta instalação foi atribuída. É o que
  // impede experiment_assigned de ser reemitido a cada abertura do app.
  assigned: boolean;
}

const INELIGIBLE: VariantDecision = { variant: DEFAULT_VARIANT, eligible: false, assigned: false };

// ---------------------------------------------------------------- atribuição

// FNV-1a 32 bits. Escolhido por ser SÍNCRONO: crypto.subtle.digest é assíncrono
// e não serve para decidir o que renderizar. A distribuição de um hash não
// criptográfico é mais que suficiente aqui — o que se exige de um bucketer é
// espalhar bem, não resistir a adversário.
export function fnv1a(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    // Multiplicação pelo primo 16777619 sem estourar 32 bits em float.
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

// Determinística e estável: a mesma instalação recebe a mesma variante em
// qualquer dispositivo, sessão ou versão do app. O experiment_key entra no hash
// para que um experimento futuro não herde exatamente o mesmo corte de
// população que este — senão os dois mediriam sempre as mesmas pessoas.
export function variantForInstallation(installationId: string): PostOnboardingVariant {
  return VARIANTS[fnv1a(`${EXPERIMENT_KEY}:${installationId}`) % VARIANTS.length];
}

// ------------------------------------------------------------ elegibilidade

function flagEnabled(): boolean {
  // Default-OFF, ao contrário de NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED. Aquela
  // flag é default-ON porque NÃO rastrear foi a falha que escondeu a produção,
  // e rastrear é observacional. Esta muda o produto para metade das pessoas: um
  // build que chegue a um servidor onde a env nunca foi setada precisa cair no
  // comportamento provado, não no que ainda não foi medido.
  return process.env.NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED === "true";
}

function minBuild(): number | null {
  const raw = process.env.NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_MIN_BUILD;
  if (!raw || !/^\d+$/.test(raw)) return null;
  return Number(raw);
}

function startedAt(): number | null {
  const raw = process.env.NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT;
  if (!raw) return null;
  const parsed = Date.parse(raw);
  return Number.isNaN(parsed) ? null : parsed;
}

// O corte de build existe pelo mesmo motivo de ANDROID_FUNNEL_MIN_BUILD: uma
// instalação de um build que não emite os eventos do experimento apareceria no
// painel como abandono numa etapa que ela não tinha como alcançar.
function buildEligible(): boolean {
  const min = minBuild();
  if (min === null) return true;

  const raw = getAnalyticsContext().build_number;
  if (!raw || !/^\d+$/.test(raw)) return false; // build desconhecido não entra no experimento

  return Number(raw) >= min;
}

function windowOpen(): boolean {
  const start = startedAt();
  return start === null || Date.now() >= start;
}

// `authenticated` é passado de fora porque a sessão é conhecida pela página, não
// por este módulo — a mesma divisão que mantém o wizard ignorante sobre auth.
export function isEligible({ authenticated }: { authenticated: boolean }): boolean {
  if (authenticated) return false;
  if (!flagEnabled()) return false;
  if (!isNativeApp()) return false; // Web e PWA não participam
  if (!buildEligible()) return false;
  if (!windowOpen()) return false;
  return !!getCachedInstallationId();
}

// ------------------------------------------------------------- persistência

type ExperimentStore = Record<string, StoredAssignment>;

function readStore(): ExperimentStore {
  if (typeof window === "undefined") return {};
  try {
    const raw = window.localStorage.getItem(STORE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as ExperimentStore) : {};
  } catch {
    // Store corrompido é tratado como ausente: reatribuir é determinístico e
    // devolve exatamente a mesma variante, então não há nada a perder.
    return {};
  }
}

function writeStore(store: ExperimentStore): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORE_KEY, JSON.stringify(store));
  } catch {
    // Sem persistência a variante continua correta — o hash é determinístico.
    // O que se perde é a defesa contra o Auto Backup, não a estabilidade.
  }
}

function validStored(entry: unknown, installationId: string): StoredAssignment | null {
  if (!entry || typeof entry !== "object") return null;
  const candidate = entry as Partial<StoredAssignment>;
  if (!VARIANTS.includes(candidate.variant as PostOnboardingVariant)) return null;
  // Atribuição de OUTRA instalação (restore do Android Auto Backup): descartar.
  if (candidate.installation_id !== installationId) return null;
  return candidate as StoredAssignment;
}

// ------------------------------------------------------------------ decisão

// Lê a atribuição existente ou cria uma. Síncrona: nada aqui espera rede.
export function resolveVariant({ authenticated }: { authenticated: boolean }): VariantDecision {
  if (!isEligible({ authenticated })) return INELIGIBLE;

  const installationId = getCachedInstallationId();
  if (!installationId) return INELIGIBLE;

  const store = readStore();
  const stored = validStored(store[EXPERIMENT_KEY], installationId);
  if (stored) return { variant: stored.variant, eligible: true, assigned: false };

  const variant = variantForInstallation(installationId);
  store[EXPERIMENT_KEY] = { variant, assigned_at: new Date().toISOString(), installation_id: installationId };
  writeStore(store);

  return { variant, eligible: true, assigned: true };
}

// Registra a atribuição: evento + linha no backend. Fire-and-forget nos dois —
// a variante local já está decidida e uma falha de rede não pode mudá-la.
export function recordAssignment(variant: PostOnboardingVariant): void {
  const installationId = getCachedInstallationId();
  if (!installationId) return;

  trackOnce(`experiment_assigned:${EXPERIMENT_KEY}`, "experiment_assigned", {
    experiment_key: EXPERIMENT_KEY,
    variant,
    assignment_method: "installation_hash",
    source: "onboarding_preauth",
  });

  void api
    .post<{ status: string; variant?: PostOnboardingVariant }>("/api/v1/experiments/assignments", {
      experiment_key: EXPERIMENT_KEY,
      variant,
      installation_id: installationId,
    })
    .then((response) => {
      // O banco é o desempate: se já existe linha com outra variante, ela é a
      // que teve exposição medida. Adotamos para as próximas aberturas em vez de
      // trocar o que está na tela — trocar agora mostraria dois tratamentos para
      // a mesma pessoa, que é exatamente o que o índice único evita.
      const authoritative = response?.variant;
      if (!authoritative || authoritative === variant) return;
      if (!VARIANTS.includes(authoritative)) return;

      const store = readStore();
      store[EXPERIMENT_KEY] = {
        variant: authoritative,
        assigned_at: new Date().toISOString(),
        installation_id: installationId,
      };
      writeStore(store);
    })
    .catch(() => {
      // Uma atribuição não gravada custa uma linha de conferência. O funil vive
      // no pipeline de eventos, que tem fila e retry próprios.
    });
}

// ---------------------------------------------------------------- exposição

function exposureKey(): string {
  return `${EXPOSED_KEY_PREFIX}${EXPERIMENT_KEY}`;
}

export function hasBeenExposed(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(exposureKey()) !== null;
  } catch {
    return false;
  }
}

function markExposed(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(exposureKey(), new Date().toISOString());
  } catch {
    // trackOnce ainda cobre o double render desta sessão.
  }
}

// Emitida SÓ quando a variante realmente muda a experiência — no fim do
// onboarding, no momento do desvio. Não na montagem da página (nem todo mundo
// chega ao fim) e não no resumo (as duas variantes o veem). Uma exposição que
// não corresponde a uma bifurcação real infla o denominador de todas as taxas.
//
// Dedup em dois níveis porque um só não basta: trackOnce cobre o double render
// do StrictMode dentro de um carregamento; o marcador persistido cobre reload,
// volta da Activity do Google e nova sessão.
export function exposeOnce(variant: PostOnboardingVariant): void {
  if (hasBeenExposed()) return;
  markExposed();

  trackOnce(`experiment_exposed:${EXPERIMENT_KEY}`, "experiment_exposed", {
    experiment_key: EXPERIMENT_KEY,
    variant,
    exposure_point: "onboarding_completed",
  });
}

// O desvio propriamente dito, registrado onde ele acontece.
export function trackDestinationSelected(
  variant: PostOnboardingVariant,
  extra: { onboarding_flow?: string } = {}
): void {
  trackEvent("post_onboarding_destination_selected", {
    experiment_key: EXPERIMENT_KEY,
    variant,
    destination: variant === "open_app" ? "app" : "account_gate",
    ...extra,
  });
}

// Só para os testes: o módulo guarda estado em localStorage e o trackOnce tem
// um Set global de processo.
export function __resetStoreForTests(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(STORE_KEY);
    window.localStorage.removeItem(exposureKey());
  } catch {
    /* nada a limpar */
  }
}
