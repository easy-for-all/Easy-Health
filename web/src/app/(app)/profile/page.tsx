"use client";

import { useEffect, useRef, useState, useTransition } from "react";
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
    ]).then(([p, s, media]) => {
      setProfile(p);
      setStats(s);
      setMediaItems(media ?? []);
      if (p) setForm({ age: p.age, weight_kg: p.weight_kg, height_cm: p.height_cm, goal: p.goal, fitness_level: p.fitness_level });
    }).finally(() => setLoading(false));
  }, []);

  async function handleSave() {
    setError("");
    setSaving(true);
    try {
      const updated = profile
        ? await api.patch<HealthProfile>("/api/v1/health_profile", form)
        : await api.post<HealthProfile>("/api/v1/health_profile", form);
      setProfile(updated);
      setEditing(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : t("saveError"));
    } finally {
      setSaving(false);
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
    <div className="min-h-screen px-4 py-6 pb-28" style={{ background: "#0a0f1e" }}>
      <header className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-bold text-white">{t("title")}</h1>
        <button onClick={handleSignOut} className="text-sm text-slate-500 hover:text-red-400">
          {t("signOut")}
        </button>
      </header>

      {/* Usuário + Avatar */}
      <div className="mb-4 rounded-2xl bg-primary-500 px-5 py-6 text-white">
        <div className="flex items-center gap-4">
          <button
            onClick={() => avatarInputRef.current?.click()}
            disabled={uploadingAvatar}
            className="relative flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full bg-primary-400 text-xl font-bold text-white hover:bg-primary-300 disabled:opacity-60"
          >
            {user?.avatar_url?.startsWith("/") ? (
              <img src={`${API_URL}${user.avatar_url}`} alt="Avatar" className="h-full w-full object-cover" />
            ) : (
              initials
            )}
            {uploadingAvatar && (
              <div className="absolute inset-0 flex items-center justify-center bg-black/40 text-xs">...</div>
            )}
          </button>
          <div className="min-w-0">
            <p className="text-2xl font-bold">{user?.name}</p>
            <p className="mt-1 text-sm text-primary-100">{user?.email}</p>
            <p className="mt-1 text-xs text-primary-200">{t("tapAvatarHint")}</p>
          </div>
        </div>
      </div>
      <input ref={avatarInputRef} type="file" accept="image/*" capture="user" className="hidden" onChange={handleAvatarChange} />
      {avatarError && (
        <p className="mb-3 rounded-xl border border-red-800 bg-red-950/40 px-4 py-2 text-sm text-red-400">{avatarError}</p>
      )}

      {/* Stats */}
      {stats && (
        <div className="mb-4 space-y-3">
          <div className="flex gap-3">
            <div className="flex-1 rounded-xl border border-slate-800 bg-slate-900 p-4 text-center">
              <p className="text-2xl font-bold text-white">{stats.total_sessions}</p>
              <p className="text-xs text-slate-400">{t("workouts")}</p>
            </div>
            <div className="flex-1 rounded-xl border border-slate-800 bg-slate-900 p-4 text-center">
              <p className="text-2xl font-bold text-orange-400">🔥 {stats.streak}</p>
              <p className="text-xs text-slate-400">{t("streak")}</p>
            </div>
          </div>
          {(stats.best_streak != null || stats.last_activity_at) && (
            <div className="rounded-xl border border-orange-900/50 bg-orange-950/30 p-4">
              <div className="flex items-center justify-between">
                {stats.best_streak != null && stats.best_streak > 0 && (
                  <div className="text-center">
                    <p className="text-lg font-bold text-orange-400">🏆 {stats.best_streak}</p>
                    <p className="text-xs text-orange-500/70">Melhor sequência</p>
                  </div>
                )}
                {stats.last_activity_at && (
                  <div className="text-center">
                    <p className="text-sm font-semibold text-slate-300">
                      {new Date(stats.last_activity_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" })}
                    </p>
                    <p className="text-xs text-slate-500">Último treino</p>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Dados físicos */}
      <div className="mb-4 rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-semibold text-white">{t("physicalData")}</h2>
          {!editing && (
            <button onClick={() => setEditing(true)} className="text-sm text-primary-400 hover:underline">
              {t("edit")}
            </button>
          )}
        </div>

        {!profile ? (
          <p className="text-sm text-slate-500">{t("noProfile")}</p>
        ) : editing ? (
          <EditForm
            form={form}
            onChange={(key, val) => setForm((f) => ({ ...f, [key]: val }))}
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

      {/* CTA Perfil Detalhado */}
      <Link
        href="/profile/detailed"
        className="mb-4 flex items-center justify-between rounded-2xl border border-primary-500/30 bg-primary-500/10 px-5 py-4 transition hover:bg-primary-500/15"
      >
        <div>
          <p className="font-semibold text-primary-400">Ver perfil detalhado</p>
          <p className="text-xs text-primary-500/70">Análises, exames e evolução corporal</p>
        </div>
        <span className="text-primary-400 text-lg">→</span>
      </Link>

      {/* Privacidade e comunidade */}
      <Link
        href="/settings"
        className="mb-4 flex items-center justify-between rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4 transition hover:bg-slate-800"
      >
        <div>
          <p className="font-semibold text-white">Privacidade e comunidade</p>
          <p className="text-xs text-gray-400">Visibilidade, código de indicação, feed</p>
        </div>
        <span className="text-gray-400 text-lg">→</span>
      </Link>

      {/* Personal Trainer / Permissões */}
      {user?.account_type === "personal_trainer" ? (
        <Link
          href="/personal/dashboard"
          className="mb-4 flex items-center justify-between rounded-2xl border border-blue-800/40 bg-blue-900/20 px-5 py-4 transition hover:bg-blue-900/30"
        >
          <div>
            <p className="font-semibold text-blue-300">Painel do Personal Trainer</p>
            <p className="text-xs text-blue-400/70">Alunos, convites e aderência</p>
          </div>
          <span className="text-blue-400 text-lg">→</span>
        </Link>
      ) : (
        <Link
          href="/personal"
          className="mb-4 flex items-center justify-between rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4 transition hover:bg-slate-800"
        >
          <div>
            <p className="font-semibold text-white">Sou Personal Trainer</p>
            <p className="text-xs text-gray-400">Gerencie alunos e ganhe comissões</p>
          </div>
          <span className="text-gray-400 text-lg">→</span>
        </Link>
      )}

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
          capture={mediaTab === "body_photo" ? "environment" : undefined}
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

      {/* Idioma */}
      <div className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <h2 className="mb-4 font-semibold text-white">{t("language")}</h2>
        <div className="flex gap-3">
          <button
            onClick={() => handleLocaleChange("pt-BR")}
            className={`flex flex-1 items-center justify-center gap-2 rounded-full border py-3 text-sm font-semibold transition ${
              locale === "pt-BR"
                ? "border-primary-500 bg-primary-500/12 text-primary-400"
                : "border-slate-800 text-slate-500 hover:border-slate-600"
            }`}
          >
            🇧🇷 Português
          </button>
          <button
            onClick={() => handleLocaleChange("en-US")}
            className={`flex flex-1 items-center justify-center gap-2 rounded-full border py-3 text-sm font-semibold transition ${
              locale === "en-US"
                ? "border-primary-500 bg-primary-500/12 text-primary-400"
                : "border-slate-800 text-slate-500 hover:border-slate-600"
            }`}
          >
            🇺🇸 English
          </button>
        </div>
      </div>

      {/* Aparência */}
      <div className="mt-4 rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <h2 className="mb-4 font-semibold text-white">Aparência</h2>
        <button
          onClick={toggleTheme}
          className="flex w-full items-center justify-between rounded-xl border border-slate-800 px-4 py-3 hover:bg-slate-800"
        >
          <div className="flex items-center gap-3">
            <span className="text-xl">{theme === "dark" ? "🌙" : "☀️"}</span>
            <span className="text-sm text-slate-400">
              {theme === "dark" ? "Modo escuro ativo" : "Modo claro ativo"}
            </span>
          </div>
          <span className="text-xs text-primary-400 font-semibold">
            {theme === "dark" ? "Usar claro" : "Usar escuro"}
          </span>
        </button>
      </div>

      {/* Legal */}
      <div className="mt-4 rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <h2 className="mb-4 font-semibold text-white">Legal</h2>
        <div className="flex flex-col gap-2">
          <a
            href="/terms"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-between rounded-xl border border-slate-800 px-4 py-3 text-sm text-slate-400 hover:bg-slate-800"
          >
            <span>Termos de Uso</span>
            <span className="text-slate-600">›</span>
          </a>
          <a
            href="/privacy"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-between rounded-xl border border-slate-800 px-4 py-3 text-sm text-slate-400 hover:bg-slate-800"
          >
            <span>Política de Privacidade</span>
            <span className="text-slate-600">›</span>
          </a>
          <a
            href="mailto:suporte@easyhealth.com.br"
            className="flex items-center justify-between rounded-xl border border-slate-800 px-4 py-3 text-sm text-slate-400 hover:bg-slate-800"
          >
            <span>Fale Conosco</span>
            <span className="text-slate-600">›</span>
          </a>
        </div>
      </div>

      {/* Admin */}
      {user?.admin && (
        <Link
          href="/admin"
          className="mt-4 flex items-center justify-between rounded-2xl border border-primary-500/30 bg-primary-500/10 px-5 py-4 transition hover:bg-primary-500/15"
        >
          <div>
            <p className="font-semibold text-primary-400">Painel Administrativo</p>
            <p className="text-xs text-primary-500/70">Estatísticas da plataforma</p>
          </div>
          <span className="text-lg text-primary-400">→</span>
        </Link>
      )}

      {/* Conta */}
      <div className="mt-4 rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <h2 className="mb-4 font-semibold text-white">Conta</h2>
        <div className="flex flex-col gap-2">
          <button
            onClick={() => setCleanDataOpen(true)}
            className="flex items-center justify-between rounded-xl border border-slate-800 px-4 py-3 text-sm text-slate-400 hover:bg-slate-800"
          >
            <span>Limpar Meus Dados</span>
            <span className="text-slate-600">›</span>
          </button>
          <button
            onClick={() => setDeleteAccountOpen(true)}
            className="flex items-center justify-between rounded-xl border border-red-900/50 px-4 py-3 text-sm text-red-400 hover:bg-red-950/30"
          >
            <span>Excluir Conta</span>
            <span className="text-red-700">›</span>
          </button>
        </div>
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

function EditForm({
  form,
  onChange,
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
  error: string;
  saving: boolean;
  onSave: () => void;
  onCancel: () => void;
  goalLabels: Record<Goal, string>;
  levelLabels: Record<FitnessLevel, string>;
  t: ReturnType<typeof useTranslations<"profile">>;
}) {
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
