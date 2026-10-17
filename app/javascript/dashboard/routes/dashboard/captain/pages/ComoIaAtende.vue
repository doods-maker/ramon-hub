<script setup>
// Como a IA atende (Inteligência, só admin): o Perfil da IA do padrão do escritório, de cada tese e de cada
// caixa sem tese — perfil pronto, Marcador na Trilha, Permissões e Gatilhos por Etapa (spec 2026-10-17).
// Tudo é rascunho na tela até "Salvar alterações", que manda só os alvos mudados (cfg inteiro; null = segue o padrão).
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonIaAtendimentoAPI from 'dashboard/api/ramonIaAtendimento';
import { CARTAO, CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  COR_DO_ESTADO,
  ajustes,
  baseDe,
  efetivo,
  estadoDaEtapa,
  marcadorDe,
  paraGravar,
} from 'dashboard/routes/dashboard/ramon/helpers/perfilIa';
import ListaAlvos from './comoIaAtende/ListaAlvos.vue';
import Trilha from './comoIaAtende/Trilha.vue';
import LimitesDaEtapa from './comoIaAtende/LimitesDaEtapa.vue';
import LimitesGerais from './comoIaAtende/LimitesGerais.vue';

defineOptions({ name: 'CaptainComoIaAtende' });

const { t } = useI18n();
const route = useRoute();
const K = 'RAMON.COMO_IA';
const PERFIS = ['cautelosa', 'equilibrada', 'acelerada'];

const dados = ref(null);
const erro = ref(false);
const salvando = ref(false);
// alvo ('padrao' | 'tese:<id>' | 'caixa:<id>') → cfg | null (segue o padrão): o do servidor e o da tela
const salvos = ref({});
const cfgs = ref({});
// limites gerais do escritório (só no Padrão): o do servidor e o da tela
const limitesSalvos = ref(null);
const limites = ref(null);
const alvoId = ref('padrao');
const etapaSel = ref('');

const copia = valor => JSON.parse(JSON.stringify(valor));
const aplicar = corpo => {
  dados.value = corpo;
  salvos.value = {
    padrao: corpo.padrao,
    ...Object.fromEntries(corpo.teses.map(x => [`tese:${x.id}`, x.cfg])),
    ...Object.fromEntries(corpo.caixas.map(x => [`caixa:${x.id}`, x.cfg])),
  };
  cfgs.value = copia(salvos.value);
  limitesSalvos.value = corpo.limites;
  limites.value = copia(corpo.limites);
  if (!etapaSel.value) etapaSel.value = corpo.etapas[0]?.chave ?? '';
};

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await RamonIaAtendimentoAPI.get();
    aplicar(data);
    if (route.query.alvo in cfgs.value) alvoId.value = route.query.alvo;
  } catch (e) {
    erro.value = true;
  }
};

const prontos = computed(() => dados.value.prontos);
const etapas = computed(() => dados.value.etapas);
const cfgDe = id => cfgs.value[id] ?? cfgs.value.padrao;
const nomePerfil = base => t(`${K}.PERFIS.${base}.NOME`);
const miniDe = cfg => {
  const marcador = marcadorDe(cfg, prontos.value, etapas.value);
  return etapas.value.map(e => estadoDaEtapa(e.chave, marcador, etapas.value));
};
const nAjustes = cfg => ajustes(cfg, prontos.value, etapas.value);
const comAjustes = (cfg, chave) => {
  const n = nAjustes(cfg);
  if (!n) return nomePerfil(baseDe(cfg));
  return t(`${K}.${chave}${n === 1 ? '_UM' : ''}`, {
    perfil: nomePerfil(baseDe(cfg)),
    n,
  });
};

