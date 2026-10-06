<script setup>
// Tela Ferramentas (I-FE1/I-FE2): o catálogo do config/agents/tools.yml — o
// que cada ferramenta faz, em qual sistema mexe, o nível (cor), em quais
// skills é usada e o que Execuções registrou. Leitura pura. As ferramentas
// HTTP personalizadas ficam na tela antiga, aberta pelo "Avançado" (admin).
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Policy from 'dashboard/components/policy.vue';
import CaptainFerramentasAPI from 'dashboard/api/captain/ferramentas';
import {
  AVISO,
  CARTAO,
  CHIP,
  SECAO,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  NIVEL_TOM,
  agruparPorSistema,
} from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';

defineOptions({ name: 'CaptainFerramentas' });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const ferramentas = ref([]);
const loading = ref(true);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await CaptainFerramentasAPI.get();
    ferramentas.value = response.data.payload;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const grupos = computed(() => agruparPorSistema(ferramentas.value));

const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const abrirSkill = skill =>
  router.push(
    accountScopedRoute('captain_assistants_scenarios_index', {
      assistantId: skill.assistant_id,
    })
  );
const abrirHttp = () =>
  router.push(
    accountScopedRoute('captain_assistants_index', {
      navigationPath: 'captain_tools_index',
    })
  );
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.FERRAMENTAS.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.FERRAMENTAS.SUBTITLE') }}
      </p>
      <div class="flex flex-wrap gap-1.5 mt-3">
        <span
          v-for="(tom, nivel) in NIVEL_TOM"
          :key="nivel"
          :class="[CHIP, tom]"
        >
          {{ t(`CAPTAIN_RAMON.NIVEL.${nivel}`) }}
        </span>
      </div>

      <div
        v-if="error"
        data-testid="ferramentas-error"
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

      <template v-else>
        <section
          v-for="grupo in grupos"
          :key="grupo.sistema"
          class="mt-6"
          :data-testid="`ferramentas-${grupo.sistema}`"
        >
          <h2 :class="TITULO">
            {{
              t('CAPTAIN_RAMON.FERRAMENTAS.GRUPO', {
                sistema: t(
                  `CAPTAIN_RAMON.FERRAMENTAS.SISTEMA.${grupo.sistema}`
                ),
                n: grupo.ferramentas.length,
              })
            }}
          </h2>
          <div class="flex flex-col gap-2 mt-2">
            <article
              v-for="tool in grupo.ferramentas"
              :key="tool.id"
              data-testid="ferramenta"
              :class="CARTAO"
            >
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ tool.title }}
                </h3>
                <span :class="[CHIP, NIVEL_TOM[tool.nivel]]">
                  {{ t(`CAPTAIN_RAMON.NIVEL.${tool.nivel}`) }}
                </span>
                <span
                  v-if="tool.erros_7d"
                  class="ml-auto"
                  :class="[CHIP, TOM.ruby]"
                >
                  {{
                    t('CAPTAIN_RAMON.FERRAMENTAS.ERROS_7D', {
                      n: tool.erros_7d,
                    })
                  }}
                </span>
              </div>
              <p class="mt-1 text-sm text-n-slate-11">{{ tool.description }}</p>
              <div
                class="flex flex-wrap items-center gap-1.5 mt-2 text-xs text-n-slate-10"
                :class="SECAO"
              >
                <span>{{ t('CAPTAIN_RAMON.FERRAMENTAS.USADA_EM') }}</span>
                <button
                  v-for="skill in tool.skills"
                  :key="skill.id"
                  type="button"
                  class="hover:underline"
                  :class="[CHIP, TOM.slate]"
                  @click="abrirSkill(skill)"
                >
                  {{
                    t('CAPTAIN_RAMON.FERRAMENTAS.SKILL', {
                      skill: skill.title,
                      assistente: skill.assistant_name,
                    })
                  }}
                </button>
                <span v-if="!tool.skills.length">
                  {{ t('CAPTAIN_RAMON.FERRAMENTAS.SEM_SKILL') }}
                </span>
                <span class="ml-auto">
                  {{
                    tool.ultima_execucao_em
                      ? t('CAPTAIN_RAMON.FERRAMENTAS.ULTIMA', {
                          quando: fmtHora(tool.ultima_execucao_em),
                          n: tool.execucoes_7d,
                        })
                      : t('CAPTAIN_RAMON.FERRAMENTAS.NUNCA')
                  }}
                </span>
              </div>
            </article>
          </div>
        </section>

        <Policy :permissions="['administrator']">
          <section
            data-testid="ferramentas-avancado"
            class="mt-6 flex flex-wrap items-center gap-3"
            :class="[AVISO, TOM.slate]"
          >
            <div class="flex-1 min-w-0">
              <p class="font-semibold">
                {{ t('CAPTAIN_RAMON.FERRAMENTAS.AVANCADO_TITULO') }}
              </p>
              <p>{{ t('CAPTAIN_RAMON.FERRAMENTAS.AVANCADO_TEXTO') }}</p>
            </div>
            <Button
              size="xs"
              variant="faded"
              color="slate"
              icon="i-lucide-arrow-right"
              :label="t('CAPTAIN_RAMON.FERRAMENTAS.AVANCADO_BOTAO')"
              @click="abrirHttp"
            />
          </section>
        </Policy>
      </template>
    </div>
  </section>
</template>
