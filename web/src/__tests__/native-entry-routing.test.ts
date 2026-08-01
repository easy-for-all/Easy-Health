import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { proxy } from "@/proxy";

describe("native entry routing", () => {
  it("rewrites the Android native entry query to the lightweight route", () => {
    const response = proxy(new NextRequest("https://easyhealth.art/?native_entry=1"));

    expect(response.headers.get("x-middleware-rewrite")).toBe("https://easyhealth.art/native-entry");
  });

  it("leaves the public landing root on the normal route", () => {
    const response = proxy(new NextRequest("https://easyhealth.art/"));

    expect(response.headers.get("x-middleware-rewrite")).toBeNull();
    expect(response.headers.get("location")).toBeNull();
  });
});
