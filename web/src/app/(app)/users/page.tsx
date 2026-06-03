"use client";

import { useState, useCallback } from "react";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import { PublicUserCard } from "@/shared/components/public-user-card";
import type { PublicProfile } from "@/shared/types/user";

export default function UsersSearchPage() {
  const t = useTranslations("users");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<PublicProfile[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  const search = useCallback(async (q: string) => {
    if (q.trim().length < 2) return;
    setLoading(true);
    setSearched(true);
    try {
      const data = await api.get<{ users: PublicProfile[] }>(`/api/v1/users?q=${encodeURIComponent(q.trim())}`);
      setResults(data.users);
    } catch {
      setResults([]);
    } finally {
      setLoading(false);
    }
  }, []);

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") search(query);
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <h1 className="mb-3 text-base font-semibold text-gray-900 dark:text-gray-100">{t("title")}</h1>
        <div className="flex gap-2">
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={t("search_placeholder")}
            className="flex-1 rounded-xl border border-gray-200 bg-white px-4 py-2.5 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100 dark:placeholder-gray-500"
          />
          <button
            onClick={() => search(query)}
            disabled={query.trim().length < 2 || loading}
            className="rounded-xl bg-primary-500 px-4 py-2.5 text-sm font-medium text-white disabled:opacity-40"
          >
            {loading ? "..." : "→"}
          </button>
        </div>
      </header>

      <div className="mx-auto max-w-lg space-y-3 px-4 py-4">
        {searched && !loading && results.length === 0 && (
          <p className="py-8 text-center text-sm text-gray-500 dark:text-gray-400">{t("no_results")}</p>
        )}
        {results.map((user) => (
          <PublicUserCard key={user.id} user={user} />
        ))}
      </div>
    </div>
  );
}
