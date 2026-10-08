// Quadro de fluxos (B2): catálogo do que o motor da B1 executa
// (Ramon::Fluxos::Grafo::GATILHOS / TIPOS_PASSO) e as operações puras do
// quadro. Desenho salvo = { nos: [{id, tipo, config, posicao}], setas: [{de, saida, para}] }.

export const GATILHOS = [
  {
    tipo: 'conversa_criada',
    icone: 'i-lucide-message-square-plus',
    alvo: 'conversa',
  },
  {
    tipo: 'mensagem_recebida',
    icone: 'i-lucide-message-square',
    alvo: 'conversa',
  },
  {
    tipo: 'conversa_resolvida',
    icone: 'i-lucide-circle-check-big',
    alvo: 'conversa',
  },
  { tipo: 'conversa_reaberta', icone: 'i-lucide-rotate-ccw', alvo: 'conversa' },
  {
    tipo: 'conversa_atribuida',
    icone: 'i-lucide-user-round-check',
    alvo: 'conversa',
  },
  { tipo: 'lead_criado', icone: 'i-lucide-user-plus', alvo: 'lead' },
  {
    tipo: 'lead_mudou_etapa',
    icone: 'i-lucide-git-commit-horizontal',
    alvo: 'lead',
  },
  { tipo: 'lead_ganho', icone: 'i-lucide-trophy', alvo: 'lead' },
  { tipo: 'lead_perdido', icone: 'i-lucide-circle-x', alvo: 'lead' },
  { tipo: 'reuniao_marcada', icone: 'i-lucide-calendar-check', alvo: 'lead' },
  { tipo: 'reuniao_cancelada', icone: 'i-lucide-calendar-x', alvo: 'lead' },
  { tipo: 'reuniao_na_agenda', icone: 'i-lucide-calendar-clock', alvo: 'lead' },
  { tipo: 'contrato_assinado', icone: 'i-lucide-file-signature', alvo: 'lead' },
  { tipo: 'contrato_recusado', icone: 'i-lucide-file-x', alvo: 'lead' },
  { tipo: 'documento_recebido', icone: 'i-lucide-file-input', alvo: 'lead' },
  { tipo: 'evento_advbox', icone: 'i-lucide-scale', alvo: 'lead' },
  { tipo: 'lead_parado', icone: 'i-lucide-timer-off', alvo: 'lead' },
  { tipo: 'relogio', icone: 'i-lucide-alarm-clock', alvo: 'lead' },
  { tipo: 'manual', icone: 'i-lucide-hand', alvo: 'lead' },
  { tipo: 'horario_conta', icone: 'i-lucide-building-2', alvo: 'conta' },
  { tipo: 'nota_escrita', icone: 'i-lucide-sticky-note', alvo: 'conversa' },
];
export const gatilhoInfo = tipo => GATILHOS.find(g => g.tipo === tipo);

