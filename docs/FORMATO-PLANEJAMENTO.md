# FORMATO-PLANEJAMENTO.md

Especificação técnica do JSON v1.0 que o painel daRocha consome via botão "Importar Planejamento".

## Estrutura raiz


```json
{
  "version": "1.0",
  "client_slug": "slug-do-cliente",
  "month": "2026-06",
  "metadata": {
    "title": "Planejamento Junho 2026 — Nome do Cliente",
    "description": "Descrição temática do mês",
    "author": "daRocha Comunicação",
    "created_at": "2026-05-25"
  },
  "posts": [ /* array de posts */ ],
  "campaigns": [ /* array de campanhas */ ]
}
```



| Campo raiz | Tipo | Obrigatório | Notas |
|---|---|---|---|
| `version` | string | sim | Sempre `"1.0"` |
| `client_slug` | string | sim | Slug do cliente conforme cadastrado no painel |
| `month` | string | sim | `YYYY-MM` |
| `metadata` | objeto | recomendado | Título, descrição, autor, created_at |
| `posts` | array | sim | Pode ser vazio |
| `campaigns` | array | sim | Pode ser vazio |

## Post


```json
{
  "date": "2026-06-04",
  "time": "10:00",
  "external_id": "telecall-2026-05-mvno-lancamento",
  "title": "MVNO",
  "format": "Carrossel",
  "pillar": "Nome Exato do Pilar Cadastrado",
  "instagram": "Texto Instagram com \\n\\n quebras e #hashtags",
  "linkedin": "Texto LinkedIn (apenas se cliente tem LinkedIn habilitado)",
  "tiktok": "Texto TikTok (apenas se cliente tem TikTok habilitado)",
  "briefing_summary": "Resumo curto (1-2 frases) que aparece no card do post.",
  "briefing_full": {
    "format": "Carrossel 5 slides 1080x1350px (4:5) — Instagram e LinkedIn",
    "tone": "Profissional, consultivo",
    "texts": [
      { "label": "Capa", "text": "Título da capa" },
      { "label": "Slide 2", "text": "Conteúdo do slide" },
      { "label": "CTA Final", "text": "Chamada de ação" }
    ],
    "visual_ref": "Descrição da referência visual desejada.",
    "search_terms": "termos em inglês para banco de imagens",
    "reference_link": "https://www.istockphoto.com/search/2/image-film?phrase=exemplo"
  }
}
```



| Campo | Tipo | Obrigatório | Notas |
|---|---|---|---|
| `date` | string | sim | `YYYY-MM-DD`, **deve estar dentro do mês declarado** |
| `time` | string | sim | `HH:MM` (24h) |
| `external_id` | string | sim | Slug-style único por cliente (minúsculas, números, hífen). NUNCA mude depois de criado — é a chave que liga comentários e aprovações ao post entre re-imports |
| `title` | string | sim | Nome curto do post (max 30 chars). Substitui o pillar como identificador visual no calendário e em listagens |
| `format` | string | sim | Apenas: Post Estático, Carrossel, Reels, Story, Infográfico, Vídeo |
| `pillar` | string | sim | Pilar exato da lista válida do cliente |
| `instagram` | string | sim | Use `\n` para quebras de linha |
| `linkedin` | string | condicional | Apenas se cliente tem LinkedIn habilitado. Rejeita import se trouxer linkedin pra cliente sem essa plataforma. |
| `tiktok` | string | condicional | Apenas se cliente tem TikTok habilitado. Rejeita import se trouxer tiktok pra cliente sem essa plataforma. |
| `briefing_summary` | string | sim | 1-2 frases |
| `briefing_full` | objeto | sim | Detalhes (formato detalhado, tom, textos, ref visual) |
| `status` | string | não | `pending` (default), `approved`, `rejected` |

### briefing_full

| Campo | Obrigatório | Notas |
|---|---|---|
| `format` | sim | Detalhado, ex: "Reels 9:16 (20-25s)" |
| `tone` | sim | Tom da comunicação |
| `texts` | sim | Array de `{label, text}` com textos da arte |
| `visual_ref` | sim | Descrição da referência visual |
| `search_terms` | sim | Termos em inglês para banco de imagens |
| `reference_link` | sim | URL de referência |

## Como criar external_id

O `external_id` é uma chave estável que identifica unicamente cada post de um cliente. Ele é usado pelo painel pra:

- Atualizar posts já importados sem perder comentários, aprovações e mídias anexadas
- Distinguir posts entre múltiplos imports do mesmo mês
- Detectar quando um post foi removido do planejamento

REGRAS:
- Slug-style: apenas minúsculas (a-z), números (0-9) e hífen (-)
- Único por cliente (não precisa ser globalmente único no banco)
- ESTÁVEL: NUNCA mude depois de criado. Se mudar, o sistema enxerga como "post novo" e perde comentários
- Descritivo: deve ser legível e identificar o tema do post

