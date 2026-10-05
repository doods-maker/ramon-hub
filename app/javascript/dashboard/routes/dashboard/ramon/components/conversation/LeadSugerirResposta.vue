<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import Button from 'dashboard/components-next/button/Button.vue';

// "Sugerir resposta" do copiloto, na linha de ações do cabeçalho do painel.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadSugerirResposta' });

const { t } = useI18n();
const loading = ref(false);

const sugerir = async () => {
  if (loading.value) return;
  loading.value = true;
  try {
    const { data } = await RamonCopilotAPI.generate(
      props.conversationId,
      'draft'
    );
    // Cai como rascunho no editor de resposta (ReplyBox escuta este evento);
    // nada é enviado — quem envia é o Eduardo.
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, data.content);
    useAlert(t('RAMON.COPILOT.DRAFT_READY'));
  } catch (error) {
    useAlert(error?.response?.data?.error || t('RAMON.COPILOT.ERROR'));
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <Button
    data-testid="copilot-suggest"
    sm
    icon="i-lucide-sparkles"
    :disabled="loading"
    :label="loading ? $t('RAMON.COPILOT.WORKING') : $t('RAMON.COPILOT.SUGGEST')"
    @click="sugerir"
  />
</template>
