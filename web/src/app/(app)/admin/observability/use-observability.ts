"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/shared/lib/api";
import { ObservabilityPayload } from "./types";

const REFRESH_MS = 60_000;

// Plain useEffect + AbortController, matching the rest of the admin panel.
// The repo has no react-query/SWR and this page is not a reason to introduce
// one — a single polled endpoint does not justify a new data layer.
export function useObservability(range: string) {
  const [data, setData] = useState<ObservabilityPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const mounted = useRef(true);

  const load = useCallback(
    async (options?: { refresh?: boolean; silent?: boolean }) => {
      if (!options?.silent) setLoading(true);
      try {
        const params = new URLSearchParams({ range });
        if (options?.refresh) params.set("refresh", "1");
        const payload = await api.get<ObservabilityPayload>(
          `/api/v1/admin/observability?${params.toString()}`
        );
        if (!mounted.current) return;
        setData(payload);
        setError(null);
      } catch {
        if (!mounted.current) return;
        // Message stays generic: an API error body is not something to render
        // verbatim into an admin page.
        setError("Não foi possível carregar o painel de observabilidade.");
      } finally {
        if (mounted.current) setLoading(false);
      }
    },
    [range]
  );

  useEffect(() => {
    mounted.current = true;
    load();

    const timer = setInterval(() => load({ silent: true }), REFRESH_MS);
    return () => {
      mounted.current = false;
      clearInterval(timer);
    };
  }, [load]);

  return { data, loading, error, reload: load };
}
