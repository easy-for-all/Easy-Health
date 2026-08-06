"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { TimelineEvent, TimelineResponse } from "./types";
import { formatDateTime } from "./metric-cell";

// Collapsible investigation panel. Not a card — it lives below the tables so
// the six-card contract is unaffected.
//
// PRIVACY: the backend returns event names, timestamps and a small allow-list
// of enum fields. There is no email, name, token or raw property blob to
// render, and this component must never start showing one.

const EVENT_LABEL: Record<string, string> = {
  app_first_open: "App aberto (primeira vez)",
  app_opened: "App aberto",
  session_started: "Sessão iniciada",
  web_session_started: "Sessão web iniciada",
  // Pre-auth steps: Android builds may start from the native entry screen or
  // from the historical landing page, then continue into auth.
  landing_page_viewed: "Landing exibida",
  native_entry_viewed: "Entrada nativa exibida",
  // No Android estas duas acontecem ANTES da autenticação.
  onboarding_started: "Onboarding iniciado",
  plan_preview_viewed: "Resumo do plano exibido",
  onboarding_draft_resumed: "Rascunho retomado",
  auth_consent_blocked: "Bloqueado por falta de aceite",
  auth_screen_viewed: "Tela de acesso exibida",
  auth_provider_clicked: "Tentou autenticar",
  signup_selected: "Escolheu criar conta",
  login_selected: "Escolheu entrar",
  signup_started: "Cadastro por email enviado",
  login_started: "Login por email enviado",
  login_failed: "Login por email falhou",
  social_login_started: "Tocou em entrar com Google",
  social_login_failed: "Google falhou no dispositivo",
  social_login_completed: "Google concluído no dispositivo",
  auth_client_error: "Erro no dispositivo",
  auth_api_error: "Erro retornado pela API",
  google_auth_started: "Autenticação iniciada",
  google_auth_succeeded: "Autenticação concluída",
  google_auth_failed: "Autenticação falhou",
  email_auth_started: "Auth por e-mail chegou à API",
  email_auth_succeeded: "Auth por e-mail concluída",
  email_auth_failed: "Auth por e-mail falhou",
  android_registration_started: "Cadastro iniciado",
  android_registration_succeeded: "Cadastro concluído",
  android_registration_failed: "Cadastro falhou",
  installation_link_succeeded: "Vínculo realizado",
  installation_link_failed: "Vínculo falhou",
  signup_completed: "Conta criada",
  login_completed: "Login concluído",
  workout_created: "Treino criado",
  workout_started: "Treino iniciado",
  workout_completed: "Treino concluído",
};

// The user dismissed the account picker. Read from failure_category, never from
// the error code text: the category is a closed vocabulary the backend validates.
function isUserCancelled(event: TimelineEvent): boolean {
  return event.failure_category === "user_cancelled";
}

function timelinePath(user: string, installation: string): string {
  const params = new URLSearchParams();
  if (user) params.set("user_id", user);
  if (installation) params.set("installation_id", installation);
  return `/api/v1/admin/observability/timeline?${params.toString()}`;
}

// Entry point for the "Funil Android Externo" block, which links each
// installation of an abandonment bucket straight to its timeline.
//
// Read from window.location instead of useSearchParams: this page is statically
// prerendered, and useSearchParams would force a Suspense boundary around the
// whole panel (Next fails the production build otherwise). The panel never
// reaches the server anyway — the page renders a loading screen until the admin
// gate resolves on the client.
function deepLinkedInstallationId(): string {
  if (typeof window === "undefined") return "";
  return new URLSearchParams(window.location.search).get("installation_id")?.trim() ?? "";
}

