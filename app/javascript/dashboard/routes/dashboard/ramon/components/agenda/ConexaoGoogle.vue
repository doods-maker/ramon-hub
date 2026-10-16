<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ramonGoogleAgendaAPI from 'dashboard/api/ramonGoogleAgenda';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';

// compacto: só o botão conectar/reconectar (cabeçalho da Agenda); conectado = nada.
defineProps({ compacto: { type: Boolean, default: false } });

const { t } = useI18n();
const carregado = ref(false);
const conectada = ref(false);
const email = ref('');
const revogada = ref(false); // token revogado → oferece reconectar
const carregando = ref(false);

const carregar = async () => {
  try {
    const { data } = await ramonGoogleAgendaAPI.status();
    conectada.value = Boolean(data.conectada);
    email.value = data.email || '';
    revogada.value = data.status === 'desconectada';
    carregado.value = true;
  } catch (e) {
    carregado.value = false; // sem status, não oferece nada
  }
};

const conectar = async () => {
  carregando.value = true;
  try {
    const { data } = await ramonGoogleAgendaAPI.autorizar();
    window.location.href = data.url;
  } catch (e) {
    useAlert(t('RAMON.AGENDA.GOOGLE_ERRO'));
  } finally {
    carregando.value = false;
  }
};

const desconectar = async () => {
  try {
    await ramonGoogleAgendaAPI.desconectar();
    await carregar();
  } catch (e) {
    useAlert(t('RAMON.AGENDA.GOOGLE_ERRO'));
  }
};

const rotuloConectar = computed(() =>
  revogada.value
    ? t('RAMON.AGENDA.RECONECTAR_GOOGLE')
    : t('RAMON.AGENDA.CONECTAR_GOOGLE')
);

onMounted(carregar);
</script>

<template>
  <template v-if="carregado">
    <Button
      v-if="compacto && !conectada"
      sm
      faded
      blue
      icon="i-lucide-calendar-plus"
      data-testid="agenda-conectar-google"
      :label="rotuloConectar"
      :is-loading="carregando"
      @click="conectar"
    />
    <div
      v-else-if="!compacto"
      class="flex flex-col gap-3 items-start"
      data-testid="google-agenda-card"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        <template v-if="conectada">
          {{ t('RAMON.AGENDA.GOOGLE_CONECTADO_COMO', { email }) }}
        </template>
        <template v-else-if="revogada">
          {{ t('RAMON.AGENDA.GOOGLE_REVOGADO') }}
        </template>
        <template v-else>{{ t('RAMON.AGENDA.GOOGLE_NAO_CONECTADO') }}</template>
      </p>
      <ConfirmButton
        v-if="conectada"
        :label="t('RAMON.AGENDA.DESCONECTAR')"
        :confirm-label="t('RAMON.AGENDA.DESCONECTAR_CONFIRMA')"
        color="slate"
        confirm-color="ruby"
        variant="outline"
        icon="i-lucide-unplug"
        class="rounded-xl"
        data-testid="google-agenda-desconectar"
        @click="desconectar"
      />
      <Button
        v-else
        sm
        blue
        icon="i-lucide-calendar-plus"
        data-testid="google-agenda-conectar"
        :label="rotuloConectar"
        :is-loading="carregando"
        @click="conectar"
      />
    </div>
  </template>
</template>
