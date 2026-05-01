"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { HealthProfile, Goal, FitnessLevel } from "@/shared/types/health-profile";

const GOAL_LABELS: Record<Goal, string> = {
  lose_weight: "Perder peso",
  gain_muscle: "Ganhar músculo",
  maintain:    "Manter peso",
  health:      "Saúde geral",
};

const LEVEL_LABELS: Record<FitnessLevel, string> = {
  beginner:     "Iniciante",
  intermediate: "Intermediário",
  advanced:     "Avançado",
};

type Stats = { total_sessions: number; streak: number };

export default function ProfilePage() {
  const { user, signOut } = useAuth();
  const router = useRouter();

  const [profile, setProfile] = useState<HealthProfile | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<Partial<HealthProfile>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    Promise.all([
      api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
      api.get<Stats>("/api/v1/workout_sessions/stats").catch(() => null),
    ]).then(([p, s]) => {
      setProfile(p);
      setStats(s);
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
      setError(err instanceof Error ? err.message : "Erro ao salvar");
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

  if (loading) return <LoadingScreen />;

  return (
    <div className="min-h-screen px-4 py-6">
      <header className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-bold text-gray-900">Perfil</h1>
        <button onClick={handleSignOut} className="text-sm text-gray-400 hover:text-red-500">
          Sair
        </button>
      </header>

      {/* Usuário */}
      <div className="mb-4 rounded-2xl bg-green-500 px-5 py-6 text-white">
        <p className="text-2xl font-bold">{user?.name}</p>
        <p className="mt-1 text-sm text-green-100">{user?.email}</p>
      </div>

      {/* Stats */}
      {stats && (
        <div className="mb-4 flex gap-3">
          <div className="flex-1 rounded-xl bg-white border border-gray-100 p-4 text-center">
            <p className="text-2xl font-bold text-gray-900">{stats.total_sessions}</p>
            <p className="text-xs text-gray-500">treinos</p>
          </div>
          <div className="flex-1 rounded-xl bg-white border border-gray-100 p-4 text-center">
            <p className="text-2xl font-bold text-orange-500">🔥 {stats.streak}</p>
            <p className="text-xs text-gray-500">dias seguidos</p>
          </div>
        </div>
      )}

      {/* Dados físicos */}
      <div className="rounded-2xl bg-white border border-gray-100 p-5">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-semibold text-gray-900">Dados físicos</h2>
          {!editing && (
            <button onClick={() => setEditing(true)} className="text-sm text-green-600 hover:underline">
              Editar
            </button>
          )}
        </div>

        {!profile ? (
          <p className="text-sm text-gray-400">Perfil não encontrado.</p>
        ) : editing ? (
          <EditForm
            form={form}
            onChange={(key, val) => setForm((f) => ({ ...f, [key]: val }))}
            error={error}
            saving={saving}
            onSave={handleSave}
            onCancel={() => { setEditing(false); setError(""); }}
          />
        ) : (
          <dl className="space-y-3">
            <ProfileRow label="Objetivo"     value={GOAL_LABELS[profile.goal]} />
            <ProfileRow label="Nível"        value={LEVEL_LABELS[profile.fitness_level]} />
            <ProfileRow label="Idade"        value={`${profile.age} anos`} />
            <ProfileRow label="Peso"         value={`${profile.weight_kg} kg`} />
            <ProfileRow label="Altura"       value={`${profile.height_cm} cm`} />
          </dl>
        )}
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
}: {
  form: Partial<HealthProfile>;
  onChange: (key: keyof HealthProfile, val: string | number) => void;
  error: string;
  saving: boolean;
  onSave: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="space-y-4">
      {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

      <Select
        label="Objetivo"
        value={String(form.goal ?? "")}
        onChange={(v) => onChange("goal", v as Goal)}
        options={[
          { value: "lose_weight", label: "Perder peso" },
          { value: "gain_muscle", label: "Ganhar músculo" },
          { value: "maintain",    label: "Manter peso" },
          { value: "health",      label: "Saúde geral" },
        ]}
      />
      <Select
        label="Nível"
        value={String(form.fitness_level ?? "")}
        onChange={(v) => onChange("fitness_level", v as FitnessLevel)}
        options={[
          { value: "beginner",     label: "Iniciante" },
          { value: "intermediate", label: "Intermediário" },
          { value: "advanced",     label: "Avançado" },
        ]}
      />

      {(["age", "weight_kg", "height_cm"] as const).map((key) => (
        <div key={key}>
          <label className="mb-1 block text-sm font-medium text-gray-700">
            {key === "age" ? "Idade" : key === "weight_kg" ? "Peso (kg)" : "Altura (cm)"}
          </label>
          <input
            type="number"
            value={String(form[key] ?? "")}
            onChange={(e) => onChange(key, Number(e.target.value))}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none"
          />
        </div>
      ))}

      <div className="flex gap-2 pt-2">
        <button onClick={onCancel} className="flex-1 rounded-lg border border-gray-200 py-2 text-sm text-gray-600">
          Cancelar
        </button>
        <button onClick={onSave} disabled={saving} className="flex-1 rounded-lg bg-green-500 py-2 text-sm font-semibold text-white disabled:opacity-50">
          {saving ? "Salvando..." : "Salvar"}
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
        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}
