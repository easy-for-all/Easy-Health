"use client";

import { useState, useEffect, useCallback } from "react";
import { api } from "@/shared/lib/api";
import { FilterChips } from "@/shared/components/ui/filter-chips";
import { PostCard, type Post } from "@/shared/components/community/post-card";
import { IconEyeOff, IconTrophy } from "@/shared/components/icons";
import Link from "next/link";

const FILTERS = [
  { id: "all",     label: "Todos"      },
  { id: "friends", label: "Amigos"     },
  { id: "similar", label: "Parecidas"  },
];

const BADGE_SAMPLES = [
  { icon: "🔥", label: "7 dias" },
  { icon: "💪", label: "10 treinos" },
  { icon: "⚡", label: "Consistente" },
];

function FeedNote() {
  return (
    <div
      style={{
        display: "flex",
        gap: 10,
        padding: "12px 14px",
        background: "var(--surface-2)",
        borderRadius: "var(--r-md)",
        border: "1px solid var(--border)",
        marginBottom: 16,
      }}
    >
      <span style={{ flexShrink: 0, color: "var(--text-dim)", marginTop: 1 }}>
        <IconEyeOff className="w-4 h-4" />
      </span>
      <p style={{ margin: 0, fontSize: 12, color: "var(--text-muted)", lineHeight: 1.5 }}>
        Só aparecem aqui quem optou por participar da Comunidade.{" "}
        <Link href="/community/privacy" style={{ color: "var(--primary)", fontWeight: 600 }}>
          Ajustar minha visibilidade
        </Link>
      </p>
    </div>
  );
}

function BadgeStrip() {
  return (
    <div style={{ marginBottom: 20 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 10 }}>
        <p className="eyebrow">Suas conquistas</p>
        <Link href="/community/badges" style={{ fontSize: 12, fontWeight: 600, color: "var(--primary)", textDecoration: "none" }}>
          Ver todas
        </Link>
      </div>
      <div style={{ display: "flex", gap: 8, overflowX: "auto", scrollbarWidth: "none", paddingBottom: 2 }}>
        {BADGE_SAMPLES.map((b) => (
          <div
            key={b.label}
            style={{
              flexShrink: 0,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 4,
              padding: "10px 14px",
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--r-md)",
              minWidth: 72,
            }}
          >
            <span style={{ fontSize: 22 }}>{b.icon}</span>
            <span style={{ fontSize: 10, fontWeight: 700, color: "var(--text-muted)", textAlign: "center" }}>
              {b.label}
            </span>
          </div>
        ))}
        <Link
          href="/community/badges"
          style={{
            flexShrink: 0,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 4,
            padding: "10px 14px",
            background: "var(--surface)",
            border: "1px solid var(--primary-soft)",
            borderRadius: "var(--r-md)",
            minWidth: 72,
            color: "var(--primary)",
            textDecoration: "none",
          }}
        >
          <IconTrophy className="w-5 h-5" />
          <span style={{ fontSize: 10, fontWeight: 700, textAlign: "center" }}>Mais</span>
        </Link>
      </div>
    </div>
  );
}

function EmptyState({ filter }: { filter: string }) {
  const messages: Record<string, { icon: string; title: string; body: string }> = {
    all:     { icon: "🌍", title: "Comunidade vazia por enquanto",   body: "Quando alunos ativarem a visibilidade pública, os treinos aparecerão aqui."  },
    friends: { icon: "🤝", title: "Nenhum amigo no feed ainda",      body: "Conecte-se com um Personal Trainer ou convide amigos para o app."             },
    similar: { icon: "🎯", title: "Sem usuários parecidos por aqui", body: "Complete seu perfil de saúde para encontrar usuários com objetivos similares." },
  };
  const m = messages[filter] ?? messages.all;
  return (
    <div style={{ textAlign: "center", padding: "48px 16px" }}>
      <span style={{ fontSize: 40 }}>{m.icon}</span>
      <p className="h-sm" style={{ margin: "12px 0 6px" }}>{m.title}</p>
      <p style={{ fontSize: 13, color: "var(--text-muted)", lineHeight: 1.5 }}>{m.body}</p>
    </div>
  );
}

export default function CommunityPage() {
  const [filter, setFilter]   = useState("all");
  const [posts, setPosts]     = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError]     = useState<string | null>(null);

  const load = useCallback(async (f: string) => {
    setLoading(true);
    setError(null);
    try {
      const data = await api.get<{ posts: Record<string, unknown>[] }>(`/api/v1/community/feed?filter=${f}`);
      const mapped: Post[] = (data.posts ?? []).map((p) => ({
        id:             p.id as string | number,
        name:           p.name as string,
        hue:            p.hue as number | undefined,
        avatarUrl:      (p.avatar_url ?? p.avatarUrl) as string | null | undefined,
        time:           p.time as string,
        type:           p.type as Post["type"],
        title:          p.title as string,
        highlight:      (p.highlight ?? p.highlight) as string | undefined,
        streakDays:     (p.streak_days ?? p.streakDays) as number[] | undefined,
        reaction_count: p.reaction_count as number | undefined,
        reacted:        p.reacted as boolean | undefined,
        comment_count:  p.comment_count as number | undefined,
      }));
      setPosts(mapped);
    } catch {
      setError("Não foi possível carregar o feed.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(filter); }, [filter, load]);

  const handleCongrats = async (id: string | number, reacted: boolean) => {
    try {
      if (reacted) {
        await api.post(`/api/v1/community/posts/${id}/reactions`, { reaction_type: "congrats" });
      } else {
        await api.delete(`/api/v1/community/posts/${id}/reactions`);
      }
    } catch {
      // optimistic — ignore error
    }
  };

  return (
    <main
      style={{
        maxWidth: 480,
        margin: "0 auto",
        padding: "20px 16px",
        paddingBottom: "calc(var(--nav-pb) + 16px)",
      }}
    >
      <h1 className="h-lg" style={{ marginBottom: 16 }}>Comunidade</h1>

      <FeedNote />
      <BadgeStrip />

      <FilterChips chips={FILTERS} active={filter} onChange={(f) => setFilter(f)} />

      <div style={{ marginTop: 16, display: "flex", flexDirection: "column", gap: 12 }}>
        {loading && (
          <div style={{ textAlign: "center", padding: "32px 0", color: "var(--text-dim)" }}>
            Carregando...
          </div>
        )}

        {!loading && error && (
          <div style={{ textAlign: "center", padding: "32px 0", color: "var(--hot)", fontSize: 14 }}>
            {error}
          </div>
        )}

        {!loading && !error && posts.length === 0 && <EmptyState filter={filter} />}

        {!loading && !error && posts.map((post) => (
          <PostCard key={post.id} post={post} onCongrats={handleCongrats} />
        ))}
      </div>
    </main>
  );
}
