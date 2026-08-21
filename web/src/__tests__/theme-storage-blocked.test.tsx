import { render, screen } from "@testing-library/react";
import { describe, it, expect, afterEach, vi } from "vitest";

// Regression test for Sentry RUBY-RAILS-K: ThemeProvider lives in the ROOT
// layout, so an exception in its mount effect is not contained by
// app/error.tsx — it reaches app/global-error.tsx and white-screens the landing
// page ("Algo deu errado") for every visitor whose browser blocks storage.

const REAL_LOCAL_STORAGE = Object.getOwnPropertyDescriptor(window, "localStorage");

function blockLocalStorage(): void {
  Object.defineProperty(window, "localStorage", {
    configurable: true,
    get() {
      throw new DOMException(
        "Failed to read the 'localStorage' property from 'Window': Access is denied for this document.",
        "SecurityError",
      );
    },
  });
}

afterEach(() => {
  if (REAL_LOCAL_STORAGE) Object.defineProperty(window, "localStorage", REAL_LOCAL_STORAGE);
  window.localStorage.clear();
  document.documentElement.classList.remove("dark");
});

// safe-storage resolves availability once per module instance, so the provider
// is imported fresh with the stub already in place.
async function renderProvider() {
  vi.resetModules();
  const { ThemeProvider, useTheme } = await import("@/features/theme/theme-context");

  function ThemeProbe() {
    return <span data-testid="theme">{useTheme().theme}</span>;
  }

  return render(
    <ThemeProvider>
      <ThemeProbe />
    </ThemeProvider>,
  );
}

describe("ThemeProvider with storage blocked", () => {
  it("renders in light theme instead of crashing the app", async () => {
    blockLocalStorage();

    await expect(renderProvider()).resolves.toBeTruthy();

    expect(screen.getByTestId("theme")).toHaveTextContent("light");
    expect(document.documentElement.classList.contains("dark")).toBe(false);
  });

  it("still restores the saved theme when storage works", async () => {
    window.localStorage.setItem("theme", "dark");

    await renderProvider();

    expect(screen.getByTestId("theme")).toHaveTextContent("dark");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
  });
});
