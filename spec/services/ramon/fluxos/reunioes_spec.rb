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

  describe 'a chave (RAMON_FLUXO_REUNIOES=on + os 3 fluxos em modo normal)' do
    let!(:fluxos) do
      described_class::GATILHOS.to_h do |chave, gatilho|
        [chave, fluxo_publicado(account, grafo_linear({ 'tipo' => gatilho }, ['parar', {}]), sistema_chave: chave, modo: 'sombra')]
      end
    end

    it 'só assume com a env ligada e os 3 normais, ligados, publicados e com o gatilho certo' do
      expect(described_class.assumiu?(account)).to be(false)
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        expect(described_class.assumiu?(account)).to be(false) # ainda em sombra
        described_class.mudar_modo!(account, 'normal')
        expect(described_class.assumiu?(account)).to be(true)
        fluxos['reuniao_cancelada'].update!(ativo: false)
        expect(described_class.assumiu?(account)).to be(false) # 1 desligado na tela devolve tudo ao código
      end
      fluxos['reuniao_cancelada'].update!(ativo: true)
      expect(described_class.assumiu?(account)).to be(false) # sem a env
    end

    it 'limite do dia num dos 3 devolve tudo ao código (o Disparo pularia o fluxo e ninguém faria)' do
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        fluxos['reuniao_cancelada'].update!(limite_dia: 5)
        expect(described_class.assumiu?(account)).to be(false)
      end
    end

    it 'virar para normal sem a env é recusado; voltar para sombra vira os 3 juntos' do
      expect { described_class.mudar_modo!(account, 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_REUNIOES/)
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        described_class.mudar_modo!(account, 'sombra')
      end
      expect(fluxos.values.map { |f| f.reload.modo }).to all(eq('sombra'))
      expect(described_class.descrever(account)).to include('o CÓDIGO faz o agendamento')
    end
  end
end
