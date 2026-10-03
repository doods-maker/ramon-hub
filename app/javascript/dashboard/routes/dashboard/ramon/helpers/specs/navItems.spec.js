import { itensDoMenu, itensDoMais, CONVERSA_ROUTES } from '../navItems';

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
  it('Mais só existe pro gestor', () => {
    expect(itensDoMais('sdr')).toEqual([]);
    expect(itensDoMais('gestor').map(i => i.key)).toContain('tv');
  });
});
