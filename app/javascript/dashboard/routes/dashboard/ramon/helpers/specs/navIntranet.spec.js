import { secoesIntranet, grupoDaRota, linkDaAba } from '../navIntranet';

const mapa = secoes =>
  secoes.map(s => [
    s.label,
    s.grupos.map(g => [g.key, g.abas.map(a => a.name)]),
  ]);

// Inteligência num lugar só (plano 2026-11-22): toda a IA do hub numa seção.
const INTELIGENCIA_ADMIN = [
  'RAMON.NAV.INTELIGENCIA',
  [
    ['ia_visao_geral', ['captain_visao_geral_index']],
    ['ia_como_atende', ['captain_como_ia_atende_index']],
    ['ia_teses', ['ramon_playbooks', 'captain_assistants_responses_index']],
    [
      'ia_assistentes',
      [
        'captain_assistants_create_index',
        'captain_assistants_settings_index',
        'captain_assistants_scenarios_index',
        'captain_ferramentas_index',
        'captain_assistants_inboxes_index',
      ],
    ],
    ['ia_automacoes', ['captain_automacoes_index']],
    [
      'ia_testar',
      [
        'captain_assistants_playground_index',
        'captain_assistants_casos_teste_index',
      ],
    ],
    [
      'ia_historico',
      [
        'captain_execucoes_index',
        'captain_ia_uso_index',
        'ramon_registro_acoes',
      ],
    ],
  ],
];

describe('secoesIntranet', () => {
  it('admin: 3 seções, com todas as abas', () => {
    expect(mapa(secoesIntranet(true))).toEqual([
      [
        'RAMON.NAV.OPERACAO',
        [
          ['hoje', ['ramon_index', 'ramon_esteira']],
          ['funil', ['ramon_funil', 'ramon_radar', 'ramon_pos_venda']],
          ['agenda', ['ramon_agenda', 'ramon_reunioes']],
          [
            'clientes',
            [
              'ramon_pessoas',
              'ramon_portal_clientes',
              'ramon_conferencia_fases',
              'ramon_calculos',
              'ramon_protocolos',
              'ramon_validacao_apto',
            ],
          ],
        ],
      ],
      [
        'RAMON.NAV.GESTAO',
        [
          [
            'marketing',
            [
              'ramon_conteudo',
              'ramon_marketing_trafego',
              'ramon_marketing_custos',
            ],
          ],
          [
            'resultados',
            [
              'ramon_painel_time',
              'ramon_extrato',
              'ramon_relatorios',
              'ramon_tv',
            ],
          ],
          ['configuracoes', ['ramon_funil_config', 'ramon_registro_acoes']],
        ],
      ],
      INTELIGENCIA_ADMIN,
    ]);
  });

  it('agente: sem Conteúdo e Configurações; Resultados com Painel do time e Extrato', () => {
    const gestao = secoesIntranet(false)[1];
    expect(mapa([gestao])).toEqual([
      [
        'RAMON.NAV.GESTAO',
        [['resultados', ['ramon_painel_time', 'ramon_extrato']]],
      ],
    ]);
    expect(secoesIntranet(false)[0].grupos).toHaveLength(4);
  });
});

describe('painel dos agentes', () => {
  const grupos = painel =>
    secoesIntranet(true, painel)[1].grupos.map(grupo => grupo.key);

  it('só aparece para quem o backend liberou, mesmo sendo admin', () => {
    expect(grupos(false)).not.toContain('agentes');
    expect(grupos(true)).toContain('agentes');
    expect(grupoDaRota('ramon_agentes', true)).toBeUndefined();
    expect(grupoDaRota('ramon_agentes', true, true).key).toBe('agentes');
  });
});

