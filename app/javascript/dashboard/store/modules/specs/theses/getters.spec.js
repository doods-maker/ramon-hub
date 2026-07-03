import { getters } from '../../theses';

describe('theses getters', () => {
  it('getTheses retorna os registros ordenados por position', () => {
    const state = {
      records: [
        { id: 2, name: 'BPC/LOAS', position: 1 },
        { id: 1, name: 'Auxílio-acidente', position: 0 },
      ],
    };
    expect(getters.getTheses(state)).toEqual([
      { id: 1, name: 'Auxílio-acidente', position: 0 },
      { id: 2, name: 'BPC/LOAS', position: 1 },
    ]);
  });

  it('getThesis encontra a tese pelo id', () => {
    const state = {
      records: [
        { id: 1, name: 'Auxílio-acidente' },
        { id: 2, name: 'BPC/LOAS' },
      ],
    };
    expect(getters.getThesis(state)(2)).toEqual({ id: 2, name: 'BPC/LOAS' });
  });

  it('getThesis retorna undefined quando não encontra', () => {
    const state = { records: [{ id: 1, name: 'Auxílio-acidente' }] };
    expect(getters.getThesis(state)(99)).toBeUndefined();
  });

  it('getUIFlags retorna as uiFlags do estado', () => {
    const state = { uiFlags: { isFetching: true } };
    expect(getters.getUIFlags(state)).toEqual({ isFetching: true });
  });
});
