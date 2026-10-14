require 'rails_helper'

RSpec.describe Ramon::CopilotoLimite do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: etapa('Novo'), conversation: conversation) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  def etapa(nome) = account.lead_stages.find_by!(name: nome)
  def modo!(modo) = conversation.update!(custom_attributes: { 'copiloto_modo' => modo })
  def avisos = Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso')

  # Review Focus 4: sem handoff (a resposta do turno ainda sai) e aviso uma vez só.
  it 'até reunião: Reunião agendada volta a conversa para rascunho, carimba e avisa uma vez, sem handoff' do
    modo!('piloto_ate_reuniao')
    lead.update!(lead_stage: etapa('Qualificação'))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_reuniao')

    lead.update!(lead_stage: etapa('Reunião agendada'))
    expect(conversation.reload.custom_attributes).to include(
      'copiloto_modo' => 'rascunho', 'copiloto_limite' => include('limite' => 'reuniao', 'modo' => 'piloto_ate_reuniao')
    )
    expect(conversation.status).to eq('pending')

    lead.update!(lead_stage: etapa('Negociação'))
    expect(avisos.count).to eq(1)
  end

  # Review Focus 5.
  it 'Perdido não conta como reunião; ganho conta' do
    modo!('piloto_ate_reuniao')
    lead.update!(lead_stage: account.lead_stages.find_by!(is_lost: true))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_reuniao')

    ganho = account.lead_stages.find_by!(is_won: true)
    lead.update_columns(lead_stage_id: ganho.id, won_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- sem o fluxo "Lead ganho"
    expect(described_class.atingido?('reuniao', lead.reload)).to be(true)
  end

  it 'link do ZapSign no lead encerra o "até reunião" (contrato é nível acima)' do
    modo!('piloto_ate_reuniao')
    lead.update!(custom_attributes: { 'zapsign' => { 'sign_url' => 'https://zap/x' } })
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'reuniao')
  end

  it 'lead ganho encerra o "até contrato"' do
    modo!('piloto_ate_contrato')
    lead.update_columns(lead_stage_id: account.lead_stages.find_by!(is_won: true).id, won_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- sem o fluxo "Lead ganho"
    expect(described_class.verificar(lead.reload)).to eq('contrato')
    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho')
  end

  it 'lead já além do limite religado a uma conversa nova em modo "até…" encerra na hora' do
    lead.update!(lead_stage: etapa('Reunião agendada'))
    nova = create(:conversation, account: account, status: :pending,
                                 custom_attributes: { 'copiloto_modo' => 'piloto_ate_reuniao' })

    lead.update!(conversation: nova)

    expect(nova.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                     'copiloto_limite' => include('limite' => 'reuniao'))
  end

  it 'até qualificar: roteiro qualificado muda a etapa direto e depois encerra o modo' do
    modo!('piloto_ate_qualificacao')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela', titulo: 'Sequela',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'concluir', 'efeitos' => { 'etapa' => 'Qualificação' } }])

    Ramon::Roteiro.registrar(lead, chave: 'sequela', valor: 'sim')

    expect(lead.reload.lead_stage).to eq(etapa('Qualificação'))
    expect(account.copilot_suggestions.count).to eq(0)
    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                             'copiloto_limite' => include('limite' => 'qualificacao'))
    expect(avisos.count).to eq(1)
  end

  # Review Focus 5: desqualificado não é limite — segue o Perdido direto e a IA calada (F1).
  it 'até qualificar: desqualificado vai direto para Perdido com a IA calada, sem carimbo de limite' do
    modo!('piloto_ate_qualificacao')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'tem_advogado', titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' }])

    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim')

    expect(lead.reload.lead_stage).to eq(account.lead_stages.find_by!(is_lost: true))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('manual')
    expect(conversation.custom_attributes).not_to have_key('copiloto_limite')
  end

  it 'até qualificar numa tese sem roteiro: para na reunião' do
    modo!('piloto_ate_qualificacao')
    lead.update!(lead_stage: etapa('Reunião agendada'))
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'qualificacao')
  end

  it 'fora dos modos "sozinha até…" nada muda' do
    modo!('piloto_total')
    lead.update!(lead_stage: etapa('Reunião agendada'))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_total')
    expect(described_class.encerrar(lead, 'contrato', 'x')).to be_nil
    expect(avisos.count).to eq(0)
  end
end
