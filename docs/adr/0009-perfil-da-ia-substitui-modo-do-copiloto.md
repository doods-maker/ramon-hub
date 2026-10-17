# Perfil da IA substitui o Modo do Copiloto

Até 2026-10-17 a autonomia da IA era um campo de 7 valores (`copiloto_modo`:
manual, rascunho, piloto limitado, piloto total e "sozinha até qualificar /
reunião / contrato"), gravado na conversa, na caixa e numa env, e explicado em 7
lugares. Cada valor misturava duas perguntas: *até que etapa a IA vai sozinha* e
*o que ela pode fazer no caminho* (marcar reunião, mandar contrato, mover etapa).

Decidimos (Eduardo, 2026-10-17) trocar o campo pelo **Perfil da IA**: um
Marcador na Trilha (as Etapas reais do Funil) + uma Permissão por ação
(sozinha / rascunho / nunca) + Gatilhos de equipe por Etapa. Ele é definido por
Tese, por caixa e no Padrão do escritório, e quem manda é a conversa → Tese →
caixa → padrão. Na conversa sobra só a Pausa (IA pausada ou só rascunho).

Consequência que contraria o glossário antigo: as ações de regra fixa (efeitos
do roteiro, marcar reunião, contrato automático) **executam** quando o Perfil dá
*sozinha* àquela ação — o código já fazia isso nos modos "direto"; agora a regra
é explícita e por ação. As Tools que o modelo chama por conta própria para mover
etapa ou marcar Perdido continuam sempre Sugestão. O Marcador é teto: depois
dele, nenhuma ação passa de rascunho.

Os Perfis ficam em `accounts.settings['ia_atendimento']`, que o `audited` já
registra: o histórico e o desfazer saem do Registro de ações, sem tabela nova.

Alternativas descartadas:

- **Manter os 7 modos e só juntar as telas**: não responde "até onde, em cada
  ação", e o modo "Piloto total" continuaria sem volta.
- **Grade etapa × ação (semáforo)**: testada em mockup e reprovada pelo Eduardo
  como difícil de ler; a Permissão é por ação, não por célula.
- **Tabela própria de perfis**: mais limpa, mas pede migração, policy e auditoria
  nova; o volume (uma linha por tese/caixa) cabe no jsonb da conta.
