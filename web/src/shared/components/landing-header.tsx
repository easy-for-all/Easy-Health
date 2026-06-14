"use client";

import { useState } from "react";
import Link from "next/link";

export function LandingHeader() {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header style={{ position: "sticky", top: 0, zIndex: 50, backdropFilter: "blur(18px)", WebkitBackdropFilter: "blur(18px)", background: "oklch(0.155 0.022 262 / .82)", borderBottom: "1px solid var(--border)" }}>
      <div style={{ margin: "0 auto", maxWidth: 1180, display: "flex", alignItems: "center", justifyContent: "space-between", height: 72, padding: "0 clamp(16px, 4vw, 32px)" }}>
        <Link href="/" style={{ display: "flex", alignItems: "center", gap: 10, fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 21, letterSpacing: "-0.01em", color: "var(--text)", textDecoration: "none" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="EasyHealth" style={{ width: 34, height: 34, borderRadius: 10 }} />
          EasyHealth
        </Link>
        <nav style={{ display: "flex", alignItems: "center", gap: 4 }}>
          {/* Desktop nav links */}
          {[{ href: "#funciona", label: "Como funciona" }, { href: "#planos", label: "Planos" }].map((l) => (
            <a key={l.href} href={l.href} className="landing-nav-link sm:block" style={{ display: "none", fontWeight: 600, textDecoration: "none", padding: "8px 12px", fontSize: 15, transition: "color .15s" }}>
              {l.label}
            </a>
          ))}
          <Link href="/login" className="hidden sm:block" style={{ fontWeight: 600, color: "var(--text-muted)", textDecoration: "none", padding: "8px 12px", fontSize: 15 }}>
            Entrar
          </Link>
          <Link href="/sign-up" className="hidden sm:block" style={{ background: "linear-gradient(180deg, var(--primary), var(--primary-2))", color: "var(--on-primary)", fontWeight: 700, fontSize: 15, padding: "10px 20px", borderRadius: "var(--r-pill)", boxShadow: "var(--glow)", textDecoration: "none" }}>
            Criar conta
          </Link>

          {/* Mobile: CTA + hamburger */}
          <Link href="/sign-up" className="sm:hidden" style={{ background: "linear-gradient(180deg, var(--primary), var(--primary-2))", color: "var(--on-primary)", fontWeight: 700, fontSize: 14, padding: "8px 16px", borderRadius: "var(--r-pill)", boxShadow: "var(--glow)", textDecoration: "none" }}>
            Criar conta
          </Link>
          <button
            className="sm:hidden"
            onClick={() => setMenuOpen((v) => !v)}
            aria-label={menuOpen ? "Fechar menu" : "Abrir menu"}
            style={{ padding: 8, background: "none", border: "none", cursor: "pointer", color: "var(--text-muted)", display: "flex", alignItems: "center" }}
          >
            {menuOpen ? (
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            ) : (
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            )}
          </button>
        </nav>
      </div>

      {/* Mobile dropdown */}
      {menuOpen && (
        <div className="sm:hidden" style={{ borderTop: "1px solid var(--border)", padding: "12px 16px 16px", display: "flex", flexDirection: "column", gap: 4, background: "oklch(0.13 0.02 262 / .98)" }}>
          <a
            href="#funciona"
            onClick={() => setMenuOpen(false)}
            style={{ display: "block", padding: "12px 16px", fontSize: 15, fontWeight: 600, color: "var(--text-muted)", textDecoration: "none", borderRadius: 12 }}
          >
            Como funciona
          </a>
          <a
            href="#planos"
            onClick={() => setMenuOpen(false)}
            style={{ display: "block", padding: "12px 16px", fontSize: 15, fontWeight: 600, color: "var(--text-muted)", textDecoration: "none", borderRadius: 12 }}
          >
            Planos
          </a>
          <Link
            href="/login"
            onClick={() => setMenuOpen(false)}
            style={{ display: "block", padding: "12px 16px", fontSize: 15, fontWeight: 600, color: "var(--text-muted)", textDecoration: "none", borderRadius: 12 }}
          >
            Entrar
          </Link>
        </div>
      )}
    </header>
  );
}
