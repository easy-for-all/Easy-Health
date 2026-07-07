"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { FiltersBar } from "./filters-bar";
import { FlowSelection } from "./flow-selection";
import { ConversionByFlowTable } from "./conversion-by-flow-table";
import { TimeToPlan } from "./time-to-plan";
import { StepDropoffFunnel } from "./step-dropoff-funnel";
import { Activation24h } from "./activation-24h";
import { ProgressiveProfilingSection } from "./progressive-profiling";
import { AiQuality } from "./ai-quality";
import { DeclaredPreferences } from "./declared-preferences";
import type { FlowFilter, OnboardingAnalytics, PeriodFilter, StatusFilter } from "./types";

function Subsection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-3">
      <h3 className="text-xs font-semibold uppercase tracking-wider text-[var(--text-dim)]">{title}</h3>
      {children}
    </div>
  );
}

export function OnboardingAnalyticsSection() {
  const [period, setPeriod] = useState<PeriodFilter>("30d");
  const [flow, setFlow] = useState<FlowFilter>("");
  const [status, setStatus] = useState<StatusFilter>("");
  const [data, setData] = useState<OnboardingAnalytics | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    function fetchAnalytics() {
      setLoading(true);
      const params = new URLSearchParams();
      if (period) params.set("onboarding_period", period);
      if (flow) params.set("onboarding_flow", flow);
      if (status) params.set("onboarding_status", status);

      api
        .get<{ onboarding_analytics: OnboardingAnalytics }>(`/api/v1/admin/stats?${params}`)
        .then((res) => setData(res.onboarding_analytics))
        .catch(() => setData(null))
        .finally(() => setLoading(false));
    }

    fetchAnalytics();
  }, [period, flow, status]);

  return (
    <section>
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        Onboarding Analytics
      </h2>

      <FiltersBar
        period={period}
        flow={flow}
        status={status}
        onPeriodChange={setPeriod}
        onFlowChange={setFlow}
        onStatusChange={setStatus}
      />

      {loading || !data ? (
        <div className="py-8 text-center text-sm text-[var(--text-muted)]">Carregando...</div>
      ) : (
        <div className="space-y-6">
          <Subsection title="Escolha do onboarding">
            <FlowSelection data={data.flow_selection} />
          </Subsection>

          <Subsection title="Conversão por fluxo">
            <ConversionByFlowTable data={data.conversion_by_flow} />
          </Subsection>

          <Subsection title="Tempo até o treino criado">
            <TimeToPlan data={data.time_to_first_plan} />
          </Subsection>

          <Subsection title="Abandono por etapa">
            <StepDropoffFunnel data={data.step_dropoff} flow={flow} />
          </Subsection>

          <Subsection title="Ativação em 24h">
            <Activation24h data={data.first_workout_24h} />
          </Subsection>

          <Subsection title="Progressive Profiling">
            <ProgressiveProfilingSection data={data.progressive_profiling} />
          </Subsection>

          <Subsection title="Qualidade da IA">
            <AiQuality data={data.ai_quality} />
          </Subsection>

          <Subsection title="Preferências dos usuários">
            <DeclaredPreferences data={data.declared_preferences} />
          </Subsection>
        </div>
      )}
    </section>
  );
}
