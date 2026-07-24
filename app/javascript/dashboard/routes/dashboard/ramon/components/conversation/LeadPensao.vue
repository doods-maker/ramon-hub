<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadPensao' });

const { t } = useI18n();

const isLoading = ref(false);
const hasError = ref(false);
const errorMessage = ref('');
const resultado = ref(null);
const decisoes = ref({ desemprego: null, facultativo: null, uniao_2_anos: null });

const dataObito = ref('');
const valorBeneficioObito = ref('');
const dependentes = ref([
  { tipo: 'conjuge', nascimento: '', invalido: false, inicio_uniao: '' },
]);

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));
const dataBr = iso => (iso ? iso.split('-').reverse().join('/') : '');

// "1518", "1518.50" ou "1518,50" — nunca input number pra dinheiro (lição #95).
const decimalValido = v => /^\d+([.,]\d{1,2})?$/.test(v);
const normDecimal = v => String(v).replace(',', '.');

const adicionarDependente = () =>
  dependentes.value.push({
    tipo: 'filho',
    nascimento: '',
    invalido: false,
    inicio_uniao: '',
  });
const removerDependente = i => dependentes.value.splice(i, 1);

const decisoesPreenchidas = () => {
  const d = {};
  if (decisoes.value.desemprego !== null)
    d.desemprego = decisoes.value.desemprego;
  if (decisoes.value.facultativo !== null)
    d.facultativo = decisoes.value.facultativo;
  if (decisoes.value.uniao_2_anos !== null)
    d.uniao_2_anos = decisoes.value.uniao_2_anos;
  return d;
};

const dependentesPayload = () =>
  dependentes.value.map(dep => {
    const item = { tipo: dep.tipo, invalido: Boolean(dep.invalido) };
    if (dep.nascimento) item.nascimento = dep.nascimento;
    if (dep.tipo === 'conjuge' && dep.inicio_uniao)
      item.inicio_uniao = dep.inicio_uniao;
    return item;
  });

const payload = () => {
  const p = {
    data_obito: dataObito.value,
    dependentes: dependentesPayload(),
    decisoes: decisoesPreenchidas(),
  };
  if (valorBeneficioObito.value && decimalValido(valorBeneficioObito.value)) {
    p.valor_beneficio_obito = normDecimal(valorBeneficioObito.value);
  }
  return p;
};

const chamar = async () => {
  hasError.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.pensao(props.lead.id, payload());
    resultado.value = data;
  } catch (error) {
    hasError.value = true;
    errorMessage.value =
      error?.response?.data?.error || t('RAMON.SIMULADOR.PENSAO_ERRO');
  }
};

const calcular = async () => {
  isLoading.value = true;
  await chamar();
  isLoading.value = false;
};

// pendência de 1 clique: `false` explícito na resposta "Não" (nunca omitido).
const responder = (tipo, valor) => {
  decisoes.value[tipo] = valor;
  calcular();
};

// erro nunca se mascara de vazio: retry refaz a mesma ação que falhou.
const retry = () => calcular();

const cenarioBorda = cenario =>
  cenario.mantida
    ? 'border-n-teal-9 bg-n-teal-3'
    : 'border-n-ruby-9 bg-n-ruby-3';
const cenarioTexto = cenario =>
  cenario.mantida ? 'text-n-teal-11' : 'text-n-ruby-11';

