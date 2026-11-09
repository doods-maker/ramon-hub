<script setup>
// Contrato apto (Ramon::ContratoApto): depois do contrato limpo, o advogado da
// tese valida ("Apto para protocolo") ou devolve com motivo; sem resposta em 5
// dias úteis o backend dá o apto sozinho. O Closer do lead reenvia o devolvido;
// o admin designa o advogado do lead (tese sem advogado fixo, ex.: IR). Quem
// pode cada ação o backend confere (apto_pode_validar vem do servidor).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { SECAO } from '../../helpers/ui';

const props = defineProps({ lead: { type: Object, required: true } });

const store = useStore();
const { t } = useI18n();
const saving = ref(false);
const devolvendo = ref(false);
const motivo = ref('');

const situacao = computed(() => props.lead.apto_situacao);
const admin = computed(() => store.getters.getCurrentRole === 'administrator');
const podeReenviar = computed(
  () =>
    situacao.value === 'devolvido' &&
    (admin.value || props.lead.closer_id === store.getters.getCurrentUserID)
);
const agentes = computed(() => store.getters['agents/getAgents'] || []);
const prazo = computed(() =>
  props.lead.apto_prazo
    ? new Date(props.lead.apto_prazo).toLocaleDateString('pt-BR')
    : ''
);

const agir = async (acao, extra = {}) => {
  saving.value = true;
  try {
    await store.dispatch('leads/apto', { id: props.lead.id, acao, ...extra });
    devolvendo.value = false;
    motivo.value = '';
  } catch (e) {
    useAlert(t('RAMON.APTO.ERRO'));
  } finally {
    saving.value = false;
  }
};

// vazio = volta para os advogados da tese
const designar = event => {
  agir('designar', { userId: Number(event.target.value) || null });
};
</script>

<template>
  <div v-if="situacao" data-testid="lead-apto" class="mt-3" :class="SECAO">
    <label class="block mb-1 text-xs text-n-slate-10">
      {{ $t('RAMON.APTO.TITULO') }}
    </label>
    <p
      class="text-sm"
      :class="
        situacao.startsWith('apto') ? 'text-n-teal-11' : 'text-n-slate-12'
      "
    >
      {{ $t(`RAMON.APTO.SITUACAO.${situacao}`) }}
      <span
        v-if="prazo"
        data-testid="apto-prazo"
        class="font-mono text-xs text-n-slate-10"
      >
        {{ $t('RAMON.APTO.PRAZO', { data: prazo }) }}
      </span>
    </p>
    <p
      v-if="situacao === 'devolvido' && lead.devolvido_motivo"
      class="mt-1 text-xs text-n-amber-11"
    >
      {{ lead.devolvido_motivo }}
    </p>

    <div
      v-if="situacao === 'aguardando' && lead.apto_pode_validar"
      class="flex flex-wrap items-center gap-2 mt-2"
    >
      <Button
        data-testid="apto-validar"
        size="sm"
        color="blue"
        :disabled="saving"
        :label="$t('RAMON.APTO.VALIDAR')"
        @click="agir('validar')"
      />
      <Button
        data-testid="apto-devolver"
        size="sm"
        variant="faded"
        color="slate"
        :disabled="saving"
        :label="$t('RAMON.APTO.DEVOLVER')"
        @click="devolvendo = true"
      />
    </div>
    <div v-if="devolvendo" class="mt-2">
      <textarea
        v-model="motivo"
        data-testid="apto-motivo"
        rows="2"
        class="w-full text-sm"
        :placeholder="$t('RAMON.APTO.MOTIVO')"
      />
      <Button
        data-testid="apto-devolver-confirmar"
        size="sm"
        color="ruby"
        :disabled="saving || !motivo.trim()"
        :label="$t('RAMON.APTO.DEVOLVER_CONFIRMAR')"
        @click="agir('devolver', { motivo: motivo.trim() })"
      />
    </div>

    <Button
      v-if="podeReenviar"
      data-testid="apto-reenviar"
      class="mt-2"
      size="sm"
      color="blue"
      :disabled="saving"
      :label="$t('RAMON.APTO.REENVIAR')"
      @click="agir('reenviar')"
    />

    <label v-if="admin" class="block mt-2 text-xs text-n-slate-10">
      {{ $t('RAMON.APTO.DESIGNAR') }}
      <select
        data-testid="apto-designar"
        class="block w-full mt-1 text-sm"
        :value="lead.validador_id || ''"
        :disabled="saving"
        @change="designar"
      >
        <option value="">{{ $t('RAMON.APTO.DESIGNAR_TESE') }}</option>
        <option v-for="agente in agentes" :key="agente.id" :value="agente.id">
          {{ agente.name }}
        </option>
      </select>
    </label>
  </div>
</template>
