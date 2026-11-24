<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonBiAPI from 'dashboard/api/ramonBi';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { AVISO, TOM } from '../helpers/ui';

defineOptions({ name: 'RamonBiEscritorio' });

const { t } = useI18n();
const versao = ref(null);
const enviando = ref(false);
const erro = ref('');
const input = ref(null);

const formatarData = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const carregar = async () => {
  try {
    const { data } = await RamonBiAPI.get();
    versao.value = data.enviado ? data : null;
  } catch {
    erro.value = t('RAMON.BI_ESCRITORIO.ERRO_ENVIO');
  }
};

const escolherArquivo = async event => {
  const [file] = event.target.files;
  event.target.value = '';
  if (!file) return;
  erro.value = '';
  // O servidor valida de novo (tipo e tamanho); aqui só poupa a ida e volta.
  if (!/\.html?$/i.test(file.name)) {
    erro.value = t('RAMON.BI_ESCRITORIO.ERRO_TIPO');
    return;
  }
  enviando.value = true;
  try {
    const { data } = await RamonBiAPI.enviar(file);
    versao.value = data;
  } catch (e) {
    // Em falha a versão anterior continua na tela.
    erro.value = e.response?.data?.error || t('RAMON.BI_ESCRITORIO.ERRO_ENVIO');
  } finally {
    enviando.value = false;
  }
};

onMounted(carregar);
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background p-4 sm:p-8">
    <RamonPageHeader
      :title="t('RAMON.BI_ESCRITORIO.TITULO')"
      :subtitle="
        versao
          ? t('RAMON.BI_ESCRITORIO.ENVIADO_EM', {
              data: formatarData(versao.enviado_em),
              nome: versao.enviado_por,
            })
          : ''
      "
      compact
    >
      <template #actions>
        <input
          ref="input"
          type="file"
          accept=".html,text/html"
          class="hidden"
          @change="escolherArquivo"
        />
        <Button
          sm
          :label="
            enviando
              ? t('RAMON.BI_ESCRITORIO.ENVIANDO')
              : t('RAMON.BI_ESCRITORIO.ENVIAR')
          "
          :is-loading="enviando"
          :disabled="enviando"
          @click="input.click()"
        />
      </template>
    </RamonPageHeader>
    <p v-if="erro" :class="[AVISO, TOM.ruby]" class="self-start mb-3">
      {{ erro }}
    </p>
    <div
      v-if="versao"
      class="flex flex-1 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
    >
      <!-- allow-scripts SEM allow-same-origin: o HTML roda isolado do hub. -->
      <iframe
        :srcdoc="versao.html"
        sandbox="allow-scripts"
        class="border-0 w-full flex-1"
        :title="t('RAMON.BI_ESCRITORIO.TITULO')"
      />
    </div>
    <p v-else :class="[AVISO, TOM.slate]" class="self-start">
      {{ t('RAMON.BI_ESCRITORIO.VAZIO') }}
    </p>
  </div>
</template>
