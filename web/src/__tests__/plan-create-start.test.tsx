import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi, beforeEach } from "vitest";
import { CreateStart } from "@/features/plan-creation/screens/create-start";

const { mockTrackOnboardingEvent } = vi.hoisted(() => ({
  mockTrackOnboardingEvent: vi.fn(),
}));

vi.mock("@/shared/lib/onboarding-tracking", () => ({
  trackOnboardingEvent: mockTrackOnboardingEvent,
}));

describe("CreateStart", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("keeps quick and complete selectable", async () => {
    const user = userEvent.setup();
    const onSelect = vi.fn();

    render(<CreateStart onSelect={onSelect} />);

    await user.click(screen.getByRole("button", { name: /Completo/i }));
    await user.click(screen.getByRole("button", { name: /Continuar/i }));

    expect(onSelect).toHaveBeenCalledWith("complete");
    expect(mockTrackOnboardingEvent).toHaveBeenCalledWith(
      "onboarding_flow_selected",
      expect.objectContaining({
        onboardingFlow: "complete",
        metadata: { selected_option: "complete" },
      }),
    );
  });

  it("marks photo and chat as coming soon and prevents selection", async () => {
    const user = userEvent.setup();
    const onSelect = vi.fn();

    render(<CreateStart onSelect={onSelect} />);

    const photo = screen.getByRole("button", { name: /Pela sua foto/i });
    const chat = screen.getByRole("button", { name: /Conversar com a IA/i });

    expect(screen.getAllByText("EM BREVE")).toHaveLength(2);
    expect(screen.queryByText("Novo")).not.toBeInTheDocument();
    expect(photo).toBeDisabled();
    expect(chat).toBeDisabled();
    expect(photo).toHaveAttribute("aria-disabled", "true");
    expect(chat).toHaveAttribute("aria-disabled", "true");

    await user.click(photo);
    await user.click(chat);
    await user.click(screen.getByRole("button", { name: /Continuar/i }));

    expect(onSelect).toHaveBeenCalledWith("quick");
  });
});
