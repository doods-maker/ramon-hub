<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  FILETE,
  TITULO,
  TOM,
} from '../../helpers/ui';

const props = defineProps({
  lead: { type: Object, required: true },
  der: { type: String, default: '' },
  seguradoNome: { type: String, default: '' },
  // Parâmetros do cálculo reaberto do histórico (só desta aba): repreenche e
  // recalcula sem gravar outra linha no histórico.
  inicial: { type: Object, default: null },
});
defineOptions({ name: 'LeadElegibilidade' });

const { t } = useI18n();

const isLoading = ref(false);
const simulando = ref(false);
const ocupado = computed(() => isLoading.value || simulando.value);
const hasError = ref(false);
const errorMessage = ref('');
const resultado = ref(null);
const decisoes = ref({
  desemprego: props.inicial?.decisoes?.desemprego ?? null,
  facultativo: props.inicial?.decisoes?.facultativo ?? null,
});
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
      segurado_nome: props.seguradoNome || undefined,
      ...extra,
    });
    resultado.value = data;
  } catch (error) {
    hasError.value = true;
    errorMessage.value =
      error?.response?.data?.error || t('RAMON.SIMULADOR.ELEG_ERRO');
  }
};

const analisar = async (extra = {}) => {
  ultimaAcao.value = 'analisar';
  isLoading.value = true;
  await chamar(extra);
  isLoading.value = false;
};

const responder = (tipo, valor) => {
  decisoes.value[tipo] = valor;
  analisar();
};

const simular = async (extra = {}) => {
  ultimaAcao.value = 'simular';
  simulando.value = true;
  await chamar({ simular_lacunas: true, ...extra });
  simulando.value = false;
};

const retry = () => (ultimaAcao.value === 'simular' ? simular() : analisar());

if (props.inicial && props.der) {
  const semHistorico = { sem_historico: true };
  if (props.inicial.simular_lacunas) simular(semHistorico);
  else analisar(semHistorico);
}

// só as linhas que mudaram (elegibilidade, RMI ou previsão) — o resto some
// pra não afogar o advogado em cartões que a lacuna não afetou.
const cartoesAlterados = sim =>
  (sim.cartoes || []).filter(
    c =>
      c.elegivel_antes !== c.elegivel_depois ||
      c.rmi_antes !== c.rmi_depois ||
      c.previsao_antes !== c.previsao_depois
  );

