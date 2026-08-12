---
name: imagens-para-artes
description: Busca, cura, baixa e registra a licença de fotos para artes de social media e páginas de site (carrosséis, posts estáticos, heroes). Varre Adobe Stock, Pexels, Unsplash, Pixabay e Openverse de uma vez, aplica as regras fotográficas da marca do cliente, entrega um shortlist para aprovação e só então baixa em alta com nomenclatura slide-0X.jpg e registro de licença. Use SEMPRE que o pedido envolver imagem de banco, foto de stock, "buscar imagens para o carrossel", "preencher os slots de imagem", IMAGENS.md, curadoria fotográfica ou qualquer arte que precise de foto antes de renderizar. Use também quando o usuário reclamar que não consegue baixar imagens ou que o banco está bloqueado.
---

# Imagens para artes

Fluxo padrão da daRocha para colocar foto de banco dentro de arte, sem
retrabalho de licença e sem quebrar as regras visuais do cliente.

## Antes de qualquer busca

1. **Leia o perfil da marca** em `references/` (ex: `references/telecall.md`).
   As regras fotográficas de cada cliente são eliminatórias, não sugestões.
   Se o cliente não tiver arquivo de perfil, pergunte as regras antes de buscar
   e crie o arquivo ao final.
2. **Cheque o acervo já licenciado.** Rode `python scripts/bancos.py licencas`
   para ler o registro consolidado. Se alguma imagem já comprada atende o card,
   reuse: no Adobe Stock, relicenciar um asset já adquirido apenas renova a URL
   e não consome crédito novo. Isso também evita a mesma foto aparecer em duas
   páginas diferentes do mesmo cliente.
3. **Confirme as chaves de API.** Rode `python scripts/bancos.py doctor`. Ele
   diz quais bancos estão ativos nesta máquina. Se faltar chave, siga
   `references/setup.md`.

## Fluxo

### Etapa 1 — Definir os cards

Se existir um `IMAGENS.md` (gerado pelo prompt de carrossel), use-o como fonte:
cada card traz número, cena desejada, termos de busca em inglês e padrão de
composição. Se não existir, escreva um antes de buscar. Nunca busque no chute.

Regra de query: **inglês, 2 a 4 palavras**. Português rende resultado pobre em
todos os bancos. `fiber optic technician` funciona; `técnico instalando fibra
óptica em empresa` não.

### Etapa 2 — Shortlist

```bash
python scripts/bancos.py buscar "fiber optic technician" --n 12 --out ./preview/card-03
```

Isso varre todos os bancos disponíveis em paralelo, baixa as miniaturas para a
pasta indicada e escreve um `resultados.json` com id, banco, autor, licença,
dimensões e URL. Miniatura é grátis e não licencia nada.

Depois **olhe as miniaturas** (leia os arquivos como imagem) e descarte o que
violar o perfil da marca antes de mostrar ao usuário. O filtro é seu, não do
banco. Apresente de 2 a 3 finalistas por card, com o motivo da escolha em uma
linha, e espere aprovação.

Para Adobe Stock, use o MCP da Adobe na mesma etapa: `adobe_mandatory_init`,
depois `asset_search` com `entityScope: "StockAsset"` e
`filters.contentType: "Photo"`. Não use filtro de orientação, ele costuma
devolver vazio. Exiba com `asset_preview_file`.

### Etapa 3 — Baixar em alta e registrar

Só depois do "pode licenciar":

```bash
python scripts/bancos.py baixar pexels:3184418 \
  --como slide-03.jpg \
  --dir assets/imagens/post-1 \
  --card "Card 3 — sala de reunião com vídeo"
```

O comando baixa a maior resolução disponível, grava com o nome exato pedido e
acrescenta a linha correspondente em `LICENCAS.md` na raiz do projeto: banco,
id, autor, tipo de licença, URL de origem, arquivo de destino e data.

Adobe Stock não passa pelo script. Licencie via MCP com
`asset_license_and_download_stock`, baixe a URL presignada com
`curl -L -o assets/imagens/post-1/slide-03.jpg "<url>"` (ela expira em cerca de
1 hora) e registre à mão:

```bash
python scripts/bancos.py registrar --banco adobe --id 714059085 \
  --arquivo assets/imagens/post-1/slide-03.jpg --card "Card 3"
```

### Etapa 4 — Fechar

Confira que nenhum slot ficou vazio, que todo arquivo baixado aparece no
`LICENCAS.md` e que nenhuma foto se repete entre cards do mesmo carrossel.
Só então rode o render final.

## Erros que já custaram retrabalho

- **Licenciar antes de aprovar.** Crédito gasto não volta. Shortlist primeiro,
  sempre.
- **Confiar no filtro do banco.** O tier gratuito de várias fontes é dominado
  por foto desfocada de propósito, principalmente em cena de multidão e feira.
  Se o perfil do cliente proíbe imagem borrada, isso elimina boa parte do
  acervo gratuito e o caminho é o Adobe pago.
- **Repetir foto entre páginas.** Cheque o `LICENCAS.md` consolidado antes,
  não depois.
- **Chave de API dentro do repositório ou do vault.** Vai em `.env` local, por
  máquina. Ver `references/setup.md`.
- **Sandbox de rede.** Se o download falhar com erro de proxy ou domínio
  bloqueado, você está num ambiente com allowlist. O script não resolve isso.
  Rode em máquina local ou peça a liberação dos domínios listados em
  `references/setup.md`.

## Arquivos

- `scripts/bancos.py` — busca, download, registro de licença. Só stdlib.
- `references/setup.md` — chaves de API, instalação em várias máquinas, domínios.
- `references/telecall.md` — perfil fotográfico da Telecall.