const alvos = computed(() =>
  [
    { id: 'padrao', tipo: 'padrao', nome: t(`${K}.PADRAO`) },
    ...dados.value.teses.map(x => ({
      id: `tese:${x.id}`,
      tipo: 'tese',
      nome: x.nome,
    })),
    ...dados.value.caixas.map(x => ({
      id: `caixa:${x.id}`,
      tipo: 'caixa',
      nome: x.nome,
    })),
  ].map(alvo => {
    const segue = cfgs.value[alvo.id] === null;
    const cfg = cfgDe(alvo.id);
    return {
      ...alvo,
      estado: segue ? t(`${K}.LISTA.SEGUE`) : comAjustes(cfg, 'LISTA.AJUSTES'),
      personalizado: !segue && nAjustes(cfg) > 0,
      mini: miniDe(cfg),
    };
  })
);

const atual = computed(() => alvos.value.find(a => a.id === alvoId.value));
const segue = computed(() => cfgs.value[alvoId.value] === null);
const cfgAtual = computed(() => cfgDe(alvoId.value));
const base = computed(() => baseDe(cfgAtual.value));
const ajustesAtuais = computed(() => nAjustes(cfgAtual.value));
const selo = computed(() =>
  ajustesAtuais.value
    ? comAjustes(cfgAtual.value, 'SELO.PERSONALIZADO')
    : t(`${K}.SELO.PERFIL`, { perfil: nomePerfil(base.value) })
);
const marcadorAtual = computed(() =>
  marcadorDe(cfgAtual.value, prontos.value, etapas.value)
);
const etapaAtual = computed(() =>
  etapas.value.find(e => e.chave === etapaSel.value)
);

// Mudou = o que a IA faria (ou o "segue o padrão") é outro que o salvo.
const chave = cfg =>
  cfg ? JSON.stringify(efetivo(cfg, prontos.value, etapas.value)) : 'null';
const mudados = computed(() =>
  dados.value
    ? Object.keys(cfgs.value).filter(
        id => chave(cfgs.value[id]) !== chave(salvos.value[id])
      )
    : []
);
const limitesMudaram = computed(
  () =>
    !!limites.value &&
    JSON.stringify(limites.value) !== JSON.stringify(limitesSalvos.value)
);
const nMudancas = computed(
  () => mudados.value.length + (limitesMudaram.value ? 1 : 0)
);
const naoSalvas = computed(() =>
  nMudancas.value === 1
    ? t(`${K}.NAO_SALVAS_UMA`)
    : t(`${K}.NAO_SALVAS`, { n: nMudancas.value })
);

const definir = cfg => {
  cfgs.value[alvoId.value] = cfg;
};
const editar = muda => muda(cfgs.value[alvoId.value]);
const escolherPerfil = k => definir({ base: k });
const desfazer = () => definir({ base: base.value });
const personalizar = () => definir(copia(cfgs.value.padrao));
const voltarAoPadrao = () => definir(null);
const mudarMarcador = marcador =>
  editar(cfg => {
    cfg.marcador = marcador;
  });
const mudarPermissao = (acao, valor) =>
  editar(cfg => {
    cfg.permissoes = { ...cfg.permissoes, [acao]: valor };
  });
const mudarGatilhos = (etapa, lista) =>
  editar(cfg => {
    cfg.gatilhos = { ...cfg.gatilhos, [etapa]: lista };
  });

const salvar = async () => {
  const corpo = {};
  mudados.value.forEach(id => {
    const cfg = paraGravar(cfgs.value[id], etapas.value);
    if (id === 'padrao') {
      corpo.padrao = cfg;
      return;
    }
    const [tipo, numero] = id.split(':');
    const secao = tipo === 'tese' ? 'teses' : 'caixas';
    corpo[secao] = { ...corpo[secao], [numero]: cfg };
  });
  if (limitesMudaram.value) {
    const { agente_dia: _somenteLeitura, ...editaveis } = limites.value;
    corpo.limites = editaveis;
  }
  salvando.value = true;
  try {
    const { data } = await RamonIaAtendimentoAPI.salvar(corpo);
    aplicar(data);
    useAlert(t(`${K}.SALVO`));
  } catch (e) {
    useAlert(e?.response?.data?.error || t(`${K}.ERRO_SALVAR`));
  } finally {
    salvando.value = false;
  }
};

