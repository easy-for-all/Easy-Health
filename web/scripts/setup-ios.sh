#!/usr/bin/env bash
# Regenera o projeto iOS a partir do zero, como setup-android.sh faz para o
# Android. `ios/` é descartável e não versionado: o que é versionado são os
# assets do bundle (out-native), o plugin nativo local e esta receita.
#
# Exige macOS com Xcode. Não roda em Linux/WSL — o Capacitor consegue copiar o
# template, mas nada depois disso funciona.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERRO: o projeto iOS só pode ser gerado no macOS com Xcode." >&2
  echo "      No Linux/WSL, use 'npm run build:native' para validar o bundle." >&2
  exit 1
fi

echo "==> Build do bundle nativo (assets locais que vão dentro do IPA)"
npm run build:native

if [[ ! -f "out-native/index.html" ]]; then
  echo "ERRO: out-native/index.html não foi gerado. O IPA precisa dele para abrir." >&2
  exit 1
fi

if [[ ! -d "ios" ]]; then
  echo "==> Criando o projeto iOS (Swift Package Manager)"
  CAP_TARGET=ios npx cap add ios --packagemanager SPM
fi

echo "==> Sincronizando web assets e plugins nativos"
CAP_TARGET=ios npx cap sync ios

# Guarda de release. Um server.url no target iOS transforma o app em shell de
# conteúdo remoto, que é exatamente o que as guidelines 2.5.2 e 4.2 rejeitam.
if grep -rq '"url"' ios/App/App/capacitor.config.json 2>/dev/null; then
  echo "ERRO: capacitor.config.json do iOS contém server.url." >&2
  echo "      Confira se CAP_TARGET=ios estava setado e se CAP_LIVE_RELOAD_URL está vazio." >&2
  exit 1
fi

echo
echo "Pronto. Abra o Xcode com:  npm run ios:open"
echo "No Xcode: Team -> Bundle Identifier -> Signing & Capabilities -> device -> Run."
