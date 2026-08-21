"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { safeLocal } from "@/shared/lib/safe-storage";

type Theme = "light" | "dark";

interface ThemeContextValue {
  theme: Theme;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue>({
  theme: "light",
  toggleTheme: () => {},
});

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>("light");

  // Storage may be blocked for the document (SecurityError on the property
  // access itself). This effect runs inside the root layout, so an exception
  // here reaches app/global-error.tsx and white-screens the whole site — hence
  // safeLocal, never window.localStorage. Blocked storage simply means the
  // theme stays light and is not persisted.
  useEffect(() => {
    const stored = safeLocal.get("theme") as Theme | null;
    if (stored === "dark" || stored === "light") {
      setTheme(stored);
      document.documentElement.classList.toggle("dark", stored === "dark");
    }
  }, []);

  function toggleTheme() {
    const next: Theme = theme === "dark" ? "light" : "dark";
    setTheme(next);
    safeLocal.set("theme", next);
    document.documentElement.classList.toggle("dark", next === "dark");
  }

  return (
    <ThemeContext.Provider value={{ theme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
