import { describe, it, expect } from "vitest";
import {
  formatAdsRatio,
  formatBRL,
  formatConversions,
  formatCount,
  formatMetric,
  syncTone,
  type Metric,
} from "@/app/(app)/admin/android-acquisition/metrics";

function metric(overrides: Partial<Metric> = {}): Metric {
  return {
    value: 50,
    numerator: 1,
    denominator: 2,
    sample_size: 2,
    status: "complete",
    definition: "test_v1",
    ...overrides,
  };
}

describe("formatBRL", () => {
  it("renders an em dash for a missing value instead of R$ 0,00", () => {
    // CPI with no installs is "no denominator", never "free acquisition".
    expect(formatBRL(null)).toBe("—");
    expect(formatBRL(undefined)).toBe("—");
  });

  it("formats a real amount in pt-BR", () => {
    expect(formatBRL(12.5)).toContain("12,50");
  });
});

describe("formatConversions", () => {
  it("shows a whole number without decimal noise", () => {
    expect(formatConversions(12)).toBe("12");
  });

  it("keeps two decimals for a fractional attributed conversion", () => {
    // Attribution models produce fractions; rounding 0.83 up would invent a
    // conversion Google never attributed.
    expect(formatConversions(0.83)).toBe("0,83");
  });

  it("renders an em dash when there is no value", () => {
    expect(formatConversions(undefined)).toBe("—");
  });
});

describe("formatCount", () => {
  it("keeps a real zero as zero", () => {
    // Zero attributed sign_ups on a new campaign is a legitimate zero.
    expect(formatCount(0)).toBe("0");
  });
});

describe("formatMetric", () => {
  it("renders an em dash when there is nothing to divide by", () => {
    expect(formatMetric(metric({ status: "no_coverage", denominator: 0, value: 0 }))).toBe("—");
  });

  it("renders the percentage when the metric has coverage", () => {
    expect(formatMetric(metric({ value: 42.5 }))).toBe("42,5%");
  });
});

describe("formatAdsRatio", () => {
  it("renders an em dash when the ratio is absent", () => {
    expect(formatAdsRatio(null)).toBe("—");
  });

  it("renders the percentage when present", () => {
    expect(formatAdsRatio({ value: 25, numerator: 2, denominator: 8 })).toBe("25%");
  });
});

describe("syncTone", () => {
  it("warns only when the data is old or the sync failed", () => {
    expect(syncTone("ok")).toBe("ok");
    expect(syncTone("stale")).toBe("warn");
    expect(syncTone("error")).toBe("warn");
  });

  it("does not treat a missing configuration as a failure", () => {
    expect(syncTone("not_configured")).toBe("muted");
    expect(syncTone("never_synced")).toBe("muted");
  });
});
