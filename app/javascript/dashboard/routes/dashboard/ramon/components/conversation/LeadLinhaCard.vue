<script setup>
// Linha curta do lead no card da conversa: bolinha na cor da etapa +
// "Etapa · Tese · Responsável". Entra no ConversationCard nativo por 1 linha.
import { computed } from 'vue';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import { partesDaLinha } from '../../helpers/leadNaConversa';

const props = defineProps({
  lead: { type: Object, default: null },
});

const texto = computed(() => partesDaLinha(props.lead).join(' · '));
</script>

<template>
  <p
    v-if="texto"
    data-testid="lead-linha-card"
    class="flex items-center min-w-0 gap-1.5 my-0 text-xs leading-5 text-n-slate-10"
    :title="texto"
  >
    <span
      class="rounded-full size-1.5 shrink-0 bg-[var(--stage)]"
      :style="{ '--stage': lead.stage_color || DEFAULT_STAGE_COLOR }"
    />
    <span class="truncate">{{ texto }}</span>
  </p>
</template>
