<script setup>
import { ref, computed, watch } from 'vue';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import { extractFilenameFromUrl } from 'dashboard/helper/URLHelper';
import { TITULO, TOM } from '../../helpers/ui';

// "Arquivos recebidos" no item Docs: anexos da conversa do lead, agrupados
// por dia (mais recente primeiro, como a API devolve).
const props = defineProps({
  // id da conversa NA URL da API (display_id) — o mesmo que o dock usa;
  // hoje coincide com o conversation_id do lead em produção.
  conversationId: { type: [Number, String], required: true },
});
defineOptions({ name: 'ArquivosRecebidos' });

const arquivos = ref([]);
const carregando = ref(false);
const erro = ref(false);

// ponytail: só a 1ª página da API (100 anexos); paginar se algum lead passar disso.
const carregar = async id => {
  arquivos.value = [];
  carregando.value = true;
  erro.value = false;
  try {
    const { data } = await ConversationAPI.getAllAttachments(id);
    arquivos.value = data.payload || [];
  } catch (e) {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};
watch(() => props.conversationId, carregar, { immediate: true });

const TIPOS = {
  image: { icone: 'i-lucide-image', tom: TOM.teal, rotulo: 'IMAGE' },
  audio: { icone: 'i-lucide-mic', tom: TOM.iris, rotulo: 'AUDIO' },
  video: { icone: 'i-lucide-video', tom: TOM.amber, rotulo: 'VIDEO' },
  pdf: { icone: 'i-lucide-file-text', tom: TOM.ruby, rotulo: 'PDF' },
  file: { icone: 'i-lucide-file', tom: TOM.blue, rotulo: 'FILE' },
};

const nomeDe = arquivo => {
  const nome = extractFilenameFromUrl(arquivo.data_url) || '';
  try {
    return decodeURIComponent(nome);
  } catch (e) {
    return nome;
  }
};
const tipoDe = arquivo => {
  if (['image', 'audio', 'video'].includes(arquivo.file_type))
    return arquivo.file_type;
  const ext = (arquivo.extension || nomeDe(arquivo).split('.').pop() || '')
    .toLowerCase()
    .replace('.', '');
  return ext === 'pdf' ? 'pdf' : 'file';
};

const quando = arquivo => new Date(arquivo.created_at * 1000);
const dia = data => data.toLocaleDateString('pt-BR');
const hora = data =>
  data.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

const grupos = computed(() =>
  arquivos.value.reduce((acc, arquivo) => {
    const data = quando(arquivo);
    const chave = dia(data);
    const item = {
      id: arquivo.id,
      url: arquivo.data_url,
      nome: nomeDe(arquivo),
      tipo: TIPOS[tipoDe(arquivo)],
      quando: `${chave} ${hora(data)}`,
    };
    const ultimo = acc[acc.length - 1];
    if (ultimo?.dia === chave) ultimo.itens.push(item);
    else acc.push({ dia: chave, itens: [item] });
    return acc;
  }, [])
);
</script>

<template>
  <div data-testid="arquivos-recebidos" class="flex flex-col gap-2">
    <p :class="TITULO">{{ $t('RAMON.LEAD_PANEL.ARQUIVOS.TITLE') }}</p>
    <p v-if="carregando" class="text-xs text-n-slate-10">
      {{ $t('RAMON.LEAD_PANEL.ARQUIVOS.LOADING') }}
    </p>
    <p v-else-if="erro" class="text-xs text-n-ruby-11">
      {{ $t('RAMON.LEAD_PANEL.ARQUIVOS.ERROR') }}
    </p>
    <p
      v-else-if="!grupos.length"
      data-testid="arquivos-vazio"
      class="flex items-center gap-1.5 text-xs text-n-slate-10"
    >
      <span class="i-lucide-file-x size-3.5 shrink-0" />
      {{ $t('RAMON.LEAD_PANEL.ARQUIVOS.EMPTY') }}
    </p>
    <section
      v-for="grupo in grupos"
      :key="grupo.dia"
      data-testid="arquivos-dia"
    >
      <p class="mt-1 mb-1 text-xs font-medium text-n-slate-10">
        {{ grupo.dia }}
      </p>
      <div
        v-for="item in grupo.itens"
        :key="item.id"
        data-testid="arquivo"
        class="flex items-center gap-3 py-1.5"
      >
        <span
          data-testid="arquivo-tipo"
          class="flex items-center justify-center size-10 shrink-0 rounded-lg"
          :class="item.tipo.tom"
        >
          <span class="size-5" :class="item.tipo.icone" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="truncate text-sm font-medium text-n-slate-12">
            {{ item.nome }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{
              `${$t(`RAMON.LEAD_PANEL.ARQUIVOS.TIPO.${item.tipo.rotulo}`)} · ${item.quando}`
            }}
          </p>
        </div>
        <a
          :href="item.url"
          target="_blank"
          rel="noopener noreferrer"
          download
          data-testid="arquivo-baixar"
          :title="$t('RAMON.LEAD_PANEL.ARQUIVOS.DOWNLOAD')"
          :aria-label="$t('RAMON.LEAD_PANEL.ARQUIVOS.DOWNLOAD')"
          class="flex items-center justify-center size-8 shrink-0 rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
        >
          <span class="i-lucide-download size-4" />
        </a>
      </div>
    </section>
  </div>
</template>
