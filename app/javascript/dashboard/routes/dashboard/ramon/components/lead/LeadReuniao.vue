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

const botao = ativo =>
  ativo
    ? 'bg-n-iris-9 text-white'
    : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 hover:text-n-slate-12';
</script>

<template>
  <div data-testid="lead-reuniao" class="mb-3">
    <label class="block mb-1 text-xs text-n-slate-10">
      {{ $t('RAMON.REUNIAO.TITULO') }}
    </label>
    <div class="flex flex-wrap items-center gap-2">
      <template v-if="podeMarcar">
        <button
          data-testid="reuniao-qualificada"
          :disabled="saving"
          class="px-3 py-1.5 text-xs rounded-lg disabled:opacity-60"
          :class="botao(lead.reuniao_resultado === 'qualificada')"
          @click="marcar('qualificada')"
        >
          {{ $t('RAMON.REUNIAO.QUALIFICADA') }}
        </button>
        <button
          data-testid="reuniao-nao-qualificada"
          :disabled="saving"
          class="px-3 py-1.5 text-xs rounded-lg disabled:opacity-60"
          :class="botao(lead.reuniao_resultado === 'nao_qualificada')"
          @click="marcar('nao_qualificada')"
        >
          {{ $t('RAMON.REUNIAO.NAO_QUALIFICADA') }}
        </button>
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
        class="text-xs text-n-slate-10"
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
