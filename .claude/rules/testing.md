# Testing Rules — Easy Health

## Objetivo
Reduzir regressões e erros antes de qualquer entrega.

## Regras obrigatórias
- Toda feature nova deve ter teste.
- Toda correção de bug deve ter teste cobrindo o bug.
- Não considerar uma tarefa finalizada sem rodar testes.
- Não alterar testes apenas para “passar”; corrigir a causa raiz.

## Backend
- Usar testes unitários para models/services.
- Usar testes de request para APIs Rails.
- Testar validações, regras de negócio e respostas HTTP.

## Frontend
- Usar testes para componentes críticos.
- Testar fluxos principais: login, onboarding, treino do dia, perfil e criação de treino.

## Regressão mínima
Antes de finalizar qualquer mudança, validar:
- login
- criação de conta
- onboarding
- perfil
- treino do dia
- criação/edição de treino
- troca de exercício
- registro de atividade