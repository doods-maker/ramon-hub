// Espelho de Ramon::Fluxos::Grafo#erros (app/services/ramon/fluxos/grafo.rb):
// mesmas regras, mesma ordem. Serve para acender o passo antes de chamar o
// back; quem decide no Publicar continua sendo o back.
import {
  CHATWOOT_PERMITIDAS,
  GATILHOS,
  TIPOS_PASSO,
  JANELA_PADRAO,
  UNIDADES,
  PASSOS_CONTA,
  alcancaveis,
  rotinaAlvo,
  semLead,
} from './fluxo';

export const OBRIGATORIOS = {
  rascunho_texto: ['texto'],
  nota_privada: ['texto'],
  mover_etapa: ['etapa_id'],
  criar_tarefa: ['titulo'],
  escolha: ['campo'],
  avisar_sino: ['texto'],
  avisar_push: ['texto'],
  perguntar_ia: ['pergunta'],
  rascunho_ia: ['instrucao'],
  rodar_skill: ['assistente_id', 'skill_id'],
  registrar_atividade: ['texto'],
  trocar_responsavel: ['papel'],
  rotina: ['rotina'],
};
const MENSAGEM_CLIENTE = ['send_message', 'send_attachment'];
const PROIBIDAS = [
  ...MENSAGEM_CLIENTE,
  'send_email_transcript',
  'send_webhook_event',
];
const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
const CHAVE_CAMPO = /^[a-z][a-z0-9_]{0,39}$/;
// = Ramon::Fluxos::Contexto::RESERVADAS (app/services/ramon/fluxos/contexto.rb): nomes que o hub monta em `dados`
const RESERVADAS = [
  'texto',
  'quando',
  'regra',
  'documento',
  'nome',
  'nome_completo',
  'telefone',
  'responsavel',
  'responsavel_id',
  'etapa',
  'etapa_id',
  'tese',
  'tese_id',
  'origem',
  'canal',
  'valor',
  'prioridade',
  'caixa',
  'caixa_id',
  'status',
  'etiquetas',
  'documentos_completos',
  'documentos_faltantes',
  'resposta_ia',
  'evento',
  'titulo',
  'titulo_tarefa',
  'resumo',
  'resumo_antes',
  'primeiro_nome',
  'hoje',
  'reuniao_de_pe',
  'horario_passou',
  'tentativa',
  'dias_parado',
  'primeira_resposta',
  'sla_minutos',
];

const erro = (no, codigo, params = {}) => ({ no, codigo, params });

// blank? do Rails
const vazio = v =>
  v == null ||
  v === false ||
  (typeof v === 'string' && !v.trim()) ||
  (Array.isArray(v) && !v.length) ||
  (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length);

const temSaida = (id, setas) => setas.some(s => s.de === id);

// relógio exige a hora; lead parado usa 11:00 se vier vazia (Grafo#erros_hora)
const errosHora = gatilho => {
  const c = gatilho.config || {};
  const hora = String(c.hora ?? '');
  if (c.tipo === 'relogio' && !hora) return [erro(gatilho.id, 'GATILHO_HORA')];
  return !hora || HORA.test(hora) ? [] : [erro(gatilho.id, 'GATILHO_HORA')];
};

const errosAdvbox = (id, c) => {
  if (c.acao === 'tarefa')
    return ['tipo_tarefa_id', 'responsavel_id']
      .filter(k => vazio(c[k]))
      .map(campo => erro(id, 'FALTA', { campo }));
  if (c.acao === 'movimentacao')
    return String(c.descricao ?? '').trim().length >= 10
      ? []
      : [erro(id, 'ADVBOX_DESCRICAO')];
  return [erro(id, 'ADVBOX_ACAO')];
};

const errosWebhook = (id, c, setas) => [
  ...(String(c.url ?? '').startsWith('https://')
    ? []
    : [erro(id, 'WEBHOOK_HTTPS')]),
  ...(temSaida(id, setas) ? [erro(id, 'WEBHOOK_ULTIMO')] : []),
];

// chave fora do padrão ou reservada (Grafo#erros_campo)
const errosCampo = (id, c) => {
  const chave = String(c.chave ?? '');
  return CHAVE_CAMPO.test(chave) && !RESERVADAS.includes(chave)
    ? []
    : [erro(id, 'CAMPO_CHAVE')];
};

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
  (c.desde === 'conversa' && c.prazo === 'sla_caixa') ||
  (Number.parseInt(c.quantidade, 10) > 0 && UNIDADES.includes(c.unidade));

