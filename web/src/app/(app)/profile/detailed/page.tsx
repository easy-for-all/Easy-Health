"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

type PhysicalData = {
  age: number | null;
  weight_kg: number | null;
  height_cm: number | null;
  fitness_level: string | null;
  goal: string | null;
  training_days_per_week: number | null;
  training_location: string | null;
  modality: string | null;
  bmi: number | null;
};

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
};

type MediaItem = {
  id: number;
  category: "body_photo" | "exam";
  notes: string | null;
  captured_at: string;
  file_url: string | null;
  mime_type: string | null;
};

type DetailedProfile = {
  physical: PhysicalData | null;
  data_points: DataPoint[];
  media: MediaItem[];
};

const FIELD_LABELS: Record<string, string> = {
  weight_kg:               "Peso",
  height_cm:               "Altura",
  bmi:                     "IMC",
  body_fat_pct:            "% Gordura",
  muscle_mass_kg:          "Massa Muscular",
  glucose_mgdl:            "Glicose",
  cholesterol_mgdl:        "Colesterol Total",
  hdl_mgdl:                "HDL",
  ldl_mgdl:                "LDL",
  triglycerides_mgdl:      "Triglicerídeos",
  blood_pressure_systolic: "PA Sistólica",
  blood_pressure_diastolic:"PA Diastólica",
  heart_rate_bpm:          "Freq. Cardíaca",
  visceral_fat:            "Gordura Visceral",
  body_analysis:           "Análise Corporal",
};

const GOAL_LABELS: Record<string, string> = {
  lose_weight:  "Perder peso",
  gain_muscle:  "Ganhar músculo",
  maintain:     "Manter peso",
  health:       "Saúde geral",
};

const LEVEL_LABELS: Record<string, string> = {
  beginner:     "Iniciante",
  intermediate: "Intermediário",
  advanced:     "Avançado",
};

const LOCATION_LABELS: Record<string, string> = {
  gym:     "Academia",
  home:    "Casa",
  outdoor: "Ao ar livre",
  any:     "Qualquer lugar",
};

const SOURCE_LABELS: Record<string, string> = {
  exam:        "Exame",
  body_photo:  "Foto corporal",
  manual:      "Manual",
};

function InfoRow({ label, value }: { label: string; value: string | null | undefined }) {
  if (!value) return null;
  return (
    <div className="flex items-start justify-between gap-4 py-2 border-b border-gray-50 last:border-0">
      <span className="text-sm text-gray-500 shrink-0">{label}</span>
      <span className="text-sm font-medium text-gray-900 text-right">{value}</span>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-4 rounded-2xl border border-gray-100 bg-white p-5">
      <h2 className="mb-3 font-semibold text-gray-900">{title}</h2>
      {children}
    </div>
  );
}

function riskColor(fieldName: string, value: number): string {
  const ranges: Record<string, { ok: [number, number] }> = {
    glucose_mgdl:            { ok: [70, 99] },
    cholesterol_mgdl:        { ok: [0, 200] },
    hdl_mgdl:                { ok: [40, 999] },
    ldl_mgdl:                { ok: [0, 130] },
    triglycerides_mgdl:      { ok: [0, 150] },
    blood_pressure_systolic: { ok: [90, 129] },
    blood_pressure_diastolic:{ ok: [60, 84] },
    body_fat_pct:            { ok: [5, 25] },
    bmi:                     { ok: [18.5, 24.9] },
  };
  const r = ranges[fieldName];
  if (!r) return "text-gray-700";
  return value >= r.ok[0] && value <= r.ok[1] ? "text-green-700" : "text-amber-600";
}

