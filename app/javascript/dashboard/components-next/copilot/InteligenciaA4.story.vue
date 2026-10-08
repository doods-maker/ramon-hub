<script setup>
import Copilot from './Copilot.vue';
import MenuItem from 'dashboard/components/widgets/conversation/contextMenu/menuItem.vue';
import VirarFaqMenuItem from 'dashboard/modules/conversations/components/VirarFaqMenuItem.vue';

const COPILOTO = { id: 2, name: 'Copiloto do Escritório' };
const ASSISTENTES = [{ id: 1, name: 'Atendimento' }, COPILOTO];
const RESPOSTA = [
  {
    id: 1,
    message_type: 'user',
    message: { content: 'Situação do processo deste cliente' },
  },
  {
    id: 2,
    message_type: 'assistant',
    message: {
      content:
        'Processo 5001234-56.2026.4.04.7207 (Maria Exemplo) — fase: perícia agendada para 20/10. Responsável: Dra. Exemplo. Última movimentação 02/10: intimação da perícia. Tarefa aberta: avisar a cliente.',
    },
  },
];
</script>

<template>
  <Story
    title="Ramon/Inteligência A4"
    :layout="{ type: 'grid', width: '360px' }"
  >
    <Variant title="Menu da mensagem">
      <div class="w-56 rounded-md bg-n-background p-1 shadow-xl">
        <MenuItem
          :option="{
            icon: 'clipboard',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY'),
          }"
          variant="icon"
        />
        <MenuItem
          :option="{
            icon: 'link',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY_PERMALINK'),
          }"
          variant="icon"
        />
        <MenuItem
          :option="{
            icon: 'comment-add',
            label: $t('CONVERSATION.CONTEXT_MENU.CREATE_A_CANNED_RESPONSE'),
          }"
          variant="icon"
        />
        <VirarFaqMenuItem :conversation-id="12" :message-id="345" />
      </div>
    </Variant>
    <Variant title="Copiloto na conversa">
      <div class="h-[640px]">
        <Copilot
          :messages="[]"
          conversation-inbox-type="Channel::Whatsapp"
          :assistants="ASSISTENTES"
          :active-assistant="COPILOTO"
          equipe
          na-conversa
        />
      </div>
    </Variant>
    <Variant title="Copiloto fora da conversa">
      <div class="h-[640px]">
        <Copilot
          :messages="[]"
          conversation-inbox-type=""
          :assistants="ASSISTENTES"
          :active-assistant="COPILOTO"
          equipe
        />
      </div>
    </Variant>
    <Variant title="Copiloto respondeu">
      <div class="h-[640px]">
        <Copilot
          :messages="RESPOSTA"
          conversation-inbox-type="Channel::Whatsapp"
          :assistants="ASSISTENTES"
          :active-assistant="COPILOTO"
          equipe
          na-conversa
        />
      </div>
    </Variant>
  </Story>
</template>
