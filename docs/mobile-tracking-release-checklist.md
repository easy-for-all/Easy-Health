# Mobile Tracking — Release Checklist (aparelho Android real)

Package: `com.EasyHealth.myapp`. Executar em um aparelho Android físico com a build
**release** (AAB da esteira) ou uma build debug assinada. **Não marcar item como
validado sem execução real.**

## Pré-requisitos de flags (senão o tracking novo fica dark)
- Backend: `MOBILE_ANALYTICS_ENABLED=true`.
- Build/app: `NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED=true` e, para Firebase nativo,
  `NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED=true` / `_CRASHLYTICS_ENABLED=true` /
  `_PERFORMANCE_ENABLED=true`.

## Comandos ADB úteis (Windows/WSL → usar `adb.exe`)
```bash
adb.exe devices
adb.exe install app-release.aab            # ou: adb.exe install-multiple ...
adb.exe shell am start -n com.EasyHealth.myapp/.MainActivity
adb.exe logcat | grep -iE "Analytics|Firebase|Crashlytics|installation"
# Ativar o Firebase DebugView (eventos em tempo real no Console):
adb.exe shell setprop debug.firebase.analytics.app com.EasyHealth.myapp
# Desativar:
adb.exe shell setprop debug.firebase.analytics.app .none
# Forçar parada (cold start no próximo open):
adb.exe shell am force-stop com.EasyHealth.myapp
```

## Checklist
1. [ ] Instalar build limpa (app removido antes).
2. [ ] Abrir o app.
3. [ ] `installation_id` criado (log `installation_id_created` / Preferences `eh_installation_id`).
4. [ ] Registro no backend: `POST /api/v1/app/installations/register` → linha em `app_installations` (source=`register`).
5. [ ] `app_opened` emitido.
6. [ ] `session_started` (reason=`cold_start`).
7. [ ] Navegar entre telas → `screen_view` (nomes estáveis, sem id).
8. [ ] Cadastro/login → instalação associada ao usuário (`last_authenticated_at`, `user_id`).
9. [ ] Criar treino → `workout_created`.
10. [ ] Visualizar treino gerado.
11. [ ] Iniciar treino → `workout_started`.
12. [ ] Concluir treino → `workout_completed`.
13. [ ] Background por <30min e retornar → `app_resumed`, **mesma** sessão.
14. [ ] Background por >30min e retornar → novo `session_started` (reason=`resume_timeout`).
15. [ ] Atualizar versão do app → `app_updated` (from/to version).
16. [ ] Conceder permissão de push → token registrado (`device_tokens`).
17. [ ] Enviar push de teste (painel admin `push_test`).
18. [ ] Abrir o push → `POST push_dispatches/:id/opened` (ou `notification_deliveries/:id/opened`).
19. [ ] Deep link resolvido (rota alvo).
20. [ ] Iniciar treino após push → `workout_started_after_push` (janela 2h).
21. [ ] Concluir → `workout_completed_after_push`.
22. [ ] Firebase DebugView mostra os eventos nativos (Analytics ativo).
23. [ ] Backend: eventos em `product_analytics_events` com `platform="android"`.
24. [ ] Painel admin "App Android": instalações conhecidas > 1; cobertura sobe.
25. [ ] Sentry: erros JS com tags platform/app_version.
26. [ ] Crashlytics: crash controlado (rota admin protegida) aparece no Console.
27. [ ] Performance: traces de app start no Console.
28. [ ] Login social Google continua funcionando.
29. [ ] Validar que o mesmo evento **não** aparece duplicado em GA4 (web) e Firebase (nativo).
30. [ ] AAB release publicado no track interno sem regressão de push.
