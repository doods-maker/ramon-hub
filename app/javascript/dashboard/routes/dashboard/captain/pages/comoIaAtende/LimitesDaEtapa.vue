<script setup>
// "Limites em {etapa}": a Permissão de cada ação da Etapa (clique alterna) e os Gatilhos de equipe.
// Emite o valor novo; quem grava no cfg é a página.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  TOM_DO_ESTADO,
  alternarGatilho,
  baseDe,
  efetivo,
  permissaoEfetiva,
  proximaPermissao,
} from 'dashboard/routes/dashboard/ramon/helpers/perfilIa';

const props = defineProps({
  etapa: { type: Object, required: true },
  cfg: { type: Object, required: true },
  // corpo do GET (prontos, etapas, acoes, gatilhos)
  dados: { type: Object, required: true },
  travado: { type: Boolean, default: false },
});
const emit = defineEmits(['permissao', 'gatilhos']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const K = 'RAMON.COMO_IA.LIMITES';

const ICONE = {
  fora_do_horario: 'i-lucide-moon',
  pedir_documentos: 'i-lucide-file-text',
  desqualificar: 'i-lucide-user-x',
  mover_etapa: 'i-lucide-arrow-right-left',
  marcar_reuniao: 'i-lucide-calendar-check',
  citar_honorario: 'i-lucide-banknote',
  logistica: 'i-lucide-calendar-clock',
  contrato_zapsign: 'i-lucide-file-signature',
};
// Linhas só de leitura (spec): a confirmação da reunião é do fluxo Reuniões; desconto é sempre nunca.
const REUNIAO = 'fase-reuniao-agendada';
const NEGOCIACAO = 'fase-negociacao';
const LEGENDA = [
  ['sozinha', 'bg-n-teal-9'],
  ['rascunho', 'bg-n-amber-9'],
  ['nunca', 'bg-n-ruby-9'],
  ['ajustado', 'bg-n-blue-9'],
];
const LINHA =
  'flex min-h-[52px] flex-wrap items-center gap-3 border-b border-n-weak px-1 py-2.5';

const pronto = computed(() => props.dados.prontos[baseDe(props.cfg)]);
const atual = computed(() =>
  efetivo(props.cfg, props.dados.prontos, props.dados.etapas)
);
const linhas = computed(() =>
  props.dados.acoes
    .filter(acao => acao.etapas.includes(props.etapa.chave))
    .map(acao => ({
      ...acao,
      ...permissaoEfetiva(
        acao.chave,
        props.etapa.chave,
        props.cfg,
        props.dados.prontos,
        props.dados.etapas
      ),
      ajustada:
        atual.value.permissoes[acao.chave] !==
        pronto.value.permissoes[acao.chave],
    }))
);
const ligados = computed(() => atual.value.gatilhos[props.etapa.chave]);
const gatilhosAjustados = computed(
  () =>
    ligados.value.length !== pronto.value.gatilhos.length ||
    ligados.value.some(g => !pronto.value.gatilhos.includes(g))
);

const estado = valor => t(`RAMON.COMO_IA.ESTADO.${valor}`);
const trocar = linha =>
  emit(
    'permissao',
    linha.chave,
    proximaPermissao(atual.value.permissoes[linha.chave], linha.sem_nunca)
  );
const alternar = gatilho =>
  emit(
    'gatilhos',
    props.etapa.chave,
    alternarGatilho(ligados.value, gatilho.chave, props.dados.gatilhos)
  );
</script>

<template>
  <div>
    <div class="mb-2.5 flex flex-wrap items-baseline gap-2.5">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`, { etapa: etapa.nome }) }}
      </h3>
      <span class="text-[12.5px] text-n-slate-10">{{ t(`${K}.DICA`) }}</span>
    </div>
    <ul class="reset-base list-none border-t border-n-weak">
      <li
        v-for="linha in linhas"
        :key="linha.chave"
        :data-testid="`limite-${linha.chave}`"
        :class="LINHA"
      >
        <span
          :class="ICONE[linha.chave]"
          class="size-4 shrink-0 text-n-slate-10"
          aria-hidden="true"
        />
        <span
          class="flex min-w-0 flex-1 items-center gap-2 text-[13.5px] text-n-slate-12"
        >
          <span
            v-if="linha.ajustada"
            data-testid="ajustada"
            class="size-1.5 shrink-0 rounded-full bg-n-blue-9"
            :title="t(`${K}.AJUSTADO`)"
          />
          {{ t(`RAMON.COMO_IA.ACOES.${linha.chave}`) }}
        </span>
        <span
          v-if="linha.limitadoPeloMarcador"
          class="text-[11.5px] text-n-slate-10"
        >
          {{ t(`${K}.LIMITADO`, { valor: estado(linha.propria) }) }}
        </span>
        <button
          type="button"
          data-testid="permissao"
          :disabled="travado"
          :aria-label="
            t(`${K}.TROCAR`, {
              acao: t(`RAMON.COMO_IA.ACOES.${linha.chave}`),
              valor: estado(linha.propria),
            })
          "
          class="min-w-[6.5rem] justify-between !gap-2 !py-1.5 !text-xs disabled:cursor-not-allowed"
          :class="[CHIP, TOM_DO_ESTADO[linha.valor]]"
          @click="trocar(linha)"
        >
          <span class="flex items-center gap-1.5">
            <span class="size-1.5 rounded-full bg-current" />
            {{ estado(linha.valor) }}
          </span>
          <span class="i-lucide-chevrons-up-down size-3 opacity-70" />
        </button>
      </li>
      <li
        v-if="etapa.chave === REUNIAO"
        data-testid="limite-confirmacao"
        :class="LINHA"
      >
        <span
          class="i-lucide-bell size-4 shrink-0 text-n-slate-10"
          aria-hidden="true"
        />
        <span class="min-w-0 flex-1 text-[13.5px] text-n-slate-12">
          {{ t(`${K}.CONFIRMACAO`) }}
        </span>
        <router-link
          :to="accountScopedRoute('captain_automacoes_index')"
          class="text-xs font-medium text-n-blue-11 hover:underline"
        >
          {{ t(`${K}.ABRIR_FLUXOS`) }}
        </router-link>
      </li>
      <li
        v-if="etapa.chave === NEGOCIACAO"
        data-testid="limite-desconto"
        :class="LINHA"
      >
        <span
          class="i-lucide-percent size-4 shrink-0 text-n-slate-10"
          aria-hidden="true"
        />
        <span class="min-w-0 flex-1 text-[13.5px] text-n-slate-12">
          {{ t(`${K}.DESCONTO`) }}
        </span>
        <span class="!py-1.5 !text-xs" :class="[CHIP, TOM.ruby]">
          <span class="i-lucide-lock size-3" aria-hidden="true" />
          {{ t(`${K}.REGRA`) }}
        </span>
      </li>
      <li data-testid="limite-gatilhos" :class="LINHA">
        <span
          class="i-lucide-hand size-4 shrink-0 text-n-slate-10"
          aria-hidden="true"
        />
        <span
          class="flex min-w-0 flex-1 items-center gap-2 text-[13.5px] text-n-slate-12"
        >
          <span
            v-if="gatilhosAjustados"
            class="size-1.5 shrink-0 rounded-full bg-n-blue-9"
            :title="t(`${K}.AJUSTADO`)"
          />
          {{ t(`${K}.GATILHOS`) }}
          <span
            class="i-lucide-info size-3.5 text-n-slate-10"
            role="img"
            :title="t(`${K}.GATILHOS_DICA`)"
            :aria-label="t(`${K}.GATILHOS_DICA`)"
          />
        </span>
        <span class="flex flex-wrap justify-end gap-1.5 md:max-w-[62%]">
          <button
            v-for="gatilho in dados.gatilhos"
            :key="gatilho.chave"
            type="button"
            :data-testid="`gatilho-${gatilho.chave}`"
            :disabled="travado || gatilho.pendente"
            :aria-pressed="ligados.includes(gatilho.chave)"
            :title="
              gatilho.pendente ? t(`${K}.PENDENTE`) : t(`${K}.GATILHOS_DICA`)
            "
            class="inline-flex items-center gap-1 rounded-full border border-solid px-2.5 py-1 text-xs disabled:cursor-not-allowed"
            :class="[
              ligados.includes(gatilho.chave)
                ? `border-transparent font-medium ${TOM.ruby}`
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-8',
              gatilho.pendente ? 'opacity-60' : '',
            ]"
            @click="alternar(gatilho)"
          >
            <span
              v-if="ligados.includes(gatilho.chave)"
              class="i-lucide-check size-3"
              aria-hidden="true"
            />
            {{ gatilho.nome }}
            <span v-if="gatilho.pendente" class="text-[10.5px]">
              {{ t(`${K}.PENDENTE_SUFIXO`) }}
            </span>
          </button>
        </span>
      </li>
    </ul>
    <p class="mt-3 flex flex-wrap gap-4 text-xs text-n-slate-10">
      <span
        v-for="[chave, cor] in LEGENDA"
        :key="chave"
        class="inline-flex items-center gap-1.5"
      >
        <span class="size-2 rounded-full" :class="cor" />
        {{ t(`RAMON.COMO_IA.LEGENDA.${chave}`) }}
      </span>
    </p>
  </div>
</template>
