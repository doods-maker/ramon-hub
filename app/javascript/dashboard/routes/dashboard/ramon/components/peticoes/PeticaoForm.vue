<script setup>
// Nova petição / editar dados: cliente (busca de contato), processo CNJ com
// sugestões do espelho do ADVBOX, inicial (tribunal na mão), responsável,
// prazo e descrição. Quem grava é o backend; aqui só o formulário.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { mensagemErro } from '../../helpers/erro';
import {
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  ROTULO,
  RODAPE_JANELA,
  SELECT,
  TITULO_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  peticao: { type: Object, default: null }, // null = nova
  tribunais: { type: Array, default: () => [] },
});
const emit = defineEmits(['salvo', 'cancel']);

const { t } = useI18n();
const store = useStore();
const agentes = useMapGetter('agents/getAgents');
const meuId = useMapGetter('getCurrentUserID');

const p = props.peticao || {};
const contato = ref(p.contato || null);
const termo = ref('');
const pessoas = ref([]);
const processos = ref([]);
const form = ref({
  numero_processo: p.numero_processo || '',
  inicial: !!p.inicial,
  tribunal: p.inicial ? p.tribunal : '',
  responsavel_id: p.responsavel?.id || meuId.value,
  prazo: p.prazo || '',
  descricao: p.descricao || '',
});
const salvando = ref(false);
const erro = ref('');

const agentesOrdenados = computed(() =>
  [...(agentes.value || [])].sort((a, b) =>
    a.name.localeCompare(b.name, 'pt-BR')
  )
);

let espera = null;
watch(termo, valor => {
  clearTimeout(espera);
  if (valor.trim().length < 2) {
    pessoas.value = [];
    return;
  }
  espera = setTimeout(async () => {
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

const carregarProcessos = async () => {
  processos.value = [];
  if (!contato.value) return;
  try {
    const { data } = await RamonPeticoesAPI.processos(contato.value.id);
    processos.value = data.processos;
  } catch {
    processos.value = [];
  }
};

const escolher = c => {
  contato.value = { id: c.id, name: c.name };
  termo.value = '';
  pessoas.value = [];
  carregarProcessos();
};

const salvar = async () => {
  salvando.value = true;
  erro.value = '';
  const { inicial } = form.value;
  // Tribunal vazio = o backend deduz pelo número.
  const dados = {
    ...form.value,
    contact_id: contato.value?.id || '',
    numero_processo: inicial ? '' : form.value.numero_processo,
    tribunal: inicial ? form.value.tribunal : '',
  };
  try {
    const { data } = props.peticao
      ? await RamonPeticoesAPI.update(props.peticao.id, dados)
      : await RamonPeticoesAPI.create(dados);
    emit('salvo', data);
  } catch (e) {
    erro.value = mensagemErro(e, t('RAMON.PETICOES.ERRO_ACAO'));
  } finally {
    salvando.value = false;
  }
};

onKeyStroke('Escape', () => emit('cancel'));
onMounted(() => {
  store.dispatch('agents/get');
  carregarProcessos();
});
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

        <div :class="ROTULO">
          {{ t('RAMON.PETICOES.CLIENTE') }}
          <div v-if="contato" class="flex items-center justify-between gap-2">
            <span class="truncate text-sm text-n-slate-12">{{
              contato.name
            }}</span>
            <Button
              link
              xs
              type="button"
              :label="t('RAMON.PETICOES.TROCAR')"
              @click="contato = null"
            />
          </div>
          <template v-else>
            <input
              v-model="termo"
              data-testid="peticao-form-cliente"
              :class="CAMPO"
              :placeholder="t('RAMON.PETICOES.CLIENTE_BUSCA')"
            />
            <ul
              v-if="pessoas.length"
              class="reset-base ms-0 flex list-none flex-col"
            >
              <li v-for="c in pessoas" :key="c.id">
                <button
                  type="button"
                  class="flex items-center justify-between gap-3"
                  :class="LINHA"
                  @click="escolher(c)"
                >
                  <span class="truncate text-n-slate-12">{{ c.name }}</span>
                  <span class="shrink-0 font-mono text-xs text-n-slate-10">
                    {{ c.phone_number || '' }}
                  </span>
                </button>
              </li>
            </ul>
          </template>
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="form.inicial" type="checkbox" />
          {{ t('RAMON.PETICOES.INICIAL') }}
        </label>

        <label v-if="form.inicial" :class="ROTULO">
          {{ t('RAMON.PETICOES.TRIBUNAL') }}
          <select v-model="form.tribunal" required :class="SELECT">
            <option v-for="tr in tribunais" :key="tr.chave" :value="tr.chave">
              {{ tr.nome }}
            </option>
          </select>
        </label>
        <label v-else :class="ROTULO">
          {{ t('RAMON.PETICOES.NUMERO') }}
          <input
            v-model.trim="form.numero_processo"
            required
            list="peticao-form-processos"
            data-testid="peticao-form-numero"
            :class="CAMPO"
            :placeholder="t('RAMON.PETICOES.NUMERO_PLACEHOLDER')"
          />
          <datalist id="peticao-form-processos">
            <option
              v-for="pr in processos"
              :key="pr.numero"
              :value="pr.numero"
              :label="pr.tipo"
            />
          </datalist>
        </label>

        <label :class="ROTULO">
          {{ t('RAMON.PETICOES.RESPONSAVEL') }}
          <select v-model="form.responsavel_id" :class="SELECT">
            <option v-for="a in agentesOrdenados" :key="a.id" :value="a.id">
              {{ a.name }}
            </option>
          </select>
        </label>

        <label :class="ROTULO">
          {{ t('RAMON.PETICOES.PRAZO') }}
          <input v-model="form.prazo" type="date" :class="CAMPO" />
        </label>

        <label :class="ROTULO">
          {{ t('RAMON.PETICOES.DESCRICAO') }}
          <input
            v-model="form.descricao"
            :class="CAMPO"
            :placeholder="t('RAMON.PETICOES.DESCRICAO_PLACEHOLDER')"
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
            data-testid="peticao-form-salvar"
            :is-loading="salvando"
            :label="t('RAMON.PETICOES.SALVAR')"
          />
        </div>
      </form>
    </div>
  </Teleport>
</template>
