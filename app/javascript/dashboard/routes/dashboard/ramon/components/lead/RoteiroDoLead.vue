<script setup>
// Roteiro da IA no painel do lead e no Testar (F2): passo a passo (respondido / pergunta agora / a perguntar /
// não perguntado), resultado das calculadoras e o desfecho com motivo. Com leadId, "Reabrir roteiro".
// Mesma cara da Qualificação viva: à vista só o que falta; respondidos atrás do toggle.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadsAPI from 'dashboard/api/leads';
import ConfirmModal from '../ConfirmModal.vue';
import { mensagemErro } from '../../helpers/erro';
import { AVISO, CARTAO, CHIP, TITULO, TOM } from '../../helpers/ui';

const props = defineProps({
  // painel montado pelo servidor (Ramon::Roteiro::Painel)
  roteiro: { type: Object, required: true },
  // sem leadId (Testar): só mostra, sem reabrir
  leadId: { type: Number, default: null },
  // 'ganho' | 'perdido' | '' — lead fechado não reabre por aqui
  bloqueio: { type: String, default: '' },
});
const emit = defineEmits(['reaberto']);
const { t } = useI18n();

const ICONE = {
  respondido: 'i-lucide-check text-n-teal-11',
  atual: 'i-lucide-arrow-right text-n-blue-11',
  pendente: 'i-lucide-circle-dashed text-n-slate-10',
  fora: 'i-lucide-minus text-n-slate-9',
};
const TOM_DESFECHO = {
  qualificado: TOM.teal,
  desqualificado: TOM.ruby,
  humano: TOM.amber,
};

const passos = computed(() => props.roteiro.passos || []);
const respondidos = computed(
  () => passos.value.filter(p => p.situacao === 'respondido').length
);
// a barra conta o que foi ou ainda vai ser perguntado (pulado pelo "vai para" não entra)
const total = computed(
  () => passos.value.filter(p => p.situacao !== 'fora').length
);
const faltam = computed(() =>
  passos.value.filter(p => ['atual', 'pendente'].includes(p.situacao))
);
const abertos = ref(false);
const visiveis = computed(() => (abertos.value ? passos.value : faltam.value));
const decisivo = computed(
  () => passos.value.find(p => p.chave === props.roteiro.decisivo)?.titulo || ''
);
const resposta = passo => passo.valor ?? passo.saida ?? '';

const confirmando = ref(false);
const reabrindo = ref(false);
const reabrir = async () => {
  confirmando.value = false;
  reabrindo.value = true;
  try {
    const { data } = await LeadsAPI.reabrirRoteiro(props.leadId);
    emit('reaberto', data);
    useAlert(t('RAMON.ROTEIRO_IA.REABERTO'));
  } catch (e) {
    useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));
  } finally {
    reabrindo.value = false;
  }
};
</script>

<template>
  <div :class="CARTAO" data-testid="panel-card-roteiro">
    <div class="flex items-center gap-2">
      <p :class="TITULO">{{ $t('RAMON.ROTEIRO_IA.TITULO') }}</p>
      <div class="flex-1 h-1 overflow-hidden rounded-full bg-n-alpha-2">
        <div
          class="h-full bg-n-teal-9"
          :style="{ width: `${total ? (respondidos / total) * 100 : 0}%` }"
        />
      </div>
      <span
        class="font-mono text-xs font-semibold text-n-slate-12"
        data-testid="roteiro-contagem"
      >
        {{ $t('RAMON.ROTEIRO_IA.CONTAGEM', { ok: respondidos, total }) }}
      </span>
    </div>

    <div v-if="roteiro.desfecho" class="mt-2 flex flex-col gap-1">
      <p
        data-testid="roteiro-desfecho"
        class="m-0"
        :class="[AVISO, TOM_DESFECHO[roteiro.desfecho]]"
      >
        <span class="font-semibold">
          {{
            $t(`RAMON.ROTEIRO_IA.DESFECHO.${roteiro.desfecho.toUpperCase()}`)
          }}
        </span>
        <template v-if="roteiro.motivo"> — {{ roteiro.motivo }}</template>
      </p>
      <p
        v-if="roteiro.aguarda_equipe && leadId"
        class="m-0 text-xs text-n-slate-11"
      >
        {{ $t('RAMON.ROTEIRO_IA.AGUARDA_EQUIPE') }}
      </p>
      <template v-if="leadId">
        <p
          v-if="bloqueio"
          data-testid="roteiro-bloqueio"
          class="m-0 text-xs text-n-slate-10"
        >
          {{ $t(`RAMON.ROTEIRO_IA.REABRIR_${bloqueio.toUpperCase()}`) }}
        </p>
        <Button
          v-else
          data-testid="roteiro-reabrir"
          link
          xs
          slate
          icon="i-lucide-rotate-ccw"
          class="self-start"
          :label="$t('RAMON.ROTEIRO_IA.REABRIR')"
          :disabled="reabrindo"
          @click="confirmando = true"
        />
      </template>
    </div>
    <p
      v-else-if="roteiro.so_comuns && !faltam.length"
      class="m-0 mt-2 text-xs text-n-slate-11"
    >
      {{ $t('RAMON.ROTEIRO_IA.COMUNS_CONCLUIDOS') }}
    </p>

    <div class="mt-1 flex flex-col">
      <div
        v-for="passo in visiveis"
        :key="passo.chave"
        data-testid="roteiro-passo"
        class="flex items-center gap-2 py-1 text-[12.5px]"
      >
        <span
          class="size-3.5 shrink-0"
          :class="ICONE[passo.situacao]"
          :title="
            $t(`RAMON.ROTEIRO_IA.SITUACAO.${passo.situacao.toUpperCase()}`)
          "
        />
        <span
          class="min-w-0 truncate"
          :class="
            passo.situacao === 'atual'
              ? 'font-medium text-n-slate-12'
              : 'text-n-slate-11'
          "
        >
          {{ passo.titulo }}
        </span>
        <span
          v-if="resposta(passo)"
          class="ml-auto max-w-[45%] shrink-0 truncate font-mono text-xs text-n-slate-12"
          :title="resposta(passo)"
        >
          {{ resposta(passo) }}
        </span>
        <span
          v-if="passo.calc"
          data-testid="roteiro-calc"
          class="shrink-0"
          :class="[CHIP, TOM.iris]"
          :title="passo.calc.detalhe"
        >
          {{ passo.calc.resultado }}
        </span>
      </div>
      <Button
        v-if="respondidos"
        data-testid="roteiro-respondidos"
        link
        slate
        xs
        trailing-icon
        class="self-start mt-1"
        :icon="abertos ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        :label="$t('RAMON.ROTEIRO_IA.RESPONDIDOS', { count: respondidos })"
        @click="abertos = !abertos"
      />
    </div>
    <ConfirmModal
      v-if="confirmando"
      :title="$t('RAMON.ROTEIRO_IA.REABRIR_CONFIRMA')"
      :message="$t('RAMON.ROTEIRO_IA.REABRIR_AJUDA', { passo: decisivo })"
      :confirm-label="$t('RAMON.ROTEIRO_IA.REABRIR')"
      confirm-color="blue"
      @confirm="reabrir"
      @cancel="confirmando = false"
    />
  </div>
</template>
