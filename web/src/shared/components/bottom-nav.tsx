"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion } from "framer-motion";
import { IconUsers } from "./icons";

// ── Icons ────────────────────────────────────────────────────────────────────

function IconHome() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <path d="M3 9.5L12 3l9 6.5V20a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9.5z" />
      <path d="M9 21V12h6v9" />
    </svg>
  );
}

function IconDumbbell() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <rect x="2" y="10" width="4" height="4" rx="1" />
      <rect x="18" y="10" width="4" height="4" rx="1" />
      <line x1="6" y1="12" x2="18" y2="12" />
      <rect x="5" y="9" width="2" height="6" rx="0.5" />
      <rect x="17" y="9" width="2" height="6" rx="0.5" />
    </svg>
  );
}

function IconChart() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <line x1="18" y1="20" x2="18" y2="10" />
      <line x1="12" y1="20" x2="12" y2="4" />
      <line x1="6" y1="20" x2="6" y2="14" />
    </svg>
  );
}

function IconUser() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <circle cx="12" cy="8" r="4" />
      <path d="M4 20c0-4 3.6-7 8-7s8 3 8 7" />
    </svg>
  );
}

// ── Nav config ───────────────────────────────────────────────────────────────

const ITEMS = [
  { href: "/dashboard",  label: "Hoje",      Icon: IconHome,  match: (p: string) => p === "/dashboard" || p === "/" },
  { href: "/workouts",   label: "Treinos",   Icon: IconDumbbell, match: (p: string) => p.startsWith("/workout") || p.startsWith("/workouts") || p.startsWith("/plan") },
  { href: "/history",    label: "Progresso", Icon: IconChart, match: (p: string) => p.startsWith("/history") },
  { href: "/community",  label: "Comunidade", Icon: ({ className }: { className?: string }) => <IconUsers className={className ?? "w-6 h-6"} />, match: (p: string) => p.startsWith("/community") },
  { href: "/profile",    label: "Perfil",    Icon: IconUser,  match: (p: string) => p.startsWith("/profile") },
] as const;

const IMMERSIVE_PREFIXES = ["/personal", "/join"];

export function BottomNav() {
  const pathname = usePathname();

  if (IMMERSIVE_PREFIXES.some((prefix) => pathname.startsWith(prefix))) {
    return null;
  }

  return (
    <nav
      style={{
        position: "fixed", bottom: 0, left: 0, right: 0, zIndex: 30,
        borderTop: "1px solid var(--border)",
        background: "var(--glass, oklch(0.185 0.026 262 / 0.72))",
        backdropFilter: "blur(16px)",
        paddingBottom: "env(safe-area-inset-bottom, 0px)",
        paddingLeft: "env(safe-area-inset-left, 0px)",
        paddingRight: "env(safe-area-inset-right, 0px)",
      }}
    >
      <div style={{ display: "flex" }}>
        {ITEMS.map(({ href, label, Icon, match }) => {
          const active = match(pathname);
          return (
            <Link
              key={href}
              href={href}
              style={{
                flex: 1, display: "flex", flexDirection: "column",
                alignItems: "center", gap: 4, padding: "9px 0",
                fontSize: 10, fontWeight: 600,
                color: active ? "var(--primary)" : "var(--text-dim)",
                textDecoration: "none",
                transition: "color .18s",
              }}
            >
              <motion.span
                whileTap={{ scale: 0.85 }}
                transition={{ duration: 0.1 }}
                style={{ position: "relative", display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}
              >
                <Icon />
                {label}
                {active && (
                  <motion.span
                    layoutId="nav-dot"
                    style={{
                      position: "absolute", bottom: -10,
                      width: 4, height: 4, borderRadius: "50%",
                      background: "var(--primary)",
                    }}
                    transition={{ type: "spring", stiffness: 400, damping: 30 }}
                  />
                )}
              </motion.span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
