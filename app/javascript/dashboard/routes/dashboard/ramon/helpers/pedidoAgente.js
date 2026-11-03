// Traduz um pedido de permissão da esteira para o que a pessoa precisa ler:
// a ação em português, a quem vai e o texto em seções (ADR 0014).

const ACOES = {
  advbox_criar_tarefa: { chave: 'TAREFA', icone: 'i-lucide-square-check' },
  advbox_criar_movimentacao: {
    chave: 'MOVIMENTACAO',
    icone: 'i-lucide-pencil-line',
  },
  WebFetch: { chave: 'SITE', icone: 'i-lucide-globe', linha: 'url' },
  WebSearch: { chave: 'BUSCA', icone: 'i-lucide-search', linha: 'query' },
  Bash: { chave: 'COMANDO', icone: 'i-lucide-terminal', linha: 'command' },
  Write: { chave: 'ARQUIVO', icone: 'i-lucide-file-pen', linha: 'file_path' },
  Edit: { chave: 'ARQUIVO', icone: 'i-lucide-file-pen', linha: 'file_path' },
};
const OUTRA = { chave: 'OUTRA', icone: 'i-lucide-wrench' };

// "SITUAÇÃO: texto" ou "DOCUMENTOS QUE FALTAM:\n1. item"
const ROTULO = /^([A-ZÀ-Ú][A-ZÀ-Ú ]{2,}):\s*/;

export const blocosDoTexto = texto =>
  String(texto || '')
    .split(/\n{2,}/)
    .map(trecho => trecho.trim())
    .filter(Boolean)
    .map(trecho => {
      const achou = trecho.match(ROTULO);
      return achou
        ? { rotulo: achou[1], texto: trecho.slice(achou[0].length) }
        : { rotulo: null, texto: trecho };
    });

const dataBr = valor => String(valor).split('-').reverse().join('/');

const camposDe = ({ entrada = {}, nomes = {} }) => {
  const campos = [];
  const incluir = (chave, valor) => valor && campos.push({ chave, valor });
  incluir(
    'PARA',
    nomes.responsavel ||
      (entrada.responsavel_id && `#${entrada.responsavel_id}`)
  );
  incluir(
    'TIPO',
    nomes.tipo || (entrada.tipo_tarefa_id && `#${entrada.tipo_tarefa_id}`)
  );
  incluir('PROCESSO', entrada.processo_id && `#${entrada.processo_id}`);
  incluir('PRAZO', entrada.prazo && dataBr(entrada.prazo));
  return campos;
};

export const descreverPedido = pedido => {
  const entrada = pedido.entrada || {};
  const nome = String(pedido.ferramenta || '')
    .split('__')
    .pop();
  const acao = ACOES[nome];
  const [, cliente, numero] = String(pedido.caso || '').match(
    /^(.*?)\s*#?(\d+)$/
  ) || [null, pedido.caso || '', ''];

  return {
    ...(acao || OUTRA),
    conhecida: Boolean(acao),
    ferramenta: nome,
    cliente,
    numero,
    linha: acao?.linha ? entrada[acao.linha] : null,
    campos: camposDe({ entrada, nomes: pedido.nomes }),
    blocos: blocosDoTexto(entrada.descricao || entrada.aviso),
  };
};
