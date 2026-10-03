<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import LeadsAPI from 'dashboard/api/leads';
import HojeBloco from './HojeBloco.vue';
import HojeMetrica from './HojeMetrica.vue';
import Selo from './Selo.vue';
import SeloPrazo from './SeloPrazo.vue';
import {
  GRADE,
  LINHA,
  TARDE,
  QUEM,
  NOME,
  DETALHE,
  HORA,
  COL_SELO,
  CAIXA,
  CAIXA_TITULO,
  BTN_LINHA,
  BTN_CHEIO,
  BTN_TINT,
  horaDe,
  diaCurto,
  desde,
  reais,
} from './hoje';

// Tela Hoje do SDR (e "equipe") e do Closer — o Closer vem com reunioes_hoje.
const props = defineProps({ dados: { type: Object, required: true } });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

// Cor da etapa "Reunião agendada" do funil (pílula do mockup).
const COR_REUNIAO = '#8b5cf6';

const ehCloser = computed(() => Array.isArray(props.dados.reunioes_hoje));
const mes = computed(() => props.dados.mes || {});
const detalhe = partes => partes.filter(Boolean).join(' · ');
const citado = texto => (texto ? `“${texto}”` : null);
const tempo = iso => {
  const d = desde(iso);
  return t(`RAMON.HOJE.${d.key}`, { count: d.count });
};

const conversa = id =>
  accountScopedRoute('inbox_conversation', { conversation_id: id });
const ficha = leadId => accountScopedRoute('ramon_lead_dossie', { leadId });
const conversaOuFicha = item =>
  item.conversa_id ? conversa(item.conversa_id) : ficha(item.lead_id);

const estourou = linha => new Date(linha.prazo_em) < Date.now();
const vencidoHaDias = item => desde(item.vence_em).minutos >= 1440;
const docsProntos = docs => docs.total > 0 && docs.received === docs.total;

// Rascunho de retomada (nada é enviado) e abre a conversa pra revisar.
const preparando = ref(null);
const prepararFollowUp = async item => {
  preparando.value = item.lead_id;
  try {
    await LeadsAPI.followUpDraft(item.lead_id);
    router.push(conversaOuFicha(item));
  } catch {
    useAlert(t('RAMON.HOJE.FOLLOW_UP_ERRO'));
  } finally {
    preparando.value = null;
  }
};
</script>