// tom = chave do TOM do kit (ramon/helpers/ui.js); rascunho = selo "sai como rascunho"
export const PASSOS = {
  gatilho: { grupo: null, icone: 'i-lucide-zap', tom: 'blue' },
  se: { grupo: 'CONDICAO', icone: 'i-lucide-split', tom: 'amber' },
  escolha: { grupo: 'CONDICAO', icone: 'i-lucide-git-fork', tom: 'amber' },
  rascunho_texto: {
    grupo: 'MENSAGEM',
    icone: 'i-lucide-file-pen-line',
    tom: 'slate',
    rascunho: true,
  },
  acao_chatwoot: { grupo: 'CONVERSA', icone: 'i-lucide-tag', tom: 'slate' },
  nota_privada: {
    grupo: 'CONVERSA',
    icone: 'i-lucide-sticky-note',
    tom: 'slate',
  },
  mover_etapa: { grupo: 'LEAD', icone: 'i-lucide-move-right', tom: 'slate' },
  criar_tarefa: { grupo: 'LEAD', icone: 'i-lucide-list-todo', tom: 'slate' },
  avisar_sino: { grupo: 'AVISAR', icone: 'i-lucide-bell', tom: 'slate' },
  avisar_push: { grupo: 'AVISAR', icone: 'i-lucide-smartphone', tom: 'slate' },
  perguntar_ia: {
    grupo: 'IA',
    icone: 'i-lucide-message-circle-question',
    tom: 'amber',
  },
  rascunho_ia: {
    grupo: 'IA',
    icone: 'i-lucide-sparkles',
    tom: 'slate',
    rascunho: true,
  },
  rodar_skill: { grupo: 'IA', icone: 'i-lucide-wand-sparkles', tom: 'slate' },
  trocar_responsavel: {
    grupo: 'LEAD',
    icone: 'i-lucide-user-round-cog',
    tom: 'slate',
  },
  preencher_campo: {
    grupo: 'LEAD',
    icone: 'i-lucide-text-cursor-input',
    tom: 'slate',
  },
  registrar_atividade: {
    grupo: 'LEAD',
    icone: 'i-lucide-history',
    tom: 'slate',
  },
  apagar_reuniao: {
    grupo: 'LEAD',
    icone: 'i-lucide-calendar-x',
    tom: 'slate',
  },
  rotina: { grupo: 'LEAD', icone: 'i-lucide-package-check', tom: 'slate' },
  registrar_retomada: {
    grupo: 'LEAD',
    icone: 'i-lucide-repeat',
    tom: 'slate',
  },
  advbox: { grupo: 'INTEGRACOES', icone: 'i-lucide-scale', tom: 'slate' },
  webhook: { grupo: 'INTEGRACOES', icone: 'i-lucide-webhook', tom: 'slate' },
  esperar: { grupo: 'CONTROLE', icone: 'i-lucide-hourglass', tom: 'slate' },
  parar: { grupo: 'CONTROLE', icone: 'i-lucide-octagon-x', tom: 'slate' },
};
export const TIPOS_PASSO = Object.keys(PASSOS).filter(t => t !== 'gatilho');

// "+ Adicionar passo": tudo que o motor roda (B1 + B2b).
export const PALETA = [
  {
    grupo: 'CONDICAO',
    itens: [
      { chave: 'se', tipo: 'se' },
      { chave: 'escolha', tipo: 'escolha' },
    ],
  },
  {
    grupo: 'MENSAGEM',
    itens: [{ chave: 'rascunho_texto', tipo: 'rascunho_texto' }],
  },
  {
    grupo: 'CONVERSA',
    itens: [
      {
        chave: 'etiqueta',
        tipo: 'acao_chatwoot',
        config: { acoes: [{ action_name: 'add_label', action_params: [] }] },
      },
      {
        chave: 'atribuir',
        tipo: 'acao_chatwoot',
        config: { acoes: [{ action_name: 'assign_agent', action_params: [] }] },
      },
      { chave: 'acao_chatwoot', tipo: 'acao_chatwoot' },
      { chave: 'nota_privada', tipo: 'nota_privada' },
    ],
  },
  {
    grupo: 'LEAD',
    itens: [
      { chave: 'mover_etapa', tipo: 'mover_etapa' },
      { chave: 'criar_tarefa', tipo: 'criar_tarefa' },
      { chave: 'trocar_responsavel', tipo: 'trocar_responsavel' },
      { chave: 'preencher_campo', tipo: 'preencher_campo' },
      { chave: 'registrar_atividade', tipo: 'registrar_atividade' },
      { chave: 'apagar_reuniao', tipo: 'apagar_reuniao' },
      { chave: 'registrar_retomada', tipo: 'registrar_retomada' },
      { chave: 'rotina', tipo: 'rotina' },
    ],
  },
  {
    grupo: 'IA',
    itens: [
      { chave: 'perguntar_ia', tipo: 'perguntar_ia' },
      { chave: 'rascunho_ia', tipo: 'rascunho_ia' },
      { chave: 'rodar_skill', tipo: 'rodar_skill' },
    ],
  },
  {
    grupo: 'INTEGRACOES',
    itens: [
      { chave: 'advbox', tipo: 'advbox' },
      { chave: 'webhook', tipo: 'webhook' },
    ],
  },
  {
    grupo: 'AVISAR',
    itens: [
      { chave: 'avisar_sino', tipo: 'avisar_sino' },
      { chave: 'avisar_push', tipo: 'avisar_push' },
    ],
  },
  {
    grupo: 'CONTROLE',
    itens: [
      { chave: 'esperar', tipo: 'esperar' },
      { chave: 'parar', tipo: 'parar' },
    ],
  },
];

