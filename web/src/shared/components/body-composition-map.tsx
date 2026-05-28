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

const REGION_LABELS: Record<string, string> = {
  chest:       "Peito",
  abdomen:     "Abdômen",
  shoulders:   "Ombros",
  biceps:      "Bíceps",
  triceps:     "Tríceps",
  back:        "Costas",
  glutes:      "Glúteos",
  quadriceps:  "Quadríceps",
  hamstrings:  "Posteriores",
  calves:      "Panturrilhas",
};

function regionFill(muscleLevel: number, fatLevel: number): string {
  const score = muscleLevel - fatLevel;
  if (score >= 2)  return "#22c55e";
  if (score >= 1)  return "#84cc16";
  if (score >= 0)  return "#f59e0b";
  if (score >= -1) return "#f97316";
  return "#ef4444";
}

function getRegion(regions: BodyRegion[], name: string) {
  return regions.find((r) => r.name === name);
}

function regionProps(regions: BodyRegion[], name: string) {
  const r = getRegion(regions, name);
  if (!r) return { fill: "#d1d5db", fillOpacity: 0.3 };
  return {
    fill:        regionFill(r.muscleLevel, r.fatLevel),
    fillOpacity: 0.25 + r.confidence * 0.55,
  };
}

const GRAY = "#d1d5db";
const SW   = "1";

function FrontView({ regions }: { regions: BodyRegion[] }) {
  const rp = (name: string) => regionProps(regions, name);

  return (
    <svg viewBox="0 0 80 160" style={{ width: 80, height: 160 }} xmlns="http://www.w3.org/2000/svg">
      {/* Head */}
      <ellipse cx="40" cy="13" rx="11" ry="12" fill={GRAY} fillOpacity={0.4} stroke={GRAY} strokeWidth={SW} />
      {/* Neck */}
      <rect x="34" y="24" width="12" height="8" fill={GRAY} fillOpacity={0.4} stroke={GRAY} strokeWidth={SW} />

      {/* Shoulders */}
      <ellipse cx="15" cy="33" rx="9" ry="5" {...rp("shoulders")} stroke={GRAY} strokeWidth={SW} />
      <ellipse cx="65" cy="33" rx="9" ry="5" {...rp("shoulders")} stroke={GRAY} strokeWidth={SW} />

      {/* Chest — upper torso */}
      <path d="M18 31 Q17 46 16 60 L64 60 Q63 46 62 31 Q52 33 40 33 Q28 33 18 31 Z" {...rp("chest")} stroke={GRAY} strokeWidth={SW} />

      {/* Abdomen — lower torso */}
      <path d="M16 60 L64 60 L65 88 L15 88 Z" {...rp("abdomen")} stroke={GRAY} strokeWidth={SW} />

      {/* Biceps — upper arms */}
      <path d="M18 33 Q11 46 11 60 Q14 62 17 60 Q18 48 21 35 Z" {...rp("biceps")} stroke={GRAY} strokeWidth={SW} />
      <path d="M62 33 Q69 46 69 60 Q66 62 63 60 Q62 48 59 35 Z" {...rp("biceps")} stroke={GRAY} strokeWidth={SW} />

      {/* Forearms — gray, no tracked region */}
      <path d="M11 60 Q9 68 11 77 Q15 79 19 77 Q19 67 17 60 Z" fill={GRAY} fillOpacity={0.2} stroke={GRAY} strokeWidth={SW} />
      <path d="M69 60 Q71 68 69 77 Q65 79 61 77 Q61 67 63 60 Z" fill={GRAY} fillOpacity={0.2} stroke={GRAY} strokeWidth={SW} />

      {/* Quadriceps — upper legs */}
      <path d="M15 88 Q12 108 13 120 L30 120 Q31 108 33 88 Z" {...rp("quadriceps")} stroke={GRAY} strokeWidth={SW} />
      <path d="M65 88 Q68 108 67 120 L50 120 Q49 108 47 88 Z" {...rp("quadriceps")} stroke={GRAY} strokeWidth={SW} />

      {/* Lower legs — gray */}
      <path d="M13 120 Q12 133 14 145 Q22 147 28 145 Q29 133 30 120 Z" fill={GRAY} fillOpacity={0.2} stroke={GRAY} strokeWidth={SW} />
      <path d="M67 120 Q68 133 66 145 Q58 147 52 145 Q51 133 50 120 Z" fill={GRAY} fillOpacity={0.2} stroke={GRAY} strokeWidth={SW} />
    </svg>
  );
}