PADRÃO RECOMENDADO:
{client-slug}-{ano-mes}-{tema-curto}

EXEMPLOS BONS:
- telecall-2026-05-cases-abertura
- telecall-2026-05-mvno-lancamento
- cna-taquara-2026-06-volta-aulas
- jr-hoteis-2026-06-dia-namorados

EXEMPLOS RUINS:
- telecall-2026-05-1 (não descritivo)
- abertura mês de cases (espaços e maiúsculas — formato inválido)
- Cases-Abertura (maiúsculas — formato inválido)
- post-1 (sem cliente nem mês)

## Plataformas por cliente

Cada cliente declara explicitamente quais plataformas usa (campo `platforms` na tabela clients).

| Cliente | Slug | Plataformas |
|---|---|---|
| Telecall | telecall | instagram + linkedin |
| CNA Taquara | cna-taquara | instagram + tiktok |
| CNA Queimados | cna-queimados | instagram + tiktok |
| JR Hotéis | jr-hoteis | instagram + tiktok |

REGRAS DE IMPORT:
- O JSON deve trazer copy APENAS das plataformas habilitadas do cliente
- Se o JSON trouxer plataforma não habilitada (ex: tiktok pra Telecall, linkedin pra CNA), o import é REJEITADO com erro claro
- Cada post precisa ter pelo menos UMA plataforma habilitada do cliente com copy preenchida
- Validação acontece tanto no painel (client-side) quanto na função SQL (server-side)

## Campaign

> **Schema Fase 3.** A campanha usa `networks[]` (redes de mídia paga) e `budget_cents`
> (inteiro em centavos). Os campos antigos `platform` (singular) e `budget_brl` (reais)
> **não são mais aceitos** — o painel rejeita o import se aparecerem.


```json
{
  "external_id": "telecall-camp-2026-06-leads-b2b",
  "name": "Nome da Campanha",
  "networks": ["meta", "google"],
  "description": "Descrição expandida da campanha",
  "objective": "Conversão (Lead Generation)",
  "format": "Multi-formato",
  "budget_cents": 500000,
  "start_date": "2026-06-01",
  "end_date": "2026-06-30",
  "briefing_full": { /* mesma estrutura do briefing_full de post */ },
  "ads": [ /* array de anúncios */ ]
}
```



| Campo | Tipo | Obrigatório | Notas |
|---|---|---|---|
| `external_id` | string | sim | Slug-style único por cliente (minúsculas, números, hífen). Convenção: `{client-slug}-camp-{ano-mes}-{tema}` (ex: `telecall-camp-2026-06-leads-b2b`). ESTÁVEL — liga comentários/aprovações entre re-imports |
| `name` | string | sim | |
| `networks` | array | sim | Lista **não-vazia** de redes de mídia paga. Cada rede deve estar habilitada pro cliente (`clients.ad_networks`). Substitui o antigo `platform` |
| `description` | string | recomendado | Descrição expandida |
| `objective` | string | recomendado | Ex: "Conversão (Lead Generation)" |
| `format` | string | recomendado | Ex: "Multi-formato", "Search Ads" |
| `budget_cents` | inteiro | não | Orçamento em **centavos** (`500000` = R$ 5.000,00). Opcional |
| `start_date` | string | sim | `YYYY-MM-DD` |
| `end_date` | string | não | `YYYY-MM-DD`. Opcional (campanha contínua); se presente, ≥ `start_date` |
| `briefing_full` | objeto | recomendado | Mesma estrutura de post |
| `ads` | array | sim | Pode ser vazio |

### Redes de mídia paga por cliente

Cada cliente declara quais redes de mídia paga usa (campo `ad_networks` na tabela `clients`).
As `networks` de cada campanha — e o `network` de cada anúncio — precisam estar nessa lista.

| Cliente | Slug | Redes (`ad_networks`) |
|---|---|---|
| Telecall | telecall | meta, linkedin, google |
| CNA Taquara | cna-taquara | meta, tiktok, google |
| CNA Queimados | cna-queimados | meta, tiktok, google |
| JR Hotéis | jr-hoteis | meta, tiktok, google |

Chaves válidas de rede: `meta`, `google`, `tiktok`, `linkedin`.

## Ad

> **Schema Fase 3.** Cada anúncio traz `external_id`, `network` (uma das redes da
> campanha) e `budget_cents` (inteiro em centavos, > 0).


```json
{
  "external_id": "telecall-camp-2026-06-leads-b2b-a1",
  "code": "A1",
  "network": "meta",
  "headline": "Título principal do anúncio",
  "description": "Copy completo do anúncio.",
  "format": "Reels Vertical 9:16",
  "placement": "Feed + Stories + Reels",
  "cta": "Saiba Mais",
  "budget_cents": 250000,
  "start_date": "2026-06-01",
  "end_date": "2026-06-30"
}
```