const isCessaDict = v => v !== null && typeof v === 'object';
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-pensao">
    <p
      class="text-xs font-medium text-n-amber-11 p-2 rounded-lg bg-n-amber-3 border border-n-amber-6"
      data-testid="pensao-aviso-cnis-falecido"
    >
      {{ $t('RAMON.SIMULADOR.PENSAO_AVISO_CNIS_FALECIDO') }}
    </p>

    <div class="grid grid-cols-2 gap-2">
      <label class="flex flex-col gap-1 text-xs text-n-slate-10">
        {{ $t('RAMON.SIMULADOR.PENSAO_DATA_OBITO') }}
        <input
          v-model="dataObito"
          type="date"
          data-testid="pensao-data-obito"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-10">
        {{ $t('RAMON.SIMULADOR.PENSAO_VALOR_BENEFICIO_OBITO') }}
        <input
          v-model="valorBeneficioObito"
          type="text"
          inputmode="decimal"
          data-testid="pensao-valor-beneficio"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8"
        />
      </label>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-xs font-medium text-n-slate-12">
        {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTES_TITULO') }}
      </span>
      <div
        v-for="(dep, i) in dependentes"
        :key="i"
        class="flex flex-col gap-1 p-1.5 rounded-lg border border-n-weak"
        :data-testid="`pensao-dependente-${i}`"
      >
        <div class="grid grid-cols-2 gap-1">
          <label class="flex flex-col gap-1 text-xs text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_TIPO') }}
            <select
              v-model="dep.tipo"
              :data-testid="`pensao-dependente-tipo-${i}`"
              class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12"
            >
              <option value="conjuge">
                {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_CONJUGE') }}
              </option>
              <option value="filho">
                {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_FILHO') }}
              </option>
              <option value="outro">
                {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_OUTRO') }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_NASCIMENTO') }}
            <input
              v-model="dep.nascimento"
              type="date"
              :data-testid="`pensao-dependente-nascimento-${i}`"
              class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12"
            />
          </label>
        </div>
        <label class="flex items-center gap-2 text-xs text-n-slate-11">
          <input
            v-model="dep.invalido"
            type="checkbox"
            :data-testid="`pensao-dependente-invalido-${i}`"
          />
          {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_INVALIDO') }}
        </label>
        <label
          v-if="dep.tipo === 'conjuge'"
          class="flex flex-col gap-1 text-xs text-n-slate-10"
        >
          {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_INICIO_UNIAO') }}
          <input
            v-model="dep.inicio_uniao"
            type="date"
            :data-testid="`pensao-dependente-uniao-${i}`"
            class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12"
          />
        </label>
        <button
          type="button"
          class="self-start text-xs text-n-ruby-11"
          :data-testid="`pensao-dependente-remover-${i}`"
          @click="removerDependente(i)"
        >
          {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_REMOVER') }}
        </button>
      </div>
      <button
        type="button"
        data-testid="pensao-dependente-add"
        class="self-start text-xs underline text-n-slate-11"
        @click="adicionarDependente"
      >
        {{ $t('RAMON.SIMULADOR.PENSAO_DEPENDENTE_ADICIONAR') }}
      </button>
    </div>

    <button
      type="button"
      data-testid="pensao-calcular"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="!dataObito || !dependentes.length || isLoading"
      @click="calcular"
    >
      {{
        isLoading
          ? $t('RAMON.SIMULADOR.PENSAO_CALCULANDO')
          : $t('RAMON.SIMULADOR.PENSAO_CALCULAR')
      }}
    </button>

    <div v-if="hasError" data-testid="pensao-error">
      <p class="text-sm text-n-ruby-11">{{ errorMessage }}</p>
      <button
        type="button"
        data-testid="pensao-retry"
        class="mt-1 text-xs text-n-iris-11 hover:underline"
        @click="retry"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <template v-if="resultado">
      <div
        v-if="resultado.qualidade_falecido === 'dispensada'"
        class="p-2 rounded-lg border border-n-teal-9 bg-n-teal-3 text-xs text-n-teal-11 font-medium"
        data-testid="pensao-qualidade-dispensada"
      >
        {{ $t('RAMON.SIMULADOR.PENSAO_QUALIDADE_DISPENSADA') }}
      </div>

      <div
        v-else-if="resultado.qualidade_falecido?.cenarios"
        class="flex flex-col gap-2"
        data-testid="pensao-cenarios"
      >
        <div
          v-if="resultado.qualidade_falecido.cenarios.unico"
          class="flex flex-col gap-1 p-2 rounded-lg border"
          :class="cenarioBorda(resultado.qualidade_falecido.cenarios.unico)"
          data-testid="pensao-cenario-unico"
        >
          <p
            class="text-sm font-medium"
            :class="cenarioTexto(resultado.qualidade_falecido.cenarios.unico)"
          >
            {{
              resultado.qualidade_falecido.cenarios.unico.mantida
                ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
            }}
            <template v-if="resultado.qualidade_falecido.cenarios.unico.ate">
              — {{ dataBr(resultado.qualidade_falecido.cenarios.unico.ate) }}
            </template>
          </p>
          <p class="text-xs text-n-slate-10">
            {{ resultado.qualidade_falecido.cenarios.unico.fundamento }}
          </p>
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div
            v-if="resultado.qualidade_falecido.cenarios.sem_desemprego"
            class="flex flex-col gap-1 p-2 rounded-lg border"
            :class="
              cenarioBorda(resultado.qualidade_falecido.cenarios.sem_desemprego)
            "
            data-testid="pensao-cenario-sem-desemprego"
          >
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.ELEG_SEM_DESEMPREGO') }}
            </span>
            <p
              class="text-sm font-medium"
              :class="
                cenarioTexto(
                  resultado.qualidade_falecido.cenarios.sem_desemprego
                )
              "
            >
              {{
                resultado.qualidade_falecido.cenarios.sem_desemprego.mantida
                  ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                  : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
              }}
              <template
                v-if="resultado.qualidade_falecido.cenarios.sem_desemprego.ate"
              >
                —
                {{
                  dataBr(
                    resultado.qualidade_falecido.cenarios.sem_desemprego.ate
                  )
                }}
              </template>
            </p>
            <p class="text-xs text-n-slate-10">
              {{
                resultado.qualidade_falecido.cenarios.sem_desemprego
                  .fundamento
              }}
            </p>
          </div>
          <div
            v-if="resultado.qualidade_falecido.cenarios.com_desemprego"
            class="flex flex-col gap-1 p-2 rounded-lg border"
            :class="
              cenarioBorda(resultado.qualidade_falecido.cenarios.com_desemprego)
            "
            data-testid="pensao-cenario-com-desemprego"
          >
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.ELEG_COM_DESEMPREGO') }}
            </span>
            <p
              class="text-sm font-medium"
              :class="
                cenarioTexto(
                  resultado.qualidade_falecido.cenarios.com_desemprego
                )
              "
            >
              {{
                resultado.qualidade_falecido.cenarios.com_desemprego.mantida
                  ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                  : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
              }}
              <template
                v-if="resultado.qualidade_falecido.cenarios.com_desemprego.ate"
              >
                —
                {{
                  dataBr(
                    resultado.qualidade_falecido.cenarios.com_desemprego.ate
                  )
                }}
              </template>
            </p>
            <p class="text-xs text-n-slate-10">
              {{
                resultado.qualidade_falecido.cenarios.com_desemprego
                  .fundamento
              }}
            </p>
          </div>
        </div>
      </div>

      <div
        v-if="
          resultado.decisoes_pendentes && resultado.decisoes_pendentes.length
        "
        class="flex flex-col gap-2"
        data-testid="pensao-pendencias"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{ $t('RAMON.SIMULADOR.ELEG_PENDENCIAS') }}
        </span>
        <div
          v-for="(pend, i) in resultado.decisoes_pendentes"
          :key="i"
          class="flex flex-col gap-1 p-2 rounded-lg bg-n-amber-3 border border-n-amber-6"
          :data-testid="`pensao-pendencia-${i}`"
        >
          <p class="text-xs text-n-amber-11 font-medium">{{ pend.pergunta }}</p>
          <p class="text-xs text-n-slate-11">
            {{ $t('RAMON.SIMULADOR.ELEG_SIM') }}:
            {{ pend.efeito_por_resposta?.sim }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ $t('RAMON.SIMULADOR.ELEG_NAO') }}:
            {{ pend.efeito_por_resposta?.nao }}
          </p>
          <div class="flex gap-2">
            <button
              type="button"
              data-testid="pensao-pendencia-sim"
              class="px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="isLoading"
              @click="responder(pend.tipo, true)"
            >
              {{ $t('RAMON.SIMULADOR.ELEG_SIM') }}
            </button>
            <button
              type="button"
              data-testid="pensao-pendencia-nao"
              class="px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="isLoading"
              @click="responder(pend.tipo, false)"
            >
              {{ $t('RAMON.SIMULADOR.ELEG_NAO') }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-if="resultado.base"
        class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1 border border-n-weak"
        data-testid="pensao-base"
      >
        <p class="text-sm text-n-slate-12">
          <span class="text-n-slate-10"
            >{{ $t('RAMON.SIMULADOR.PENSAO_BASE') }}:</span
          >
          {{ money(resultado.base.valor) }}
          <span class="text-xs text-n-slate-10">
            ({{ resultado.base.origem }})
          </span>
        </p>
      </div>

      <div class="flex gap-4">
        <p class="text-sm text-n-slate-12">
          <span class="text-n-slate-10"
            >{{ $t('RAMON.SIMULADOR.PENSAO_PERCENTUAL') }}:</span
          >
          <span class="font-semibold" data-testid="pensao-percentual">
            {{ resultado.percentual }}%
          </span>
        </p>
        <p class="text-sm text-n-slate-12">
          <span class="text-n-slate-10"
            >{{ $t('RAMON.SIMULADOR.PENSAO_RMI') }}:</span
          >
          <span class="font-semibold" data-testid="pensao-rmi">
            {{ money(resultado.rmi) }}
          </span>
        </p>
      </div>

      <div
        v-if="resultado.quotas && resultado.quotas.length"
        class="flex flex-col gap-2"
        data-testid="pensao-quotas"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{ $t('RAMON.SIMULADOR.PENSAO_QUOTAS_TITULO') }}
        </span>
        <div
          v-for="(q, i) in resultado.quotas"
          :key="i"
          class="flex flex-col gap-1 p-2 rounded-lg border border-n-weak"
          :data-testid="`pensao-quota-${i}`"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ q.tipo }}
            </span>
            <span class="text-sm font-semibold text-n-slate-12">
              {{ q.quota_pct }}%
            </span>
          </div>
          <template v-if="!q.cessa_em">
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.PENSAO_CESSA_VITALICIA') }}
            </span>
          </template>
          <template v-else-if="isCessaDict(q.cessa_em)">
            <div
              class="flex flex-col gap-0.5 text-xs text-n-slate-10"
              :data-testid="`pensao-quota-cessa-dict-${i}`"
            >
              <span>
                {{ $t('RAMON.SIMULADOR.PENSAO_UNIAO_MENOR2') }}:
                {{ dataBr(q.cessa_em.uniao_menor_2_anos) }}
              </span>
              <span>
                {{ $t('RAMON.SIMULADOR.PENSAO_UNIAO_2OUMAIS') }}:
                {{ dataBr(q.cessa_em.uniao_2_anos_ou_mais) }}
              </span>
            </div>
          </template>
          <template v-else>
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.PENSAO_CESSA_EM') }}:
              {{ dataBr(q.cessa_em) }}
            </span>
          </template>
          <p class="text-xs text-n-slate-10">{{ q.fundamento }}</p>
          <ul
            v-if="q.avisos && q.avisos.length"
            class="flex flex-col gap-0.5 text-xs text-n-amber-11 list-disc ps-4"
          >
            <li v-for="(aviso, j) in q.avisos" :key="j">{{ aviso }}</li>
          </ul>
        </div>
      </div>

      <ul
        v-if="resultado.avisos && resultado.avisos.length"
        class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        data-testid="pensao-avisos"
      >
        <li v-for="(aviso, i) in resultado.avisos" :key="i">{{ aviso }}</li>
      </ul>
    </template>
  </div>
</template>
