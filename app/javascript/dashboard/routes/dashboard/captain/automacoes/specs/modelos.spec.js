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
    expect(tipos).not.toContain('webhook');
  });

  it('Pós-contrato: contrato assinado → … → se documentos completos, senão rascunho da IA + push', () => {
    const { desenho } = MODELOS.find(m => m.chave === 'pos_contrato');
    expect(desenho.nos[0].config.tipo).toBe('contrato_assinado');
    const se = desenho.nos.find(n => n.tipo === 'se');
    expect(se.config.condicoes).toEqual([
      { campo: 'documentos_completos', operador: 'igual', valor: 'sim' },
    ]);
    const nao = desenho.setas.find(s => s.de === se.id && s.saida === 'nao');
    expect(desenho.nos.find(n => n.id === nao.para).tipo).toBe('rascunho_ia');
  });
});
