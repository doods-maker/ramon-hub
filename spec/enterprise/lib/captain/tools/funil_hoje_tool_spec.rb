require 'rails_helper'

RSpec.describe Captain::Tools::FunilHojeTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:metrics) { instance_double(Ramon::CockpitMetrics) }
  let(:conversion) do
    [
      { stage_id: 1, name: 'Novo', entered: 10, advanced: 8, rate: 80 },
      { stage_id: 2, name: 'Qualificacao', entered: 8, advanced: 2, rate: 25 },
      { stage_id: 3, name: 'Reuniao', entered: 0, advanced: 0, rate: 0 }
    ]
  end
  let(:theses) do
    [
      { name: 'Auxilio-acidente', total: 5, prev_total: 3, reasons: [{ reason: 'sem_documentos', count: 3 }] },
      { name: 'BPC', total: 2, prev_total: 0, reasons: [] },
      { name: 'Rural', total: 1, prev_total: 1, reasons: [] },
      { name: 'Especial', total: 1, prev_total: 0, reasons: [] }
    ]
  end

  before do
    allow(Ramon::CockpitMetrics).to receive(:new).with(account).and_return(metrics)
    allow(metrics).to receive_messages(goal: { target: 12, done: 4 }, conversion: conversion,
                                       sla_today: { breached: 2, avg_first_response_minutes: 14.5 },
                                       losses_by_thesis: { window_days: 90, theses: theses })
  end

  describe '#perform' do
    it 'summarizes goal, conversion with the bottleneck, sla and top losses' do
      resultado = tool.perform(tool_context)

      expect(resultado).to include('Meta do dia: 4 de 12')
      expect(resultado).to include('- Qualificacao: 2/8 avancaram (25%) <- gargalo')
      expect(resultado).not_to include('Reuniao: 0/0 avancaram (0%) <- gargalo')
      expect(resultado).to include('SLA de 1a resposta hoje: 2 estouradas; media 14.5 min')
      expect(resultado).to include('Auxilio-acidente: 5 perdidos (antes: 3); motivo mais comum: sem_documentos (3)')
      expect(resultado).not_to include('Especial')
    end

    it 'handles an empty day' do
      allow(metrics).to receive_messages(conversion: [], sla_today: { breached: 0, avg_first_response_minutes: nil },
                                         losses_by_thesis: { window_days: 90, theses: [] })

      resultado = tool.perform(tool_context)

      expect(resultado).to include('sem dados de etapa')
      expect(resultado).to include('sem respostas ainda')
      expect(resultado).to include('Perdas por tese (90d): nenhuma.')
    end
  end
end
