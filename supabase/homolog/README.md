# Homolog - estoque-orkan-homolog

Ambiente de homologacao para validar mudancas antes de aplicar em producao.

## Credenciais

Ver `loginSenhas.txt` (raiz do projeto, nao commitado).

- Project URL: `https://earxvgvwjutgegxeclfn.supabase.co`
- Anon public key: ver loginSenhas.txt

## Instalacao inicial (uma vez)

1. Abrir https://supabase.com/dashboard -> projeto `estoque-orkan-homolog` -> **SQL Editor**
2. Colar conteudo de `setup.sql` e executar (cria schema + policies + funcoes com A2/A3)
3. **Authentication -> Users -> Add user**:
   - `helena.alencar@orkan.com.br` / `Orkan@2020` (auto-confirm email)
   - `teste@orkan.com.br` / `Orkan@2020`
4. **Authentication -> Providers -> Email**: confirmar que esta habilitado
5. (Opcional) **Authentication -> URL Configuration**: adicionar `http://localhost:8000` aos redirect URLs

## Como acessar o app apontando pro homolog

Servir o HTML local:

```bash
cd "C:/Users/Engenharia/OneDrive - Orkan/Documentos/PROJETOS/ORKAN/ESTOQUE"
python -m http.server 8000
```

Abrir `http://localhost:8000/estoque-app.html` - o app detecta hostname e aponta automaticamente pro homolog. Banner amarelo "HOMOLOG" aparece no topo.

## Fluxo de mudanca

1. Rodar SQL nova em homolog primeiro
2. Testar no app servido localmente
3. Rodar testes Playwright (`dev/tests/`)
4. Se OK, aplicar mesma SQL em prod (`supabase/prod/README.md`)
5. Deploy do HTML em prod (processo atual do `HANDOFF-status.md`)

## Quando reinstalar do zero

Rodar `setup.sql` de novo. O `DROP TABLE` no inicio limpa tudo (cuidado: perde dados).
Util quando quiser testar cenarios limpos ou depois que o projeto pausa por inatividade.
