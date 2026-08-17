import type { CapacitorConfig } from '@capacitor/cli';

// CAP_TARGET seleciona a plataforma sendo sincronizada. Os scripts ios:* o
// definem; sem ele o comportamento é exatamente o de sempre (Android remoto).
const target = process.env.CAP_TARGET ?? 'android';
const liveReloadUrl = process.env.CAP_LIVE_RELOAD_URL;

// REGRA INEGOCIÁVEL DO iOS: o release NÃO pode conter server.url.
//
// App Store 2.5.2 proíbe app que baixa e executa código remoto, e 4.2 rejeita
// site empacotado. O IPA precisa iniciar a partir dos assets que ele mesmo
// carrega. server.url no iOS existe SOMENTE para live reload em
// desenvolvimento, e é opt-in explícito via CAP_LIVE_RELOAD_URL.
//
// O Android segue no shell remoto, inalterado: mudar isso agora quebraria o
// app que já está publicado, e não é objetivo desta etapa.
function serverConfig(): CapacitorConfig['server'] {
  if (liveReloadUrl) {
    return { url: liveReloadUrl, cleartext: true };
  }

  if (target === 'ios') {
    // Sem server: o WKWebView carrega o bundle de webDir.
    return undefined;
  }

  return { url: 'https://easyhealth.art/?native_entry=1', cleartext: false };
}

const config: CapacitorConfig = {
  appId: 'com.EasyHealth.myapp',
  appName: 'Easy Health',
  // Android nunca usa webDir de verdade (carrega a URL remota), então 'public'
  // segue servindo de placeholder lá. O iOS aponta para o build do target
  // nativo, que é o que de fato vai dentro do IPA.
  webDir: target === 'ios' ? 'out-native' : 'public',
  server: serverConfig(),
  plugins: {
    SocialLogin: {
      providers: {
        google: true,
        facebook: false,
        // Ligado no PR 3, junto com o fluxo de Sign in with Apple.
        apple: false,
        twitter: false,
      },
    },
    SystemBars: {
      insetsHandling: 'css',
      style: 'DEFAULT',
      hidden: false,
    },
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert'],
    },
  },
};

export default config;
