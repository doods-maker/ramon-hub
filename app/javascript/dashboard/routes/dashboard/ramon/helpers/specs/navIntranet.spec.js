import { secoesIntranet, grupoDaRota } from '../navIntranet';

const mapa = secoes =>
  secoes.map(s => [
    s.label,
    s.grupos.map(g => [g.key, g.abas.map(a => a.name)]),
  ]);

describe('secoesIntranet', () => {
  it('admin: 7 itens em 2 seções, com todas as abas', () => {
    expect(mapa(secoesIntranet(true))).toEqual([
      [
        'RAMON.NAV.OPERACAO',
        [
          ['hoje', ['ramon_index', 'ramon_esteira']],
          ['funil', ['ramon_funil', 'ramon_radar', 'ramon_pos_venda']],
          ['agenda', ['ramon_agenda', 'ramon_reunioes']],
          [
            'clientes',
            ['ramon_pessoas', 'ramon_portal_clientes', 'ramon_calculos'],
          ],
        ],
      ],
      [
        'RAMON.NAV.GESTAO',
        [
          ['conteudo', ['ramon_conteudo']],
          [
            'resultados',
            [
              'ramon_painel_time',
              'ramon_extrato',
              'ramon_relatorios',
              'ramon_tv',
            ],
          ],
          [
            'configuracoes',
            ['ramon_funil_config', 'ramon_playbooks', 'ramon_registro_acoes'],
          ],
        ],
      ],
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

describe('grupoDaRota', () => {
  it.each([
    ['ramon_esteira', 'hoje'],
    ['ramon_pos_venda', 'funil'],
    ['ramon_reuniao', 'agenda'],
    ['ramon_linha_da_vida', 'clientes'],
    ['ramon_lead_dossie', 'clientes'],
    ['ramon_calculos_lead', 'clientes'],
    ['ramon_relatorios', 'resultados'],
    ['ramon_playbooks', 'configuracoes'],
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
