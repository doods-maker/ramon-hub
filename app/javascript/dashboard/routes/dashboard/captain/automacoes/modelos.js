// Modelos do "Novo fluxo" (B2): só passos que a B1 executa. Textos ao cliente
// saem como RASCUNHO e passam pelo Eduardo antes de qualquer fluxo publicado.
const no = (id, tipo, config, x, y) => ({
  id,
  tipo,
  config,
  posicao: { x, y },
});
const seta = (de, saida, para) => ({ de, saida, para });

export const MODELOS = [
  {
    chave: 'branco',
    icone: 'i-lucide-plus',
    desenho: {
      nos: [no('n1', 'gatilho', { tipo: 'manual' }, 0, 0)],
      setas: [],
    },
  },
  {
    chave: 'pos_contrato',
    icone: 'i-lucide-file-check',
    limite_dia: 20,
    desenho: {
      nos: [
        no(
          'n1',
          'gatilho',
          { tipo: 'lead_mudou_etapa', para_etapa_ids: [] },
          0,
          0
        ),
        no(
          'n2',
          'rascunho_texto',
          {
            rotulo: 'Boas-vindas',
            texto:
              'Olá, {nome}! Seja bem-vindo(a). Para darmos andamento ao seu caso, vamos precisar de alguns documentos — já te explico quais.',
          },
          0,
          140
        ),
        no(
          'n3',
          'criar_tarefa',
          {
            titulo: 'Conferir documentos de {nome}',
            tipo: 'document',
            prazo_dias: 1,
          },
          0,
          300
        ),
        no('n4', 'esperar', { quantidade: 2, unidade: 'dias' }, 0, 440),
        no(
          'n5',
          'rascunho_texto',
          {
            rotulo: 'Lembrete dos documentos',
            texto:
              'Oi, {nome}! Passando para lembrar dos documentos do seu caso. Se tiver dúvida sobre algum deles, é só me chamar por aqui.',
          },
          0,
          580
        ),
        no(
          'n6',
          'avisar_push',
          { texto: 'Lembrete de documentos pronto para revisar: {nome}' },
          0,
          740
        ),
      ],
      setas: [
        seta('n1', 's', 'n2'),
        seta('n2', 's', 'n3'),
        seta('n3', 's', 'n4'),
        seta('n4', 's', 'n5'),
        seta('n5', 's', 'n6'),
      ],
    },
  },
  {
    chave: 'fora_do_horario',
    icone: 'i-lucide-moon',
    limite_dia: 50,
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'mensagem_recebida', caixa_ids: [] }, 0, 0),
        no(
          'n2',
          'se',
          {
            juncao: 'e',
            condicoes: [
              { campo: 'texto', operador: 'em_horario_comercial', valor: '' },
            ],
          },
          0,
          140
        ),
        no(
          'n3',
          'rascunho_texto',
          {
            rotulo: 'Retorno fora do horário',
            texto:
              'Oi, {nome}! Recebemos sua mensagem. Nosso atendimento é em horário comercial — assim que a equipe voltar, respondemos por aqui.',
          },
          130,
          300
        ),
      ],
      setas: [seta('n1', 's', 'n2'), seta('n2', 'nao', 'n3')],
    },
  },
  {
    chave: 'rodar_na_mao',
    icone: 'i-lucide-hand',
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'manual' }, 0, 0),
        no(
          'n2',
          'rascunho_texto',
          {
            rotulo: 'Pedir documentos',
            texto:
              'Oi, {nome}! Para seguirmos com o seu caso, ainda precisamos de alguns documentos. Pode me enviar por aqui quando puder?',
          },
          0,
          140
        ),
        no(
          'n3',
          'criar_tarefa',
          {
            titulo: 'Cobrar documentos de {nome}',
            tipo: 'document',
            prazo_dias: 2,
          },
          0,
          300
        ),
      ],
      setas: [seta('n1', 's', 'n2'), seta('n2', 's', 'n3')],
    },
  },
  {
    chave: 'lead_ganho',
    icone: 'i-lucide-trophy',
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'lead_ganho' }, 0, 0),
        no(
          'n2',
          'nota_privada',
          {
            texto:
              'Lead ganho: conferir a passagem do caso para o jurídico (responsável: {responsavel}).',
          },
          0,
          140
        ),
        no(
          'n3',
          'criar_tarefa',
          {
            titulo: 'Passagem para o jurídico: {nome}',
            tipo: 'other',
            prazo_dias: 1,
          },
          0,
          280
        ),
        no('n4', 'avisar_sino', { texto: 'Lead ganho: {nome}' }, 0, 420),
      ],
      setas: [
        seta('n1', 's', 'n2'),
        seta('n2', 's', 'n3'),
        seta('n3', 's', 'n4'),
      ],
    },
  },
];
