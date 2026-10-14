require 'rails_helper'

RSpec.describe Ramon::Roteiro, '.reabrir' do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo, conversation: conversation) }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela', position: 1, titulo: 'Sequela', tipo_resposta: 'texto',
                           saidas: [{ 'id' => 'ficou', 'quando' => 'ficou', 'acao' => 'concluir' }])
  end

  # Fora do piloto total o Perdido do roteiro vira sugestão no Cockpit.
  def desqualificar!
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'acao')
  end

  it 'recusar o Perdido sugerido reabre no passo que decidiu' do
    desqualificar!.dismiss!

    atual = described_class.atual(lead.reload)
    expect(atual[:passo].chave).to eq('tem_advogado')
    expect(atual[:estado].keys).not_to include('desfecho', 'decisivo', 'aguarda_equipe')
    expect(lead.lead_activities.where(kind: 'roteiro').last.to_value).to eq('roteiro reaberto')
  end

  it 'aprovar marca Perdido e cala a IA; tirar do Perdido no Kanban reabre e devolve o modo de antes' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_limitado' })
    expect(desqualificar!.apply!).to be(true)
    expect(lead.reload.lost_reason).to eq('Sem viabilidade')
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('manual')
    expect(conversation.label_list).to include('desqualificado-ia')

    lead.update!(lead_stage: novo)

    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_limitado')
    expect(conversation.label_list).not_to include('desqualificado-ia')
    expect(described_class.atual(lead.reload)[:passo].chave).to eq('tem_advogado')
  end

  it 'Kanban e recusa só reabrem desqualificado; reabrir sem filtro volta no passo que decidiu' do
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    described_class.registrar(lead, chave: 'sequela', saida_id: 'ficou')
    expect(described_class.reabrir(lead.reload, se: 'desqualificado')).to be(false)

    lead.update!(lead_stage: account.lead_stages.find_by!(is_lost: true))
    lead.update!(lead_stage: novo)
    expect(described_class.atual(lead.reload)[:estado]['desfecho']).to eq('qualificado')

    expect(described_class.reabrir(lead)).to be(true)
    expect(described_class.atual(lead.reload)[:passo].chave).to eq('sequela')
  end

  it 'recusar sugestão que não é do roteiro não mexe no roteiro' do
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    outra = account.copilot_suggestions.create!(lead: lead, kind: 'acao', status: 'pending',
                                                payload: { 'acao' => 'perdido', 'texto' => 'sumiu' })
    outra.dismiss!
    expect(described_class.atual(lead.reload)[:estado]['desfecho']).to eq('desqualificado')
  end
end
