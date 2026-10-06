require 'rails_helper'

RSpec.describe Ramon::Fluxos::Reunioes do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService).
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, closer: closer, name: 'João Pereira')
  end

  describe 'regras únicas (código e fluxos)' do
    it 'reunião de pé: tarefa de reunião aberta no horário, com 60 s de folga' do
      inicio = 2.days.from_now.change(usec: 0)
      task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: inicio + 30.seconds)
      expect(described_class.reuniao_aberta?(lead, inicio)).to be(true)
      task.update!(completed_at: Time.current)
      expect(described_class.reuniao_aberta?(lead, inicio)).to be(false)
      expect(described_class.reuniao_aberta?(lead, nil)).to be(false)
    end

    it 'quem recebe o lembrete: Closer e SDR; sem nenhum dos dois, os administradores' do
      admin = create(:user, account: account, role: :administrator)
      expect(described_class.destinatarios(lead)).to eq([closer.id])
      lead.update!(closer: nil)
      expect(described_class.destinatarios(lead)).to eq([admin.id])
    end
  end

  describe 'rastro do que o código avisou' do
    after { Redis::Alfred.delete("ramon:reunioes:rastro:#{account.id}") }

    it 'grava e lê de volta dentro do intervalo, com o horário da gravação' do
      agora = Time.current.change(usec: 0)
      travel_to(agora) { described_class.rastro!(account, 'tipo' => 'lembrete', 'lead_id' => 7, 'user_ids' => [1, 2]) }

      lidos = described_class.rastros(account, agora - 1.minute, agora + 1.minute)

      expect(lidos).to eq([{ 'tipo' => 'lembrete', 'lead_id' => 7, 'user_ids' => [1, 2], 'em' => agora.to_f }])
      expect(described_class.rastros(account, agora + 1.minute, agora + 2.minutes)).to eq([])
    end

    it 'apara o que passou de 8 dias na próxima gravação' do
      agora = Time.current.change(usec: 0)
      travel_to(agora - 9.days) { described_class.rastro!(account, 'tipo' => 'velho') }
      travel_to(agora) { described_class.rastro!(account, 'tipo' => 'novo') }

      lidos = described_class.rastros(account, agora - 10.days, agora + 1.minute)

      expect(lidos.pluck('tipo')).to eq(['novo'])
    end
  end
end
