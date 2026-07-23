<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
  der: { type: String, default: '' },
});
defineOptions({ name: 'LeadElegibilidade' });

const { t } = useI18n();

const isLoading = ref(false);
const simulando = ref(false);
const ocupado = computed(() => isLoading.value || simulando.value);
const hasError = ref(false);
const errorMessage = ref('');
const resultado = ref(null);
const decisoes = ref({ desemprego: null, facultativo: null });
// erro nunca se mascara de vazio: retry refaz a mesma ação que falhou.
const ultimaAcao = ref('analisar');

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));
const dataBr = iso => (iso ? iso.split('-').reverse().join('/') : '');
const simNao = valor =>
  valor === true
    ? t('RAMON.SIMULADOR.ELEG_SIM')
    : t('RAMON.SIMULADOR.ELEG_NAO');

const decisoesPreenchidas = () => {
  const d = {};
  if (decisoes.value.desemprego !== null)
    d.desemprego = decisoes.value.desemprego;
  if (decisoes.value.facultativo !== null)
    d.facultativo = decisoes.value.facultativo;
  return d;
};

const chamar = async (extra = {}) => {
  hasError.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.elegibilidade(props.lead.id, {
      der: props.der,
      decisoes: decisoesPreenchidas(),
      ...extra,
    });
    resultado.value = data;
  } catch (error) {
    hasError.value = true;
    errorMessage.value =
      error?.response?.data?.error || t('RAMON.SIMULADOR.ELEG_ERRO');
  }
};

const analisar = async () => {
  ultimaAcao.value = 'analisar';
  isLoading.value = true;
  await chamar();
  isLoading.value = false;
};

const responder = (tipo, valor) => {
  decisoes.value[tipo] = valor;
  analisar();
};

const simular = async () => {
  ultimaAcao.value = 'simular';
  simulando.value = true;
  await chamar({ simular_lacunas: true });
  simulando.value = false;
};

const retry = () => (ultimaAcao.value === 'simular' ? simular() : analisar());

// só as linhas que mudaram (elegibilidade, RMI ou previsão) — o resto some
// pra não afogar o advogado em cartões que a lacuna não afetou.
const cartoesAlterados = sim =>
  (sim.cartoes || []).filter(
    c =>
      c.elegivel_antes !== c.elegivel_depois ||
      c.rmi_antes !== c.rmi_depois ||
      c.previsao_antes !== c.previsao_depois
  );

const cenarioBorda = cenario =>
  cenario.mantida
    ? 'border-n-teal-9 bg-n-teal-3'
    : 'border-n-ruby-9 bg-n-ruby-3';
