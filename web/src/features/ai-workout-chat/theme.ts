// Dark-first palette, matching coach-sheet.css's hardcoded oklch values —
// this screen is always dark regardless of the app's light/dark toggle,
// same precedent as the existing Coach chat sheet.
export const AI_CHAT_COLORS = {
  bg: "oklch(0.155 0.022 262)",
  surface: "oklch(0.213 0.028 262)",
  text: "oklch(0.975 0.008 258)",
  textMuted: "oklch(0.755 0.018 262)",
  textDim: "oklch(0.585 0.020 262)",
  border: "oklch(0.315 0.026 262)",
  primary: "oklch(0.685 0.17 258)",
  primarySoft: "oklch(0.685 0.17 258 / 0.14)",
  danger: "oklch(0.65 0.2 25)",
} as const;
