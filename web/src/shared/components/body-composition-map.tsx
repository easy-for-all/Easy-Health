"use client";

import { useState } from "react";

export type BodyRegion = {
  name: string;
  muscleLevel: number;
  fatLevel: number;
  confidence: number;
  note: string;
};

export type BodyCompositionData = {
  estimatedBodyFatPercentage: number | null;
  confidence: number;
  summary: string;
  regions: BodyRegion[];
};

// ── Constants ─────────────────────────────────────────────

const REGION_LABELS: Record<string, string> = {
  chest:      "Peito",
  abdomen:    "Abdômen",
  shoulders:  "Ombros",
  biceps:     "Bíceps",
  triceps:    "Tríceps",
  back:       "Costas",
  glutes:     "Glúteos",
  quadriceps: "Quadríceps",
  hamstrings: "Posteriores",
  calves:     "Panturrilhas",
};

const REGION_SIDE: Record<string, "front" | "back"> = {
  shoulders:  "front",
  chest:      "front",
  biceps:     "front",
  abdomen:    "front",
  quadriceps: "front",
  back:       "back",
  triceps:    "back",
  glutes:     "back",
  hamstrings: "back",
  calves:     "back",
};

const STATUS_COLORS: Record<string, string> = {
  otimo:   "var(--status-otimo)",
  bom:     "var(--status-bom)",
  medio:   "var(--status-medio)",
  atencao: "var(--status-atencao)",
  critico: "var(--status-critico)",
};

const STATUS_LABELS: Record<string, string> = {
  otimo:   "Ótimo",
  bom:     "Bom",
  medio:   "Médio",
  atencao: "Atenção",
  critico: "Crítico",
};

const FRONT_ORDER = ["shoulders", "chest", "biceps", "abdomen", "quadriceps"];
const BACK_ORDER  = ["back", "triceps", "glutes", "hamstrings", "calves"];

// ── Helpers ───────────────────────────────────────────────

function regionStatus(r: BodyRegion): string {
  const s = r.muscleLevel - r.fatLevel;
  if (s >= 2)  return "otimo";
  if (s >= 1)  return "bom";
  if (s >= 0)  return "medio";
  if (s >= -1) return "atencao";
  return "critico";
}

function colorOf(regions: BodyRegion[], name: string): string {
  const r = regions.find((x) => x.name === name);
  if (!r) return "var(--surface-3)";
  return STATUS_COLORS[regionStatus(r)] ?? "var(--surface-3)";
}

// ── SVG Body Map ─────────────────────────────────────────

