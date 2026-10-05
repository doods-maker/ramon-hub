<script setup>
// "Vincular a cliente" (histórico da tela Cálculos): acha a pessoa (mesma
// busca de contato da tela), escolhe o caso dela e leva o CNIS do cálculo pra
// lá. Caso que já tem OUTRO CNIS só é sobrescrito depois de confirmar.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import CalculosAPI from 'dashboard/api/calculos';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  RODAPE_JANELA,
  TITULO,
  TITULO_JANELA,
} from '../helpers/ui';

const props = defineProps({
  calculo: { type: Object, required: true },
});
const emit = defineEmits(['cancel', 'vinculado']);

const { t } = useI18n();

const termo = ref('');
const pessoas = ref([]);
const pessoa = ref(null);
const casos = ref([]);
const ocupado = ref(false);
// caso escolhido que já tem outro CNIS: espera o "Substituir".
const conflito = ref(null);
let timer = null;

watch(termo, valor => {
  clearTimeout(timer);
  pessoa.value = null;
  casos.value = [];
  if (valor.trim().length < 2) {
    pessoas.value = [];
    return;
  }
  timer = setTimeout(async () => {
    try {
      const { data } = await ContactAPI.search(
        encodeURIComponent(valor.trim()),
        1,
        'name',
        ''
      );
      pessoas.value = data.payload || [];
    } catch {
      pessoas.value = [];
    }
  }, 300);
});

const escolherPessoa = async contato => {
  pessoa.value = contato;
  try {
    const { data } = await LeadsAPI.get({ contact_id: contato.id });
    casos.value = data.payload || [];
  } catch {
    casos.value = [];
  }
};

const vincular = async (caso, substituir = false) => {
  ocupado.value = true;
  try {
    const { data } = await CalculosAPI.vincular(
      props.calculo.id,
      caso.id,
      substituir
    );
    emit('vinculado', data);
  } catch (error) {
    if (error?.response?.status === 409) conflito.value = caso;
    else useAlert(t('RAMON.CALCULOS.VINCULAR_ERRO'));
  } finally {
    ocupado.value = false;
  }
};

const diaMes = iso =>
  new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
    <div class="!w-96" :class="[JANELA]" data-testid="vincular-calculo">
      <h3 :class="TITULO_JANELA">{{ $t('RAMON.CALCULOS.VINCULAR_TITULO') }}</h3>

      <template v-if="conflito">
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            $t('RAMON.CALCULOS.VINCULAR_SUBSTITUIR', {
              data: diaMes(calculo.created_at),
            })
          }}
        </p>
        <div :class="RODAPE_JANELA">
          <Button
            sm
            faded
            slate
            :label="$t('RAMON.MODAL.CANCEL')"
            @click="conflito = null"
          />
          <Button
            data-testid="vincular-substituir"
            sm
            ruby
            :disabled="ocupado"
            :label="$t('RAMON.CALCULOS.REABRIR_SUBSTITUIR')"
            @click="vincular(conflito, true)"
          />
        </div>
      </template>

      <template v-else>
        <p class="mb-3 text-xs text-n-slate-10">
          {{ $t('RAMON.CALCULOS.VINCULAR_HINT') }}
        </p>
        <input
          v-model="termo"
          data-testid="vincular-busca"
          :class="CAMPO"
          :placeholder="$t('RAMON.CALCULOS.SEARCH_PLACEHOLDER')"
        />
        <ul
          v-if="!pessoa && pessoas.length"
          class="flex flex-col mt-2 list-none reset-base ms-0"
        >
          <li v-for="c in pessoas" :key="c.id">
            <button
              data-testid="vincular-pessoa"
              class="flex items-center justify-between gap-3"
              :class="LINHA"
              @click="escolherPessoa(c)"
            >
              <span class="truncate text-n-slate-12">{{ c.name }}</span>
              <span class="font-mono text-xs shrink-0 text-n-slate-10">
                {{ c.phone_number || '' }}
              </span>
            </button>
          </li>
        </ul>
        <template v-if="pessoa">
          <p class="mt-3 mb-1" :class="TITULO">{{ pessoa.name }}</p>
          <ul
            v-if="casos.length"
            class="flex flex-col list-none reset-base ms-0"
          >
            <li v-for="caso in casos" :key="caso.id">
              <button
                data-testid="vincular-caso"
                :disabled="ocupado"
                :class="LINHA"
                @click="vincular(caso)"
              >
                {{ caso.thesis_name || caso.name }}
              </button>
            </li>
          </ul>
          <p v-else class="mb-0 text-sm text-n-slate-10">
            {{ $t('RAMON.CALCULOS.VINCULAR_SEM_CASO', { name: pessoa.name }) }}
          </p>
        </template>
        <div :class="RODAPE_JANELA">
          <Button
            sm
            faded
            slate
            :label="$t('RAMON.MODAL.CANCEL')"
            @click="emit('cancel')"
          />
        </div>
      </template>
    </div>
  </div>
</template>
