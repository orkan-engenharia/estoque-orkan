# Prod - estoque-orkan

Banco de dados de producao. **Nao roda setup.sql aqui** (dropa tabelas).

## Credenciais

- Project URL: `https://rpumyrlovwtwssevjbsp.supabase.co`
- Acesso ao dashboard: ver `loginSenhas.txt`

## Fluxo para aplicar migrations

1. Validar primeiro em homolog (ver `supabase/homolog/README.md`)
2. Rodar testes Playwright contra homolog - devem passar
3. Abrir https://supabase.com/dashboard -> projeto `estoque` -> **SQL Editor**
4. Colar a migration de `supabase/migrations/NNN-descricao.sql`
5. Executar
6. Verificar no app em producao que nao quebrou nada

## Migrations pendentes

| Migration | Descricao | Aplicada em prod? |
|-----------|-----------|-------------------|
| `001-a2-a3-move-inventory-security.sql` | Endurece `move_inventory` (search_path fixo + auth.uid()) | NAO |

## Checklist antes de aplicar em prod

- [ ] Migration rodou sem erro em homolog
- [ ] Testes Playwright passaram contra homolog
- [ ] Teste manual de cenario feliz + pelo menos um edge case
- [ ] Backup do banco (Supabase faz automatico, mas confirmar no dashboard)
- [ ] Comunicar o time se a janela de deploy exige downtime (geralmente nao exige)

## Rollback

Cada migration deve ser idempotente (usar `CREATE OR REPLACE`, `IF NOT EXISTS`).
Para reverter a 001: rodar `supabase/functions.sql` original no SQL Editor - ele restaura
a versao anterior do `move_inventory`.
