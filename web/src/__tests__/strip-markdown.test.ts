// Requires: vitest or jest + ts-jest
// Setup: npx vitest (add vitest to devDependencies), or configure jest with ts-jest
import { stripMarkdown } from "@/shared/utils/strip-markdown";

describe("stripMarkdown", () => {
  it("passes plain text through unchanged", () => {
    expect(stripMarkdown("Texto simples")).toBe("Texto simples");
  });

  it("removes bold asterisks", () => {
    expect(stripMarkdown("**Supino Reto** agora")).toBe("Supino Reto agora");
  });

  it("removes bold underscores", () => {
    expect(stripMarkdown("__Carga__ aumentada")).toBe("Carga aumentada");
  });

  it("removes italic asterisks", () => {
    expect(stripMarkdown("*atenção* ao movimento")).toBe("atenção ao movimento");
  });

  it("removes italic underscores", () => {
    expect(stripMarkdown("_foco_ na execução")).toBe("foco na execução");
  });

  it("removes inline code backticks", () => {
    expect(stripMarkdown("`completed_partial` status")).toBe("completed_partial status");
  });

  it("removes heading markers", () => {
    expect(stripMarkdown("## Treino de hoje")).toBe("Treino de hoje");
    expect(stripMarkdown("# Título")).toBe("Título");
    expect(stripMarkdown("### Subtítulo")).toBe("Subtítulo");
  });

  it("removes HTML tags", () => {
    expect(stripMarkdown("<strong>Supino</strong>")).toBe("Supino");
    expect(stripMarkdown("<br />linha")).toBe("linha");
  });

  it("removes unordered list markers", () => {
    expect(stripMarkdown("- item um")).toBe("item um");
    expect(stripMarkdown("* item dois")).toBe("item dois");
    expect(stripMarkdown("+ item três")).toBe("item três");
  });

  it("removes markdown links", () => {
    expect(stripMarkdown("[clique aqui](https://example.com)")).toBe("clique aqui");
  });

  it("handles mixed markdown in a sentence", () => {
    const input = "**Atenção:** Faça *3 séries* de `Supino Reto` com carga moderada.";
    const output = stripMarkdown(input);
    expect(output).toBe("Atenção: Faça 3 séries de Supino Reto com carga moderada.");
  });

  it("handles AI-style response with bold exercise name", () => {
    const input = "Boa série de **Agachamento Livre**! Mantenha 80kg e execute com controle.";
    expect(stripMarkdown(input)).toBe(
      "Boa série de Agachamento Livre! Mantenha 80kg e execute com controle."
    );
  });

  it("returns empty string unchanged", () => {
    expect(stripMarkdown("")).toBe("");
  });

  it("trims leading and trailing whitespace", () => {
    expect(stripMarkdown("  texto com espaços  ")).toBe("texto com espaços");
  });

  it("handles multiline text with headings and bullets", () => {
    const input = `## Resumo\n- Série 1: 15 kg\n- Série 2: **17.5 kg**\n`;
    const output = stripMarkdown(input);
    expect(output).not.toContain("##");
    expect(output).not.toContain("**");
    expect(output).toContain("15 kg");
    expect(output).toContain("17.5 kg");
  });
});
