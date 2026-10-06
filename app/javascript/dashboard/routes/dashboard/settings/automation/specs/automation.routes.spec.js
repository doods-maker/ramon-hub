import automation from '../automation.routes';

describe('Configurações → Automação (FORK ramon)', () => {
  it('o link antigo cai em Inteligência → Automações', () => {
    expect(automation.routes.map(r => r.path)).toEqual([
      '/app/accounts/:accountId/settings/automation',
      '/app/accounts/:accountId/settings/automation/list',
    ]);
    automation.routes.forEach(r =>
      expect(r.redirect({ params: { accountId: '7' } })).toEqual({
        name: 'captain_automacoes_index',
        params: { accountId: '7' },
      })
    );
  });
});