export default function DetailedProfilePage() {
  const router = useRouter();
  const [data, setData]     = useState<DetailedProfile | null>(null);
  const [loading, setLoading] = useState(true);

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

  const { physical, data_points, media } = data;

  const bodyPhotos  = media.filter((m) => m.category === "body_photo");
  const exams       = media.filter((m) => m.category === "exam");
  const bodyAnalyses = data_points.filter((dp) => dp.source_type === "body_photo" && dp.field_name === "body_analysis");
  const examPoints   = data_points.filter((dp) => dp.source_type === "exam");
  const photoPoints  = data_points.filter((dp) => dp.source_type === "body_photo" && dp.field_name !== "body_analysis");
  const riskPoints   = examPoints.filter((dp) => {
    const r = { glucose_mgdl: [70, 99], cholesterol_mgdl: [0, 200], ldl_mgdl: [0, 130],
                triglycerides_mgdl: [0, 150], blood_pressure_systolic: [90, 129] };
    const range = r[dp.field_name as keyof typeof r];
    return range && (dp.value < range[0] || dp.value > range[1]);
  });

  return (
    <div className="min-h-screen bg-gray-50 px-4 py-6 pb-28">
      <header className="mb-5 flex items-center gap-3">
        <button
          onClick={() => router.back()}
          className="flex h-9 w-9 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-600"
        >
          ←
        </button>
        <h1 className="text-xl font-bold text-gray-900">Perfil Detalhado</h1>
      </header>

      {/* Dados físicos */}
      {physical && (
        <Section title="Dados Físicos">
          <InfoRow label="Objetivo"        value={physical.goal ? GOAL_LABELS[physical.goal] ?? physical.goal : null} />
          <InfoRow label="Nível"           value={physical.fitness_level ? LEVEL_LABELS[physical.fitness_level] ?? physical.fitness_level : null} />
          <InfoRow label="Idade"           value={physical.age ? `${physical.age} anos` : null} />
          <InfoRow label="Peso"            value={physical.weight_kg ? `${physical.weight_kg} kg` : null} />
          <InfoRow label="Altura"          value={physical.height_cm ? `${physical.height_cm} cm` : null} />
          <InfoRow label="IMC"             value={physical.bmi ? `${physical.bmi}` : null} />
          <InfoRow label="Local de treino" value={physical.training_location ? LOCATION_LABELS[physical.training_location] ?? physical.training_location : null} />
          <InfoRow label="Dias/semana"     value={physical.training_days_per_week ? `${physical.training_days_per_week}x por semana` : null} />
        </Section>
      )}

      {/* Comparação de fotos */}
      {bodyPhotos.length > 0 && (
        <Section title="Evolução Corporal">
          {bodyPhotos.length >= 2 ? (
            <div className="grid grid-cols-2 gap-3 mb-3">
              {[bodyPhotos[bodyPhotos.length - 1], bodyPhotos[0]].map((photo, idx) => (
                <div key={photo.id} className="text-center">
                  <img
                    src={`${API_URL}${photo.file_url}`}
                    alt={idx === 0 ? "Antes" : "Agora"}
                    className="h-36 w-full rounded-xl object-cover"
                  />
                  <p className="mt-1 text-xs font-medium text-gray-600">{idx === 0 ? "Antes" : "Agora"}</p>
                  <p className="text-xs text-gray-400">
                    {new Date(photo.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
                  </p>
                </div>
              ))}
            </div>
          ) : (
            <img
              src={`${API_URL}${bodyPhotos[0].file_url}`}
              alt="Foto corporal"
              className="mb-3 h-40 w-full rounded-xl object-cover"
            />
          )}
          <p className="text-xs text-gray-400">{bodyPhotos.length} foto{bodyPhotos.length !== 1 ? "s" : ""} registrada{bodyPhotos.length !== 1 ? "s" : ""}</p>
        </Section>
      )}

      {/* Análise corporal */}
      {bodyAnalyses.length > 0 && (
        <Section title="Análise das Fotos">
          {bodyAnalyses.map((dp, i) => (
            <div key={dp.id} className={`${i > 0 ? "mt-4 border-t border-gray-100 pt-4" : ""}`}>
              <p className="text-sm leading-relaxed text-gray-700">{dp.ai_notes || dp.raw_text}</p>
              <p className="mt-1 text-xs text-gray-400">
                {new Date(dp.collected_at || dp.created_at).toLocaleDateString("pt-BR", {
                  day: "numeric", month: "short", year: "numeric",
                })}
              </p>
            </div>
          ))}
          <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
            Estas observações são orientações gerais. Consulte um profissional de saúde para avaliação precisa.
          </p>
        </Section>
      )}

      {/* Dados de composição corporal */}
      {photoPoints.length > 0 && (
        <Section title="Composição Corporal Estimada">
          {photoPoints.map((dp) => (
            <div key={dp.id} className="flex items-start justify-between py-2 border-b border-gray-50 last:border-0">
              <span className="text-sm text-gray-500">{FIELD_LABELS[dp.field_name] ?? dp.field_name}</span>
              <div className="text-right">
                <span className={`text-sm font-semibold ${riskColor(dp.field_name, dp.value)}`}>
                  {dp.value}{dp.unit ? ` ${dp.unit}` : ""}
                </span>
                {dp.confidence != null && (
                  <p className="text-xs text-gray-400">{Math.round(dp.confidence * 100)}% confiança</p>
                )}
              </div>
            </div>
          ))}
        </Section>
      )}

      {/* Marcadores de exame */}
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
          {examPoints.map((dp) => (
            <div key={dp.id} className="flex items-start justify-between py-2 border-b border-gray-50 last:border-0">
              <div>
                <span className="text-sm text-gray-600">{FIELD_LABELS[dp.field_name] ?? dp.field_name}</span>
                {dp.ai_notes && <p className="text-xs text-gray-400 mt-0.5">{dp.ai_notes}</p>}
              </div>
              <span className={`text-sm font-semibold shrink-0 ml-2 ${riskColor(dp.field_name, dp.value)}`}>
                {dp.value}{dp.unit ? ` ${dp.unit}` : ""}
              </span>
            </div>
          ))}
          <p className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
            Sugestão: valide os valores com seu médico ou nutricionista.
          </p>
        </Section>
      )}

      {/* Exames salvos */}
      {exams.length > 0 && (
        <Section title={`Exames (${exams.length})`}>
          {exams.map((exam) => (
            <div key={exam.id} className="flex items-center gap-3 py-2 border-b border-gray-50 last:border-0">
              {exam.mime_type === "application/pdf" ? (
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-red-50 text-lg">📄</div>
              ) : (
                <img
                  src={`${API_URL}${exam.file_url}`}
                  alt="Exame"
                  className="h-10 w-10 shrink-0 rounded-lg object-cover"
                />
              )}
              <p className="text-xs text-gray-500">
                {new Date(exam.captured_at).toLocaleDateString("pt-BR", {
                  day: "numeric", month: "short", year: "numeric",
                })}
              </p>
            </div>
          ))}
        </Section>
      )}

      {/* Estado vazio */}
      {!physical && data_points.length === 0 && media.length === 0 && (
        <div className="mt-12 text-center">
          <p className="text-3xl mb-3">📋</p>
          <p className="text-sm text-gray-500">Nenhum dado registrado ainda.</p>
          <p className="mt-1 text-xs text-gray-400">
            Complete seu perfil, adicione fotos e exames para ver o histórico aqui.
          </p>
        </div>
      )}
    </div>
  );
}
