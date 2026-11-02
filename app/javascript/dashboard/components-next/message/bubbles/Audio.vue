<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import { useMessageContext } from '../provider.js';

const { attachments, isEquipe } = useMessageContext();

// FORK(ramon): na Equipe o player fica dentro da bolha, sem o cartão à parte.
const EQUIPE_SEM_CARTAO =
  '!p-0 !rounded-none !bg-transparent !border-0 !shadow-none';

const attachment = computed(() => {
  return attachments.value[0];
});
</script>

<template>
  <BaseBubble :class="{ 'bg-transparent': !isEquipe }" data-bubble-name="audio">
    <AudioChip
      :attachment="attachment"
      class="p-2 text-n-slate-12 skip-context-menu"
      :class="{ [EQUIPE_SEM_CARTAO]: isEquipe }"
    />
  </BaseBubble>
</template>
