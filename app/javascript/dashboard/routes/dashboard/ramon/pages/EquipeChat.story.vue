<script setup>
// Story das bolhas do chat Equipe (aprovação por print, claro/escuro): MessageList
// real, com os dados de exemplo do mockup. Sem rede; sem router: a rota entra por provide.
import { provide, reactive } from 'vue';
import { routeLocationKey } from 'vue-router';
import { createPinia, setActivePinia } from 'pinia';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useEquipeStore } from 'dashboard/stores/equipe';
import types from 'dashboard/store/mutation-types';
import MessageList from 'next/message/MessageList.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

provide(routeLocationKey, reactive({ query: {} }));

const CAIXA = 7;
const GRUPO = 43;
const DIRETA = 44;
const EU = 1;
const ADMIN_DE_FORA = 99;
const PESSOAS = {
  1: 'Eduardo',
  2: 'Gabriela',
  3: 'Thaís',
  4: 'Brenda',
};

const conversas = [
  { id: GRUPO, inbox_id: CAIXA, equipe_tipo: 'grupo', equipe_pessoas: [] },
  {
    id: DIRETA,
    inbox_id: CAIXA,
    equipe_tipo: '1a1',
    equipe_pessoas: [
      { id: EU, name: PESSOAS[1] },
      { id: 4, name: PESSOAS[4] },
    ],
  },
];

const store = useStore();
store.commit(`inboxes/${types.SET_INBOXES}`, [{ id: CAIXA, equipe: true }]);
store.commit(types.SET_ALL_CONVERSATION, conversas);
store.commit(types.SET_CURRENT_CHAT_WINDOW, conversas[0]);

setActivePinia(createPinia());
useEquipeStore().participantes[GRUPO] = [1, 2, 3, 4].map(id => ({
  id,
  name: PESSOAS[id],
}));

const hoje = (hora, minuto, diasAtras = 0) => {
  const data = new Date();
  data.setDate(data.getDate() - diasAtras);
  data.setHours(hora, minuto, 0, 0);
  return Math.floor(data.getTime() / 1000);
};

let proximoId = 1;
const mensagem = (conversa, autor, createdAt, content, extra = {}) => {
  proximoId += 1;
  return {
    id: extra.id ?? proximoId,
    content,
    inbox_id: CAIXA,
    conversation_id: conversa,
    message_type: 1,
    content_type: 'text',
    status: 'sent',
    content_attributes: {},
    created_at: createdAt,
    private: false,
    source_id: null,
    sender_id: autor,
    sender_type: 'User',
    sender: { id: autor, name: PESSOAS[autor], thumbnail: '', type: 'user' },
    ...extra,
  };
};

const grupo = [
  mensagem(GRUPO, 3, hoje(17, 40, 1), 'Saio às 18h hoje.'),
  mensagem(GRUPO, 3, hoje(17, 45, 1), 'Amanhã chego às 8h.'),
  mensagem(
    GRUPO,
    2,
    hoje(8, 12),
    'Bom dia, pessoal. Agenda de hoje já está no grupo do setor.'
  ),
  mensagem(
    GRUPO,
    EU,
    hoje(8, 20),
    'Obrigado, Gabriela. Quem cobre a recepção no almoço?',
    { id: 900 }
  ),
  mensagem(GRUPO, 3, hoje(8, 24), 'Eu cubro hoje.', {
    content_attributes: { in_reply_to: 900 },
  }),
  mensagem(GRUPO, 3, hoje(8, 25), null, {
    attachments: [
      {
        id: 1,
        message_id: 1,
        file_type: 'file',
        data_url: 'https://exemplo.invalid/escala-do-almoco.pdf',
        thumb_url: '',
        extension: 'pdf',
      },
    ],
  }),
  mensagem(
    GRUPO,
    EU,
    hoje(9, 2),
    '[@Brenda](mention://user/4/Brenda) consegue olhar os documentos da tarde?'
  ),
  mensagem(
    GRUPO,
    4,
    hoje(14, 32),
    '[@Eduardo](mention://user/1/Eduardo) o cliente das 14h chegou?'
  ),
  mensagem(
    GRUPO,
    4,
    hoje(14, 33),
    '[@todos](mention://todos/0/todos) reunião às 17h, sala do Dr. Ramon.'
  ),
];

const direta = [
  mensagem(DIRETA, 4, hoje(10, 5), 'Oi, Eduardo. Tem um minuto?'),
  mensagem(DIRETA, 4, hoje(10, 6), 'É sobre os documentos da tarde.'),
  mensagem(DIRETA, EU, hoje(10, 10), 'Pode falar.'),
];

const variantes = [
  { titulo: 'Grupo', mensagens: grupo, usuario: EU },
  { titulo: '1:1', mensagens: direta, usuario: EU },
  { titulo: 'Admin de fora, grupo', mensagens: grupo, usuario: ADMIN_DE_FORA },
  { titulo: 'Admin de fora, 1:1', mensagens: direta, usuario: ADMIN_DE_FORA },
];
</script>

<template>
  <Story
    title="Ramon/Equipe/Bolhas do chat"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant v-for="v in variantes" :key="v.titulo" :title="v.titulo">
      <MessageList
        class="flex flex-col py-4"
        :current-user-id="v.usuario"
        :messages="v.mensagens"
      />
    </Variant>
  </Story>
</template>
