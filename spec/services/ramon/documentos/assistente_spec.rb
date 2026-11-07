require 'rails_helper'

# Assistente "Documentos" (rake ramon:documentos:assistente): instruções aprovadas pelo Eduardo em 07/11, num arquivo do
# repo. O CI roda sem enterprise/: lá só vale o carregamento do texto; criar o assistente roda onde o Captain existe.
RSpec.describe Ramon::Documentos::Assistente do
  it 'as instruções são o texto aprovado, sem a cerca do markdown', :aggregate_failures do
    texto = described_class.instrucoes
    expect(texto).to start_with('Você é da equipe do escritório Ramon Antonio Advogados, de Tubarão/SC.')
    expect(texto).to include('UMA mensagem por resposta', 'ferramenta enviar_passo_a_passo: UMA imagem por tema')
    expect(texto).to end_with("e passe para uma pessoa, que vai combinar o melhor horário.\n")
    expect(texto).not_to include('```')
  end

  # A descrição do Captain::Assistant vai até 255 caracteres (a rake caiu nisso em produção, 07/11): ela leva só o
  # 1º bloco do texto aprovado; os demais blocos viram as regras gerais (response_guidelines), como no assistente de vendas.
  it 'divide o texto aprovado: 1º bloco na descrição (até 255) e os demais nas regras gerais, sem perder nada', :aggregate_failures do
    expect(described_class.descricao).to start_with('Você é da equipe do escritório Ramon Antonio Advogados')
    expect(described_class.descricao.length).to be <= 255
    expect(described_class.diretrizes.first).to start_with('COMO FALAR')
    expect(described_class.diretrizes.last).to start_with('SENHA DO GOV.BR')
    expect([described_class.descricao, *described_class.diretrizes].join("\n\n")).to eq(described_class.instrucoes.strip)
  end

  context 'with o Captain', if: ChatwootApp.enterprise? do
    let(:account) { create(:account) }
    let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
    let(:da_caixa) do
      create(:captain_assistant, account: account,
                                 config: { 'temperature' => 0.4, 'product_name' => 'Banca', 'handoff_message' => 'Já chamei alguém' })
    end

    before do
      documentos
      create(:captain_inbox, captain_assistant: da_caixa, inbox: create(:inbox, account: account))
    end

    it 'cria o assistente com as instruções, a config técnica da caixa, as tools de Documentos e liga à etapa', :aggregate_failures do
      assistente = described_class.criar_ou_atualizar!(account)

      expect(assistente).to have_attributes(name: 'Documentos', description: described_class.descricao,
                                            response_guidelines: described_class.diretrizes)
      expect(assistente.config['instructions']).to eq(described_class.instrucoes)
      expect(assistente.config).to include('temperature' => 0.4, 'product_name' => 'Banca', 'handoff_message' => 'Já chamei alguém')
      expect(assistente.scenarios.enabled.flat_map(&:tools)).to match_array(described_class::TOOLS)
      expect(documentos.reload.captain_assistant).to eq(assistente)
    end

    it 'rodar de novo atualiza o mesmo assistente e a mesma skill, sem duplicar', :aggregate_failures do
      2.times { described_class.criar_ou_atualizar!(account) }

      expect(account.captain_assistants.where(name: 'Documentos').count).to eq(1)
      expect(account.captain_assistants.find_by(name: 'Documentos').scenarios.count).to eq(1)
    end

    it 'não liga a chave da etapa' do
      described_class.criar_ou_atualizar!(account)
      expect(Ramon::EtapaDeGanho.documentos_ligado?).to be(false)
    end
  end
end
