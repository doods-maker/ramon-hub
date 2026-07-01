import { getters } from '../../leads';

describe('leads getters', () => {
  it('getLeadByConversationId encontra o lead pelo conversation_id', () => {
    const state = {
      records: [
        { id: 1, conversation_id: 5 },
        { id: 2, conversation_id: 9 },
      ],
    };
    expect(getters.getLeadByConversationId(state)(9)).toEqual({
      id: 2,
      conversation_id: 9,
    });
  });

  it('retorna undefined quando não encontra o lead', () => {
    const state = { records: [{ id: 1, conversation_id: 5 }] };
    expect(getters.getLeadByConversationId(state)(99)).toBeUndefined();
  });
});
