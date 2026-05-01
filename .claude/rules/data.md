# Data Rules — Easy Health

## Banco
- PostgreSQL.
- Usar migrations versionadas.
- Evitar campos genéricos sem necessidade.

## Modelagem inicial
Domínios principais:
- users
- health_profiles
- workout_plans
- workout_days
- exercises
- workout_sessions
- activity_logs

## Princípios
- Dados devem ser simples de consultar.
- Evitar normalização excessiva no MVP.
- Manter histórico de atividades do usuário.
- Nunca apagar dados importantes sem soft delete ou confirmação clara.