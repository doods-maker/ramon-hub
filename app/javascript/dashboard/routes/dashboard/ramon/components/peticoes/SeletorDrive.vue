<script setup>
// Seletor do Drive do escritório: abre na pasta do cliente (ou na raiz),
// navega pastas, busca por nome em todo o Drive e põe os arquivos marcados
// no pacote (o hub baixa na hora; o pacote não muda se a pasta mudar).
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatarMB } from './helpers';
import { mensagemErro } from '../../helpers/erro';
import {
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  RODAPE_JANELA,
  TITULO_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  peticaoId: { type: Number, required: true },
  pastaInicial: { type: String, default: '' },
});
const emit = defineEmits(['adicionado', 'cancel']);

const { t } = useI18n();
const pasta = ref(null); // { pasta_id, pai_id, raiz_id, itens }
const busca = ref('');
const encontrados = ref(null); // resultado da busca; null = mostrando a pasta
const marcados = ref([]);
const carregando = ref(false);
const adicionando = ref(false);
const erro = ref('');

const itens = computed(() => encontrados.value || pasta.value?.itens || []);

const falhou = e => {
  erro.value =
    e?.response?.data?.error === 'DRIVE_OFF'
      ? t('RAMON.PETICOES.DRIVE_OFF')
      : mensagemErro(e, t('RAMON.PETICOES.DRIVE_ERRO'));
};

const abrir = async pastaId => {
  carregando.value = true;
  erro.value = '';
  try {
    const { data } = await RamonPeticoesAPI.drive(pastaId);
    pasta.value = data;
    busca.value = '';
    encontrados.value = null;
  } catch (e) {
    falhou(e);
  } finally {
    carregando.value = false;
  }
};

let espera = null;
watch(busca, valor => {
  clearTimeout(espera);
  if (valor.trim().length < 3) {
    encontrados.value = null;
    return;
  }
  espera = setTimeout(async () => {
    try {
      const { data } = await RamonPeticoesAPI.buscarDrive(valor.trim());
      encontrados.value = data.itens;
    } catch (e) {
      falhou(e);
    }
  }, 400);
});

const clicar = item => {
  if (item.pasta) {
    abrir(item.id);
    return;
  }
  marcados.value = marcados.value.includes(item.id)
    ? marcados.value.filter(id => id !== item.id)
    : [...marcados.value, item.id];
};

const adicionar = async () => {
  adicionando.value = true;
  erro.value = '';
  try {
    const { data } = await RamonPeticoesAPI.adicionarDoDrive(
      props.peticaoId,
      marcados.value
    );
    emit('adicionado', data);
  } catch (e) {
    falhou(e);
  } finally {
    adicionando.value = false;
  }
};

onKeyStroke('Escape', () => emit('cancel'));
onMounted(() => abrir(props.pastaInicial));
</script>

<template>
  <Teleport to="body">
    <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
      <div
        class="flex !w-[32rem] flex-col gap-3"
        :class="JANELA"
        data-testid="seletor-drive"
      >
        <h3 class="!mb-0" :class="TITULO_JANELA">
          {{ t('RAMON.PETICOES.DRIVE_TITULO') }}
        </h3>
        <input
          v-model="busca"
          type="search"
          data-testid="seletor-drive-busca"
          :class="CAMPO"
          :placeholder="t('RAMON.PETICOES.DRIVE_BUSCA')"
        />
        <Button
          v-if="!encontrados && pasta && pasta.pai_id"
          link
          xs
          class="self-start"
          icon="i-lucide-arrow-left"
          :label="t('RAMON.PETICOES.DRIVE_VOLTAR')"
          @click="abrir(pasta.pai_id)"
        />

        <p v-if="erro" class="m-0 text-sm text-n-ruby-11">{{ erro }}</p>
        <div
          v-else-if="carregando"
          class="h-40 animate-pulse rounded-lg bg-n-alpha-2"
        />
        <p v-else-if="!itens.length" class="m-0 text-sm text-n-slate-10">
          {{ t('RAMON.PETICOES.DRIVE_VAZIO') }}
        </p>
        <ul
          v-else
          class="reset-base ms-0 flex max-h-80 list-none flex-col overflow-y-auto"
        >
          <li v-for="item in itens" :key="item.id">
            <button
              type="button"
              class="flex items-center gap-2"
              :class="[LINHA, marcados.includes(item.id) ? 'bg-n-alpha-2' : '']"
              data-testid="seletor-drive-item"
              @click="clicar(item)"
            >
              <span
                class="size-4 shrink-0 text-n-slate-10"
                :class="
                  item.pasta
                    ? 'i-lucide-folder'
                    : marcados.includes(item.id)
                      ? 'i-lucide-square-check text-n-blue-11'
                      : 'i-lucide-square'
                "
              />
              <span class="min-w-0 flex-1 truncate text-n-slate-12">{{
                item.name
              }}</span>
              <span
                v-if="!item.pasta"
                class="shrink-0 font-mono text-[11px] text-n-slate-10"
              >
                {{ formatarMB(item.size) }}
              </span>
            </button>
          </li>
        </ul>

        <div class="!mt-1" :class="RODAPE_JANELA">
          <Button
            sm
            faded
            slate
            :label="t('RAMON.MODAL.CANCEL')"
            @click="emit('cancel')"
          />
          <Button
            sm
            data-testid="seletor-drive-adicionar"
            :disabled="!marcados.length"
            :is-loading="adicionando"
            :label="t('RAMON.PETICOES.DRIVE_ADICIONAR', { n: marcados.length })"
            @click="adicionar"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
