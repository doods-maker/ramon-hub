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
end
