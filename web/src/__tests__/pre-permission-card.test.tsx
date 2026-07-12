import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { PrePermissionCard } from "@/features/notifications/pre-permission-card";

const {
  mockGetState,
  mockEnsure,
  mockRequest,
  apiGet,
  apiPatch,
  toastShow,
  trackEventMock,
} = vi.hoisted(() => ({
  mockGetState: vi.fn(),
  mockEnsure: vi.fn(),
  mockRequest: vi.fn(),
  apiGet: vi.fn(),
  apiPatch: vi.fn(),
  toastShow: vi.fn(),
  trackEventMock: vi.fn(),
}));

vi.mock("@/shared/lib/pushNotifications", () => ({
  getPushPermissionState: mockGetState,
  ensurePushTokenRegistered: mockEnsure,
  requestPushPermissionAndRegister: mockRequest,
}));

vi.mock("@/shared/lib/api", () => ({
  api: { get: apiGet, patch: apiPatch },
}));

vi.mock("@/shared/lib/analytics", () => ({ trackEvent: trackEventMock }));

vi.mock("@/shared/components/ui/toast-provider", () => ({
  useToast: () => ({ show: toastShow }),
}));

const ANSWERED_KEY = "eh_push_prepermission_answered";

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
  apiGet.mockResolvedValue({
    workout_reminders_enabled: false,
    preferred_workout_period: "evening",
    preferred_workout_time: "19:00",
  });
  apiPatch.mockResolvedValue({});
});

async function enableButton() {
  return await screen.findByRole("button", { name: /Ativar lembretes/i });
}

describe("PrePermissionCard — permission already granted", () => {
  it("silently syncs the token and never shows the card", async () => {
    mockGetState.mockResolvedValue("granted");
    render(<PrePermissionCard />);

    await waitFor(() => expect(mockEnsure).toHaveBeenCalledWith("permission_granted"));
    expect(screen.queryByText(/Ativar lembretes/i)).not.toBeInTheDocument();
    expect(mockRequest).not.toHaveBeenCalled();
  });

  it("syncs even when the card was previously answered", async () => {
    localStorage.setItem(ANSWERED_KEY, "1");
    mockGetState.mockResolvedValue("granted");
    render(<PrePermissionCard />);

    await waitFor(() => expect(mockEnsure).toHaveBeenCalledWith("permission_granted"));
  });
});

describe("PrePermissionCard — opt-in flow", () => {
  it("enables reminders and marks answered only when the token is actually registered", async () => {
    mockGetState.mockResolvedValue("prompt");
    mockRequest.mockResolvedValue({ permissionState: "granted", registered: true });
    const user = userEvent.setup();
    render(<PrePermissionCard />);

    await user.click(await enableButton());

    await waitFor(() => expect(apiPatch).toHaveBeenCalledWith(
      "/api/v1/notification_preferences",
      { push_enabled: true, workout_reminders_enabled: true },
    ));
    expect(toastShow).toHaveBeenCalledWith(expect.stringContaining("Pronto!"), { variant: "good" });
    expect(localStorage.getItem(ANSWERED_KEY)).toBe("1");
  });

  it("does NOT claim success or persist answered when the backend sync fails", async () => {
    mockGetState.mockResolvedValue("prompt");
    mockRequest.mockResolvedValue({
      permissionState: "granted",
      registered: false,
      failureReason: "backend_sync_failed",
    });
    const user = userEvent.setup();
    render(<PrePermissionCard />);

    const btn = await enableButton();
    await user.click(btn);

    await waitFor(() =>
      expect(toastShow).toHaveBeenCalledWith(expect.stringContaining("não conseguimos concluir"), { variant: "hot" }),
    );
    expect(apiPatch).not.toHaveBeenCalled();
    expect(localStorage.getItem(ANSWERED_KEY)).toBeNull();
    // The card stays available for a retry and the button is not stuck in busy.
    expect(await enableButton()).toBeEnabled();
  });
});
