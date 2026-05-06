# CLAUDE.md — Painel daRocha

Instruções permanentes para sessões do Claude Code neste repo.

---

## O que é este projeto

Painel de aprovação de conteúdo da agência **daRocha Comunicação** para clientes (cliente atual de exemplo: Telecall). Permite que a agência publique calendário editorial e campanhas de tráfego pago, e que o cliente aprove/comente cada peça.

Hospedado como site estático (custom domain via `CNAME`). Backend é Supabase.

---

## Arquitetura — em uma frase

**Monólito HTML único** (`index.html`, ~6800 linhas) com HTML + CSS + JS vanilla inline, sem build step, conversando direto com Supabase via `@supabase/supabase-js@2` carregado via CDN.

### Arquivos
- `index.html` — toda a aplicação
- `README.md` — vazio (literalmente só `# darocha`)
- `CNAME` — domínio custom para deploy estático
- **Não existe** `package.json`, build script, framework, ou pasta de assets

### Dependências externas (CDN)
- `https://unpkg.com/lucide@latest` — ícones
- `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2` — cliente Supabase
- Google Fonts: Plus Jakarta Sans + Source Sans 3

---

## Dois modos de operação

A variável global `APP_MODE` alterna entre:

| Modo | Trigger | Persistência |
|---|---|---|
| `demo` | login com username (`admin`/`editor`/`cliente`) sem `@` | arrays em memória; reload perde tudo |
| `cloud` | login com email | Supabase real (Auth + Postgres + Storage + Realtime) |

Detectado em `loginForm submit` (~linha 2969). Quase toda função de mutação verifica `if (APP_MODE !== 'cloud') return;` antes de bater no banco.

**Credenciais demo** (hardcoded em `USERS`, ~linha 2313):
- `admin` / `admin123`
- `editor` / `editor123`
- `cliente` / `cliente123`

---

## Roles e permissões

Definidos em `PERMS` (~linha 2319). Três roles:

- **admin** — tudo: aprovar, comentar, upload, editar, gerenciar usuários, painel admin, deletar
- **editor** — como admin, **menos** gestão de usuários e admin panel
- **cliente** — só visualiza, aprova/reprova, comenta com anexos, reage com emoji. Não faz upload nem edita. Trancado no próprio `client_id`.

---

## Mapa do código (7 blocos `<script>` inline)

| Linhas | Bloco |
|---|---|
| 2255-2839 | Assets (logos SVG/base64), constantes (USERS, PERMS, PILLAR_COLORS, FORMATS), seed `posts[]`/`campaigns[]` (modo demo), estado global (`currentUser`, `currentClientFilter`, `calendarMonth`, etc.) |
| 2841-3332 | Utils (formatters, escapeHtml, sortPostsByDate, postsForMonth), toast/modal, auth (login/logout/`tryAutoLogin`/`enterApp`), `renderAll`, tabs, navegação de calendário |
| 3334-3724 | Aba Conteúdo: `renderContentTab`, sidebar de posts, `renderPostDetail`, edição inline (data/hora/formato/pilar), legendas IG+LinkedIn, briefing card |
| 3726-4472 | Comentários/replies/reações com emoji popover, drawer de briefing completo, lightbox de mídia, drag-and-drop entre dias do calendário, upload de mídia |
| 4474-5681 | Aba Tráfego Pago (cards de budget, cards de campanha expansíveis, cards de ad), painel administrativo (Usuários + Clientes), seletor de cliente no header, `DOMContentLoaded` |
| 5683-6120 | **Camada Supabase**: `loadCloudData()`, `normalizePost/Campaign/Comment`, objeto `cloudSync.*` (todas as mutações), `startRealtimeSubscriptions` com `debounceReload` 600ms |
| 6122-6800 | Importar Planejamento: modal de 4 etapas, parser de Markdown (`parseMarkdownPlanning`), validação, detecção de conflito, RPC `import_planning` |

Para localizar uma função use `grep -n "functionName" index.html`.

---

## Schema Supabase (inferido das queries — não há SQL no repo)

### Tabelas
- `profiles` — `id, name, email, role, client_id, avatar_url` (extends `auth.users`)
- `clients` — `id, name, slug, primary_color, logo_url, active`
- `user_clients` — many-to-many usuário × cliente
- `posts` — `id, client_id, date, time, format, pillar, instagram, linkedin, briefing_summary, briefing_full (jsonb), status`
- `media` — `id, client_id, post_id?, campaign_id?, ad_id?, storage_path, url, type, name, size_bytes, uploaded_by`
- `comments` — `id, post_id, author_id, text, created_at`
- `replies` — `id, comment_id, post_id, author_id, text, created_at`
- `reactions` — `id, comment_id?, reply_id?, post_id, author_id, emoji`
- `comment_attachments` — `id, comment_id?, reply_id?, storage_path, url, type, name`
- `campaigns` — `id, client_id, platform, name, description, objective, format, budget_cents, start_date, end_date, briefing_full (jsonb)`
- `ads` — `id, campaign_id, code, headline, description, format, placement, cta, budget_cents, start_date, end_date, status`
- `campaign_comments` — `id, campaign_id?, ad_id?, text, author_id, created_at`

