"use client";

import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

export default function ErrorPage({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  // This used to be `void error`: a render crash showed "Algo deu errado" and
  // was never reported anywhere. On Android that made a broken landing or auth
  // screen indistinguishable from a user who simply left.
  useEffect(() => {
    Sentry.captureException(error, { tags: { boundary: "route" } });
  }, [error]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-8 text-center">
      <h2 className="text-xl font-semibold text-gray-800 dark:text-gray-100">
        Algo deu errado
      </h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">
        Ocorreu um erro inesperado. Tente novamente.
      </p>
      <button
        onClick={reset}
        className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700"
      >
        Tentar novamente
      </button>
    </div>
  );
}
