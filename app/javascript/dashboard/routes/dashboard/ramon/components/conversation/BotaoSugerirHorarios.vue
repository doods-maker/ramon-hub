<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import LeadsAPI from 'dashboard/api/leads';
import NextButton from 'dashboard/components-next/button/Button.vue';

// "Sugerir horários" na caixa de resposta: rascunho com os horários livres do Closer do lead.
// Só aparece quando a conversa tem lead; quem revisa e envia é a pessoa.
defineOptions({ name: 'BotaoSugerirHorarios' });

// ponytail: texto aguarda ok do Eduardo
const montarRascunho = texto =>
  `Posso te atender em: ${texto}. Qual fica melhor pra você?`;

const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const lead = computed(() =>
  currentChat.value?.id
    ? leadByConv.value(Number(currentChat.value.id))
    : undefined
);
const loading = ref(false);

const sugerir = async () => {
  if (loading.value) return;
  loading.value = true;
  try {
    const { data } = await LeadsAPI.horariosLivres(lead.value.id);
    if (!data.texto) {
      useAlert(t('RAMON.AGENDA.SEM_HORARIOS'));
      return;
    }
    emitter.emit(
      BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
      montarRascunho(data.texto)
    );
  } catch (error) {
    useAlert(error?.response?.data?.error || t('RAMON.AGENDA.SEM_HORARIOS'));
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <NextButton
    v-if="lead"
    v-tooltip.top-end="$t('RAMON.AGENDA.SUGERIR_HORARIOS')"
    data-testid="sugerir-horarios"
    icon="i-lucide-calendar-clock"
    slate
    faded
    sm
    :is-loading="loading"
    @click="sugerir"
  />
</template>
