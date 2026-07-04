// Porta lib/painel-lead.ts da intranet legada: o que o Kit do Closer mostra
// depende do momento da venda. SDR (qualificando) ≠ Closer (fechando).
const CLOSER_STAGES = [
  'Reunião agendada',
  'Reunião realizada',
  'Negociação',
  'Última chance',
];

export function stageMode(lead) {
  if (lead?.won_at || lead?.lost_at) return 'encerrado';
  if (CLOSER_STAGES.includes(lead?.stage_name)) return 'closer';
  return 'sdr';
}

export function kitBlocks(mode) {
  switch (mode) {
    case 'closer':
      return ['resumo', 'venda_objecoes', 'documentos', 'proximo_passo'];
    case 'encerrado':
      return [];
    default:
      return ['roteiro', 'proximo_passo'];
  }
}
