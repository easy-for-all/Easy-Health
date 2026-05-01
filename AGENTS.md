    # AGENTS.md — Easy Health

## Projeto
Easy Health é um webapp de treino e saúde com foco em experiência mobile-first, planejamento de treinos e registro simples de evolução.

## Stack
- Frontend: Next.js + React + TypeScript + Tailwind
- Backend: Ruby on Rails API
- Database: PostgreSQL
- Auth: Rails session/cookie
- Storage: S3-compatible

## Como trabalhar
- Sempre planeje antes de implementar mudanças médias ou grandes.
- Não implemente features grandes de uma vez.
- Trabalhe em pequenas etapas.
- Antes de codar, liste arquivos impactados e abordagem.
- Depois de implementar, rode lint/build/test quando possível.

## Regras principais
- Mobile-first.
- Código simples e legível.
- Evitar overengineering.
- Lógica de negócio deve ficar no backend Rails.
- Frontend deve ser organizado por features.
- Não implementar JWT customizado no MVP.
- Não commitar secrets, tokens ou `.env`.

## QA
Toda mudança relevante deve considerar:
- teste unitário
- teste de integração/API quando aplicável
- regressão dos fluxos principais:
  - login
  - onboarding
  - perfil
  - planejamento de treino
  - treino do dia
  - registro de atividade