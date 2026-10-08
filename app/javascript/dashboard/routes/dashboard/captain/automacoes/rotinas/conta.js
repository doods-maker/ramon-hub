// B5-conta: = Ramon::Fluxos::Rotinas::Conta::ROTINAS (as 7 rotinas da conta, só no gatilho Horário da conta).
export default [
  { chave: 'resumo_do_dia', alvo: 'conta' },
  { chave: 'retrato_funil', alvo: 'conta' },
  { chave: 'fechamento_extrato', alvo: 'conta' },
  { chave: 'espelho_painel', alvo: 'conta' },
  { chave: 'copiloto_noturno', alvo: 'conta' },
  { chave: 'publicar_pecas', alvo: 'conta' },
  { chave: 'avisos_painel', alvo: 'conta' },
];
