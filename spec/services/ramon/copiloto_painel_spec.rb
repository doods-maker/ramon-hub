require 'rails_helper'

RSpec.describe Ramon::CopilotoPainel do
  let(:account) { create(:account) }
  let(:contato) do
    create(:contact, account: account, name: 'Maria Souza', email: 'maria@exemplo.com', phone_number: '+5548999998888',
                     custom_attributes: { cpf: '123.456.789-00' })
  end
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { travel_to Time.zone.parse('2026-10-07 15:00:00 UTC') }

  describe '.contexto' do
    it 'leva o caso, o nome do cliente e a data de hoje — sem telefone, e-mail, CPF nem o texto da conversa', :aggregate_failures do
      lead = create(:lead, account: account, conversation_id: conversa.id, name: 'Maria Souza')
      create(:message, conversation: conversa, account: account, inbox: conversa.inbox, content: 'Meu benefício foi negado')

      texto = described_class.contexto(account, conversa.display_id, admin)

      expect(texto).to include("caso #{lead.id} do hub (lead_id=#{lead.id})", 'cliente Maria Souza', "conversa ##{conversa.display_id}")
      expect(texto).to start_with('Contexto: hoje é 07/10/2026; a equipe')
      expect(texto).not_to include('99999')
      expect(texto).not_to include('maria@exemplo.com')
      expect(texto).not_to include('123.456.789', 'benefício foi negado')
    end

    it 'conversa sem caso usa o nome do contato' do
      expect(described_class.contexto(account, conversa.display_id, admin)).to include('sem caso no hub', 'cliente Maria Souza')
    end

    it 'agente fora da caixa da conversa não recebe cliente nem caso (só a data)', :aggregate_failures do
      create(:lead, account: account, conversation_id: conversa.id, name: 'Maria Souza')
      agente = create(:user, account: account, role: :agent)

      texto = described_class.contexto(account, conversa.display_id, agente)

      expect(texto).to eq('Contexto: hoje é 07/10/2026; nenhuma conversa aberta na tela.')
      create(:inbox_member, inbox: conversa.inbox, user: agente)
      expect(described_class.contexto(account, conversa.display_id, agente)).to include('cliente Maria Souza')
    end

    it 'sem conversa aberta diz isso (e a data)' do
      expect(described_class.contexto(account, nil, admin)).to eq('Contexto: hoje é 07/10/2026; nenhuma conversa aberta na tela.')
    end
  end

  it '.com_contexto põe o contexto só na última pergunta da pessoa', :aggregate_failures do
    historico = [{ role: 'user', content: 'primeira' }, { role: 'assistant', content: 'resposta' }, { role: 'user', content: 'segunda' }]

    novo = described_class.com_contexto(historico, account, nil, nil)

    expect(novo[0]).to eq(role: 'user', content: 'primeira')
    expect(novo[1]).to eq(role: 'assistant', content: 'resposta')
    expect(novo[2][:content]).to eq("Contexto: hoje é 07/10/2026; nenhuma conversa aberta na tela.\n\nsegunda")
    expect(historico[2][:content]).to eq('segunda')
  end
end
