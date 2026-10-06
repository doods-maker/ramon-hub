<script setup>
import { onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonRelatoriosAPI from 'dashboard/api/ramonRelatorios';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { AVISO, TOM } from '../helpers/ui';

defineOptions({ name: 'RamonRelatorios' });

const { t } = useI18n();
const loading = ref(true);
const error = ref(false);
const configured = ref(false);
const embedUrl = ref('');

// O link assinado do Metabase vence (expires_at, 8h no backend): renova 5 min
// antes, sem piscar a tela. Iframe com erro: busca um link novo uma vez só.
const RENOVAR_ANTES_MS = 5 * 60 * 1000;
const MINIMO_MS = 60 * 1000;
let renovacao = null;
let tentouDeNovo = false;

const fetchEmbed = async ({ silencioso = false } = {}) => {
  if (!silencioso) loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonRelatoriosAPI.get();
    configured.value = data.configured;
    embedUrl.value = data.url || '';
    clearTimeout(renovacao);
    if (data.expires_at) {
      const espera = new Date(data.expires_at) - Date.now() - RENOVAR_ANTES_MS;
      renovacao = setTimeout(
        () => fetchEmbed({ silencioso: true }),
        Math.max(espera, MINIMO_MS)
      );
    }
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

// ponytail: o navegador quase nunca dispara `error` em iframe (HTTP 4xx/5xx
// carregam normal); cobre só falha de rede. Link vencido já é coberto acima.
const onIframeErro = () => {
  if (tentouDeNovo) return;
  tentouDeNovo = true;
  fetchEmbed({ silencioso: true });
};

onMounted(fetchEmbed);
onUnmounted(() => clearTimeout(renovacao));
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background p-4 sm:p-8">
    <RamonPageHeader
      :title="t('RAMON.RELATORIOS.TITLE')"
      :subtitle="t('RAMON.RELATORIOS.SUBTITLE')"
      compact
    />
    <div v-if="loading" class="flex-1" />
    <div
      v-else-if="error"
      :class="[AVISO, TOM.ruby]"
      class="flex items-center gap-3 self-start"
    >
      {{ t('RAMON.RELATORIOS.LOAD_ERROR') }}
      <Button
        link
        xs
        :label="t('RAMON.RELATORIOS.RETRY')"
        @click="fetchEmbed()"
      />
    </div>
    <p v-else-if="!configured" :class="[AVISO, TOM.slate]" class="self-start">
      {{ t('RAMON.RELATORIOS.NOT_CONFIGURED') }}
    </p>
    <div
      v-else
      class="flex flex-1 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
    >
      <iframe
        :src="embedUrl"
        class="border-0 w-full flex-1"
        :title="t('RAMON.RELATORIOS.TITLE')"
        @error="onIframeErro"
      />
    </div>
  </div>
</template>
