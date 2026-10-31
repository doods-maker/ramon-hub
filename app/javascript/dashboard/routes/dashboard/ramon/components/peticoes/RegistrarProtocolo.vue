<script setup>
// Volta do tribunal: número do evento + comprovante (PDF ou print). O hub
// marca a petição como protocolada e arquiva pacote + comprovante no Drive.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { erroPeticao } from './helpers';
import {
  ARQUIVO,
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  ROTULO,
  RODAPE_JANELA,
  TITULO_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  peticaoId: { type: Number, required: true },
});
const emit = defineEmits(['registrado', 'cancel']);

const { t } = useI18n();
const numeroEvento = ref('');
const comprovante = ref(null);
const salvando = ref(false);
const erro = ref('');

const registrar = async () => {
  salvando.value = true;
  erro.value = '';
  try {
    const { data } = await RamonPeticoesAPI.registrarProtocolo(
      props.peticaoId,
      numeroEvento.value.trim(),
      comprovante.value
    );
    emit('registrado', data);
  } catch (e) {
    erro.value = erroPeticao(e, t);
  } finally {
    salvando.value = false;
  }
};

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <Teleport to="body">
    <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
      <form
        class="flex !w-96 flex-col gap-3"
        :class="JANELA"
        data-testid="registrar-protocolo"
        @submit.prevent="registrar"
      >
        <h3 class="!mb-0" :class="TITULO_JANELA">
          {{ t('RAMON.PETICOES.REGISTRAR') }}
        </h3>
        <label :class="ROTULO">
          {{ t('RAMON.PETICOES.NUMERO_EVENTO') }}
          <input
            v-model="numeroEvento"
            required
            data-testid="registrar-protocolo-evento"
            :class="CAMPO"
          />
        </label>
        <label :class="ROTULO">
          {{ t('RAMON.PETICOES.COMPROVANTE') }}
          <input
            type="file"
            required
            accept=".pdf,.jpg,.jpeg,.png"
            :class="ARQUIVO"
            @change="comprovante = $event.target.files[0] || null"
          />
        </label>
        <p v-if="erro" class="m-0 text-xs text-n-ruby-11">{{ erro }}</p>
        <div class="!mt-1" :class="RODAPE_JANELA">
          <Button
            sm
            faded
            slate
            type="button"
            :label="t('RAMON.MODAL.CANCEL')"
            @click="emit('cancel')"
          />
          <Button
            sm
            type="submit"
            data-testid="registrar-protocolo-salvar"
            :is-loading="salvando"
            :label="t('RAMON.PETICOES.REGISTRAR')"
          />
        </div>
      </form>
    </div>
  </Teleport>
</template>
