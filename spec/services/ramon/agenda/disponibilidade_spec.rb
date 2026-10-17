require 'rails_helper'

RSpec.describe Ramon::Agenda::Disponibilidade do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:lead) { create(:lead, account: account) }
  let(:zona) { 'America/Sao_Paulo' }
  # quinta, 22/10/2026, 9h em São Paulo
  let(:agora) { Time.zone.parse('2026-10-22T09:00:00-03:00') }
  let(:disp) { described_class.new(user: user, account: account, agora: agora) }

  def hora(iso)
    Time.zone.parse(iso)
  end

  def reuniao_as(iso)
    create(:lead_task, account: account, lead: lead, kind: 'meeting', agenda_user_id: user.id, due_at: hora(iso))
  end

  def conectar_google
    GoogleAgendaConta.create!(account: account, user: user, email: 'a@b.com', access_token: 'at', refresh_token: 'rt',
                              expira_em: 1.hour.from_now)
  end

  def stub_eventos(cliente, eventos)
    allow(cliente).to receive(:eventos).and_return(eventos)
  end

  describe '#livres' do
    it 'usa o horário gravado nos limites da conta (só a tarde, 14h–18h)', :aggregate_failures do
      Ramon::IaLimites.gravar!(account, { 'horario' => { 'dias' => [1, 2, 3, 4, 5], 'janelas' => [%w[14:00 18:00]] } })
      locais = described_class.new(user: user, account: account, agora: agora).livres.map { |t| t.in_time_zone(zona) }
      expect(locais).not_to be_empty
      expect(locais.map(&:hour).min).to be >= 14
    end

    it 'com agenda vazia devolve 3 horários, um por meio-período, o primeiro depois das 11h' do
      livres = disp.livres
      locais = livres.map { |t| t.in_time_zone(zona) }
      expect(locais.size).to eq(3)
      expect(locais.first.to_date).to eq(Date.new(2026, 10, 22))
      expect([locais.first.hour, locais.first.min]).to eq([11, 0])
      expect(locais.map { |t| [t.to_date, t.hour < 12] }.uniq.size).to eq(3)
    end

    it 'trata reunião do hub às 14h como ocupada (13h30–14h30 fora, 15h livre)' do
      task = reuniao_as('2026-10-22T14:00:00-03:00')
      %w[13:30 14:00 14:30].each { |h| expect(disp.livre?(hora("2026-10-22T#{h}:00-03:00"))).to be(false) }
      expect(disp.livre?(hora('2026-10-22T15:00:00-03:00'))).to be(true)
      expect(disp.livre?(hora('2026-10-22T14:30:00-03:00'), ignorar_task_id: task.id)).to be(true)
    end

    it 'trata evento do Google 15h–16h como ocupado (14h45–16h15)' do
      conta = conectar_google
      cliente = instance_double(Ramon::GoogleAgenda::Cliente)
      allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(conta).and_return(cliente)
      stub_eventos(cliente, [{ id: 'a', inicio: hora('2026-10-22T15:00:00-03:00'), fim: hora('2026-10-22T16:00:00-03:00'),
                               titulo: 'x', cancelado: false },
                             { id: 'b', inicio: nil, fim: nil, titulo: nil, cancelado: true }])
      expect(disp.livre?(hora('2026-10-22T14:30:00-03:00'))).to be(false)
      expect(disp.livre?(hora('2026-10-22T16:00:00-03:00'))).to be(false)
      expect(disp.livre?(hora('2026-10-22T16:30:00-03:00'))).to be(true)
    end

    it 'ignora evento do Google que é reunião do hub (hub_task_id): já entra pelo hub, sem contar em dobro nem colidir na remarcação' do
      conta = conectar_google
      cliente = instance_double(Ramon::GoogleAgenda::Cliente)
      allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(conta).and_return(cliente)
      stub_eventos(cliente, [{ id: 'hubtask1', inicio: hora('2026-10-22T15:00:00-03:00'), fim: hora('2026-10-22T15:30:00-03:00'),
                               cancelado: false, hub_task_id: 1 }])
      expect(disp.livre?(hora('2026-10-22T15:00:00-03:00'))).to be(true)
    end

    it 'ignora evento cancelado do Google' do
      conta = conectar_google
      cliente = instance_double(Ramon::GoogleAgenda::Cliente)
      allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(conta).and_return(cliente)
      stub_eventos(cliente, [{ id: 'a', inicio: hora('2026-10-22T15:00:00-03:00'), fim: hora('2026-10-22T16:00:00-03:00'),
                               cancelado: true }])
      expect(disp.livre?(hora('2026-10-22T15:00:00-03:00'))).to be(true)
    end

    it 'pula sábado, domingo e feriado' do
      # quarta 18/11: o próximo fim de semana e a sexta 20/11 (feriado) ficam de fora
      d = described_class.new(user: user, account: account, agora: hora('2026-11-18T08:00:00-03:00'))
      dias = d.livres(qtd: 20).map { |t| t.in_time_zone(zona).to_date }.uniq
      expect(dias).to include(Date.new(2026, 11, 19), Date.new(2026, 11, 23))
      expect(dias).not_to include(Date.new(2026, 11, 20), Date.new(2026, 11, 21), Date.new(2026, 11, 22))
    end

    it 'sem conexão com o Google usa só o hub, sem erro' do
      conta = conectar_google
      cliente = instance_double(Ramon::GoogleAgenda::Cliente)
      allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(conta).and_return(cliente)
      allow(cliente).to receive(:eventos).and_raise(Ramon::GoogleAgenda::Cliente::SemConexao)
      reuniao_as('2026-10-22T14:00:00-03:00')
      expect(disp.livre?(hora('2026-10-22T14:00:00-03:00'))).to be(false)
      expect(disp.livre?(hora('2026-10-22T15:00:00-03:00'))).to be(true)
    end
  end

  describe '#livre?' do
    it 'é falso dentro de um ocupado e verdadeiro fora' do
      reuniao_as('2026-10-22T14:00:00-03:00')
      expect(disp.livre?(hora('2026-10-22T14:00:00-03:00'))).to be(false)
      expect(disp.livre?(hora('2026-10-22T15:00:00-03:00'))).to be(true)
    end

    it 'é falso com menos de 2h de antecedência e fora das janelas' do
      expect(disp.livre?(hora('2026-10-22T10:30:00-03:00'))).to be(false)
      expect(disp.livre?(hora('2026-10-22T12:30:00-03:00'))).to be(false)
    end
  end

  describe '#colide?' do
    it 'sábado às 10h sem nada na agenda não colide (janela e dia útil são regras da oferta)' do
      expect(disp.colide?(hora('2026-10-24T10:00:00-03:00'))).to be(false)
    end

    it 'colide com reunião do hub e com a folga; ignora a própria reunião' do
      task = reuniao_as('2026-10-22T14:00:00-03:00')
      expect(disp.colide?(hora('2026-10-22T14:00:00-03:00'))).to be(true)
      expect(disp.colide?(hora('2026-10-22T14:30:00-03:00'))).to be(true) # folga de 15 min
      expect(disp.colide?(hora('2026-10-22T14:00:00-03:00'), ignorar_task_id: task.id)).to be(false)
    end
  end

  describe '.texto' do
    it 'junta horários do mesmo dia com "ou"' do
      txt = described_class.texto([hora('2026-10-22T14:00:00-03:00'), hora('2026-10-23T09:00:00-03:00'), hora('2026-10-23T10:30:00-03:00')])
      expect(txt).to eq('quinta, 22/10 às 14:00; sexta, 23/10 às 9:00 ou 10:30')
    end
  end
end
