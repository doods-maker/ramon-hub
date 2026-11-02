<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import EquipeAPI from 'dashboard/api/ramonEquipe';
import {
  EMOJIS_REACAO,
  resumoReacoes,
} from 'dashboard/routes/dashboard/ramon/helpers/equipe';

// Selos sob a bolha e barra ao passar o mouse (no toque, ao tocar na bolha). A barra se posiciona na
// grade da mensagem, que é o group/equipe. A tela atualiza pelo message.updated, não pela resposta.
const props = defineProps({
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
  reacoes: { type: Array, default: () => [] },
  participantes: { type: Array, default: () => [] },
  meuId: { type: Number, required: true },
  podeReagir: { type: Boolean, default: false },
  direita: { type: Boolean, default: false },
  comAutor: { type: Boolean, default: false },
});

defineEmits(['responder']);

const { t } = useI18n();

const selos = computed(() =>
  resumoReacoes(props.reacoes, props.participantes, props.meuId)
);

const reagir = async emoji => {
  if (!props.podeReagir) return;
  try {
    await EquipeAPI.reagir(props.conversationId, props.messageId, emoji);
  } catch {
    useAlert(t('RAMON.EQUIPE.ERRO'));
  }
};
</script>

<template>
  <div class="contents">
    <div
      v-if="podeReagir"
      data-testid="barra-reacoes"
      class="absolute z-10 hidden w-max items-center gap-0.5 -top-5 px-1.5 py-0.5 border rounded-2xl shadow-md bg-n-solid-2 border-n-strong group-hover/equipe:flex [@media(hover:none)]:group-focus-within/equipe:flex"
      :class="{
        'ltr:right-1 rtl:left-1': direita,
        'ltr:left-9 rtl:right-9': !direita && comAutor,
        'ltr:left-1 rtl:right-1': !direita && !comAutor,
      }"
    >
      <button
        v-for="emoji in EMOJIS_REACAO"
        :key="emoji"
        type="button"
        class="px-1 py-0.5 text-sm rounded-lg cursor-pointer hover:bg-n-alpha-2"
        @click="reagir(emoji)"
      >
        {{ emoji }}
      </button>
      <button
        type="button"
        class="flex items-center px-1 py-0.5 text-sm rounded-lg cursor-pointer text-n-slate-11 hover:bg-n-alpha-2"
        :title="t('RAMON.EQUIPE.RESPONDER')"
        :aria-label="t('RAMON.EQUIPE.RESPONDER')"
        @click="$emit('responder')"
      >
        <span class="i-lucide-reply size-3.5" />
      </button>
    </div>
    <div
      v-if="selos.length"
      class="relative flex flex-wrap gap-1 mb-1 -mt-1"
      :class="{ 'ltr:mr-2 rtl:ml-2': direita }"
    >
      <component
        :is="podeReagir ? 'button' : 'span'"
        v-for="selo in selos"
        :key="selo.emoji"
        data-testid="selo"
        class="px-1.5 text-xs border rounded-xl text-n-slate-12"
        :class="[
          selo.minha
            ? 'border-n-blue-11 bg-n-blue-9/[.18]'
            : 'border-n-strong bg-n-alpha-2',
          { 'cursor-pointer': podeReagir },
        ]"
        :title="selo.nomes.join(', ')"
        @click="reagir(selo.emoji)"
      >
        {{ selo.emoji }} {{ selo.total }}
      </component>
    </div>
  </div>
</template>
