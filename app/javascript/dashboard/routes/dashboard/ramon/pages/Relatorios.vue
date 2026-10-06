<script setup>
import { onMounted, ref } from 'vue';
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

const fetchEmbed = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonRelatoriosAPI.get();
    configured.value = data.configured;
    embedUrl.value = data.url || '';
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchEmbed);
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
        @click="fetchEmbed"
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
      />
    </div>
  </div>
</template>
