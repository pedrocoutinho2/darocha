# Setup de Project para Novo Cliente — daRocha

> Use este checklist toda vez que for criar um Project no Claude para um novo cliente.

---

## ⏱ Tempo estimado: 10 minutos

## 📋 O que você vai precisar antes de começar

- [ ] Nome oficial do cliente
- [ ] Slug do cliente (identificador curto, minúsculas, sem espaços — ex: `acme-corp`)
- [ ] Lista de pilares de conteúdo do cliente (entre 5 e 15 normalmente)
- [ ] Tom de comunicação da marca (1-2 frases)
- [ ] Setor/área de atuação
- [ ] Diferenciais e termos técnicos frequentes (se houver)

---

## ✅ Passo a passo

### 1. Cadastrar o cliente no painel admin
1. Login no painel daRocha como admin
2. Painel Administrativo → Aba Clientes → Cadastrar novo cliente
3. Preencha: nome, slug, cor primária, logo (opcional)
4. Salvar

### 2. Criar o Project no Claude
1. Barra lateral do Claude → **Projects** → **+ New project**
2. Nome: `Planejamento [Nome do Cliente]`
3. Description: "Planejamento mensal de conteúdo — [Nome do Cliente] · daRocha Comunicação"

### 3. Subir os arquivos no Project knowledge
Faça upload destes 3 arquivos no **Project knowledge** (são iguais para todos os clientes):
- [ ] `docs/FORMATO-PLANEJAMENTO.md`
- [ ] `docs/EXEMPLO-planejamento.md`
- [ ] `docs/EXEMPLO-planejamento.json`

### 4. Personalizar e colar as Custom Instructions
Olhe os exemplos em `docs/instrucoes-clientes/` (Telecall, CNA Taquara, CNA Queimados, JR Hoteis) para entender o formato. Crie seu próprio baseado neles, personalizando:

- Nome e descrição do setor do cliente
- Slug do cliente (mesmo cadastrado no painel)
- Lista exata dos pilares cadastrados
- Tom de comunicação (4-6 linhas)

Cole o conteúdo final em **Project → Custom Instructions**.

### 5. Validar
Mande uma mensagem de teste no Project:

> "Resume os pilares e tom desse cliente"

Se ele responder com a lista correta, está tudo certo.

---

## 🎯 Como gerar planejamentos depois

> "Cria planejamento de julho/2026 com 12 posts. Foco do mês: lançamento do produto X. 1 campanha Meta de R$ 5mil."

Eu já vou saber: cliente, pilares válidos, tom, formato JSON exato.

---

## 🆘 Problemas comuns

| Problema | Solução |
|---|---|
| "Pilar não está na lista oficial" no upload | Confira se o nome no JSON bate exato com o cadastrado no painel |
| "Cliente do arquivo não bate com selecionado" | O `client_slug` no JSON precisa ser igual ao slug do cliente no painel |
| Claude gera formatos errados (com slides/segundos no campo format) | Reforce nas instruções: "campo `format` raiz aceita APENAS Post Estático, Carrossel, Reels, Story, Infográfico, Vídeo" |
