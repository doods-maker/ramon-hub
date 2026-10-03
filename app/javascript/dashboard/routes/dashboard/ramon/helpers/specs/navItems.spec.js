import {
  itensDoMenu,
  itensDoMais,
  CONVERSA_ROUTES,
  SUBITENS_CONVERSAS,
  NOTIFICACAO_ROUTES,
  ehAreaChatwoot,
} from '../navItems';

const chaves = papel => itensDoMenu(papel).map(i => i.key);

describe('itensDoMenu', () => {
  it('gestor vê os 9', () => {
    expect(chaves('gestor')).toEqual([
      'hoje',
      'conversas',
      'funil',
      'clientes',
      'agenda',
      'calculos',
      'conteudo',
      'resultados',
      'mais',
    ]);
  });
  it('sdr, closer e equipe veem 7 (sem conteúdo e sem mais)', () => {
    ['sdr', 'closer', 'equipe'].forEach(papel =>
      expect(chaves(papel)).toEqual([
        'hoje',
        'conversas',
        'funil',
        'clientes',
        'agenda',
        'calculos',
        'resultados',
      ])
    );
  });
  it('recepção vê 4', () => {
    expect(chaves('recepcao')).toEqual([
      'hoje',
      'conversas',
      'clientes',
      'agenda',
    ]);
  });
  it('advogada vê 5', () => {
    expect(chaves('advogada')).toEqual([
      'hoje',
      'conversas',
      'clientes',
      'agenda',
      'calculos',
    ]);
  });
  it('Resultados: gestor vai a relatórios, os demais ao extrato', () => {
    const rota = papel =>
      itensDoMenu(papel).find(i => i.key === 'resultados').rota;
    expect(rota('gestor')).toBe('ramon_relatorios');
    expect(rota('sdr')).toBe('ramon_extrato');
  });
  it('label é chave i18n do bloco RAMON.MENU', () => {
    expect(itensDoMenu('gestor')[0].label).toBe('RAMON.MENU.HOJE');
    expect(itensDoMais('gestor').find(i => i.key === 'pos_venda').label).toBe(
      'RAMON.MENU.POS_VENDA'
    );
  });
  it('Conversas acende em qualquer rota de conversa, menos o kanban', () => {
    expect(CONVERSA_ROUTES).toContain('home');
    expect(CONVERSA_ROUTES).toContain('inbox_conversation');
    expect(CONVERSA_ROUTES).not.toContain('kanban_board');
  });
  it('caixa de notificações acende o sino, não Conversas', () => {
    expect(CONVERSA_ROUTES).not.toContain('inbox_view');
    expect(NOTIFICACAO_ROUTES).toEqual([
      'inbox_view',
      'inbox_view_conversation',
    ]);
  });
  it('sub-itens de Conversas: menções, participando, não atendidas', () => {
    expect(SUBITENS_CONVERSAS.map(i => i.rota)).toEqual([
      'conversation_mentions',
      'conversation_participating',
      'conversation_unattended',
    ]);
    expect(SUBITENS_CONVERSAS[0].label).toBe('RAMON.MENU.MENCOES');
  });
  it('área nativa do Chatwoot pelo 1º segmento depois da conta', () => {
    [
      '/app/accounts/2/settings/inboxes/list',
      '/app/accounts/2/captain/1/faqs',
      '/app/accounts/2/reports/overview',
      '/app/accounts/2/contacts',
      '/app/accounts/2/companies',
      '/app/accounts/2/campaigns/sms',
      '/app/accounts/2/portals/x/pt/articles',
    ].forEach(path => expect(ehAreaChatwoot(path)).toBe(true));
    [
      '/app/accounts/2/dashboard',
      '/app/accounts/2/ramon/funil',
      '/app/accounts/2/ramon/contacts-x',
      '/app/accounts/2/inbox-view',
      '/app/accounts/2/profile/settings',
    ].forEach(path => expect(ehAreaChatwoot(path)).toBe(false));
  });
  it('Mais só existe pro gestor', () => {
    expect(itensDoMais('sdr')).toEqual([]);
    expect(itensDoMais('gestor').map(i => i.key)).toContain('tv');
  });
  it('Hoje acende só na tela Hoje; o Centro de Comando abre o Mais', () => {
    expect(itensDoMenu('gestor')[0].names).toEqual(['ramon_index']);
    expect(itensDoMais('gestor')[0]).toMatchObject({
      key: 'painel',
      rota: 'ramon_painel',
      label: 'RAMON.MENU.PAINEL',
    });
  });
});
