require 'rails_helper'

RSpec.describe Ramon::Hoje::Gestor do
  subject(:hoje) { described_class.new(account: account).perform }

  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }

  it 'sem nada acontecendo: precisa vazio, números zerados, sem meta' do
    expect(hoje[:precisa]).to eq([])
    expect(hoje[:mes]).to include(contratos: 0, meta_contratos: nil, reunioes_qualificadas: 0)
    expect(hoje[:time]).to include(recepcao: { atribuidas: 0, chegadas: 0 })
  end

  it 'peça em rascunho vira alerta de conteúdo com o gancho' do
    create(:peca, account: account, gancho: 'Quem tem direito')
    create(:peca, account: account, status: 'publicado')
    alerta = hoje[:precisa].find { |a| a[:tipo] == 'conteudo' }
    expect(alerta).to include(count: 1, nivel: 'act', nomes: ['Quem tem direito'])
  end

  it 'lead além do SLA vira alerta vermelho com o nome' do
    inbox = create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 5)
    conversa = create(:conversation, account: account, inbox: inbox, created_at: 10.minutes.ago)
    create(:lead, account: account, lead_stage: novo, conversation: conversa, name: 'Rosane')
    expect(hoje[:precisa].first).to include(tipo: 'sla', nivel: 'bad', count: 1, nomes: ['Rosane'])
  end

  it 'funil parado agrupa pela etapa com mais leads parados' do
    novo.update!(stalled_after_days: 4)
    lead = create(:lead, account: account, lead_stage: novo)
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(hoje[:precisa]).to include(include(tipo: 'parado', count: 1, etapa: 'Novo', dias: 4))
  end

  it 'meta do mês = soma das metas dos closers do mês' do
    closer = create(:user, account: account)
    MetaComercial.create!(account: account, user: closer, papel: 'closer', mes: Time.find_zone!('America/Sao_Paulo').today.beginning_of_month,
                          meta: 13)
    expect(hoje[:mes][:meta_contratos]).to eq(13)
  end

  it 'recepção: conta as conversas da caixa do escritório atribuídas hoje' do
    caixa = create(:inbox, account: account, portaria_enabled: true)
    hoje_em = { 'ramon_atribuicao' => { 'por_nome' => 'Gabriela', 'em' => Time.current.iso8601 } }
    create(:conversation, account: account, inbox: caixa, additional_attributes: hoje_em)
    create(:conversation, account: account, inbox: caixa, additional_attributes: { 'ramon_atribuicao' => { 'em' => 2.days.ago.iso8601 } })
    create(:conversation, account: account, additional_attributes: hoje_em) # fora da caixa
    create(:conversation, account: account, inbox: caixa)
    expect(hoje[:time][:recepcao]).to eq(atribuidas: 1, chegadas: 0)
  end

  it 'funil lista só etapas abertas, com contagem' do
    create(:lead, account: account, lead_stage: novo)
    expect(hoje[:funil]).to include(hash_including(etapa: 'Novo', count: 1))
    expect(hoje[:funil].pluck(:etapa)).not_to include(account.lead_stages.find_by(is_won: true).name)
  end
end
