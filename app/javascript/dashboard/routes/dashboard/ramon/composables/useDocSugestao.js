import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

// Resolver único da sugestão da IA (custom_attributes.doc_sugestao):
// resolvida:true sempre; aceitar também grava recebido + vincula o anexo.
// Compartilhado entre DocChecklist (painel) e RamonEvent (bolha na conversa).
export function useDocSugestao(lead) {
  const store = useStore();
  const { t } = useI18n();
  const pending = ref(false);

  const resolver = async (aceitar, { itemId, attachmentId }) => {
    if (pending.value) return;
    pending.value = true;
    const patch = { doc_sugestao: { resolvida: true } };
    if (aceitar) {
      patch.doc_status = { [itemId]: 'recebido' };
      patch.doc_anexos = { [itemId]: attachmentId };
    }
    try {
      await store.dispatch('leads/update', {
        id: lead.value.id,
        custom_attributes: patch,
      });
    } catch (e) {
      useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    } finally {
      pending.value = false;
    }
  };

  return { pending, resolver };
}
