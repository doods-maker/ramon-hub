require 'rails_helper'

RSpec.describe Ramon::GoogleAgendaPushJob do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Dr. Eduardo') }
  let(:contact) { create(:contact, account: account, email: 'maria@example.com') }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores', closer_id: closer.id, contact: contact) }
  let(:inicio) { Time.zone.parse('2026-10-20T10:00:00-03:00') }
  let(:url) { 'https://www.googleapis.com/calendar/v3/calendars/primary/events' }
  let(:cliente) { instance_double(Ramon::GoogleAgenda::Cliente) }

  def reuniao(**attrs)
    create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: inicio, **attrs)
  end

  def conectar = GoogleAgendaConta.create!(user: closer, account: account, refresh_token: 'rt', access_token: 'at')

  before do
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new).and_return(cliente)
  end

  it 'sem conta Google conectada não chama o Google' do
    task = reuniao
    described_class.perform_now('criar', { 'task_id' => task.id })
    expect(Ramon::GoogleAgenda::Cliente).not_to have_received(:new)
  end

  describe 'criar' do
    before { conectar }

    it 'cria o evento com o texto aprovado, convida o cliente e grava o id e o Meet', :aggregate_failures do
      task = reuniao
      allow(cliente).to receive(:criar).and_return({ id: 'ev1', meet_url: 'https://meet.google.com/abc' })

      described_class.perform_now('criar', { 'task_id' => task.id })

      expect(cliente).to have_received(:criar).with(
        inicio: inicio, fim: inicio + 30.minutes, titulo: 'Conversa com Ramon Antonio Advogados', meet: true,
        convidado_email: 'maria@example.com', hub_task_id: task.id, id: "hubtask#{task.id}",
        descricao: a_string_starting_with('Olá, Maria! Esta é a nossa conversa sobre o seu caso, com Dr. Eduardo.')
                     .and(include('link do Google Meet'))
      )
      expect(task.reload).to have_attributes(google_event_id: 'ev1', meet_url: 'https://meet.google.com/abc')
    end

    it 'manda título e descrição no corpo da chamada ao Google (WebMock)' do
      allow(Ramon::GoogleAgenda::Cliente).to receive(:new).and_call_original
      allow(Ramon::GoogleAgenda::Token).to receive(:valido).and_return('tok')
      stub = stub_request(:post, url).with(
        query: hash_including({}),
        body: hash_including('summary' => 'Conversa com Ramon Antonio Advogados', 'attendees' => [{ 'email' => 'maria@example.com' }],
                             'description' => include('Maria', 'Dr. Eduardo'))
      ).to_return(status: 200, body: { id: 'ev9', hangoutLink: 'https://meet.google.com/x' }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
      task = reuniao

      described_class.perform_now('criar', { 'task_id' => task.id })

      expect(stub).to have_been_requested
      expect(task.reload.google_event_id).to eq('ev9')
    end

    it 'WhatsApp: sem Meet e com a ligação na descrição' do
      task = reuniao(formato: 'whatsapp')
      allow(cliente).to receive(:criar).and_return({ id: 'ev1', meet_url: nil })

      described_class.perform_now('criar', { 'task_id' => task.id })

      expect(cliente).to have_received(:criar).with(hash_including(meet: false, descricao: include('Ligação pelo WhatsApp')))
    end

    it 'contato sem e-mail não convida ninguém' do
      contact.update!(email: nil)
      task = reuniao
      allow(cliente).to receive(:criar).and_return({ id: 'ev1', meet_url: nil })

      described_class.perform_now('criar', { 'task_id' => task.id })

      expect(cliente).to have_received(:criar).with(hash_including(convidado_email: nil))
    end

    it 'tarefa que já tem evento não cria de novo' do
      task = reuniao
      task.update_columns(google_event_id: 'ja') # rubocop:disable Rails/SkipsModelValidations
      allow(cliente).to receive(:criar)

      described_class.perform_now('criar', { 'task_id' => task.id })

      expect(cliente).not_to have_received(:criar)
    end

    it 'tarefa que sumiu não faz nada' do
      allow(cliente).to receive(:criar)
      described_class.perform_now('criar', { 'task_id' => 0 })
      expect(cliente).not_to have_received(:criar)
    end

    it 'Google responde 409 (evento já existe): busca o evento e grava o id e o Meet' do
      task = reuniao
      allow(cliente).to receive(:criar).and_raise(Ramon::GoogleAgenda::Cliente::Erro.new(409))
      allow(cliente).to receive(:evento).with("hubtask#{task.id}").and_return({ id: "hubtask#{task.id}", meet_url: 'https://meet.google.com/z' })

      described_class.perform_now('criar', { 'task_id' => task.id })

      expect(task.reload).to have_attributes(google_event_id: "hubtask#{task.id}", meet_url: 'https://meet.google.com/z')
    end

    it 'Transitorio sobe para o retry_on' do
      task = reuniao
      allow(cliente).to receive(:criar).and_raise(Ramon::GoogleAgenda::Token::Transitorio)

      expect { described_class.perform_now('criar', { 'task_id' => task.id }) }.to have_enqueued_job(described_class)
    end

    it 'SemConexao sai em silêncio' do
      task = reuniao
      allow(cliente).to receive(:criar).and_raise(Ramon::GoogleAgenda::Cliente::SemConexao)
      expect { described_class.perform_now('criar', { 'task_id' => task.id }) }.not_to raise_error
    end

    it 'erro do Google não estoura e não grava nada' do
      task = reuniao
      allow(cliente).to receive(:criar).and_raise(Ramon::GoogleAgenda::Cliente::Erro.new(400))
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

      expect { described_class.perform_now('criar', { 'task_id' => task.id }) }.not_to raise_error
      expect(task.reload.google_event_id).to be_nil
    end
  end

  describe 'atualizar' do
    before { conectar }

    it 'move o evento para o horário novo' do
      task = reuniao
      task.update_columns(google_event_id: 'ev1', meet_url: 'https://meet.google.com/abc') # rubocop:disable Rails/SkipsModelValidations
      allow(cliente).to receive(:atualizar)

      described_class.perform_now('atualizar', { 'task_id' => task.id })

      expect(cliente).to have_received(:atualizar).with('ev1', inicio: inicio, fim: inicio + 30.minutes)
    end

    it 'sem evento no Google cria' do
      task = reuniao
      allow(cliente).to receive(:criar).and_return({ id: 'ev2', meet_url: nil })

      described_class.perform_now('atualizar', { 'task_id' => task.id })

      expect(task.reload.google_event_id).to eq('ev2')
    end

    it 'sem evento e com a reunião concluída não cria' do
      task = reuniao(completed_at: Time.current)
      allow(cliente).to receive(:criar)

      described_class.perform_now('atualizar', { 'task_id' => task.id })

      expect(cliente).not_to have_received(:criar)
    end

    it 'de vídeo para WhatsApp: descrição com a ligação e Meet limpo', :aggregate_failures do
      task = reuniao(formato: 'whatsapp')
      task.update_columns(google_event_id: 'ev1', meet_url: 'https://meet.google.com/abc') # rubocop:disable Rails/SkipsModelValidations
      allow(cliente).to receive(:atualizar)

      described_class.perform_now('atualizar', { 'task_id' => task.id })

      expect(cliente).to have_received(:atualizar).with('ev1', hash_including(descricao: include('Ligação pelo WhatsApp')))
      expect(task.reload.meet_url).to be_nil
    end

    it 'de WhatsApp para vídeo: pede Meet novo e grava o link' do
      task = reuniao(formato: 'video')
      task.update_columns(google_event_id: 'ev1', meet_url: nil) # rubocop:disable Rails/SkipsModelValidations
      allow(cliente).to receive(:atualizar).and_return('https://meet.google.com/novo')

      described_class.perform_now('atualizar', { 'task_id' => task.id })

      expect(cliente).to have_received(:atualizar).with('ev1', hash_including(meet: true))
      expect(task.reload.meet_url).to eq('https://meet.google.com/novo')
    end
  end

  describe 'cancelar' do
    it 'apaga o evento do Google do dono, mesmo com a tarefa já destruída' do
      conectar
      allow(cliente).to receive(:cancelar)

      described_class.perform_now('cancelar', { 'task_id' => 0, 'google_event_id' => 'ev1', 'agenda_user_id' => closer.id })

      expect(cliente).to have_received(:cancelar).with('ev1')
    end
  end
end
