"use client";

import { useState, useEffect } from "react";
import { api } from "@/shared/lib/api";
import { Medal } from "@/shared/components/ui/medal";
import { useRouter } from "next/navigation";

interface Badge {
  key: string;
  icon: string;
  name: string;
  desc: string;
  earned: boolean;
  progress?: number;
}

export default function CommunityBadgesPage() {
  const router = useRouter();
  const [badges, setBadges] = useState<Badge[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get<{ badges: Badge[] }>("/api/v1/badges")
      .then((d) => setBadges(d.badges))
      .finally(() => setLoading(false));
  }, []);

  const earned = badges.filter((b) => b.earned);
  const locked = badges.filter((b) => !b.earned);

  return (
    <main
      style={{
        maxWidth: 480,
        margin: "0 auto",
        padding: "20px 16px",
        paddingBottom: "calc(var(--nav-pb) + 16px)",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 20 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{
            background: "none",
            border: "none",
            color: "var(--text-muted)",
            cursor: "pointer",
            fontSize: 22,
            padding: 0,
            lineHeight: 1,
          }}
        >
          ←
        </button>
        <h1 className="h-lg" style={{ margin: 0 }}>Conquistas</h1>
      </div>

      {loading && (
        <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text-dim)" }}>
          Carregando...
        </div>
      )}

      {!loading && earned.length > 0 && (
        <section style={{ marginBottom: 28 }}>
          <p className="eyebrow" style={{ marginBottom: 12 }}>Conquistadas ({earned.length})</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
            {earned.map((b) => (
              <Medal key={b.key} icon={b.icon} name={b.name} desc={b.desc} earned />
            ))}
          </div>
        </section>
      )}

      {!loading && locked.length > 0 && (
        <section>
          <p className="eyebrow" style={{ marginBottom: 12 }}>Em progresso ({locked.length})</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
            {locked.map((b) => (
              <Medal key={b.key} icon={b.icon} name={b.name} desc={b.desc} earned={false} progress={b.progress} />
            ))}
          </div>
        </section>
      )}

      {!loading && badges.length === 0 && (
        <div style={{ textAlign: "center", padding: "48px 0" }}>
          <span style={{ fontSize: 40 }}>🏅</span>
          <p className="h-sm" style={{ margin: "12px 0 6px" }}>Nenhuma conquista ainda</p>
          <p style={{ fontSize: 13, color: "var(--text-muted)" }}>Complete treinos para ganhar suas primeiras conquistas.</p>
        </div>
      )}
    </main>
  );
}
