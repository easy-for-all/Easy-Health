"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { motion } from "framer-motion";

function UserIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <circle cx="12" cy="8" r="4" />
      <path d="M4 20c0-4 3.6-7 8-7s8 3 8 7" />
    </svg>
  );
}

function DumbbellIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <rect x="2" y="10" width="4" height="4" rx="1" />
      <rect x="18" y="10" width="4" height="4" rx="1" />
      <line x1="6" y1="12" x2="18" y2="12" />
      <rect x="5" y="9" width="2" height="6" rx="0.5" />
      <rect x="17" y="9" width="2" height="6" rx="0.5" />
    </svg>
  );
}

function ClipboardIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <rect x="6" y="4" width="12" height="16" rx="2" />
      <path d="M9 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1" />
      <line x1="9" y1="10" x2="15" y2="10" />
      <line x1="9" y1="14" x2="13" y2="14" />
    </svg>
  );
}

function CreditCardIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <rect x="2" y="5" width="20" height="14" rx="2" />
      <line x1="2" y1="10" x2="22" y2="10" />
      <line x1="6" y1="15" x2="10" y2="15" />
    </svg>
  );
}

function UsersIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <circle cx="9" cy="7" r="3" />
      <path d="M3 20c0-3 2.7-5 6-5s6 2 6 5" />
      <circle cx="17" cy="7" r="3" />
      <path d="M21 20c0-3-1.3-5-4-5" />
    </svg>
  );
}

export function BottomNav() {
  const pathname = usePathname();
  const t = useTranslations("nav");

  const ITEMS = [
    { href: "/profile",   label: t("profile"),      Icon: UserIcon },
    { href: "/workouts",  label: t("workouts"),      Icon: DumbbellIcon },
    { href: "/users",     label: t("community"),     Icon: UsersIcon },
    { href: "/billing",   label: t("subscription"),  Icon: CreditCardIcon },
  ];

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-10 border-t border-gray-100/60 bg-white/85 backdrop-blur-md dark:border-gray-800/60 dark:bg-gray-950/85">
      <div className="flex">
        {ITEMS.map(({ href, label, Icon }) => {
          const active =
            href === "/workouts"
              ? (pathname.startsWith("/workouts") && !pathname.startsWith("/workouts/shared")) ||
                pathname.startsWith("/workout") ||
                pathname.startsWith("/plan")
              : href === "/users"
              ? pathname.startsWith("/users") || pathname.startsWith("/workouts/shared")
              : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={`flex flex-1 flex-col items-center gap-1 py-3 text-xs font-medium transition-colors ${
                active ? "text-primary-500" : "text-gray-400 dark:text-gray-500"
              }`}
            >
              <motion.span
                whileTap={{ scale: 0.85 }}
                transition={{ duration: 0.1 }}
                className="relative flex flex-col items-center gap-1"
              >
                <Icon />
                {label}
                {active && (
                  <motion.span
                    layoutId="nav-dot"
                    className="absolute -bottom-2.5 h-1 w-1 rounded-full bg-primary-500"
                    transition={{ type: "spring", stiffness: 400, damping: 30 }}
                  />
                )}
              </motion.span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
