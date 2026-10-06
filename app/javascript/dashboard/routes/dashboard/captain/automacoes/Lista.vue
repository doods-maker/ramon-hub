<script setup>
// Automações (B2, mockup tela 1): 4 números, a lista de fluxos com liga/desliga
// e o que rodou hoje. A aba "Do sistema" chega na B3 (spec §8).
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  ABA,
  ABA_ATIVA,
  CHIP,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { gatilhoInfo } from './fluxo';
import NovoFluxo from './NovoFluxo.vue';

defineOptions({ name: 'CaptainAutomacoes' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const fluxos = ref([]);
const resumo = ref({});
const erro = ref(false);
const novo = ref(false);

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await RamonFluxosAPI.get();
    fluxos.value = data.payload.filter(f => f.origem !== 'sistema');
    resumo.value = data.resumo;
  } catch (e) {
    erro.value = true;
  }
};
onMounted(carregar);

const abrir = id =>
  router.push(accountScopedRoute('captain_automacoes_editor', { fluxoId: id }));

const ligar = async (fluxo, ativo) => {
  await RamonFluxosAPI.update(fluxo.id, { ativo });
  carregar();
};

const criar = async modelo => {
  try {
    const { data } = await RamonFluxosAPI.create({
      nome: t(`${K}.MODELOS.${modelo.chave}.NOME`),
      limite_dia: modelo.limite_dia ?? null,
      rascunho: modelo.desenho,
    });
    abrir(data.id);
  } catch (e) {
    useAlert(t(`${K}.ERRO_CRIAR`));
  }
};

const TRACO = '—';
const selo = f => {
  if (f.falharam_24h)
    return {
      classe: TOM.ruby,
      icone: 'i-lucide-triangle-alert',
      texto: t(`${K}.SELO.FALHOU`, { n: f.falharam_24h }),
    };
  if (!f.ativo)
    return { classe: TOM.slate, icone: '', texto: t(`${K}.SELO.DESLIGADO`) };
  return { classe: TOM.teal, icone: '', texto: t(`${K}.SELO.OK`) };
};
const subtitulo = f =>
  f.versao
    ? t(`${K}.VERSAO_EDITADO`, {
        versao: f.versao,
        data: new Date(f.editado_em).toLocaleDateString('pt-BR'),
      })
    : t(`${K}.NUNCA_PUBLICADO`);
const hojeLimite = f => `${f.hoje} / ${f.limite_dia ?? TRACO}`;
const largura = f =>
  `${Math.min(100, Math.round((f.hoje / f.limite_dia) * 100))}%`;
const ultima = iso =>
  iso ? dynamicTime(Math.floor(new Date(iso).getTime() / 1000)) : TRACO;
const gatilho = tipo => (tipo ? t(`${K}.GATILHOS.${tipo}`) : TRACO);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div
      class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak px-7"
    >
      <h1 class="text-[15px] font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`) }}
      </h1>
      <span class="hidden text-[13px] text-n-slate-10 md:inline">
        {{ t(`${K}.DICA`) }}
      </span>
      <Button
        class="ml-auto"
        sm
        icon="i-lucide-plus"
        :label="t(`${K}.NOVO`)"
        @click="novo = true"
      />
    </div>
    <div class="flex gap-1 border-b border-n-weak px-7 pt-3">
      <span :class="[ABA, ABA_ATIVA]">
        {{ t(`${K}.ABA_MEUS`) }}
        <span class="font-mono text-[11.5px] text-n-slate-10">
          {{ fluxos.length }}
        </span>
      </span>
    </div>

    <div class="flex-1 overflow-y-auto px-7 pb-12 pt-5">
      <div v-if="erro" class="text-sm text-n-ruby-11">
        {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
        <button
          type="button"
          class="ml-1 text-n-blue-11 hover:underline"
          @click="carregar"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else>
        <div
          data-testid="fluxos-resumo"
          class="mb-5 grid max-w-[1100px] grid-cols-2 gap-3 md:grid-cols-4"
        >
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.LIGADOS`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.ligados ?? 0 }}
              <small class="text-xs font-normal text-n-slate-10">
                {{ t(`${K}.RESUMO.DE`, { total: fluxos.length }) }}
              </small>
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.HOJE`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.hoje ?? 0 }}
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.ESPERANDO`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.esperando ?? 0 }}
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.FALHARAM`) }}
            </span>
            <b
              class="font-mono text-xl font-medium"
              :class="
                resumo.falharam_24h ? 'text-n-ruby-11' : 'text-n-slate-12'
              "
            >
              {{ resumo.falharam_24h ?? 0 }}
            </b>
          </div>
        </div>

        <p v-if="!fluxos.length" class="text-sm text-n-slate-10">
          {{ t(`${K}.VAZIO`) }}
        </p>

        <table v-else class="w-full max-w-[1100px] border-collapse">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-xs font-medium text-n-slate-10"
            >
              <th class="w-11 p-2" />
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.FLUXO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.GATILHO`) }}</th>
              <th class="p-2 font-medium">
                {{ t(`${K}.TABELA.HOJE_LIMITE`) }}
              </th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ESPERANDO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ULTIMA`) }}</th>
              <th class="p-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="f in fluxos"
              :key="f.id"
              data-testid="fluxo-linha"
              class="cursor-pointer border-b border-n-weak text-[13.5px] hover:bg-n-alpha-2"
              @click="abrir(f.id)"
            >
              <td class="p-2" @click.stop>
                <span
                  :title="f.versao ? '' : t(`${K}.PUBLIQUE_ANTES`)"
                  :class="f.versao ? '' : 'pointer-events-none opacity-50'"
                >
                  <Switch
                    :model-value="f.ativo"
                    @update:model-value="v => ligar(f, v)"
                  />
                </span>
              </td>
              <td class="p-2">
                <b class="block font-medium text-n-slate-12">{{ f.nome }}</b>
                <span class="text-[12.5px] text-n-slate-11">
                  {{ subtitulo(f) }}
                </span>
              </td>
              <td class="p-2">
                <span
                  class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11"
                >
                  <i
                    v-if="f.gatilho_tipo"
                    :class="gatilhoInfo(f.gatilho_tipo)?.icone"
                    class="size-3.5 text-n-blue-11"
                  />
                  {{ gatilho(f.gatilho_tipo) }}
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ hojeLimite(f) }}
                <span
                  v-if="f.limite_dia"
                  class="ml-1.5 inline-block h-[5px] w-14 overflow-hidden rounded-full bg-n-alpha-2 align-middle"
                >
                  <i
                    class="block h-full bg-n-blue-9"
                    :style="{ width: largura(f) }"
                  />
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">{{ f.esperando }}</td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ ultima(f.ultima_em) }}
              </td>
              <td class="p-2">
                <span :class="[CHIP, selo(f).classe]" class="font-mono">
                  <i
                    v-if="selo(f).icone"
                    :class="selo(f).icone"
                    class="size-3"
                  />
                  {{ selo(f).texto }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <NovoFluxo v-if="novo" @criar="criar" @fechar="novo = false" />
  </section>
</template>
