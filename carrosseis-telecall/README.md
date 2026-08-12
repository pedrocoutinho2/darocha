# Carrosséis Telecall — Saúde + Telefonia (agosto/2026)

Artes de dois carrosséis para Instagram e LinkedIn da **Telecall**, renderizadas
de HTML/CSS para PNG via Playwright. Sistema visual daRocha × Telecall (v2).

- **Post 1 — Vertical Saúde** (`post-1-vertical-saude/`) — 5 cards. `external_id: telecall-2026-08-vertical-saude`. Publicação 2026-08-05 10:00.
- **Post 2 — Telefonia Corporativa** (`post-2-telefonia-corporativa/`) — 6 cards. `external_id: telecall-2026-08-telefonia-corporativa`. Publicação 2026-08-11 14:00.

## Estrutura

```
carrosseis-telecall/
  post-1-vertical-saude/     index.html + style.css   (5 cards)
  post-2-telefonia-corporativa/ index.html + style.css (6 cards)
  assets/
    base.css                 tokens, @font-face, composições, componentes
    fontes/                  Poppins 700/800, Inter 300/400/500 (locais, sem CDN)
    logo/                    telecall-azul.png (branca via filter no fundo escuro)
    imagens/post-1/          slide-01.jpg ... (você coloca os JPGs licenciados)
    imagens/post-2/          slide-01.jpg ...
  render.js                  Playwright: screenshot por card + contact sheet
  IMAGENS.md                 briefing de busca + registro de licença
  output/                    PNGs gerados (git-ignored)
```

## Renderizar

Pré-requisitos já resolvidos no ambiente: Node + Playwright + Chromium.

```bash
npm install                       # playwright + fontes (@fontsource) + @tabler/icons

# Validação (placeholders tonais + termo de busca) e contact sheet:
node render.js --post=all --ratio=4x5

# Com as fotos reais, depois de colocá-las em assets/imagens/:
node render.js --post=all --ratio=all --images=real
```

Flags: `--post=1|2|all` · `--ratio=4x5|1x1|all` · `--images=placeholder|real` · `--contact=false`.

Renderiza em `deviceScaleFactor:2` e faz downscale para 1080px de largura (bordas e
tipografia nítidas). Saída em `output/post-N/<ratio>/slide-XX.png` e
`output/preview-post-N.png` (contact sheet).

## Imagens

Ver `IMAGENS.md`: uma linha por card com a cena, os termos de busca (EN) e a
composição. Nomeie os JPGs `slide-01.jpg`, `slide-02.jpg`, … dentro de
`assets/imagens/post-1/` e `post-2/`. Regras: sem rosto frontal, sem desfoque,
sem IA, nada de tons quentes que briguem com o navy.

## Legendas e publicação

Ver `LEGENDAS.md` (gerado na Etapa 4) para legendas de Instagram/LinkedIn,
data/hora e registro de IDs da Adobe Stock.
