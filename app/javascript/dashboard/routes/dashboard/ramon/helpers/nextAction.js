// Próxima ação do lead, igual no card e na lista do Funil: reunião marcada
// com data e hora absolutas; o resto com cor semântica — vencida ruby, hoje
// âmbar, futura teal. { dot, text, label } | null (sem tarefa).
export const nextActionInfo = (lead, t) => {
  const raw = lead.next_task_due_at;
  if (!raw) return null;
  const due = new Date(raw);
  if (Number.isNaN(due.getTime())) return null;
  const title = lead.next_task_title || '';
  // Reunião marcada (Cal.com/agendar_reuniao): data e hora absolutas, não "em 3d".
  if (lead.next_task_kind === 'meeting' && due.getTime() >= Date.now())
    return {
      dot: 'bg-n-blue-9',
      text: 'text-n-blue-11 font-semibold',
      label: t('RAMON.KANBAN.CARD.NEXT_MEETING', {
        when: due.toLocaleString('pt-BR', {
          weekday: 'short',
          day: '2-digit',
          month: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
        }),
      }),
    };
  if (due.getTime() < Date.now())
    return {
      dot: 'bg-n-ruby-9',
      text: 'text-n-ruby-11',
      label: t('RAMON.KANBAN.CARD.NEXT_OVERDUE', { title }),
    };
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const days = Math.floor((due.getTime() - startOfToday.getTime()) / 86400000);
  if (days === 0)
    return {
      dot: 'bg-n-amber-9',
      text: 'text-n-amber-11',
      label: t('RAMON.KANBAN.CARD.NEXT_TODAY', { title }),
    };
  if (days === 1)
    return {
      dot: 'bg-n-teal-9',
      text: 'text-n-teal-11',
      label: t('RAMON.KANBAN.CARD.NEXT_TOMORROW', { title }),
    };
  return {
    dot: 'bg-n-teal-9',
    text: 'text-n-teal-11',
    label: t('RAMON.KANBAN.CARD.NEXT_IN_DAYS', { days, title }),
  };
};
