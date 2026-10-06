<script setup>
// Texto com variáveis clicáveis (mockup .vars): insere {chave} onde está o cursor.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ROTULO, TEXTAREA } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { VARIAVEIS } from './fluxo';

const props = defineProps({
  modelValue: { type: String, default: '' },
  rotulo: { type: String, required: true },
  linhas: { type: Number, default: 4 },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const area = ref(null);
const fichas = VARIAVEIS.map(v => ({ v, texto: `{${v}}` }));

const inserir = token => {
  const el = area.value;
  const valor = props.modelValue || '';
  const inicio = el.selectionStart ?? valor.length;
  const fim = el.selectionEnd ?? valor.length;
  emit('update:modelValue', valor.slice(0, inicio) + token + valor.slice(fim));
};
</script>

<template>
  <div>
    <label :class="ROTULO">
      {{ rotulo }}
      <textarea
        ref="area"
        :class="TEXTAREA"
        :rows="linhas"
        :value="modelValue"
        @input="emit('update:modelValue', $event.target.value)"
      />
    </label>
    <div class="mt-2 flex flex-wrap gap-1">
      <button
        v-for="ficha in fichas"
        :key="ficha.v"
        type="button"
        :data-testid="`var-${ficha.v}`"
        class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 font-mono text-[11.5px] text-n-slate-11 hover:bg-n-blue-9/[0.08] hover:text-n-blue-11"
        @click="inserir(ficha.texto)"
      >
        {{ ficha.texto }}
      </button>
    </div>
    <p class="mt-1.5 text-xs text-n-slate-10">
      {{ t('CAPTAIN_RAMON.FLUXOS.PAINEL.VARIAVEIS_AJUDA') }}
    </p>
  </div>
</template>
