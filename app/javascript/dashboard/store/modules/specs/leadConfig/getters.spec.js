import { getters, mutations } from '../../leadConfig';
import types from '../../../mutation-types';

describe('leadConfig getters', () => {
  it('getLostReasons retorna os motivos de perda do estado', () => {
    const state = {
      lostReasons: [
        { id: 1, name: 'Sem interesse' },
        { id: 2, name: 'Sem documentos' },
      ],
    };
    expect(getters.getLostReasons(state)).toEqual([
      { id: 1, name: 'Sem interesse' },
      { id: 2, name: 'Sem documentos' },
    ]);
  });

  it('SET_LEAD_CONFIG popula lostReasons e faz pass-through de probability/stalled_after_days nos stages', () => {
    const state = {
      stages: [],
      benefitTypes: [],
      priorities: [],
      sources: [],
      lostReasons: [],
    };
    mutations[types.SET_LEAD_CONFIG](state, {
      stages: [
        { id: 1, name: 'Novo', probability: 10, stalled_after_days: 3 },
      ],
      lost_reasons: [{ id: 1, name: 'Sem interesse' }],
    });
    expect(state.lostReasons).toEqual([{ id: 1, name: 'Sem interesse' }]);
    // o stage inteiro é guardado → campos novos passam adiante
    expect(state.stages[0]).toMatchObject({
      probability: 10,
      stalled_after_days: 3,
    });
  });

  it('SET_LEAD_CONFIG usa [] quando lost_reasons ausente', () => {
    const state = { lostReasons: [{ id: 9 }] };
    mutations[types.SET_LEAD_CONFIG](state, { stages: [] });
    expect(state.lostReasons).toEqual([]);
  });
});
