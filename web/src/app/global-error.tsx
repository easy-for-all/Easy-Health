"use client";

import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  // Same reason as app/error.tsx: a swallowed crash is invisible in production.
  useEffect(() => {
    Sentry.captureException(error, { tags: { boundary: "global" } });
  }, [error]);

  return (
    <html lang="pt-BR">
      <body>
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-8 text-center">
          <h2 className="text-xl font-semibold">Algo deu errado</h2>
          <p className="text-sm text-gray-500">
            Ocorreu um erro crítico. Por favor, recarregue a página.
          </p>
          <button
            onClick={reset}
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white"
          >
            Recarregar
          </button>
        </div>
      </body>
    </html>
  );
}
