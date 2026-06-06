"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { AgentOrb } from "@/shared/components/agent-orb/agent-orb";
import { BodyCompositionMap, type BodyCompositionData } from "@/shared/components/body-composition-map";
import "./profile-detail.css";

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

function bmiClass(bmi: number) {
  if (bmi < 18.5) return { label: "Abaixo do peso", status: "cool" };
  if (bmi < 25)   return { label: "Peso normal",    status: "good" };
  if (bmi < 30)   return { label: "Sobrepeso",      status: "warn" };
  return               { label: "Obesidade",         status: "hot" };
}

// ─── Icon helpers ─────────────────────────────────────────────────────────────

function IconBack() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ width: 18, height: 18 }}>
      <polyline points="15 18 9 12 15 6" />
    </svg>
  );
}

function IconInfo() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="16" x2="12" y2="12" />
      <line x1="12" y1="8" x2="12.01" y2="8" />
    </svg>
  );
}

function IconScale() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 20h20M6 20V10l6-6 6 6v10" />
      <path d="M10 20v-5h4v5" />
    </svg>
  );
}

function IconTarget() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <circle cx="12" cy="12" r="6" />
      <circle cx="12" cy="12" r="2" />
    </svg>
  );
}

function IconFire() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z" />
      <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  );
}

function IconDroplet() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z" />
    </svg>
  );
}

function IconDoc() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="8" y1="13" x2="16" y2="13" />
      <line x1="8" y1="17" x2="12" y2="17" />
    </svg>
  );
}

function IconChevronRight() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" style={{ width: 16, height: 16 }}>
      <polyline points="9 18 15 12 9 6" />
    </svg>
  );
}

