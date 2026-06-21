"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { ToggleRow } from "@/shared/components/ui/toggle-row";
import { IconLock } from "@/shared/components/icons";

type Visibility = "private" | "public_limited" | "public";

interface PrivacyData {
  profile_visibility: Visibility;
  community_enabled: boolean;
}

interface PublicProfileData {
  public_profile: {
    display_name?: string;
    avatar_visible: boolean;
    show_workout_count: boolean;
    show_streak: boolean;
    show_badges: boolean;
    show_progress_photos?: boolean;
  };
}

const VISIBILITY_OPTIONS: { value: Visibility; label: string; hint: string }[] = [
  {
    value: "private",
    label: "Privado",
    hint: "Ninguém vê seu perfil ou treinos na Comunidade.",
  },
  {
    value: "public_limited",
    label: "Limitado",
    hint: "Apenas as informações que você escolher ficam visíveis.",
  },
  {
    value: "public",
    label: "Público",
    hint: "Seu perfil aparece no feed e pode ser encontrado por outros.",
  },
];

function VisibilityHint({ visibility }: { visibility: Visibility }) {
  const opt = VISIBILITY_OPTIONS.find((o) => o.value === visibility);
  if (!opt) return null;
  return (
    <div
      style={{
        padding: "10px 14px",
        background: "var(--surface-2)",
        borderRadius: "var(--r-sm)",
        marginTop: 8,
        fontSize: 13,
        color: "var(--text-muted)",
        lineHeight: 1.5,
      }}
    >
      {opt.hint}
    </div>
  );
}

