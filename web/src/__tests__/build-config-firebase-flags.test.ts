import { readFileSync } from "fs";
import path from "path";
import { describe, it, expect } from "vitest";

// A causa raiz do incidente não estava no TypeScript: estava na ausência da
// variável no momento do `next build`. firebase.ts pode estar perfeito e ainda
// assim nenhum evento sai, porque NEXT_PUBLIC_* é inlined no build e o único
// canal para a imagem de produção é
// docker-compose.prod.yml (build.args) -> web/Dockerfile (ARG/ENV).
// Nenhum teste de unidade cobre esse canal — este cobre.

const FLAG = "NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED";

const WEB_DIR = path.resolve(__dirname, "../..");
const REPO_ROOT = path.resolve(WEB_DIR, "..");

const dockerfile = readFileSync(path.join(WEB_DIR, "Dockerfile"), "utf8");
const composeProd = readFileSync(path.join(REPO_ROOT, "docker-compose.prod.yml"), "utf8");

describe("web/Dockerfile", () => {
  it(`declara ARG e ENV para ${FLAG}`, () => {
    expect(dockerfile).toMatch(new RegExp(`^ARG ${FLAG}(=|$)`, "m"));
    expect(dockerfile).toMatch(new RegExp(`^ENV ${FLAG}=\\$\\{${FLAG}\\}`, "m"));
  });

  // Um ARG declarado depois do build não chega ao bundle: é a mesma falha, só
  // que mais difícil de enxergar no diff.
  it("declara o ARG ANTES do npm run build", () => {
    const argAt = dockerfile.indexOf(`ARG ${FLAG}`);
    const buildAt = dockerfile.indexOf("RUN npm run build");
    expect(argAt).toBeGreaterThan(-1);
    expect(buildAt).toBeGreaterThan(-1);
    expect(argAt).toBeLessThan(buildAt);
  });

  it("default true, para o caminho de produção nascer correto", () => {
    expect(dockerfile).toContain(`ARG ${FLAG}=true`);
  });

  // O guard pós-build procura `.env.<FLAG>` e não `process.env.<FLAG>`: o
  // Turbopack reescreve process para um shim (t.default.env.X), então procurar
  // por "process.env" não encontraria a leitura não resolvida e o guard passaria
  // verde com o bundle quebrado. Verificado contra um build real sem o ARG.
  const guard = dockerfile
    .slice(dockerfile.indexOf("RUN npm run build"))
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("#"))
    .join("\n");

  it("audita os chunks client para provar que a flag foi inlinada", () => {
    expect(guard).toContain(".next/static/chunks");
    expect(guard).toContain(`".env." + FLAG`);
  });

  it("não ancora a busca em 'process.env', que o Turbopack não emite", () => {
    expect(guard).not.toContain(`process.env.${FLAG}`);
  });

  // O grep do Alpine é o do busybox e não tem --include: ele sai com erro de uso,
  // que dentro de um `if` vira "não encontrou nada" e faz o guard passar sempre.
  // Foi assim que a primeira versão deste guard nasceu inócua.
  it("roda em node, não em grep --include (indisponível no busybox)", () => {
    expect(guard).toContain("RUN node -e");
    expect(guard).not.toContain("--include");
  });

  // Sem isto, um .next do host entra pelo COPY e o guard pode auditar chunks de
  // outro build.
  it("limpa o .next herdado do contexto antes de buildar", () => {
    const rmAt = dockerfile.indexOf("RUN rm -rf .next");
    const buildAt = dockerfile.indexOf("RUN npm run build");
    expect(rmAt).toBeGreaterThan(-1);
    expect(rmAt).toBeLessThan(buildAt);
  });
});

describe("docker-compose.prod.yml", () => {
  const webBlock = composeProd.slice(
    composeProd.indexOf("\n  web:"),
    composeProd.indexOf("\n    ports:", composeProd.indexOf("\n  web:"))
  );

  it(`conecta ${FLAG} em web.build.args`, () => {
    expect(webBlock).toContain("args:");
    expect(webBlock).toContain(`${FLAG}: \${${FLAG}:-true}`);
  });

  // `:-` (sem default) trataria ausente e vazio igual e injetaria "" no build arg,
  // sobrescrevendo o default do ARG e derrubando o guard do Dockerfile. O default
  // precisa estar aqui também, não só no Dockerfile.
  it("usa o default :-true, e não o :-vazio das flags de A/B", () => {
    expect(webBlock).not.toContain(`${FLAG}: \${${FLAG}:-}`);
  });
});