function BodyFigure({ regions, side }: { regions: BodyRegion[]; side: "front" | "back" }) {
  const c = (name: string) => colorOf(regions, name);
  const BODY = "var(--surface-2)";

  return (
    <svg
      className="bodyfig"
      viewBox="0 0 120 300"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      {/* Silhouette base — always visible */}
      <ellipse cx="60" cy="26" rx="17" ry="18" fill={BODY} />
      <rect x="52" y="40" width="16" height="11" rx="5" fill={BODY} />
      <rect x="33" y="48" width="54" height="74" rx="20" fill={BODY} />
      <rect x="37" y="110" width="46" height="30" rx="15" fill={BODY} />
      <rect x="14" y="52" width="16" height="108" rx="8" fill={BODY} />
      <rect x="90" y="52" width="16" height="108" rx="8" fill={BODY} />
      <rect x="38" y="130" width="20" height="80" rx="10" fill={BODY} />
      <rect x="62" y="130" width="20" height="80" rx="10" fill={BODY} />
      <rect x="40" y="200" width="16" height="86" rx="8" fill={BODY} />
      <rect x="64" y="200" width="16" height="86" rx="8" fill={BODY} />

      {side === "front" ? (
        <>
          <ellipse cx="33" cy="56" rx="13" ry="12" fill={c("shoulders")} />
          <ellipse cx="87" cy="56" rx="13" ry="12" fill={c("shoulders")} />
          <rect x="40" y="56" width="19" height="21" rx="8" fill={c("chest")} />
          <rect x="61" y="56" width="19" height="21" rx="8" fill={c("chest")} />
          <rect x="14" y="64" width="16" height="32" rx="8" fill={c("biceps")} />
          <rect x="90" y="64" width="16" height="32" rx="8" fill={c("biceps")} />
          <rect x="45" y="80" width="30" height="35" rx="9" fill={c("abdomen")} />
          <rect x="38" y="134" width="20" height="54" rx="10" fill={c("quadriceps")} />
          <rect x="62" y="134" width="20" height="54" rx="10" fill={c("quadriceps")} />
        </>
      ) : (
        <>
          <ellipse cx="33" cy="56" rx="13" ry="12" fill={c("shoulders")} />
          <ellipse cx="87" cy="56" rx="13" ry="12" fill={c("shoulders")} />
          <rect x="40" y="56" width="19" height="40" rx="9" fill={c("back")} />
          <rect x="61" y="56" width="19" height="40" rx="9" fill={c("back")} />
          <rect x="14" y="64" width="16" height="32" rx="8" fill={c("triceps")} />
          <rect x="90" y="64" width="16" height="32" rx="8" fill={c("triceps")} />
          <rect x="39" y="112" width="20" height="25" rx="10" fill={c("glutes")} />
          <rect x="61" y="112" width="20" height="25" rx="10" fill={c("glutes")} />
          <rect x="38" y="140" width="20" height="52" rx="10" fill={c("hamstrings")} />
          <rect x="62" y="140" width="20" height="52" rx="10" fill={c("hamstrings")} />
          <rect x="40" y="206" width="16" height="48" rx="8" fill={c("calves")} />
          <rect x="64" y="206" width="16" height="48" rx="8" fill={c("calves")} />
        </>
      )}
    </svg>
  );
}

// ── Pips meter ────────────────────────────────────────────

function Pips({ count, kind }: { count: number; kind: "mus" | "fat" }) {
  return (
    <span className="pips">
      {Array.from({ length: 5 }, (_, i) => (
        <i key={i} className={i < count ? `on ${kind}` : ""} />
      ))}
    </span>
  );
}

// ── Icons ─────────────────────────────────────────────────

function IconDumbbell() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M6.5 6.5h11M6.5 17.5h11M3 12h18M3 9.5v5M21 9.5v5M6.5 6.5v11M17.5 6.5v11" />
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

function IconChevronDown() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
      <polyline points="6 9 12 15 18 9" />
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

// ── Main Component ────────────────────────────────────────

type Props = {
  data: BodyCompositionData;
  onReanalyze?: () => void;
  reanalyzing?: boolean;
  reanalyzeError?: string | null;
  canReanalyze?: boolean;
};

