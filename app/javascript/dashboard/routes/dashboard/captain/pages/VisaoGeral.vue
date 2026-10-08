<script setup>
// Visão geral da Inteligência (I-VG1–3): a entrada da área. Junta o que o hub
// já grava — aprovações, régua da D7, rascunhos, 1ª resposta, transferências,
// ferramentas, agente Claude, base de conhecimento e o Vigia. Leitura pura;
// cada bloco leva à tela onde se age.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonInteligenciaAPI from 'dashboard/api/ramonInteligencia';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
import { modoDefault } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';
import VigiaBloco from './VigiaBloco.vue';

defineOptions({ name: 'CaptainVisaoGeral' });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

const visao = ref(null);
const assistentes = ref([]);
const execucoes = ref(null);
const loading = ref(true);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const [respVisao, respAssistentes, respExecucoes] = await Promise.all([
      RamonInteligenciaAPI.get(),
      CaptainAssistantAPI.stats(),
      CaptainToolRunsAPI.list(),
    ]);
    visao.value = respVisao.data;
    assistentes.value = respAssistentes.data.payload;
    execucoes.value = respExecucoes.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

// <progress> nativo pintado só com Tailwind (sem style).
const BARRA =
  'mt-2 block h-2 w-full appearance-none overflow-hidden rounded-full bg-n-slate-9/10 [&::-webkit-progress-bar]:bg-n-slate-9/10 [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9';
const DESFECHOS = [
  { chave: 'igual', tom: TOM.teal },
  { chave: 'editado', tom: TOM.blue },
  { chave: 'descartado', tom: TOM.ruby },
  { chave: 'sem_resposta', tom: TOM.slate },
  { chave: 'pendente', tom: TOM.slate },
];
const LADOS = ['com_ia', 'sem_ia'];

const rascunhos = computed(() => visao.value.rascunhos);
const totalRascunhos = computed(() =>
  Object.values(rascunhos.value).reduce((soma, n) => soma + n, 0)
);
const piloto = computed(() => visao.value.piloto);
const pilotoEmVigor = computed(() => modoDefault().startsWith('piloto_'));
const resposta = computed(() => visao.value.primeira_resposta);
const transferencias = computed(() => visao.value.transferencias);
const aprovacoes = computed(() => visao.value.aprovacoes);
const agente = computed(() => visao.value.agente);
const caderno = computed(() => visao.value.caderno || []);

const faqsPendentes = computed(() =>
  assistentes.value.reduce((soma, item) => soma + item.faqs_pendentes, 0)
);
const assistenteComPendentes = computed(
  () =>
    [...assistentes.value].sort(
      (a, b) => b.faqs_pendentes - a.faqs_pendentes
    )[0]
);
const temAprovacao = computed(
  () => aprovacoes.value.sugestoes > 0 || faqsPendentes.value > 0
);

const resumoTools = computed(() => execucoes.value.resumo);
const topTools = computed(() =>
  Object.entries(resumoTools.value.por_tool)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([id, total]) => ({
      ...ferramentaInfo(id, execucoes.value.catalogo),
      total,
    }))
);

