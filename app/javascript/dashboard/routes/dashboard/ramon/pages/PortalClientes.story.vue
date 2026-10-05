<script setup>
// Story do Painel do cliente (lado do escritório) — aprovação visual por
// print, claro/escuro. Sem rede: window.axios responde com dados FICTÍCIOS por
// URL. As variantes "aberto", "busca" e "senha" clicam na tela depois de
// montar (pelo texto do botão, pra servir no código antigo e no novo).
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import PortalClientes from './PortalClientes.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();

const PROCESSOS_MARIA = [
  {
    id: 501,
    numero: '5003421-18.2025.4.04.7207',
    tipo: 'Auxílio-acidente',
    etapa: 'PERÍCIA AGENDADA',
    fase: 'JUDICIAL',
    cliente_ve: 'Perícia agendada',
    etapa_interna: false,
    documentos: [
      { item: 'Laudo do ortopedista', enviado: true, enviado_em: diasAtras(0) },
      { item: 'Comprovante de residência', enviado: false },
      { item: 'Exame de imagem do joelho', enviado: false },
    ],
  },
  {
    id: 502,
    numero: 'NB 712.345.678-9',
    tipo: 'Aposentadoria por idade',
    etapa: 'NEGADO / AVISAR CLIENTE',
    fase: 'ADMINISTRATIVO',
    cliente_ve: 'Pedido protocolado no INSS',
    etapa_interna: true,
    documentos: [],
  },
];

const CLIENTES = [
  {
    id: 1,
    nome: 'Ana Paula Martins',
    advbox_customer_id: 9101,
    cpf: '123.456.789-09',
    email: 'ana.martins@exemplo.com.br',
    convidado_em: diasAtras(20),
    termos_aceitos_em: diasAtras(19),
    sincronizado_em: diasAtras(0),
    ultimo_acesso_em: diasAtras(1),
    dias_acesso: 6,
    processos: [],
    envios_count: 3,
    assinaturas_pendentes: 0,
  },
  {
    id: 2,
    nome: 'Carlos Eduardo Lima',
    advbox_customer_id: 9102,
    cpf: '987.654.321-00',
    email: null,
    convidado_em: diasAtras(3),
    termos_aceitos_em: null,
    sincronizado_em: diasAtras(3),
    ultimo_acesso_em: null,
    dias_acesso: 0,
    processos: [],
    envios_count: 0,
    assinaturas_pendentes: 0,
  },
  {
    id: 3,
    nome: 'José Ribeiro da Silva',
    advbox_customer_id: 9103,
    cpf: '456.789.123-45',
    email: 'jose.ribeiro@exemplo.com.br',
    convidado_em: null,
    termos_aceitos_em: null,
    sincronizado_em: diasAtras(8),
    ultimo_acesso_em: null,
    dias_acesso: 0,
    processos: [],
    envios_count: 0,
    assinaturas_pendentes: 0,
  },
  {
    id: 4,
    nome: 'Maria Aparecida Souza',
    advbox_customer_id: 9104,
    cpf: '321.654.987-10',
    email: 'maria.souza@exemplo.com.br',
    convidado_em: diasAtras(35),
    termos_aceitos_em: diasAtras(34),
    sincronizado_em: diasAtras(0),
    ultimo_acesso_em: diasAtras(0),
    dias_acesso: 14,
    processos: PROCESSOS_MARIA,
    envios_count: 7,
    assinaturas_pendentes: 1,
  },
  {
    id: 5,
    nome: 'Pedro Henrique Alves',
    advbox_customer_id: 9105,
    cpf: '654.987.321-55',
    email: 'pedro.alves@exemplo.com.br',
    convidado_em: diasAtras(60),
    termos_aceitos_em: diasAtras(59),
    sincronizado_em: diasAtras(0),
    ultimo_acesso_em: diasAtras(41),
    suspenso_em: diasAtras(2),
    dias_acesso: 3,
    processos: [],
    envios_count: 1,
    assinaturas_pendentes: 0,
  },
];

