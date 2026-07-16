import { readFileSync } from "fs";
import path from "path";
import { describe, it, expect } from "vitest";
import {
  ALL_EVENTS,
  EVENT_SINKS,
  SERVER_TRACKED_EVENTS,
  TAXONOMY_VERSION,
  isKnownEvent,
} from "@/shared/lib/analytics/taxonomy";

// The frontend taxonomy is an auto-mirror of the backend single source of truth
// (api/config/analytics/events.yml). This test fails loudly if they drift.
function loadYaml(): { taxonomy_version: number; events: Record<string, { version: number; sinks: string[] }> } {
  const ymlPath = path.resolve(__dirname, "../../../api/config/analytics/events.yml");
  const raw = readFileSync(ymlPath, "utf8");

  const events: Record<string, { version: number; sinks: string[] }> = {};
  let taxonomyVersion = 0;
  for (const line of raw.split("\n")) {
    const tv = line.match(/^taxonomy_version:\s*(\d+)/);
    if (tv) taxonomyVersion = Number(tv[1]);
    // e.g. "  workout_completed: { version: 1, sinks: [server, ga4] }"
    const m = line.match(/^\s{2}([a-z_]+):\s*\{\s*version:\s*(\d+),\s*sinks:\s*\[([^\]]*)\]\s*\}/);
    if (m) {
      const [, name, version, sinksRaw] = m;
      events[name] = {
        version: Number(version),
        sinks: sinksRaw.split(",").map((s) => s.trim()).filter(Boolean),
      };
    }
  }
  return { taxonomy_version: taxonomyVersion, events };
}

describe("analytics taxonomy parity (TS ⇔ events.yml)", () => {
  const yaml = loadYaml();

  it("has the same taxonomy version", () => {
    expect(TAXONOMY_VERSION).toBe(yaml.taxonomy_version);
  });

  it("has exactly the same event names", () => {
    const yamlNames = Object.keys(yaml.events).sort();
    expect([...ALL_EVENTS].sort()).toEqual(yamlNames);
  });

  it("has the same sinks for every event", () => {
    for (const [name, meta] of Object.entries(yaml.events)) {
      const tsSinks = [...(EVENT_SINKS as Record<string, string[]>)[name]].sort();
      expect(tsSinks).toEqual([...meta.sinks].sort());
    }
  });

  it("derives server-tracked events consistently", () => {
    const yamlServer = Object.entries(yaml.events)
      .filter(([, m]) => m.sinks.includes("server"))
      .map(([n]) => n)
      .sort();
    expect([...SERVER_TRACKED_EVENTS].sort()).toEqual(yamlServer);
  });

  it("recognises known and unknown events", () => {
    expect(isKnownEvent("workout_completed")).toBe(true);
    expect(isKnownEvent("not_a_real_event")).toBe(false);
  });
});
