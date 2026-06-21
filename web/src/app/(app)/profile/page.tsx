"use client";

import React, { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslations, useLocale } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";
import { useTheme } from "@/features/theme/theme-context";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { compressImage } from "@/shared/lib/image";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { DeleteAccountModal } from "@/shared/components/delete-account-modal";
import { CleanDataModal } from "@/shared/components/clean-data-modal";
import { setLocale } from "@/app/actions";
import type { HealthProfile, Goal, FitnessLevel } from "@/shared/types/health-profile";
import "@/shared/components/workout/workout-ui.css";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

type Stats = { total_sessions: number; streak: number; best_streak?: number; last_activity_at?: string | null };
type MediaCategory = "body_photo" | "exam";
type UserMedia = {
  id: number;
  category: MediaCategory;
  notes: string | null;
  captured_at: string;
  file_url: string;
  file_name?: string;
  file_size?: number;
  mime_type?: string;
};
type ExtractedDataPoint = {
  id: number;
  field_name: string;
  value: number;
  unit: string | null;
  confidence: number | null;
  ai_notes: string | null;
};
const FIELD_LABELS: Record<string, string> = {
  weight_kg:                  "Peso",
  height_cm:                  "Altura",
  bmi:                        "IMC",
  body_fat_pct:               "% Gordura",
  muscle_mass_kg:             "Massa Muscular",
  glucose_mgdl:               "Glicose",
  cholesterol_mgdl:           "Colesterol Total",
  hdl_mgdl:                   "HDL",
  ldl_mgdl:                   "LDL",
  triglycerides_mgdl:         "Triglicerídeos",
  blood_pressure_systolic:    "PA Sistólica",
  blood_pressure_diastolic:   "PA Diastólica",
  heart_rate_bpm:             "Freq. Cardíaca",
  visceral_fat:               "Gordura Visceral",
};

