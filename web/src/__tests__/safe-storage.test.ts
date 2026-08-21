import { describe, it, expect, afterEach, vi } from "vitest";

// Reproduces the production failure of Sentry RUBY-RAILS-K: the browser denies
// storage to the document, so READING the property throws — getItem is never
// reached.
type StoreName = "localStorage" | "sessionStorage";

const REAL_DESCRIPTORS: Record<StoreName, PropertyDescriptor | undefined> = {
  localStorage: Object.getOwnPropertyDescriptor(window, "localStorage"),
  sessionStorage: Object.getOwnPropertyDescriptor(window, "sessionStorage"),
};

function block(name: StoreName): void {
  Object.defineProperty(window, name, {
    configurable: true,
    get() {
      throw new DOMException(
        `Failed to read the '${name}' property from 'Window': Access is denied for this document.`,
        "SecurityError",
      );
    },
  });
}

function restore(): void {
  (Object.keys(REAL_DESCRIPTORS) as StoreName[]).forEach((name) => {
    const descriptor = REAL_DESCRIPTORS[name];
    if (descriptor) Object.defineProperty(window, name, descriptor);
  });
}

// Availability is resolved once per module instance, so every test imports a
// fresh copy with the stub already installed.
async function freshModule() {
  vi.resetModules();
  return import("@/shared/lib/safe-storage");
}

afterEach(() => {
  restore();
  window.localStorage.clear();
  window.sessionStorage.clear();
});

describe("safe-storage", () => {
  it("uses the real store when storage is allowed", async () => {
    const { safeLocal, safeSession } = await freshModule();

    expect(safeLocal.isAvailable()).toBe(true);
    expect(safeSession.isAvailable()).toBe(true);

    safeLocal.set("theme", "dark");
    expect(window.localStorage.getItem("theme")).toBe("dark");
    expect(safeLocal.get("theme")).toBe("dark");

    safeLocal.remove("theme");
    expect(window.localStorage.getItem("theme")).toBeNull();
    expect(safeLocal.get("theme")).toBeNull();
  });

  it("falls back to memory when localStorage access is denied", async () => {
    block("localStorage");
    const { safeLocal } = await freshModule();

    expect(safeLocal.isAvailable()).toBe(false);
    expect(safeLocal.get("missing")).toBeNull();

    safeLocal.set("foo", "bar");
    expect(safeLocal.get("foo")).toBe("bar");

    safeLocal.remove("foo");
    expect(safeLocal.get("foo")).toBeNull();
  });

  it("falls back to memory when sessionStorage access is denied", async () => {
    block("sessionStorage");
    const { safeSession } = await freshModule();

    expect(safeSession.isAvailable()).toBe(false);
    expect(safeSession.get("missing")).toBeNull();

    safeSession.set("foo", "bar");
    expect(safeSession.get("foo")).toBe("bar");

    safeSession.remove("foo");
    expect(safeSession.get("foo")).toBeNull();
  });

  it("keeps the two stores independent — blocking one leaves the other usable", async () => {
    block("localStorage");
    const { safeLocal, safeSession } = await freshModule();

    expect(safeLocal.isAvailable()).toBe(false);
    expect(safeSession.isAvailable()).toBe(true);

    safeSession.set("wk_quick_day", "{}");
    expect(window.sessionStorage.getItem("wk_quick_day")).toBe("{}");
  });
});
