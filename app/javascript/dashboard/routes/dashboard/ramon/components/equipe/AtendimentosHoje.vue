<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, CHIP, TITULO, TOM } from '../../helpers/ui';

// Opção A (Eduardo, 20/10): na tela Hoje da recepção, os atendimentos do dia
// no ADVBOX com "Chegou" de 1 clique (avisa direto quem atende) e, em cima,
// "Chegou alguém sem horário" (abre o painel de busca). Quem monta esta
// lista é o CommandCenter, só pra quem é do time recepção.
const { t } = useI18n();
const chegadas = useChegadasStore();

const agenda = ref([]);
const advboxFora = ref(false);
const enviando = ref(null);

// Mesmos rótulos e tons do painel "Avisar chegada".
const estados = computed(() => ({
  aguardando: { rotulo: t('RAMON.CHEGADA.ESTADO_aguardando'), tom: TOM.amber },
  escalado: { rotulo: t('RAMON.CHEGADA.ESTADO_escalado'), tom: TOM.ruby },
  respondido: { rotulo: t('RAMON.CHEGADA.ESTADO_respondido'), tom: TOM.teal },
}));

// ponytail: casa pelo nome (a chegada não guarda o advbox_post_id no evento);
// dois agendados com o mesmo nome no dia dividem o estado.
const chegadaDe = item =>
  [...chegadas.itens].reverse().find(c => c.cliente_nome === item.cliente_nome);

const chegou = async item => {
  // Sem advogado casado no hub: o painel abre com o nome pra escolher quem atende.
  if (!item.destinatario_id) {
    chegadas.pedirPainel(item);
    return;
  }
  enviando.value = item.advbox_post_id;
  try {
    await chegadas.criar({
      cliente_nome: item.cliente_nome,
      advbox_customer_id: item.advbox_customer_id,
      advbox_post_id: item.advbox_post_id,
      // Tarefa ATENDIMENTO do ADVBOX = atendimento marcado → "Reunião", como no painel.
      motivo: t('RAMON.CHEGADA.MOTIVO_REUNIAO'),
      destinatario_id: item.destinatario_id,
    });
  } catch {
    useAlert(t('RAMON.CHEGADA.ERRO_AVISAR'));
  } finally {
    enviando.value = null;
  }
};

onMounted(async () => {
  chegadas.carregar().catch(() => {});
  try {
    const { data } = await ChegadasAPI.agenda();
    agenda.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
});
</script>

<template>
  <section data-testid="atendimentos-hoje" class="flex flex-col gap-2.5">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h2 :class="TITULO">{{ t('RAMON.CHEGADA.ATENDIMENTOS_HOJE') }}</h2>
      <Button
        data-testid="chegou-sem-horario"
        faded
        sm
        icon="i-lucide-plus"
        :label="t('RAMON.CHEGADA.SEM_HORARIO')"
        @click="chegadas.pedirPainel()"
      />
    </div>
    <div :class="CARTAO" class="flex flex-col gap-1">
      <p v-if="advboxFora" class="text-sm text-n-ruby-11">
        {{ t('RAMON.CHEGADA.ADVBOX_FORA') }}
      </p>
      <p v-else-if="!agenda.length" class="text-xs text-n-slate-10">
        {{ t('RAMON.CHEGADA.SEM_ATENDIMENTOS') }}
      </p>
      <div
        v-for="item in agenda"
        :key="item.advbox_post_id"
        data-testid="atendimento"
        class="flex items-center gap-3 rounded-lg px-2 py-2"
      >
        <div class="min-w-0 flex-1">
          <p class="truncate text-[13.5px] font-medium text-n-slate-12">
            {{ item.cliente_nome }}
          </p>
          <p
            v-if="item.responsavel_advbox"
            class="truncate text-[11px] text-n-slate-10"
          >
            {{ item.responsavel_advbox }}
          </p>
        </div>
        <span
          v-if="chegadaDe(item)"
          data-testid="atendimento-estado"
          :class="[CHIP, estados[chegadaDe(item).estado].tom]"
        >
          {{ estados[chegadaDe(item).estado].rotulo }}
        </span>
        <Button
          v-else
          data-testid="atendimento-chegou"
          sm
          :label="t('RAMON.CHEGADA.CHEGOU_BOTAO')"
          :is-loading="enviando === item.advbox_post_id"
          @click="chegou(item)"
        />
      </div>
    </div>
  </section>
</template>
