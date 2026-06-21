"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Avatar } from "../ui/avatar";

export type PostType = "workout" | "streak" | "evolution" | "achievement";

export interface Post {
  id: string | number;
  name: string;
  short?: string;
  hue?: number;
  avatarUrl?: string | null;
  time: string;
  type: PostType;
  title: string;
  highlight?: string;
  streakDays?: number[];
  sparkline?: number[];
  medalIcon?: string;
  congrats?: number;
  reaction_count?: number;
  reacted?: boolean;
  comment_count?: number;
}

interface PostCardProps {
  post: Post;
  onCongrats?: (id: string | number, reacted: boolean) => void;
}

// Tiny sparkline for evolution posts
function Sparkline({ values }: { values: number[] }) {
  if (values.length < 2) return null;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;
  const w = 64;
  const h = 24;
  const pts = values
    .map((v, i) => {
      const x = (i / (values.length - 1)) * w;
      const y = h - ((v - min) / range) * h;
      return `${x},${y}`;
    })
    .join(" ");

  return (
    <svg width={w} height={h} style={{ overflow: "visible" }}>
      <polyline
        points={pts}
        fill="none"
        stroke="var(--good)"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// Streak dots
function StreakDots({ days }: { days: number[] }) {
  return (
    <div style={{ display: "flex", gap: 4 }}>
      {days.map((active, i) => (
        <span
          key={i}
          style={{
            width: 8,
            height: 8,
            borderRadius: "50%",
            background: active ? "var(--hot)" : "var(--surface-3)",
            flexShrink: 0,
          }}
        />
      ))}
    </div>
  );
}

const TYPE_LABEL: Record<PostType, string> = {
  workout:     "Treino concluído",
  streak:      "Sequência",
  evolution:   "Evolução",
  achievement: "Conquista",
};

const TYPE_COLOR: Record<PostType, string> = {
  workout:     "var(--primary)",
  streak:      "var(--hot)",
  evolution:   "var(--good)",
  achievement: "oklch(0.72 0.18 78)",
};

export function PostCard({ post, onCongrats }: PostCardProps) {
  const [congratulated, setCongratulated] = useState(post.reacted ?? false);
  const [count, setCount] = useState(post.reaction_count ?? post.congrats ?? 0);

  const handleCongrats = () => {
    const next = !congratulated;
    setCongratulated(next);
    setCount((c) => next ? c + 1 : Math.max(0, c - 1));
    onCongrats?.(post.id, next);
  };

  return (
    <article
      style={{
        background: "var(--surface)",
        borderRadius: "var(--r-lg)",
        border: "1px solid var(--border)",
        padding: "16px",
        display: "flex",
        flexDirection: "column",
        gap: 12,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <Avatar name={post.name} avatarUrl={post.avatarUrl} hue={post.hue} size={40} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{ margin: 0, fontWeight: 700, fontSize: 14, color: "var(--text)", lineHeight: 1.2 }}>
            {post.name}
          </p>
          <p style={{ margin: 0, fontSize: 11, color: "var(--text-dim)" }}>
            <span
              style={{
                fontWeight: 700,
                color: TYPE_COLOR[post.type],
                marginRight: 4,
              }}
            >
              {TYPE_LABEL[post.type]}
            </span>
            · {post.time}
          </p>
        </div>
      </div>

      {/* Body */}
      <div>
        <p style={{ margin: "0 0 6px", fontWeight: 600, fontSize: 15, color: "var(--text)" }}>
          {post.title}
        </p>
        {post.highlight && (
          <p style={{ margin: 0, fontSize: 13, color: "var(--text-muted)" }}>{post.highlight}</p>
        )}

        {post.type === "streak" && post.streakDays && (
          <StreakDots days={post.streakDays} />
        )}

        {post.type === "evolution" && post.sparkline && (
          <div style={{ marginTop: 8 }}>
            <Sparkline values={post.sparkline} />
          </div>
        )}

        {post.type === "achievement" && post.medalIcon && (
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 4 }}>
            <span style={{ fontSize: 28 }}>{post.medalIcon}</span>
          </div>
        )}
      </div>

      {/* Footer */}
      <div style={{ borderTop: "1px solid var(--hairline)", paddingTop: 10 }}>
        <motion.button
          onClick={handleCongrats}
          whileTap={{ scale: 0.94 }}
          aria-label={congratulated ? "Você parabenizou" : "Parabenizar"}
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 6,
            padding: "7px 14px",
            borderRadius: "var(--r-pill)",
            border: `1.5px solid ${congratulated ? "var(--good)" : "var(--border)"}`,
            background: congratulated ? "var(--good-soft)" : "transparent",
            color: congratulated ? "var(--good)" : "var(--text-muted)",
            fontSize: 13,
            fontWeight: 600,
            cursor: "pointer",
            transition: "all .2s var(--ease)",
            minHeight: 44,
          }}
        >
          <span>{congratulated ? "🙌" : "👏"}</span>
          {congratulated ? "Parabéns enviado!" : "Parabenizar"}
          {count > 0 && (
            <span style={{ fontSize: 11, color: "inherit", opacity: 0.75 }}>
              {count}
            </span>
          )}
        </motion.button>
      </div>
    </article>
  );
}