export function InvestigationTimeline() {
  const [userId, setUserId] = useState("");
  const [installationId, setInstallationId] = useState(deepLinkedInstallationId);
  const [data, setData] = useState<TimelineResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deepLinked] = useState(() => deepLinkedInstallationId() !== "");

  // Only the resolved request writes state: a setState in the body of an effect
  // triggers a cascading render (react-hooks/set-state-in-effect).
  useEffect(() => {
    const fromUrl = deepLinkedInstallationId();
    if (!fromUrl) return;

    let active = true;
    api
      .get<TimelineResponse>(timelinePath("", fromUrl))
      .then((result) => active && setData(result))
      .catch(() => active && setError("Não foi possível carregar a linha do tempo."));

    return () => {
      active = false;
    };
  }, []);

  async function search(event: React.FormEvent) {
    event.preventDefault();
    if (!userId.trim() && !installationId.trim()) {
      setError("Informe um ID interno de usuário ou um installation ID.");
      return;
    }

    setLoading(true);
    setError(null);
    try {
      setData(await api.get<TimelineResponse>(timelinePath(userId.trim(), installationId.trim())));
    } catch {
      setError("Não foi possível carregar a linha do tempo.");
      setData(null);
    } finally {
      setLoading(false);
    }
  }

  return (
    <details
      open={deepLinked}
      className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4"
    >
      <summary className="cursor-pointer text-sm font-semibold text-[var(--text)]">
        Investigação por usuário ou instalação
      </summary>

      <form onSubmit={search} className="mt-3 flex flex-col gap-2 sm:flex-row">
        <input
          type="text"
          inputMode="numeric"
          value={userId}
          onChange={(e) => setUserId(e.target.value)}
          placeholder="ID interno do usuário"
          aria-label="ID interno do usuário"
          className="w-full rounded-xl border border-[var(--border)] bg-[var(--bg)] px-3 py-2 text-sm text-[var(--text)] sm:w-56"
        />
        <input
          type="text"
          value={installationId}
          onChange={(e) => setInstallationId(e.target.value)}
          placeholder="Installation ID"
          aria-label="Installation ID"
          className="w-full rounded-xl border border-[var(--border)] bg-[var(--bg)] px-3 py-2 text-sm text-[var(--text)] sm:flex-1"
        />
        <button
          type="submit"
          disabled={loading}
          className="rounded-xl bg-primary-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {loading ? "Buscando..." : "Buscar"}
        </button>
      </form>

      <p className="mt-2 text-xs text-[var(--text-dim)]">
        Retorna apenas eventos e horários. Nenhum e-mail, nome, token ou payload é exibido.
      </p>

      {error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}

      {data ? (
        <div className="mt-4">
          <dl className="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
            <div>
              <dt className="text-[var(--text-dim)]">Usuário</dt>
              <dd className="text-[var(--text)]">{data.subject.user_ref ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-[var(--text-dim)]">Instalação</dt>
              <dd className="text-[var(--text)]">
                {data.subject.installation_found
                  ? data.subject.installation_linked
                    ? "encontrada e vinculada"
                    : "encontrada, anônima"
                  : "não encontrada"}
              </dd>
            </div>
            <div>
              <dt className="text-[var(--text-dim)]">Build</dt>
              <dd className="text-[var(--text)]">
                {data.subject.app_version ?? "—"}
                {data.subject.app_build ? ` (${data.subject.app_build})` : ""}
              </dd>
            </div>
            <div>
              <dt className="text-[var(--text-dim)]">Última autenticação</dt>
              <dd className="text-[var(--text)]">{formatDateTime(data.subject.last_authenticated_at)}</dd>
            </div>
          </dl>

          {data.events.length === 0 ? (
            <p className="mt-4 text-sm text-[var(--text-muted)]">Nenhum evento registrado para este alvo.</p>
          ) : (
            <ol className="mt-4 space-y-2">
              {data.events.map((event, index) => (
                <li
                  key={`${event.event_name}-${event.occurred_at}-${index}`}
                  className="flex flex-col gap-0.5 rounded-xl border border-[var(--border)] p-2.5 sm:flex-row sm:items-baseline sm:justify-between"
                >
                  <span className="text-sm text-[var(--text)]">
                    {EVENT_LABEL[event.event_name] ?? event.event_name}
                    {/* A cancellation is a deliberate exit, not a defect. Painting
                        it red made every investigation start by ruling out a bug
                        that was never there — so it reads as an outcome, in the
                        same neutral tone as the other dimensions. */}
                    {isUserCancelled(event) ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">
                        Login Google cancelado pelo usuário
                      </span>
                    ) : event.error_code ? (
                      <span className="ml-2 text-xs text-red-600 dark:text-red-400">{event.error_code}</span>
                    ) : null}
                    {event.auth_flow ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">{event.auth_flow}</span>
                    ) : null}
                    {event.provider ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">{event.provider}</span>
                    ) : null}
                    {event.auth_screen ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">{event.auth_screen}</span>
                    ) : null}
                    {event.intent ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">{event.intent}</span>
                    ) : null}
                    {event.terms_accepted !== undefined ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">terms={event.terms_accepted}</span>
                    ) : null}
                    {event.stage ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">{event.stage}</span>
                    ) : null}
                    {event.http_status ? (
                      <span className="ml-2 text-xs text-[var(--text-dim)]">HTTP {event.http_status}</span>
                    ) : null}
                  </span>
                  <span className="text-xs text-[var(--text-dim)]">{formatDateTime(event.occurred_at)}</span>
                </li>
              ))}
            </ol>
          )}
        </div>
      ) : null}
    </details>
  );
}
