import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    // The installation/analytics suites call vi.resetModules() per test and then
    // re-import the module graph through dynamic import(), which re-transforms it
    // every time. On a loaded machine (CI runner, or a local run alongside the
    // backend suite) that alone can exceed the 5s default and fail a test that has
    // nothing wrong with it — always as a timeout, never as a wrong assertion.
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