function IconSparkles() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6L12 3z" />
      <path d="M19 14l.7 1.9L21.6 17l-1.9.7L19 19.6l-.7-1.9L16.4 17l1.9-.7L19 14z" />
    </svg>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function DetailedProfilePage() {
  const router = useRouter();
  const [data, setData]             = useState<DetailedProfile | null>(null);
  const [loading, setLoading]       = useState(true);
  const [reanalyzing, setReanalyzing]       = useState(false);
  const [reanalyzeError, setReanalyzeError] = useState<string | null>(null);
  const [lightboxItem, setLightboxItem]     = useState<MediaItem | null>(null);

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
      <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
        <button onClick={() => router.back()} className="pdt-back" style={{ marginBottom: 16 }}>
          <IconBack />
        </button>
        <p style={{ textAlign: "center", fontSize: 14, color: "var(--text-dim)", marginTop: 48 }}>
          Não foi possível carregar o perfil detalhado.
        </p>
      </div>
    );
  }

  const { data_points, media } = data;

  const bodyPhotos    = media.filter((m) => m.category === "body_photo");
  const exams         = media.filter((m) => m.category === "exam");
  const analyzablePhoto = bodyPhotos.find((p) => p.file_url !== null) ?? null;

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

  const compositionPoints: DataPoint[] = COMPOSITION_FIELDS.flatMap((field) => {
    const candidates = data_points.filter((dp) => dp.field_name === field);
    if (candidates.length === 0) return [];
    const fromExam  = candidates.find((dp) => dp.source_type === "exam");
    const fromPhoto = candidates.find((dp) => dp.source_type === "body_photo");
    return [fromExam ?? fromPhoto!];
  });

  // Estimated analysis values
  const estW   = data.physical?.weight_kg ?? null;
  const estH   = data.physical?.height_cm ?? null;
  const estAge = data.physical?.age ?? null;
  const estFatPct = compositionPoints.find((dp) => dp.field_name === "body_fat_pct")?.value ?? null;
  const estBmiRaw = data.physical?.bmi ?? (estW && estH ? estW / ((estH / 100) ** 2) : null);
  const estBmi    = estBmiRaw ? Math.round(estBmiRaw * 10) / 10 : null;
  const estIdealMin = estH ? Math.round(18.5 * (estH / 100) ** 2 * 10) / 10 : null;
  const estIdealMax = estH ? Math.round(24.9 * (estH / 100) ** 2 * 10) / 10 : null;
  const estBmr = estW && estH && estAge ? Math.round(10 * estW + 6.25 * estH - 5 * estAge) : null;
  const estLeanMass = estW && estFatPct != null ? Math.round(estW * (1 - estFatPct / 100) * 10) / 10 : null;
  const estBodyWater = estLeanMass
    ? Math.round(estLeanMass * 0.73 * 10) / 10
    : estW ? Math.round(estW * 0.60 * 10) / 10 : null;
  const estBmiInfo = estBmi ? bmiClass(estBmi) : null;
  const hasEstData = !!(estBmi || estIdealMin || estBmr || estBodyWater);

  const photoBeforeItem = bodyPhotos.length >= 2 ? bodyPhotos[bodyPhotos.length - 1] : null;
  const photoNowItem    = bodyPhotos.length >= 1 ? bodyPhotos[0] : null;

  const daysBetweenPhotos = photoBeforeItem && photoNowItem
    ? Math.abs(Math.round(
        (new Date(photoNowItem.captured_at).getTime() - new Date(photoBeforeItem.captured_at).getTime())
        / 86400000
      ))
    : null;

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
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>

      {/* ── Topbar ── */}
      <div className="pdt-topbar">
        <button
          className="pdt-back"
          onClick={() => router.back()}
          aria-label="Voltar para perfil"
        >
          <IconBack />
        </button>
        <span className="ai-pill">
          ✦ IA
        </span>
      </div>

      {/* ── Cabeçalho ── */}
      <div className="pdt-head pdt-rise" style={{ animationDelay: "0.02s" }}>
        <span className="eyebrow accent">Perfil · saúde</span>
        <h1 className="pdt-title">Composição corporal</h1>
        <p className="pdt-lede">Estimativas da IA com base nas suas fotos e dados físicos.</p>
      </div>

      {/* ── 1. Análise detalhada (metric grid) ── */}
      {hasEstData && (
        <div className="pdt-section pdt-rise" style={{ animationDelay: "0.06s" }}>
          <span className="eyebrow" style={{ display: "block", marginBottom: 11 }}>Análise detalhada</span>
          <div className="metric-grid">

            {/* IMC */}
            {estBmi && estBmiInfo && (
              <div className="metric">
                <div className="mk">
                  <span className="mic"><IconScale /></span>
                  IMC
                </div>
                <div className={`mv${estBmiInfo.status === "warn" || estBmiInfo.status === "hot" ? " warn" : ""}`}>
                  {estBmi}
                </div>
                {estBmiInfo && (
                  <span className={`mtag ${estBmiInfo.status === "good" ? "good" : estBmiInfo.status === "warn" || estBmiInfo.status === "hot" ? "warn" : ""}`}
                    style={estBmiInfo.status === "good"
                      ? { color: "var(--good)", background: "var(--good-soft)" }
                      : estBmiInfo.status === "hot"
                      ? { color: "var(--hot)", background: "var(--hot-soft)" }
                      : undefined
                    }
                  >
                    {estBmiInfo.label}
                  </span>
                )}
              </div>
            )}

            {/* Peso ideal */}
            {estIdealMin && estIdealMax && (
              <div className="metric">
                <div className="mk">
                  <span className="mic"><IconTarget /></span>
                  Peso ideal
                </div>
                <div className="mv">
                  {estIdealMin}–{estIdealMax}
                  <small> kg</small>
                </div>
              </div>
            )}

            {/* TMB estimada */}
            {estBmr && (
              <div className="metric">
                <div className="mk">
                  <span className="mic"><IconFire /></span>
                  TMB estimada
                </div>
                <div className="mv">
                  ~{estBmr}
                  <small> kcal/dia</small>
                </div>
              </div>
            )}

            {/* Água corporal */}
            {estBodyWater && (
              <div className="metric">
                <div className="mk">
                  <span className="mic"><IconDroplet /></span>
                  Água corporal
                </div>
                <div className="mv">
                  ~{estBodyWater}
                  <small> litros</small>
                </div>
              </div>
            )}

          </div>

          {/* Nota disclaimer */}
          <div className="note-line">
            <span className="lic"><IconInfo /></span>
            <span>Valores estimados para acompanhamento. Consulte um profissional para avaliação precisa.</span>
          </div>
        </div>
      )}

      {/* ── 2. Evolução corporal ── */}
      {bodyPhotos.length > 0 && (
        <div className="pdt-section pdt-rise" style={{ animationDelay: "0.10s" }}>
          <div className="pdt-section-header">
            <span className="eyebrow">Evolução corporal</span>
            {daysBetweenPhotos != null && (
              <span className="evo-tag">{daysBetweenPhotos} dias</span>
            )}
          </div>
          <div className="evo-compare">
            {/* Antes */}
            <figure className="evo">
              {photoBeforeItem?.file_url ? (
                <button onClick={() => setLightboxItem(photoBeforeItem)} style={{ display: "block", width: "100%", background: "none", border: 0, padding: 0, cursor: "pointer" }} aria-label="Ver foto anterior">
                  <img
                    src={`${API_URL}${photoBeforeItem.file_url}`}
                    alt="Foto antes"
                    className="evo-img"
                  />
                </button>
              ) : (
                <div className="evo-placeholder">
                  <span>Adicione mais fotos para comparar</span>
                </div>
              )}
              <figcaption>
                <b>Antes</b>
                <span>{photoBeforeItem ? formatDate(photoBeforeItem.captured_at) : "—"}</span>
              </figcaption>
            </figure>

            {/* Agora */}
            <figure className="evo">
              {photoNowItem?.file_url ? (
                <button onClick={() => setLightboxItem(photoNowItem)} style={{ display: "block", width: "100%", background: "none", border: 0, padding: 0, cursor: "pointer" }} aria-label="Ver foto atual">
                  <img
                    src={`${API_URL}${photoNowItem.file_url}`}
                    alt="Foto agora"
                    className="evo-img"
                  />
                </button>
              ) : (
                <div className="evo-placeholder">
                  <span>Nenhuma foto ainda</span>
                </div>
              )}
              <figcaption>
                <b>Agora</b>
                <span>{photoNowItem ? formatDate(photoNowItem.captured_at) : "—"}</span>
              </figcaption>
            </figure>
          </div>
        </div>
      )}

      {/* ── 3. Análise da última foto ── */}
      {bodyAnalyses.length > 0 && (
        <div className="pdt-section pdt-rise" style={{ animationDelay: "0.13s" }}>
          <div className="insight">
            <div className="ihead">
              <AgentOrb size="card" glyph />
              <b>Análise da última foto</b>
              <span className="itag">
                {formatDate(bodyAnalyses[0].collected_at || bodyAnalyses[0].created_at)}
              </span>
            </div>
            <p>{bodyAnalyses[0].ai_notes || bodyAnalyses[0].raw_text}</p>
          </div>
        </div>
      )}

      {/* ── 4. Mapa corporal por IA ── */}
      {(bodyCompositionData || bodyPhotos.length > 0) && (
        <div className="pdt-section pdt-rise" style={{ animationDelay: "0.16s" }}>
          <div className="explain">
            <div className="ehead">
              <AgentOrb size="card" glyph />
              <b>Mapa corporal por IA</b>
            </div>

            {bodyCompositionData ? (
              <BodyCompositionMap
                data={bodyCompositionData}
                onReanalyze={handleReanalyze}
                reanalyzing={reanalyzing}
                reanalyzeError={reanalyzeError}
                canReanalyze={!!analyzablePhoto}
              />
            ) : (
              <div style={{ textAlign: "center", padding: "8px 0 4px" }}>
                <p style={{ fontSize: 13.5, color: "var(--text-muted)", marginBottom: 14, lineHeight: 1.55 }}>
                  Gere um mapa corporal detalhado a partir da sua foto mais recente.
                </p>
                {reanalyzeError && (
                  <p style={{ marginBottom: 10, padding: "8px 12px", borderRadius: "var(--r-sm)", background: "var(--hot-soft)", color: "var(--hot)", fontSize: 13 }}>
                    {reanalyzeError}
                  </p>
                )}
                <button
                  className="btn-reanalyze"
                  onClick={handleReanalyze}
                  disabled={reanalyzing || !analyzablePhoto}
                  style={{ borderStyle: "solid" }}
                >
                  {reanalyzing ? "Analisando foto..." : "🔍 Gerar mapa corporal"}
                </button>
                {!analyzablePhoto && (
                  <p style={{ marginTop: 8, fontSize: 12, color: "var(--text-dim)" }}>
                    {bodyPhotos.length === 0
                      ? "Adicione uma foto corporal para ativar essa funcionalidade."
                      : "A foto salva não está mais disponível. Envie uma nova foto."}
                  </p>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ── 5. Exames ── */}
      <div className="pdt-section pdt-rise" style={{ animationDelay: "0.19s" }}>
        <div className="pdt-section-header">
          <span className="eyebrow">
            Exames
            {exams.length > 0 && (
              <span style={{ marginLeft: 5, fontSize: 11, color: "var(--text-dim)", letterSpacing: 0, fontWeight: 600, textTransform: "none" }}>
                ({exams.length})
              </span>
            )}
          </span>
          <button className="pdt-section-action">+ Enviar</button>
        </div>

        {exams.length > 0 ? (
          <div className="list-card">
            {exams.map((exam) => {
              const isPdf = exam.mime_type === "application/pdf";
              return (
                <button
                  key={exam.id}
                  className="list-card-item"
                  onClick={() => {
                    if (isPdf && exam.file_url) {
                      window.open(`${API_URL}${exam.file_url}`, "_blank");
                    } else {
                      setLightboxItem(exam);
                    }
                  }}
                  aria-label={`Abrir exame: ${exam.file_name || "Exame"}`}
                >
                  <span className="list-card-icon">
                    <IconDoc />
                  </span>
                  <span className="list-card-text">
                    <span className="list-card-name">{exam.file_name || "Exame"}</span>
                    <span className="list-card-date">{formatDate(exam.captured_at)}</span>
                  </span>
                  <span className="list-card-chevron" aria-hidden="true">
                    <IconChevronRight />
                  </span>
                </button>
              );
            })}
          </div>
        ) : (
          <div className="empty-card">
            <div className="ei">
              <IconDoc />
            </div>
            <b>Nenhum exame enviado</b>
            <p>Envie seus resultados de exames para a IA extrair e acompanhar seus marcadores de saúde.</p>
          </div>
        )}
      </div>

      {/* ── 6. Recomendações ── */}
      <div className="pdt-section pdt-rise" style={{ animationDelay: "0.22s" }}>
        <span className="eyebrow" style={{ display: "block", marginBottom: 11 }}>Recomendações</span>
        {examPoints.length > 0 || compositionPoints.length > 0 ? (
          <div className="insight">
            <p style={{ margin: 0 }}>
              Com base no seu histórico, mantenha consistência nos treinos e acompanhe sua
              evolução regularmente. Consulte um profissional de saúde para orientações
              personalizadas sobre dieta e exercício.
            </p>
          </div>
        ) : (
          <div className="empty-card">
            <div className="ei">
              <IconSparkles />
            </div>
            <b>Sem recomendações ainda</b>
            <p>Adicione fotos e exames para a IA gerar recomendações personalizadas.</p>
          </div>
        )}
      </div>

      {/* ─── Lightbox ─────────────────────────────────────── */}
      {lightboxItem && (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center"
          style={{ background: "rgba(0,0,0,0.9)" }}
          onClick={() => setLightboxItem(null)}
        >
          <button
            onClick={() => setLightboxItem(null)}
            aria-label="Fechar"
            style={{
              position: "absolute", right: 16, top: 16,
              width: 40, height: 40, borderRadius: "50%",
              background: "rgba(255,255,255,0.15)", border: 0,
              color: "#fff", fontSize: 18, cursor: "pointer",
              display: "grid", placeItems: "center",
            }}
          >
            ✕
          </button>
          <img
            src={`${API_URL}${lightboxItem.file_url}`}
            alt="Visualização"
            style={{ maxHeight: "88svh", maxWidth: "92vw", borderRadius: "var(--r-md)", objectFit: "contain" }}
            onClick={(e) => e.stopPropagation()}
          />
          {lightboxItem.captured_at && (
            <p style={{ position: "absolute", bottom: 24, fontSize: 13, color: "rgba(255,255,255,0.6)" }}>
              {formatDate(lightboxItem.captured_at)}
            </p>
          )}
        </div>
      )}

    </div>
  );
}