// Ações nativas editáveis na tela (parametro = que formulário abre).
// Mensagem ao cliente/transcript/webhook nunca (Grafo::PROIBIDAS_CHATWOOT);
// nota privada e "mudar status" já têm passo próprio / resolver-abrir-pendente.
export const ACOES_CHATWOOT = [
  { nome: 'add_label', parametro: 'etiquetas' },
  { nome: 'remove_label', parametro: 'etiquetas' },
  { nome: 'assign_agent', parametro: 'pessoa' },
  { nome: 'remove_assigned_agent', parametro: null },
  { nome: 'assign_team', parametro: 'time' },
  { nome: 'remove_assigned_team', parametro: null },
  { nome: 'change_priority', parametro: 'prioridade' },
  { nome: 'resolve_conversation', parametro: null },
  { nome: 'open_conversation', parametro: null },
  { nome: 'pending_conversation', parametro: null },
  { nome: 'snooze_conversation', parametro: null },
  { nome: 'mute_conversation', parametro: null },
  { nome: 'send_email_to_team', parametro: 'email_time' },
];
// = Grafo.permitidas_chatwoot (o que a regra nativa aceita, menos as proibidas)
export const CHATWOOT_PERMITIDAS = [
  ...ACOES_CHATWOOT.map(a => a.nome),
  'change_status',
  'add_private_note',
  'add_sla',
];
export const PRIORIDADES = ['urgent', 'high', 'medium', 'low', 'nil'];
// = handlers do Ramon::AdvboxEventProcessor::RULES (chave do filtro do gatilho evento_advbox)
export const REGRAS_ADVBOX = [
  'contrato_fechado',
  'requerimento_protocolado',
  'indeferimento',
  'decisao',
  'exigencia',
  'reativacao_futura',
  'exito',
  'marco',
  'concessao',
  'arquivado',
];
// Fluxos do sistema (B3, db/seeds/ramon/fluxos/sistema/*.json): grupos da aba "Do sistema"
// na ordem da tela, e o selo de quem sai para fora sem uma pessoa no meio.
export const GRUPOS_SISTEMA = [
  'leads_conversas',
  'contrato_documentos',
  'painel_cliente',
  'rotinas_relatorios',
  'instagram',
];
export const ALCANCES = ['fala_com_cliente', 'publica'];
export const PAPEIS = ['sdr', 'closer']; // Ramon::Papeis::COLUNA

// Ramon::Fluxos::Contexto#dados — o que o {chave} dos textos e as condições enxergam.
export const VARIAVEIS = [
  'nome',
  'nome_completo',
  'telefone',
  'responsavel',
  'etapa',
  'tese',
  'origem',
  'canal',
  'prioridade',
  'caixa',
  'status',
  'texto',
  'documentos_faltantes',
  'resposta_ia',
  'quando',
  'regra',
  'documento',
  'evento',
  'titulo',
  'titulo_tarefa',
  'resumo',
  'resumo_antes',
  'primeiro_nome',
  'hoje',
  'sla_minutos',
  'tentativa',
  'dias_parado',
];
export const CAMPOS = [
  'etapa',
  'tese',
  'origem',
  'canal',
  'prioridade',
  'responsavel',
  'caixa',
  'status',
  'etiquetas',
  'valor',
  'texto',
  'nome',
  'telefone',
  'documentos_completos',
  'regra',
  'evento',
  'reuniao_de_pe',
  'horario_passou',
  'primeira_resposta',
];
export const OPERADORES = [
  'igual',
  'diferente',
  'contem',
  'nao_contem',
  'maior',
  'menor',
  'existe',
  'vazio',
  'em_horario_comercial',
];
export const SEM_VALOR = ['existe', 'vazio', 'em_horario_comercial'];
export const TIPOS_TAREFA = ['follow_up', 'document', 'meeting', 'other']; // LeadTask::KINDS
// = Ramon::Fluxos::Passos::Lead::TIPOS_ATIVIDADE (as de reunião aparecem como as do código)
export const TIPOS_ATIVIDADE = [
  'fluxo',
  'meeting_scheduled',
  'meeting_rescheduled',
  'meeting_cancelled',
  'advbox_contrato_fechado',
  'advbox_inss_protocolado',
  'advbox_indeferido',
  'advbox_decisao',
  'advbox_exigencia',
  'advbox_reativacao_futura',
  'advbox_exito',
  'advbox_marco',
  'advbox_concessao',
  'advbox_arquivado',
];
// Rotinas prontas do hub (= Ramon::Fluxos::Rotinas): as 5 da B4.4/B4.5 (de lead) + as de cada plano B5, um arquivo por
// plano em ./rotinas/<plano>.js = [{ chave, alvo: 'conta' | 'lead' | 'conversa' }] (= ROTINAS do módulo do plano).
const PLANOS = import.meta.glob('./rotinas/*.js', {
  eager: true,
  import: 'default',
});
export const ROTINAS_INFO = [
  ...[
    'dossie_passagem',
    'pesquisa_nps',
    'pesquisa_nps_exito',
    'abrir_caso_advbox',
    'concluir_tarefas',
  ].map(chave => ({ chave, alvo: 'lead' })),
  ...Object.keys(PLANOS)
    .sort()
    .flatMap(arquivo => PLANOS[arquivo]),
];
export const ROTINAS = ROTINAS_INFO.map(r => r.chave);
export const rotinaAlvo = chave =>
  ROTINAS_INFO.find(r => r.chave === chave)?.alvo;
