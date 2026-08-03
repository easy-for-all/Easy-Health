import { beforeEach, describe, expect, it, vi } from "vitest";
import { clearDraft, loadDraft, saveDraft } from "@/features/plan-creation/draft";
import { buildInitialForm } from "@/features/plan-creation/types";

const KEY = "eh_onboarding_draft";

function form(overrides: Partial<ReturnType<typeof buildInitialForm>> = {}) {
  return { ...buildInitialForm(), ...overrides };
}

describe("plan creation draft", () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.useRealTimers();
  });

  it("returns null when nothing was saved", () => {
    expect(loadDraft()).toBeNull();
  });

  it("round-trips mode, step and answers", () => {
    saveDraft({ mode: "quick", stepId: "quick-place", form: form({ goal: "hypertrophy", age: "41" }) });

    const draft = loadDraft();
    expect(draft?.mode).toBe("quick");
    expect(draft?.stepId).toBe("quick-place");
    expect(draft?.form.goal).toBe("hypertrophy");
    expect(draft?.form.age).toBe("41");
  });

  it("clearDraft removes the draft", () => {
    saveDraft({ mode: "quick", stepId: "quick-goal", form: form() });
    clearDraft();
    expect(loadDraft()).toBeNull();
  });

  it("discards a draft older than 24h and removes the key", () => {
    saveDraft({ mode: "quick", stepId: "quick-time", form: form() });

    const stored = JSON.parse(window.localStorage.getItem(KEY) as string);
    stored.savedAt = Date.now() - 25 * 60 * 60 * 1000;
    window.localStorage.setItem(KEY, JSON.stringify(stored));

    expect(loadDraft()).toBeNull();
    expect(window.localStorage.getItem(KEY)).toBeNull();
  });

  it("keeps a draft that is still inside the 24h window", () => {
    saveDraft({ mode: "complete", stepId: "complete-place", form: form() });

    const stored = JSON.parse(window.localStorage.getItem(KEY) as string);
    stored.savedAt = Date.now() - 23 * 60 * 60 * 1000;
    window.localStorage.setItem(KEY, JSON.stringify(stored));

    expect(loadDraft()?.stepId).toBe("complete-place");
  });

  it("discards a draft written by another format version", () => {
    saveDraft({ mode: "quick", stepId: "quick-goal", form: form() });

    const stored = JSON.parse(window.localStorage.getItem(KEY) as string);
    stored.version = 99;
    window.localStorage.setItem(KEY, JSON.stringify(stored));

    expect(loadDraft()).toBeNull();
    expect(window.localStorage.getItem(KEY)).toBeNull();
  });

  it("discards malformed JSON instead of throwing", () => {
    window.localStorage.setItem(KEY, "{not json");
    expect(loadDraft()).toBeNull();
    expect(window.localStorage.getItem(KEY)).toBeNull();
  });

  it("discards a draft with an unknown mode", () => {
    saveDraft({ mode: "quick", stepId: "quick-goal", form: form() });

    const stored = JSON.parse(window.localStorage.getItem(KEY) as string);
    stored.mode = "photo";
    window.localStorage.setItem(KEY, JSON.stringify(stored));

    expect(loadDraft()).toBeNull();
  });

  // Um build que acrescente um campo ao WizardFormState precisa ler rascunhos
  // gravados antes dele sem entregar undefined para as telas.
  it("fills fields missing from an older draft with their defaults", () => {
    saveDraft({ mode: "quick", stepId: "quick-limits", form: form({ goal: "weight_loss" }) });

    const stored = JSON.parse(window.localStorage.getItem(KEY) as string);
    delete stored.form.session_duration_minutes;
    window.localStorage.setItem(KEY, JSON.stringify(stored));

    const draft = loadDraft();
    expect(draft?.form.goal).toBe("weight_loss");
    expect(draft?.form.session_duration_minutes).toBe(buildInitialForm().session_duration_minutes);
  });
});
