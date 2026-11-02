<script setup>
// Nova petição / editar dados num modal: os campos vêm de CamposPeticao.
// Quem grava é o backend; aqui só o formulário.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import CamposPeticao from './CamposPeticao.vue';
import { dadosDoForm, erroPeticao, formDaPeticao } from './helpers';
import {
  FUNDO_JANELA,
  JANELA,
  RODAPE_JANELA,
  TITULO_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  peticao: { type: Object, default: null }, // null = nova
  tribunais: { type: Array, default: () => [] },
});
const emit = defineEmits(['salvo', 'cancel']);

const { t } = useI18n();
const meuId = useMapGetter('getCurrentUserID');

const contato = ref(props.peticao?.contato || null);
const form = ref(formDaPeticao(props.peticao, meuId.value));
const salvando = ref(false);
const erro = ref('');

const salvar = async () => {
  salvando.value = true;
  erro.value = '';
  const dados = dadosDoForm(form.value, contato.value);
  try {
    const { data } = props.peticao
      ? await RamonPeticoesAPI.update(props.peticao.id, dados)
      : await RamonPeticoesAPI.create(dados);
    emit('salvo', data);
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
        class="flex !w-[28rem] flex-col gap-3"
        :class="JANELA"
        data-testid="peticao-form"
        @submit.prevent="salvar"
      >
        <h3 class="!mb-0" :class="TITULO_JANELA">
          {{ peticao ? t('RAMON.PETICOES.EDITAR') : t('RAMON.PETICOES.NOVA') }}
        </h3>

        <CamposPeticao
          v-model:form="form"
          v-model:contato="contato"
          :tribunais="tribunais"
        />

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
            data-testid="peticao-form-salvar"
            :is-loading="salvando"
            :label="t('RAMON.PETICOES.SALVAR')"
          />
        </div>
      </form>
    </div>
  </Teleport>
</template>
