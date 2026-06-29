import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.EasyHealth.myapp',
  appName: 'Easy Health',
  webDir: 'public',
  server: {
    url: 'https://easyhealth.art',
    cleartext: false,
  },
};

export default config;