// o select do passo: no Horário da conta só as da conta; nos demais gatilhos, só as de lead/conversa
export const rotinasPara = alvo =>
  ROTINAS_INFO.filter(r => (r.alvo === 'conta') === (alvo === 'conta')).map(
    r => r.chave
  );
// = Ramon::Fluxos::HorarioConta::PASSOS — o que roda sem lead (gatilho Horário da conta)
export const PASSOS_CONTA = [
  'se',
  'escolha',
  'esperar',
  'parar',
  'avisar_push',
  'rotina',
];
export const UNIDADES = ['minutos', 'horas', 'dias'];
// Ramon::Fluxos::Horario (B4.2): janela padrão quando o passo não tem a sua (0 = domingo)
export const JANELA_PADRAO = { dias: [1, 2, 3, 4, 5], inicio: 8, fim: 18 };

const copia = obj => JSON.parse(JSON.stringify(obj));

const CONFIG_INICIAL = {
  se: {
    juncao: 'e',
    condicoes: [{ campo: 'etapa', operador: 'igual', valor: '' }],
  },
  escolha: {
    campo: 'tese',
    casos: [
      { chave: 'c1', rotulo: '', valores: [] },
      { chave: 'c2', rotulo: '', valores: [] },
    ],
  },
  esperar: { quantidade: 1, unidade: 'dias' },
  criar_tarefa: { titulo: '', tipo: 'other', prazo_dias: 1 },
  acao_chatwoot: { acoes: [] },
  advbox: { acao: 'tarefa', prazo_dias: 1 },
  trocar_responsavel: { papel: 'closer' },
};
export const configInicial = tipo => copia(CONFIG_INICIAL[tipo] || {});

export const saidasDe = (tipo, config = {}) => {
  if (['parar', 'webhook'].includes(tipo)) return [];
  if (['se', 'perguntar_ia'].includes(tipo)) return ['sim', 'nao'];
  if (tipo === 'escolha')
    return [...(config.casos || []).map(c => c.chave), 'outro'];
  return ['s'];
};

export const idSeta = (de, saida) => `${de}:${saida}`;

const numero = id => Number(String(id).replace(/\D/g, '')) || 0;
export const novaChave = casos =>
  `c${Math.max(0, ...casos.map(c => numero(c.chave))) + 1}`;
export const proximoId = nodes =>
  `n${Math.max(0, ...nodes.map(n => numero(n.id))) + 1}`;

export const paraVueFlow = ({ nos = [], setas = [] } = {}) => ({
  nodes: nos.map(no => ({
    id: no.id,
    type: 'passo',
    position: { x: no.posicao?.x ?? 0, y: no.posicao?.y ?? 0 },
    data: { tipo: no.tipo, config: no.config ?? {} },
    deletable: no.tipo !== 'gatilho',
  })),
  edges: setas.map(seta => ({
    id: idSeta(seta.de, seta.saida),
    source: seta.de,
    sourceHandle: seta.saida,
    target: seta.para,
    targetHandle: 'e',
  })),
});

