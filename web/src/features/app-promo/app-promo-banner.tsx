"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { PLAY_STORE_URL, useAppPromoTarget } from "@/shared/lib/platform";

// Persisted so a dismissal is remembered across sessions (never nag on every
// visit). Same `eh_` convention as PrePermissionCard.
const DISMISSED_KEY = "eh_app_promo_dismissed";

function dismissedLocally(): boolean {
  try {
    return localStorage.getItem(DISMISSED_KEY) === "1";
  } catch {
    return false;
  }
}

// Thin, dismissible top banner promoting the Android app in the logged-in area
// (mounted next to TrialBanner). Web-only: never shows inside the native app,
// on iOS web, or once the user has dismissed it.
export function AppPromoBanner() {
  const target = useAppPromoTarget();
  const t = useTranslations("appPromo");
  // Lazy initializer reads localStorage on the client's first render (returns
  // false during SSR via the try/catch). Never surfaces in the SSR DOM because
  // `target` is "hidden" until mount, so there's no hydration mismatch.
  const [dismissed, setDismissed] = useState(dismissedLocally);
  const [qrOpen, setQrOpen] = useState(false);

  const visible = target !== "hidden" && !dismissed;

  useEffect(() => {
    if (!visible) return;
    trackEvent(EVENTS.APP_PROMO_VIEWED, { placement: "app_banner", target });
  }, [visible, target]);

  if (!visible) return null;

  function handleDismiss() {
    trackEvent(EVENTS.APP_PROMO_DISMISSED, { placement: "app_banner", target });
    try {
      localStorage.setItem(DISMISSED_KEY, "1");
    } catch {
      /* ignore */
    }
    setDismissed(true);
  }

  const isAndroid = target === "android-button";

  return (
    <div
      style={{
        width: "100%",
        background: "var(--primary-soft)",
        color: "var(--text)",
        borderBottom: "1px solid var(--border)",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "8px 14px", fontSize: 13 }}>
        <span style={{ flex: 1, minWidth: 0 }}>{t("banner.text")}</span>
        {isAndroid ? (
          <a
            href={PLAY_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            onClick={() => trackEvent(EVENTS.APP_PROMO_CLICK, { placement: "app_banner", target })}
            style={{
              flexShrink: 0,
              borderRadius: "var(--r-pill)",
              padding: "6px 12px",
              fontSize: 12,
              fontWeight: 700,
              background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
              color: "var(--on-primary)",
              textDecoration: "none",
            }}
          >
            {t("banner.cta")}
          </a>
        ) : (
          <button
            onClick={() => {
              if (!qrOpen) trackEvent(EVENTS.APP_PROMO_CLICK, { placement: "app_banner", target });
              setQrOpen((v) => !v);
            }}
            style={{
              flexShrink: 0,
              background: "transparent",
              border: 0,
              cursor: "pointer",
              fontSize: 12,
              fontWeight: 700,
              color: "var(--primary)",
            }}
          >
            {t("banner.ctaQr")} {qrOpen ? "▲" : "▼"}
          </button>
        )}
        <button
          onClick={handleDismiss}
          aria-label={t("dismiss")}
          style={{
            flexShrink: 0,
            background: "transparent",
            border: 0,
            cursor: "pointer",
            color: "var(--text-muted)",
            fontSize: 16,
            lineHeight: 1,
            padding: "2px 4px",
          }}
        >
          ✕
        </button>
      </div>
      {!isAndroid && qrOpen && (
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8, padding: "4px 14px 14px" }}>
          <img
            src="/app-qr.svg"
            alt={t("card.androidCta")}
            width={128}
            height={128}
            style={{ borderRadius: "var(--r-sm)", background: "#fff", padding: 8 }}
          />
          <p style={{ fontSize: 12, color: "var(--text-muted)", margin: 0 }}>{t("card.qrHint")}</p>
        </div>
      )}
    </div>
  );
}
