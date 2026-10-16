require 'rails_helper'

RSpec.describe Ramon::FunilObservador do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'), conversation: conversa, name: 'Maria da Silva')
  end
  let(:aplicar) { instance_double(Ramon::FunilObservador::Aplicar, perform: nil) }

  def resultado(content) = Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)

  def mensagem(content, private: false)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: private ? :outgoing : :incoming,
                     content: content, private: private)
  end

  before { allow(Ramon::FunilObservador::Aplicar).to receive(:new).and_return(aplicar) }

  it 'sem conversa devolve nil e não chama o LLM' do
    lead_sem = create(:lead, account: account)
    allow(Ramon::LlmClient).to receive(:complete)

    expect(described_class.new(lead_sem).perform).to be_nil
    expect(Ramon::LlmClient).not_to have_received(:complete)
  end

  it 'conversa só com nota privada não chama o LLM' do
    mensagem('nota', private: true)
    allow(Ramon::LlmClient).to receive(:complete)

    expect(described_class.new(lead).perform).to be_nil
    expect(Ramon::LlmClient).not_to have_received(:complete)
  end

  it 'aceita JSON com cercas e entrega o Hash ao Aplicar' do
    mensagem('Respondi as perguntas')
    allow(Ramon::LlmClient).to receive(:complete).and_return(resultado("```json\n{\"etapa\":\"qualificacao\",\"etapa_motivo\":\"ok\"}\n```"))

    decisao = described_class.new(lead).perform

    expect(decisao).to eq('etapa' => 'qualificacao', 'etapa_motivo' => 'ok')
    expect(Ramon::FunilObservador::Aplicar).to have_received(:new).with(lead, decisao)
    expect(aplicar).to have_received(:perform)
  end

  it 'conteúdo que não é JSON devolve nil sem exceção e sem aplicar' do
    mensagem('Oi')
    allow(Ramon::LlmClient).to receive(:complete).and_return(resultado('não sei'))

    expect(described_class.new(lead).perform).to be_nil
    expect(Ramon::FunilObservador::Aplicar).not_to have_received(:new)
  end

  it 'TransientError sobe para o job tentar de novo' do
    mensagem('Oi')
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')

    expect { described_class.new(lead).perform }.to raise_error(Ramon::LlmClient::TransientError)
  end

  it 'envia o prompt mascarado, com ficha, motivos de perda e tarefas Cobrar:' do
    mensagem('Meu CPF é 123.456.789-09, sou a Maria')
    tarefa = create(:lead_task, account: account, lead: lead, title: 'Cobrar: laudo', due_at: 1.day.from_now)
    enviado = nil
    allow(Ramon::LlmClient).to receive(:complete) do |**args|
      enviado = args
      resultado('{"etapa":null}')
    end

    described_class.new(lead).perform

    expect(enviado[:user]).not_to include('123.456.789-09')
    expect(enviado[:user]).to include('[cpf]', 'Etapa atual: Novo', 'Sumiu / não respondeu', "#{tarefa.id} — Cobrar: laudo")
    expect(enviado).to include(funcao: 'funil_observador', account_id: account.id, lead_id: lead.id)
  end

  it 'manda hoje, a hora de cada mensagem e o que a equipe desfez (30 dias), com a regra no system prompt' do
    travel_to Time.zone.parse('2026-10-16 14:30:00 -03:00') do
      mensagem('Não quero mais')
      FunilAcao.create!(account: account, lead: lead, peca: 'perdido_recusa', acao: 'perdido', alvo: 'Honorário', ensaio: false,
                        desfeita_em: Time.zone.parse('2026-10-15 09:05:00 -03:00'))
      FunilAcao.create!(account: account, lead: lead, peca: 'etapa_ia', acao: 'mover_etapa', alvo: 'Qualificação', ensaio: false,
                        desfeita_em: 40.days.ago)
      enviado = nil
      allow(Ramon::LlmClient).to receive(:complete) do |**args|
        enviado = args
        resultado('{"etapa":null}')
      end

      described_class.new(lead).perform

      expect(enviado[:user]).to include('Hoje: sexta 16/10/2026 14:30', '[16/10 14:30] Cliente: Não quero mais',
                                        "A equipe desfez 'perdido: Honorário' em 15/10 09:05; só repita se houver fato novo")
      expect(enviado[:user]).not_to include("desfez 'mover_etapa")
      expect(enviado[:system]).to include('decida só por fatos do cliente posteriores a esse desfazer')
    end
  end

  describe 'colheita na pausa' do
    let(:servico) { instance_double(Ramon::ColheitaExtractionService, perform: nil, extractable?: true) }

    before do
      mensagem('Oi')
      allow(Ramon::LlmClient).to receive(:complete).and_return(resultado('{"etapa":null}'))
      allow(Ramon::ColheitaExtractionService).to receive(:new).with(lead).and_return(servico)
    end

    it 'on: roda o serviço uma vez, fora de transação, e registra a ação' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')
      fora = ActiveRecord::Base.connection.open_transactions
      durante = nil
      allow(servico).to receive(:perform) { durante = ActiveRecord::Base.connection.open_transactions }

      described_class.new(lead).perform

      expect(servico).to have_received(:perform).once
      expect(durante).to eq(fora)
      expect(FunilAcao.where(lead: lead, peca: 'colheita', acao: 'colher', ensaio: false).count).to eq(1)
    end

    it 'roda também quando o LLM não devolve decisão' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')
      allow(Ramon::LlmClient).to receive(:complete).and_return(resultado('não sei'))

      described_class.new(lead).perform

      expect(servico).to have_received(:perform).once
    end

    it 'off: não roda e não registra' do
      described_class.new(lead).perform

      expect(servico).not_to have_received(:perform)
      expect(FunilAcao.where(peca: 'colheita')).to be_empty
    end

    it 'ensaio: não roda, só registra a ação de ensaio' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'ensaio')

      described_class.new(lead).perform

      expect(servico).not_to have_received(:perform)
      expect(FunilAcao.where(lead: lead, peca: 'colheita', ensaio: true).count).to eq(1)
    end

    %w[on ensaio].each do |modo|
      it "#{modo}: tese sem colheita não chama o serviço nem registra ação" do
        Ramon::FunilAutomatico.mudar!(account, 'colheita', modo)
        allow(servico).to receive(:extractable?).and_return(false)

        described_class.new(lead).perform

        expect(servico).not_to have_received(:perform)
        expect(FunilAcao.where(peca: 'colheita')).to be_empty
      end
    end

    it 'lead que ficou perdido não é colhido' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')
      allow(aplicar).to receive(:perform) { lead.update_columns(lost_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

      described_class.new(lead).perform

      expect(servico).not_to have_received(:perform)
    end
  end
end
