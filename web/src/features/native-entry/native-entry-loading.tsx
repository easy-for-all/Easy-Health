"use client";

export function NativeEntryLoading() {
  return (
    <div
      className="flex min-h-svh items-center justify-center"
      style={{
        background: "#0a0f1e",
        paddingTop: "max(20px, var(--safe-area-top))",
        paddingRight: "max(16px, var(--safe-area-right))",
        paddingBottom: "max(20px, var(--safe-area-bottom))",
        paddingLeft: "max(16px, var(--safe-area-left))",
      }}
      role="status"
      aria-label="Carregando"
    >
      <div className="h-7 w-7 animate-spin rounded-full border-4 border-primary-500 border-t-transparent" />
    </div>
  );
}
