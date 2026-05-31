"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { BodyCompositionMap, type BodyCompositionData } from "@/shared/components/body-composition-map";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

// ─── Types ────────────────────────────────────────────────────────────────────

type DataPoint = {
  id: number;
  field_name: string;
  value: number;
  unit: string | null;
  source_type: string;
  status: string;
  confidence: number | null;
  ai_notes: string | null;
  raw_text: string | null;
  collected_at: string;
  created_at: string;
  user_media_id?: number | null;
};

type MediaItem = {
  id: number;
  category: "body_photo" | "exam";
  notes: string | null;
  captured_at: string;
  file_url: string | null;
  file_name: string | null;
  file_size: number | null;
  mime_type: string | null;
};

type DetailedProfile = {
  physical: {
    age: number | null;
    weight_kg: number | null;
    height_cm: number | null;
    fitness_level: string | null;
    goal: string | null;
    training_days_per_week: number | null;
    training_location: string | null;
    modality: string | null;
    bmi: number | null;
  } | null;
  data_points: DataPoint[];
  media: MediaItem[];
};

// ─── Constants ────────────────────────────────────────────────────────────────

const FIELD_LABELS: Record<string, string> = {
  weight_kg:                "Peso",
  height_cm:                "Altura",
  bmi:                      "IMC",
  body_fat_pct:             "% Gordura",
  muscle_mass_kg:           "Massa Muscular",
  glucose_mgdl:             "Glicose",
  cholesterol_mgdl:         "Colesterol Total",
  hdl_mgdl:                 "HDL",
  ldl_mgdl:                 "LDL",
  triglycerides_mgdl:       "Triglicerídeos",
  blood_pressure_systolic:  "PA Sistólica",
  blood_pressure_diastolic: "PA Diastólica",
  heart_rate_bpm:           "Freq. Cardíaca",
  visceral_fat:             "Gordura Visceral",
  body_analysis:            "Análise Corporal",
  visual_observation:       "Análise Corporal",
};

const COMPOSITION_FIELDS = ["body_fat_pct", "muscle_mass_kg", "bmi", "visceral_fat"];

const RISK_RANGES: Record<string, [number, number]> = {
  glucose_mgdl:             [70, 99],
  cholesterol_mgdl:         [0, 200],
  hdl_mgdl:                 [40, 999],
  ldl_mgdl:                 [0, 130],
  triglycerides_mgdl:       [0, 150],
  blood_pressure_systolic:  [90, 129],
  blood_pressure_diastolic: [60, 84],
  body_fat_pct:             [5, 25],
  bmi:                      [18.5, 24.9],
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return "";
  return new Date(dateStr).toLocaleDateString("pt-BR", {
    day: "numeric", month: "short", year: "numeric",
  });
}

function riskColor(fieldName: string, value: number) {
  const range = RISK_RANGES[fieldName];
  if (!range) return { text: "text-gray-700", bg: "bg-gray-50 border-gray-100" };
  const ok = value >= range[0] && value <= range[1];
  return ok
    ? { text: "text-green-700", bg: "bg-green-50 border-green-200" }
    : { text: "text-amber-600", bg: "bg-amber-50 border-amber-200" };
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function Section({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <div className="mb-4 rounded-2xl border border-gray-100 bg-white p-5">
      <div className="mb-3">
        <h2 className="font-semibold text-gray-900">{title}</h2>
        {subtitle && <p className="text-xs text-gray-400 mt-0.5">{subtitle}</p>}
      </div>
      {children}
    </div>
  );
}

function DocIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6 text-red-400">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="8" y1="13" x2="16" y2="13" />
      <line x1="8" y1="17" x2="12" y2="17" />
    </svg>
  );
}

