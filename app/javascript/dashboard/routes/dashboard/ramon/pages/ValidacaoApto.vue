<script setup>
// Aguardando validação (Ramon::ContratoApto): os contratos limpos que o advogado
// da tese (ou o admin) precisa validar. Valida em lote os marcados; devolve um a
// um, com motivo. Sem resposta em 5 dias úteis o backend dá o apto sozinho.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import LeadAptosAPI from 'dashboard/api/leadAptos';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { CAMPO, CARTAO, CHIP, ROTULO, TEXTAREA, TOM } from '../helpers/ui';

defineOptions({ name: 'RamonValidacaoApto' });

const { t } = useI18n();
const store = useStore();
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const agentes = computed(() => store.getters['agents/getAgents'] || []);
const loading = ref(true);
const error = ref(false);
const fila = ref([]);
const marcados = ref([]);
const salvando = ref(false);
const devolvendo = ref(null);
const motivo = ref('');

const dataBr = iso => (iso ? new Date(iso).toLocaleDateString('pt-BR') : '');

const carregar = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await LeadAptosAPI.get();
    fila.value = data;
    marcados.value = [];
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

const validarLote = async () => {
  salvando.value = true;
  try {
    const { data } = await LeadAptosAPI.validarLote(marcados.value);
    useAlert(
      t('RAMON.VALIDACAO_APTO.VALIDADOS', { count: data.validados.length })
    );
    await carregar();
  } catch {
    useAlert(t('RAMON.VALIDACAO_APTO.ERRO'));
  } finally {
    salvando.value = false;
  }
};

// admin escolhe o advogado do caso (tese sem advogado fixo, ex.: IR)
const designar = async (id, event) => {
  const userId = Number(event.target.value) || null;
  try {
    await LeadsAPI.apto(id, { acao: 'designar', userId });
    await carregar();
  } catch {
    useAlert(t('RAMON.VALIDACAO_APTO.ERRO'));
  }
};

const devolver = async id => {
  salvando.value = true;
  try {
    await LeadsAPI.apto(id, { acao: 'devolver', motivo: motivo.value.trim() });
    devolvendo.value = null;
    motivo.value = '';
    await carregar();
  } catch {
    useAlert(t('RAMON.VALIDACAO_APTO.ERRO'));
  } finally {
    salvando.value = false;
  }
};

onMounted(() => {
  carregar();
  if (isAdmin.value && !agentes.value.length) store.dispatch('agents/get');
});
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-5xl flex-col gap-4">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.VALIDACAO_APTO.TITLE')"
        :subtitle="t('RAMON.VALIDACAO_APTO.SUBTITLE')"
        compact
      />
      <div v-if="loading" class="h-32 animate-pulse rounded-xl bg-n-alpha-2" />
      <div v-else-if="error" class="flex flex-col items-start gap-1 text-sm">
        <p class="m-0 text-n-ruby-11">{{ t('RAMON.VALIDACAO_APTO.ERRO') }}</p>
        <Button
          link
          xs
          :label="t('RAMON.VALIDACAO_APTO.RETRY')"
          @click="carregar"
        />
      </div>
      <p
        v-else-if="!fila.length"
        data-testid="validacao-vazia"
        class="m-0 text-sm text-n-slate-10"
      >
        {{ t('RAMON.VALIDACAO_APTO.VAZIA') }}
      </p>
      <template v-else>
        <div>
          <Button
            data-testid="validacao-lote"
            sm
            :disabled="salvando || !marcados.length"
            :label="
              t('RAMON.VALIDACAO_APTO.VALIDAR_LOTE', { count: marcados.length })
            "
            @click="validarLote"
          />
        </div>
        <ul class="m-0 flex flex-col gap-2 p-0">
          <li
            v-for="caso in fila"
            :key="caso.id"
            data-testid="validacao-linha"
            :class="CARTAO"
            class="flex flex-col gap-2"
          >
            <div class="flex flex-wrap items-center gap-4">
              <input
                v-if="caso.apto_situacao === 'aguardando'"
                v-model="marcados"
                type="checkbox"
                :value="caso.id"
                data-testid="validacao-marcar"
                :aria-label="caso.name"
              />
              <router-link
                class="text-sm font-medium text-n-blue-11 underline"
                :to="{ name: 'ramon_lead_dossie', params: { leadId: caso.id } }"
              >
                {{ caso.name }}
              </router-link>
              <span :class="[CHIP, TOM.slate]">{{ caso.tese }}</span>
              <span class="text-xs text-n-slate-11">
                {{
                  t('RAMON.VALIDACAO_APTO.CLOSER', { nome: caso.closer || '—' })
                }}
              </span>
              <span
                class="ms-auto text-xs"
                :class="
                  caso.apto_situacao === 'devolvido'
                    ? 'text-n-amber-11'
                    : 'text-n-slate-11'
                "
              >
                {{ t(`RAMON.APTO.SITUACAO.${caso.apto_situacao}`) }}
                <template v-if="caso.apto_prazo">
                  ·
                  {{ t('RAMON.APTO.PRAZO', { data: dataBr(caso.apto_prazo) }) }}
                  ·
                  {{
                    t('RAMON.VALIDACAO_APTO.DIAS_RESTANTES', {
                      count: caso.dias_restantes,
                    })
                  }}
                </template>
              </span>
            </div>
            <p
              v-if="
                caso.apto_situacao === 'aguardando' &&
                caso.assinatura_conferida === false
              "
              data-testid="validacao-sem-assinatura"
              class="m-0 text-xs text-n-amber-11"
            >
              {{ t('RAMON.APTO.SEM_ASSINATURA') }}
            </p>
            <p
              v-if="caso.sem_validador"
              data-testid="validacao-sem-validador"
              class="m-0 text-xs text-n-amber-11"
            >
              {{ t('RAMON.VALIDACAO_APTO.SEM_VALIDADOR') }}
            </p>
            <label v-if="isAdmin" :class="ROTULO" class="max-w-xs">
              {{ t('RAMON.APTO.DESIGNAR') }}
              <select
                data-testid="validacao-designar"
                :class="CAMPO"
                :value="caso.validador_id || ''"
                @change="designar(caso.id, $event)"
              >
                <option value="">{{ t('RAMON.APTO.DESIGNAR_TESE') }}</option>
                <option
                  v-for="agente in agentes"
                  :key="agente.id"
                  :value="agente.id"
                >
                  {{ agente.name }}
                </option>
              </select>
            </label>
            <p v-if="caso.devolvido_motivo" class="m-0 text-xs text-n-amber-11">
              {{ caso.devolvido_motivo }}
            </p>
            <div v-if="caso.apto_situacao === 'aguardando'">
              <Button
                v-if="devolvendo !== caso.id"
                data-testid="validacao-devolver"
                xs
                faded
                slate
                :label="t('RAMON.APTO.DEVOLVER')"
                @click="devolvendo = caso.id"
              />
              <div v-else class="flex flex-col gap-2">
                <label :class="ROTULO">
                  {{ t('RAMON.APTO.MOTIVO') }}
                  <textarea
                    v-model="motivo"
                    data-testid="validacao-motivo"
                    rows="2"
                    :class="TEXTAREA"
                  />
                </label>
                <div>
                  <Button
                    data-testid="validacao-devolver-confirmar"
                    xs
                    color="amber"
                    :disabled="salvando || !motivo.trim()"
                    :label="t('RAMON.APTO.DEVOLVER_CONFIRMAR')"
                    @click="devolver(caso.id)"
                  />
                </div>
              </div>
            </div>
          </li>
        </ul>
      </template>
    </div>
  </div>
</template>
