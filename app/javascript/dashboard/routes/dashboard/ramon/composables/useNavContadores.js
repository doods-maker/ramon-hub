import { ref, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import LeadTasksAPI from 'dashboard/api/leadTasks';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

// Números do menu: conversas abertas (minhas; recepção = sem responsável —
// o flag de não lidas está desligado na conta), tarefas de hoje e peças
// aguardando aprovação. Falha de rede = número some, menu segue.
const CINCO_MINUTOS = 5 * 60 * 1000;

const contar = async busca => {
  try {
    return await busca();
  } catch {
    return 0;
  }
};

export const useNavContadores = papel => {
  const conversas = ref(0);
  const agenda = ref(0);
  const conteudo = ref(0);

  const carregar = async () => {
    const [nConversas, nAgenda, nConteudo] = await Promise.all([
      contar(async () => {
        const { data } = await ConversationAPI.meta({ status: 'open' });
        return papel.value === 'recepcao'
          ? data.meta.unassigned_count
          : data.meta.mine_count;
      }),
      contar(async () => {
        const { data } = await LeadTasksAPI.getAccountScope('today');
        return data.payload.length;
      }),
      papel.value === 'gestor'
        ? contar(async () => {
            const { data } = await RamonConteudoAPI.get();
            return data.payload.filter(p => p.status === 'rascunho').length;
          })
        : 0,
    ]);
    conversas.value = nConversas;
    agenda.value = nAgenda;
    conteudo.value = nConteudo;
  };

  // Times chegam depois do mount: papel muda de 'equipe' pra 'recepcao' etc.
  watch(papel, carregar);
  useIntervalFn(carregar, CINCO_MINUTOS);
  return { conversas, agenda, conteudo, carregar };
};
