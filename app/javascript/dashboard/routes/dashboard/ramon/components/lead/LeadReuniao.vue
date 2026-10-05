<script setup>
// Operação SDR + Closer (playbook §13, itens 4–5): o Closer marca a reunião
// (qualificada ou não — base do prêmio do SDR) e o selo mostra o caminho até
// o contrato limpo. Quem pode marcar: Closer do lead, time closer (lead sem
// Closer — o backend confere) ou gestor.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { contratoLimpoStatus } from '../../helpers/contratoLimpo';
import Button from 'dashboard/components-next/button/Button.vue';
import { SECAO } from '../../helpers/ui';

const props = defineProps({ lead: { type: Object, required: true } });

const store = useStore();
const { t } = useI18n();
const saving = ref(false);

const podeMarcar = computed(() => {
  if (store.getters.getCurrentRole === 'administrator') return true;
  const closerId = props.lead.closer_id;
  return !closerId || closerId === store.getters.getCurrentUserID;
});

const registradaEm = computed(() =>
  props.lead.reuniao_registrada_em
    ? new Date(props.lead.reuniao_registrada_em).toLocaleDateString('pt-BR')
    : ''
);

const contrato = computed(() => contratoLimpoStatus(props.lead));

const marcar = async resultado => {
  saving.value = true;
  try {
    await store.dispatch('leads/registrarReuniao', {
      id: props.lead.id,
      resultado,
    });
  } catch (e) {
    useAlert(t('RAMON.REUNIAO.ERRO'));
  } finally {
    saving.value = false;
  }
};

// escolha marcada = primário azul; a outra = secundário
const variante = ativo =>
  ativo
    ? { variant: 'solid', color: 'blue' }
    : { variant: 'faded', color: 'slate' };
</script>

<template>
  <div data-testid="lead-reuniao" class="mt-3" :class="SECAO">
    <label class="block mb-1 text-xs text-n-slate-10">
      {{ $t('RAMON.REUNIAO.TITULO') }}
    </label>
    <div class="flex flex-wrap items-center gap-2">
      <template v-if="podeMarcar">
        <Button
          data-testid="reuniao-qualificada"
          size="sm"
          v-bind="variante(lead.reuniao_resultado === 'qualificada')"
          :disabled="saving"
          :label="$t('RAMON.REUNIAO.QUALIFICADA')"
          @click="marcar('qualificada')"
        />
        <Button
          data-testid="reuniao-nao-qualificada"
          size="sm"
          v-bind="variante(lead.reuniao_resultado === 'nao_qualificada')"
          :disabled="saving"
          :label="$t('RAMON.REUNIAO.NAO_QUALIFICADA')"
          @click="marcar('nao_qualificada')"
        />
      </template>
      <span v-else-if="lead.reuniao_resultado" class="text-sm text-n-slate-12">
        {{ $t(`RAMON.REUNIAO.RESULTADO.${lead.reuniao_resultado}`) }}
      </span>
      <span v-else class="text-sm text-n-slate-10">
        {{ $t('RAMON.REUNIAO.SEM_REGISTRO') }}
      </span>
      <span
        v-if="registradaEm"
        data-testid="reuniao-data"
        class="font-mono text-xs text-n-slate-10"
      >
        {{ $t('RAMON.REUNIAO.REGISTRADA_EM', { data: registradaEm }) }}
      </span>
    </div>
    <p
      v-if="contrato"
      data-testid="contrato-limpo-selo"
      class="mt-2 text-xs"
      :class="contrato.key === 'LIMPO' ? 'text-n-teal-11' : 'text-n-amber-11'"
    >
      {{ $t(`RAMON.CONTRATO.${contrato.key}`, { count: contrato.count }) }}
    </p>
  </div>
</template>
