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

// ── Crashlytics ────────────────────────────────────────────────────────────
// Mesmo canal, mesma falha: a flag existia em firebase.ts e era lida, mas sem
// ARG/ENV no Dockerfile e sem build arg no compose ela resolvia false em TODO
// bundle Docker, independente do .env do servidor.
//
// Default false de propósito, e é por isso que este bloco não reusa as
// asserções acima: Crashlytics é uma decisão de privacidade SEPARADA do
// Analytics e não deve ser ligada como efeito colateral dele.

const CRASHLYTICS_FLAG = "NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED";

describe(`web/Dockerfile — ${CRASHLYTICS_FLAG}`, () => {
  it("declara ARG e ENV", () => {
    expect(dockerfile).toMatch(new RegExp(`^ARG ${CRASHLYTICS_FLAG}(=|$)`, "m"));
    expect(dockerfile).toMatch(
      new RegExp(`^ENV ${CRASHLYTICS_FLAG}=\\$\\{${CRASHLYTICS_FLAG}\\}`, "m")
    );
  });

  it("declara o ARG ANTES do npm run build", () => {
    const argAt = dockerfile.indexOf(`ARG ${CRASHLYTICS_FLAG}`);
    const buildAt = dockerfile.indexOf("RUN npm run build");
    expect(argAt).toBeGreaterThan(-1);
    expect(argAt).toBeLessThan(buildAt);
  });

  it("default false — ligar coleta é decisão explícita, não herdada do Analytics", () => {
    expect(dockerfile).toContain(`ARG ${CRASHLYTICS_FLAG}=false`);
  });

  it("recusa valores que não sejam true/false", () => {
    // Um vazio ou um "True" resolveria silenciosamente para desligado — a
    // mesma armadilha que o guard do Analytics existe para fechar.
    expect(dockerfile).toContain(`RUN case "$${CRASHLYTICS_FLAG}" in`);
  });
});

describe(`docker-compose.prod.yml — ${CRASHLYTICS_FLAG}`, () => {
  const webBlock = composeProd.slice(
    composeProd.indexOf("\n  web:"),
    composeProd.indexOf("\n    ports:", composeProd.indexOf("\n  web:"))
  );

  it("conecta a flag em web.build.args com default false", () => {
    expect(webBlock).toContain(`${CRASHLYTICS_FLAG}: \${${CRASHLYTICS_FLAG}:-false}`);
  });

  it("não usa o :-vazio, que sobrescreveria o default do ARG", () => {
    expect(webBlock).not.toContain(`${CRASHLYTICS_FLAG}: \${${CRASHLYTICS_FLAG}:-}`);
  });
});

// ── Sentry ─────────────────────────────────────────────────────────────────
// Aqui o encanamento nunca faltou — faltava alguém checar se o valor estava no
// .env do servidor. Em 15-16/08 não estava, os builds saíram sem DSN, e quando
// foi preciso classificar um incidente não havia Sentry para consultar.
// Estas asserções travam as duas metades: o canal no build e o guard no deploy.

const SENTRY_DSN = "NEXT_PUBLIC_SENTRY_DSN";
const safeDeploy = readFileSync(
  path.join(REPO_ROOT, "scripts/production/safe_deploy.sh"),
  "utf8"
);

describe(`${SENTRY_DSN} — canal de build`, () => {
  it("tem ARG e ENV no Dockerfile, antes do build", () => {
    expect(dockerfile).toMatch(new RegExp(`^ARG ${SENTRY_DSN}(=|$)`, "m"));
    expect(dockerfile).toMatch(new RegExp(`^ENV ${SENTRY_DSN}=\\$\\{${SENTRY_DSN}\\}`, "m"));
    expect(dockerfile.indexOf(`ARG ${SENTRY_DSN}`))
      .toBeLessThan(dockerfile.indexOf("RUN npm run build"));
  });

  it("é passado como build arg no compose", () => {
    const webBlock = composeProd.slice(
      composeProd.indexOf("\n  web:"),
      composeProd.indexOf("\n    ports:", composeProd.indexOf("\n  web:"))
    );
    expect(webBlock).toContain(`${SENTRY_DSN}: \${${SENTRY_DSN}}`);
  });
});

describe(`${SENTRY_DSN} — guard de deploy`, () => {
  it("safe_deploy valida a presença antes de construir a imagem", () => {
    expect(safeDeploy).toContain("assert_sentry_dsn()");
    const defAt = safeDeploy.indexOf("assert_sentry_dsn()");
    const callAt = safeDeploy.indexOf("\nassert_sentry_dsn\n");
    const buildAt = safeDeploy.indexOf("compose build");
    expect(callAt).toBeGreaterThan(defAt);
    expect(callAt).toBeLessThan(buildAt);
  });

  it("falha o deploy quando ausente, em vez de apenas avisar", () => {
    const fn = safeDeploy.slice(
      safeDeploy.indexOf("assert_sentry_dsn()"),
      safeDeploy.indexOf("\n}", safeDeploy.indexOf("assert_sentry_dsn()"))
    );
    expect(fn).toContain("fail ");
  });

  it("nunca imprime o valor do DSN", () => {
    const fn = safeDeploy.slice(
      safeDeploy.indexOf("assert_sentry_dsn()"),
      safeDeploy.indexOf("\n}", safeDeploy.indexOf("assert_sentry_dsn()"))
    );
    // Só a presença. O próprio filtro do Sentry trata "dsn" como chave sensível.
    expect(fn).toContain("present: yes");
    expect(fn).not.toMatch(/log .*\$val/);
    expect(fn).not.toMatch(/echo .*\$val/);
  });
});
