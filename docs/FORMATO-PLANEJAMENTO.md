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
  "title": "MVNO",
  "format": "Carrossel",
  "pillar": "Nome Exato do Pilar Cadastrado",
  "instagram": "Texto Instagram com \\n\\n quebras e #hashtags",
  "linkedin": "Texto LinkedIn mais corporativo",
  "briefing_summary": "Resumo curto (1-2 frases) que aparece no card do post.",
  "briefing_full": {
    "format": "Carrossel 5 slides — Instagram e LinkedIn",
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
| `title` | string | sim | Nome curto do post (max 30 chars). Substitui o pillar como identificador visual no calendário e em listagens |
| `format` | string | sim | Apenas: Post Estático, Carrossel, Reels, Story, Infográfico, Vídeo |
| `pillar` | string | sim | Pilar exato da lista válida do cliente |
| `instagram` | string | sim | Use `\n` para quebras de linha |
| `linkedin` | string | sim | |
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

## Campaign


```json
{
  "platform": "meta",
  "name": "Nome da Campanha",
  "description": "Descrição expandida da campanha",
  "objective": "Conversão (Lead Generation)",
  "format": "Multi-formato",
  "budget_brl": 5000.00,
  "start_date": "2026-06-01",
  "end_date": "2026-06-30",
  "briefing_full": { /* mesma estrutura do briefing_full de post */ },
  "ads": [ /* array de anúncios */ ]
}
```



| Campo | Tipo | Obrigatório | Notas |
|---|---|---|---|
| `platform` | string | sim | `linkedin`, `meta` ou `google` (minúsculas) |
| `name` | string | sim | |
| `description` | string | sim | Descrição expandida |
| `objective` | string | sim | Ex: "Conversão (Lead Generation)" |
| `format` | string | sim | Ex: "Multi-formato", "Search Ads" |
| `budget_brl` | número | sim | Em reais (`6000.00` = R$ 6.000,00) |
| `start_date` | string | sim | `YYYY-MM-DD` |
| `end_date` | string | sim | `YYYY-MM-DD` |
| `briefing_full` | objeto | sim | Mesma estrutura de post |
| `ads` | array | sim | Pode ser vazio |

## Ad


```json
{
  "code": "A1",
  "headline": "Título principal do anúncio",
  "description": "Copy completo do anúncio.",
  "format": "Reels Vertical 9:16",
  "placement": "Feed + Stories + Reels",
  "cta": "Saiba Mais",
  "budget_brl": 2500.00,
  "start_date": "2026-06-01",
  "end_date": "2026-06-30"
}
```



| Campo | Tipo | Obrigatório |
|---|---|---|
| `code` | string | sim — ex: `"A1"`, `"B2"` |
| `headline` | string | sim |
| `description` | string | sim |
| `format` | string | sim |
| `placement` | string | recomendado |
| `cta` | string | sim |
| `budget_brl` | número | sim |
| `start_date` | string | sim |
| `end_date` | string | sim |

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



## Validações que o painel aplica no upload

**Rejeita** o arquivo se:
- `version != "1.0"`
- `client_slug` não bate com o cliente selecionado no painel
- `month` não bate com o mês selecionado no painel
- Algum post com `date` fora do mês
- Algum pilar fora da lista oficial cadastrada
- Algum post sem `title` ou com `title` > 30 caracteres
- Algum campo obrigatório vazio
- `budget_brl` negativo
- `start_date > end_date`

**Avisa** (não bloqueia):
- Posts em data + hora duplicados
- Mais de 30 posts no mês

## Substituição de mês existente

Se importar para um mês que já tem dados, o painel pergunta:

> "Já existe planejamento para [Mês] [Ano] (X posts, Y campanhas). Substituir tudo?"

Confirmando, **apaga** todos os posts/campanhas/comentários/mídias daquele mês e **insere** os novos. Operação atômica (rollback se falhar).
