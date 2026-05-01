# Backend Rules — Easy Health

## Stack
- Ruby on Rails API
- PostgreSQL
- Active Record

## Arquitetura
- Modular monolith.
- Controllers devem ser simples.
- Lógica de negócio deve ficar em services.
- Models não devem concentrar regras complexas demais.

## API
- Usar REST.
- Retornar JSON.
- Usar status HTTP corretos.
- Padronizar erros.

## Regras
- Nunca confiar em dados vindos do frontend.
- Sempre validar inputs no backend.
- Criar migrations claras.
- Evitar callbacks complexos em models.