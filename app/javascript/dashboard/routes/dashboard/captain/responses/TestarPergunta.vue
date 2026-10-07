<script setup>
// "Testar pergunta" (I-FQ2): digite como o lead perguntaria e veja as FAQs que
// a ferramenta faq_lookup do assistente acharia, na mesma ordem (até 5).
// Leitura pura: não grava nada, não chama a IA.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import {
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();
const pergunta = ref('');
const resultado = ref(null); // null = ainda não testou
const testando = ref(false);
const erro = ref(false);
const vazio = computed(() => !pergunta.value.trim());

const testar = async () => {
  const texto = pergunta.value.trim();
  if (!texto || testando.value) return;
  testando.value = true;
  erro.value = false;
  try {
    const { data } = await CaptainAssistantAPI.buscarFaq(
      props.assistantId,
      texto
    );
    resultado.value = data.payload;
  } catch (e) {
    erro.value = true;
    resultado.value = null;
  } finally {
    testando.value = false;
  }
};
</script>

<template>
  <section data-testid="testar-pergunta" class="mb-4" :class="CARTAO">
    <h2 :class="TITULO">{{ t('INTEL.FAQ.TESTAR.TITULO') }}</h2>
    <p class="mt-1 text-xs text-n-slate-10">
      {{ t('INTEL.FAQ.TESTAR.AJUDA') }}
    </p>
    <form class="flex items-center gap-2 mt-2" @submit.prevent="testar">
      <input
        v-model="pergunta"
        data-testid="testar-pergunta-campo"
        :class="CAMPO"
        :placeholder="t('INTEL.FAQ.TESTAR.PLACEHOLDER')"
      />
      <Button
        type="submit"
        class="shrink-0"
        size="sm"
        :label="t('INTEL.FAQ.TESTAR.BOTAO')"
        :is-loading="testando"
        :disabled="vazio || testando"
      />
    </form>
    <p v-if="erro" class="mt-2 text-sm text-n-ruby-11">
      {{ t('INTEL.FAQ.TESTAR.ERRO') }}
    </p>
    <p
      v-else-if="resultado && !resultado.length"
      data-testid="testar-pergunta-nada"
      class="mt-2"
      :class="[AVISO, TOM.amber]"
    >
      {{ t('INTEL.FAQ.TESTAR.NADA') }}
    </p>
    <ol v-else-if="resultado" class="flex flex-col gap-2 mt-3 list-none">
      <li
        v-for="(faq, posicao) in resultado"
        :key="faq.id"
        data-testid="testar-pergunta-faq"
        class="flex items-start gap-2"
      >
        <span class="shrink-0" :class="[CHIP, TOM.blue]">
          {{ posicao + 1 }}
        </span>
        <div class="min-w-0">
          <p
            class="flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12"
          >
            <span class="font-medium">{{ faq.question }}</span>
            <span v-if="faq.tese" :class="[CHIP, TOM.slate]">
              {{ t(`INTEL.TESE.${faq.tese}`) }}
            </span>
          </p>
          <p class="text-xs text-n-slate-11 line-clamp-2">{{ faq.answer }}</p>
        </div>
      </li>
    </ol>
  </section>
</template>
