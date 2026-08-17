import { describe, it, expect } from "vitest";
import fs from "fs";
import path from "path";

// Guarda do artefato que vai dentro do IPA.
//
// A regra que este arquivo protege: o app iOS tem que abrir a partir dos
// próprios assets. Um index.html ausente, ou um entrypoint apontando para
// easyhealth.art, transforma o app num shell de conteúdo remoto — que é o que
// as guidelines 2.5.2 e 4.2 rejeitam.
//
// Roda apenas quando `npm run build:native` já produziu o output; sem ele os
// testes são pulados, para que um `npm test` limpo não falhe por artefato
// ausente. O CI deve rodar build:native antes de test.

const OUT = path.resolve(__dirname, "../../out-native");
const built = fs.existsSync(path.join(OUT, "index.html"));
const describeBuilt = built ? describe : describe.skip;

describeBuilt("native build output", () => {
  const html = built ? fs.readFileSync(path.join(OUT, "index.html"), "utf8") : "";

  it("contains index.html", () => {
    expect(fs.existsSync(path.join(OUT, "index.html"))).toBe(true);
  });

  it("ships JS and CSS assets locally", () => {
    const assets = fs.readdirSync(path.join(OUT, "assets"));

    expect(assets.some((f) => f.endsWith(".js"))).toBe(true);
    expect(assets.some((f) => f.endsWith(".css"))).toBe(true);
  });

  it("mounts the app from a relative local entrypoint", () => {
    const entry = /<script[^>]+src="([^"]+)"/.exec(html)?.[1];

    expect(entry).toBeDefined();
    expect(entry!.startsWith("./")).toBe(true);
    expect(entry).toMatch(/\.js$/);
  });

  it("does NOT use easyhealth.art as the app entrypoint", () => {
    // Referência ao domínio da API dentro do JS é esperada e legítima — o Rails
    // segue remoto. O que não pode é o HTML carregar o app a partir de lá.
    const remoteEntry = /<script[^>]+src="https?:\/\/[^"]*easyhealth\.art/i.test(html);
    const remoteDoc = /<meta[^>]+http-equiv=["']refresh/i.test(html);

    expect(remoteEntry).toBe(false);
    expect(remoteDoc).toBe(false);
  });

  it("has a mount point for the client-side router", () => {
    expect(html).toContain('id="root"');
  });

  it("declares viewport-fit=cover so safe areas resolve", () => {
    expect(html).toMatch(/viewport-fit=cover/);
  });
});
