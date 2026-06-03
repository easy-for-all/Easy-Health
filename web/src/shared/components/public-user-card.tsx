"use client";

import Link from "next/link";
import Image from "next/image";
import { useTranslations } from "next-intl";
import type { PublicProfile } from "@/shared/types/user";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

interface PublicUserCardProps {
  user: PublicProfile;
}

export function PublicUserCard({ user }: PublicUserCardProps) {
  const t = useTranslations("users");

  const avatarSrc = user.avatar_url
    ? user.avatar_url.startsWith("http") ? user.avatar_url : `${API_URL}${user.avatar_url}`
    : null;

  return (
    <div className="flex items-center gap-3 rounded-xl bg-white p-4 shadow-sm dark:bg-gray-800">
      <div className="flex-shrink-0">
        {avatarSrc ? (
          <Image
            src={avatarSrc}
            alt={user.display_name}
            width={44}
            height={44}
            className="rounded-full object-cover"
          />
        ) : (
          <div className="flex h-11 w-11 items-center justify-center rounded-full bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300 font-semibold text-lg">
            {user.display_name.charAt(0).toUpperCase()}
          </div>
        )}
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-medium text-gray-900 dark:text-gray-100 truncate">{user.display_name}</span>
          {user.account_type === "personal_trainer" && (
            <span className="flex-shrink-0 rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-700 dark:bg-blue-900 dark:text-blue-300">
              {t("personal_trainer_badge")}
            </span>
          )}
        </div>
        {user.public_bio && (
          <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400 truncate">{user.public_bio}</p>
        )}
        {user.show_workout_count && user.workout_count != null && (
          <p className="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
            {t("workouts_count", { count: user.workout_count })}
          </p>
        )}
      </div>

      <Link
        href={`/users/${user.id}`}
        className="flex-shrink-0 rounded-lg bg-primary-500 px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-primary-600"
      >
        {t("view_profile")}
      </Link>
    </div>
  );
}
