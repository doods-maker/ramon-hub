<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import HojeBloco from './HojeBloco.vue';
import Selo from './Selo.vue';
import {
  GRADE,
  LINHA,
  QUEM,
  NOME,
  DETALHE,
  HORA,
  COL_SELO,
  CAIXA,
  CAIXA_TITULO,
  BTN_CHEIO,
  BTN_TINT,
  horaDe,
  desde,
} from './hoje';

// Tela Hoje da Recepção: caixa do escritório sem responsável + quem vem hoje (ADVBOX).
defineProps({ dados: { type: Object, required: true } });
const emit = defineEmits(['recarregar']);

const { t } = useI18n();
const store = useStore();
const { accountScopedRoute } = useAccount();

const ADVBOX_URL = 'https://app.advbox.com.br';
const SITUACAO = {
  atendido: { tom: 'ok', chave: 'ATENDIDO' },
  aguardando: { tom: 'warn', chave: 'AGUARDANDO' },
  nao_chegou: { tom: 'neutro', chave: 'NAO_CHEGOU' },
};

const conversa = id =>
  accountScopedRoute('inbox_conversation', { conversation_id: id });
const espera = c => desde(c.esperando_desde);
const detalhe = c =>
  [
    t(c.cliente ? 'RAMON.HOJE.CLIENTE' : 'RAMON.HOJE.NUMERO_NOVO'),
    c.ultima_mensagem && `“${c.ultima_mensagem}”`,
  ]
    .filter(Boolean)
    .join(' · ');
const comQuem = a =>
  [
    a.responsavel_advbox && t('RAMON.HOJE.COM', { nome: a.responsavel_advbox }),
    a.chegou_em && t('RAMON.HOJE.CHEGOU', { hora: horaDe(a.chegou_em) }),
  ]
    .filter(Boolean)
    .join(' · ');

// Número novo → comercial (vira lead como indicação, sai da fila do escritório).
const encaminhando = ref(null);
const encaminhar = async c => {
  encaminhando.value = c.conversa_id;
  try {
    await store.dispatch('leads/encaminharComercial', {
      conversationId: c.conversa_id,
    });
    emit('recarregar');
  } catch {
    useAlert(t('RAMON.HOJE.ENCAMINHAR_ERRO'));
  } finally {
    encaminhando.value = null;
  }
};
</script>

<template>
  <div :class="GRADE">
    <div class="min-w-0">
      <HojeBloco
        :titulo="t('RAMON.HOJE.SEM_RESPONSAVEL')"
        :total="dados.sem_responsavel.length"
        :dica="t('RAMON.HOJE.SEM_RESPONSAVEL_DICA')"
        :vazio="t('RAMON.HOJE.SEM_RESPONSAVEL_VAZIO')"
      >
        <div
          v-for="c in dados.sem_responsavel"
          :key="c.conversa_id"
          :class="LINHA"
        >
          <span :class="COL_SELO">
            <Selo :tom="espera(c).minutos >= 10 ? 'warn' : 'neutro'">
              {{ t(`RAMON.HOJE.${espera(c).key}`, { count: espera(c).count }) }}
            </Selo>
          </span>
          <router-link :to="conversa(c.conversa_id)" :class="QUEM">
            <b v-if="c.nome" :class="NOME">{{ c.nome }}</b>
            <b v-else :class="NOME" class="font-mono">{{ c.telefone }}</b>
            <span :class="DETALHE">{{ detalhe(c) }}</span>
          </router-link>
          <router-link
            v-if="c.cliente"
            :to="conversa(c.conversa_id)"
            :class="BTN_CHEIO"
          >
            {{ t('RAMON.HOJE.ATRIBUIR') }}
          </router-link>
          <button
            v-else
            type="button"
            data-testid="encaminhar-comercial"
            :class="BTN_TINT"
            :disabled="encaminhando === c.conversa_id"
            @click="encaminhar(c)"
          >
            {{ t('RAMON.HOJE.ENCAMINHAR') }}
          </button>
        </div>
      </HojeBloco>

      <HojeBloco
        :titulo="t('RAMON.HOJE.ATENDIMENTOS')"
        :total="dados.advbox_fora ? null : dados.atendimentos.length"
        :vazio="t('RAMON.HOJE.ATENDIMENTOS_VAZIO')"
      >
        <template #acao>
          <a
            :href="ADVBOX_URL"
            target="_blank"
            rel="noopener noreferrer"
            class="text-[12.5px] font-medium text-n-blue-11"
          >
            {{ t('RAMON.HOJE.DO_ADVBOX') }}
          </a>
        </template>
        <p
          v-if="dados.advbox_fora"
          data-testid="advbox-fora"
          class="py-4 text-[13px] text-n-amber-11"
        >
          {{ t('RAMON.HOJE.ADVBOX_FORA') }}
        </p>
        <template v-else>
          <div
            v-for="a in dados.atendimentos"
            :key="a.advbox_post_id"
            :class="LINHA"
          >
            <span :class="HORA">{{ a.hora || '—' }}</span>
            <div :class="QUEM">
              <b :class="NOME">{{ a.cliente_nome }}</b>
              <span :class="DETALHE">{{ comQuem(a) }}</span>
            </div>
            <Selo :tom="SITUACAO[a.situacao].tom">
              <span
                v-if="a.situacao === 'atendido'"
                class="i-lucide-check size-3"
              />
              {{ t(`RAMON.HOJE.${SITUACAO[a.situacao].chave}`) }}
            </Selo>
          </div>
        </template>
      </HojeBloco>
    </div>

    <aside>
      <div :class="CAIXA">
        <h3 :class="CAIXA_TITULO">{{ t('RAMON.HOJE.CAIXA') }}</h3>
        <div
          v-for="chave in ['sem_responsavel', 'controladoria', 'com_advogadas']"
          :key="chave"
          class="flex justify-between gap-3 py-1 text-[13px]"
        >
          <span class="text-n-slate-9">
            {{ t(`RAMON.HOJE.CAIXA_${chave.toUpperCase()}`) }}
          </span>
          <b class="font-mono font-medium text-n-slate-12">
            {{ dados.caixa[chave] || 0 }}
          </b>
        </div>
      </div>
    </aside>
  </div>
</template>
