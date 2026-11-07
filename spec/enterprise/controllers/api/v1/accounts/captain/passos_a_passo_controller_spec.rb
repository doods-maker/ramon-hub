require 'rails_helper'

# Tela de upload das imagens do passo a passo (Inteligência › Assistentes › assistente): uma por tema, só administrador.
RSpec.describe 'Api::V1::Accounts::Captain::PassosAPasso', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/passos_a_passo" }
  let(:png) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  def tema(nome) = response.parsed_body['temas'].find { |t| t['tema'] == nome }

  it 'agente não vê nem sobe imagem' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin sobe a imagem do tema (o nome vira o tema), troca sem duplicar e remove', :aggregate_failures do
    2.times { post url, headers: admin.create_new_auth_token, params: { tema: 'meu_inss_cnis', file: png } }
    expect(response).to have_http_status(:ok)
    expect(tema('meu_inss_cnis')).to include('nome' => 'meu_inss_cnis.png', 'url' => be_present)
    expect(assistant.reload.passos_a_passo.count).to eq(1)

    delete "#{url}/meu_inss_cnis", headers: admin.create_new_auth_token, as: :json
    expect(tema('meu_inss_cnis')).to include('url' => nil)
    expect(response.parsed_body['ligado']).to be(false)
  end

  it 'recusa tema fora da lista e arquivo que não é imagem', :aggregate_failures do
    post url, headers: admin.create_new_auth_token, params: { tema: 'xablau', file: png }
    expect(response).to have_http_status(:unprocessable_entity)

    pdf = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'application/pdf')
    post url, headers: admin.create_new_auth_token, params: { tema: 'meu_inss_cnis', file: pdf }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
