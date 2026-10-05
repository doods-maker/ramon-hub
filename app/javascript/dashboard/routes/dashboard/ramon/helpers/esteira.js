import { brlCompact } from './currency';

// Item da Esteira na tela: compartilhado pela Esteira e pela fila do Centro de
// Comando, pra o motivo, o tom e o valor saírem iguais nas duas telas.

// Motivo legível: chaves i18n vindas do backend; moeda formatada aqui.
export const reasonLabel = (t, reason) =>
  t(
    `RAMON.ESTEIRA.REASON.${reason.key}`,
    reason.key === 'PRESCRIPTION_BLEEDING'
      ? { value: brlCompact(reason.params.monthly) }
      : reason.params
  );

// Tom do motivo: prescrição ruby, tarefa âmbar, resto neutro. Pinta o chip
// e o filete do cartão (pelo 1º motivo).
export const tomMotivo = (key = '') => {
  if (key.startsWith('PRESCRIPTION')) return 'ruby';
  if (key.startsWith('TASK')) return 'amber';
  return 'slate';
};

// Ponto de severidade da lista dos próximos.
export const severityDotClass = item => {
  const key = item.reasons[0]?.key || '';
  if (key.startsWith('PRESCRIPTION')) return 'bg-n-ruby-9';
  if (key === 'TASK_OVERDUE' || key === 'STALLED') return 'bg-n-amber-9';
  return 'bg-n-teal-9';
};
