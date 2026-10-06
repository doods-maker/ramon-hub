require 'rails_helper'

RSpec.describe Ramon::Fluxos::Passos::Externo do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) do
    create(:lead, account: account, conversation: conversa, contact: conversa.contact,
                  custom_attributes: { 'advbox' => { 'lawsuits_id' => 77 } })
  end
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }), nome: 'Pós-contrato') }

  def ctx(alvo: lead, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
  end

  describe 'advbox' do
    it 'cria tarefa FIXA no processo do lead com os IDs escolhidos na tela' do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_return('posts_id' => 9)
      travel_to(Time.zone.parse('2026-10-06 13:00:00 UTC')) do
        described_class.advbox({ 'acao' => 'tarefa', 'tipo_tarefa_id' => 8_745_408, 'responsavel_id' => 266_778,
                                 'prazo_dias' => 2, 'descricao' => 'Conferir documentos' }, ctx)
      end
      expect(Ramon::AdvboxClient).to have_received(:create_post).with(
        hash_including(lawsuits_id: '77', tasks_id: '8745408', guests: [266_778], date_deadline: '2026-10-08', comments: 'Conferir documentos')
      )
    end

    it 'registra movimentação no processo do lead' do
      allow(Ramon::AdvboxClient).to receive(:create_movement)
      travel_to(Time.zone.parse('2026-10-06 13:00:00 UTC')) do
        described_class.advbox({ 'acao' => 'movimentacao', 'descricao' => 'Contrato assinado pelo cliente' }, ctx)
      end
      expect(Ramon::AdvboxClient).to have_received(:create_movement)
        .with(lawsuit_id: 77, description: 'Contrato assinado pelo cliente', date: '06/10/2026')
    end

    it 'lead sem processo no ADVBOX falha na hora (não adianta repetir)' do
      sem = create(:lead, account: account)
      expect { described_class.advbox({ 'acao' => 'movimentacao', 'descricao' => 'xxxxxxxxxxxx' }, ctx(alvo: sem)) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /processo no ADVBOX/)
    end

    it 'recusa do ADVBOX (4xx) também não se repete' do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_raise(Ramon::AdvboxClient::RequestError.new(422, { 'erro' => 'x' }))
      expect { described_class.advbox({ 'acao' => 'tarefa', 'tipo_tarefa_id' => 1, 'responsavel_id' => 2 }, ctx) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /HTTP 422/)
    end
  end

  describe 'configuração faltando não se repete' do
    it 'ação inválida e IDs faltando' do
      expect { described_class.advbox({ 'acao' => 'xyz' }, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /ação válida/)
      expect { described_class.advbox({ 'acao' => 'tarefa' }, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /incompleto/)
    end

    it 'token do ADVBOX ausente é impossível; outra indisponibilidade segue com nova tentativa' do
      allow(Ramon::AdvboxClient).to receive(:create_movement)
        .and_raise(Ramon::AdvboxClient::UnavailableError, 'AdvBox indisponível: ADVBOX_API_TOKEN não configurado')
      expect { described_class.advbox({ 'acao' => 'movimentacao', 'descricao' => 'x' }, ctx) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /não configurado/)
      allow(Ramon::AdvboxClient).to receive(:create_movement)
        .and_raise(Ramon::AdvboxClient::UnavailableError, 'AdvBox respondeu HTTP 503')
      expect { described_class.advbox({ 'acao' => 'movimentacao', 'descricao' => 'x' }, ctx) }
        .to raise_error(Ramon::AdvboxClient::UnavailableError)
    end

    it 'webhook: 4xx não repete (só o host na mensagem), 429 e 5xx repetem' do
      url = 'https://hooks.exemplo.com.br/x?token=segredo'
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError, '404 Not Found')
      expect { described_class.webhook({ 'url' => url }, ctx) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, 'webhook recusado por hooks.exemplo.com.br (HTTP 404)')
      %w[429\ Too\ Many 503\ Unavailable].each do |msg|
        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError, msg)
        expect { described_class.webhook({ 'url' => url }, ctx) }.to raise_error(SafeFetch::HttpError)
      end
    end
  end

  describe 'webhook' do
    let(:url) { 'https://hooks.exemplo.com.br/fluxo' }

    it 'POST JSON só com os dados do caso, timeout curto' do
      corpo = nil
      allow(SafeFetch).to receive(:fetch) { |_u, **opts| corpo = JSON.parse(opts[:body]) }
      described_class.webhook({ 'url' => url }, ctx)
      expect(SafeFetch).to have_received(:fetch).with(url, hash_including(method: :post, open_timeout: 2, read_timeout: 5))
      expect(corpo.keys).to match_array(%w[fluxo fluxo_id execucao_id alvo_tipo alvo_id lead_id enviado_em dados])
      expect(corpo).to include('fluxo' => 'Pós-contrato', 'lead_id' => lead.id)
      expect(corpo['dados']).to include('nome', 'telefone')
    end

    it 'dados só com campos liberados: CPF de campo livre nunca sai' do
      corpo = nil
      allow(SafeFetch).to receive(:fetch) { |_u, **opts| corpo = JSON.parse(opts[:body]) }
      lead.update!(custom_attributes: lead.custom_attributes.merge('campos' => { 'cpf' => '123' }))
      described_class.webhook({ 'url' => url }, ctx)
      expect(corpo['dados']).to include('nome', 'telefone')
      expect(corpo['dados']).not_to have_key('cpf')
    end

    it 'endereço de rede interna é recusado na hora' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::UnsafeUrlError, 'private network')
      expect { described_class.webhook({ 'url' => 'https://10.0.0.5/x' }, ctx) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /webhook recusado/)
    end
  end

  it 'ensaio não grava no ADVBOX nem chama o webhook' do
    allow(Ramon::AdvboxClient).to receive(:create_post)
    allow(SafeFetch).to receive(:fetch)
    c = ctx(ensaio: true)
    expect(described_class.advbox({ 'acao' => 'tarefa', 'tipo_tarefa_id' => 1, 'responsavel_id' => 2 }, c)[:resumo]).to start_with('faria: ')
    expect(described_class.webhook({ 'url' => 'https://hooks.exemplo.com.br/x?token=segredo' }, c)[:resumo])
      .to eq('faria: POST para hooks.exemplo.com.br') # na trilha só o host, nunca o token da URL
    expect(Ramon::AdvboxClient).not_to have_received(:create_post)
    expect(SafeFetch).not_to have_received(:fetch)
  end
end
