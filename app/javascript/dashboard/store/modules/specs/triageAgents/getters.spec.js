import { getters } from '../../triageAgents';

describe('triageAgents getters', () => {
  it('getAgents retorna os registros ordenados por id', () => {
    const state = {
      records: [
        { id: 2, name: 'Triagem Trabalhista' },
        { id: 1, name: 'Triagem Previdenciária' },
      ],
    };
    expect(getters.getAgents(state)).toEqual([
      { id: 1, name: 'Triagem Previdenciária' },
      { id: 2, name: 'Triagem Trabalhista' },
    ]);
  });

  it('getUIFlags retorna as uiFlags do estado', () => {
    const state = { uiFlags: { isFetching: true } };
    expect(getters.getUIFlags(state)).toEqual({ isFetching: true });
  });
});