describe('grupoDaRota', () => {
  it.each([
    ['ramon_esteira', 'hoje'],
    ['ramon_pos_venda', 'funil'],
    ['ramon_reuniao', 'agenda'],
    ['ramon_linha_da_vida', 'clientes'],
    ['ramon_lead_dossie', 'clientes'],
    ['ramon_calculos_lead', 'clientes'],
    ['ramon_conferencia_fases', 'clientes'],
    ['ramon_protocolo', 'clientes'],
    ['ramon_relatorios', 'resultados'],
    ['ramon_registro_acoes', 'configuracoes'],
  ])('%s acende %s', (rota, grupo) => {
    expect(grupoDaRota(rota, true).key).toBe(grupo);
  });

  it('a aba que acende é a da rota-mãe', () => {
    const clientes = grupoDaRota('ramon_calculos_lead', false);
    const ativa = clientes.abas.find(a =>
      a.names.includes('ramon_calculos_lead')
    );
    expect(ativa.name).toBe('ramon_calculos');
  });

  it('agente não acha grupo de rota só de admin; fora da intranet = nada', () => {
    expect(grupoDaRota('ramon_funil_config', false)).toBeUndefined();
    expect(grupoDaRota('ramon_registro_acoes', false)).toBeUndefined();
    expect(grupoDaRota('ramon_extrato', false).abas).toHaveLength(2);
    expect(grupoDaRota('ramon_external_shortcuts', true)).toBeUndefined();
  });
});

describe('Inteligência', () => {
  it('agente vê só o que a rota de hoje deixa (sem Como atende, Automações, Teses, custo e registro)', () => {
    const ia = secoesIntranet(false).find(
      s => s.label === 'RAMON.NAV.INTELIGENCIA'
    );
    expect(mapa([ia])).toEqual([
      [
        'RAMON.NAV.INTELIGENCIA',
        [
          ['ia_visao_geral', ['captain_visao_geral_index']],
          ['ia_teses', ['captain_assistants_responses_index']],
          [
            'ia_assistentes',
            [
              'captain_assistants_create_index',
              'captain_assistants_settings_index',
              'captain_assistants_scenarios_index',
              'captain_ferramentas_index',
              'captain_assistants_inboxes_index',
            ],
          ],
          ['ia_testar', ['captain_assistants_playground_index']],
          ['ia_historico', ['captain_execucoes_index']],
        ],
      ],
    ]);
  });

  it.each([
    ['ramon_playbooks', 'ia_teses'],
    ['captain_assistants_responses_pending', 'ia_teses'],
    ['captain_assistants_documents_index', 'ia_teses'],
    ['captain_assistants_guidelines_index', 'ia_assistentes'],
    ['captain_assistants_guardrails_index', 'ia_assistentes'],
    ['captain_tools_index', 'ia_assistentes'],
    ['captain_automacoes_editor', 'ia_automacoes'],
    ['captain_automacoes_execucao', 'ia_automacoes'],
  ])('%s acende %s', (rota, grupo) => {
    expect(grupoDaRota(rota, true).key).toBe(grupo);
  });

  it('Registro com tipo=ia é "Mudanças da IA" no Histórico; sem filtro, segue em Configurações', () => {
    const historico = grupoDaRota('ramon_registro_acoes', true, false, {
      tipo: 'ia',
    });
    expect(historico.key).toBe('ia_historico');
    expect(grupoDaRota('ramon_registro_acoes', true).key).toBe('configuracoes');
    expect(
      grupoDaRota('ramon_registro_acoes', true, false, { tipo: 'lead' }).key
    ).toBe('configuracoes');
  });
});

describe('linkDaAba', () => {
  const aba = (grupo, nome) =>
    secoesIntranet(true)
      .flatMap(s => s.grupos)
      .find(g => g.key === grupo)
      .abas.find(a => a.name === nome);

  it('aba comum vai direto para a rota', () => {
    expect(
      linkDaAba(aba('ia_visao_geral', 'captain_visao_geral_index'))
    ).toEqual({ name: 'captain_visao_geral_index', params: {}, query: {} });
  });

  it('aba de assistente passa pelo resolvedor do Captain (lembra o último assistente)', () => {
    const faqs = aba('ia_teses', 'captain_assistants_responses_index');
    expect(linkDaAba(faqs)).toEqual({
      name: 'captain_assistants_index',
      params: { navigationPath: 'captain_assistants_responses_index' },
      query: {},
    });
  });

  it('Mudanças da IA abre o Registro já filtrado', () => {
    expect(
      linkDaAba(aba('ia_historico', 'ramon_registro_acoes')).query
    ).toEqual({ tipo: 'ia' });
  });
});