### Storage buckets
- `media` — uploads de posts/campanhas/ads
- `attachments` — anexos de comentários
- `client-logos` — logos de cliente

### RPCs (PostgreSQL functions)
- `update_post_status(post_id, new_status)`
- `update_ad_status(ad_id, new_status)`
- `import_planning(p_payload, p_replace)` — bulk import mensal
- `check_planning_exists(p_client_id, p_month)`
- `admin_list_users()` — retorna profiles com clientes agregados
- `admin_update_user(p_user_id, p_name, p_email, p_role, p_client_ids)`
- `admin_create_client(...)`
- `admin_update_client(...)`

---

## Convenções importantes

### snake_case ↔ camelCase
Banco usa `snake_case`, código JS usa `camelCase`. **Sempre traduzir** ao escrever no banco. As funções `normalizePost`, `normalizeCampaign`, `normalizeComment`, `normalizeBriefingFull` (linhas 5761-5866) fazem o caminho inverso na leitura. Ao adicionar campos novos, atualize ambos.

### Legacy clientId
Posts antigos sem `client_id` assumem **Telecall = 1** (`postsForMonth`, linha 2915; `campaignsForClient`, linha 2926). Mantenha esse fallback ao mexer em filtros.

### Cliente role é trancado
Em `enterApp` (linha 3075): se `currentUser.role === 'cliente'`, o `currentClientFilter` é forçado para o próprio `clientId` e o seletor de cliente vira fixo (sem dropdown). RLS no Supabase já garante isso no servidor — não remova essa proteção do front também.

### `TODAY_REF = '2026-04-15'`
Constante na linha 2351 simula "hoje" pro destaque do calendário (porque os dados de exemplo estão em 2026). `buildCalendar` usa essa data quando o mês exibido é abril/2026; senão usa `Date.now()`.

### Anon key e URL inline
Em 2274-2275 — **isso é intencional**. RLS no banco protege os dados. Não troque por env vars (não há build step).

### Renderização
Tudo é `innerHTML` + `lucide.createIcons()` para reativar ícones após cada render. Sempre chame `lucide.createIcons()` depois de injetar HTML novo com `<i data-lucide="...">`.

### Realtime
`startRealtimeSubscriptions` escuta `postgres_changes` em todas as tabelas principais e chama `debounceReload` (600ms). Mutações otimistas locais não são feitas — o padrão é: chamar `cloudSync.X` → realtime detecta → `reloadFromCloud` repinta tudo.

---

## Como testar mudanças

Não há `dev server`, build, lint, ou test suite. Para testar:

1. Abrir `index.html` direto no navegador (`open index.html`) ou servir com `python3 -m http.server`
2. Login demo (admin/admin123) para iterar sem mexer no Supabase
3. Login cloud para validar com banco real
4. Para mudanças de schema: aplicar no Supabase via MCP tools (`mcp__claude_ai_Supabase__*`) ou painel web

**Não rode build steps** — não há nenhum. Não tente adicionar webpack/vite/etc. A escolha por monólito é deliberada.

---

## O que evitar

- **Não fragmentar** o `index.html` em arquivos separados sem o usuário pedir explicitamente. O monólito é a arquitetura escolhida.
- **Não adicionar build step, framework, ou bundler.**
- **Não criar `.md`** ou outros docs sem o usuário pedir.
- **Não trocar fetch direto por uma camada de abstração** — `cloudSync.*` já é a camada.
- **Não otimizar prematuramente** — a página renderiza tudo via `innerHTML`; está bom assim na escala atual.
- **Não remover o modo `demo`** — é útil para iterar UI sem tocar no banco.

---

## Quando o usuário pede uma mudança

1. Achar a função relevante via `grep -n` no `index.html`
2. Confirmar se a mudança afeta os dois modos (demo + cloud) ou só um
3. Se mexe em dado persistido: atualizar tanto o `normalize*` (leitura) quanto `cloudSync.*` (escrita)
4. Se adiciona campo novo no banco: aplicar migration via Supabase MCP
5. Verificar permissões — toda ação deveria conferir `PERMS[currentUser.role].canX`