export function BodyCompositionMap({
  data,
  onReanalyze,
  reanalyzing = false,
  reanalyzeError = null,
  canReanalyze = false,
}: Props) {
  const [side, setSide] = useState<"front" | "back">("front");
  const [openRegion, setOpenRegion] = useState<string | null>(null);

  const visibleRegions = (side === "front" ? FRONT_ORDER : BACK_ORDER)
    .map((name) => data.regions.find((r) => r.name === name))
    .filter(Boolean) as BodyRegion[];

  const allRegions = [...FRONT_ORDER, ...BACK_ORDER]
    .map((name) => data.regions.find((r) => r.name === name))
    .filter(Boolean) as BodyRegion[];

  return (
    <div>
      {/* Fat badge + summary */}
      {(data.estimatedBodyFatPercentage != null || data.summary) && (
        <div className="map-top">
          {data.estimatedBodyFatPercentage != null && (
            <div className="fat-badge">
              <b>
                {data.estimatedBodyFatPercentage}
                <small>%</small>
              </b>
              <span>gordura est.</span>
              {data.confidence != null && (
                <em>{Math.round(data.confidence * 100)}% conf.</em>
              )}
            </div>
          )}
          {data.summary && (
            <p className="map-summary">{data.summary}</p>
          )}
        </div>
      )}

      {/* Toggle Frente / Costas */}
      <div className="bm-toggle" role="group" aria-label="Selecionar vista do mapa corporal">
        <button
          className={side === "front" ? "active" : ""}
          onClick={() => setSide("front")}
          aria-pressed={side === "front"}
        >
          Frente
        </button>
        <button
          className={side === "back" ? "active" : ""}
          onClick={() => setSide("back")}
          aria-pressed={side === "back"}
        >
          Costas
        </button>
      </div>

      {/* SVG figure */}
      <div className="bodyfig-wrap">
        <BodyFigure regions={data.regions} side={side} />
      </div>

      {/* Legend */}
      <div className="bm-legend" aria-label="Legenda de status muscular">
        {Object.entries(STATUS_LABELS).map(([key, label]) => (
          <span key={key} className="lg">
            <span className="dot" style={{ background: STATUS_COLORS[key] }} />
            {label}
          </span>
        ))}
      </div>

      {/* Region list — shows all regions, grouped by visible side */}
      <div className="region-list" role="list">
        {allRegions.map((region) => {
          const status = regionStatus(region);
          const color  = STATUS_COLORS[status];
          const isOpen = openRegion === region.name;
          const sideOf = REGION_SIDE[region.name] ?? "front";

          return (
            <button
              key={region.name}
              className={`region-row${isOpen ? " open" : ""}`}
              onClick={() => setOpenRegion(isOpen ? null : region.name)}
              aria-expanded={isOpen}
              role="listitem"
            >
              <span className="rr-head">
                <span
                  className="rdot"
                  style={{ background: color }}
                  aria-hidden="true"
                />
                <span className="rname">
                  {REGION_LABELS[region.name] ?? region.name}
                  {sideOf !== side && (
                    <span
                      style={{ fontSize: 10, color: "var(--text-faint)", marginLeft: 5, fontWeight: 500 }}
                      aria-hidden="true"
                    >
                      {sideOf === "back" ? "costas" : "frente"}
                    </span>
                  )}
                </span>
                <span className="meters" aria-label={`Músculo ${region.muscleLevel}/5, Gordura ${region.fatLevel}/5`}>
                  <span className="meter">
                    <span className="mlbl" aria-label="Músculo">
                      <IconDumbbell />
                    </span>
                    <Pips count={region.muscleLevel} kind="mus" />
                  </span>
                  <span className="meter">
                    <span className="mlbl" aria-label="Gordura">
                      <IconDroplet />
                    </span>
                    <Pips count={region.fatLevel} kind="fat" />
                  </span>
                </span>
                <span className="rchev" aria-hidden="true">
                  <IconChevronDown />
                </span>
              </span>
              {region.note && (
                <span className="rr-note" aria-hidden={!isOpen}>
                  <p>{region.note}</p>
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Reanalyze button */}
      {onReanalyze && (
        <div>
          {reanalyzeError && (
            <p style={{ marginBottom: 8, padding: "8px 12px", borderRadius: "var(--r-sm)", background: "var(--hot-soft)", color: "var(--hot)", fontSize: 13 }}>
              {reanalyzeError}
            </p>
          )}
          <button
            className="btn-reanalyze"
            onClick={onReanalyze}
            disabled={reanalyzing || !canReanalyze}
          >
            {reanalyzing ? "Analisando foto..." : "↺ Reanalisar foto mais recente"}
          </button>
          {!canReanalyze && !reanalyzing && (
            <p style={{ marginTop: 6, fontSize: 12, color: "var(--text-dim)", textAlign: "center" }}>
              Adicione uma foto corporal para usar esta função.
            </p>
          )}
        </div>
      )}

      {/* Empty body map state — no data yet */}
      {data.regions.length === 0 && (
        <div className="empty-card">
          <div className="ei">
            <IconSparkles />
          </div>
          <b>Mapa corporal não gerado ainda</b>
          <p>Adicione uma foto corporal para a IA gerar o mapa muscular personalizado.</p>
        </div>
      )}
    </div>
  );
}
