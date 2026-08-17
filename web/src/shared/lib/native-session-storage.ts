// Armazenamento seguro do token de sessão nativo.
//
// O bearer token ehs_... é uma credencial de autenticação. Ele NÃO pode ser
// guardado em localStorage, sessionStorage, IndexedDB, Capacitor Preferences,
// cookie legível por JS ou arquivo em texto puro — qualquer um deles é legível
// por um XSS e nenhum sobrevive a uma auditoria de App Review.
//
// No iOS o valor vai para o Keychain, via plugin nativo local
// (web/native-plugins/easyhealth-secure-storage). A política de acessibilidade
// escolhida é kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, documentada em
// KeychainStore.swift: não sincroniza via iCloud, fica preso ao aparelho, não é
// visível para outros apps e não pede Face ID a cada requisição.
//
// DELIBERADAMENTE SEM FALLBACK. Fora do shell nativo, todo método é inerte.
// Um fallback para localStorage seria pior que não ter armazenamento: daria a
// impressão de que a credencial está protegida quando não está.

export interface SecureStorage {
  get(options: { key: string }): Promise<{ value: string | null }>;
  set(options: { key: string; value: string }): Promise<void>;
  remove(options: { key: string }): Promise<void>;
}

// Implementação web inerte. Na web a sessão é o cookie httponly, que o JS nunca
// lê — não existe segredo para guardar aqui.
const INERT: SecureStorage = {
  get: async () => ({ value: null }),
  set: async () => undefined,
  remove: async () => undefined,
};

// Registro preguiçoso, não no topo do módulo.
//
// api.ts importa mobile-session, que importa este arquivo — ou seja, ele entra
// na árvore de praticamente todo teste. Chamar registerPlugin durante a carga
// do módulo quebrava qualquer suíte que mocka @capacitor/core parcialmente
// (várias mockam só `Capacitor`), transformando um detalhe de plugin nativo em
// falha de testes que não têm nada a ver com isso.
let plugin: SecureStorage | null = null;

async function secureStorage(): Promise<SecureStorage> {
  if (plugin) return plugin;
  try {
    const { registerPlugin } = await import("@capacitor/core");
    plugin = registerPlugin<SecureStorage>("EasyhealthSecureStorage", {
      web: async () => INERT,
    });
  } catch {
    plugin = INERT;
  }
  return plugin;
}

export interface NativeSessionStorage {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

export const nativeSessionStorage: NativeSessionStorage = {
  async get(key) {
    const { value } = await (await secureStorage()).get({ key });
    return value ?? null;
  },
  async set(key, value) {
    await (await secureStorage()).set({ key, value });
  },
  async remove(key) {
    await (await secureStorage()).remove({ key });
  },
};
