# Patch para o prompt de carrosséis Telecall

Cole este bloco em `prompt-claude-code-carrosseis-telecall.md`, na seção de
design system, e no brandbook v2.

---

## Elemento gráfico de linha (usar sempre que couber)

Retângulo de cantos arredondados, contorno fino sólido em azul, sangrando pela
borda do card. É um detalhe de marca que o cliente valoriza, então aloque
sempre que a arte permitir. Não é obrigatório em todo card.

Não use quando:

- O card tem foto ocupando o fundo inteiro (full bleed).
- O card é denso de texto e a linha invadiria a área de leitura.
- Simplesmente não ficou bom. Card sem linha é melhor que linha mal colocada.

Quando usar:

- A posição **muda a cada card**. Nunca repita o mesmo canto em cards
  consecutivos. Faça o elemento circular pelas bordas ao longo do carrossel:
  base, lateral direita, topo, lateral esquerda, e assim por diante. Cards que
  pularam a linha não quebram a sequência, ela retoma de onde parou.
- Sempre sangrando. O que aparece é um pedaço do retângulo, nunca a figura
  inteira dentro do card.
- A escala varia junto com a posição: em uns cards é um arco largo e discreto,
  em outros um canto pequeno.
- Nunca cruza texto nem foto. É moldura, não textura.
- Contorno fino, sem gradiente, sem preenchimento, sem sombra.

Sugestão de implementação em CSS, com uma classe por variação de posição:

```css
.linha-marca {
  position: absolute;
  border: 2px solid #2B5CA8;
  border-radius: 40px;
  pointer-events: none;
}
/* card 1 */ .pos-a { left: -8%;  bottom: -18%; width: 78%; height: 34%; }
/* card 2 */ .pos-b { right: -14%; bottom: -10%; width: 62%; height: 46%; }
/* card 3 */ .pos-c { right: -20%; top: -12%;    width: 55%; height: 40%; }
/* card 4 */ .pos-d { left: -22%;  top: -16%;    width: 70%; height: 38%; }
```

Antes de renderizar, confira: dois cards seguidos não podem usar a mesma classe.

## Assinatura do card

Somente o **card de capa** leva a logo horizontal completa. Do card 2 em diante,
apenas o símbolo.

- Arquivo: `Ícone final PNG.png` (PNG sem fundo), da pasta de marca no Drive.
  Salvar em `assets/logo/simbolo-telecall.png`.
- Não usar a variante "fletado", nem o `.ai`, nem o `.psd`.
- Posição do símbolo é **fixa** entre os cards internos. O que se move é o
  elemento de linha, não a assinatura.

## Checklist antes do render final

1. Os cards que comportavam a linha receberam uma? (full bleed e cards densos
   ficam de fora de propósito)
2. Algum par de cards consecutivos com linha repete a mesma posição?
3. A linha cruza texto ou foto em algum card?
4. Capa com logo horizontal, demais cards com o símbolo?
5. Nenhum card ficou com slot de imagem vazio?
