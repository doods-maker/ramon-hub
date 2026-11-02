<script setup>
// Campos de dados da petição (cliente, processo/tribunal, responsável, prazo,
// descrição), usados no modal de PeticaoForm e na ConferenciaPasta. `incertos`
// = campos que a leitura da pasta não soube dizer: ficam destacados.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, LINHA, ROTULO, SELECT, TOM } from '../../helpers/ui';

const props = defineProps({
  tribunais: { type: Array, default: () => [] },
  incertos: { type: Array, default: () => [] },
  obrigatorios: { type: Boolean, default: true },
});
const form = defineModel('form', { type: Object, required: true });
const contato = defineModel('contato', { type: Object, default: null });

const { t } = useI18n();
const store = useStore();
const agentes = useMapGetter('agents/getAgents');

const termo = ref('');
const pessoas = ref([]);
const processos = ref([]);

const agentesOrdenados = computed(() =>
  [...(agentes.value || [])].sort((a, b) =>
    a.name.localeCompare(b.name, 'pt-BR')
  )
);

// Campo incerto: caixa âmbar translúcida (o rótulo "Confira" vem junto).
const marca = campo =>
  props.incertos.includes(campo) ? [TOM.amber, 'rounded-lg p-2'] : '';

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

onMounted(() => {
  store.dispatch('agents/get');
  carregarProcessos();
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <div :class="[ROTULO, marca('cpf')]">
      {{ t('RAMON.PETICOES.CLIENTE') }}
      <div v-if="contato" class="flex items-center justify-between gap-2">
        <span class="truncate text-sm text-n-slate-12">{{ contato.name }}</span>
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

    <label v-if="form.inicial" :class="[ROTULO, marca('tribunal')]">
      {{ t('RAMON.PETICOES.TRIBUNAL') }}
      <select v-model="form.tribunal" :required="obrigatorios" :class="SELECT">
        <option v-if="!obrigatorios" value="" />
        <option v-for="tr in tribunais" :key="tr.chave" :value="tr.chave">
          {{ tr.nome }}
        </option>
      </select>
    </label>
    <label v-else :class="[ROTULO, marca('numero_processo')]">
      {{ t('RAMON.PETICOES.NUMERO') }}
      <input
        v-model.trim="form.numero_processo"
        :required="obrigatorios"
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

    <label :class="[ROTULO, marca('responsavel')]">
      {{ t('RAMON.PETICOES.RESPONSAVEL') }}
      <select v-model="form.responsavel_id" :class="SELECT">
        <option v-for="a in agentesOrdenados" :key="a.id" :value="a.id">
          {{ a.name }}
        </option>
      </select>
      <slot name="responsavel" />
    </label>

    <label :class="ROTULO">
      {{ t('RAMON.PETICOES.PRAZO') }}
      <input v-model="form.prazo" type="date" :class="CAMPO" />
    </label>

    <label :class="[ROTULO, marca('titulo')]">
      {{ t('RAMON.PETICOES.DESCRICAO') }}
      <input
        v-model="form.descricao"
        :class="CAMPO"
        :placeholder="t('RAMON.PETICOES.DESCRICAO_PLACEHOLDER')"
      />
    </label>
  </div>
</template>
