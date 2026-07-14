"use client";

import { useEffect, useRef } from "react";
import { useTranslations } from "next-intl";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { PLAY_STORE_URL, useAppPromoTarget } from "@/shared/lib/platform";

// Premium, platform-aware app promo block. Reused on the public landing and on
// the post-first-workout "ready" screen. It is the web-only mirror of
// PrePermissionCard (which is native-only): inside the native app it renders
// nothing, since those users already have the app.
export function AppPromoCard({ placement }: { placement: "landing" | "ready" }) {
  const target = useAppPromoTarget();
  const t = useTranslations("appPromo");
  const viewed = useRef(false);

  useEffect(() => {
    if (target === "hidden" || viewed.current) return;
    viewed.current = true;
    trackEvent(EVENTS.APP_PROMO_VIEWED, { placement, target });
  }, [target, placement]);

  if (target === "hidden") return null;

  return (
    <div style={cardStyle}>
      <p style={titleStyle}>{t("card.title")}</p>
      <p style={descStyle}>{t("card.subtitle")}</p>

      {target === "android-button" ? (
        <a
          href={PLAY_STORE_URL}
          target="_blank"
          rel="noopener noreferrer"
          style={primaryBtn}
          onClick={() => trackEvent(EVENTS.APP_PROMO_CLICK, { placement, target })}
        >
          ▶ {t("card.androidCta")}
        </a>
      ) : (
        <div style={qrWrap}>
          <img src="/app-qr.svg" alt={t("card.androidCta")} width={132} height={132} style={qrImg} />
          <p style={qrHint}>{t("card.qrHint")}</p>
        </div>
      )}
    </div>
  );
}

const cardStyle: React.CSSProperties = {
  background: "var(--surface)",
  border: "1px solid var(--border)",
  borderRadius: "var(--r-lg)",
  padding: 18,
  marginBottom: 14,
  textAlign: "center",
};
const titleStyle: React.CSSProperties = {
  fontFamily: "var(--font-display)",
  fontWeight: 700,
  fontSize: 18,
  margin: "0 0 6px",
  letterSpacing: "-0.015em",
};
const descStyle: React.CSSProperties = { fontSize: 13, color: "var(--text-muted)", margin: "0 0 14px" };
const primaryBtn: React.CSSProperties = {
  display: "inline-flex",
  alignItems: "center",
  justifyContent: "center",
  gap: 6,
  width: "100%",
  borderRadius: "var(--r-pill)",
  padding: "14px",
  background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
  color: "var(--on-primary)",
  fontWeight: 700,
  fontSize: 14,
  textDecoration: "none",
  boxShadow: "var(--glow)",
};
const qrWrap: React.CSSProperties = { display: "flex", flexDirection: "column", alignItems: "center", gap: 10 };
const qrImg: React.CSSProperties = { borderRadius: "var(--r-sm)", background: "#fff", padding: 8 };
const qrHint: React.CSSProperties = { fontSize: 12.5, color: "var(--text-muted)", margin: 0, maxWidth: 220 };
