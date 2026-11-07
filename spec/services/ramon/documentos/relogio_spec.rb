require 'rails_helper'

# Relógio da cobrança da etapa Documentos (spec §7): função pura, testada por tabela. Horário padrão dos fluxos: seg–sex
# 8h–18h em São Paulo (1 dia útil = 10 h úteis). 05/10/2026 é segunda; 30/10 é sexta; 02/11 (Finados) é segunda.
RSpec.describe Ramon::Documentos::Relogio do
  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  def passo(agora, horario: described_class::CONFIG['horario'], **estado)
    described_class.proximo_passo(estado: estado.transform_keys(&:to_s).transform_values { |v| sp(v).iso8601 }, agora: sp(agora),
                                  horario: horario)
  end

  # [caso, estado, agora, passo esperado, quando venceu]
  casos = [
    ['entrou em horário comercial: abertura na hora',
     { entrou_em: '2026-10-05 10:00' }, '2026-10-05 10:00', :abertura, '2026-10-05 10:00'],
    ['entrou na sexta à noite: no sábado nada sai',
     { entrou_em: '2026-10-09 19:00' }, '2026-10-10 10:00', nil, nil],
    ['entrou na sexta à noite: abertura segunda às 8h',
     { entrou_em: '2026-10-09 19:00' }, '2026-10-12 08:00', :abertura, '2026-10-12 08:00'],
    ['abertura sem resposta: antes das 3 h úteis, nada',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00' }, '2026-10-05 12:59', nil, nil],
    ['abertura sem resposta: lembrete 1 com 3 h úteis',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00' }, '2026-10-05 13:00', :lembrete_1, '2026-10-05 13:00'],
    ['abertura às 16h30: as 3 h úteis atravessam a noite (1h30 + 1h30)',
     { entrou_em: '2026-10-05 16:30', abertura_em: '2026-10-05 16:30' }, '2026-10-06 09:30', :lembrete_1, '2026-10-06 09:30'],
    ['lembrete 2 só na manhã do dia útil seguinte',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', lembrete_1_em: '2026-10-05 13:00' }, '2026-10-05 17:59', nil, nil],
    ['lembrete 2 na manhã do dia útil seguinte, às 8h',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', lembrete_1_em: '2026-10-05 13:00' },
     '2026-10-06 08:00', :lembrete_2, '2026-10-06 08:00'],
    ['lembrete 1 na sexta: lembrete 2 na segunda',
     { entrou_em: '2026-10-09 10:00', abertura_em: '2026-10-09 10:00', lembrete_1_em: '2026-10-09 13:00' },
     '2026-10-12 08:15', :lembrete_2, '2026-10-12 08:00'],
    ['silêncio 4 h úteis depois do lembrete 2',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', lembrete_1_em: '2026-10-05 13:00',
       lembrete_2_em: '2026-10-06 08:00' }, '2026-10-06 12:00', :silencio, '2026-10-06 12:00'],
    ['teto: depois do silêncio, nada mais até o cliente responder',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', lembrete_1_em: '2026-10-05 13:00',
       lembrete_2_em: '2026-10-06 08:00', silencio_em: '2026-10-06 12:00' }, '2026-10-16 10:00', nil, nil],
    ['respondeu: a resposta zera o silêncio (nenhum lembrete)',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultima_resposta_em: '2026-10-05 11:00' },
     '2026-10-05 13:00', nil, nil],
    ['respondeu, sem documento novo: acompanhamento com 1 dia útil',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultima_resposta_em: '2026-10-05 11:00' },
     '2026-10-06 10:00', :acompanhamento, '2026-10-06 10:00'],
    ['depois do acompanhamento: travado com 2 dias úteis',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultima_resposta_em: '2026-10-05 11:00',
       acompanhamento_em: '2026-10-06 10:00' }, '2026-10-07 10:00', :travado, '2026-10-07 10:00'],
    ['documento novo depois do acompanhamento recomeça a contagem (não trava)',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultima_resposta_em: '2026-10-05 11:00',
       acompanhamento_em: '2026-10-06 10:00', ultimo_documento_em: '2026-10-06 15:00' }, '2026-10-07 10:00', nil, nil],
    ['documento novo: novo acompanhamento 1 dia útil depois dele',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultima_resposta_em: '2026-10-05 11:00',
       acompanhamento_em: '2026-10-06 10:00', ultimo_documento_em: '2026-10-06 15:00' }, '2026-10-07 15:00', :acompanhamento,
     '2026-10-07 15:00'],
    ['travado e nenhum documento novo: nada mais',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultima_resposta_em: '2026-10-05 11:00',
       acompanhamento_em: '2026-10-06 10:00', travado_em: '2026-10-07 10:00' }, '2026-10-14 10:00', nil, nil],
    ['Review Focus 1: respondeu às 23h depois do lembrete 1: lembrete 2 não sai de manhã',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', lembrete_1_em: '2026-10-05 13:00',
       ultima_resposta_em: '2026-10-05 23:00' }, '2026-10-06 08:00', nil, nil],
    ['Review Focus 1: a contagem segue do lembrete 1, em horário comercial',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', lembrete_1_em: '2026-10-05 13:00',
       ultima_resposta_em: '2026-10-05 23:00' }, '2026-10-06 13:00', :acompanhamento, '2026-10-06 13:00'],
    ['vencido, mas fora do horário: espera (cobrança nunca sai à noite)',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00' }, '2026-10-05 21:00', nil, nil],
    ['cliente escreveu antes da abertura: a IA já respondeu, não há abertura',
     { entrou_em: '2026-10-09 19:00', ultima_resposta_em: '2026-10-10 09:00' }, '2026-10-12 08:00', nil, nil],
    ['Review Focus 2: documento pelo Painel do Cliente (sem mensagem) conta como resposta e como documento novo',
     { entrou_em: '2026-10-05 10:00', abertura_em: '2026-10-05 10:00', ultimo_documento_em: '2026-10-05 11:00' },
     '2026-10-06 11:00', :acompanhamento, '2026-10-06 11:00'],
    ['Review Focus 5 (limitação): o Horario dos fluxos não conhece feriado; Finados conta como dia útil',
     { entrou_em: '2026-10-30 10:00', abertura_em: '2026-10-30 10:00', lembrete_1_em: '2026-10-30 13:00' },
     '2026-11-02 08:00', :lembrete_2, '2026-11-02 08:00'],
    ['sem entrou_em (nunca entrou pela cobrança): nada',
     {}, '2026-10-05 10:00', nil, nil]
  ]

  casos.each do |caso, estado, agora, esperado, em|
    it caso do
      resultado = passo(agora, **estado)
      expect(resultado).to eq(esperado && { passo: esperado, em: sp(em) })
    end
  end

  it 'janela própria (9h–17h): abertura de quem entrou às 8h sai às 9h', :aggregate_failures do
    horario = { 'dias' => [1, 2, 3, 4, 5], 'inicio' => 9, 'fim' => 17 }
    expect(passo('2026-10-05 08:30', horario: horario, entrou_em: '2026-10-05 08:00')).to be_nil
    expect(passo('2026-10-05 09:00', horario: horario, entrou_em: '2026-10-05 08:00')).to eq(passo: :abertura, em: sp('2026-10-05 09:00'))
  end
end
