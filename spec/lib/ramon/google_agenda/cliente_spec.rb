require 'rails_helper'

RSpec.describe Ramon::GoogleAgenda::Cliente do
  let(:conta) { instance_double(GoogleAgendaConta) }
  let(:cliente) { described_class.new(conta) }
  let(:url) { 'https://www.googleapis.com/calendar/v3/calendars/primary/events' }
  let(:inicio) { Time.zone.parse('2026-10-20T10:00:00-03:00') }
  let(:fim) { inicio + 30.minutes }
  let(:cancelar_query) { { 'sendUpdates' => 'all' } }

  before { allow(Ramon::GoogleAgenda::Token).to receive(:valido).with(conta).and_return('tok') }

  def json(corpo, status = 200)
    { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  describe '#eventos' do
    it 'mapeia campos, hub_task_id e dia inteiro' do
      itens = [
        { id: 'a', status: 'confirmed', summary: 'Reunião', updated: '2026-10-16T12:00:00Z',
          start: { dateTime: '2026-10-20T10:00:00-03:00' }, end: { dateTime: '2026-10-20T10:30:00-03:00' },
          extendedProperties: { private: { hub_task_id: '42' } } },
        { id: 'b', status: 'cancelled', summary: 'Férias', updated: '2026-10-16T12:00:00Z',
          start: { date: '2026-10-21' }, end: { date: '2026-10-22' } },
        { id: 'c', status: 'cancelled' }
      ]
      stub_request(:get, url).with(query: hash_including('singleEvents' => 'true', 'orderBy' => 'startTime', 'showDeleted' => 'true'),
                                   headers: { 'Authorization' => 'Bearer tok' }).to_return(json(items: itens))
      a, b, c = cliente.eventos(de: inicio, ate: inicio + 1.day)
      expect(a).to include(id: 'a', titulo: 'Reunião', cancelado: false, hub_task_id: 42, inicio: inicio, fim: fim)
      expect(b).to include(cancelado: true, hub_task_id: nil, inicio: Time.zone.parse('2026-10-21T00:00:00-03:00'),
                           fim: Time.zone.parse('2026-10-22T00:00:00-03:00'))
      expect(c).to include(id: 'c', cancelado: true, inicio: nil, fim: nil, hub_task_id: nil)
    end
  end

  describe '#criar' do
    it 'com Meet manda conferenceData e devolve o hangoutLink' do
      stub = stub_request(:post, url).with(query: { 'conferenceDataVersion' => '1', 'sendUpdates' => 'all' }) do |req|
        corpo = JSON.parse(req.body)
        corpo.dig('conferenceData', 'createRequest', 'requestId') == 'hub-7' && corpo['attendees'] == [{ 'email' => 'c@x.com' }]
      end.to_return(json(id: 'ev1', hangoutLink: 'https://meet.google.com/abc'))
      r = cliente.criar(inicio: inicio, fim: fim, titulo: 'T', descricao: 'D', meet: true, convidado_email: 'c@x.com', hub_task_id: 7)
      expect(r).to eq(id: 'ev1', meet_url: 'https://meet.google.com/abc')
      expect(stub).to have_been_requested
    end

    it 'sem convidado usa sendUpdates=none e lê o Meet de entryPoints' do
      entradas = [{ entryPointType: 'phone', uri: 'tel:1' }, { entryPointType: 'video', uri: 'https://meet.google.com/x' }]
      stub_request(:post, url).with(query: { 'conferenceDataVersion' => '1', 'sendUpdates' => 'none' })
                              .to_return(json(id: 'ev2', conferenceData: { entryPoints: entradas }))
      r = cliente.criar(inicio: inicio, fim: fim, titulo: 'T', descricao: 'D', meet: true, hub_task_id: 8)
      expect(r[:meet_url]).to eq('https://meet.google.com/x')
    end
  end

  describe '#criar com id e #evento' do
    it 'manda o id escolhido no corpo' do
      stub = stub_request(:post, url).with(query: hash_including({}), body: hash_including('id' => 'hubtask7'))
                                     .to_return(json(id: 'hubtask7'))
      expect(cliente.criar(inicio: inicio, fim: fim, titulo: 'T', descricao: 'D', meet: false, hub_task_id: 7, id: 'hubtask7'))
        .to include(id: 'hubtask7')
      expect(stub).to have_been_requested
    end

    it 'busca um evento pelo id' do
      stub_request(:get, "#{url}/hubtask7").to_return(json(id: 'hubtask7', hangoutLink: 'https://meet.google.com/q'))
      expect(cliente.evento('hubtask7')).to eq(id: 'hubtask7', meet_url: 'https://meet.google.com/q')
    end
  end

  describe '#atualizar e #cancelar' do
    it 'atualiza com PATCH' do
      stub = stub_request(:patch, "#{url}/ev1").with(query: cancelar_query).to_return(json({}))
      expect(cliente.atualizar('ev1', inicio: inicio, fim: fim)).to be(true)
      expect(stub).to have_been_requested
    end

    it 'atualiza pedindo Meet novo e devolve o link' do
      stub = stub_request(:patch, "#{url}/ev1").with(query: cancelar_query.merge('conferenceDataVersion' => '1'),
                                                     body: hash_including('conferenceData' => hash_including('createRequest')))
                                               .to_return(json(hangoutLink: 'https://meet.google.com/abc'))
      expect(cliente.atualizar('ev1', inicio: inicio, fim: fim, meet: true)).to eq('https://meet.google.com/abc')
      expect(stub).to have_been_requested
    end

    it 'meet: false tira o Meet do evento (conferenceData nulo, versão 1)' do
      stub = stub_request(:patch, "#{url}/ev1").with(query: cancelar_query.merge('conferenceDataVersion' => '1')) do |req|
        corpo = JSON.parse(req.body)
        corpo.key?('conferenceData') && corpo['conferenceData'].nil?
      end.to_return(json({}))
      expect(cliente.atualizar('ev1', inicio: inicio, fim: fim, meet: false)).to be(true)
      expect(stub).to have_been_requested
    end

    it 'atualiza a descrição quando informada' do
      stub = stub_request(:patch, "#{url}/ev1").with(query: cancelar_query, body: hash_including('description' => 'Nova')).to_return(json({}))
      cliente.atualizar('ev1', inicio: inicio, fim: fim, descricao: 'Nova')
      expect(stub).to have_been_requested
    end

    it 'cancelar com 410 conta como sucesso' do
      stub_request(:delete, "#{url}/ev1").with(query: cancelar_query).to_return(status: 410)
      expect(cliente.cancelar('ev1')).to be(true)
    end
  end

  describe 'erros' do
    it '503 vira Transitorio' do
      stub_request(:delete, "#{url}/ev1").with(query: cancelar_query).to_return(status: 503)
      expect { cliente.cancelar('ev1') }.to raise_error(Ramon::GoogleAgenda::Token::Transitorio)
    end

    it 'token nil vira SemConexao' do
      allow(Ramon::GoogleAgenda::Token).to receive(:valido).with(conta).and_return(nil)
      expect { cliente.cancelar('ev1') }.to raise_error(described_class::SemConexao)
    end

    it '401 renova uma vez e repete; segundo 401 vira Erro' do
      allow(Ramon::GoogleAgenda::Token).to receive(:renovar).with(conta).and_return('novo')
      stub_request(:delete, "#{url}/ev1").with(query: cancelar_query).to_return({ status: 401 }, { status: 204 })
      expect(cliente.cancelar('ev1')).to be(true)
      stub_request(:delete, "#{url}/ev2").with(query: cancelar_query).to_return(status: 401)
      expect { cliente.cancelar('ev2') }.to raise_error(described_class::Erro)
      expect(Ramon::GoogleAgenda::Token).to have_received(:renovar).twice
    end

    it '400 vira Erro' do
      stub_request(:delete, "#{url}/ev1").with(query: cancelar_query).to_return(status: 400)
      expect { cliente.cancelar('ev1') }.to raise_error(described_class::Erro)
    end
  end
end
