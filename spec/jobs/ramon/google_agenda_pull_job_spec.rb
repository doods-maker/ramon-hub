require 'rails_helper'

RSpec.describe Ramon::GoogleAgendaPullJob do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Dr. Eduardo') }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores', closer_id: closer.id) }
  let(:inicio) { Time.zone.parse('2026-10-20T10:00:00-03:00') }
  let(:cliente) { instance_double(Ramon::GoogleAgenda::Cliente) }
  let(:conta) { GoogleAgendaConta.create!(user: closer, account: account, refresh_token: 'rt', access_token: 'at') }
  let!(:task) { create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: inicio, agenda_user: closer) }

  def evento(**attrs)
    { id: 'ev1', inicio: inicio, fim: inicio + 30.minutes, titulo: 'Conversa', cancelado: false, hub_task_id: task.id,
      atualizado_em: 1.minute.from_now }.merge(attrs)
  end

  def pull(*eventos)
    allow(cliente).to receive(:eventos).and_return(eventos)
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(conta).and_return(cliente)
    described_class.perform_now
  end

  before do
    conta
    allow(Ramon::ReuniaoAgendamento).to receive(:remarcar)
    allow(Ramon::ReuniaoAgendamento).to receive(:cancelar)
  end

  it 'evento movido no Google remarca a reunião sem empurrar de volta' do
    novo = inicio + 1.day
    pull(evento(inicio: novo))
    expect(Ramon::ReuniaoAgendamento).to have_received(:remarcar).with(task: task, starts_at: novo, sem_google: true).once
  end

  it 'Google mais velho que a tarefa (push do hub ainda a caminho) não desfaz a remarcação do hub' do
    pull(evento(inicio: inicio + 1.day, atualizado_em: task.updated_at - 1.minute))
    expect(Ramon::ReuniaoAgendamento).not_to have_received(:remarcar)
  end

  it 'evento igual ao hub (dentro de 60 s) não faz nada' do
    pull(evento(inicio: inicio + 30.seconds))
    expect(Ramon::ReuniaoAgendamento).not_to have_received(:remarcar)
    expect(Ramon::ReuniaoAgendamento).not_to have_received(:cancelar)
  end

  it 'evento cancelado no Google cancela a reunião sem empurrar de volta' do
    pull(evento(cancelado: true))
    expect(Ramon::ReuniaoAgendamento).to have_received(:cancelar).with(task: task, sem_google: true).once
  end

  it 'cancelamento: toca a tarefa antes, e o pull seguinte (tarefa ainda viva) não repete o gatilho' do
    travel_to(1.hour.from_now) do
      pull(evento(cancelado: true, atualizado_em: Time.current)) # o Google cancelou agora (> updated_at da tarefa)
      pull(evento(cancelado: true, atualizado_em: Time.current)) # a tarefa (mock não apaga) foi tocada: updated_at == agora
    end
    expect(Ramon::ReuniaoAgendamento).to have_received(:cancelar).once
  end

  it 'cancelado mínimo (só id, sem hub_task_id) acha a reunião pelo google_event_id' do
    task.update_columns(google_event_id: 'ev1') # rubocop:disable Rails/SkipsModelValidations
    pull({ id: 'ev1', inicio: nil, fim: nil, cancelado: true, hub_task_id: nil })
    expect(Ramon::ReuniaoAgendamento).to have_received(:cancelar).with(task: task, sem_google: true).once
  end

  it 'reunião que o hub já cancelou (tarefa sumiu) não faz nada' do
    pull(evento(cancelado: true, hub_task_id: task.id + 1000))
    expect(Ramon::ReuniaoAgendamento).not_to have_received(:cancelar)
  end

  it 'compromisso pessoal (sem reunião do hub) é ignorado' do
    pull(evento(id: 'pessoal', hub_task_id: nil, inicio: inicio + 2.days))
    expect(Ramon::ReuniaoAgendamento).not_to have_received(:remarcar)
  end

  it 'reunião de outro dono de agenda não é mexida' do
    task.update_columns(agenda_user_id: create(:user, account: account).id) # rubocop:disable Rails/SkipsModelValidations
    pull(evento(inicio: inicio + 1.day))
    expect(Ramon::ReuniaoAgendamento).not_to have_received(:remarcar)
  end

  it 'grava ultima_sincronizacao_em ao sincronizar' do
    pull
    expect(conta.reload.ultima_sincronizacao_em).to be_present
  end

  it 'conta com erro não impede a próxima e não marca a sincronização' do
    outro = create(:user, account: account, name: 'Outro')
    outra_conta = GoogleAgendaConta.create!(user: outro, account: account, refresh_token: 'rt2', access_token: 'at2')
    quebrado = instance_double(Ramon::GoogleAgenda::Cliente)
    allow(quebrado).to receive(:eventos).and_raise(Ramon::GoogleAgenda::Cliente::Erro.new(500))
    allow(cliente).to receive(:eventos).and_return([evento(cancelado: true)])
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(conta).and_return(cliente)
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new).with(outra_conta).and_return(quebrado)

    described_class.perform_now

    expect(Ramon::ReuniaoAgendamento).to have_received(:cancelar).once
    expect(outra_conta.reload.ultima_sincronizacao_em).to be_nil
  end

  it 'conta sem conexão é pulada em silêncio' do
    allow(cliente).to receive(:eventos).and_raise(Ramon::GoogleAgenda::Cliente::SemConexao)
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new).and_return(cliente)
    expect { described_class.perform_now }.not_to raise_error
    expect(conta.reload.ultima_sincronizacao_em).to be_nil
  end
end