// filete do cenário: verde = qualidade mantida, vermelho = perdida
const cenarioBorda = cenario => (cenario.mantida ? FILETE.teal : FILETE.ruby);
const cenarioTexto = cenario =>
  cenario.mantida ? 'text-n-teal-11' : 'text-n-ruby-11';
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="lead-elegibilidade">
    <Button
      data-testid="eleg-analisar"
      :disabled="!der || ocupado"
      sm
      class="self-start"
      :label="
        isLoading
          ? $t('RAMON.SIMULADOR.SIMULANDO')
          : $t('RAMON.SIMULADOR.ELEG_ANALISAR')
      "
      @click="analisar()"
    />

    <div v-if="hasError" data-testid="eleg-error">
      <p class="mb-0" :class="[AVISO, TOM.ruby]">{{ errorMessage }}</p>
      <Button
        data-testid="eleg-retry"
        link
        xs
        class="mt-1"
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="retry"
      />
    </div>

    <template v-if="resultado">
      <div
        v-if="resultado.qualidade?.cenarios"
        class="flex flex-col gap-2"
        data-testid="eleg-cenarios"
      >
        <div
          v-if="resultado.qualidade.cenarios.unico"
          class="flex flex-col gap-1"
          :class="[
            CARTAO_STATUS,
            cenarioBorda(resultado.qualidade.cenarios.unico),
          ]"
          data-testid="eleg-cenario-unico"
        >
          <p
            class="mb-0 text-sm font-medium"
            :class="cenarioTexto(resultado.qualidade.cenarios.unico)"
          >
            {{
              resultado.qualidade.cenarios.unico.mantida
                ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
            }}
            <template v-if="resultado.qualidade.cenarios.unico.ate">
              —
              <span class="font-mono">{{
                dataBr(resultado.qualidade.cenarios.unico.ate)
              }}</span>
            </template>
          </p>
          <p class="mb-0 text-xs text-n-slate-10">
            {{ resultado.qualidade.cenarios.unico.fundamento }}
          </p>
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div
            v-if="resultado.qualidade.cenarios.sem_desemprego"
            class="flex flex-col gap-1"
            :class="[
              CARTAO_STATUS,
              cenarioBorda(resultado.qualidade.cenarios.sem_desemprego),
            ]"
            data-testid="eleg-cenario-sem-desemprego"
          >
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.ELEG_SEM_DESEMPREGO') }}
            </span>
            <p
              class="mb-0 text-sm font-medium"
              :class="cenarioTexto(resultado.qualidade.cenarios.sem_desemprego)"
            >
              {{
                resultado.qualidade.cenarios.sem_desemprego.mantida
                  ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                  : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
              }}
              <template v-if="resultado.qualidade.cenarios.sem_desemprego.ate">
                —
                <span class="font-mono">{{
                  dataBr(resultado.qualidade.cenarios.sem_desemprego.ate)
                }}</span>
              </template>
            </p>
            <p class="mb-0 text-xs text-n-slate-10">
              {{ resultado.qualidade.cenarios.sem_desemprego.fundamento }}
            </p>
          </div>
          <div
            v-if="resultado.qualidade.cenarios.com_desemprego"
            class="flex flex-col gap-1"
            :class="[
              CARTAO_STATUS,
              cenarioBorda(resultado.qualidade.cenarios.com_desemprego),
            ]"
            data-testid="eleg-cenario-com-desemprego"
          >
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.SIMULADOR.ELEG_COM_DESEMPREGO') }}
            </span>
            <p
              class="mb-0 text-sm font-medium"
              :class="cenarioTexto(resultado.qualidade.cenarios.com_desemprego)"
            >
              {{
                resultado.qualidade.cenarios.com_desemprego.mantida
                  ? $t('RAMON.SIMULADOR.ELEG_MANTIDA')
                  : $t('RAMON.SIMULADOR.ELEG_PERDIDA')
              }}
              <template v-if="resultado.qualidade.cenarios.com_desemprego.ate">
                —
                <span class="font-mono">{{
                  dataBr(resultado.qualidade.cenarios.com_desemprego.ate)
                }}</span>
              </template>
            </p>
            <p class="mb-0 text-xs text-n-slate-10">
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
        <span :class="TITULO">
          {{ $t('RAMON.SIMULADOR.ELEG_PENDENCIAS') }}
        </span>
        <div
          v-for="(pend, i) in resultado.decisoes_pendentes"
          :key="i"
          class="flex flex-col gap-1"
          :class="[CARTAO_STATUS, FILETE.amber]"
          :data-testid="`eleg-pendencia-${i}`"
        >
          <p class="mb-0 text-xs text-n-amber-11 font-medium">
            {{ pend.pergunta }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ $t('RAMON.SIMULADOR.ELEG_SIM') }}:
            {{ pend.efeito_por_resposta?.sim }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ $t('RAMON.SIMULADOR.ELEG_NAO') }}:
            {{ pend.efeito_por_resposta?.nao }}
          </p>
          <div class="flex gap-2">
            <Button
              data-testid="eleg-pendencia-sim"
              :disabled="ocupado"
              sm
              faded
              slate
              :label="$t('RAMON.SIMULADOR.ELEG_SIM')"
              @click="responder(pend.tipo, true)"
            />
            <Button
              data-testid="eleg-pendencia-nao"
              :disabled="ocupado"
              sm
              faded
              slate
              :label="$t('RAMON.SIMULADOR.ELEG_NAO')"
              @click="responder(pend.tipo, false)"
            />
          </div>
        </div>
      </div>

      <div
        v-if="resultado.carencia"
        class="flex flex-col gap-1"
        :class="CARTAO"
        data-testid="eleg-carencia"
      >
        <p
          class="mb-0 flex flex-wrap items-baseline gap-x-1 text-sm text-n-slate-12"
        >
          <span class="text-n-slate-10"
            >{{ $t('RAMON.SIMULADOR.ELEG_CARENCIA') }}:</span
          >
          <span class="font-mono">{{ resultado.carencia.total }}</span>
        </p>
        <p
          v-if="resultado.carencia.art_27a?.aplicavel"
          class="mb-0 text-xs text-n-amber-11"
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
        <span :class="TITULO">
          {{ $t('RAMON.SIMULADOR.ELEG_LACUNAS') }}
        </span>
        <div class="overflow-x-auto">
          <table class="w-full text-xs text-n-slate-11">
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="(lac, i) in resultado.lacunas"
                :key="i"
                :data-testid="`eleg-lacuna-${i}`"
              >
                <td class="p-1 font-mono whitespace-nowrap">
                  {{ dataBr(lac.inicio) }} – {{ dataBr(lac.fim) }}
                </td>
                <td class="p-1 font-mono text-end whitespace-nowrap">
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
        <Button
          data-testid="eleg-simular"
          :disabled="ocupado"
          sm
          class="self-start"
          :label="
            simulando
              ? $t('RAMON.SIMULADOR.SIMULANDO')
              : $t('RAMON.SIMULADOR.ELEG_SIMULAR')
          "
          @click="simular()"
        />
      </div>

      <div
        v-if="resultado.simulacao && resultado.simulacao.length"
        class="flex flex-col gap-2"
        data-testid="eleg-simulacao"
      >
        <div
          v-for="(sim, i) in resultado.simulacao"
          :key="i"
          class="flex flex-col gap-1"
          :class="CARTAO"
          :data-testid="`eleg-simulacao-cenario-${i}`"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
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
              <span class="font-mono">{{ money(cartao.rmi_antes) }}</span> ·
              <span class="font-mono">{{
                dataBr(cartao.previsao_antes)
              }}</span></span
            >
            <span
              >{{ $t('RAMON.SIMULADOR.ELEG_DEPOIS') }}:
              {{ simNao(cartao.elegivel_depois) }} ·
              <span class="font-mono">{{ money(cartao.rmi_depois) }}</span> ·
              <span class="font-mono">{{
                dataBr(cartao.previsao_depois)
              }}</span></span
            >
          </div>
          <p v-if="sim.aviso" class="mb-0 text-xs text-n-amber-11 font-medium">
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
