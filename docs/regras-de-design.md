# Regras de design do hub

Checklist conferido em **cada tela** antes do print de aprovação (claro e escuro).
Fonte: cheat sheets "Do's and Don'ts" (perspecto.io), adotadas em 07/11/2026.
O kit que aplica isso fica em `app/javascript/dashboard/routes/dashboard/ramon/helpers/ui.js`
e os tokens de cor em `app/javascript/dashboard/assets/scss/_ramon-brand.scss`.

Decisões nossas que vencem a regra genérica estão marcadas com **Hub:**.

## Números e painéis
- [ ] O número que mais importa vem grande; os outros, menores.
- [ ] Todo número tem período e variação ("Outubro · ▲ 8% vs setembro").
- [ ] Gráfico de barras começa no zero.
- [ ] Mais de 3 partes: barras ordenadas, nunca pizza.
- [ ] Números em tabela alinhados à direita, com `font-mono` (algarismos da mesma largura).
- [ ] Gráfico com várias linhas: uma em cor, as outras cinza.

## Cor
- [ ] Uma cor de destaque só (azul `n-blue-9`) para ação; o resto neutro.
- [ ] Erro nunca só pela cor: borda vermelha **e** texto dizendo o que corrigir.
- [ ] Significado fixo: ruby = perigo/risco, amber = atenção, teal = ganho. Botão de excluir é vermelho; "manter" é neutro. **Hub:** verde do WhatsApp (`TOM.verde`) só no que imita o WhatsApp: bolha enviada, contador de não lidas e o botão "Nova conversa" da Equipe (09/11/2026).
- [ ] Texto sobre botão colorido com 4,5:1 (azul + branco = 5,2:1).
- [ ] Área grande com tom suave; cor forte só em detalhe. **Hub:** fundo colorido sempre translúcido (`TOM`, `AVISO`).
- [ ] Link com cor **e** sublinhado.

## Tema escuro
- [ ] Fundo cinza bem escuro, não preto puro. **Hub:** fundo #121212, cartão #1c1c1c, menu #222 (era preto puro até 07/11/2026).
- [ ] Texto quase branco (`slate-12` = #ededed); hierarquia por tom de cinza, não por branco puro.
- [ ] Cor da marca mais clara no escuro (texto azul = `blue-11` #60a5fa).
- [ ] Camada acima = cinza mais claro, não sombra (sombra some no escuro).
- [ ] Cinza de texto com 4,5:1 sobre o fundo **e** sobre o cartão.
- [ ] Imagem clara escurecida ou com versão escura.

## Texto
- [ ] Texto com 4,5:1 de contraste. **Hub:** o cinza mais claro para texto é `slate-10` (#767676 no claro); `slate-9` não serve para texto.
- [ ] Título claramente maior ou mais forte que o corpo.
- [ ] Espaço entre linhas de 1,4 a 1,6 no corpo.
- [ ] De 45 a 75 caracteres por linha em texto corrido (resumo da IA, notas).
- [ ] Caixa-alta só em rótulo curto (`SOBRESCRITO`), nunca em frase.
- [ ] No máximo duas fontes: Geist (texto) e Geist Mono (números, horários, valores). Variar pelo peso.
- [ ] Texto com mais de duas linhas alinhado à esquerda.
- [ ] Título grande com letras um pouco mais juntas.

## Botões e formulários
- [ ] Um botão primário por tela/janela; o resto secundário (`RODAPE_JANELA`: secundário à esquerda).
- [ ] O botão diz o que acontece ("Excluir lead", "Manter"), nunca "OK/Sim/Não". Nada de `window.confirm`.
- [ ] Rótulo fixo acima do campo; placeholder só como exemplo.
- [ ] Rótulo mais perto do próprio campo do que do campo de cima (`ROTULO`).

## Espaço
- [ ] Espaços da escala 4 · 8 · 16 · 24 · 32 (Tailwind 1 · 2 · 4 · 6 · 8). Nada de `p-[13px]`.
- [ ] Mais espaço entre grupos do que dentro do grupo.
- [ ] Tudo alinhado pela mesma margem esquerda.
- [ ] Cartão com 16px de espaço interno (`CARTAO` = `p-4`). **Hub:** o cartão do funil fica em 12px (coluna de 240px, 2 botões por linha).
- [ ] Canto de dentro = canto de fora − espaço interno (cartão `rounded-xl` 12px com `p-4` → elemento interno com canto pequeno, `rounded-md` ou menos).

## Celular
**Hub:** a equipe usa o hub no PC. No celular só entram as telas escolhidas
(dashboard, Centro de Comando e aceites do painel dos agentes); estas regras valem para elas.
- [ ] Área de toque de pelo menos 44×44px.
- [ ] Ação principal embaixo, onde o polegar alcança.
- [ ] Campo de texto com 16px (abaixo disso o iPhone dá zoom).
- [ ] Teclado certo por campo (`type="tel"`, `inputmode="numeric"`, `type="email"`).
- [ ] Nenhuma ação que só aparece no hover.
- [ ] Janela que sobe de baixo (bottom sheet), não janela no meio.