<template>
  <div :class="GRADE">
    <div v-if="ehCloser" class="min-w-0">
      <HojeBloco
        :titulo="t('RAMON.HOJE.REUNIOES_HOJE')"
        :total="dados.reunioes_hoje.length"
        :vazio="t('RAMON.HOJE.REUNIOES_HOJE_VAZIO')"
      >
        <div
          v-for="(r, i) in dados.reunioes_hoje"
          :key="`${r.lead_id}-${r.quando}`"
          :class="LINHA"
        >
          <span :class="HORA">{{ horaDe(r.quando) }}</span>
          <div :class="QUEM">
            <b :class="NOME">{{ r.nome }}</b>
            <span :class="DETALHE">{{ r.tese }}</span>
          </div>
          <Selo v-if="docsProntos(r.docs)" tom="ok">
            <span class="i-lucide-check size-3" />
            {{ t('RAMON.HOJE.DOSSIE_PRONTO') }}
          </Selo>
          <Selo v-else-if="r.docs.total" tom="warn">
            {{
              t('RAMON.HOJE.FALTAM_DOCS', {
                count: r.docs.total - r.docs.received,
              })
            }}
          </Selo>
          <router-link
            :to="ficha(r.lead_id)"
            :class="i === 0 ? BTN_CHEIO : BTN_LINHA"
          >
            {{ t('RAMON.HOJE.ABRIR_DOSSIE') }}
          </router-link>
        </div>
      </HojeBloco>

      <HojeBloco
        :titulo="t('RAMON.HOJE.ASSINATURA')"
        :total="dados.assinatura.length"
        :vazio="t('RAMON.HOJE.ASSINATURA_VAZIO')"
      >
        <div v-for="a in dados.assinatura" :key="a.lead_id" :class="LINHA">
          <span :class="COL_SELO">
            <Selo
              v-if="a.enviado_em"
              :tom="desde(a.enviado_em).minutos >= 1440 ? 'warn' : 'neutro'"
            >
              {{ tempo(a.enviado_em) }}
            </Selo>
          </span>
          <div :class="QUEM">
            <b :class="NOME">{{ a.nome }}</b>
            <span :class="DETALHE">
              {{ detalhe([a.tese, t('RAMON.HOJE.ENVIADO_ZAPSIGN')]) }}
            </span>
          </div>
          <router-link :to="conversaOuFicha(a)" :class="BTN_TINT">
            {{ t('RAMON.HOJE.LEMBRAR') }}
          </router-link>
        </div>
      </HojeBloco>
    </div>

    <div v-else class="min-w-0">
      <HojeBloco
        :titulo="t('RAMON.HOJE.RESPONDER_AGORA')"
        :total="dados.responder.length"
        :dica="t('RAMON.HOJE.RESPONDER_DICA')"
        :vazio="t('RAMON.HOJE.RESPONDER_VAZIO')"
      >
        <div
          v-for="l in dados.responder"
          :key="l.lead_id"
          :class="[LINHA, estourou(l) ? TARDE : '']"
        >
          <span :class="COL_SELO"><SeloPrazo :prazo-em="l.prazo_em" /></span>
          <div :class="QUEM">
            <b :class="NOME">{{ l.nome }}</b>
            <span :class="DETALHE">
              {{ detalhe([l.tese, l.canal, citado(l.ultima_mensagem)]) }}
            </span>
          </div>
          <router-link :to="conversa(l.conversa_id)" :class="BTN_CHEIO">
            {{ t('RAMON.HOJE.RESPONDER') }}
          </router-link>
        </div>
      </HojeBloco>

      <HojeBloco
        :titulo="t('RAMON.HOJE.FOLLOW_UPS')"
        :total="dados.follow_ups.length"
        :vazio="t('RAMON.HOJE.FOLLOW_UPS_VAZIO')"
      >
        <div
          v-for="f in dados.follow_ups"
          :key="`${f.lead_id}-${f.vence_em}`"
          :class="LINHA"
        >
          <span :class="COL_SELO">
            <Selo v-if="vencidoHaDias(f)" tom="warn">
              {{ tempo(f.vence_em) }}
            </Selo>
            <Selo v-else>{{ t('RAMON.HOJE.HOJE') }}</Selo>
          </span>
          <div :class="QUEM">
            <b :class="NOME">{{ f.nome }}</b>
            <span :class="DETALHE">{{ detalhe([f.tese, f.titulo]) }}</span>
          </div>
          <button
            type="button"
            data-testid="preparar-follow-up"
            :class="BTN_TINT"
            :disabled="preparando === f.lead_id"
            @click="prepararFollowUp(f)"
          >
            <span class="i-lucide-sparkles size-4" />
            {{ t('RAMON.HOJE.PREPARAR_FOLLOW_UP') }}
          </button>
        </div>
      </HojeBloco>

      <HojeBloco
        :titulo="t('RAMON.HOJE.REUNIOES_MARCADAS')"
        :total="dados.reunioes.length"
        :vazio="t('RAMON.HOJE.REUNIOES_MARCADAS_VAZIO')"
      >
        <div
          v-for="r in dados.reunioes"
          :key="`${r.nome}-${r.quando}`"
          :class="LINHA"
        >
          <span :class="HORA">{{ diaCurto(r.quando) }}</span>
          <span :class="HORA">{{ horaDe(r.quando) }}</span>
          <div :class="QUEM">
            <b :class="NOME">{{ r.nome }}</b>
            <span :class="DETALHE">
              {{
                detalhe([
                  r.tese,
                  r.closer
                    ? t('RAMON.HOJE.COM', { nome: r.closer })
                    : t('RAMON.HOJE.COM_O_CLOSER'),
                ])
              }}
            </span>
          </div>
          <span
            class="ramon-stage-pill inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-[9px] py-1 text-[11.5px] font-medium leading-none"
            :style="{ '--stage': COR_REUNIAO }"
          >
            <span class="size-1.5 rounded-full bg-current" />
            {{ t('RAMON.HOJE.REUNIAO_MARCADA') }}
          </span>
        </div>
      </HojeBloco>
    </div>

    <aside>
      <div :class="CAIXA">
        <h3 :class="CAIXA_TITULO">{{ t('RAMON.HOJE.SEU_MES') }}</h3>
        <template v-if="ehCloser">
          <HojeMetrica
            :rotulo="t('RAMON.HOJE.CONTRATOS_FECHADOS')"
            :valor="mes.contagem || 0"
            :meta="mes.meta"
            barra="act"
          />
          <HojeMetrica
            :rotulo="t('RAMON.HOJE.FECHAMENTO')"
            :valor="mes.fechamento == null ? '—' : `${mes.fechamento}%`"
          />
        </template>
        <template v-else>
          <HojeMetrica
            :rotulo="t('RAMON.HOJE.REUNIOES_QUALIFICADAS')"
            :valor="mes.contagem || 0"
            :meta="mes.meta"
            barra="act"
          />
          <HojeMetrica
            :rotulo="t('RAMON.HOJE.CONTRATOS_DOS_LEADS')"
            :valor="mes.contratos || 0"
          />
        </template>
        <HojeMetrica
          :rotulo="t('RAMON.HOJE.VARIAVEL')"
          :valor="reais(mes.total)"
        />
      </div>
      <router-link
        :to="accountScopedRoute('ramon_extrato')"
        :class="BTN_LINHA"
        class="w-full justify-center"
      >
        {{ t('RAMON.HOJE.VER_EXTRATO') }}
      </router-link>
    </aside>
  </div>
</template>
