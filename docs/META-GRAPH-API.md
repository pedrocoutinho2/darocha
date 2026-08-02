# Integração Meta Graph API — Publicação no Instagram

## Estado
P1 (validação manual) concluído em 01/08/2026. Publicação de teste real
realizada no IG da Telecall via Graph API Explorer (container → publish).

## App Meta
- Nome: PainelDaRocha
- App ID: 27921103514168187
- Caso de uso: Instagram — setup "API com login do Facebook"
- Modo: desenvolvimento (App Review/Advanced Access pendente — necessário
  antes de escalar; prazo típico 2-4 semanas)

## System User
- ID: 122096328525427656
- Token: sem expiração, guardado FORA do repo (secrets do Supabase no P2)
- Escopos: instagram_basic, instagram_content_publish, pages_show_list,
  business_management
- Ativos atribuídos: páginas Telecall, JR Hotéis, CNA Taquara, CNA Queimados

## Mapeamento de contas
| Cliente | Página FB (id) | ig-user-id |
|---|---|---|
| Telecall | 362038470562529 | 17841407987295125 |
| CNA Taquara | 1893417677425165 | 17841416803645638 |
| CNA Queimados | 141067015953699 | 17841418328114858 |
| JR Hotéis | 204866786694387 | 17841423248731728 |

Nota: no Business Manager existem duplicatas "CNA Idiomas Queimados" e
"CNA Queimados/RJ" sem IG vinculado — a página oficial do Queimados é a de
id 141067015953699.

## Fluxo de publicação validado
1. POST /{ig-user-id}/media?image_url={URL_JPEG_PUBLICA}&caption={legenda}
   → retorna creation_id (container expira em 24h)
2. POST /{ig-user-id}/media_publish?creation_id={creation_id}
   → retorna media id publicado

Restrições: image_url deve ser JPEG público, proporção entre 4:5 e 1.91:1,
recomendado 1080px+ (padrão do painel 1080x1350 é compatível).
Host: graph.facebook.com (NÃO graph.instagram.com — host do outro setup).

## Roadmap
- P2: Edge Function publish-instagram + botão no painel (imagem única)
- P3: carrossel + vídeo/Reels
- App Review antes de uso em produção contínua

---

REGRA ABSOLUTA: nenhum token, chave ou credencial neste doc.
