<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useChegadasStore } from 'dashboard/stores/chegadas';
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
  horaDe,
  diaMes,
  desde,
} from './hoje';

// Tela Hoje da advogada: conversas atribuídas a ela + semana no ADVBOX + quem
// chegou na recepção pra ela (store de chegadas, ao vivo pelo ActionCable).
defineProps({ dados: { type: Object, required: true } });

const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const chegadas = useChegadasStore();
const meuId = useMapGetter('getCurrentUserID');

const conversa = id =>
  accountScopedRoute('inbox_conversation', { conversation_id: id });
const tempo = iso => {
  const d = desde(iso);
  return t(`RAMON.HOJE.${d.key}`, { count: d.count });
};
const tomEspera = iso => {
  const { minutos } = desde(iso);
  if (minutos < 30) return 'act';
  return minutos >= 1440 ? 'warn' : 'neutro';
};

const minhasChegadas = computed(() =>
  chegadas.itens.filter(c => c.destinatario?.id === meuId.value)
);
</script>

<template>
  <div :class="GRADE">
    <div class="min-w-0">
      <HojeBloco
        :titulo="t('RAMON.HOJE.ATRIBUIDAS')"
        :total="dados.atribuidas.length"
        :vazio="t('RAMON.HOJE.ATRIBUIDAS_VAZIO')"
      >
        <div v-for="c in dados.atribuidas" :key="c.conversa_id" :class="LINHA">
          <span :class="COL_SELO">
            <Selo :tom="tomEspera(c.esperando_desde)">
              {{
                tomEspera(c.esperando_desde) === 'act'
                  ? t('RAMON.HOJE.NOVA')
                  : tempo(c.esperando_desde)
              }}
            </Selo>
          </span>
          <div :class="QUEM">
            <b v-if="c.nome" :class="NOME">{{ c.nome }}</b>
            <b v-else :class="NOME" class="font-mono">{{ c.telefone }}</b>
            <span v-if="c.ultima_mensagem" :class="DETALHE">
              {{ `“${c.ultima_mensagem}”` }}
            </span>
          </div>
          <router-link :to="conversa(c.conversa_id)" :class="BTN_CHEIO">
            {{ t('RAMON.HOJE.RESPONDER') }}
          </router-link>
        </div>
      </HojeBloco>

      <HojeBloco
        :titulo="t('RAMON.HOJE.SEMANA')"
        :total="dados.advbox_fora ? null : dados.semana.length"
        :vazio="t('RAMON.HOJE.SEMANA_VAZIO')"
      >
        <p
          v-if="dados.advbox_fora"
          data-testid="advbox-fora"
          class="py-4 text-[13px] text-n-amber-11"
        >
          {{ t('RAMON.HOJE.ADVBOX_FORA') }}
        </p>
        <template v-else>
          <div
            v-for="(s, i) in dados.semana"
            :key="`${s.data}-${s.hora}-${i}`"
            :class="LINHA"
          >
            <span :class="HORA">{{ diaMes(s.data) }}</span>
            <span :class="HORA">{{ s.hora || '—' }}</span>
            <div :class="QUEM">
              <b :class="NOME">{{ s.tarefa }}</b>
              <span :class="DETALHE">
                {{ s.cliente }}
                <span v-if="s.processo" class="font-mono">
                  {{ `${s.cliente ? ' · ' : ''}${s.processo}` }}
                </span>
                {{ s.notas ? ` · ${s.notas}` : '' }}
              </span>
            </div>
            <Selo v-if="s.destaque" tom="act">
              {{ t(`RAMON.HOJE.DESTAQUE.${s.destaque}`) }}
            </Selo>
          </div>
        </template>
      </HojeBloco>
    </div>

    <aside>
      <div :class="CAIXA">
        <h3 :class="CAIXA_TITULO">{{ t('RAMON.HOJE.CHEGOU_RECEPCAO') }}</h3>
        <p v-if="!minhasChegadas.length" class="text-[13px] text-n-slate-9">
          {{ t('RAMON.HOJE.CHEGOU_VAZIO') }}
        </p>
        <div
          v-for="c in minhasChegadas"
          :key="c.id"
          class="flex items-center gap-3.5 py-1"
        >
          <div :class="QUEM">
            <b :class="NOME">{{ c.cliente_nome }}</b>
            <span :class="DETALHE">
              {{
                [
                  c.motivo,
                  t('RAMON.HOJE.CHEGOU', { hora: horaDe(c.created_at) }),
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </div>
          <Selo :tom="c.estado === 'respondido' ? 'ok' : 'warn'">
            {{
              t(
                c.estado === 'respondido'
                  ? 'RAMON.HOJE.RESPONDIDO'
                  : 'RAMON.HOJE.AGUARDANDO'
              )
            }}
          </Selo>
        </div>
      </div>
    </aside>
  </div>
</template>
