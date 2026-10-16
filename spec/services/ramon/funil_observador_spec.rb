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

  it 'o system prompt proíbe repetir cobrança listada e copiar checklist/exemplo em pendencias' do
    expect(described_class::SYSTEM_PROMPT).to include(
      'Não repita promessa que já está nas tarefas "Cobrar:" listadas.',
      '"pendencias" = só documentos que o cliente disse que vai mandar e ainda não mandou; não copie a checklist nem o exemplo.'
    )
    expect(described_class::SYSTEM_PROMPT).not_to include('"laudo", "CNIS"')
  end

  describe 'colheita na pausa' do
    before do
      lead
      mensagem('Oi')
      allow(Ramon::LlmClient).to receive(:complete).and_return(resultado('{"etapa":null}'))
    end

    it 'on: enfileira o job da colheita (retry próprio), sem FunilAcao nem atividade' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')

      expect { described_class.new(lead).perform }.to have_enqueued_job(Ramon::ColheitaExtractionJob).with(lead_id: lead.id).exactly(:once)
      expect(FunilAcao.count).to eq(0)
      expect(lead.lead_activities.where(kind: 'funil_auto')).to be_none
    end

    it 'roda também quando o LLM não devolve decisão' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')
      allow(Ramon::LlmClient).to receive(:complete).and_return(resultado('não sei'))

      expect { described_class.new(lead).perform }.to have_enqueued_job(Ramon::ColheitaExtractionJob)
    end

    %w[off ensaio].each do |modo|
      it "#{modo}: não enfileira e não registra" do
        Ramon::FunilAutomatico.mudar!(account, 'colheita', modo)

        expect { described_class.new(lead).perform }.not_to have_enqueued_job(Ramon::ColheitaExtractionJob)
        expect(FunilAcao.count).to eq(0)
      end
    end

    it 'lead que ficou perdido não é colhido' do
      Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')
      allow(aplicar).to receive(:perform) { lead.update_columns(lost_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.new(lead).perform }.not_to have_enqueued_job(Ramon::ColheitaExtractionJob)
    end
  end
end
