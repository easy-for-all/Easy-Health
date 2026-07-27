"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { api } from "@/shared/lib/api";

type DeliveryStatus =
  | "pending"
  | "sending"
  | "accepted_by_make"
  | "retrying"
  | "failed_to_reach_make"
  | "dead_letter"
  | "disabled"
  | "skipped";

type MakeStatus = "unknown" | "received" | "routed" | "filtered" | "completed" | "failed";

type DeliveryUser = {
  id: number;
  admin_display_id: string;
  name: string | null;
  display_name: string;
  email: string;
};

type DeliveryRow = {
  id: number;
  event_name: string;
  occurred_at: string | null;
  created_at: string | null;
  user: DeliveryUser | null;
  channels: string[];
  destination: string | null;
  delivery_status: DeliveryStatus;
  attempt_count: number;
  http_status: number | null;
  make_status: MakeStatus;
};

type DeliveryDetail = DeliveryRow & {
  source: string;
  first_attempt_at: string | null;
  last_attempt_at: string | null;
  next_retry_at: string | null;
  delivered_to_provider_at: string | null;
  response_body: string | null;
  error_class: string | null;
  error_message: string | null;
  delivery_duration_ms: number | null;
  idempotency_key: string | null;
  make_execution_id: string | null;
  make_callback_at: string | null;
  make_processing_message: string | null;
  payload: Record<string, unknown>;
  metadata: Record<string, unknown>;
};

type DeliveriesResponse = {
  summary: {
    events_generated: number;
    accepted_by_make: number;
    with_error: number;
    pending_or_retry: number;
  };
  deliveries: DeliveryRow[];
  total: number;
  page: number;
  per: number;
};

const PERIODS = [
  { value: "24h", label: "Últimas 24 horas" },
  { value: "7d", label: "Últimos 7 dias" },
  { value: "30d", label: "Últimos 30 dias" },
];

const DELIVERY_STATUS_OPTIONS = [
  { value: "", label: "Todos" },
  { value: "pending", label: "Pendente" },
  { value: "sending", label: "Enviando" },
  { value: "accepted_by_make", label: "Aceito pelo Make" },
  { value: "retrying", label: "Nova tentativa" },
  { value: "failed_to_reach_make", label: "Erro ao alcançar o Make" },
  { value: "dead_letter", label: "Falha definitiva" },
  { value: "disabled", label: "Desabilitado" },
  { value: "skipped", label: "Ignorado" },
];

const MAKE_STATUS_OPTIONS = [
  { value: "", label: "Todos" },
  { value: "unknown", label: "Desconhecido" },
  { value: "received", label: "Recebido" },
  { value: "routed", label: "Roteado" },
  { value: "filtered", label: "Filtrado" },
  { value: "completed", label: "Concluído" },
  { value: "failed", label: "Falhou" },
];

