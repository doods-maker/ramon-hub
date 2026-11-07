<script setup>
// Imagens do passo a passo da etapa Documentos (Ramon::Documentos::PassoAPasso): uma por tema, guardadas no
// assistente e mandadas ao cliente pela ferramenta enviar_passo_a_passo. Só aparece com a chave da etapa ligada.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import {
  ARQUIVO,
  CARTAO,
  TITULO,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: { type: Number, required: true },
});
const { t } = useI18n();
const K = 'INTEL.PASSO_A_PASSO';

const dados = ref(null);
// false, ou o motivo da recusa (o do servidor, quando vem)
const erro = ref(false);

// chamada = () => promessa da API (dentro do try: falha síncrona também vira aviso)
const guardar = async chamada => {
  try {
    dados.value = (await chamada()).data;
    erro.value = false;
  } catch (e) {
    erro.value = e?.response?.data?.error || t(`${K}.ERRO`);
  }
};

onMounted(() =>
  guardar(() => CaptainAssistant.passosAPasso(props.assistantId))
);

const subir = (tema, evento) => {
  const arquivo = evento.target.files?.[0];
  if (arquivo)
    guardar(() =>
      CaptainAssistant.subirPassoAPasso(props.assistantId, tema, arquivo)
    );
};
const remover = tema =>
  guardar(() => CaptainAssistant.removerPassoAPasso(props.assistantId, tema));
</script>

<template>
  <section v-if="dados?.ligado" data-testid="passo-a-passo" :class="CARTAO">
    <p :class="TITULO">{{ t(`${K}.TITULO`) }}</p>
    <p class="mt-1 mb-3 text-xs text-n-slate-11">{{ t(`${K}.AJUDA`) }}</p>
    <p v-if="erro" class="mb-2 text-xs text-n-ruby-11">{{ erro }}</p>
    <ul class="reset-base flex list-none flex-col gap-3">
      <li
        v-for="item in dados.temas"
        :key="item.tema"
        :data-testid="`tema-${item.tema}`"
        class="flex flex-wrap items-center gap-3"
      >
        <img
          v-if="item.url"
          :src="item.url"
          :alt="t(`${K}.TEMAS.${item.tema}`)"
          class="size-12 rounded-md object-cover"
        />
        <span
          v-else
          class="i-lucide-image-off size-12 text-n-slate-8"
          aria-hidden="true"
        />
        <span class="min-w-0 flex-1 text-sm text-n-slate-12">
          {{ t(`${K}.TEMAS.${item.tema}`) }}
        </span>
        <input
          type="file"
          accept="image/jpeg,image/png"
          :aria-label="t(`${K}.ENVIAR`, { tema: t(`${K}.TEMAS.${item.tema}`) })"
          :class="ARQUIVO"
          class="max-w-56"
          @change="subir(item.tema, $event)"
        />
        <Button
          v-if="item.url"
          size="sm"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          :label="t(`${K}.REMOVER`)"
          @click="remover(item.tema)"
        />
      </li>
    </ul>
  </section>
</template>