function BodyFatVisual({ fatPct }: { fatPct: number }) {
  const getClass = (pct: number) => {
    if (pct < 10) return { label: "Atlético",   color: "#0ea5e9" };
    if (pct < 14) return { label: "Fitness",    color: "#22c55e" };
    if (pct < 18) return { label: "Aceitável",  color: "#84cc16" };
    if (pct < 25) return { label: "Médio",      color: "#f59e0b" };
    if (pct < 32) return { label: "Alto",       color: "#f97316" };
    return               { label: "Muito Alto", color: "#ef4444" };
  };
  const { label, color } = getClass(fatPct);
  const opacity = Math.min(0.15 + fatPct / 60, 0.85);

  return (
    <div className="flex flex-col items-center gap-1">
      <svg viewBox="0 0 80 160" className="w-20 h-40" xmlns="http://www.w3.org/2000/svg">
        {/* Head */}
        <ellipse cx="40" cy="13" rx="11" ry="12" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
        {/* Neck */}
        <rect x="33" y="24" width="14" height="7" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
        {/* Torso */}
        <path d="M17 31 Q13 58 15 88 L65 88 Q67 58 63 31 Q52 33 40 33 Q28 33 17 31 Z" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
        {/* Left arm */}
        <path d="M17 33 Q9 52 11 77 Q15 79 19 77 Q19 58 21 35 Z" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
        {/* Right arm */}
        <path d="M63 33 Q71 52 69 77 Q65 79 61 77 Q61 58 59 35 Z" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
        {/* Left leg */}
        <path d="M15 88 Q13 118 15 145 Q23 147 29 145 Q31 118 33 88 Z" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
        {/* Right leg */}
        <path d="M65 88 Q67 118 65 145 Q57 147 51 145 Q49 118 47 88 Z" fill={color} fillOpacity={opacity} stroke="#d1d5db" strokeWidth="1.5" />
      </svg>
      <p className="text-2xl font-bold" style={{ color }}>{fatPct}%</p>
      <span className="rounded-full px-2.5 py-0.5 text-xs font-semibold text-white" style={{ backgroundColor: color }}>
        {label}
      </span>
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function DetailedProfilePage() {
  const router = useRouter();
  const [data, setData]               = useState<DetailedProfile | null>(null);
  const [loading, setLoading]         = useState(true);
  const [photoHistoryOpen, setPhotoHistoryOpen] = useState(false);
  const [lightboxItem, setLightboxItem]         = useState<MediaItem | null>(null);
  const [reanalyzing, setReanalyzing]           = useState(false);
  const [reanalyzeError, setReanalyzeError]     = useState<string | null>(null);

  useEffect(() => {
    api
      .get<DetailedProfile>("/api/v1/detailed_profile")
      .then(setData)
      .catch(() => null)
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <LoadingScreen />;

  if (!data) {
    return (
      <div className="min-h-screen px-4 py-6 pb-28">
        <button onClick={() => router.back()} className="mb-4 text-sm text-primary-600">← Voltar</button>
        <p className="text-center text-sm text-gray-400 mt-12">Não foi possível carregar o perfil detalhado.</p>
      </div>
    );
  }

  const { data_points, media } = data;

  const bodyPhotos = media.filter((m) => m.category === "body_photo");
  const analyzablePhoto = bodyPhotos.find((p) => p.file_url !== null) ?? null;
  const exams      = media.filter((m) => m.category === "exam");

  // Bug fix: cobrir field_name legado ("visual_observation") e novo ("body_analysis")
  const bodyAnalyses = data_points.filter(
    (dp) => dp.source_type === "body_photo" &&
            (dp.field_name === "body_analysis" || dp.field_name === "visual_observation")
  );

  const latestCompositionPoint = data_points.find((dp) => dp.field_name === "body_composition_map");
  const bodyCompositionData: BodyCompositionData | null = (() => {
    if (!latestCompositionPoint?.raw_text) return null;
    try {
      const raw = latestCompositionPoint.raw_text;
      const jsonStr = raw.match(/\{[\s\S]*\}/)?.[0] ?? raw;
      return JSON.parse(jsonStr) as BodyCompositionData;
    } catch { return null; }
  })();
  const examPoints = data_points.filter((dp) => dp.source_type === "exam");

  const riskPoints = examPoints.filter((dp) => {
    const range = RISK_RANGES[dp.field_name];
    return range && (dp.value < range[0] || dp.value > range[1]);
  });

  // Composição: pegar o data_point mais recente de cada campo de composição corporal
  const compositionPoints: DataPoint[] = COMPOSITION_FIELDS.flatMap((field) => {
    const candidates = data_points.filter((dp) => dp.field_name === field);
    if (candidates.length === 0) return [];
    // Priorizar exame sobre foto; ambos já vêm ordenados por collected_at desc
    const fromExam  = candidates.find((dp) => dp.source_type === "exam");
    const fromPhoto = candidates.find((dp) => dp.source_type === "body_photo");
    return [fromExam ?? fromPhoto!];
  });

  const hasExamAnalysis = (mediaId: number | null | undefined) =>
    mediaId != null && examPoints.some((dp) => dp.user_media_id === mediaId);

  // Estimated analysis calculations
  const estW   = data.physical?.weight_kg ?? null;
  const estH   = data.physical?.height_cm ?? null;
  const estAge = data.physical?.age ?? null;
  const estFatPct = compositionPoints.find((dp) => dp.field_name === "body_fat_pct")?.value ?? null;
  const estBmiRaw = data.physical?.bmi ?? (estW && estH ? estW / ((estH / 100) ** 2) : null);
  const estBmi = estBmiRaw ? Math.round(estBmiRaw * 10) / 10 : null;
  const estLeanMass = estW && estFatPct != null ? Math.round(estW * (1 - estFatPct / 100) * 10) / 10 : null;
  const estIdealMin = estH ? Math.round(18.5 * (estH / 100) ** 2 * 10) / 10 : null;
  const estIdealMax = estH ? Math.round(24.9 * (estH / 100) ** 2 * 10) / 10 : null;
  const estBmr = estW && estH && estAge ? Math.round(10 * estW + 6.25 * estH - 5 * estAge) : null;
  const estBodyWater = estLeanMass
    ? Math.round(estLeanMass * 0.73 * 10) / 10
    : estW ? Math.round(estW * 0.60 * 10) / 10 : null;
  const estBmiClass = !estBmi ? null
    : estBmi < 18.5 ? { label: "Abaixo do peso", color: "text-blue-600" }
    : estBmi < 25   ? { label: "Peso normal",    color: "text-green-600" }
    : estBmi < 30   ? { label: "Sobrepeso",      color: "text-amber-600" }
    :                 { label: "Obesidade",       color: "text-red-600" };
  const hasEstData = !!(estBmi || estLeanMass || estIdealMin || estBmr);

  const isEmpty = !data.physical && data_points.length === 0 && media.length === 0;

  async function handleReanalyze() {
    if (!analyzablePhoto) return;
    setReanalyzing(true);
    setReanalyzeError(null);
    try {
      await api.post(`/api/v1/user_media/${analyzablePhoto.id}/reanalyze`, {});
      const fresh = await api.get<DetailedProfile>("/api/v1/detailed_profile");
      setData(fresh);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Não foi possível analisar. Tente novamente.";
      setReanalyzeError(msg);
    } finally {
      setReanalyzing(false);
    }
  }

  return (
    <div className="min-h-screen bg-gray-50 px-4 py-6 pb-28">

      {/* Header */}
      <header className="mb-5 flex items-center gap-3">
        <button
          onClick={() => router.back()}
          className="flex h-9 w-9 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-600"
        >
          ←
        </button>
        <div>
          <h1 className="text-xl font-bold text-gray-900">Perfil Detalhado</h1>
          <p className="text-xs text-gray-400">Evolução, composição e análises</p>
        </div>
      </header>

      {isEmpty && (
        <div className="mt-12 text-center">
          <p className="text-4xl mb-3">📋</p>
          <p className="text-sm text-gray-500">Nenhum dado registrado ainda.</p>
          <p className="mt-1 text-xs text-gray-400">
            Complete seu perfil, adicione fotos e exames para ver o histórico aqui.
          </p>
        </div>
      )}

      {/* 1. Composição Corporal Estimada */}
      {compositionPoints.length > 0 && (
        <Section
          title="Composição Corporal"
          subtitle="Estimativa baseada em foto ou exame"
        >
          <div className="grid grid-cols-2 gap-3">
            {compositionPoints.map((dp) => {
              const { text, bg } = riskColor(dp.field_name, dp.value);
              const isFromExam   = dp.source_type === "exam";
              return (
                <div key={dp.id} className={`rounded-xl border p-3 ${bg}`}>
                  <p className="text-xs text-gray-500 mb-1">
                    {FIELD_LABELS[dp.field_name] ?? dp.field_name}
                  </p>
                  <p className={`text-xl font-bold leading-none ${text}`}>
                    {dp.value}
                    {dp.unit && <span className="text-xs font-normal ml-1">{dp.unit}</span>}
                  </p>
                  <p className="text-xs text-gray-400 mt-1">
                    {isFromExam ? "por exame" : "por foto"}
                    {dp.confidence != null && ` · ${Math.round(dp.confidence * 100)}% conf.`}
                  </p>
                </div>
              );
            })}
          </div>
          <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
            Use como acompanhamento de evolução, não como diagnóstico médico.
          </p>
        </Section>
      )}

      {/* 1b. Análise Detalhada Estimada */}
      {hasEstData && (
        <Section title="Análise Detalhada" subtitle="Estimativas com base nos seus dados físicos">
          <div className="space-y-3">
            {estFatPct != null && (
              <div className="flex items-center gap-4">
                <div className="flex-1 space-y-2">
                  {estBmi && estBmiClass && (
                    <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5">
                      <p className="text-xs text-gray-500">IMC</p>
                      <p className={`text-xl font-bold leading-none ${estBmiClass.color}`}>{estBmi}</p>
                      <p className={`mt-0.5 text-xs ${estBmiClass.color}`}>{estBmiClass.label}</p>
                    </div>
                  )}
                  {estLeanMass && (
                    <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5">
                      <p className="text-xs text-gray-500">Massa Magra</p>
                      <p className="text-xl font-bold leading-none text-gray-800">
                        {estLeanMass}<span className="ml-1 text-xs font-normal">kg</span>
                      </p>
                    </div>
                  )}
                </div>
                <BodyFatVisual fatPct={estFatPct} />
              </div>
            )}

            <div className="grid grid-cols-2 gap-2">
              {estFatPct == null && estBmi && estBmiClass && (
                <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5">
                  <p className="text-xs text-gray-500">IMC</p>
                  <p className={`text-xl font-bold leading-none ${estBmiClass.color}`}>{estBmi}</p>
                  <p className={`mt-0.5 text-xs ${estBmiClass.color}`}>{estBmiClass.label}</p>
                </div>
              )}
              {estIdealMin && estIdealMax && (
                <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5">
                  <p className="text-xs text-gray-500">Peso Ideal</p>
                  <p className="text-sm font-bold text-gray-800">
                    {estIdealMin}–{estIdealMax}<span className="ml-1 text-xs font-normal">kg</span>
                  </p>
                </div>
              )}
              {estBmr && (
                <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5">
                  <p className="text-xs text-gray-500">TMB Estimada</p>
                  <p className="text-sm font-bold text-gray-800">
                    ~{estBmr}<span className="ml-1 text-xs font-normal">kcal/dia</span>
                  </p>
                </div>
              )}
              {estBodyWater && (
                <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5">
                  <p className="text-xs text-gray-500">Água Corporal</p>
                  <p className="text-sm font-bold text-gray-800">
                    ~{estBodyWater}<span className="ml-1 text-xs font-normal">L</span>
                  </p>
                </div>
              )}
            </div>

            <p className="rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
              Valores estimados para acompanhamento. Consulte um profissional para avaliação precisa.
            </p>
          </div>
        </Section>
      )}

      {/* 2. Evolução Corporal */}
      {bodyPhotos.length > 0 && (
        <Section title="Evolução Corporal">
          <div className="grid grid-cols-2 gap-3 mb-3">
            {/* Antes — foto mais antiga (último índice) */}
            {bodyPhotos.length >= 2 ? (
              <button
                onClick={() => setLightboxItem(bodyPhotos[bodyPhotos.length - 1])}
                className="text-center"
              >
                <img
                  src={`${API_URL}${bodyPhotos[bodyPhotos.length - 1].file_url}`}
                  alt="Antes"
                  className="h-36 w-full rounded-xl object-cover"
                />
                <p className="mt-1 text-xs font-semibold text-gray-600">Antes</p>
                <p className="text-xs text-gray-400">{formatDate(bodyPhotos[bodyPhotos.length - 1].captured_at)}</p>
              </button>
            ) : (
              <div className="flex h-36 items-center justify-center rounded-xl bg-gray-100 text-center">
                <p className="text-xs text-gray-400 px-3">Adicione mais fotos para comparar</p>
              </div>
            )}

            {/* Agora — foto mais recente (índice 0) */}
            <button
              onClick={() => setLightboxItem(bodyPhotos[0])}
              className="text-center"
            >
              <img
                src={`${API_URL}${bodyPhotos[0].file_url}`}
                alt="Agora"
                className="h-36 w-full rounded-xl object-cover"
              />
              <p className="mt-1 text-xs font-semibold text-gray-600">Agora</p>
              <p className="text-xs text-gray-400">{formatDate(bodyPhotos[0].captured_at)}</p>
            </button>
          </div>

          <button
            onClick={() => setPhotoHistoryOpen(true)}
            className="w-full rounded-xl border border-primary-100 bg-primary-50 py-2.5 text-sm font-semibold text-primary-700 transition hover:bg-primary-100"
          >
            Histórico de fotos ({bodyPhotos.length})
          </button>
        </Section>
      )}

      {/* 3. Análise da última foto */}
      {bodyAnalyses.length > 0 && (
        <Section title="Análise da última foto">
          <p className="text-sm leading-relaxed text-gray-700">
            {bodyAnalyses[0].ai_notes || bodyAnalyses[0].raw_text}
          </p>
          <p className="mt-2 text-xs text-gray-400">
            {formatDate(bodyAnalyses[0].collected_at || bodyAnalyses[0].created_at)}
          </p>
          <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
            Observação geral. Consulte um profissional de saúde para avaliação precisa.
          </p>
        </Section>
      )}

      {/* 3.5 Mapa Corporal por IA */}
      {(bodyCompositionData || bodyPhotos.length > 0) && (
        <Section
          title="Mapa Corporal por IA"
          subtitle="Avaliação muscular e de gordura por região"
        >
          {bodyCompositionData ? (
            <>
              <BodyCompositionMap data={bodyCompositionData} />
              {analyzablePhoto && (
                <div className="mt-4">
                  {reanalyzeError && (
                    <p className="mb-2 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{reanalyzeError}</p>
                  )}
                  <button
                    onClick={handleReanalyze}
                    disabled={reanalyzing}
                    className="w-full rounded-xl border border-gray-200 py-2.5 text-sm font-medium text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
                  >
                    {reanalyzing ? "Analisando foto..." : "↺ Re-analisar foto mais recente"}
                  </button>
                </div>
              )}
              <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
                Estimativa visual por IA. Consulte um profissional para avaliação precisa.
              </p>
            </>
          ) : (
            <div className="text-center py-4">
              <p className="text-sm text-gray-500 mb-3">
                Gere um mapa corporal detalhado a partir da sua foto mais recente.
              </p>
              {reanalyzeError && (
                <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{reanalyzeError}</p>
              )}
              <button
                onClick={handleReanalyze}
                disabled={reanalyzing || !analyzablePhoto}
                className="w-full rounded-xl bg-primary-600 py-3 text-sm font-semibold text-white transition hover:bg-primary-700 disabled:opacity-50"
              >
                {reanalyzing ? "Analisando foto..." : "🔍 Gerar mapa corporal"}
              </button>
              {!analyzablePhoto && (
                <p className="mt-2 text-xs text-gray-400">
                  {bodyPhotos.length === 0
                    ? "Adicione uma foto corporal para ativar essa funcionalidade."
                    : "A foto salva não está mais disponível. Envie uma nova foto para usar esta função."}
                </p>
              )}
            </div>
          )}
        </Section>
      )}

      {/* 4. Marcadores de Exames */}
      {examPoints.length > 0 && (
        <Section title="Marcadores de Exames">
          {riskPoints.length > 0 && (
            <div className="mb-3 rounded-xl bg-amber-50 border border-amber-200 px-3 py-2">
              <p className="text-xs font-semibold text-amber-700 mb-1">Pontos de atenção</p>
              {riskPoints.map((dp) => (
                <p key={dp.id} className="text-xs text-amber-700">
                  {FIELD_LABELS[dp.field_name] ?? dp.field_name}: {dp.value}{dp.unit ? ` ${dp.unit}` : ""}
                </p>
              ))}
            </div>
          )}
          {examPoints.map((dp) => {
            const { text } = riskColor(dp.field_name, dp.value);
            return (
              <div key={dp.id} className="flex items-start justify-between py-2 border-b border-gray-50 last:border-0">
                <div>
                  <span className="text-sm text-gray-600">{FIELD_LABELS[dp.field_name] ?? dp.field_name}</span>
                  {dp.ai_notes && <p className="text-xs text-gray-400 mt-0.5">{dp.ai_notes}</p>}
                </div>
                <span className={`text-sm font-semibold shrink-0 ml-2 ${text}`}>
                  {dp.value}{dp.unit ? ` ${dp.unit}` : ""}
                </span>
              </div>
            );
          })}
          <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
            Valide os valores com seu médico ou nutricionista.
          </p>
        </Section>
      )}

      {/* 5. Exames */}
      {exams.length > 0 && (
        <Section title={`Exames (${exams.length})`}>
          {exams.map((exam) => {
            const isPdf      = exam.mime_type === "application/pdf";
            const isAnalyzed = hasExamAnalysis(exam.id);
            return (
              <button
                key={exam.id}
                onClick={() => {
                  if (isPdf) {
                    window.open(`${API_URL}${exam.file_url}`, "_blank");
                  } else {
                    setLightboxItem(exam);
                  }
                }}
                className="flex w-full items-center gap-3 py-2.5 border-b border-gray-50 last:border-0 text-left"
              >
                {isPdf ? (
                  <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-red-50 border border-red-100">
                    <DocIcon />
                  </div>
                ) : (
                  <img
                    src={`${API_URL}${exam.file_url}`}
                    alt="Exame"
                    className="h-12 w-12 shrink-0 rounded-xl object-cover"
                  />
                )}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-800 truncate">
                    {exam.file_name || "Exame"}
                  </p>
                  <p className="text-xs text-gray-400">{formatDate(exam.captured_at)}</p>
                </div>
                {isAnalyzed && (
                  <span className="shrink-0 rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">
                    Analisado
                  </span>
                )}
                <span className="shrink-0 text-gray-300 text-base">›</span>
              </button>
            );
          })}
        </Section>
      )}

      {/* 6. Recomendações */}
      <Section title="Recomendações">
        {examPoints.length > 0 || compositionPoints.length > 0 ? (
          <p className="text-sm leading-relaxed text-gray-600">
            Com base no seu histórico, mantenha consistência nos treinos e acompanhe sua
            evolução regularmente. Consulte um profissional de saúde para orientações
            personalizadas sobre dieta e exercício.
          </p>
        ) : (
          <p className="text-sm text-gray-400">
            Adicione fotos e exames para receber recomendações personalizadas.
          </p>
        )}
      </Section>

      {/* ─── Bottom Sheet: Histórico de fotos ───────────────────────────── */}
      {photoHistoryOpen && (
        <div
          className="fixed inset-0 z-50 flex items-end bg-black/40"
          onClick={() => setPhotoHistoryOpen(false)}
        >
          <div
            className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
            <div className="mb-4 flex items-center justify-between mt-3">
              <h3 className="text-base font-bold text-gray-900">
                Histórico de fotos ({bodyPhotos.length})
              </h3>
              <button
                onClick={() => setPhotoHistoryOpen(false)}
                className="flex h-8 w-8 items-center justify-center rounded-full border border-gray-200 text-gray-500 text-sm"
              >
                ✕
              </button>
            </div>

            <div className="grid grid-cols-3 gap-2">
              {bodyPhotos.map((photo) => (
                <button
                  key={photo.id}
                  onClick={() => {
                    setPhotoHistoryOpen(false);
                    setLightboxItem(photo);
                  }}
                  className="text-center"
                >
                  <img
                    src={`${API_URL}${photo.file_url}`}
                    alt="Foto corporal"
                    className="h-28 w-full rounded-xl object-cover"
                  />
                  <p className="mt-1 text-xs text-gray-500">{formatDate(photo.captured_at)}</p>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ─── Lightbox ────────────────────────────────────────────────────── */}
      {lightboxItem && (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/90"
          onClick={() => setLightboxItem(null)}
        >
          <button
            onClick={() => setLightboxItem(null)}
            className="absolute right-4 top-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/20 text-white text-xl"
          >
            ✕
          </button>
          <img
            src={`${API_URL}${lightboxItem.file_url}`}
            alt="Visualização"
            className="max-h-[88vh] max-w-[92vw] rounded-xl object-contain"
            onClick={(e) => e.stopPropagation()}
          />
          {lightboxItem.captured_at && (
            <p className="absolute bottom-6 text-sm text-white/70">
              {formatDate(lightboxItem.captured_at)}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
