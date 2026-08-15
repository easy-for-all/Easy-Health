import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AuthProvider, useAuth } from "@/features/auth/auth-context";

// The authenticated boot is the only place that re-syncs an already-granted FCM
// token. It must key off the SAME robust native detection as the rest of the app
// (isNativeApp), because Capacitor.isNativePlatform() answers false inside the
// shell that loads the remote site — which silently disabled push in production.

const h = vi.hoisted(() => ({
  isNativePlatform: true,
  platform: "android" as string,
}));

// Hoisted with the mock factories: AuthProvider is imported statically here, so
// the factory below runs before a plain class declaration would be initialized.
const MockApiError = vi.hoisted(
  () =>
    class ApiError extends Error {
      status: number;
      constructor(message: string, status: number) {
        super(message);
        this.name = "ApiError";
        this.status = status;
      }
    },
);

const apiGet = vi.hoisted(() => vi.fn());
const apiDelete = vi.hoisted(() => vi.fn());
const syncPushIfGranted = vi.hoisted(() => vi.fn());
const claimAnonymousData = vi.hoisted(() => vi.fn());

vi.mock("@capacitor/core", () => ({
  Capacitor: {
    isNativePlatform: (): boolean => h.isNativePlatform,
    getPlatform: (): string => h.platform,
  },
}));

vi.mock("@/shared/lib/api", () => ({
  api: { get: apiGet, delete: apiDelete, post: vi.fn() },
  ApiError: MockApiError,
  TRIAL_EXPIRED_EVENT: "app:trial_expired",
}));

vi.mock("@/shared/lib/analytics", () => ({
  identifyUser: vi.fn(),
  resetIdentity: vi.fn(),
}));

vi.mock("@/shared/lib/analytics/installation", () => ({
  ensureInstallationForAuth: vi.fn(async () => ({})),
}));

vi.mock("@/features/anonymous/claim", () => ({
  claimAnonymousData,
}));

vi.mock("@/shared/lib/pushNotifications", () => ({
  syncPushIfGranted,
}));

const USER = { id: 13, email: "admin@easyhealth.art", name: "Admin" };

function Probe() {
  const { user, loading } = useAuth();
  return <div data-testid="probe">{loading ? "loading" : (user?.email ?? "anonymous")}</div>;
}

function renderProvider() {
  return render(
    <AuthProvider>
      <Probe />
    </AuthProvider>,
  );
}

beforeEach(() => {
  h.isNativePlatform = true;
  h.platform = "android";
  apiGet.mockReset();
  apiGet.mockResolvedValue(USER);
  apiDelete.mockReset();
  apiDelete.mockResolvedValue(undefined);
  syncPushIfGranted.mockReset();
  syncPushIfGranted.mockResolvedValue({ permissionState: "granted", registered: true });
  claimAnonymousData.mockReset();
  claimAnonymousData.mockResolvedValue(undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("AuthProvider push boot", () => {
  it("syncs push on an authenticated boot when isNativePlatform() lies but getPlatform()=android", async () => {
    h.isNativePlatform = false;
    h.platform = "android";

    renderProvider();

    await waitFor(() => expect(syncPushIfGranted).toHaveBeenCalledWith("auth_boot"));
    expect(syncPushIfGranted).toHaveBeenCalledTimes(1);
  });

  it("never syncs push on the web", async () => {
    h.isNativePlatform = false;
    h.platform = "web";

    renderProvider();

    await waitFor(() => expect(screen.getByTestId("probe")).toHaveTextContent(USER.email));
    expect(syncPushIfGranted).not.toHaveBeenCalled();
  });

  it("never syncs push without an authenticated session, even on Android", async () => {
    h.isNativePlatform = false;
    h.platform = "android";
    apiGet.mockRejectedValue(new MockApiError("unauthorized", 401));

    renderProvider();

    await waitFor(() => expect(screen.getByTestId("probe")).toHaveTextContent("anonymous"));
    expect(syncPushIfGranted).not.toHaveBeenCalled();
  });

  it("keeps the session usable when the push sync fails (best-effort, no unhandled rejection)", async () => {
    h.isNativePlatform = false;
    h.platform = "android";
    syncPushIfGranted.mockRejectedValue(new Error("push exploded"));
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const unhandled = vi.fn();
    process.on("unhandledRejection", unhandled);

    try {
      renderProvider();

      await waitFor(() => expect(syncPushIfGranted).toHaveBeenCalledWith("auth_boot"));
      // Auth boot completed and the user is still available to consumers.
      await waitFor(() => expect(screen.getByTestId("probe")).toHaveTextContent(USER.email));
      await waitFor(() => expect(consoleError).toHaveBeenCalled());
      await new Promise((r) => setTimeout(r, 0));
      expect(unhandled).not.toHaveBeenCalled();
    } finally {
      process.off("unhandledRejection", unhandled);
    }
  });

  it("does not re-sync on a rerender that does not change the authenticated identity", async () => {
    h.isNativePlatform = false;
    h.platform = "android";

    const { rerender } = renderProvider();
    await waitFor(() => expect(syncPushIfGranted).toHaveBeenCalledTimes(1));

    rerender(
      <AuthProvider>
        <Probe />
      </AuthProvider>,
    );

    await new Promise((r) => setTimeout(r, 0));
    expect(syncPushIfGranted).toHaveBeenCalledTimes(1);
  });
});