export default function ProfilePage() {
  const { user, signOut, updateUser } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const router = useRouter();
  const t = useTranslations("profile");
  const locale = useLocale();

  const [profile, setProfile] = useState<HealthProfile | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<Partial<HealthProfile>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [, startTransition] = useTransition();

  const [mediaTab, setMediaTab] = useState<MediaCategory>("body_photo");
  const [mediaItems, setMediaItems] = useState<UserMedia[]>([]);
  const [mediaViewMode, setMediaViewMode] = useState<"grid" | "list">("grid");
  const [uploadingMedia, setUploadingMedia] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [avatarError, setAvatarError] = useState("");
  const [mediaUploadError, setMediaUploadError] = useState("");
  const [faceBlurredNotice, setFaceBlurredNotice] = useState(false);
  const [pendingDataPoints, setPendingDataPoints] = useState<ExtractedDataPoint[]>([]);
  const [confirmingDp, setConfirmingDp] = useState<number | null>(null);
  const [bodyAnalysis, setBodyAnalysis] = useState<{ id: number; observation: string; confidence: number | null } | null>(null);
  const [photoHistoryOpen, setPhotoHistoryOpen] = useState(false);
  const [lightboxPhoto, setLightboxPhoto] = useState<UserMedia | null>(null);
  const [deleteAccountOpen, setDeleteAccountOpen] = useState(false);
  const [cleanDataOpen, setCleanDataOpen] = useState(false);
  const [showUpdatePlanPrompt, setShowUpdatePlanPrompt] = useState(false);
  const [regenerating, setRegenerating] = useState(false);
  const [bodyHistory, setBodyHistory] = useState<{ field_name: string; value: number; unit: string | null; collected_at: string }[]>([]);

  const avatarInputRef = useRef<HTMLInputElement>(null);
  const mediaInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "perfil" });
  }, []);

  useEffect(() => {
    Promise.all([
      api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
      api.get<Stats>("/api/v1/workout_sessions/stats").catch(() => null),
      api.get<UserMedia[]>("/api/v1/user_media").catch(() => []),
      api.get<{ field_name: string; value: number; unit: string | null; collected_at: string }[]>("/api/v1/health_data_points/history").catch(() => []),
    ]).then(([p, s, media, history]) => {
      setProfile(p);
      setStats(s);
      setMediaItems(media ?? []);
      setBodyHistory(Array.isArray(history) ? history : []);
      if (p) setForm({ age: p.age, weight_kg: p.weight_kg, height_cm: p.height_cm, goal: p.goal, fitness_level: p.fitness_level, limitations: p.limitations ?? [] });
    }).finally(() => setLoading(false));
  }, []);

  async function handleSave() {
    setError("");
    setSaving(true);
    const prevGoal = profile?.goal;
    const prevFitnessLevel = profile?.fitness_level;
    try {
      const updated = profile
        ? await api.patch<HealthProfile>("/api/v1/health_profile", form)
        : await api.post<HealthProfile>("/api/v1/health_profile", form);
      setProfile(updated);
      setEditing(false);
      if (form.goal !== prevGoal || form.fitness_level !== prevFitnessLevel) {
        setShowUpdatePlanPrompt(true);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : t("saveError"));
    } finally {
      setSaving(false);
    }
  }

  async function handleRegeneratePlan() {
    setRegenerating(true);
    try {
      await api.post("/api/v1/workout_plan/regenerate", {}, { timeout: 90_000 });
      router.push("/plan");
    } catch {
      setRegenerating(false);
    }
  }

  async function handleSignOut() {
    try {
      await signOut();
    } finally {
      router.replace("/login");
      router.refresh();
    }
  }

  function handleLocaleChange(next: "pt-BR" | "en-US") {
    startTransition(async () => {
      await setLocale(next);
      router.refresh();
    });
  }

  async function handleAvatarChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingAvatar(true);
    setAvatarError("");
    try {
      const compressed = await compressImage(file, 1200, 0.85);
      const formData = new FormData();
      formData.append("avatar", compressed);
      const result = await api.upload<{ avatar_url: string }>("/api/v1/profile/avatar", formData);
      updateUser({ avatar_url: result.avatar_url });
    } catch (err) {
      setAvatarError(err instanceof Error ? err.message : "Erro ao salvar foto");
    } finally {
      setUploadingAvatar(false);
      if (avatarInputRef.current) avatarInputRef.current.value = "";
    }
  }

  async function handleMediaUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingMedia(true);
    setMediaUploadError("");
    setFaceBlurredNotice(false);
    try {
      const processed = file.type.startsWith("image/") ? await compressImage(file, 1920, 0.85) : file;
      const formData = new FormData();
      formData.append("file", processed);
      formData.append("category", mediaTab);
      formData.append("captured_at", new Date().toISOString());

      const res = await fetch(`${API_URL}/api/v1/user_media`, {
        method: "POST",
        credentials: "include",
        body: formData,
      });
      const body = await res.json();

      if (!res.ok) {
        const msg = body?.error || body?.errors?.[0] || "Erro ao enviar arquivo.";
        setMediaUploadError(msg);
        return;
      }

      if (body?.face_blurred) {
        setFaceBlurredNotice(true);
      }

      if (body?.extracted_data?.length > 0) {
        setPendingDataPoints(body.extracted_data as ExtractedDataPoint[]);
      }

      if (body?.body_analysis?.observation) {
        setBodyAnalysis(body.body_analysis);
      }

      setMediaItems((prev) => [body as UserMedia, ...prev]);
    } catch {
      setMediaUploadError("Erro ao enviar arquivo. Tente novamente.");
    } finally {
      setUploadingMedia(false);
      if (mediaInputRef.current) mediaInputRef.current.value = "";
    }
  }

  async function handleDeleteMedia(id: number) {
    await api.delete(`/api/v1/user_media/${id}`).catch(() => null);
    setMediaItems((prev) => prev.filter((m) => m.id !== id));
  }

  async function handleDataPointAction(dp: ExtractedDataPoint, actionType: "confirm" | "save_advanced" | "ignore") {
    setConfirmingDp(dp.id);
    try {
      await api.patch(`/api/v1/health_data_points/${dp.id}`, { action_type: actionType });
      if (actionType === "confirm") {
        const updated = await api.get<HealthProfile>("/api/v1/health_profile").catch(() => null);
        if (updated) setProfile(updated);
      }
      setPendingDataPoints((prev) => prev.filter((p) => p.id !== dp.id));
    } catch {
      // keep the card visible on error
    } finally {
      setConfirmingDp(null);
    }
  }

  if (loading) return <LoadingScreen />;

  const goalLabels: Record<Goal, string> = {
    lose_weight: t("goals.lose_weight"),
    gain_muscle: t("goals.gain_muscle"),
    maintain:    t("goals.maintain"),
    health:      t("goals.health"),
  };

  const levelLabels: Record<FitnessLevel, string> = {
    beginner:     t("levels.beginner"),
    intermediate: t("levels.intermediate"),
    advanced:     t("levels.advanced"),
  };

  const bodyPhotos = mediaItems.filter((m) => m.category === "body_photo");
  const exams      = mediaItems.filter((m) => m.category === "exam");

  const initials = user?.name
    ? user.name.split(" ").map((n) => n[0]).slice(0, 2).join("").toUpperCase()
    : "?";

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: 26, fontWeight: 700, letterSpacing: "-0.02em", margin: 0 }}>{t("title")}</h1>
        <button
          onClick={handleSignOut}
          style={{ fontSize: 13, color: "var(--text-dim)", background: "none", border: "none", cursor: "pointer" }}
        >
          {t("signOut")}
        </button>
      </header>

      {/* Profile head */}
      <div className="profile-head" style={{ marginBottom: 14 }}>
        <button
          onClick={() => avatarInputRef.current?.click()}
          disabled={uploadingAvatar}
          className="ph-av"
          aria-label={t("tapAvatarHint")}
        >
          {user?.avatar_url?.startsWith("/") ? (
            <img src={`${API_URL}${user.avatar_url}`} alt="Avatar" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          ) : (
            initials
          )}
          {uploadingAvatar && (
            <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,.4)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11 }}>…</div>
          )}
        </button>
        <div style={{ minWidth: 0 }}>
          <b>{user?.name}</b>
          <small>{user?.email}</small>
        </div>
      </div>
      <input ref={avatarInputRef} type="file" accept="image/*" className="hidden" onChange={handleAvatarChange} />
      {avatarError && (
        <p style={{ marginBottom: 12, borderRadius: "var(--r-md)", border: "1px solid var(--hot)", background: "var(--hot-soft)", padding: "10px 14px", fontSize: 13, color: "var(--hot)" }}>{avatarError}</p>
      )}

      {/* Stats */}
      {stats && (
        <div className="mini-stats" style={{ marginBottom: 14 }}>
          <div className="mini-stat">
            <b style={{ color: "var(--primary)" }}>{stats.total_sessions}</b>
            <span>{t("workouts")}</span>
          </div>
          <div className="mini-stat">
            <b style={{ color: "var(--hot)" }}>🔥 {stats.streak}</b>
            <span>{t("streak")}</span>
          </div>
          {stats.best_streak != null && stats.best_streak > 0 ? (
            <div className="mini-stat">
              <b>🏆 {stats.best_streak}</b>
              <span>Melhor sequência</span>
            </div>
          ) : stats.last_activity_at ? (
            <div className="mini-stat">
              <b style={{ fontSize: 16 }}>{new Date(stats.last_activity_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" })}</b>
              <span>Último treino</span>
            </div>
          ) : (
            <div className="mini-stat">
              <b style={{ color: "var(--text-dim)" }}>—</b>
              <span>Sem dados</span>
            </div>
          )}
        </div>
      )}

      {/* DNA de treino */}
      {profile && (
        <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: "16px 18px", marginBottom: 14 }}>
          <p className="eyebrow" style={{ marginBottom: 12 }}>DNA de treino</p>
          <div className="dna">
            {[
              { k: "Objetivo",       v: goalLabels[profile.goal] },
              { k: "Nível",          v: levelLabels[profile.fitness_level] },
              { k: "Dias / semana",  v: profile.training_days_per_week ? `${profile.training_days_per_week}×` : "—" },
              { k: "Peso",           v: profile.weight_kg ? `${profile.weight_kg} kg` : "—" },
              { k: "Altura",         v: profile.height_cm ? `${profile.height_cm} cm` : "—" },
            ].map(({ k, v }) => (
              <div key={k} className="attr">
                <span className="ak">{k}</span>
                <span className="av2"><span className="pip" />{v}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Dados físicos */}
      <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: "16px 18px", marginBottom: 14 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 14 }}>
          <p style={{ fontWeight: 700, margin: 0 }}>{t("physicalData")}</p>
          {!editing && (
            <button onClick={() => setEditing(true)} style={{ fontSize: 13, color: "var(--primary)", background: "none", border: "none", cursor: "pointer", fontWeight: 700 }}>
              {t("edit")}
            </button>
          )}
        </div>

        {!profile ? (
          <p style={{ fontSize: 14, color: "var(--text-muted)" }}>{t("noProfile")}</p>
        ) : editing ? (
          <EditForm
            form={form}
            onChange={(key, val) => setForm((f) => ({ ...f, [key]: val }))}
            onLimitationsChange={(lims) => setForm((f) => ({ ...f, limitations: lims }))}
            error={error}
            saving={saving}
            onSave={handleSave}
            onCancel={() => { setEditing(false); setError(""); }}
            goalLabels={goalLabels}
            levelLabels={levelLabels}
            t={t}
          />
        ) : (
          <dl className="space-y-3">
            <ProfileRow label={t("goal")}   value={goalLabels[profile.goal]} />
            <ProfileRow label={t("level")}  value={levelLabels[profile.fitness_level]} />
            <ProfileRow label={t("age")}    value={`${profile.age} ${t("years")}`} />
            <ProfileRow label={t("weight")} value={`${profile.weight_kg} ${t("kg")}`} />
            <ProfileRow label={t("height")} value={`${profile.height_cm} ${t("cm")}`} />
          </dl>
        )}
      </div>

      {/* Body evolution chart */}
      {!editing && <BodyEvolutionSection history={bodyHistory} />}

      {/* Update plan prompt */}
      {showUpdatePlanPrompt && !editing && (
        <div style={{
          marginBottom: 16, padding: "16px", borderRadius: "var(--r-lg)",
          background: "var(--primary-soft)", border: "1px solid oklch(0.685 var(--accent-c,0.17) var(--accent-h,258)/.3)",
        }}>
          <p style={{ fontWeight: 700, fontSize: 14, margin: "0 0 4px", color: "var(--primary)" }}>
            Perfil atualizado
          </p>
          <p style={{ fontSize: 13, color: "var(--text-dim)", margin: "0 0 12px" }}>
            Seu objetivo ou nível mudou. Deseja gerar um novo plano personalizado?
          </p>
          <div style={{ display: "flex", gap: 8 }}>
            <button
              onClick={handleRegeneratePlan}
              disabled={regenerating}
              style={{
                flex: 1, padding: "11px", borderRadius: "var(--r-md)", border: "none",
                background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
                color: "var(--on-primary)", fontWeight: 700, fontSize: 13,
                cursor: regenerating ? "not-allowed" : "pointer", opacity: regenerating ? 0.7 : 1,
              }}
            >
              {regenerating ? "Gerando plano…" : "Atualizar plano de treino"}
            </button>
            <button
              onClick={() => setShowUpdatePlanPrompt(false)}
              style={{
                padding: "11px 16px", borderRadius: "var(--r-md)",
                border: "1px solid var(--border)", background: "transparent",
                color: "var(--text-dim)", fontSize: 13, cursor: "pointer",
              }}
            >
              Agora não
            </button>
          </div>
        </div>
      )}

      {/* Navegação — list-card */}
      <div className="list-card" style={{ marginBottom: 14 }}>
        <Link href="/profile/detailed" className="li">
          <span className="lic">
            <svg viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
          </span>
          <span className="lt">
            <span style={{ fontWeight: 700 }}>Perfil detalhado</span>
            <span style={{ display: "block", fontSize: 12, color: "var(--text-dim)" }}>IMC, água corporal, exames</span>
          </span>
          <span className="lv">›</span>
        </Link>
        <Link href="/settings" className="li">
          <span className="lic">
            <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/></svg>
          </span>
          <span className="lt">
            <span style={{ fontWeight: 700 }}>Privacidade e comunidade</span>
            <span style={{ display: "block", fontSize: 12, color: "var(--text-dim)" }}>Visibilidade, convites, feed</span>
          </span>
          <span className="lv">›</span>
        </Link>
        <Link href={user?.account_type === "personal_trainer" ? "/personal/dashboard" : "/personal"} className="li">
          <span className="lic">
            <svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
          </span>
          <span className="lt">
            <span style={{ fontWeight: 700 }}>{user?.account_type === "personal_trainer" ? "Painel Personal Trainer" : "Sou Personal Trainer"}</span>
            <span style={{ display: "block", fontSize: 12, color: "var(--text-dim)" }}>
              {user?.account_type === "personal_trainer" ? "Alunos, convites e aderência" : "Gerencie alunos e ganhe comissões"}
            </span>
          </span>
          <span className="lv">›</span>
        </Link>
      </div>

      {/* Fotos e Exames */}
      <div className="mb-4 rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-semibold text-white">{t("photosAndExams")}</h2>
          <button
            onClick={() => mediaInputRef.current?.click()}
            disabled={uploadingMedia}
            className="rounded-full bg-primary-500 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
          >
            {uploadingMedia ? t("sending") : t("addMedia")}
          </button>
        </div>
        <input
          ref={mediaInputRef}
          type="file"
          accept="image/*,application/pdf"
          className="hidden"
          onChange={handleMediaUpload}
        />

        {mediaUploadError && (
          <div className="mb-3 rounded-xl border border-red-800 bg-red-950/40 px-4 py-3 text-sm text-red-400">
            {mediaUploadError}
          </div>
        )}

        {faceBlurredNotice && (
          <div className="mb-3 rounded-xl border border-blue-800 bg-blue-950/40 px-4 py-3 text-sm text-blue-400 flex items-start gap-2">
            <span className="mt-0.5">&#128274;</span>
            <span>Rosto ofuscado por privacidade. A foto foi salva com o rosto pixelado.</span>
          </div>
        )}

        {pendingDataPoints.length > 0 && (
          <div className="mb-4 rounded-xl border border-green-800/50 bg-green-950/30 p-4">
            <p className="mb-3 text-sm font-semibold text-green-400">
              Encontramos dados no exame. O que deseja fazer?
            </p>
            {pendingDataPoints.map((dp) => (
              <div key={dp.id} className="mb-3 rounded-xl border border-slate-700 bg-slate-800 p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-white">
                    {FIELD_LABELS[dp.field_name] ?? dp.field_name}:{" "}
                    <strong>{dp.value}{dp.unit ? ` ${dp.unit}` : ""}</strong>
                  </span>
                  {dp.confidence != null && (
                    <span className="text-xs text-slate-500">
                      {Math.round(dp.confidence * 100)}% confiança
                    </span>
                  )}
                </div>
                {dp.ai_notes && (
                  <p className="mb-2 text-xs text-slate-400">{dp.ai_notes}</p>
                )}
                <div className="flex gap-2">
                  <button
                    onClick={() => handleDataPointAction(dp, "confirm")}
                    disabled={confirmingDp === dp.id}
                    className="flex-1 rounded-full bg-primary-500 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
                  >
                    Atualizar perfil
                  </button>
                  <button
                    onClick={() => handleDataPointAction(dp, "save_advanced")}
                    disabled={confirmingDp === dp.id}
                    className="flex-1 rounded-full border border-slate-700 py-1.5 text-xs font-medium text-slate-400 disabled:opacity-50"
                  >
                    Salvar no histórico
                  </button>
                  <button
                    onClick={() => handleDataPointAction(dp, "ignore")}
                    disabled={confirmingDp === dp.id}
                    className="rounded-full border border-slate-700 px-3 py-1.5 text-xs text-slate-500 disabled:opacity-50"
                  >
                    Ignorar
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        {bodyAnalysis && (
          <div className="mb-4 rounded-xl border border-purple-800/50 bg-purple-950/30 p-4">
            <p className="mb-2 text-sm font-semibold text-purple-400">Observação da foto</p>
            <p className="mb-3 text-sm text-slate-300">{bodyAnalysis.observation}</p>
            <div className="flex gap-2">
              <button
                onClick={async () => {
                  await api.patch(`/api/v1/health_data_points/${bodyAnalysis.id}`, { action_type: "save_advanced" }).catch(() => null);
                  setBodyAnalysis(null);
                }}
                className="flex-1 rounded-full bg-purple-600 py-1.5 text-xs font-semibold text-white"
              >
                Salvar observação
              </button>
              <button
                onClick={async () => {
                  await api.patch(`/api/v1/health_data_points/${bodyAnalysis.id}`, { action_type: "ignore" }).catch(() => null);
                  setBodyAnalysis(null);
                }}
                className="rounded-full border border-slate-700 px-3 py-1.5 text-xs text-slate-500"
              >
                Ignorar
              </button>
            </div>
          </div>
        )}

        {/* Tabs */}
        <div className="mb-4 flex gap-2">
          {(["body_photo", "exam"] as MediaCategory[]).map((tab) => (
            <button
              key={tab}
              onClick={() => setMediaTab(tab)}
              className={`flex-1 rounded-full border py-2 text-xs font-semibold transition ${
                mediaTab === tab
                  ? "border-primary-500 bg-primary-500/12 text-primary-400"
                  : "border-slate-800 text-slate-500"
              }`}
            >
              {tab === "body_photo" ? t("bodyEvolution") : t("exams")}
            </button>
          ))}
        </div>

        {/* Body photos: before/after + history button */}
        {mediaTab === "body_photo" && (
          bodyPhotos.length === 0 ? (
            <p className="text-center text-sm text-gray-400">{t("noPhotos")}</p>
          ) : (
            <>
              <div className="mb-3 rounded-xl border border-primary-500/30 bg-primary-500/10 p-3">
                <p className="mb-2 text-xs font-semibold text-primary-400">{t("beforeVsNow")}</p>
                <div className="grid grid-cols-2 gap-2">
                  {bodyPhotos.length >= 2 ? (
                    <button onClick={() => setLightboxPhoto(bodyPhotos[bodyPhotos.length - 1])} className="text-center">
                      {bodyPhotos[bodyPhotos.length - 1].file_url && (
                        <img
                          src={`${API_URL}${bodyPhotos[bodyPhotos.length - 1].file_url}`}
                          alt="Antes"
                          className="h-32 w-full rounded-lg object-cover"
                        />
                      )}
                      <p className="mt-1 text-xs font-semibold text-slate-400">{t("before")}</p>
                      <p className="text-xs text-slate-500">
                        {new Date(bodyPhotos[bodyPhotos.length - 1].captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
                      </p>
                    </button>
                  ) : (
                    <div className="flex h-32 items-center justify-center rounded-lg bg-slate-800">
                      <p className="px-2 text-center text-xs text-slate-500">Adicione mais fotos para comparar</p>
                    </div>
                  )}
                  <button onClick={() => setLightboxPhoto(bodyPhotos[0])} className="text-center">
                    {bodyPhotos[0].file_url && (
                      <img
                        src={`${API_URL}${bodyPhotos[0].file_url}`}
                        alt="Agora"
                        className="h-32 w-full rounded-lg object-cover"
                      />
                    )}
                    <p className="mt-1 text-xs font-semibold text-slate-400">{t("now")}</p>
                    <p className="text-xs text-gray-400">
                      {new Date(bodyPhotos[0].captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
                    </p>
                  </button>
                </div>
              </div>
              <button
                onClick={() => setPhotoHistoryOpen(true)}
                className="w-full rounded-full border border-primary-500/30 bg-primary-500/10 py-2.5 text-sm font-semibold text-primary-400 transition hover:bg-primary-500/15"
              >
                Histórico de fotos ({bodyPhotos.length})
              </button>
            </>
          )
        )}

        {/* Toggle lista/grade — somente para exames */}
        {mediaTab === "exam" && exams.length > 0 && (
          <div className="mb-3 flex justify-end gap-1">
            <button
              onClick={() => setMediaViewMode("grid")}
              className={`rounded-lg border px-2.5 py-1 text-xs font-semibold ${mediaViewMode === "grid" ? "border-primary-500 bg-primary-500/12 text-primary-400" : "border-slate-800 text-slate-500"}`}
            >
              {t("gridView")}
            </button>
            <button
              onClick={() => setMediaViewMode("list")}
              className={`rounded-lg border px-2.5 py-1 text-xs font-semibold ${mediaViewMode === "list" ? "border-primary-500 bg-primary-500/12 text-primary-400" : "border-slate-800 text-slate-500"}`}
            >
              {t("listView")}
            </button>
          </div>
        )}

        {/* Exames */}
        {mediaTab === "exam" && (
          exams.length === 0 ? (
            <p className="text-center text-sm text-gray-400">{t("noExams")}</p>
          ) : mediaViewMode === "list" ? (
            <div className="space-y-2">
              {exams.map((item) => (
                <div key={item.id} className="flex items-center gap-3 rounded-xl border border-slate-800 bg-slate-800/50 p-3">
                  {item.mime_type === "application/pdf" ? (
                    <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg bg-red-50 text-xl">📄</div>
                  ) : (
                    <>{item.file_url && <img src={`${API_URL}${item.file_url}`} alt="Exame" className="h-12 w-12 flex-shrink-0 rounded-lg object-cover" />}</>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-white">{item.file_name ?? "Arquivo"}</p>
                    <p className="text-xs text-slate-500">
                      {new Date(item.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
                      {item.file_size ? ` · ${(item.file_size / 1024).toFixed(0)} KB` : ""}
                    </p>
                  </div>
                  <button onClick={() => handleDeleteMedia(item.id)} className="flex-shrink-0 text-xs text-red-400 hover:text-red-600">{t("removeMedia")}</button>
                </div>
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-2">
              {exams.map((item) => (
                <div key={item.id} className="relative">
                  {item.mime_type === "application/pdf" ? (
                    <div className="flex h-32 w-full items-center justify-center rounded-lg bg-slate-800 text-3xl">📄</div>
                  ) : (
                    <>{item.file_url && <img src={`${API_URL}${item.file_url}`} alt="Exame" className="h-32 w-full rounded-lg object-cover" />}</>
                  )}
                  <div className="mt-1 flex items-center justify-between">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-xs text-slate-500">
                        {new Date(item.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" })}
                      </p>
                      {item.file_name && <p className="truncate text-xs text-gray-400">{item.file_name}</p>}
                    </div>
                    <button onClick={() => handleDeleteMedia(item.id)} className="ml-1 flex-shrink-0 text-xs text-red-400 hover:text-red-600">✕</button>
                  </div>
                </div>
              ))}
            </div>
          )
        )}
      </div>

      {/* Preferências */}
      <div className="list-card" style={{ marginBottom: 14 }}>
        <p className="eyebrow" style={{ padding: "12px 17px 0" }}>{t("language")}</p>
        <div style={{ display: "flex", gap: 10, padding: "12px 17px" }}>
          {(["pt-BR", "en-US"] as const).map((loc) => (
            <button
              key={loc}
              onClick={() => handleLocaleChange(loc)}
              style={{
                flex: 1, borderRadius: "var(--r-pill)", padding: "10px",
                border: locale === loc ? "1.5px solid var(--primary)" : "1.5px solid var(--border)",
                background: locale === loc ? "var(--primary-soft)" : "var(--surface)",
                color: locale === loc ? "var(--primary)" : "var(--text-muted)",
                fontWeight: 700, fontSize: 13, cursor: "pointer",
              }}
            >
              {loc === "pt-BR" ? "🇧🇷 Português" : "🇺🇸 English"}
            </button>
          ))}
        </div>
        <button className="li" onClick={toggleTheme} style={{ width: "100%", textAlign: "left" }}>
          <span className="lic"><span style={{ fontSize: 18 }}>{theme === "dark" ? "🌙" : "☀️"}</span></span>
          <span className="lt">{theme === "dark" ? "Modo escuro" : "Modo claro"}</span>
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--primary)" }}>{theme === "dark" ? "Usar claro" : "Usar escuro"}</span>
        </button>
      </div>

      {/* Legal */}
      <div className="list-card" style={{ marginBottom: 14 }}>
        <a href="/terms" target="_blank" rel="noopener noreferrer" className="li">
          <span className="lt">Termos de Uso</span><span className="lv">›</span>
        </a>
        <a href="/privacy" target="_blank" rel="noopener noreferrer" className="li">
          <span className="lt">Política de Privacidade</span><span className="lv">›</span>
        </a>
        <a href="mailto:suporte@easyhealth.com.br" className="li">
          <span className="lt">Fale Conosco</span><span className="lv">›</span>
        </a>
      </div>

      {/* Admin */}
      {user?.admin && (
        <Link
          href="/admin"
          style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 14, background: "var(--primary-soft)", border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .3)", borderRadius: "var(--r-lg)", padding: "14px 18px", textDecoration: "none" }}
        >
          <div>
            <p style={{ fontWeight: 700, color: "var(--primary)", margin: 0 }}>Painel Administrativo</p>
            <p style={{ fontSize: 12, color: "var(--text-dim)", margin: 0 }}>Estatísticas da plataforma</p>
          </div>
          <span style={{ color: "var(--primary)", fontSize: 18 }}>→</span>
        </Link>
      )}

      {/* Conta */}
      <div className="list-card">
        <button className="li" onClick={() => setCleanDataOpen(true)} style={{ width: "100%", textAlign: "left" }}>
          <span className="lt">Limpar Meus Dados</span><span className="lv">›</span>
        </button>
        <button className="li danger" onClick={() => setDeleteAccountOpen(true)} style={{ width: "100%", textAlign: "left" }}>
          <span className="lt">Excluir Conta</span><span className="lv" style={{ color: "var(--hot)" }}>›</span>
        </button>
      </div>

      {/* ─── Photo History Bottom Sheet ──────────────────────────────────────── */}
      {photoHistoryOpen && (
        <div
          className="fixed inset-0 z-50 flex items-end bg-black/40"
          onClick={() => setPhotoHistoryOpen(false)}
        >
          <div
            className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-slate-900 px-4 pb-24 pt-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mx-auto mb-1 h-1 w-10 rounded-full bg-slate-700" />
            <div className="mb-4 mt-3 flex items-center justify-between">
              <h3 className="text-base font-bold text-white">
                Histórico de fotos ({bodyPhotos.length})
              </h3>
              <button
                onClick={() => setPhotoHistoryOpen(false)}
                className="flex h-8 w-8 items-center justify-center rounded-full border border-slate-700 text-sm text-slate-400"
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
                    setLightboxPhoto(photo);
                  }}
                  className="text-center"
                >
                  {photo.file_url && (
                    <img
                      src={`${API_URL}${photo.file_url}`}
                      alt="Foto corporal"
                      className="h-28 w-full rounded-xl object-cover"
                    />
                  )}
                  <p className="mt-1 text-xs text-slate-500">
                    {new Date(photo.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" })}
                  </p>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ─── Lightbox ────────────────────────────────────────────────────────── */}
      {lightboxPhoto && (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/90"
          onClick={() => setLightboxPhoto(null)}
        >
          <button
            onClick={() => setLightboxPhoto(null)}
            className="absolute right-4 top-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/20 text-xl text-white"
          >
            ✕
          </button>
          <img
            src={`${API_URL}${lightboxPhoto.file_url}`}
            alt="Visualização"
            className="max-h-[88vh] max-w-[92vw] rounded-xl object-contain"
            onClick={(e) => e.stopPropagation()}
          />
          {lightboxPhoto.captured_at && (
            <p className="absolute bottom-6 text-sm text-white/70">
              {new Date(lightboxPhoto.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
            </p>
          )}
        </div>
      )}

      {/* ─── Modais ──────────────────────────────────────────────────────────── */}
      {deleteAccountOpen && (
        <DeleteAccountModal
          onClose={() => setDeleteAccountOpen(false)}
          onSignOut={signOut}
        />
      )}
      {cleanDataOpen && (
        <CleanDataModal
          onClose={() => setCleanDataOpen(false)}
          onSuccess={() => {
            // Reload media and profile after data cleanup
            Promise.all([
              api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
              api.get<UserMedia[]>("/api/v1/user_media").catch(() => []),
            ]).then(([p, media]) => {
              setProfile(p);
              setMediaItems(media ?? []);
            });
          }}
        />
      )}
    </div>
  );
}

function ProfileRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between py-1">
      <dt className="text-sm text-slate-400">{label}</dt>
      <dd className="text-sm font-medium text-white">{value}</dd>
    </div>
  );
}

const LIMITATION_PRESETS = ["Joelho", "Lombar", "Ombro", "Punho", "Cervical", "Quadril", "Tornozelo"];

function EditForm({
  form,
  onChange,
  onLimitationsChange,
  error,
  saving,
  onSave,
  onCancel,
  goalLabels,
  levelLabels,
  t,
}: {
  form: Partial<HealthProfile>;
  onChange: (key: keyof HealthProfile, val: string | number) => void;
  onLimitationsChange: (lims: string[]) => void;
  error: string;
  saving: boolean;
  onSave: () => void;
  onCancel: () => void;
  goalLabels: Record<Goal, string>;
  levelLabels: Record<FitnessLevel, string>;
  t: ReturnType<typeof useTranslations<"profile">>;
}) {
  const [customLim, setCustomLim] = React.useState("");
  const lims: string[] = Array.isArray(form.limitations) ? form.limitations : [];

  function toggleLimitation(item: string) {
    const updated = lims.includes(item) ? lims.filter((l) => l !== item) : [...lims, item];
    onLimitationsChange(updated);
  }

  function addCustom() {
    const trimmed = customLim.trim();
    if (!trimmed || lims.includes(trimmed)) { setCustomLim(""); return; }
    onLimitationsChange([...lims, trimmed]);
    setCustomLim("");
  }
  return (
    <div className="space-y-4">
      {error && <p className="rounded-xl border border-red-800 bg-red-950/40 px-3 py-2 text-sm text-red-400">{error}</p>}

      <Select
        label={t("goal")}
        value={String(form.goal ?? "")}
        onChange={(v) => onChange("goal", v as Goal)}
        options={(Object.entries(goalLabels) as [Goal, string][]).map(([value, label]) => ({ value, label }))}
      />
      <Select
        label={t("level")}
        value={String(form.fitness_level ?? "")}
        onChange={(v) => onChange("fitness_level", v as FitnessLevel)}
        options={(Object.entries(levelLabels) as [FitnessLevel, string][]).map(([value, label]) => ({ value, label }))}
      />

      {(["age", "weight_kg", "height_cm"] as const).map((key) => (
        <div key={key}>
          <label className="mb-1 block text-sm font-medium text-slate-400">
            {key === "age" ? t("age") : key === "weight_kg" ? t("weightKg") : t("heightCm")}
          </label>
          <input
            type="number"
            value={String(form[key] ?? "")}
            onChange={(e) => onChange(key, Number(e.target.value))}
            className="w-full rounded-xl border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-white focus:border-primary-500 focus:outline-none"
          />
        </div>
      ))}

      {/* BMI inline */}
      {form.weight_kg && form.height_cm && (form.weight_kg as number) > 0 && (form.height_cm as number) > 0 && (() => {
        const bmi = (form.weight_kg as number) / Math.pow((form.height_cm as number) / 100, 2);
        const label = bmi < 18.5 ? "Abaixo do peso" : bmi < 25 ? "Peso normal" : bmi < 30 ? "Sobrepeso" : "Obesidade";
        const color = bmi < 18.5 ? "#60a5fa" : bmi < 25 ? "#4ade80" : bmi < 30 ? "#fb923c" : "#f87171";
        return (
          <div className="flex items-center justify-between rounded-xl border border-slate-700 bg-slate-800/50 px-3 py-2">
            <span className="text-sm text-slate-400">IMC</span>
            <span style={{ fontSize: 14, fontWeight: 700, color }}>
              {bmi.toFixed(1)} — {label}
            </span>
          </div>
        );
      })()}

      {/* Limitations chip editor */}
      <div>
        <label className="mb-2 block text-sm font-medium text-slate-400">Limitações / Lesões</label>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 8 }}>
          {LIMITATION_PRESETS.map((item) => {
            const active = lims.includes(item);
            return (
              <button
                key={item}
                type="button"
                onClick={() => toggleLimitation(item)}
                style={{
                  padding: "5px 12px", borderRadius: "var(--r-pill, 99px)", fontSize: 12, fontWeight: 600,
                  border: active ? "none" : "1px solid var(--border)",
                  background: active ? "var(--primary)" : "var(--surface)",
                  color: active ? "var(--on-primary)" : "var(--text-dim)",
                  cursor: "pointer",
                }}
              >
                {item}
              </button>
            );
          })}
          {lims.filter((l) => !LIMITATION_PRESETS.includes(l)).map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => toggleLimitation(item)}
              style={{
                padding: "5px 12px", borderRadius: "var(--r-pill, 99px)", fontSize: 12, fontWeight: 600,
                border: "none", background: "var(--primary)", color: "var(--on-primary)", cursor: "pointer",
              }}
            >
              {item} ×
            </button>
          ))}
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <input
            type="text"
            value={customLim}
            onChange={(e) => setCustomLim(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), addCustom())}
            placeholder="Adicionar outra..."
            className="flex-1 rounded-xl border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-white focus:border-primary-500 focus:outline-none"
          />
          <button
            type="button"
            onClick={addCustom}
            style={{ padding: "8px 14px", borderRadius: "var(--r-md)", background: "var(--surface)", border: "1px solid var(--border)", fontSize: 12, fontWeight: 600, cursor: "pointer", color: "var(--text)" }}
          >
            +
          </button>
        </div>
      </div>

      <div className="flex gap-2 pt-2">
        <button onClick={onCancel} className="flex-1 rounded-full border border-slate-700 py-2 text-sm text-slate-400">
          {t("cancel")}
        </button>
        <button onClick={onSave} disabled={saving} className="flex-1 rounded-full bg-primary-500 py-2 text-sm font-semibold text-white disabled:opacity-50">
          {saving ? t("saving") : t("save")}
        </button>
      </div>
    </div>
  );
}

function Select({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div>
      <label className="mb-1 block text-sm font-medium text-slate-400">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-xl border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-white focus:border-primary-500 focus:outline-none"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}

type BodyPoint = { field_name: string; value: number; unit: string | null; collected_at: string };

function miniLineSvg(vals: number[], w = 280, h = 60): string {
  if (vals.length < 2) return "";
  const min = Math.min(...vals);
  const max = Math.max(...vals);
  const rng = max - min || 1;
  const pad = 4;
  const pts = vals.map((v, i) => ({
    x: pad + (i / (vals.length - 1)) * (w - pad * 2),
    y: h - pad - ((v - min) / rng) * (h - pad * 2),
  }));
  const d = pts.map((p, i) => `${i ? "L" : "M"}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(" ");
  const last = pts[pts.length - 1];
  return `<svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" fill="none">
    <path d="${d} L${last.x.toFixed(1)} ${h - pad} L${pts[0].x.toFixed(1)} ${h - pad} Z" fill="var(--primary)" fill-opacity="0.12"/>
    <path d="${d}" stroke="var(--primary)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="${last.x.toFixed(1)}" cy="${last.y.toFixed(1)}" r="3.5" fill="var(--primary)"/>
  </svg>`;
}

function BodyEvolutionSection({ history }: { history: BodyPoint[] }) {
  const [view, setView] = React.useState<"weight" | "fat">("weight");
  const weights = history.filter((p) => p.field_name === "weight_kg");
  const bodyFats = history.filter((p) => p.field_name === "body_fat_pct");
  if (weights.length < 2 && bodyFats.length < 2) return null;
  const active = view === "weight" ? weights : bodyFats;
  const vals = active.map((p) => p.value);
  const first = active[0]?.value ?? 0;
  const last = active[active.length - 1]?.value ?? 0;
  const delta = (last - first).toFixed(1);
  const deltaNum = parseFloat(delta);
  const unit = active[0]?.unit ?? (view === "weight" ? "kg" : "%");

  return (
    <div style={{ borderRadius: "var(--r-lg)", background: "var(--surface)", border: "1px solid var(--border)", padding: "16px", marginBottom: 16 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 12 }}>
        <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", color: "var(--text-dim)", textTransform: "uppercase", margin: 0 }}>
          Evolução corporal
        </p>
        {weights.length >= 2 && bodyFats.length >= 2 && (
          <div style={{ display: "flex", gap: 4 }}>
            {(["weight", "fat"] as const).map((v) => (
              <button key={v} onClick={() => setView(v)} style={{
                padding: "3px 10px", borderRadius: "var(--r-pill)", border: "none", fontSize: 11, fontWeight: 600, cursor: "pointer",
                background: view === v ? "var(--primary)" : "var(--bg-2)",
                color: view === v ? "var(--on-primary)" : "var(--text-dim)",
              }}>
                {v === "weight" ? "Peso" : "% Gordura"}
              </button>
            ))}
          </div>
        )}
      </div>

      <div dangerouslySetInnerHTML={{ __html: miniLineSvg(vals) }} style={{ marginBottom: 10 }} />

      <div style={{ display: "flex", gap: 16 }}>
        <div>
          <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "0 0 2px" }}>Início</p>
          <p style={{ fontSize: 15, fontWeight: 700, margin: 0 }}>{first} {unit}</p>
        </div>
        <div>
          <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "0 0 2px" }}>Agora</p>
          <p style={{ fontSize: 15, fontWeight: 700, margin: 0 }}>{last} {unit}</p>
        </div>
        <div>
          <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "0 0 2px" }}>Total</p>
          <p style={{ fontSize: 15, fontWeight: 700, margin: 0, color: deltaNum < 0 ? "var(--good, #4ade80)" : deltaNum > 0 ? "var(--hot, #ef4444)" : "var(--text)" }}>
            {deltaNum > 0 ? "+" : ""}{delta} {unit}
          </p>
        </div>
      </div>
    </div>
  );
}