const MARIA = {
  ...CLIENTES[3],
  recados: {
    501: 'Perícia marcada para 14/10 às 9h no fórum de Tubarão. Leve os exames.',
  },
  envios: [
    {
      id: 71,
      item: 'Laudo do ortopedista',
      drive_file_id: null,
      drive_url: null,
      created_at: diasAtras(0),
    },
    {
      id: 70,
      item: 'Carteira de trabalho',
      drive_file_id: 'drv-70',
      drive_url: 'https://drive.google.com/file/d/drv-70',
      created_at: diasAtras(6),
    },
    {
      id: 69,
      item: 'RG e CPF',
      drive_file_id: 'drv-69',
      drive_url: 'https://drive.google.com/file/d/drv-69',
      created_at: diasAtras(12),
    },
  ],
  eventos: [
    {
      id: 5,
      acao: 'salvou_recado',
      user_name: 'Gabriela Matos',
      created_at: diasAtras(0),
    },
    {
      id: 4,
      acao: 'enviou_assinatura',
      detalhe: 'Procuração',
      user_name: 'Eduardo Schlata',
      created_at: diasAtras(2),
    },
    {
      id: 3,
      acao: 'nova_senha',
      user_name: 'Recepção — Juliana',
      created_at: diasAtras(20),
    },
    {
      id: 1,
      acao: 'convidou',
      user_name: 'Eduardo Schlata',
      created_at: diasAtras(35),
    },
  ],
  assinaturas: [
    {
      id: 31,
      nome: 'Procuração',
      status: 'pendente',
      created_at: diasAtras(2),
    },
    {
      id: 30,
      nome: 'Contrato de honorários',
      status: 'signed',
      created_at: diasAtras(30),
    },
  ],
};

const mensagemPronta = (nome, cpf, senha) =>
  `Olá, ${nome}! Aqui é do escritório Ramon Antonio Advogados.
Agora você pode acompanhar o seu caso pelo celular, no Painel do Cliente.

Para entrar:
1. Abra: https://cliente.ramonantonio.adv.br
2. Digite o seu CPF: ${cpf}
3. Digite esta senha provisória: ${senha}

Depois de entrar, você pode trocar a senha por outra fácil de lembrar (só números). Guarde esta senha e não passe para ninguém.
Qualquer dúvida, é só responder esta mensagem.`;

const METRICAS = {
  convidados: 3,
  entraram: 2,
  voltaram: 2,
  enviaram: 2,
  assinaram: 1,
  docs_pedidos: 2,
  docs_enviados: 10,
};

const API = {
  portal_clientes: {
    payload: CLIENTES,
    metricas: METRICAS,
    email_configurado: true,
    permissoes: { gerir_acesso: true, excluir: true },
  },
  'portal_clientes/4': MARIA,
  // Texto da mensagem = proposta do Ramon::PortalConvite::MENSAGEM (gate do Eduardo).
  'portal_clientes/2/convidar': {
    ...CLIENTES[1],
    senha_provisoria: '482913',
    email: { status: 'sem_email' },
    mensagem: mensagemPronta('Carlos', '987.654.321-00', '482913'),
    whatsapp_url: 'https://wa.me/5548999112233?text=Ol%C3%A1',
  },
  'portal_clientes/1/convidar': {
    ...CLIENTES[0],
    senha_provisoria: '705126',
    email: { status: 'sem_servidor', para: 'ana.martins@exemplo.com.br' },
    mensagem: mensagemPronta('Ana', '123.456.789-09', '705126'),
    whatsapp_url: 'https://wa.me/5548997012233?text=Ol%C3%A1',
  },
  'portal_clientes/4/convidar': {
    ...CLIENTES[3],
    senha_provisoria: '390557',
    email: { status: 'enviado', para: 'maria.souza@exemplo.com.br' },
    mensagem: null,
    whatsapp_url: null,
  },
  'ramon_calculos/advbox_customers': {
    payload: [
      {
        id: 9001,
        name: 'Rosângela Pereira Costa',
        identification: '741.852.963-00',
        email: 'Rosangela.Costa@exemplo.com.br',
        cellphone: '(48) 99812-3456',
      },
      {
        id: 9101,
        name: 'Ana Paula Martins',
        identification: '123.456.789-09',
        email: 'ana.martins@exemplo.com.br',
        cellphone: '(48) 99701-2233',
      },
      {
        id: 9002,
        name: 'Rosa Maria Fontana',
        identification: '852.963.741-11',
        email: null,
        cellphone: '(48) 99654-0987',
      },
    ],
  },
  zapsign_templates: [
    { token: 'tpl-1', name: 'Procuração INSS' },
    { token: 'tpl-2', name: 'Contrato de honorários' },
  ],
};