function BackView({ regions }: { regions: BodyRegion[] }) {
  const rp = (name: string) => regionProps(regions, name);

  return (
    <svg viewBox="0 0 80 160" style={{ width: 80, height: 160 }} xmlns="http://www.w3.org/2000/svg">
      {/* Head */}
      <ellipse cx="40" cy="13" rx="11" ry="12" fill={GRAY} fillOpacity={0.4} stroke={GRAY} strokeWidth={SW} />
      {/* Neck */}
      <rect x="34" y="24" width="12" height="8" fill={GRAY} fillOpacity={0.4} stroke={GRAY} strokeWidth={SW} />

      {/* Shoulder caps */}
      <ellipse cx="15" cy="33" rx="9" ry="5" {...rp("shoulders")} stroke={GRAY} strokeWidth={SW} />
      <ellipse cx="65" cy="33" rx="9" ry="5" {...rp("shoulders")} stroke={GRAY} strokeWidth={SW} />

      {/* Back — torso */}
      <path d="M18 31 Q14 60 15 88 L65 88 Q66 60 62 31 Q52 33 40 33 Q28 33 18 31 Z" {...rp("back")} stroke={GRAY} strokeWidth={SW} />

      {/* Triceps — upper arms */}
      <path d="M18 33 Q11 46 11 60 Q14 62 17 60 Q18 48 21 35 Z" {...rp("triceps")} stroke={GRAY} strokeWidth={SW} />
      <path d="M62 33 Q69 46 69 60 Q66 62 63 60 Q62 48 59 35 Z" {...rp("triceps")} stroke={GRAY} strokeWidth={SW} />

      {/* Forearms — gray */}
      <path d="M11 60 Q9 68 11 77 Q15 79 19 77 Q19 67 17 60 Z" fill={GRAY} fillOpacity={0.2} stroke={GRAY} strokeWidth={SW} />
      <path d="M69 60 Q71 68 69 77 Q65 79 61 77 Q61 67 63 60 Z" fill={GRAY} fillOpacity={0.2} stroke={GRAY} strokeWidth={SW} />

      {/* Glutes — upper leg */}
      <path d="M15 88 Q12 100 13 107 L30 107 Q31 100 33 88 Z" {...rp("glutes")} stroke={GRAY} strokeWidth={SW} />
      <path d="M65 88 Q68 100 67 107 L50 107 Q49 100 47 88 Z" {...rp("glutes")} stroke={GRAY} strokeWidth={SW} />

      {/* Hamstrings — mid leg */}
      <path d="M13 107 Q12 114 13 120 L30 120 Q31 114 30 107 Z" {...rp("hamstrings")} stroke={GRAY} strokeWidth={SW} />
      <path d="M67 107 Q68 114 67 120 L50 120 Q49 114 50 107 Z" {...rp("hamstrings")} stroke={GRAY} strokeWidth={SW} />

      {/* Calves — lower leg */}
      <path d="M13 120 Q12 133 14 145 Q22 147 28 145 Q29 133 30 120 Z" {...rp("calves")} stroke={GRAY} strokeWidth={SW} />
      <path d="M67 120 Q68 133 66 145 Q58 147 52 145 Q51 133 50 120 Z" {...rp("calves")} stroke={GRAY} strokeWidth={SW} />
    </svg>
  );
}

export function BodyCompositionMap({ data }: { data: BodyCompositionData }) {
  const [expandedRegion, setExpandedRegion] = useState<string | null>(null);

  const frontRegions  = ["shoulders", "chest", "biceps", "abdomen", "quadriceps"];
  const backRegions   = ["back", "triceps", "glutes", "hamstrings", "calves"];
  const orderedRegions = [...frontRegions, ...backRegions];
  const displayRegions = orderedRegions
    .map((name) => data.regions.find((r) => r.name === name))
    .filter(Boolean) as BodyRegion[];

  return (
    <div>
      {/* Summary row */}
      {(data.estimatedBodyFatPercentage != null || data.summary) && (
        <div className="mb-4 flex items-start gap-3">
          {data.estimatedBodyFatPercentage != null && (
            <div className="shrink-0 rounded-xl bg-gray-50 border border-gray-100 px-3 py-2 text-center">
              <p className="text-2xl font-bold text-gray-900">{data.estimatedBodyFatPercentage}%</p>
              <p className="text-xs text-gray-400">gordura est.</p>
              {data.confidence != null && (
                <p className="text-xs text-gray-400">{Math.round(data.confidence * 100)}% conf.</p>
              )}
            </div>
          )}
          {data.summary && (
            <p className="flex-1 text-sm leading-relaxed text-gray-600">{data.summary}</p>
          )}
        </div>
      )}

      {/* Front + Back body views */}
      <div className="flex items-start justify-center gap-8 mb-4">
        <div className="flex flex-col items-center gap-1">
          <p className="text-xs font-medium text-gray-400">Frente</p>
          <FrontView regions={data.regions} />
        </div>
        <div className="flex flex-col items-center gap-1">
          <p className="text-xs font-medium text-gray-400">Costas</p>
          <BackView regions={data.regions} />
        </div>
      </div>

      {/* Legend */}
      <div className="mb-4 flex flex-wrap items-center justify-center gap-x-3 gap-y-1.5">
        {[
          { color: "#22c55e", label: "Ótimo" },
          { color: "#84cc16", label: "Bom" },
          { color: "#f59e0b", label: "Médio" },
          { color: "#f97316", label: "Atenção" },
          { color: "#ef4444", label: "Crítico" },
        ].map(({ color, label }) => (
          <div key={label} className="flex items-center gap-1">
            <div className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: color }} />
            <span className="text-xs text-gray-500">{label}</span>
          </div>
        ))}
      </div>

      {/* Region breakdown */}
      <div className="space-y-1">
        {displayRegions.map((region) => {
          const color   = regionFill(region.muscleLevel, region.fatLevel);
          const isOpen  = expandedRegion === region.name;
          return (
            <button
              key={region.name}
              onClick={() => setExpandedRegion(isOpen ? null : region.name)}
              className="w-full rounded-xl px-3 py-2.5 text-left transition hover:bg-gray-50 active:bg-gray-100"
            >
              <div className="flex items-center gap-3">
                <div className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: color }} />
                <span className="flex-1 text-sm text-gray-700">
                  {REGION_LABELS[region.name] ?? region.name}
                </span>
                <span className="text-xs text-gray-400">
                  💪 {region.muscleLevel}/5 · 🔵 {region.fatLevel}/5
                </span>
                <span className="text-xs text-gray-300">{isOpen ? "▲" : "▼"}</span>
              </div>
              {isOpen && region.note && (
                <p className="mt-1.5 pl-5 text-xs text-gray-500 leading-relaxed">{region.note}</p>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
