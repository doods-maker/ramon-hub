import { computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { TOM } from '../helpers/ui';

// Quem atende a conversa aberta agora (decisão Eduardo 20/10): uma pessoa (responsável da conversa), a IA (conversa
// pendente) ou ninguém (aberta sem responsável = fila da equipe, IA parada). Usado no botão da IA e na faixa do painel.
// pausaServidor: lead em Perdido também cala a IA (o servidor responde pausa = 'pausada').
export const ESTADOS = {
  ia: { tom: 'teal', icone: 'i-lucide-bot' },
  rascunho: { tom: 'amber', icone: 'i-lucide-file-pen-line' },
  pausada: { tom: 'slate', icone: 'i-lucide-circle-pause' },
  pessoa: { tom: 'blue', icone: 'i-lucide-user' },
  equipe: { tom: 'ruby', icone: 'i-lucide-users' },
};

export function useQuemAtende(pausaServidor = computed(() => null)) {
  const store = useStore();
  const chat = useMapGetter('getSelectedChat');

  const pausa = computed(() => chat.value?.custom_attributes?.ia_pausa || null);
  const pessoa = computed(() => chat.value?.meta?.assignee?.name || null);
  const estado = computed(() => {
    if (pessoa.value) return 'pessoa';
    if (pausa.value === 'pausada' || pausaServidor.value === 'pausada')
      return 'pausada';
    if (chat.value?.status !== 'pending') return 'equipe';
    return pausa.value === 'rascunho' ? 'rascunho' : 'ia';
  });
  const visual = computed(() => ({
    ...ESTADOS[estado.value],
    classe: TOM[ESTADOS[estado.value].tom],
  }));
  // IA parada por pessoa, pausa ou fila da equipe: dá pra devolver.
  const podeDevolver = computed(() =>
    ['pessoa', 'pausada', 'equipe'].includes(estado.value)
  );

  // Devolver à IA: tira o responsável, a pausa e põe a conversa de volta na fila da IA (pendente).
  const devolver = async () => {
    const id = chat.value.id;
    if (pessoa.value)
      await store.dispatch('assignAgent', { conversationId: id, agentId: 0 });
    if (pausa.value) {
      const { ia_pausa: _antes, ...resto } = chat.value.custom_attributes || {};
      await store.dispatch('updateCustomAttributes', {
        conversationId: id,
        customAttributes: resto,
      });
    }
    if (chat.value?.status !== 'pending')
      await store.dispatch('toggleStatus', {
        conversationId: id,
        status: 'pending',
      });
  };

  return { chat, pausa, pessoa, estado, visual, podeDevolver, devolver };
}