let respostas = API;
let falhar = false;
const responder = async url => {
  if (falhar) throw new Error('offline');
  const path = url
    .replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '')
    .replace(/^leads\//, '');
  return { data: respostas[path] ?? {} };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });

// Clica no botão cujo texto contém `texto` (o n-ésimo, se houver vários).
const clicar = (texto, n = 0) =>
  [...document.querySelectorAll('button')]
    .filter(b => b.textContent.includes(texto))
    [n]?.click();
const depois = (ms, fn) => () => setTimeout(fn, ms);

const vazio = () => {
  respostas = {
    ...API,
    portal_clientes: {
      payload: [],
      metricas: Object.fromEntries(Object.keys(METRICAS).map(k => [k, 0])),
    },
  };
};
const erro = () => {
  falhar = true;
};
const aberto = depois(1500, () => clicar('Maria Aparecida'));
const senha = depois(1500, () => {
  clicar('Nova senha provisória', 1);
  setTimeout(() => clicar('Gerar senha nova'), 300);
});
const novaSenha = n =>
  depois(1500, () => {
    clicar('Nova senha provisória', n);
    setTimeout(() => clicar('Gerar senha nova'), 300);
  });
// Abre a Maria e digita um recado novo no 2º processo (prévia antes de salvar).
const recadoPrevia = depois(1500, () => {
  clicar('Maria Aparecida');
  setTimeout(() => {
    const campo = document.querySelectorAll('textarea')[1];
    campo.value =
      'Dona Maria, precisamos conversar sobre o resultado do pedido no INSS.\nPode nos ligar amanhã de manhã?';
    campo.dispatchEvent(new Event('input'));
  }, 800);
});
const clicarEm = texto => depois(1500, () => clicar(texto));
const confirmarSenha = depois(1500, () => clicar('Nova senha provisória', 0));
const busca = depois(1500, () => {
  const campo = document.querySelector('input[type="search"]');
  campo.value = 'Ros';
  campo.dispatchEvent(new Event('input'));
  setTimeout(() => {
    clicar('Buscar');
    setTimeout(() => clicar('Convidar'), 500);
  }, 300);
});
</script>

<template>
  <Story title="Ramon/Painel do cliente" :layout="{ type: 'single' }">
    <Variant title="Lista">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="Aberto" :init-state="aberto">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="Busca" :init-state="busca">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="Senha" :init-state="senha">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="PC1 confirmar senha" :init-state="confirmarSenha">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="PC2 sem servidor" :init-state="novaSenha(0)">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="PC2 email enviado" :init-state="novaSenha(3)">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="PC3 suspender" :init-state="clicarEm('Suspender acesso')">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="PC3 excluir" :init-state="clicarEm('Excluir')">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="PC5 recado previa" :init-state="recadoPrevia">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="Vazio" :init-state="vazio">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
    <Variant title="Erro" :init-state="erro">
      <div class="h-screen"><PortalClientes /></div>
    </Variant>
  </Story>
</template>
