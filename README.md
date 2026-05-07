# Painel daRocha — Aprovação de Conteúdo

Painel HTML standalone para aprovação de planejamentos mensais de conteúdo, integrado ao Supabase. Desenvolvido pela daRocha Comunicação para gerenciar múltiplos clientes (Telecall, CNA Taquara, CNA Queimados, JR Hotéis).

🔗 **Painel em produção**: https://painel.darochacomunicacao.com.br

## Stack

- **Frontend**: `index.html` único (~300KB) com HTML + CSS + JS embutidos. Sem build, sem npm, sem dependências locais.
- **Backend**: Supabase (PostgreSQL + Auth + Storage + Realtime).
- **Deploy**: GitHub Pages → domínio próprio via CNAME.

## Estrutura do repositório


```
.
├── index.html                              # Painel completo
├── CNAME                                   # Domínio: painel.darochacomunicacao.com.br
├── CLAUDE.md                               # Instruções para sessões do Claude Code
├── README.md                               # Este arquivo
├── sql/                                    # Migrations do Supabase (em ordem cronológica)
│   ├── 01-supabase-setup.sql
│   ├── 02-supabase-create-users.sql
│   ├── 03-supabase-import-planning.sql
│   ├── 04-supabase-multiclient.sql
│   ├── 05-supabase-restricted-editor-access.sql
│   └── 06-supabase-fix-clients-rls.sql
└── docs/                                   # Documentação do projeto
    ├── FORMATO-PLANEJAMENTO.md             # Especificação do JSON v1.0
    ├── EXEMPLO-planejamento.md             # Exemplo Markdown
    ├── EXEMPLO-planejamento.json           # Exemplo JSON
    ├── SETUP-NOVO-CLIENTE.md               # Checklist para adicionar novo cliente
    └── instrucoes-clientes/                # Custom Instructions dos Projects do Claude
        ├── INSTRUCOES-PROJECT-TELECALL.md
        ├── INSTRUCOES-PROJECT-CNA-TAQUARA.md
        ├── INSTRUCOES-PROJECT-CNA-QUEIMADOS.md
        └── INSTRUCOES-PROJECT-JR-HOTEIS.md
```



## Funcionalidades

- Login multi-usuário via Supabase Auth (admin / editor / cliente)
- Calendário mensal com drag-and-drop de posts entre dias
- Aprovação/reprovação de posts e anúncios com comentários e reações
- Upload de mídia (Supabase Storage)
- Realtime: mudanças aparecem em todas as sessões abertas em ~1s
- Painel admin: gerenciar usuários, atribuir clientes, cadastrar novos clientes
- Multi-cliente com RLS rigorosa (cada usuário vê apenas seus clientes)
- Importação de planejamento mensal via JSON ou Markdown estruturado

## Workflow de planejamento mensal

1. Cliente daRocha abre Project do cliente no Claude (ex: "Planejamento Telecall")
2. Pede: "cria planejamento de junho/2026 com 12 posts"
3. Claude entrega Markdown estruturado para revisão
4. Após aprovação, Claude converte para JSON v1.0
5. Editor sobe o JSON no painel via botão "Importar Planejamento"
6. Cliente recebe acesso, aprova/comenta posts conforme cronograma

Documentação detalhada do formato em `docs/FORMATO-PLANEJAMENTO.md`.

## Setup do Supabase (recriação do zero)

Se um dia precisar recriar a instância:

1. Crie projeto novo em https://supabase.com/dashboard
2. SQL Editor → execute os arquivos em `sql/` **em ordem numérica** (01 → 06)
3. Storage → crie 3 buckets públicos: `media`, `attachments`, `client-logos`
4. Authentication → Users → cadastre os usuários iniciais
5. Atualize `SUPABASE_URL` e `SUPABASE_ANON_KEY` no `index.html`

## Workflow de desenvolvimento


```bash
cd ~/Desktop/darocha
claude
```


O Claude Code lê automaticamente o `CLAUDE.md` e fica pronto para:

- Editar o painel: "ajusta tal coisa no painel"
- Criar SQLs incrementais: "cria SQL pra adicionar coluna X em Y"
- Documentar mudanças: "atualiza o README com..."

Após cada sessão, peça "faz commit e push". O GitHub Pages atualiza o painel em produção em ~1 minuto.

## Documentação adicional

- `CLAUDE.md` — Como o Claude Code deve trabalhar neste repo
- `docs/FORMATO-PLANEJAMENTO.md` — Spec do JSON v1.0
- `docs/SETUP-NOVO-CLIENTE.md` — Como adicionar um novo cliente
- `docs/instrucoes-clientes/` — Custom Instructions de cada Project

## Licença

Projeto interno da daRocha Comunicação. Uso restrito.
