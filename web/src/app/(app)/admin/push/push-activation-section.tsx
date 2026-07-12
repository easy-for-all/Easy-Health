"use client";

// Compact activation-push panel. Aggregate-only — no emails, no tokens.
type PushStats = {
  enabled: boolean;
  experiment_enabled: boolean;
  firebase_configured: boolean;
  permission: {
    opt_in_reminders: number;
    push_enabled: number;
    permission_granted: number;
    opted_out: number;
    active_devices: number;
  };
  funnel: {
    scheduled: number;
    sent: number;
    opened: number;
    converted: number;
    workout_started_from_push: number;
    workout_completed_from_push: number;
  };
  experiment: { treatment: number; control: number };
  preferences: { reasons_disabled: Record<string, number>; dislike_reasons: Record<string, number> };
  performance: { sent: number; failed: number; skipped: number; tokens_invalidated: number; retries: number };
};

function Card({ label, value, description }: { label: string; value: number | undefined; description: string }) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
      <p className="text-3xl font-bold text-primary-600">{value === undefined ? "—" : value.toLocaleString("pt-BR")}</p>
      <p className="mt-1 text-sm font-semibold text-[var(--text)]">{label}</p>
      <p className="mt-0.5 text-xs text-[var(--text-dim)]">{description}</p>
    </div>
  );
}

function Flag({ label, on }: { label: string; on: boolean }) {
  return (
    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${on ? "bg-green-500/15 text-green-600" : "bg-gray-500/15 text-[var(--text-muted)]"}`}>
      {label}: {on ? "ON" : "OFF"}
    </span>
  );
}

export function PushActivationSection({ stats }: { stats?: PushStats }) {
  if (!stats) return null;

  return (
    <section>
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">Push de ativação</h2>

      <div className="mb-3 flex flex-wrap gap-2">
        <Flag label="Envio" on={stats.enabled} />
        <Flag label="Experimento" on={stats.experiment_enabled} />
        <Flag label="Firebase" on={stats.firebase_configured} />
      </div>

      <p className="mb-2 text-xs font-semibold text-[var(--text-dim)]">Permissão</p>
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-3">
        <Card label="Opt-in lembretes" value={stats.permission.opt_in_reminders} description="workout_reminders on" />
        <Card label="Push ativo" value={stats.permission.push_enabled} description="push_enabled on" />
        <Card label="Permissão concedida" value={stats.permission.permission_granted} description="granted" />
        <Card label="Opt-out" value={stats.permission.opted_out} description="desativaram" />
        <Card label="Devices ativos" value={stats.permission.active_devices} description="Android válidos" />
      </div>

      <p className="mb-2 text-xs font-semibold text-[var(--text-dim)]">Funil</p>
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-3">
        <Card label="Agendados" value={stats.funnel.scheduled} description="deliveries criadas" />
        <Card label="Enviados" value={stats.funnel.sent} description="push enviados" />
        <Card label="Abertos" value={stats.funnel.opened} description="tocaram no push" />
        <Card label="Treino iniciado" value={stats.funnel.workout_started_from_push} description="após o push (2h)" />
        <Card label="Treino concluído" value={stats.funnel.workout_completed_from_push} description="após o push" />
      </div>

      <p className="mb-2 text-xs font-semibold text-[var(--text-dim)]">Experimento & performance</p>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Card label="Treatment" value={stats.experiment.treatment} description="recebem push" />
        <Card label="Control" value={stats.experiment.control} description="sem push" />
        <Card label="Falhas" value={stats.performance.failed} description="envios com erro" />
        <Card label="Ignorados" value={stats.performance.skipped} description="duplicidade/regra" />
        <Card label="Tokens inválidos" value={stats.performance.tokens_invalidated} description="invalidados" />
        <Card label="Retries" value={stats.performance.retries} description="tentativas extra" />
      </div>
    </section>
  );
}
