import { describe, expect, it } from "vitest";
import {
  channelLabel,
  formatCount,
  formatInterval,
  formatRate,
  formatRateDetail,
  isDeferrable,
  makeStatusLabel,
  makeStatusTone,
  originLabel,
  pushStatusTone,
  schedulerStatusLabel,
  schedulerTone,
  type Rate,
  type SchedulerRow,
} from "../app/(app)/admin/events-communications/metrics";

const rate = (numerator: number, denominator: number, value: number | null): Rate => ({
  numerator,
  denominator,
  value,
});

describe("formatRate", () => {
  it("renders a percentage with one decimal", () => {
    expect(formatRate(rate(1, 2, 0.5))).toBe("50.0%");
  });

  // Zero of zero is the ABSENCE of a measurement. Rendering it as 0% would
  // invent a failure that never happened and send an operator hunting for it.
  it("renders an empty denominator as a dash, never 0%", () => {
    expect(formatRate(rate(0, 0, null))).toBe("—");
    expect(formatRate(null)).toBe("—");
    expect(formatRate(undefined)).toBe("—");
  });

  it("keeps a real zero distinguishable from no data", () => {
    expect(formatRate(rate(0, 10, 0))).toBe("0.0%");
  });

  it("shows the raw counts behind a rate", () => {
    expect(formatRateDetail(rate(3, 12, 0.25))).toBe("3 de 12");
  });
});

describe("formatCount", () => {
  it("groups thousands in pt-BR", () => {
    expect(formatCount(1234)).toBe("1.234");
  });

  it("renders missing data as a dash rather than zero", () => {
    expect(formatCount(null)).toBe("—");
    expect(formatCount(undefined)).toBe("—");
    expect(formatCount(0)).toBe("0");
  });
});

describe("formatInterval", () => {
  it("renders minutes, hours and days", () => {
    expect(formatInterval(900)).toBe("15min");
    expect(formatInterval(3600)).toBe("1h");
    expect(formatInterval(86400)).toBe("1d");
    expect(formatInterval(null)).toBe("—");
  });
});

describe("scheduler health", () => {
  const row = (overrides: Partial<SchedulerRow> = {}): SchedulerRow => ({
    key: "scheduled_workout_reminder",
    registered: true,
    status: "healthy",
    ...overrides,
  });

  it("treats a never-registered scheduler as a warning, not as healthy" , () => {
    expect(schedulerTone(row({ registered: false }))).toBe("warn");
    expect(schedulerStatusLabel(row({ registered: false }))).toBe("sem registro");
  });

  it("maps status to tone", () => {
    expect(schedulerTone(row({ status: "healthy" }))).toBe("ok");
    expect(schedulerTone(row({ status: "warning" }))).toBe("warn");
    expect(schedulerTone(row({ status: "critical" }))).toBe("bad");
    expect(schedulerTone(row({ status: "insufficient_data" }))).toBe("muted");
  });
});

describe("make status", () => {
  // dead_letter is a permanent contract failure. Showing it in the same tone as
  // "retrying" would let a broken payload look like work still in flight.
  it("does not present a dead letter as an in-flight retry", () => {
    expect(makeStatusTone("dead_letter")).toBe("bad");
    expect(makeStatusTone("retrying")).toBe("warn");
    expect(makeStatusLabel("dead_letter")).toBe("descartado");
  });

  it("marks acceptance as the only success", () => {
    expect(makeStatusTone("accepted_by_make")).toBe("ok");
    expect(makeStatusTone("pending")).toBe("muted");
  });

  it("passes an unknown status through instead of hiding it", () => {
    expect(makeStatusLabel("algo_novo")).toBe("algo_novo");
  });
});

describe("push status", () => {
  it("counts every delivered variant as success", () => {
    expect(pushStatusTone("provider_accepted")).toBe("ok");
    expect(pushStatusTone("partially_accepted")).toBe("ok");
    expect(pushStatusTone("opened")).toBe("ok");
  });

  it("separates rejection from skip", () => {
    expect(pushStatusTone("failed")).toBe("bad");
    expect(pushStatusTone("skipped")).toBe("warn");
    expect(pushStatusTone(null)).toBe("muted");
  });
});

describe("deferrable skips", () => {
  // quiet_hours is the one skip Make can retry later; an opt-out never is.
  it("only marks the reasons the backend declared deferrable", () => {
    expect(isDeferrable("quiet_hours", ["quiet_hours"])).toBe(true);
    expect(isDeferrable("global_opt_out", ["quiet_hours"])).toBe(false);
    expect(isDeferrable("quiet_hours", [])).toBe(false);
  });
});

describe("labels", () => {
  it("translates the known origins and channels", () => {
    expect(originLabel("backend_scheduler")).toBe("Scheduler");
    expect(originLabel("unknown")).toBe("Desconhecida");
    expect(channelLabel("email")).toBe("E-mail");
  });

  it("falls back to the raw key for something new", () => {
    expect(originLabel("watch")).toBe("watch");
    expect(channelLabel("sms")).toBe("sms");
  });
});