export const deVueFlow = (nodes, edges) => {
  const saidas = Object.fromEntries(
    nodes.map(n => [n.id, saidasDe(n.data.tipo, n.data.config)])
  );
  return {
    nos: nodes.map(n => ({
      id: n.id,
      tipo: n.data.tipo,
      config: n.data.config,
      posicao: { x: Math.round(n.position.x), y: Math.round(n.position.y) },
    })),
    // porta que sumiu (caso apagado do escolha) leva a seta junto
    setas: edges
      .filter(e => saidas[e.source]?.includes(e.sourceHandle))
      .map(e => ({ de: e.source, saida: e.sourceHandle, para: e.target })),
  };
};

export const alcancaveis = (setas, inicio) => {
  const vistos = new Set();
  const fila = [inicio];
  while (fila.length) {
    const id = fila.shift();
    if (!vistos.has(id)) {
      vistos.add(id);
      fila.push(...setas.filter(s => s.de === id).map(s => s.para));
    }
  }
  return vistos;
};

// Nova seta: troca a que já saía da mesma porta; recusa o próprio passo e laço (D2: sem laços).
export const ligar = (edges, { source, sourceHandle, target }) => {
  if (source === target) return null;
  const outras = edges.filter(
    e => !(e.source === source && e.sourceHandle === sourceHandle)
  );
  const setas = outras.map(e => ({ de: e.source, para: e.target }));
  if (alcancaveis(setas, target).has(source)) return null;
  return [
    ...outras,
    {
      id: idSeta(source, sourceHandle),
      source,
      sourceHandle,
      target,
      targetHandle: 'e',
    },
  ];
};

const ESPACO_Y = 140;

export const adicionarPasso = (
  nodes,
  edges,
  { tipo, config },
  selecionadoId
) => {
  const id = proximoId(nodes);
  const pai = nodes.find(n => n.id === selecionadoId);
  const base =
    pai ||
    nodes.reduce((a, n) => (n.position.y > a.position.y ? n : a), nodes[0]);
  const no = {
    id,
    type: 'passo',
    // quadro vazio (sem nem o gatilho): entra na origem
    position: base
      ? { x: base.position.x, y: base.position.y + ESPACO_Y }
      : { x: 0, y: 0 },
    data: { tipo, config: config ? copia(config) : configInicial(tipo) },
    deletable: true,
  };
  const livre =
    pai &&
    saidasDe(pai.data.tipo, pai.data.config).find(
      s => !edges.some(e => e.source === pai.id && e.sourceHandle === s)
    );
  return {
    nodes: [...nodes, no],
    edges: livre
      ? [
          ...edges,
          {
            id: idSeta(pai.id, livre),
            source: pai.id,
            sourceHandle: livre,
            target: id,
            targetHandle: 'e',
          },
        ]
      : edges,
    id,
  };
};

export const duplicarPasso = (nodes, id) => {
  const original = nodes.find(n => n.id === id);
  // o gatilho é único no fluxo: não se duplica
  if (!original || original.data.tipo === 'gatilho') return { nodes, id };
  const novoId = proximoId(nodes);
  const novo = {
    id: novoId,
    type: 'passo',
    position: { x: original.position.x + 40, y: original.position.y + 40 },
    data: copia(original.data),
    deletable: true,
  };
  return { nodes: [...nodes, novo], id: novoId };
};

export const trocarConfig = (nodes, id, config) =>
  nodes.map(n => (n.id === id ? { ...n, data: { ...n.data, config } } : n));

// Caso apagado do escolha: a seta da porta que sumiu sai do quadro na hora.
export const podarSetas = (edges, no) => {
  const s = saidasDe(no.data.tipo, no.data.config);
  return edges.filter(e => e.source !== no.id || s.includes(e.sourceHandle));
};

// Mensagens do Grafo#erros que apontam passo: "Passo n3: …", "Passo n3 (Se) …", "Passo n3 não …".
export const idDoErro = msg => /^Passo (\S+?)(?::|\s|$)/.exec(msg)?.[1] ?? null;

export const caminhoAceso = (trilha = [], { setas = [] } = {}) => {
  const ids = new Set();
  trilha.forEach((linha, i) => {
    const prox = trilha[i + 1];
    const seta =
      prox &&
      setas.find(
        s => s.de === linha.no && s.saida === linha.saida && s.para === prox.no
      );
    if (seta) ids.add(idSeta(seta.de, seta.saida));
  });
  return { nos: new Set(trilha.map(l => l.no)), setas: ids };
};

const FORMATO = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
});
export const quando = iso =>
  iso ? FORMATO.format(new Date(iso)).replace(',', '') : '';