const cenarioTexto = cenario =>
  cenario.mantida ? 'text-n-teal-11' : 'text-n-ruby-11';
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-elegibilidade">
    <button
      type="button"
      data-testid="eleg-analisar"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="!der || ocupado"
      @click="analisar"
    >
      {{
        isLoading
          ? $t('RAMON.SIMULADOR.SIMULANDO')
          : $t('RAMON.SIMULADOR.ELEG_ANALISAR')
      }}
    </button>

    <div v-if="hasError" data-testid="eleg-error">
      <p class="text-sm text-n-ruby-11">{{ errorMessage }}</p>
      <button
        type="button"
        data-testid="eleg-retry"
        class="mt-1 text-xs text-n-iris-11 hover:underline"
        @click="retry"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <template v-if="resultado">
      <div
        v-if="resultado.qualidade?.cenarios"
        class="flex flex-col gap-2"
        data-testid="eleg-cenarios"
      >
        <div
          v-if="resultado.qualidade.cenarios.unico"
          class="flex flex-col gap-1 p-2 rounded-lg border"
          :class="cenarioBorda(resultado.qualidade.cenarios.unico)"
          data-testid="eleg-cenario-unico"
        >
          <p
            class="text-sm font-medium"
            :class="cenarioTexto(resultado.qualidade.cenarios.unico)"
          >
            {{
              resultado.qualidade.cenarios.unico.mantida
                ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
            }}
            <template v-if="resultado.qualidade.cenarios.unico.ate">
              — {{ dataBr(resultado.qualidade.cenarios.unico.ate) }}
            </template>
          </p>
          <p class="text-xs text-n-slate-10">
            {{ resultado.qualidade.cenarios.unico.fundamento }}
          </p>
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div
            v-if="resultado.qualidade.cenarios.sem_desemprego"
            class="flex flex-col gap-1 p-2 rounded-lg border"
            :class="cenarioBorda(resultado.qualidade.cenarios.sem_desemprego)"
            data-testid="eleg-cenario-sem-desemprego"
          >
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.ELEG_SEM_DESEMPREGO') }}
            </span>
            <p
              class="text-sm font-medium"
              :class="cenarioTexto(resultado.qualidade.cenarios.sem_desemprego)"
            >
              {{
                resultado.qualidade.cenarios.sem_desemprego.mantida
                  ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                  : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
              }}
              <template v-if="resultado.qualidade.cenarios.sem_desemprego.ate">
                —
                {{ dataBr(resultado.qualidade.cenarios.sem_desemprego.ate) }}
              </template>
            </p>
            <p class="text-xs text-n-slate-10">
              {{ resultado.qualidade.cenarios.sem_desemprego.fundamento }}
            </p>
          </div>
          <div
            v-if="resultado.qualidade.cenarios.com_desemprego"
            class="flex flex-col gap-1 p-2 rounded-lg border"
            :class="cenarioBorda(resultado.qualidade.cenarios.com_desemprego)"
            data-testid="eleg-cenario-com-desemprego"
          >
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.ELEG_COM_DESEMPREGO') }}
            </span>
            <p
              class="text-sm font-medium"
              :class="cenarioTexto(resultado.qualidade.cenarios.com_desemprego)"
            >
              {{
                resultado.qualidade.cenarios.com_desemprego.mantida
                  ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                  : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
              }}
              <template v-if="resultado.qualidade.cenarios.com_desemprego.ate">
                —
                {{ dataBr(resultado.qualidade.cenarios.com_desemprego.ate) }}
              </template>
            </p>
            <p class="text-xs text-n-slate-10">
              {{ resultado.qualidade.cenarios.com_desemprego.fundamento }}
            </p>
          </div>
        </div>
      </div>

      <div
        v-if="
          resultado.decisoes_pendentes && resultado.decisoes_pendentes.length
        "
        class="flex flex-col gap-2"
        data-testid="eleg-pendencias"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{ $t('RAMON.SIMULADOR.ELEG_PENDENCIAS') }}
        </span>
        <div
          v-for="(pend, i) in resultado.decisoes_pendentes"
          :key="i"
          class="flex flex-col gap-1 p-2 rounded-lg bg-n-amber-3 border border-n-amber-6"
          :data-testid="`eleg-pendencia-${i}`"
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
              data-testid="eleg-pendencia-sim"
              class="px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="ocupado"
              @click="responder(pend.tipo, true)"
            >
              {{ $t('RAMON.SIMULADOR.ELEG_SIM') }}
            </button>
            <button
              type="button"
              data-testid="eleg-pendencia-nao"
              class="px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="ocupado"
              @click="responder(pend.tipo, false)"
            >
              {{ $t('RAMON.SIMULADOR.ELEG_NAO') }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-if="resultado.carencia"
        class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1 border border-n-weak"
        data-testid="eleg-carencia"
      >
        <p class="text-sm text-n-slate-12">
          <span class="text-n-slate-10"
            >{{ $t('RAMON.SIMULADOR.ELEG_CARENCIA') }}:</span
          >
          {{ resultado.carencia.total }}
        </p>
        <p
          v-if="resultado.carencia.art_27a?.aplicavel"
          class="text-xs text-n-amber-11"
          data-testid="eleg-art27a"
        >
          {{
            $t('RAMON.SIMULADOR.ELEG_ART27A', {
              exigencia: resultado.carencia.art_27a.exigencia_incapacidade,
              status: simNao(resultado.carencia.art_27a.cumprida),
            })
          }}
        </p>
      </div>

      <div
        v-if="resultado.lacunas && resultado.lacunas.length"
        class="flex flex-col gap-2"
        data-testid="eleg-lacunas"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{ $t('RAMON.SIMULADOR.ELEG_LACUNAS') }}
        </span>
        <div class="overflow-x-auto">
          <table class="w-full text-xs">
            <tbody>
              <tr
                v-for="(lac, i) in resultado.lacunas"
                :key="i"
                :data-testid="`eleg-lacuna-${i}`"
              >
                <td class="p-1 whitespace-nowrap">
                  {{ dataBr(lac.inicio) }} – {{ dataBr(lac.fim) }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{ $t('RAMON.SIMULADOR.ELEG_MESES', { n: lac.meses }) }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{
                    `${$t('RAMON.SIMULADOR.ELEG_GRACA_COBRIU')}: ${simNao(
                      lac.graca_cobriu
                    )}`
                  }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{
                    $t('RAMON.SIMULADOR.ELEG_GANHO_FMT', {
                      tempo: lac.ganho_tempo_meses,
                      carencia: lac.ganho_carencia,
                    })
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <button
          type="button"
          data-testid="eleg-simular"
          class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-teal-9 text-white hover:bg-n-teal-10 disabled:opacity-40 disabled:cursor-not-allowed"
          :disabled="ocupado"
          @click="simular"
        >
          {{
            simulando
              ? $t('RAMON.SIMULADOR.SIMULANDO')
              : $t('RAMON.SIMULADOR.ELEG_SIMULAR')
          }}
        </button>
      </div>

      <div
        v-if="resultado.simulacao && resultado.simulacao.length"
        class="flex flex-col gap-2"
        data-testid="eleg-simulacao"
      >
        <div
          v-for="(sim, i) in resultado.simulacao"
          :key="i"
          class="flex flex-col gap-1 p-2 rounded-lg border border-n-weak"
          :data-testid="`eleg-simulacao-cenario-${i}`"
        >
          <span class="text-xs font-medium text-n-slate-12">{{
            sim.cenario
          }}</span>
          <div
            v-for="cartao in cartoesAlterados(sim)"
            :key="cartao.id"
            class="flex flex-col gap-0.5 text-xs text-n-slate-11"
            :data-testid="`eleg-simulacao-cartao-${cartao.id}`"
          >
            <span class="font-medium text-n-slate-12">{{ cartao.id }}</span>
            <span
              >{{ $t('RAMON.SIMULADOR.ELEG_ANTES') }}:
              {{ simNao(cartao.elegivel_antes) }} ·
              {{ money(cartao.rmi_antes) }} ·
              {{ dataBr(cartao.previsao_antes) }}</span
            >
            <span
              >{{ $t('RAMON.SIMULADOR.ELEG_DEPOIS') }}:
              {{ simNao(cartao.elegivel_depois) }} ·
              {{ money(cartao.rmi_depois) }} ·
              {{ dataBr(cartao.previsao_depois) }}</span
            >
          </div>
          <p v-if="sim.aviso" class="text-xs text-n-amber-11 font-medium">
            {{ sim.aviso }}
          </p>
        </div>
      </div>

      <ul
        v-if="resultado.avisos && resultado.avisos.length"
        class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        data-testid="eleg-avisos"
      >
        <li v-for="(aviso, i) in resultado.avisos" :key="i">{{ aviso }}</li>
      </ul>
    </template>
  </div>
</template>
