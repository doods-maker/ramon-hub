// Registro de ações (audit log): a frase em pt-BR de cada linha da trilha e o
// "antes → depois" formatado. O backend (Ramon::RegistroAcoes) já troca ids
// por nomes; aqui só se escolhe a frase e se formata o valor de cada campo.
import { formatBrl } from './currency';

const P = 'RAMON.REGISTRO';
const FUSO = 'America/Sao_Paulo';

export const TIPOS = ['lead', 'contato', 'conversa', 'dinheiro', 'acesso'];
export const TOM_DO_TIPO = {
  lead: 'blue',
  contato: 'iris',
  conversa: 'teal',
  dinheiro: 'amber',
  acesso: 'ruby',
};

// Campos que são número/data: vão em font-mono na tela.
const MONO = [
  'value',
  'meta',
  'won_at',
  'mes',
  'competencia',
  'data_nascimento',
  'cpf',
  'phone_number',
];
export const ehMono = campo => MONO.includes(campo);

const noFuso = (iso, opcoes) =>
  new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, ...opcoes }).format(
    new Date(iso)
  );

// "06/10/2026 14:32" no horário de Brasília.
export const quandoSp = iso =>
  noFuso(iso, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).replace(',', '');

const diaMesAno = data => data.split('-').reverse().join('/');
const mesAno = data => data.split('-').slice(0, 2).reverse().join('/');

const FORMATOS = {
  value: v => formatBrl(v),
  won_at: v => noFuso(v, { day: '2-digit', month: '2-digit', year: 'numeric' }),
  data_nascimento: v => diaMesAno(String(v)),
  mes: v => mesAno(String(v)),
  competencia: v => mesAno(String(v)),
  blocked: (v, t) => t(v ? `${P}.SIM` : `${P}.NAO`),
  rampa: (v, t) => t(v ? `${P}.SIM` : `${P}.NAO`),
  // enum do AccountUser: o audited guarda o inteiro (0 agente, 1 admin)
  role: (v, t) =>
    t(
      `${P}.PAPEL_CONTA.${v === 1 || v === 'administrator' ? 'ADMIN' : 'AGENTE'}`
    ),
  papel: (v, t) => t(`RAMON.EXTRATO.PAPEL.${v}`),
};

export const formatarValor = (campo, valor, t) => {
  if (valor === null || valor === undefined || valor === '') return '—';
  if (valor === '[anonimizado]') return t(`${P}.ANONIMIZADO`);
  const formato = FORMATOS[campo];
  return formato ? formato(valor, t) : String(valor);
};

export const rotuloCampo = (campo, t) => t(`${P}.CAMPO.${campo.toUpperCase()}`);

const tem = (r, campo) => Object.hasOwn(r.mudancas || {}, campo);
const valor = (r, campo, i) => r.mudancas?.[campo]?.[i];
const dePara = (r, campo, t) => ({
  de: formatarValor(campo, valor(r, campo, 0), t),
  para: formatarValor(campo, valor(r, campo, 1), t),
});

// Cada função devolve [chave da frase, parâmetros].
const LEAD = [
  ['lead_stage_id', 'LEAD_ETAPA'],
  ['sdr_id', 'LEAD_SDR'],
  ['closer_id', 'LEAD_CLOSER'],
  ['value', 'LEAD_VALOR'],
  ['lost_reason', 'LEAD_MOTIVO'],
];
const fraseLead = (r, t) => {
  if (r.acao === 'destroy') return ['LEAD_EXCLUIU'];
  const achado = LEAD.find(([campo]) => tem(r, campo));
  if (achado) return [achado[1], dePara(r, achado[0], t)];
  if (tem(r, 'won_at')) {
    return [valor(r, 'won_at', 1) ? 'LEAD_GANHO' : 'LEAD_DESFEZ_GANHO'];
  }
  return [tem(r, 'contact_id') ? 'LEAD_CONTATO' : 'LEAD_EDITOU'];
};

const ANONIMIZACAO = {
  anonimizado: 'CONTATO_ANONIMIZOU',
  anonimizado_em_massa: 'CONTATO_ANONIMIZOU_MASSA',
};
const fraseContato = (r, t) => {
  if (ANONIMIZACAO[r.comentario]) return [ANONIMIZACAO[r.comentario]];
  if (r.comentario?.startsWith('mesclado:')) return ['CONTATO_MESCLOU'];
  if (r.acao === 'destroy') return ['CONTATO_EXCLUIU'];
  const campos = Object.keys(r.mudancas || {});
  if (campos.length === 1 && campos[0] === 'blocked') {
    return [
      valor(r, 'blocked', 1) ? 'CONTATO_BLOQUEOU' : 'CONTATO_DESBLOQUEOU',
    ];
  }
  return [
    'CONTATO_EDITOU',
    { campos: campos.map(c => rotuloCampo(c, t)).join(', ') },
  ];
};

