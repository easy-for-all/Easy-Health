import { render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AnalyticsTracker } from "@/shared/components/analytics-tracker";

const {
  mockIsNativeApp,
  mockTrackEvent,
  mockTrackConversion,
  mockTrackServerEvent,
} = vi.hoisted(() => ({
  mockIsNativeApp: vi.fn(() => false),
  mockTrackEvent: vi.fn(),
  mockTrackConversion: vi.fn(),
  mockTrackServerEvent: vi.fn(),
}));

vi.mock("@/shared/lib/analytics/context", () => ({
  isNativeApp: mockIsNativeApp,
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: mockTrackEvent,
  trackConversion: mockTrackConversion,
  trackServerEvent: mockTrackServerEvent,
}));

describe("AnalyticsTracker", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsNativeApp.mockReturnValue(false);
  });

  it("skips all landing analytics when configured to skip native", () => {
    mockIsNativeApp.mockReturnValue(true);

    render(
      <AnalyticsTracker
        eventName="landing_view"
        conversionLabel="conversion"
        serverEvent="landing_page_viewed"
        skipWhenNative
      />,
    );

    expect(mockTrackEvent).not.toHaveBeenCalled();
    expect(mockTrackConversion).not.toHaveBeenCalled();
    expect(mockTrackServerEvent).not.toHaveBeenCalled();
  });

  it("tracks normally outside native runtime", () => {
    render(
      <AnalyticsTracker
        eventName="landing_view"
        conversionLabel="conversion"
        serverEvent="landing_page_viewed"
        skipWhenNative
      />,
    );

    expect(mockTrackEvent).toHaveBeenCalledWith("landing_view", undefined);
    expect(mockTrackConversion).toHaveBeenCalledWith("conversion");
    expect(mockTrackServerEvent).toHaveBeenCalledWith("landing_page_viewed", {});
  });
});
