import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import LeadsAPI from 'dashboard/api/leads';

// "Cobrar documentos" fora da gaveta (card do funil, ficha): acha os documentos
// faltando do lead (itens 'documento' da tese × custom_attributes.doc_status,
// mesma regra do DocChecklist) e marca os pendentes como solicitados.
export const useCobrarDocs = () => {
  const store = useStore();
  const { t } = useI18n();

  const pendentesDoLead = async leadId => {
    const { data: lead } = await LeadsAPI.show(leadId);
    if (!lead.thesis_id) return [];
    const tese = await store.dispatch('theses/show', lead.thesis_id);
    const status = lead.custom_attributes?.doc_status || {};
    return (tese?.items || [])
      .filter(item => item.section === 'documento')
      .map(item => ({
        id: item.id,
        title: item.title || item.content,
        status: status[item.id] || 'pendente',
      }))
      .filter(item => item.status !== 'recebido');
  };

  // o backend faz deep-merge do custom_attributes: só doc_status muda
  const marcarSolicitados = async (leadId, itens) => {
    const docStatus = Object.fromEntries(
      itens
        .filter(item => item.status === 'pendente')
        .map(item => [item.id, 'solicitado'])
    );
    if (!Object.keys(docStatus).length) return;
    try {
      await store.dispatch('leads/update', {
        id: leadId,
        custom_attributes: { doc_status: docStatus },
      });
    } catch (e) {
      useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    }
  };

  return { pendentesDoLead, marcarSolicitados };
};
