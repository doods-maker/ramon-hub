require 'rails_helper'

RSpec.describe 'Ramon IA da conversa API', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_ia_conversas/#{conversa.display_id}" }

  def ler(usuario = agente) = get(url, headers: usuario.create_new_auth_token, as: :json)

  it 'agente sem acesso à caixa não vê' do
    ler
    expect(response).to have_http_status(:unauthorized)
  end

  context 'with acesso à caixa' do
    before { create(:inbox_member, inbox: inbox, user: agente) }

    it 'sem tese nem perfil da caixa: padrão do escritório', :aggregate_failures do
      ler
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('origem' => 'padrao', 'alvo' => 'padrao', 'pausa' => nil)
    end

    it 'perfil salvo para a caixa, e a pausa da conversa' do
      cfg = { 'base' => 'equilibrada', 'marcador' => 'fase-reuniao-agendada' }
      account.update!(settings: { 'ia_atendimento' => { 'caixas' => { inbox.id.to_s => cfg } } })
      conversa.update!(custom_attributes: { 'ia_pausa' => 'rascunho' })
      ler
      expect(response.parsed_body).to include('perfil' => 'Equilibrada', 'origem' => 'caixa', 'alvo' => "caixa:#{inbox.id}", 'pausa' => 'rascunho')
    end

    it 'perfil da tese do lead, com a etapa' do
      tese = create(:thesis, account: account)
      etapa = account.lead_stages.first
      create(:lead, account: account, conversation: conversa, thesis: tese, lead_stage: etapa)
      account.update!(settings: { 'ia_atendimento' => { 'teses' => { tese.id.to_s => { 'base' => 'acelerada' } } } })
      ler
      expect(response.parsed_body).to include('perfil' => 'Acelerada', 'origem' => 'tese', 'alvo' => "tese:#{tese.id}", 'etapa' => etapa.name)
    end
  end
end
