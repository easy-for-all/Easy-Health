// Camada mínima para desacoplar navegação interna do document do navegador.
//
// Na Web e no shell remoto do Android, `window.location.replace("/login")`
// funciona: existe um servidor Next do outro lado para responder por aquela
// rota. No shell nativo com bundle local não existe — o IPA tem um único
// index.html, e uma navegação dura para capacitor://localhost/login tentaria
// carregar um documento que não está lá.
//
// Este módulo é o adapter: o shell nativo registra o roteador client-side no
// boot, e todo o resto do código continua chamando a mesma função. Sem
// registro, o comportamento é exatamente o de antes.
//
// Navegação EXTERNA (checkout do Stripe, OAuth do Google) não passa por aqui —
// ela precisa ser uma navegação de documento de verdade, em qualquer
// plataforma. Ver navigateExternal.

export type NavigationMode = "push" | "replace";
export type InternalNavigator = (path: string, mode: NavigationMode) => void;

let internalNavigator: InternalNavigator | null = null;

export function setInternalNavigator(navigator: InternalNavigator | null): void {
  internalNavigator = navigator;
}

export function hasInternalNavigator(): boolean {
  return internalNavigator !== null;
}

export function navigateInternal(path: string, mode: NavigationMode = "push"): void {
  if (internalNavigator) {
    internalNavigator(path, mode);
    return;
  }

  if (typeof window === "undefined") return;
  if (mode === "replace") window.location.replace(path);
  else window.location.assign(path);
}

// Sai do app: checkout, OAuth em navegador, links de terceiros. Nunca é
// interceptada pelo roteador — o destino não é uma rota nossa.
export function navigateExternal(url: string): void {
  if (typeof window === "undefined") return;
  window.location.href = url;
}
