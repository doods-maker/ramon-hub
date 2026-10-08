<script setup>
// Texto final que o assistente recebe (I-CF6): o dele (diretrizes, proteções e a lista de skills, do jeito
// que vão para a IA) e o de cada skill ligada. Só leitura.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import {
  FUNDO_JANELA,
  JANELA,
  RODAPE_JANELA,
  TITULO,
  TITULO_JANELA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: { type: Number, required: true },
});
const emit = defineEmits(['fechar']);
const { t } = useI18n();
onKeyStroke('Escape', () => emit('fechar'));

const PRE =
  'mt-1 max-h-72 overflow-auto whitespace-pre-wrap rounded-lg bg-n-alpha-2 p-2 font-mono text-[11px] text-n-slate-11';

const texto = ref(null);
const erro = ref(false);

onMounted(async () => {
  try {
    const { data } = await CaptainAssistant.textoFinal(props.assistantId);
    texto.value = data;
  } catch (e) {
    erro.value = true;
  }
});
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div :class="JANELA" class="!w-[44rem]" data-testid="texto-final">
      <h3 :class="TITULO_JANELA">{{ t('INTEL.CONFIG.TEXTO_FINAL') }}</h3>
      <p class="mb-3 text-xs text-n-slate-11">
        {{ t('INTEL.CONFIG.TEXTO_FINAL_AJUDA') }}
      </p>
      <p v-if="erro" class="text-sm text-n-ruby-11">
        {{ t('INTEL.CONFIG.TEXTO_FINAL_ERRO') }}
      </p>
      <template v-else-if="texto">
        <p :class="TITULO">{{ t('INTEL.CONFIG.TEXTO_FINAL_ASSISTENTE') }}</p>
        <pre :class="PRE">{{ texto.assistente }}</pre>
        <template v-for="skill in texto.skills" :key="skill.title">
          <p class="mt-3" :class="TITULO">
            {{ t('INTEL.CONFIG.TEXTO_FINAL_SKILL', { nome: skill.title }) }}
          </p>
          <pre :class="PRE">{{ skill.texto }}</pre>
        </template>
      </template>
      <div :class="RODAPE_JANELA">
        <Button
          sm
          slate
          faded
          :label="t('INTEL.CONFIG.FECHAR')"
          @click="emit('fechar')"
        />
      </div>
    </div>
  </div>
</template>