const fraseConversa = (r, t) => {
  if (r.acao === 'destroy') return ['CONVERSA_EXCLUIU'];
  const n = r.alvo?.conversa ?? '';
  if (!tem(r, 'assignee_id')) {
    return ['CONVERSA_TIME', { n, ...dePara(r, 'team_id', t) }];
  }
  const [antes, depois] = r.mudancas.assignee_id;
  const params = { n, ...dePara(r, 'assignee_id', t) };
  if (antes && depois) return ['CONVERSA_TRANSFERIU', params];
  return [depois ? 'CONVERSA_ATRIBUIU' : 'CONVERSA_DESATRIBUIU', params];
};

const fraseMeta = (r, t, pessoa) => {
  if (r.acao === 'create') {
    return [
      'META_LANCOU',
      {
        pessoa,
        mes: formatarValor('mes', valor(r, 'mes', 1), t),
        meta: valor(r, 'meta', 1),
      },
    ];
  }
  if (r.acao === 'destroy') return ['META_APAGOU', { pessoa }];
  if (tem(r, 'meta'))
    return ['META_MUDOU', { pessoa, ...dePara(r, 'meta', t) }];
  return ['META_EDITOU', { pessoa }];
};

const fraseExtrato = (r, t, pessoa) => {
  if (r.acao !== 'create') return ['EXTRATO_MEXEU', { pessoa }];
  return [
    'EXTRATO_FECHOU',
    {
      pessoa,
      papel: formatarValor('papel', valor(r, 'papel', 1), t),
      mes: formatarValor('competencia', valor(r, 'competencia', 1), t),
    },
  ];
};

const fraseAcesso = (r, t, pessoa) => {
  if (r.acao === 'create') {
    return [
      'ACESSO_ADICIONOU',
      { pessoa, papel: formatarValor('role', valor(r, 'role', 1), t) },
    ];
  }
  if (tem(r, 'role'))
    return ['ACESSO_PAPEL', { pessoa, ...dePara(r, 'role', t) }];
  return ['ACESSO_EDITOU', { pessoa }];
};

const POR_MODELO = {
  Lead: fraseLead,
  Contact: fraseContato,
  Conversation: fraseConversa,
  MetaComercial: fraseMeta,
  ExtratoFechado: fraseExtrato,
  AccountUser: fraseAcesso,
};

export const fraseDoRegistro = (r, t) => {
  const montar = POR_MODELO[r.modelo];
  const [chave, params = {}] = montar
    ? montar(r, t, r.alvo?.nome || '—')
    : ['EDITOU'];
  return t(`${P}.FRASE.${chave}`, params);
};

// Só a edição tem "antes → depois"; criação e exclusão contam na frase.
export const mudancasDoRegistro = (r, t) => {
  if (r.acao !== 'update') return [];
  return Object.entries(r.mudancas || {}).map(([campo, [antes, depois]]) => ({
    campo,
    rotulo: rotuloCampo(campo, t),
    antes: formatarValor(campo, antes, t),
    depois: formatarValor(campo, depois, t),
    mono: ehMono(campo),
  }));
};

export const quemFez = (r, t) => r.quem?.nome || t(`${P}.AUTOMACAO`);

// Para onde a linha leva: o dossiê do lead ou a Linha da Vida do contato.
export const rotaDoAlvo = alvo => {
  if (alvo?.lead_id) {
    return { name: 'ramon_lead_dossie', params: { leadId: alvo.lead_id } };
  }
  if (alvo?.contato_id) {
    return {
      name: 'ramon_linha_da_vida',
      params: { contactId: alvo.contato_id },
    };
  }
  return null;
};

export const linhaCsv = (r, t) => [
  quandoSp(r.quando),
  quemFez(r, t),
  t(`${P}.TIPO.${r.tipo}`),
  fraseDoRegistro(r, t),
  r.alvo?.nome || '',
  mudancasDoRegistro(r, t)
    .map(m => `${m.rotulo}: ${m.antes} → ${m.depois}`)
    .join('; '),
];

// CSV com ; e BOM (o Excel pt-BR abre direto), como o do Extrato.
export const paraCsv = linhas =>
  String.fromCharCode(0xfeff) +
  linhas
    .map(l => l.map(c => `"${String(c ?? '').replace(/"/g, '""')}"`).join(';'))
    .join('\n');
