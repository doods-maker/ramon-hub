<script setup>
// "Vincular a um lead" da reunião gravada: acha a pessoa (mesma busca de
// contato do VincularCalculo) e escolhe o caso dela. Quem grava é o pai.
import { ref, watch } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  RODAPE_JANELA,
  TITULO,
  TITULO_JANELA,
} from '../../helpers/ui';

const emit = defineEmits(['cancel', 'escolhido']);

const termo = ref('');
const pessoas = ref([]);
const pessoa = ref(null);
const casos = ref([]);
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

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <Teleport to="body">
    <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
      <div class="!w-96" :class="JANELA" data-testid="reuniao-vincular-janela">
        <h3 :class="TITULO_JANELA">{{ $t('RAMON.REUNIOES.LINK_TITLE') }}</h3>
        <p class="mb-3 text-xs text-n-slate-10">
          {{ $t('RAMON.REUNIOES.LINK_HINT') }}
        </p>
        <input
          v-model="termo"
          data-testid="reuniao-vincular-busca"
          :class="CAMPO"
          :placeholder="$t('RAMON.REUNIOES.LINK_SEARCH')"
        />
        <ul
          v-if="!pessoa && pessoas.length"
          class="flex flex-col mt-2 list-none reset-base ms-0"
        >
          <li v-for="c in pessoas" :key="c.id">
            <button
              data-testid="reuniao-vincular-pessoa"
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
                data-testid="reuniao-vincular-caso"
                :class="LINHA"
                @click="emit('escolhido', caso)"
              >
                {{ caso.thesis_name || caso.name }}
              </button>
            </li>
          </ul>
          <p v-else class="mb-0 text-sm text-n-slate-10">
            {{ $t('RAMON.REUNIOES.LINK_NO_CASE', { name: pessoa.name }) }}
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
      </div>
    </div>
  </Teleport>
</template>
