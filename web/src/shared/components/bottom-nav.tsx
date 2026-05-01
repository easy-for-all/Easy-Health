"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const ITEMS = [
  { href: "/workout/today", label: "Treino",  icon: "🏋️" },
  { href: "/plan",          label: "Treinos",  icon: "📋" },
  { href: "/profile",       label: "Perfil",  icon: "👤" },
];

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-10 border-t border-gray-100 bg-white">
      <div className="flex">
        {ITEMS.map(({ href, label, icon }) => {
          const active = pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={`flex flex-1 flex-col items-center gap-1 py-3 text-xs font-medium transition-colors ${
                active ? "text-green-500" : "text-gray-400"
              }`}
            >
              <span className="text-xl leading-none">{icon}</span>
              {label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
