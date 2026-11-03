<script setup>
// Painel dos agentes: o foreman-vision da esteira em tela cheia (ADR 0013).
// Quem barra de verdade é o portão no Caddy; aqui só se decide o que mostrar.
import { useI18n } from 'vue-i18n';
import AprovacoesAgentes from '../components/AprovacoesAgentes.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { usePainelAgentes } from '../composables/usePainelAgentes';

defineOptions({ name: 'RamonPainelAgentes' });

const { t } = useI18n();
const { url, carregado } = usePainelAgentes();
</script>

<template>
  <section class="flex flex-col w-full h-full min-h-0 p-6">
    <RamonPageHeader
      compact
      :title="t('RAMON.AGENTES.TITLE')"
      :subtitle="t('RAMON.AGENTES.SUBTITLE')"
    />
    <AprovacoesAgentes v-if="url" />
    <iframe
      v-if="url"
      :src="url"
      :title="t('RAMON.AGENTES.TITLE')"
      referrerpolicy="no-referrer"
      class="flex-1 w-full min-h-0 border rounded-xl border-n-weak"
    />
    <p v-else-if="carregado" class="text-sm text-n-slate-11">
      {{ t('RAMON.AGENTES.SEM_ACESSO') }}
    </p>
  </section>
</template>
