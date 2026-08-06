import { describe, it, expect } from "vitest";
import { GoogleAuthError, describeGoogleAuthError } from "@/shared/lib/googleAuth";

// Cancellation used to be inferred from /cancel/i over the code AND the message,
// so any plugin error whose text happened to mention "cancel" was filed as a
// user decision — silently removed from the failure counters and from Sentry.
// The contract is a code, and only a code.

describe("describeGoogleAuthError — cancellation", () => {
  it("recognises the plugin's documented USER_CANCELLED code", () => {
    const info = describeGoogleAuthError(
      new GoogleAuthError("Google Sign-In cancelled by user", "USER_CANCELLED"),
    );

    expect(info).toEqual({
      failure: "cancelled",
      category: "user_cancelled",
      errorCode: "USER_CANCELLED",
      reachedBackend: false,
    });
  });

  it("recognises the JS layer's lowercase 'cancelled' and normalises the code", () => {
    const info = describeGoogleAuthError(new GoogleAuthError("popup closed", "cancelled"));

    expect(info.category).toBe("user_cancelled");
    expect(info.errorCode).toBe("USER_CANCELLED");
  });

  it("does NOT treat a plugin failure as a cancellation because its message says 'cancelled'", () => {
    const info = describeGoogleAuthError(
      new GoogleAuthError("The request was cancelled by the provider", "plugin_login_failed"),
    );

    expect(info.category).toBe("provider_error");
    expect(info.failure).toBe("unknown");
  });

  it("does not read the message at all for a plain Error", () => {
    const info = describeGoogleAuthError(new Error("user cancelled the flow"));

    expect(info.category).toBe("unknown");
  });
});

describe("describeGoogleAuthError — where it broke", () => {
  it("files oauth_failed as a backend error, not as a plugin failure", () => {
    const info = describeGoogleAuthError(new GoogleAuthError("falha", "oauth_failed"));

    expect(info.category).toBe("backend_error");
    expect(info.reachedBackend).toBe(true);
  });

  it.each([
    ["consent_required", "consent_required"],
    ["account_deleted", "account_deleted"],
    ["invalid_token", "invalid_token"],
  ])("keeps the UI vocabulary for %s while categorising it as backend_error", (code, failure) => {
    const info = describeGoogleAuthError(new GoogleAuthError("nope", code));

    expect(info.failure).toBe(failure);
    expect(info.category).toBe("backend_error");
    expect(info.reachedBackend).toBe(true);
  });

  it.each(["missing_web_client_id", "plugin_init_failed"])(
    "separates the OAuth misconfiguration %s from a provider failure",
    (code) => {
      expect(describeGoogleAuthError(new GoogleAuthError("x", code)).category).toBe(
        "oauth_configuration_error",
      );
    },
  );

  it.each(["plugin_import_failed", "plugin_login_failed", "missing_id_token"])(
    "files %s as a provider error that never reached the backend",
    (code) => {
      const info = describeGoogleAuthError(new GoogleAuthError("x", code));

      expect(info.category).toBe("provider_error");
      expect(info.reachedBackend).toBe(false);
    },
  );

  it("distinguishes a timeout from a plain network failure", () => {
    const timeout = Object.assign(new Error("timed out"), { name: "TimeoutError" });

    expect(describeGoogleAuthError(timeout).category).toBe("timeout");
    expect(describeGoogleAuthError(new TypeError("fetch failed")).category).toBe("network_error");
    expect(describeGoogleAuthError(new GoogleAuthError("x", "exchange_failed")).category).toBe(
      "network_error",
    );
  });

  it("falls back to unknown without inventing a code", () => {
    expect(describeGoogleAuthError(undefined)).toEqual({
      failure: "unknown",
      category: "unknown",
      errorCode: "unknown",
      reachedBackend: false,
    });
  });
});
