"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { Avatar } from "@/shared/components/ui/avatar";
import { Medal } from "@/shared/components/ui/medal";
import { IconEyeOff } from "@/shared/components/icons";

interface PublicUser {
  id: number;
  display_name: string;
  avatar_url?: string | null;
  public_bio?: string | null;
  account_type: string;
  show_workout_count?: boolean;
  workout_count?: number;
  show_streak?: boolean;
  streak?: number;
}

interface Badge {
  key: string;
  icon: string;
  name: string;
}

export default function CommunityProfilePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [user, setUser] = useState<PublicUser | null>(null);
  const [badges, setBadges] = useState<Badge[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      api.get<PublicUser>(`/api/v1/users/${id}`),
      api.get<{ badges: Badge[] }>(`/api/v1/users/${id}/badges`).catch(() => ({ badges: [] })),
    ]).then(([u, b]) => {
      setUser(u);
      setBadges(b.badges);
    }).finally(() => setLoading(false));
  }, [id]);

  if (loading) {
    return (
      <main style={{ maxWidth: 480, margin: "0 auto", padding: "20px 16px", textAlign: "center" }}>
        <div style={{ padding: "64px 0", color: "var(--text-dim)" }}>Carregando...</div>
      </main>
    );
  }

  if (!user) {
    return (
      <main style={{ maxWidth: 480, margin: "0 auto", padding: "20px 16px", textAlign: "center" }}>
        <p style={{ color: "var(--text-muted)" }}>Perfil não encontrado.</p>
      </main>
    );
  }

  return (
    <main
      style={{
        maxWidth: 480,
        margin: "0 auto",
        padding: "20px 16px",
        paddingBottom: "calc(var(--nav-pb) + 16px)",
      }}
    >
      {/* Back */}
      <button
        onClick={() => router.back()}
        aria-label="Voltar"
        style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, marginBottom: 20, padding: 0 }}
      >
        ←
      </button>

      {/* Profile card */}
      <div
        style={{
          background: "var(--surface)",
          border: "1px solid var(--border)",
          borderRadius: "var(--r-lg)",
          padding: "24px",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 12,
          marginBottom: 20,
          textAlign: "center",
        }}
      >
        <Avatar name={user.display_name} avatarUrl={user.avatar_url} size={72} />

        <div>
          <h1 className="h-md" style={{ margin: 0 }}>{user.display_name}</h1>
          {user.account_type === "personal_trainer" && (
            <span
              style={{
                display: "inline-block",
                marginTop: 4,
                padding: "2px 10px",
                borderRadius: "var(--r-pill)",
                background: "var(--primary-soft)",
                color: "var(--primary)",
                fontSize: 11,
                fontWeight: 700,
              }}
            >
              Personal Trainer
            </span>
          )}
          {user.public_bio && (
            <p style={{ margin: "8px 0 0", fontSize: 13, color: "var(--text-muted)", lineHeight: 1.5 }}>
              {user.public_bio}
            </p>
          )}
        </div>

        {/* Stats */}
        <div style={{ display: "flex", gap: 24 }}>
          {user.show_workout_count && user.workout_count != null && (
            <div style={{ textAlign: "center" }}>
              <p className="num" style={{ fontSize: 22, color: "var(--text)", margin: 0 }}>{user.workout_count}</p>
              <p style={{ fontSize: 11, color: "var(--text-dim)", margin: 0 }}>treinos</p>
            </div>
          )}
          {user.show_streak && user.streak != null && (
            <div style={{ textAlign: "center" }}>
              <p className="num" style={{ fontSize: 22, color: "var(--hot)", margin: 0 }}>🔥 {user.streak}</p>
              <p style={{ fontSize: 11, color: "var(--text-dim)", margin: 0 }}>dias</p>
            </div>
          )}
        </div>
      </div>

      {/* Privacy note */}
      <div
        style={{
          display: "flex",
          gap: 8,
          padding: "10px 14px",
          background: "var(--surface-2)",
          borderRadius: "var(--r-sm)",
          marginBottom: 20,
        }}
      >
        <IconEyeOff className="w-4 h-4" style={{ flexShrink: 0, color: "var(--text-dim)" }} />
        <p style={{ margin: 0, fontSize: 12, color: "var(--text-muted)" }}>
          Exibindo apenas as informações que esta pessoa escolheu compartilhar.
        </p>
      </div>

      {/* Badges */}
      {badges.length > 0 && (
        <section>
          <p className="eyebrow" style={{ marginBottom: 12 }}>Conquistas</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
            {badges.map((b) => (
              <Medal key={b.key} icon={b.icon} name={b.name} earned />
            ))}
          </div>
        </section>
      )}
    </main>
  );
}
