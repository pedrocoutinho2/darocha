# Setup

## 1. Chaves de API

Todas gratuitas, cadastro de dois minutos, sem cartão.

| Banco | Onde pegar | Variável |
|---|---|---|
| Pexels | pexels.com/api | `PEXELS_API_KEY` |
| Unsplash | unsplash.com/developers | `UNSPLASH_ACCESS_KEY` |
| Pixabay | pixabay.com/api/docs | `PIXABAY_API_KEY` |
| Openverse | não exige | — |
| Adobe Stock | conector MCP, não usa chave aqui | — |

Grave em `~/.claude/imagens.env`, **uma vez por máquina**:

```
PEXELS_API_KEY=xxxxxxxx
UNSPLASH_ACCESS_KEY=xxxxxxxx
PIXABAY_API_KEY=xxxxxxxx
```

```bash
chmod 600 ~/.claude/imagens.env
```

Esse arquivo **nunca** entra no vault, no repositório da skill ou em qualquer
commit. É a única parte que não sincroniza entre máquinas, e é assim de
propósito.

Confira com:

```bash
python scripts/bancos.py doctor
```

## 2. Instalar em várias máquinas

A skill em si (SKILL.md, scripts, references) é texto e pode sincronizar. Duas
formas, escolha uma e mantenha:

**Git (recomendado).** Um repositório privado com as skills da daRocha:

```bash
git clone git@github.com:<voce>/darocha-skills.git ~/darocha-skills
mkdir -p ~/.claude/skills
ln -s ~/darocha-skills/imagens-para-artes ~/.claude/skills/imagens-para-artes
```

Numa máquina nova, repetir os dois comandos. Atualização é `git pull`. Histórico
de mudanças fica versionado, que é o que falta na opção abaixo.

**iCloud.** A pasta do vault já sincroniza entre os Macs, então dá para deixar a
skill lá e criar o link simbólico:

```bash
ln -s "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Second Brain/40-processos/skills/imagens-para-artes" \
      ~/.claude/skills/imagens-para-artes
```

Mais simples, mas sujeito a conflito de sincronização se duas máquinas editarem
ao mesmo tempo, e sem histórico.

## 3. Conector Adobe no Claude Code

O MCP da Adobe hoje está ligado no claude.ai. Para usar dentro do Claude Code:

```bash
claude mcp add --transport http adobe https://adobe-creativity.adobe.io/mcp
```

Depois `/mcp` na sessão para autenticar. Em cada máquina, uma vez.

Na sessão, sempre chamar `adobe_mandatory_init` antes de qualquer operação
Adobe. Busca com `entityScope: "StockAsset"` e `filters.contentType: "Photo"`;
não use filtro de orientação, costuma voltar vazio.

## 4. Ambientes com allowlist de rede

Claude Code local não tem restrição de rede. O sandbox web tem: só passa o que
está na allowlist, e nenhum banco de imagem está nela por padrão. Sintoma: o
download falha com erro de proxy, 403 ou domínio bloqueado.

Se precisar rodar no ambiente web, os domínios a liberar são:

```
api.pexels.com, images.pexels.com
api.unsplash.com, images.unsplash.com
pixabay.com, cdn.pixabay.com
api.openverse.org, api.openverse.engineering
stock.adobe.com, t3.ftcdn.net, t4.ftcdn.net, as1.ftcdn.net, as2.ftcdn.net
```

O host S3 do download da licença Adobe varia por bucket. Descubra rodando uma
licença e lendo o domínio da URL presignada, e acrescente.