const DELIVERY_LABELS: Record<DeliveryStatus, { label: string; cls: string }> = {
  pending: { label: "Pendente", cls: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300" },
  sending: { label: "Enviando", cls: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-200" },
  accepted_by_make: { label: "Aceito pelo Make", cls: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200" },
  retrying: { label: "Nova tentativa", cls: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-200" },
  failed_to_reach_make: { label: "Erro ao alcançar o Make", cls: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-200" },
  dead_letter: { label: "Falha definitiva", cls: "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-200" },
  disabled: { label: "Desabilitado", cls: "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300" },
  skipped: { label: "Ignorado", cls: "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300" },
};

const MAKE_LABELS: Record<MakeStatus, string> = {
  unknown: "Desconhecido",
  received: "Recebido",
  routed: "Roteado",
  filtered: "Filtrado",
  completed: "Concluído",
  failed: "Falhou",
};

function formatDateTime(value: string | null | undefined) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

function JsonBlock({ value }: { value: unknown }) {
  return (
    <pre className="max-h-72 overflow-auto rounded-lg border border-[var(--border)] bg-[var(--bg)] p-3 text-xs text-[var(--text)]">
      {JSON.stringify(value ?? {}, null, 2)}
    </pre>
  );
}

function SummaryCard({ label, value }: { label: string; value: number | undefined }) {
  return (
    <div className="rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="text-2xl font-bold text-primary-600">{(value ?? 0).toLocaleString("pt-BR")}</p>
      <p className="mt-1 text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">{label}</p>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="grid gap-1 text-xs font-medium text-[var(--text-muted)]">
      <span>{label}</span>
      {children}
    </label>
  );
}

function inputClass() {
  return "h-10 rounded-lg border border-[var(--border)] bg-[var(--surface)] px-3 text-sm text-[var(--text)] outline-none focus:border-primary-500";
}

export default function EventDeliveriesPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const [period, setPeriod] = useState("24h");
  const [eventName, setEventName] = useState("");
  const [userQuery, setUserQuery] = useState("");
  const [channel, setChannel] = useState("");
  const [destination, setDestination] = useState("");
  const [deliveryStatus, setDeliveryStatus] = useState("");
  const [httpStatus, setHttpStatus] = useState("");
  const [makeStatus, setMakeStatus] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<DeliveriesResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [detail, setDetail] = useState<DeliveryDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const query = useMemo(() => {
    const params = new URLSearchParams({ period, page: String(page) });
    if (eventName.trim()) params.set("event_name", eventName.trim());
    if (userQuery.trim()) params.set("user", userQuery.trim());
    if (channel.trim()) params.set("channel", channel.trim());
    if (destination.trim()) params.set("destination", destination.trim());
    if (deliveryStatus) params.set("delivery_status", deliveryStatus);
    if (httpStatus.trim()) params.set("http_status", httpStatus.trim());
    if (makeStatus) params.set("make_status", makeStatus);
    return params.toString();
  }, [period, page, eventName, userQuery, channel, destination, deliveryStatus, httpStatus, makeStatus]);

  useEffect(() => {
    if (authLoading) return;
    if (!user?.admin) {
      router.replace("/");
      return;
    }

    setLoading(true);
    setError("");
    api.get<DeliveriesResponse>(`/api/v1/admin/analytics/event_deliveries?${query}`)
      .then(setData)
      .catch(() => setError("Erro ao carregar entregas."))
      .finally(() => setLoading(false));
  }, [authLoading, user, router, query]);

  function resetToFirstPage(run: () => void) {
    run();
    setPage(1);
  }

  function openDetail(id: number) {
    setDetail(null);
    setDetailLoading(true);
    api.get<{ delivery: DeliveryDetail }>(`/api/v1/admin/analytics/event_deliveries/${id}`)
      .then((res) => setDetail(res.delivery))
      .finally(() => setDetailLoading(false));
  }

  function closeDetail() {
    setDetail(null);
    setDetailLoading(false);
  }

  if (authLoading || loading) return <LoadingScreen />;
  if (!user?.admin) return null;

  const totalPages = data ? Math.ceil(data.total / data.per) : 0;

  return (
    <div className="min-h-screen bg-[var(--bg)] px-4 py-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <header className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <Link href="/admin" className="text-sm font-medium text-primary-600 hover:text-primary-700">
              Voltar
            </Link>
            <h1 className="mt-2 text-xl font-bold text-[var(--text)]">Log de eventos e entregas</h1>
          </div>
          <div className="flex rounded-lg border border-[var(--border)] bg-[var(--surface)] p-1">
            {PERIODS.map((item) => (
              <button
                key={item.value}
                onClick={() => resetToFirstPage(() => setPeriod(item.value))}
                className={`h-9 rounded-md px-3 text-xs font-semibold transition-colors ${
                  period === item.value ? "bg-primary-500 text-white" : "text-[var(--text-muted)] hover:text-[var(--text)]"
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </header>

        {error && <div className="rounded-lg bg-[var(--hot-soft)] px-4 py-3 text-sm text-[var(--hot)]">{error}</div>}

        <section className="grid gap-3 sm:grid-cols-4">
          <SummaryCard label="Eventos gerados" value={data?.summary.events_generated} />
          <SummaryCard label="Aceitos pelo Make" value={data?.summary.accepted_by_make} />
          <SummaryCard label="Com erro" value={data?.summary.with_error} />
          <SummaryCard label="Pendentes ou retry" value={data?.summary.pending_or_retry} />
        </section>

        <section className="rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4">
          <div className="grid gap-3 md:grid-cols-4">
            <Field label="Evento">
              <input className={inputClass()} value={eventName} onChange={(e) => resetToFirstPage(() => setEventName(e.target.value))} />
            </Field>
            <Field label="ID ou e-mail do usuário">
              <input className={inputClass()} value={userQuery} onChange={(e) => resetToFirstPage(() => setUserQuery(e.target.value))} />
            </Field>
            <Field label="Canal">
              <input className={inputClass()} value={channel} onChange={(e) => resetToFirstPage(() => setChannel(e.target.value))} />
            </Field>
            <Field label="Destino">
              <input className={inputClass()} value={destination} onChange={(e) => resetToFirstPage(() => setDestination(e.target.value))} />
            </Field>
            <Field label="Status de entrega">
              <select className={inputClass()} value={deliveryStatus} onChange={(e) => resetToFirstPage(() => setDeliveryStatus(e.target.value))}>
                {DELIVERY_STATUS_OPTIONS.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
              </select>
            </Field>
            <Field label="HTTP">
              <input className={inputClass()} inputMode="numeric" value={httpStatus} onChange={(e) => resetToFirstPage(() => setHttpStatus(e.target.value))} />
            </Field>
            <Field label="Status no Make">
              <select className={inputClass()} value={makeStatus} onChange={(e) => resetToFirstPage(() => setMakeStatus(e.target.value))}>
                {MAKE_STATUS_OPTIONS.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
              </select>
            </Field>
            <div className="flex items-end">
              <button
                onClick={() => {
                  setEventName("");
                  setUserQuery("");
                  setChannel("");
                  setDestination("");
                  setDeliveryStatus("");
                  setHttpStatus("");
                  setMakeStatus("");
                  setPage(1);
                }}
                className="h-10 rounded-lg border border-[var(--border)] px-4 text-sm font-semibold text-[var(--text-muted)] hover:text-[var(--text)]"
              >
                Limpar
              </button>
            </div>
          </div>
        </section>

        <section className="overflow-x-auto rounded-lg border border-[var(--border)] bg-[var(--surface)]">
          <table className="w-full min-w-[980px] text-sm">
            <thead>
              <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-muted)]">
                <th className="px-4 py-3 font-medium">Data/hora</th>
                <th className="px-4 py-3 font-medium">Evento</th>
                <th className="px-4 py-3 font-medium">Usuário</th>
                <th className="px-4 py-3 font-medium">Canal</th>
                <th className="px-4 py-3 font-medium">Destino</th>
                <th className="px-4 py-3 font-medium">Status de entrega</th>
                <th className="px-4 py-3 font-medium text-center">Tentativas</th>
                <th className="px-4 py-3 font-medium text-center">HTTP</th>
                <th className="px-4 py-3 font-medium">Status no Make</th>
                <th className="px-4 py-3 font-medium text-right">ID do evento</th>
              </tr>
            </thead>
            <tbody>
              {data?.deliveries.map((delivery) => {
                const status = DELIVERY_LABELS[delivery.delivery_status];
                return (
                  <tr key={delivery.id} className="border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)]">
                    <td className="px-4 py-3 text-xs text-[var(--text-muted)]">{formatDateTime(delivery.occurred_at || delivery.created_at)}</td>
                    <td className="px-4 py-3 font-medium text-[var(--text)]">{delivery.event_name}</td>
                    <td className="px-4 py-3">
                      {delivery.user ? (
                        <div>
                          <p className="text-xs font-semibold text-[var(--text)]">{delivery.user.display_name}</p>
                          <p className="text-xs text-[var(--text-dim)]">{delivery.user.id} · {delivery.user.email}</p>
                        </div>
                      ) : "—"}
                    </td>
                    <td className="px-4 py-3 text-xs text-[var(--text-muted)]">{delivery.channels.join(", ") || "—"}</td>
                    <td className="px-4 py-3 text-xs text-[var(--text-muted)]">{delivery.destination || "—"}</td>
                    <td className="px-4 py-3">
                      <span className={`rounded-full px-2 py-1 text-xs font-semibold ${status.cls}`}>{status.label}</span>
                    </td>
                    <td className="px-4 py-3 text-center font-medium text-[var(--text)]">{delivery.attempt_count}</td>
                    <td className="px-4 py-3 text-center text-[var(--text-muted)]">{delivery.http_status ?? "—"}</td>
                    <td className="px-4 py-3 text-xs text-[var(--text-muted)]">{MAKE_LABELS[delivery.make_status] ?? delivery.make_status}</td>
                    <td className="px-4 py-3 text-right">
                      <button className="text-xs font-semibold text-primary-600 hover:text-primary-700" onClick={() => openDetail(delivery.id)}>
                        #{delivery.id}
                      </button>
                    </td>
                  </tr>
                );
              })}
              {data?.deliveries.length === 0 && (
                <tr>
                  <td colSpan={10} className="px-4 py-10 text-center text-sm text-[var(--text-muted)]">Nenhum registro encontrado</td>
                </tr>
              )}
            </tbody>
          </table>
        </section>

        {totalPages > 1 && (
          <div className="flex items-center justify-between text-sm text-[var(--text-muted)]">
            <span>{data?.total.toLocaleString("pt-BR")} registros</span>
            <div className="flex items-center gap-2">
              <button disabled={page === 1} onClick={() => setPage((p) => Math.max(1, p - 1))} className="rounded-lg border border-[var(--border)] px-3 py-1 disabled:opacity-40">Anterior</button>
              <span>{page} / {totalPages}</span>
              <button disabled={page === totalPages} onClick={() => setPage((p) => Math.min(totalPages, p + 1))} className="rounded-lg border border-[var(--border)] px-3 py-1 disabled:opacity-40">Próxima</button>
            </div>
          </div>
        )}
      </div>

      {(detailLoading || detail) && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={(e) => { if (e.currentTarget === e.target) closeDetail(); }}>
          <div className="max-h-[90vh] w-full max-w-3xl overflow-auto rounded-lg border border-[var(--border)] bg-[var(--surface)] p-5 shadow-xl">
            <div className="mb-4 flex items-center justify-between gap-4">
              <h2 className="text-base font-bold text-[var(--text)]">Evento #{detail?.id ?? ""}</h2>
              <button className="rounded-lg border border-[var(--border)] px-3 py-1 text-sm text-[var(--text-muted)] hover:text-[var(--text)]" onClick={closeDetail}>
                Fechar
              </button>
            </div>

            {detailLoading ? (
              <div className="py-8 text-center text-sm text-[var(--text-muted)]">Carregando...</div>
            ) : detail ? (
              <div className="space-y-5">
                <div className="grid gap-3 sm:grid-cols-2">
                  {[
                    ["Evento", detail.event_name],
                    ["Usuário", detail.user ? `${detail.user.id} · ${detail.user.email}` : "—"],
                    ["Geração", formatDateTime(detail.occurred_at || detail.created_at)],
                    ["Primeira tentativa", formatDateTime(detail.first_attempt_at)],
                    ["Última tentativa", formatDateTime(detail.last_attempt_at)],
                    ["Próxima tentativa", formatDateTime(detail.next_retry_at)],
                    ["Tentativas", detail.attempt_count],
                    ["HTTP", detail.http_status ?? "—"],
                    ["Erro", detail.error_class || "—"],
                    ["Mensagem", detail.error_message || "—"],
                    ["Idempotência", detail.idempotency_key || "—"],
                    ["Execução Make", detail.make_execution_id || "—"],
                  ].map(([label, value]) => (
                    <div key={String(label)} className="rounded-lg border border-[var(--border)] p-3">
                      <p className="text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">{label}</p>
                      <p className="mt-1 break-words text-sm text-[var(--text)]">{value}</p>
                    </div>
                  ))}
                </div>

                <div>
                  <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">Payload enviado</p>
                  <JsonBlock value={detail.payload} />
                </div>

                <div>
                  <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">Resposta do Make</p>
                  <JsonBlock value={detail.response_body ? tryParseJson(detail.response_body) : {}} />
                </div>

                <div>
                  <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">Metadata</p>
                  <JsonBlock value={detail.metadata} />
                </div>
              </div>
            ) : null}
          </div>
        </div>
      )}
    </div>
  );
}

function tryParseJson(value: string) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}
