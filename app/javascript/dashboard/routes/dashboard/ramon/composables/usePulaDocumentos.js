// Ganho que pula Documentos (decisão 07/11), num lugar só para o Kanban (arrastar
// e Ctrl K), o lote e o painel do lead: quando pedir o motivo (helpers/stage.js
// pulaDocumentos, com as etapas e a chave do lead_config) e a nota que ele vira.
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import LeadsAPI from 'dashboard/api/leads';
import { pulaDocumentos } from '../helpers/stage';

export const usePulaDocumentos = () => {
  const { t } = useI18n();
  const etapas = useMapGetter('leadConfig/getStages');
  const ligada = useMapGetter('leadConfig/getEtapaDocumentos');

  const pedeMotivo = (destino, origem, lead) =>
    pulaDocumentos(destino, origem, lead, etapas.value, ligada.value);

  // Depois do ganho gravado: falha não desfaz o ganho, só avisa. true = gravou.
  const anotar = (leadId, etapa, motivo) =>
    LeadsAPI.createNote(
      leadId,
      t('RAMON.FUNIL.WON.NOTA_PULA_DOCUMENTOS', { etapa: etapa?.name, motivo })
    )
      .then(() => true)
      .catch(() => {
        useAlert(t('RAMON.FUNIL.WON.NOTA_ERRO'));
        return false;
      });

  return { pedeMotivo, anotar };
};
