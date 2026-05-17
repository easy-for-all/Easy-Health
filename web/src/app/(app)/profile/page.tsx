"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations, useLocale } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { compressImage } from "@/shared/lib/image";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { setLocale } from "@/app/actions";
import type { HealthProfile, Goal, FitnessLevel } from "@/shared/types/health-profile";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

type Stats = { total_sessions: number; streak: number };
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

export default function ProfilePage() {
  const { user, signOut, updateUser } = useAuth();
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

  const avatarInputRef = useRef<HTMLInputElement>(null);
  const mediaInputRef = useRef<HTMLInputElement>(null);

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
      const updated = await api.patch<HealthProfile>("/api/v1/health_profile", form);
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
  const currentTabItems = mediaTab === "body_photo" ? bodyPhotos : exams;

  const initials = user?.name
    ? user.name.split(" ").map((n) => n[0]).slice(0, 2).join("").toUpperCase()
    : "?";

  return (
    <div className="min-h-screen px-4 py-6 pb-28">
      <header className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-bold text-gray-900">{t("title")}</h1>
        <button onClick={handleSignOut} className="text-sm text-gray-400 hover:text-red-500">
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
            {user?.avatar_url ? (
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
        <p className="mb-3 rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{avatarError}</p>
      )}

      {/* Stats */}
      {stats && (
        <div className="mb-4 flex gap-3">
          <div className="flex-1 rounded-xl border border-gray-100 bg-white p-4 text-center">
            <p className="text-2xl font-bold text-gray-900">{stats.total_sessions}</p>
            <p className="text-xs text-gray-500">{t("workouts")}</p>
          </div>
          <div className="flex-1 rounded-xl border border-gray-100 bg-white p-4 text-center">
            <p className="text-2xl font-bold text-orange-500">🔥 {stats.streak}</p>
            <p className="text-xs text-gray-500">{t("streak")}</p>
          </div>
        </div>
      )}

      {/* Dados físicos */}
      <div className="mb-4 rounded-2xl border border-gray-100 bg-white p-5">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-semibold text-gray-900">{t("physicalData")}</h2>
          {!editing && (
            <button onClick={() => setEditing(true)} className="text-sm text-primary-600 hover:underline">
              {t("edit")}
            </button>
          )}
        </div>

        {!profile ? (
          <p className="text-sm text-gray-400">{t("noProfile")}</p>
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

      {/* Fotos e Exames */}
      <div className="mb-4 rounded-2xl border border-gray-100 bg-white p-5">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-semibold text-gray-900">{t("photosAndExams")}</h2>
          <button
            onClick={() => mediaInputRef.current?.click()}
            disabled={uploadingMedia}
            className="rounded-lg bg-primary-500 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
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
          <div className="mb-3 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
            {mediaUploadError}
          </div>
        )}

        {faceBlurredNotice && (
          <div className="mb-3 rounded-lg bg-blue-50 px-4 py-3 text-sm text-blue-700 flex items-start gap-2">
            <span className="mt-0.5">🔒</span>
            <span>Rosto ofuscado por privacidade. A foto foi salva com o rosto pixelado.</span>
          </div>
        )}

        {/* Tabs */}
        <div className="mb-4 flex gap-2">
          {(["body_photo", "exam"] as MediaCategory[]).map((tab) => (
            <button
              key={tab}
              onClick={() => setMediaTab(tab)}
              className={`flex-1 rounded-lg border py-2 text-xs font-semibold transition ${
                mediaTab === tab
                  ? "border-primary-500 bg-primary-50 text-primary-700"
                  : "border-gray-200 text-gray-500"
              }`}
            >
              {tab === "body_photo" ? t("bodyEvolution") : t("exams")}
            </button>
          ))}
        </div>

        {/* Before/After card — only for body_photo with 2+ photos */}
        {mediaTab === "body_photo" && bodyPhotos.length >= 2 && (
          <div className="mb-4 rounded-xl border border-primary-100 bg-primary-50 p-3">
            <p className="mb-2 text-xs font-semibold text-primary-600">{t("beforeVsNow")}</p>
            <div className="grid grid-cols-2 gap-2">
              {[bodyPhotos[bodyPhotos.length - 1], bodyPhotos[0]].map((photo, idx) => (
                <div key={photo.id} className="text-center">
                  <img
                    src={`${API_URL}${photo.file_url}`}
                    alt={idx === 0 ? "Antes" : "Agora"}
                    className="h-32 w-full rounded-lg object-cover"
                  />
                  <p className="mt-1 text-xs text-gray-500">{idx === 0 ? t("before") : t("now")}</p>
                  <p className="text-xs text-gray-400">
                    {new Date(photo.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Toggle lista/grade — somente para exames */}
        {mediaTab === "exam" && currentTabItems.length > 0 && (
          <div className="mb-3 flex justify-end gap-1">
            <button
              onClick={() => setMediaViewMode("grid")}
              className={`rounded-lg border px-2.5 py-1 text-xs font-semibold ${mediaViewMode === "grid" ? "border-primary-500 bg-primary-50 text-primary-700" : "border-gray-200 text-gray-500"}`}
            >
              {t("gridView")}
            </button>
            <button
              onClick={() => setMediaViewMode("list")}
              className={`rounded-lg border px-2.5 py-1 text-xs font-semibold ${mediaViewMode === "list" ? "border-primary-500 bg-primary-50 text-primary-700" : "border-gray-200 text-gray-500"}`}
            >
              {t("listView")}
            </button>
          </div>
        )}

        {/* Fotos e exames */}
        {currentTabItems.length === 0 ? (
          <p className="text-center text-sm text-gray-400">
            {mediaTab === "body_photo" ? t("noPhotos") : t("noExams")}
          </p>
        ) : mediaTab === "exam" && mediaViewMode === "list" ? (
          <div className="space-y-2">
            {currentTabItems.map((item) => (
              <div key={item.id} className="flex items-center gap-3 rounded-xl border border-gray-100 bg-white p-3">
                {item.mime_type === "application/pdf" ? (
                  <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg bg-red-50 text-xl">📄</div>
                ) : (
                  <img src={`${API_URL}${item.file_url}`} alt="Exame" className="h-12 w-12 flex-shrink-0 rounded-lg object-cover" />
                )}
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium text-gray-900">{item.file_name ?? "Arquivo"}</p>
                  <p className="text-xs text-gray-400">
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
            {currentTabItems.map((item) => (
              <div key={item.id} className="relative">
                {item.mime_type === "application/pdf" ? (
                  <div className="flex h-32 w-full items-center justify-center rounded-lg bg-gray-100 text-3xl">📄</div>
                ) : (
                  <img src={`${API_URL}${item.file_url}`} alt="Foto" className="h-32 w-full rounded-lg object-cover" />
                )}
                <div className="mt-1 flex items-center justify-between">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-xs text-gray-500">
                      {new Date(item.captured_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" })}
                    </p>
                    {item.file_name && <p className="truncate text-xs text-gray-400">{item.file_name}</p>}
                  </div>
                  <button onClick={() => handleDeleteMedia(item.id)} className="ml-1 flex-shrink-0 text-xs text-red-400 hover:text-red-600">✕</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Idioma */}
      <div className="rounded-2xl border border-gray-100 bg-white p-5">
        <h2 className="mb-4 font-semibold text-gray-900">{t("language")}</h2>
        <div className="flex gap-3">
          <button
            onClick={() => handleLocaleChange("pt-BR")}
            className={`flex flex-1 items-center justify-center gap-2 rounded-xl border py-3 text-sm font-semibold transition ${
              locale === "pt-BR"
                ? "border-primary-500 bg-primary-50 text-primary-700"
                : "border-gray-200 text-gray-500 hover:bg-gray-50"
            }`}
          >
            🇧🇷 Português
          </button>
          <button
            onClick={() => handleLocaleChange("en-US")}
            className={`flex flex-1 items-center justify-center gap-2 rounded-xl border py-3 text-sm font-semibold transition ${
              locale === "en-US"
                ? "border-primary-500 bg-primary-50 text-primary-700"
                : "border-gray-200 text-gray-500 hover:bg-gray-50"
            }`}
          >
            🇺🇸 English
          </button>
        </div>
      </div>

      {/* Legal */}
      <div className="mt-4 rounded-2xl border border-gray-100 bg-white p-5">
        <h2 className="mb-4 font-semibold text-gray-900">Legal</h2>
        <div className="flex flex-col gap-2">
          <a
            href="/terms"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-between rounded-xl border border-gray-100 px-4 py-3 text-sm text-gray-600 hover:bg-gray-50"
          >
            <span>Termos de Uso</span>
            <span className="text-gray-300">›</span>
          </a>
          <a
            href="/privacy"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-between rounded-xl border border-gray-100 px-4 py-3 text-sm text-gray-600 hover:bg-gray-50"
          >
            <span>Política de Privacidade</span>
            <span className="text-gray-300">›</span>
          </a>
        </div>
      </div>
    </div>
  );
}

function ProfileRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between py-1">
      <dt className="text-sm text-gray-500">{label}</dt>
      <dd className="text-sm font-medium text-gray-900">{value}</dd>
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
      {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

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
          <label className="mb-1 block text-sm font-medium text-gray-700">
            {key === "age" ? t("age") : key === "weight_kg" ? t("weightKg") : t("heightCm")}
          </label>
          <input
            type="number"
            value={String(form[key] ?? "")}
            onChange={(e) => onChange(key, Number(e.target.value))}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-primary-500 focus:outline-none"
          />
        </div>
      ))}

      <div className="flex gap-2 pt-2">
        <button onClick={onCancel} className="flex-1 rounded-lg border border-gray-200 py-2 text-sm text-gray-600">
          {t("cancel")}
        </button>
        <button onClick={onSave} disabled={saving} className="flex-1 rounded-lg bg-primary-500 py-2 text-sm font-semibold text-white disabled:opacity-50">
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
      <label className="mb-1 block text-sm font-medium text-gray-700">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-primary-500 focus:outline-none"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}