// Ramon::Fluxos::Horario.janela_valida? — sem as chaves vale o padrão
const janelaValida = c => {
  const dias =
    'dias' in c ? [].concat(c.dias ?? []).map(Number) : JANELA_PADRAO.dias;
  const inicio = Number(c.inicio ?? JANELA_PADRAO.inicio);
  const fim = Number(c.fim ?? JANELA_PADRAO.fim);
  return (
    dias.length > 0 &&
    dias.every(d => d >= 0 && d <= 6) &&
    inicio >= 0 &&
    inicio < fim &&
    fim <= 24
  );
};
const errosJanela = (id, c) =>
  janelaValida(c) ? [] : [erro(id, 'JANELA_INVALIDA')];

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
        ...(config.condicoes || [])
          .filter(c => c.operador === 'em_horario_comercial')
          .flatMap(c => errosJanela(no.id, c)),
        ...(temSaida(no.id, setas) ? [] : [erro(no.id, 'SE_SEM_SAIDA')]),
      ];
    case 'perguntar_ia':
      return temSaida(no.id, setas) ? [] : [erro(no.id, 'SE_SEM_SAIDA')];
    case 'advbox':
      return errosAdvbox(no.id, config);
    case 'webhook':
      return errosWebhook(no.id, config, setas);
    case 'preencher_campo':
      return errosCampo(no.id, config);
    case 'escolha':
      return errosEscolha(no.id, config);
    case 'esperar':
      return [
        ...(esperaValida(config) ? [] : [erro(no.id, 'ESPERA_SEM_TEMPO')]),
        ...(config.ate === 'horario_comercial'
          ? errosJanela(no.id, config)
          : []),
      ];
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

// = Ramon::Fluxos::HorarioConta.erros: o "quando" do Horário da conta, o que roda sem lead (conta e fora do funil)
// e a rotina do alvo certo
const quandoValido = c => {
  const n = c.a_cada_minutos;
  const ok =
    n != null && n !== ''
      ? /^\d+$/.test(String(n)) && Number(n) >= 1 && Number(n) <= 1440
      : !vazio(c.hora);
  if (!ok || !('dias' in c)) return ok;
  const dias = [].concat(c.dias ?? []).map(Number);
  return dias.length > 0 && dias.every(d => d >= 0 && d <= 6);
};

// alvo = 'conta' | 'outro' (gatilho sem lead) | null (lead/conversa)
const errosNoConta = (no, alvo) => {
  if (no.tipo === 'gatilho') return [];
  if (alvo && !PASSOS_CONTA.includes(no.tipo))
    return [erro(no.id, 'CONTA_PASSO')];
  const nome = no.config?.rotina;
  if (no.tipo !== 'rotina' || vazio(nome)) return [];
  const daRotina = rotinaAlvo(nome);
  if (!daRotina) return [erro(no.id, 'ROTINA_DESCONHECIDA', { nome })];
  if ((semLead(daRotina) ? daRotina : null) === alvo) return [];
  if (alvo === 'conta') return [erro(no.id, 'ROTINA_DE_LEAD')];
  if (daRotina === 'conta') return [erro(no.id, 'ROTINA_DA_CONTA')];
  return [erro(no.id, 'ROTINA_OUTRO_ALVO')];
};

const errosConta = (gatilho, nos) => {
  const c = gatilho.config || {};
  const quando =
    c.tipo === 'horario_conta' && !quandoValido(c)
      ? [erro(gatilho.id, 'CONTA_QUANDO')]
      : [];
  const alvo = GATILHOS.find(x => x.tipo === c.tipo)?.alvo;
  return [
    ...quando,
    ...nos.flatMap(n => errosNoConta(n, semLead(alvo) ? alvo : null)),
  ];
};

export const validar = ({ nos = [], setas = [] } = {}) => {
  const gatilhos = nos.filter(n => n.tipo === 'gatilho');
  if (gatilhos.length !== 1) return [erro(null, 'UM_GATILHO')];
  const [gatilho] = gatilhos;
  if (!GATILHOS.some(x => x.tipo === gatilho.config?.tipo))
    return [erro(gatilho.id, 'GATILHO_DESCONHECIDO')];
  const hora = errosHora(gatilho);
  if (hora.length) return hora;
  return [
    ...errosSetas(nos, setas),
    ...errosAlcance(nos, setas, gatilho.id),
    ...nos.flatMap(n => errosPasso(n, setas)),
    ...errosConta(gatilho, nos),
  ];
};
