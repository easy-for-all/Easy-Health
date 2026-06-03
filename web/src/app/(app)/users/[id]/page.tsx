"use client";

import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import Image from "next/image";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { PublicProfile } from "@/shared/types/user";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

export default function UserPublicProfilePage() {
  const params = useParams();
  const router = useRouter();
  const t = useTranslations("users");
  const [user, setUser] = useState<PublicProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    api.get<{ user: PublicProfile }>(`/api/v1/users/${params.id}`)
      .then((data) => setUser(data.user))
      .catch(() => setNotFound(true))
      .finally(() => setLoading(false));
  }, [params.id]);

  if (loading) return <LoadingScreen />;

  if (notFound || !user) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-4">
        <p className="text-gray-500 dark:text-gray-400">Perfil não encontrado ou privado.</p>
        <button onClick={() => router.back()} className="text-primary-500 text-sm font-medium">← Voltar</button>
      </div>
    );
  }

  const avatarSrc = user.avatar_url
    ? user.avatar_url.startsWith("http") ? user.avatar_url : `${API_URL}${user.avatar_url}`
    : null;

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">←</button>
        <h1 className="text-base font-semibold text-gray-900 dark:text-gray-100">{user.display_name}</h1>
      </header>

      <div className="mx-auto max-w-lg px-4 py-6">
        {/* Header do perfil */}
        <div className="mb-6 flex flex-col items-center gap-4 rounded-2xl bg-white p-6 shadow-sm dark:bg-gray-900">
          {avatarSrc ? (
            <Image src={avatarSrc} alt={user.display_name} width={80} height={80} className="rounded-full object-cover" />
          ) : (
            <div className="flex h-20 w-20 items-center justify-center rounded-full bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300 text-3xl font-bold">
              {user.display_name.charAt(0).toUpperCase()}
            </div>
          )}

          <div className="text-center">
            <div className="flex items-center justify-center gap-2">
              <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">{user.display_name}</h2>
              {user.account_type === "personal_trainer" && (
                <span className="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-700 dark:bg-blue-900 dark:text-blue-300">
                  {t("personal_trainer_badge")}
                </span>
              )}
            </div>
            {user.public_bio && (
              <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">{user.public_bio}</p>
            )}
          </div>

          {user.show_workout_count && user.workout_count != null && (
            <div className="flex items-center justify-center gap-1 rounded-xl bg-gray-50 px-4 py-2 dark:bg-gray-800">
              <span className="text-lg font-bold text-gray-900 dark:text-gray-100">{user.workout_count}</span>
              <span className="text-sm text-gray-500 dark:text-gray-400">{t("workouts_count", { count: user.workout_count })}</span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