| Campo | Tipo | Obrigatório | Notas |
|---|---|---|---|
| `external_id` | string | sim | Slug-style único no JSON. Convenção: `{campaign_external_id}-{code}` (ex: `telecall-camp-2026-06-leads-b2b-a1`) |
| `code` | string | sim | ex: `"A1"`, `"B2"` |
| `network` | string | sim | Uma das redes declaradas em `networks` da campanha |
| `headline` | string | sim | |
| `description` | string | sim | |
| `format` | string | sim | |
| `placement` | string | recomendado | |
| `cta` | string | sim | |
| `budget_cents` | inteiro | sim | Em **centavos**, > 0 (`250000` = R$ 2.500,00) |
| `start_date` | string | não | `YYYY-MM-DD` (opcional) |
| `end_date` | string | não | `YYYY-MM-DD` (opcional; se presente, ≥ `start_date`) |

## Pilares válidos

Cada cliente tem sua **lista própria** de pilares cadastrados no painel.

Os pilares válidos para cada cliente estão nas Custom Instructions do Project respectivo do Claude.

⚠️ **Importante**: o nome do pilar no JSON precisa ser **exatamente igual** ao que está cadastrado no painel — incluindo acentos, maiúsculas e pontuação. Diferenças mínimas geram rejeição na importação.

## Formatos válidos


```
Post Estático
Carrossel
Reels
Story
Infográfico
Vídeo
```

**Formato padrão das artes**: 1080x1350px (4:5 vertical). Use essa dimensão como base no campo `briefing_full.format` salvo quando o formato exigir outra proporção (ex: Story 9:16, Reels 9:16).



## Validações que o painel aplica no upload

**Rejeita** o arquivo se:
- `version != "1.0"`
- `client_slug` não bate com o cliente selecionado no painel
- `month` não bate com o mês selecionado no painel
- Algum post com `date` fora do mês
- Algum pilar fora da lista oficial cadastrada
- Algum post sem `title` ou com `title` > 30 caracteres
- Algum post sem `external_id` ou com formato inválido (não-slug)
- Dois posts no mesmo JSON com o mesmo `external_id` (duplicação)
- Algum campo obrigatório vazio
- `start_date > end_date`
- Algum post traz campo de plataforma não habilitada do cliente (ex: linkedin pra cliente sem LinkedIn, tiktok pra cliente sem TikTok)
- Algum post não tem nenhuma plataforma habilitada do cliente preenchida
- **Campanha** com formato legado (`platform` ou `budget_brl` em vez de `networks[]` / `budget_cents`)
- **Campanha** sem `external_id`, com `external_id` não-slug, ou duplicado no JSON
- **Campanha** sem `networks`, ou com rede não habilitada pro cliente (`clients.ad_networks`)
- **Anúncio** sem `external_id`/`code`/`network`, com `network` fora das `networks` da campanha, ou `budget_cents` ausente/≤ 0

**Avisa** (não bloqueia):
- Posts em data + hora duplicados
- Mais de 30 posts no mês

## Comportamento do upsert idempotente (SQL 08)

A partir do SQL 08, o import usa `external_id` pra fazer upsert inteligente em vez de DELETE + INSERT:

| Cenário | Comportamento |
|---|---|
| Post no JSON existe no banco (mesmo external_id) | UPDATE — atualiza briefing/data/etc. PRESERVA id, status, comentários, reações, mídias anexadas |
| Post no JSON é novo (external_id não existe) | INSERT — cria post novo com status pending |
| Post no banco não está no JSON (e replace=TRUE) | DELETE — remove o post (e seus comentários/mídias via CASCADE) |

SALVAGUARDA: se um único import for deletar mais de 5 posts, a função retorna erro pedindo confirmação. Isso evita perda acidental de planejamento inteiro por importar JSON incompleto.

Se o usuário confirma "substituir" no painel mas alguns posts são apenas atualizações (mesmo external_id), eles são PRESERVADOS com seus comentários/aprovações.

### Payloads só-de-campanhas e o `replace`

O DELETE do modo `replace=true` age **apenas sobre posts** — campanhas e anúncios são sempre upsert (nunca deletados pelo import; o processamento de posts e campanhas é independente no resto).

⚠️ Como o `replace` apaga os posts do mês que **não estão** no JSON, um payload **só de campanhas** (`"posts": []`) com `replace=true` **apaga todos os posts já cadastrados no mês** (respeitando a salvaguarda de 5). Importe payloads só-de-campanhas com **`replace=false`** para não zerar o calendário editorial do mês.
