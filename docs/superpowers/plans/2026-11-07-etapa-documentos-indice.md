# Etapa Documentos — índice dos planos

Spec: `docs/superpowers/specs/2026-11-07-etapa-documentos-design.md` (aprovada pelo Eduardo em 07/11).
Todos os PRs seguem as skills do Matt Pocock (pedido do Eduardo, 07/11): `mattpocock-skills:tdd` por task,
`mattpocock-skills:codebase-design` nas costuras novas, `mattpocock-skills:code-review` antes do merge e
`mattpocock-skills:pr` no corpo do PR.

| PR | Plano | Tasks | Depende de | Migração | Detalhe |
|---|---|---|---|---|---|
| 1 | `2026-11-07-etapa-documentos-1-varias-etapas-de-ganho.md` | 7 | — | não (rake) | completo |
| 2 | `2026-11-07-etapa-documentos-2-assistente-por-etapa.md` | 7 | 1 | sim | nível de task |
| 3 | `2026-11-07-etapa-documentos-3-marcacao-avisos-gatilhos.md` | 8 | 1, 2 | não (imagens fora do git) | nível de task |
| 4 | `2026-11-07-etapa-documentos-4-senha-govbr.md` | 5 | 2, 3 | sim | nível de task |
| 5 | `2026-11-07-etapa-documentos-5-cobranca-e-janelas.md` | 7 | 2, 3 | não | nível de task |
| 6 | `2026-11-07-etapa-documentos-6-completo-juridico.md` | 6 | 1–3, 5 | não | nível de task |

**Liga quando:** PRs 1, 2, 3, 5 e 6 no ar + textos aprovados (instruções do agente, gatilhos, abertura,
lembretes, encerramento, modelo da Meta aprovado pela Meta) + imagens do passo a passo recortadas →
`RAMON_ETAPA_DOCUMENTOS=on`. O PR 4 (senha) pode entrar depois; até lá, o agente não pede senha e o
gatilho `govbr_sem_acesso` chama o SDR.

**Antes de executar cada PR de 2 a 6:** refinar os passos (testes exatos) contra o código do momento.

## Respostas do Eduardo (07/11)

1. **Arrastado para Fechado:** respeita a coluna, **mas pergunta o motivo**. A pessoa registra o porquê
   (obrigatório, como o motivo do Perdido) e ele fica gravado nas notas do lead. Entra no PR 1.
2. **Ganho sem WhatsApp:** vai para **Documentos com o SDR conduzindo**, sem IA, com aviso ao SDR na hora.
   Entra nos PRs 2 e 3.
3. **Teses que passam por Documentos:** decisão do Claude: chave por tese ("passa pela etapa Documentos")
   na tela de teses, em vez de depender de `theses.area`. Entra no PR 2 (migração já prevista).
4. **`spec/enterprise` fora do CI:** decisão do Claude: os testes do que fica em `enterprise/` ganham
   espelho em `spec/` (num job que roda), como já se fez em PRs anteriores.
5. **PR 0, antes do PR 1:** aba Contrato em todas as etapas abertas + a colheita volta a ter tela
   (botão de rodar e "O que a IA colheu" no painel do lead). Plano próprio.

## Perguntas ao Eduardo (respondidas acima)

1. Lead de tese previdenciária arrastado à mão para **Fechado** (em vez de Documentos): o hub desvia
   para Documentos ou respeita a coluna escolhida? (Até a resposta, respeita.)
2. Lead que ganha sem conversa de WhatsApp (só Instagram, LP ou cadastro à mão) cai em Documentos sem
   ninguém para a IA conversar: vai para Documentos com o SDR conduzindo, ou para Fechado?
