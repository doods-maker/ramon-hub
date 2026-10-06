import { MODELOS } from '../modelos';
import { validar } from '../validar';
import { deVueFlow, paraVueFlow } from '../fluxo';

describe('modelos prontos', () => {
  it('são os 5 da B2, com "em branco" primeiro', () => {
    expect(MODELOS.map(m => m.chave)).toEqual([
      'branco',
      'pos_contrato',
      'fora_do_horario',
      'rodar_na_mao',
      'lead_ganho',
    ]);
  });

  it.each(MODELOS.map(m => [m.chave, m]))(
    '%s publica sem erro e reabre idêntico',
    (_chave, modelo) => {
      expect(validar(modelo.desenho)).toEqual([]);
      const { nodes, edges } = paraVueFlow(modelo.desenho);
      expect(deVueFlow(nodes, edges)).toEqual(modelo.desenho);
    }
  );

  it('todo texto ao cliente é rascunho_texto (nunca envio)', () => {
    const tipos = MODELOS.flatMap(m => m.desenho.nos.map(n => n.tipo));
    expect(tipos).not.toContain('acao_chatwoot');
  });
});
