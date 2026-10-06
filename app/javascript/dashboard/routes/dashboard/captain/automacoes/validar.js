// Espelho de Ramon::Fluxos::Grafo#erros (app/services/ramon/fluxos/grafo.rb):
// mesmas regras, mesma ordem. Serve para acender o passo antes de chamar o
// back; quem decide no Publicar continua sendo o back.
import {
  CHATWOOT_PERMITIDAS,
  GATILHOS,
  TIPOS_PASSO,
  UNIDADES,
  alcancaveis,
} from './fluxo';

const OBRIGATORIOS = {
  rascunho_texto: ['texto'],
  nota_privada: ['texto'],
  mover_etapa: ['etapa_id'],
  criar_tarefa: ['titulo'],
  escolha: ['campo'],
  avisar_sino: ['texto'],
  avisar_push: ['texto'],
};
const MENSAGEM_CLIENTE = ['send_message', 'send_attachment'];
const PROIBIDAS = [
  ...MENSAGEM_CLIENTE,
  'send_email_transcript',
  'send_webhook_event',
];

const erro = (no, codigo, params = {}) => ({ no, codigo, params });

// blank? do Rails
const vazio = v =>
  v == null ||
  v === false ||
  (typeof v === 'string' && !v.trim()) ||
  (Array.isArray(v) && !v.length) ||
  (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length);

const errosSetas = (nos, setas) => {
  const ids = new Set(nos.map(n => n.id));
  const fantasmas = [...new Set(setas.flatMap(s => [s.de, s.para]))].filter(
    id => !ids.has(id)
  );
  const vistas = new Set();
  const repetidas = [];
  setas.forEach(s => {
    const chave = JSON.stringify([s.de, s.saida]);
    if (
      vistas.has(chave) &&
      !repetidas.some(r => r.de === s.de && r.saida === s.saida)
    )
      repetidas.push(s);
    vistas.add(chave);
  });
  return [
    ...fantasmas.map(id => erro(null, 'SETA_FANTASMA', { id })),
    ...repetidas.map(s => erro(s.de, 'SETA_REPETIDA', { saida: s.saida })),
  ];
};

const temCiclo = (nos, setas) => {
  const estado = {};
  const visita = id => {
    if (estado[id] === 'aberto') return true;
    if (estado[id] === 'fechado') return false;
    estado[id] = 'aberto';
    const achou = setas.filter(s => s.de === id).some(s => visita(s.para));
    estado[id] = 'fechado';
    return achou;
  };
  return nos.some(n => visita(n.id));
};

const errosAlcance = (nos, setas, gatilhoId) => {
  if (temCiclo(nos, setas)) return [erro(null, 'CICLO')];
  const ok = alcancaveis(setas, gatilhoId);
  return nos.filter(n => !ok.has(n.id)).map(n => erro(n.id, 'SOLTO'));
};

const errosEscolha = (id, config) => {
  const casos = config.casos || [];
  if (casos.length < 2) return [erro(id, 'ESCOLHA_POUCOS_CASOS')];
  const erros = [];
  if (new Set(casos.map(c => c.chave)).size < casos.length)
    erros.push(erro(id, 'ESCOLHA_CHAVE_REPETIDA'));
  const valores = casos.flatMap(c =>
    (c.valores || []).map(v => String(v).toLowerCase())
  );
  if (new Set(valores).size < valores.length)
    erros.push(erro(id, 'ESCOLHA_VALOR_REPETIDO'));
  return erros;
};

const esperaValida = c =>
  c.ate === 'horario_comercial' ||
  (Number.parseInt(c.quantidade, 10) > 0 && UNIDADES.includes(c.unidade));

const errosChatwoot = (id, config) => {
  const nomes = (config.acoes || []).map(a => a.action_name);
  if (!nomes.length) return [erro(id, 'CHATWOOT_SEM_ACAO')];
  if (nomes.some(n => MENSAGEM_CLIENTE.includes(n)))
    return [erro(id, 'CHATWOOT_MENSAGEM')];
  return nomes.flatMap(nome => {
    if (PROIBIDAS.includes(nome))
      return [erro(id, 'CHATWOOT_PROIBIDA', { nome })];
    if (!CHATWOOT_PERMITIDAS.includes(nome))
      return [erro(id, 'CHATWOOT_DESCONHECIDA', { nome })];
    return [];
  });
};

const errosEspecificos = (no, config, setas) => {
  switch (no.tipo) {
    case 'se':
      return [
        ...((config.condicoes || []).length
          ? []
          : [erro(no.id, 'SE_SEM_CONDICOES')]),
        ...(setas.some(s => s.de === no.id)
          ? []
          : [erro(no.id, 'SE_SEM_SAIDA')]),
      ];
    case 'escolha':
      return errosEscolha(no.id, config);
    case 'esperar':
      return esperaValida(config) ? [] : [erro(no.id, 'ESPERA_SEM_TEMPO')];
    case 'acao_chatwoot':
      return errosChatwoot(no.id, config);
    default:
      return [];
  }
};

const errosPasso = (no, setas) => {
  if (no.tipo === 'gatilho') return [];
  if (!TIPOS_PASSO.includes(no.tipo))
    return [erro(no.id, 'TIPO_DESCONHECIDO', { tipo: no.tipo })];
  const config = no.config || {};
  const faltas = (OBRIGATORIOS[no.tipo] || [])
    .filter(k => vazio(config[k]))
    .map(campo => erro(no.id, 'FALTA', { campo }));
  return [...faltas, ...errosEspecificos(no, config, setas)];
};

export const validar = ({ nos = [], setas = [] } = {}) => {
  const gatilhos = nos.filter(n => n.tipo === 'gatilho');
  if (gatilhos.length !== 1) return [erro(null, 'UM_GATILHO')];
  const [gatilho] = gatilhos;
  if (!GATILHOS.some(x => x.tipo === gatilho.config?.tipo))
    return [erro(gatilho.id, 'GATILHO_DESCONHECIDO')];
  return [
    ...errosSetas(nos, setas),
    ...errosAlcance(nos, setas, gatilho.id),
    ...nos.flatMap(n => errosPasso(n, setas)),
  ];
};