export default function CommunityPrivacyPage() {
  const router = useRouter();
  const [visibility, setVisibility]     = useState<Visibility>("private");
  const [communityOn, setCommunityOn]   = useState(false);
  const [avatarOn, setAvatarOn]         = useState(false);
  const [workoutCount, setWorkoutCount] = useState(true);
  const [streakOn, setStreakOn]         = useState(true);
  const [badgesOn, setBadgesOn]         = useState(false);
  const [photosOn, setPhotosOn]         = useState(false);
  const [saving, setSaving]             = useState(false);
  const [saved, setSaved]               = useState(false);

  const locked = visibility === "private";

  useEffect(() => {
    Promise.all([
      api.get<PrivacyData>("/api/v1/privacy_settings"),
      api.get<PublicProfileData>("/api/v1/public_profile"),
    ]).then(([priv, pub]) => {
      setVisibility(priv.profile_visibility ?? "private");
      setCommunityOn(priv.community_enabled ?? false);
      setAvatarOn(pub.public_profile.avatar_visible);
      setWorkoutCount(pub.public_profile.show_workout_count);
      setStreakOn(pub.public_profile.show_streak);
      setBadgesOn(pub.public_profile.show_badges);
      setPhotosOn(pub.public_profile.show_progress_photos ?? false);
    }).catch(() => {});
  }, []);

  const save = useCallback(async () => {
    setSaving(true);
    try {
      await Promise.all([
        api.patch("/api/v1/privacy_settings", {
          profile_visibility: visibility,
          community_enabled: communityOn && !locked,
        }),
        api.patch("/api/v1/public_profile", {
          avatar_visible: avatarOn,
          show_workout_count: workoutCount,
          show_streak: streakOn,
          show_badges: badgesOn,
          show_progress_photos: photosOn,
        }),
      ]);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } finally {
      setSaving(false);
    }
  }, [visibility, communityOn, locked, avatarOn, workoutCount, streakOn, badgesOn, photosOn]);

  return (
    <main
      style={{
        maxWidth: 480,
        margin: "0 auto",
        padding: "20px 16px",
        paddingBottom: "calc(var(--nav-pb) + 80px)",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 24 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
        >
          ←
        </button>
        <h1 className="h-lg" style={{ margin: 0 }}>Privacidade e comunidade</h1>
      </div>

      {/* Visibilidade */}
      <section
        style={{
          background: "var(--surface)",
          border: "1px solid var(--border)",
          borderRadius: "var(--r-lg)",
          padding: "16px",
          marginBottom: 16,
        }}
      >
        <p className="eyebrow" style={{ marginBottom: 14 }}>Visibilidade do perfil</p>

        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {VISIBILITY_OPTIONS.map((opt) => (
            <label
              key={opt.value}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                padding: "10px 12px",
                borderRadius: "var(--r-sm)",
                border: `1.5px solid ${visibility === opt.value ? "var(--primary)" : "var(--border)"}`,
                background: visibility === opt.value ? "var(--primary-soft)" : "transparent",
                cursor: "pointer",
                transition: "all .18s",
              }}
            >
              <input
                type="radio"
                name="visibility"
                value={opt.value}
                checked={visibility === opt.value}
                onChange={() => setVisibility(opt.value)}
                style={{ accentColor: "var(--primary)", width: 16, height: 16 }}
              />
              <span style={{ fontWeight: 600, fontSize: 14, color: "var(--text)" }}>{opt.label}</span>
            </label>
          ))}
        </div>

        <VisibilityHint visibility={visibility} />
      </section>

      {/* Controles granulares */}
      <section
        style={{
          background: "var(--surface)",
          border: `1px solid ${locked ? "var(--border)" : "var(--border)"}`,
          borderRadius: "var(--r-lg)",
          padding: "16px",
          marginBottom: 16,
          position: "relative",
          opacity: locked ? 0.55 : 1,
          transition: "opacity .2s",
        }}
      >
        {locked && (
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 6,
              marginBottom: 12,
              color: "var(--text-dim)",
              fontSize: 12,
              fontWeight: 600,
            }}
          >
            <IconLock className="w-4 h-4" />
            Disponível nos modos Limitado e Público
          </div>
        )}

        <p className="eyebrow" style={{ marginBottom: 4 }}>O que compartilhar</p>

        <div style={{ borderTop: "1px solid var(--hairline)", marginTop: 8 }}>
          <ToggleRow
            label="Participar do feed Comunidade"
            hint="Seus treinos aparecem para outros usuários"
            checked={communityOn && !locked}
            onChange={setCommunityOn}
            locked={locked}
          />
          <ToggleRow
            label="Foto do perfil"
            hint="Exibir sua foto no feed e no perfil público"
            checked={avatarOn && !locked}
            onChange={setAvatarOn}
            locked={locked}
          />
          <ToggleRow
            label="Número de treinos"
            hint="Contador de treinos realizados"
            checked={workoutCount && !locked}
            onChange={setWorkoutCount}
            locked={locked}
          />
          <ToggleRow
            label="Sequência de dias"
            hint="Quantos dias consecutivos você treina"
            checked={streakOn && !locked}
            onChange={setStreakOn}
            locked={locked}
          />
          <ToggleRow
            label="Conquistas"
            hint="Badges que você ganhou no app"
            checked={badgesOn && !locked}
            onChange={setBadgesOn}
            locked={locked}
          />
          <ToggleRow
            label="Fotos de evolução"
            hint="Fotos de progresso corporal — desligado por padrão"
            checked={photosOn && !locked}
            onChange={setPhotosOn}
            locked={locked}
          />
        </div>

        <div
          style={{
            marginTop: 12,
            padding: "10px 12px",
            background: "var(--surface-2)",
            borderRadius: "var(--r-sm)",
            fontSize: 12,
            color: "var(--text-dim)",
          }}
        >
          🔒 Peso, exames, bioimpedância e e-mail nunca são exibidos na Comunidade.
        </div>
      </section>

      {/* Salvar */}
      <button
        onClick={save}
        disabled={saving}
        style={{
          width: "100%",
          padding: "14px",
          borderRadius: "var(--r-lg)",
          background: saved ? "var(--good)" : "var(--primary)",
          color: "var(--on-primary)",
          border: "none",
          fontSize: 15,
          fontWeight: 700,
          cursor: saving ? "not-allowed" : "pointer",
          opacity: saving ? 0.7 : 1,
          transition: "background .25s, opacity .2s",
        }}
      >
        {saved ? "✓ Salvo!" : saving ? "Salvando..." : "Salvar preferências"}
      </button>
    </main>
  );
}
