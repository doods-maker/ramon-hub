require 'rails_helper'

RSpec.describe Captain::Tools::HorariosLivresTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account) }
  let(:bia) { create(:user, account: account, name: 'Bia Closer') }
  let(:disponibilidade) { instance_double(Ramon::Agenda::Disponibilidade) }

  before do
    create(:team, account: account, name: 'closer').tap { |t| create(:team_member, team: t, user: bia) }
    allow(Ramon::Agenda::Disponibilidade).to receive(:new).and_return(disponibilidade)
  end

  describe '#perform' do
    it 'fixa o Closer e devolve os horarios livres' do
      livres = [Time.zone.parse('2027-03-10 17:00'), Time.zone.parse('2027-03-10 18:00'), Time.zone.parse('2027-03-11 12:00')]
      allow(disponibilidade).to receive(:livres).with(qtd: 3).and_return(livres)

      resposta = tool.perform(tool_context, lead_id: lead.id.to_s)

      expect(lead.reload.closer).to eq(bia)
      expect(resposta).to eq("Horarios livres com Bia Closer: #{Ramon::Agenda::Disponibilidade.texto(livres)}. " \
                             'Ofereca estes ao cliente e espere ele escolher.')
    end

    it 'manda passar para a equipe quando nao ha horario' do
      allow(disponibilidade).to receive(:livres).and_return([])

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to eq(described_class::SEM_HORARIO)
    end

    it 'manda passar para a equipe quando ninguem esta no time closer' do
      Team.where(account: account, name: 'closer').destroy_all

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to eq(described_class::SEM_HORARIO)
    end
  end
end
