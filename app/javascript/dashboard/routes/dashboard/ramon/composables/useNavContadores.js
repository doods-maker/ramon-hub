import { ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import LeadTasksAPI from 'dashboard/api/leadTasks';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

// Números do menu: não lidas (store do Chatwoot), tarefas de hoje e peças
// aguardando aprovação. Falha de rede = número some, menu segue.
const CINCO_MINUTOS = 5 * 60 * 1000;

export const useNavContadores = papel => {
  const conversas = useMapGetter('conversationUnreadCounts/getAllUnreadCount');
  const agenda = ref(0);
  const conteudo = ref(0);

  const carregar = async () => {
    try {
      const { data } = await LeadTasksAPI.getAccountScope('today');
      agenda.value = data.payload.length;
    } catch {
      agenda.value = 0;
    }
    if (papel.value !== 'gestor') return;
    try {
      const { data } = await RamonConteudoAPI.get();
      conteudo.value = data.payload.filter(p => p.status === 'rascunho').length;
    } catch {
      conteudo.value = 0;
    }
  };

  useIntervalFn(carregar, CINCO_MINUTOS);
  return { conversas, agenda, conteudo, carregar };
};