const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const ir = (name, params = {}, query = {}) =>
  router.push(accountScopedRoute(name, params, query));
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.VISAO_GERAL.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.VISAO_GERAL.SUBTITLE') }}
      </p>

      <div
        v-if="error"
        data-testid="visao-geral-error"
        class="mt-4 text-sm"
        :class="[CARTAO]"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <button
          type="button"
          class="mt-1 text-xs text-n-blue-11 hover:underline"
          @click="fetchData"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>
      <p v-else-if="loading" class="mt-6 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.LOADING') }}
      </p>

      <div v-else class="grid gap-3 mt-5 lg:grid-cols-2">
        <!-- I-VG3: aprovações esperando você -->
        <section
          data-testid="vg-aprovacoes"
          :class="[CARTAO_STATUS, temAprovacao ? FILETE.amber : FILETE.teal]"
        >
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TITULO') }}
          </h2>
          <p v-if="!temAprovacao" class="mt-2 text-sm text-n-slate-11">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.NADA') }}
          </p>
          <div v-if="aprovacoes.sugestoes" class="mt-2">
            <p class="text-sm text-n-slate-12">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.SUGESTOES', {
                  n: aprovacoes.sugestoes,
                })
              }}
            </p>
            <div class="flex flex-wrap gap-1.5 mt-1">
              <button
                v-for="(n, tipo) in aprovacoes.sugestoes_por_tipo"
                :key="tipo"
                type="button"
                data-testid="vg-sugestao-tipo"
                class="hover:underline"
                :class="[CHIP, TOM.amber]"
                @click="ir('ramon_index', {}, { sugestoes: tipo })"
              >
                {{
                  t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO_N', {
                    tipo: t(
                      `CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO.${tipo}`
                    ),
                    n,
                  })
                }}
              </button>
            </div>
            <Button
              class="mt-2"
              size="xs"
              variant="faded"
              color="amber"
              icon="i-lucide-arrow-right"
              :label="t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.ABRIR_SUGESTOES')"
              @click="ir('ramon_index', {}, { sugestoes: 'todas' })"
            />
          </div>
          <div v-if="faqsPendentes" class="mt-3">
            <p class="text-sm text-n-slate-12">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.FAQS', {
                  n: faqsPendentes,
                })
              }}
            </p>
            <Button
              class="mt-1"
              size="xs"
              variant="faded"
              color="amber"
              icon="i-lucide-arrow-right"
              :label="t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.ABRIR_FAQS')"
              @click="
                ir('captain_assistants_responses_pending', {
                  assistantId: assistenteComPendentes.id,
                })
              "
            />
          </div>
        </section>

        <!-- I-VG2: régua da D7 -->
        <section data-testid="vg-piloto" :class="CARTAO">
          <h2 :class="TITULO">
            {{
              pilotoEmVigor
                ? t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.TITULO_EM_VIGOR')
                : t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.TITULO_RUMO')
            }}
          </h2>
          <p class="mt-2 text-sm text-n-slate-12">
            {{
              t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.REGUA', {
                conversas: piloto.conversas,
                meta: piloto.meta,
              })
            }}
          </p>
          <progress
            :class="BARRA"
            :value="piloto.conversas"
            :max="piloto.meta"
          />
          <p class="mt-2 text-xs text-n-slate-11">
            {{
              piloto.sem_correcao_pct === null
                ? t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.SEM_DADOS')
                : t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.SEM_CORRECAO', {
                    pct: piloto.sem_correcao_pct,
                  })
            }}
          </p>
          <p v-if="pilotoEmVigor" class="mt-2" :class="[AVISO, TOM.teal]">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.EM_VIGOR') }}
          </p>
        </section>

        <!-- rascunhos da IA -->
        <section data-testid="vg-rascunhos" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.TITULO') }}
          </h2>
          <p class="mt-2 text-2xl font-semibold text-n-slate-12">
            {{ totalRascunhos }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.GERADOS') }}
          </p>
          <div class="flex flex-wrap gap-1.5 mt-2">
            <span
              v-for="desfecho in DESFECHOS"
              :key="desfecho.chave"
              :class="[CHIP, desfecho.tom]"
            >
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.DESFECHO_N', {
                  desfecho: t(
                    `CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.${desfecho.chave}`
                  ),
                  n: rascunhos[desfecho.chave] ?? 0,
                })
              }}
            </span>
          </div>
        </section>

        <!-- tempo até a 1ª resposta -->
        <section data-testid="vg-resposta" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.TITULO') }}
          </h2>
          <div class="grid grid-cols-2 gap-3 mt-2">
            <div v-for="lado in LADOS" :key="lado">
              <p class="text-xs text-n-slate-10">
                {{ t(`CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.${lado}`) }}
              </p>
              <p class="text-2xl font-semibold text-n-slate-12">
                {{
                  resposta[lado]
                    ? t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.MEDIANA', {
                        min: resposta[lado].mediana_min.toLocaleString('pt-BR'),
                      })
                    : t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.SEM_DADOS')
                }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{
                  t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.CONVERSAS', {
                    n: resposta[lado]?.conversas ?? 0,
                  })
                }}
              </p>
            </div>
          </div>
          <p class="mt-2 text-xs text-n-slate-10">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.NOTA') }}
          </p>
        </section>

        <!-- transferências pra humano -->
        <section data-testid="vg-transferencias" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.TRANSFERENCIAS.TITULO') }}
          </h2>
          <p class="mt-2 text-2xl font-semibold text-n-slate-12">
            {{ transferencias.total }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.TRANSFERENCIAS.TOTAL') }}
          </p>
          <div
            v-if="transferencias.conversas.length"
            class="flex flex-wrap gap-1.5 mt-2"
          >
            <button
              v-for="id in transferencias.conversas"
              :key="id"
              type="button"
              class="hover:underline"
              :class="[CHIP, TOM.blue]"
              @click="ir('inbox_conversation', { conversation_id: id })"
            >
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.TRANSFERENCIAS.CONVERSA', { id })
              }}
            </button>
          </div>
        </section>

        <!-- ferramentas 24h -->
        <section data-testid="vg-ferramentas" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.TITULO') }}
          </h2>
          <div class="flex flex-wrap gap-1.5 mt-2">
            <span :class="[CHIP, TOM.slate]">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.EXECUCOES', {
                  n: resumoTools.total_24h,
                })
              }}
            </span>
            <span :class="[CHIP, resumoTools.erros_24h ? TOM.ruby : TOM.slate]">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.ERROS', {
                  n: resumoTools.erros_24h,
                })
              }}
            </span>
          </div>
          <ul v-if="topTools.length" class="flex flex-col gap-1 mt-2">
            <li
              v-for="tool in topTools"
              :key="tool.id"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              <span class="truncate">{{ tool.title }}</span>
              <span v-if="tool.nivel" :class="[CHIP, tool.tom]">
                {{ t(`CAPTAIN_RAMON.NIVEL.${tool.nivel}`) }}
              </span>
              <span class="ml-auto text-xs text-n-slate-10">
                {{ tool.total }}
              </span>
            </li>
          </ul>
          <p v-else class="mt-2 text-sm text-n-slate-11">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.NADA') }}
          </p>
          <Button
            class="mt-2"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-right"
            :label="t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.VER')"
            @click="ir('captain_execucoes_index')"
          />
        </section>

        <!-- agente Claude -->
        <section data-testid="vg-agente" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.TITULO') }}
          </h2>
          <p class="mt-2 text-sm text-n-slate-12">
            {{
              t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.HOJE', {
                n: agente.hoje,
                teto: agente.teto,
              })
            }}
          </p>
          <progress :class="BARRA" :value="agente.hoje" :max="agente.teto" />
          <span
            v-if="agente.problemas_hoje"
            class="mt-2"
            :class="[CHIP, TOM.ruby]"
          >
            {{
              t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.PROBLEMAS', {
                n: agente.problemas_hoje,
              })
            }}
          </span>
          <p class="mt-2 text-xs text-n-slate-10">
            {{
              agente.ultima_em
                ? t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.ULTIMA', {
                    quando: fmtHora(agente.ultima_em),
                  })
                : t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.NUNCA')
            }}
          </p>
          <Button
            class="mt-2"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-right"
            data-testid="vg-agente-trilha"
            :label="t('INTEL.VISAO_GERAL.VER_TRILHA')"
            @click="ir('captain_execucoes_index', {}, { aba: 'agente' })"
          />
        </section>

        <!-- base de conhecimento -->
        <section data-testid="vg-base" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.BASE.TITULO') }}
          </h2>
          <ul class="flex flex-col gap-2 mt-2 list-none">
            <li v-for="assistente in assistentes" :key="assistente.id">
              <p class="text-sm font-medium text-n-slate-12">
                {{ assistente.name }}
              </p>
              <div class="flex flex-wrap gap-1.5 mt-1">
                <button
                  type="button"
                  class="hover:underline"
                  :class="[CHIP, TOM.slate]"
                  @click="
                    ir('captain_assistants_scenarios_index', {
                      assistantId: assistente.id,
                    })
                  "
                >
                  {{
                    t('CAPTAIN_RAMON.ASSISTENTES.SKILLS', {
                      n: assistente.skills_ativas,
                    })
                  }}
                </button>
                <button
                  type="button"
                  class="hover:underline"
                  :class="[CHIP, TOM.slate]"
                  @click="
                    ir('captain_assistants_responses_index', {
                      assistantId: assistente.id,
                    })
                  "
                >
                  {{
                    t('CAPTAIN_RAMON.ASSISTENTES.FAQS', {
                      n: assistente.faqs_aprovadas,
                    })
                  }}
                </button>
                <span
                  v-if="assistente.faqs_pendentes"
                  :class="[CHIP, TOM.amber]"
                >
                  {{
                    t('CAPTAIN_RAMON.ASSISTENTES.FAQS_PENDENTES', {
                      n: assistente.faqs_pendentes,
                    })
                  }}
                </span>
              </div>
            </li>
          </ul>
        </section>

        <!-- I-X6: caderno de provas (última rodada concluída por assistente) -->
        <section data-testid="vg-caderno" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('INTEL.VISAO_GERAL.CADERNO.TITULO') }}
          </h2>
          <p v-if="!caderno.length" class="mt-2 text-sm text-n-slate-10">
            {{ t('INTEL.VISAO_GERAL.CADERNO.NUNCA') }}
          </p>
          <ul v-else class="flex flex-col gap-2 mt-2 list-none">
            <li
              v-for="item in caderno"
              :key="item.assistant_id"
              data-testid="vg-caderno-linha"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span
                  :class="[
                    CHIP,
                    item.passou === item.total ? TOM.teal : TOM.ruby,
                  ]"
                >
                  {{
                    t('INTEL.VISAO_GERAL.CADERNO.LINHA', {
                      nome: item.nome,
                      n: item.passou,
                      total: item.total,
                    })
                  }}
                </span>
                <Button
                  v-if="isAdmin"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-arrow-right"
                  :label="t('INTEL.VISAO_GERAL.CADERNO.ABRIR')"
                  @click="
                    ir('captain_assistants_casos_teste_index', {
                      assistantId: item.assistant_id,
                    })
                  "
                />
              </div>
              <p class="mt-1 text-xs text-n-slate-10">
                {{
                  t('INTEL.VISAO_GERAL.CADERNO.QUANDO', {
                    quando: fmtHora(item.em * 1000),
                  })
                }}
              </p>
            </li>
          </ul>
        </section>

        <VigiaBloco class="lg:col-span-2" />
      </div>
    </div>
  </section>
</template>
