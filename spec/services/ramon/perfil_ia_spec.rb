require 'rails_helper'

RSpec.describe Ramon::PerfilIa do
  let(:account) { create(:account) }
  # etapas do seed (Leads::SeedDefaultConfigService) — Novo … Última chance, Fechado, Perdido
  let(:etapa) { ->(label) { account.lead_stages.find_by(label: label) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:tese) { create(:thesis, account: account) }

  def gravar(alvos) = account.update!(settings: { 'ia_atendimento' => alvos })

  it 'sem nada gravado vale o INICIAL (igual a hoje)' do
    perfil = described_class.de(conversa)
    expect([perfil.origem, perfil.alvo, perfil.marcador]).to eq([:padrao, 'padrao', '_inicio'])
    expect(perfil.permissao('logistica')).to eq(:sozinha)
    expect(perfil.permissao('citar_honorario')).to eq(:rascunho)
  end

  it 'quem manda: tese (própria ou o padrão) → caixa só sem tese → padrão' do
    gravar('padrao' => { 'base' => 'cautelosa' }, 'caixas' => { inbox.id.to_s => { 'base' => 'acelerada' } },
           'teses' => { tese.id.to_s => { 'base' => 'equilibrada' } })
    lead = create(:lead, account: account, conversation: conversa)
    expect(described_class.de(conversa).base).to eq('acelerada')
    lead.update!(thesis: tese)
    expect(described_class.de(conversa).alvo).to eq("tese:#{tese.id}")
    account.update!(settings: account.settings.deep_merge('ia_atendimento' => { 'teses' => { tese.id.to_s => nil } }))
    expect(described_class.de(conversa.reload).alvo).to eq('padrao') # tese que segue o padrão não cai na caixa
  end

  it 'estado da Etapa pelo Marcador; Fechado = :fechado; Perdido e Pausa = :pausada' do
    gravar('padrao' => { 'base' => 'equilibrada' }) # marcador depois de Reunião agendada
    perfil = described_class.de(conversa)
    expect(perfil.estado(etapa['fase-reuniao-agendada'])).to eq(:sozinha)
    expect(perfil.estado(etapa['fase-reuniao-realizada'])).to eq(:rascunho)
    expect(perfil.estado(account.lead_stages.find_by(is_won: true))).to eq(:fechado)
    expect(perfil.estado(account.lead_stages.find_by(is_lost: true))).to eq(:pausada)
    expect(perfil.estado(nil)).to eq(:sozinha) # sem lead/etapa = 1ª etapa aberta
    conversa.update!(custom_attributes: { 'ia_pausa' => 'pausada' })
    expect(described_class.de(conversa).estado(etapa['fase-novo'])).to eq(:pausada)
  end

  it 'lixo gravado cai na base; marcador desconhecido = _inicio' do
    gravar('padrao' => { 'base' => 'xablau', 'marcador' => 'fase-apagada', 'permissoes' => { 'logistica' => 'x' } })
    perfil = described_class.de(conversa)
    expect(perfil.base).to eq('cautelosa')
    expect(perfil.estado(etapa['fase-novo'])).to eq(:rascunho)
    expect(perfil.permissao('logistica')).to eq(:rascunho) # o da Cautelosa
  end

  it 'etapa sem label tem a chave "id-<id>" e serve de Marcador' do
    account.lead_stages.where('position >= 2').each { |s| s.update!(position: s.position + 1) }
    nova = create(:lead_stage, account: account, position: 2) # depois de Qualificação, sem label
    gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => "id-#{nova.id}" })
    perfil = described_class.de(conversa)
    expect(described_class.chave_da_etapa(nova)).to eq("id-#{nova.id}")
    expect(perfil.estado(nova)).to eq(:sozinha)
    expect(perfil.estado(etapa['fase-reuniao-agendada'])).to eq(:rascunho)
  end

  it 'nunca tira as Tools da ação; direto? exige sozinha E Etapa antes do Marcador' do
    gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => '_fim', 'permissoes' => { 'marcar_reuniao' => 's' } })
    lead = create(:lead, account: account, conversation: conversa, lead_stage: etapa['fase-qualificacao'])
    perfil = described_class.de(lead)
    expect(perfil.tools_bloqueadas).to contain_exactly('simular_honorario', 'preparar_contrato_zapsign')
    expect(perfil.direto?('marcar_reuniao')).to be(true)
    expect(perfil.direto?('mover_etapa')).to be(false)
  end
end
