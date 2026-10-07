<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import FaqDeConversaAPI from 'dashboard/api/captain/faqDeConversa';
import MenuItem from 'dashboard/components/widgets/conversation/contextMenu/menuItem.vue';

const props = defineProps({
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const K = 'CAPTAIN_RAMON.FAQ_CONVERSA';
const ERROS = ['SEM_RESPOSTA', 'SEM_PERGUNTA', 'SEM_ASSISTENTE'];
const enviando = ref(false);

// 1 clique: a FAQ nasce PENDENTE; o aviso leva às pendentes (só administrador aprova).
const virarFaq = async () => {
  if (enviando.value) return;
  enviando.value = true;
  try {
    const { data } = await FaqDeConversaAPI.virarFaq(
      props.conversationId,
      props.messageId
    );
    useAlert(t(`${K}.${data.ja_existia ? 'JA_EXISTIA' : 'CRIADA'}`), {
      type: 'link',
      to: accountScopedRoute('captain_assistants_responses_pending', {
        assistantId: data.assistant_id,
      }),
      message: t(`${K}.VER_PENDENTES`),
    });
  } catch (e) {
    const codigo = e.response?.data?.erro;
    useAlert(t(`${K}.ERROS.${ERROS.includes(codigo) ? codigo : 'GERAL'}`));
  } finally {
    enviando.value = false;
    emit('close');
  }
};
</script>

<template>
  <MenuItem
    :option="{ icon: 'book-outline', label: t(`${K}.MENU`) }"
    variant="icon"
    data-testid="virar-faq"
    @click.stop="virarFaq"
  />
</template>
