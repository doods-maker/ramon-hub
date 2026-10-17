// GET ramon_ia_atendimento de exemplo (Ramon::PerfilIa::Tela), para os specs do helper e da tela.
const GATILHOS = [
  'pediu_pessoa',
  'juridica',
  'outra_area',
  'fora_do_tema',
  'honorario_de_novo',
  'nao_le',
  'irritado',
  'tem_advogado',
  'desconto',
  'clausula',
];
const ACOES = [
  'fora_do_horario',
  'pedir_documentos',
  'desqualificar',
  'mover_etapa',
  'marcar_reuniao',
  'citar_honorario',
  'logistica',
  'contrato_zapsign',
];

export const PRONTOS = {
  cautelosa: {
    marcador: 'fase-qualificacao',
    gatilhos: GATILHOS,
    permissoes: {
      fora_do_horario: 'r',
      pedir_documentos: 's',
      desqualificar: 'r',
      mover_etapa: 'r',
      marcar_reuniao: 'r',
      citar_honorario: 'n',
      logistica: 'r',
      contrato_zapsign: 'n',
    },
  },
  equilibrada: {
    marcador: 'fase-reuniao-agendada',
    gatilhos: GATILHOS.filter(g => g !== 'nao_le'),
    permissoes: {
      fora_do_horario: 's',
      pedir_documentos: 's',
      desqualificar: 'r',
      mover_etapa: 's',
      marcar_reuniao: 's',
      citar_honorario: 'r',
      logistica: 's',
      contrato_zapsign: 'r',
    },
  },
  acelerada: {
    marcador: '_fim',
    gatilhos: [
      'pediu_pessoa',
      'juridica',
      'outra_area',
      'fora_do_tema',
      'desconto',
      'clausula',
    ],
    permissoes: Object.fromEntries(ACOES.map(a => [a, 's'])),
  },
};

export const ETAPAS = [
  { chave: 'fase-novo', nome: 'Novo' },
  { chave: 'fase-qualificacao', nome: 'Qualificação' },
  { chave: 'fase-reuniao-agendada', nome: 'Reunião agendada' },
  { chave: 'fase-reuniao-realizada', nome: 'Reunião realizada' },
  { chave: 'fase-negociacao', nome: 'Negociação' },
  { chave: 'fase-ultima-chance', nome: 'Última chance' },
];

const ETAPAS_DA_ACAO = {
  fora_do_horario: ['fase-novo'],
  pedir_documentos: ['fase-qualificacao'],
  desqualificar: ['fase-qualificacao'],
  mover_etapa: ['fase-qualificacao'],
  marcar_reuniao: ['fase-qualificacao'],
  citar_honorario: ['fase-qualificacao', 'fase-negociacao'],
  logistica: ['fase-reuniao-agendada'],
  contrato_zapsign: ['fase-negociacao'],
};

export const dados = () => ({
  prontos: PRONTOS,
  inicial: {
    base: 'cautelosa',
    marcador: '_inicio',
    permissoes: {
      logistica: 's',
      fora_do_horario: 's',
      citar_honorario: 'r',
      contrato_zapsign: 'r',
    },
  },
  acoes: ACOES.map(chave => ({
    chave,
    etapas: ETAPAS_DA_ACAO[chave],
    sem_nunca: ['fora_do_horario', 'logistica'].includes(chave),
  })),
  gatilhos: GATILHOS.map(chave => ({
    chave,
    nome: chave,
    pendente: ['irritado', 'tem_advogado', 'desconto', 'clausula'].includes(
      chave
    ),
  })),
  etapas: ETAPAS,
  padrao: { base: 'equilibrada' },
  teses: [
    { id: 1, nome: 'BPC/LOAS', cfg: null },
    { id: 2, nome: 'Auxílio-acidente', cfg: { base: 'acelerada' } },
  ],
  caixas: [{ id: 3, nome: 'Instagram Direct', cfg: null }],
  limites: {
    horario: {
      dias: [1, 2, 3, 4, 5],
      janelas: [
        ['08:30', '12:00'],
        ['13:30', '18:00'],
      ],
    },
    atraso: { min: 30, max: 180 },
    fluxo_ia_dia: 200,
    retomadas_dia: 15,
    retomada_intervalo_dias: 5,
    teto_usd: null,
    agente_dia: 30,
  },
});