const avisarSaida = e => {
  if (!nMudancas.value) return;
  e.preventDefault();
  e.returnValue = '';
};
onMounted(() => {
  window.addEventListener('beforeunload', avisarSaida);
  carregar();
});
onBeforeUnmount(() => window.removeEventListener('beforeunload', avisarSaida));
// ponytail: window.confirm de propósito — o guard de rota precisa de resposta síncrona.
onBeforeRouteLeave(() => !nMudancas.value || window.confirm(t(`${K}.SAIR`)));
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center h-14 gap-2.5 px-6 border-b shrink-0 border-n-weak"
    >
      <span class="text-[13px] text-n-slate-10">
        {{ t(`${K}.INTELIGENCIA`) }}
      </span>
      <h1 class="text-[15px] font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`) }}
      </h1>
      <div class="flex items-center gap-3 ml-auto">
        <span
          v-if="nMudancas"
          data-testid="nao-salvas"
          class="text-xs text-n-slate-10"
        >
          {{ naoSalvas }}
        </span>
        <Button
          size="sm"
          icon="i-lucide-check"
          :label="t(`${K}.SALVAR`)"
          :disabled="!nMudancas || salvando"
          :is-loading="salvando"
          data-testid="salvar"
          @click="salvar"
        />
      </div>
    </header>

    <div v-if="erro" data-testid="erro" class="m-6 text-sm" :class="CARTAO">
      <p class="text-n-ruby-11">{{ t(`${K}.ERRO`) }}</p>
      <button
        type="button"
        class="mt-1 text-xs text-n-blue-11 hover:underline"
        @click="carregar"
      >
        {{ t(`${K}.TENTAR`) }}
      </button>
    </div>
    <p v-else-if="!dados" class="m-6 text-sm text-n-slate-10">
      {{ t(`${K}.CARREGANDO`) }}
    </p>

    <div
      v-else
      class="flex flex-col flex-1 min-h-0 overflow-y-auto md:flex-row md:overflow-hidden"
    >
      <ListaAlvos v-model="alvoId" :alvos="alvos" />

      <main class="flex-1 min-w-0 md:overflow-y-auto">
        <div class="w-full max-w-4xl px-6 pt-6 pb-16 lg:px-9">
          <div class="flex items-start gap-4">
            <div class="flex-1 min-w-0">
              <p class="text-xs text-n-slate-10">
                {{ t(`${K}.TIPO.${atual.tipo}`) }}
              </p>
              <h2
                data-testid="alvo-nome"
                class="text-xl font-semibold leading-tight text-n-slate-12"
              >
                {{ atual.nome }}
              </h2>
              <div
                class="flex flex-wrap items-center gap-2 mt-2 text-[12.5px] text-n-slate-11"
              >
                <span v-if="atual.tipo === 'padrao'">
                  {{ t(`${K}.VALE_TUDO`) }}
                </span>
                <template v-if="!segue">
                  <span
                    data-testid="selo"
                    :class="[CHIP, ajustesAtuais ? TOM.blue : TOM.slate]"
                  >
                    <span
                      v-if="ajustesAtuais"
                      class="i-lucide-sliders-horizontal size-3"
                      aria-hidden="true"
                    />
                    {{ selo }}
                  </span>
                  <button
                    v-if="ajustesAtuais"
                    type="button"
                    data-testid="desfazer"
                    class="font-medium text-n-blue-11 hover:underline"
                    @click="desfazer"
                  >
                    {{ t(`${K}.DESFAZER`) }}
                  </button>
                </template>
              </div>
            </div>
            <Button
              v-if="atual.tipo !== 'padrao' && !segue"
              size="sm"
              variant="outline"
              color="slate"
              icon="i-lucide-undo-2"
              :label="t(`${K}.VOLTAR_PADRAO`)"
              data-testid="voltar-padrao"
              @click="voltarAoPadrao"
            />
          </div>

          <div
            v-if="segue"
            data-testid="herda"
            class="flex flex-wrap items-center gap-3 px-3.5 py-3 mt-4 text-[13px] rounded-xl"
            :class="TOM.blue"
          >
            <span
              class="i-lucide-git-branch size-4 shrink-0"
              aria-hidden="true"
            />
            <span class="flex-1 min-w-0 text-n-slate-12">
              {{
                t(`${K}.HERDA.${atual.tipo}`, {
                  perfil: nomePerfil(baseDe(cfgs.padrao)),
                })
              }}
            </span>
            <Button
              size="sm"
              variant="faded"
              icon="i-lucide-pencil"
              :label="t(`${K}.PERSONALIZAR`)"
              data-testid="personalizar"
              @click="personalizar"
            />
          </div>

          <section class="mt-7" :class="{ 'opacity-50': segue }">
            <div class="flex flex-wrap items-baseline gap-2.5 mb-2.5">
              <h3 class="text-sm font-semibold text-n-slate-12">
                {{ t(`${K}.PERFIL.TITULO`) }}
              </h3>
              <span class="text-[12.5px] text-n-slate-10">
                {{ t(`${K}.PERFIL.DICA`) }}
              </span>
            </div>
            <div class="grid gap-2.5 md:grid-cols-3">
              <button
                v-for="k in PERFIS"
                :key="k"
                type="button"
                :data-testid="`perfil-${k}`"
                :disabled="segue"
                :aria-pressed="k === base"
                class="flex flex-col gap-1.5 p-3 text-left border border-solid rounded-xl disabled:cursor-not-allowed"
                :class="
                  k === base
                    ? 'border-n-blue-9 bg-n-blue-9/[0.08] ring-1 ring-inset ring-n-blue-9'
                    : 'border-n-weak hover:border-n-slate-6 hover:bg-n-alpha-2'
                "
                @click="escolherPerfil(k)"
              >
                <span
                  class="flex items-center gap-2 text-[13.5px] font-semibold text-n-slate-12"
                >
                  {{ nomePerfil(k) }}
                  <span
                    v-if="k === 'equilibrada'"
                    class="ml-auto"
                    :class="[CHIP, TOM.blue]"
                  >
                    {{ t(`${K}.PERFIL.RECOMENDADO`) }}
                  </span>
                </span>
                <span class="text-[12.5px] leading-snug text-n-slate-11">
                  {{ t(`${K}.PERFIS.${k}.DESCRICAO`) }}
                </span>
                <span class="flex gap-0.5 mt-1" aria-hidden="true">
                  <span
                    v-for="(estado, i) in miniDe({ base: k })"
                    :key="i"
                    class="flex-1 h-1 rounded-sm"
                    :class="COR_DO_ESTADO[estado]"
                  />
                </span>
              </button>
            </div>
          </section>

          <section class="mt-7" :class="{ 'opacity-50': segue }">
            <div class="flex flex-wrap items-baseline gap-2.5 mb-2.5">
              <h3 class="text-sm font-semibold text-n-slate-12">
                {{ t(`${K}.TRILHA.TITULO`) }}
              </h3>
              <span class="text-[12.5px] text-n-slate-10">
                {{ t(`${K}.TRILHA.DICA`) }}
              </span>
            </div>
            <Trilha
              v-model:selecionada="etapaSel"
              :etapas="etapas"
              :marcador="marcadorAtual"
              :travada="segue"
              @update:marcador="mudarMarcador"
            />
          </section>

          <section
            v-if="etapaAtual"
            class="mt-7"
            :class="{ 'opacity-50': segue }"
          >
            <LimitesDaEtapa
              :etapa="etapaAtual"
              :cfg="cfgAtual"
              :dados="dados"
              :travado="segue"
              @permissao="mudarPermissao"
              @gatilhos="mudarGatilhos"
            />
          </section>

          <section v-if="alvoId === 'padrao' && limites" class="mt-9">
            <LimitesGerais v-model="limites" />
          </section>
        </div>
      </main>
    </div>
  </section>
</template>
