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

  it 'reabrir grava em passo o passo decisivo (bi_roteiro)' do
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    expect(described_class.reabrir(lead.reload)).to be(true)

    expect(lead.reload.custom_attributes['roteiro']['passo']).to eq('tem_advogado')
  end

  it 'recusar sugestão que não é do roteiro não mexe no roteiro' do
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    outra = account.copilot_suggestions.create!(lead: lead, kind: 'acao', status: 'pending',
                                                payload: { 'acao' => 'perdido', 'texto' => 'sumiu' })
    outra.dismiss!
    expect(described_class.atual(lead.reload)[:estado]['desfecho']).to eq('desqualificado')
  end

  it 'recusar uma sugestão do roteiro já aplicada não reabre nada' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_limitado' })
    sugestao = desqualificar!
    sugestao.apply!
    sugestao.dismiss!

    expect(sugestao.reload.status).to eq('applied')
    expect(lead.reload.lost_at).to be_present
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('manual')
  end

  # rubocop:disable RSpec/DescribedClass -- constante explícita (regra da F5: reload no CI)
  # Revisão F5 3a: tirar do Perdido direto para "Reunião agendada" no "até reunião" não volta a enviar direto.
  it 'tirar do Perdido para além do limite devolve o modo e o limite já encerra' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_reuniao' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim') # modo direto: Perdido + IA calada
    expect(lead.reload.lost_at).to be_present

    lead.update!(lead_stage: account.lead_stages.find_by!(name: 'Reunião agendada'))

    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                             'copiloto_limite' => include('limite' => 'reuniao'))
  end

  # Revisão F5 3b: quem foi para a equipe saiu do robô (bot_handoff!); reabrir devolve ao robô no modo de antes.
  it 'reabrir quem foi para a equipe devolve a conversa ao robô no modo de antes' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_limitado' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', valor: 'nao sei') # nada casa → equipe
    expect(conversation.reload.status).to eq('open')

    expect(Ramon::Roteiro.reabrir(lead.reload)).to be(true)
    expect(conversation.reload.status).to eq('pending')
    expect(conversation.custom_attributes['copiloto_modo']).to eq('piloto_limitado')
  end

  # Review Focus 2: modo de antes manual = a equipe segue com a conversa.
  it 'reabrir quem foi para a equipe com modo de antes manual deixa a conversa com o humano' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', valor: 'nao sei')

    Ramon::Roteiro.reabrir(lead.reload)
    expect(conversation.reload.status).to eq('open')
    expect(conversation.custom_attributes['copiloto_modo']).to eq('manual')
  end

  # Revisão F5 3c: reabrir um qualificado desfaz o limite que ele causou.
  it 'reabrir um qualificado no "até qualificar" apaga o carimbo e volta o modo' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_qualificacao' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', saida_id: 'ficou')
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'qualificacao')

    Ramon::Roteiro.reabrir(lead.reload)
    expect(conversation.reload.custom_attributes).to eq('copiloto_modo' => 'piloto_ate_qualificacao')
  end

  # Revisão final F5, M1: o modo que um humano escolheu depois do limite (o seletor mantém o carimbo) vale.
  it 'reabrir um qualificado que um humano passou para manual depois do limite deixa manual' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_qualificacao' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', saida_id: 'ficou')
    conversation.update!(custom_attributes: conversation.reload.custom_attributes.merge('copiloto_modo' => 'manual'))

    Ramon::Roteiro.reabrir(lead.reload)
    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'manual',
                                                             'copiloto_limite' => include('limite' => 'qualificacao'))
  end
  # rubocop:enable RSpec/DescribedClass
end
