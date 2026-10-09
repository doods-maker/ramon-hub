<script setup>
// Ficha da automação do sistema (decisão do Eduardo 08/10): o que faz, quando, o que mexe, travas, por que fica no
// código (regra fixa) ou no fluxo — com o botão para o fluxo de verdade — e como mudar. O texto vem do JSON
// (db/seeds/ramon/fluxos/sistema/<chave>.json → "ficha", em PT-BR); aqui só os títulos são i18n.
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineProps({ fluxo: { type: Object, required: true } });

const K = 'CAPTAIN_RAMON.FLUXOS.FICHA';
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const tomDoFluxo = f => {
  if (!f.ativo) return TOM.slate;
  return f.modo === 'normal' ? TOM.teal : TOM.amber;
};
</script>

<template>
  <div
    data-testid="ficha"
    class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 py-3.5"
  >
    <template v-if="fluxo.ficha">
      <section data-testid="ficha-o-que-faz">
        <h4 :class="TITULO" class="mb-1">{{ t(`${K}.O_QUE_FAZ`) }}</h4>
        <p class="text-[13.5px] leading-relaxed text-n-slate-12">
          {{ fluxo.ficha.o_que_faz }}
        </p>
      </section>

      <section data-testid="ficha-quando" :class="[CARTAO_STATUS, FILETE.blue]">
        <h4 :class="TITULO" class="mb-1 flex items-center gap-1">
          <i class="i-lucide-clock size-3" />{{ t(`${K}.QUANDO`) }}
        </h4>
        <p class="text-[13px] leading-relaxed text-n-slate-12">
          {{ fluxo.ficha.quando }}
        </p>
      </section>

      <section
        data-testid="ficha-o-que-mexe"
        :class="[CARTAO_STATUS, FILETE.blue]"
      >
        <h4 :class="TITULO" class="mb-1 flex items-center gap-1">
          <i class="i-lucide-database size-3" />{{ t(`${K}.O_QUE_MEXE`) }}
        </h4>
        <ul class="list-disc space-y-1 pl-4 text-[13px] text-n-slate-12">
          <li v-for="item in fluxo.ficha.o_que_mexe" :key="item">
            {{ item }}
          </li>
        </ul>
      </section>

      <section
        data-testid="ficha-travas"
        :class="[CARTAO_STATUS, FILETE.amber]"
      >
        <h4 :class="TITULO" class="mb-1 flex items-center gap-1">
          <i class="i-lucide-shield-check size-3" />{{ t(`${K}.TRAVAS`) }}
        </h4>
        <ul class="list-disc space-y-1 pl-4 text-[13px] text-n-slate-12">
          <li v-for="item in fluxo.ficha.travas" :key="item">{{ item }}</li>
        </ul>
      </section>

      <section
        data-testid="ficha-por-que"
        :class="[AVISO, fluxo.fixa ? TOM.slate : TOM.teal]"
        class="!text-[13px] leading-relaxed"
      >
        <b class="mb-1 block">
          {{ fluxo.fixa ? t(`${K}.POR_QUE_CODIGO`) : t(`${K}.NO_FLUXO`) }}
        </b>
        <p>{{ fluxo.ficha.por_que }}</p>
        <div v-if="!fluxo.fixa" class="mt-2 flex flex-wrap gap-1.5">
          <router-link
            v-for="f in fluxo.ficha.fluxos"
            :key="f.id"
            data-testid="ficha-abrir-fluxo"
            :to="
              accountScopedRoute('captain_automacoes_editor', { fluxoId: f.id })
            "
            :class="[CHIP, tomDoFluxo(f)]"
            class="hover:underline"
          >
            <i class="i-lucide-workflow size-3" />
            {{ t(`${K}.ABRIR_FLUXO`) }}: {{ f.nome }} ·
            {{ f.ativo ? t(`${K}.MODO.${f.modo}`) : t(`${K}.DESLIGADO`) }}
          </router-link>
          <span
            v-if="!fluxo.ficha.fluxos.length"
            data-testid="ficha-sem-fluxo"
            class="text-xs"
          >
            {{ t(`${K}.SEM_FLUXO`) }}
          </span>
        </div>
      </section>

      <section data-testid="ficha-mudar" :class="CARTAO">
        <h4 :class="TITULO" class="mb-1.5 flex items-center gap-1">
          <i class="i-lucide-message-square-text size-3" />
          {{ t(`${K}.MUDAR`) }}
        </h4>
        <p :class="[AVISO, TOM.blue]" class="!text-[13px] leading-relaxed">
          {{ fluxo.ficha.mudar.pedido }}
        </p>
        <h5 :class="TITULO" class="mb-1 mt-2.5">{{ t(`${K}.ARQUIVOS`) }}</h5>
        <ul
          class="list-none space-y-0.5 pl-0 font-mono text-[11.5px] text-n-slate-11"
        >
          <li
            v-for="arquivo in fluxo.ficha.mudar.arquivos"
            :key="arquivo"
            class="break-all"
          >
            {{ arquivo }}
          </li>
        </ul>
        <h5 :class="TITULO" class="mb-1 mt-2.5">{{ t(`${K}.IMPACTO`) }}</h5>
        <p class="text-[13px] leading-relaxed text-n-slate-12">
          {{ fluxo.ficha.mudar.impacto }}
        </p>
      </section>
    </template>

    <details
      data-testid="sistema-descricao"
      class="text-[12.5px] text-n-slate-11"
    >
      <summary
        class="cursor-pointer text-[11px] font-medium uppercase tracking-wider text-n-slate-10"
      >
        {{ t('CAPTAIN_RAMON.FLUXOS.EDITOR.COMO_RODA') }}
      </summary>
      <p class="mt-2 whitespace-pre-line leading-relaxed">
        {{ fluxo.descricao }}
      </p>
    </details>
  </div>
</template>
